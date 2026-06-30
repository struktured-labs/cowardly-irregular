extends Node
class_name Combatant

## Base class for all battle participants (player characters and enemies)
## Manages stats, AP, status effects, and turn mechanics

signal hp_changed(old_value: int, new_value: int)
signal ap_changed(old_value: int, new_value: int)
signal died()
signal status_added(status: String)
signal status_removed(status: String)
## tick 55: emit once per level threshold crossed in gain_exp. The
## rebalance daemon listens (via BattleManager → GameLoop) and uses
## it as a passive progression signal — distinct from wipe/defeat.
signal leveled_up(new_level: int)
## tick 58: emitted when JobSystem.learn_abilities_for_level grants
## a new ability via a level threshold. UI uses this for the "X
## learned Y!" Toast.
signal ability_learned(ability_id: String)
## tick 143: emitted on poison/burn/regen ticks. BattleScene listens
## to spawn floating damage/healing popups. Pre-fix the HP bar
## dropped but no number floated up — players couldn't see status
## effects ticking unless they watched the HP bar carefully. The
## `source` field distinguishes which status caused the tick so
## the popup can color/style differently if desired.
signal status_tick_damage(amount: int, source: String)
signal status_tick_heal(amount: int, source: String)

## Core stats
@export var combatant_name: String = "Unknown"
@export var max_hp: int = 100
@export var max_mp: int = 50
@export var attack: int = 10
@export var defense: int = 10
@export var magic: int = 10
@export var speed: int = 10

## Current state
var current_hp: int
var current_mp: int
var current_ap: int = 0  # Action Points: -4 to +4 range
var is_defending: bool = false
var is_alive: bool = true

## Status effects and buffs
var status_effects: Array[String] = []
var status_durations: Dictionary = {}  # status_name -> turns remaining (-1 = permanent)
var permanent_injuries: Array[Dictionary] = []
var active_buffs: Array[Dictionary] = []  # {effect: String, stat: String, modifier: float, duration: int}
var active_debuffs: Array[Dictionary] = []

## Elemental affinities
var elemental_weaknesses: Array[String] = []  # Takes 1.5x damage from these
var elemental_resistances: Array[String] = []  # Takes 0.5x damage from these
var elemental_immunities: Array[String] = []   # Takes 0x damage from these

## Job reference and progression
var job = null
var job_level: int = 1
var job_exp: int = 0

## Secondary job (accents primary job visuals and provides minor stat bonuses)
var secondary_job = null
var secondary_job_id: String = ""

## Character customization (appearance data)
var customization = null  # CharacterCustomization reference

## Passive system
var equipped_passives: Array[String] = []  # Passive IDs
var max_passive_slots: int = 5
var learned_passives: Array[String] = []  # All unlocked passives

## Learned abilities (purchased from magic shops, persist across job changes)
var learned_abilities: Array[String] = []

## Equipment system
var equipped_weapon: String = ""  # Weapon ID
var equipped_armor: String = ""   # Armor ID
var equipped_accessory: String = ""  # Accessory ID

## Spotlight gate: when true, this PC's turn is forced through autobattle
## eval (stock per-job script) and their manual command menu + autobattle
## editor tab are hidden. Flips to false when their spotlight cutscene
## fires (see _CUTSCENE_COMPLETION_FLAGS in GameLoop). The debug flag
## GameState.debug_all_pcs_unlocked overrides this for all PCs at once.
var autobattle_locked: bool = false

## Job profiles - saves equipment, passives, and autobattle per job combo
## Key format: "primary_job_id:secondary_job_id" (e.g. "fighter:", "fighter:rogue")
var job_profiles: Dictionary = {}

## Inventory system
var inventory: Dictionary = {}  # {item_id: quantity}

## Base stats (before modifiers)
var base_max_hp: int = 100
var base_max_mp: int = 50
var base_attack: int = 10
var base_defense: int = 10
var base_magic: int = 10
var base_speed: int = 10

## Turn state
var queued_actions: Array[Dictionary] = []
var turn_order_value: float = 0.0
var doom_counter: int = -1  # Death Sentence countdown (-1 = not doomed)

## Command memory - remembers last menu selections
var last_menu_selection: String = ""  # Top-level: "attack_menu", "ability_menu", "item_menu", etc.
var last_attack_selection: String = ""  # Attack target if Attack was chosen (e.g., "attack_0")
var last_ability_selection: String = ""  # Ability submenu ID if Abilities was chosen
var last_item_selection: String = ""  # Item submenu ID if Items was chosen

## MRU ability slots — most-recently-used abilities (for top-level quick access).
## Persists across battles in-session. Pinned abilities take priority over MRU
## entries; pins are stored separately. Most-recent-first ordering.
var recent_abilities: Array[String] = []
var pinned_abilities: Array[String] = []  # Player-pinned, takes priority over MRU
const MRU_SIZE: int = 2  # Top menu shows 2 quick-access ability slots


func _ready() -> void:
	current_hp = max_hp
	current_mp = max_mp


## Initialize combatant with specific values
func initialize(stats: Dictionary) -> void:
	if stats.has("name"):
		combatant_name = stats["name"]
	if stats.has("max_hp"):
		max_hp = stats["max_hp"]
		current_hp = max_hp
	if stats.has("max_mp"):
		max_mp = stats["max_mp"]
		current_mp = max_mp
	if stats.has("attack"):
		attack = stats["attack"]
	if stats.has("defense"):
		defense = stats["defense"]
	if stats.has("magic"):
		magic = stats["magic"]
	if stats.has("speed"):
		speed = stats["speed"]


## Brave/Default system
func can_brave(ap_cost: int) -> bool:
	# Can go into AP debt up to -4
	return (current_ap - ap_cost) >= -4


func spend_ap(amount: int) -> bool:
	## Tick 369: refuse negative amounts. Pre-fix spend_ap(-3) silently
	## GRANTED 3 AP and returned true as if the cost was paid —
	## can_brave(-3) reads `(current_ap - (-3)) >= -4` which is always
	## true for any valid current_ap, then the clampi(current_ap - (-3),
	## -4, 4) added 3 AP. Callers (group attacks, autobattle queues,
	## Scriptweaver mods) treating the bool return as "AP cost paid"
	## would accidentally let a single character act for free AND gain
	## AP back. No current production caller passes negatives, but the
	## footgun is preserved for symmetry with tick 368's heal/restore_mp
	## guard. Use gain_ap for legitimate AP gain.
	if amount < 0:
		push_warning("[Combatant] spend_ap() called with negative amount %d on %s — refused, returning false (use gain_ap for AP gain)" % [amount, combatant_name])
		return false
	if not can_brave(amount):
		return false

	# Tick 286: guard ap_changed.emit on actual change. spend_ap(0)
	# was a spurious emit; gain_ap(1) at cap was the worse case.
	# UI listeners shouldn't see "ap changed" for a no-op tick.
	var old_ap = current_ap
	current_ap = clampi(current_ap - amount, -4, 4)
	if current_ap != old_ap:
		ap_changed.emit(old_ap, current_ap)
	return true


func gain_ap(amount: int) -> void:
	## Tick 369: refuse negative amounts. Pre-fix gain_ap(-2) silently
	## DRAINED 2 AP (clampi(current_ap + -2, -4, 4)) — a silent
	## bypass of spend_ap's debt-check gate. Symmetric defensive
	## guard with spend_ap above; use spend_ap for legitimate AP cost.
	if amount < 0:
		push_warning("[Combatant] gain_ap() called with negative amount %d on %s — refused (use spend_ap for AP cost)" % [amount, combatant_name])
		return
	# Tick 286: clamp at +4 means gain_ap(1) when current_ap == 4
	# was a no-op that still emitted ap_changed — UI listeners
	# repainted needlessly each turn after reaching cap. Guard on
	# actual change.
	var old_ap = current_ap
	current_ap = clampi(current_ap + amount, -4, 4)
	if current_ap != old_ap:
		ap_changed.emit(old_ap, current_ap)


func execute_defer() -> void:
	"""Defer action: skip turn, reduce incoming damage (no AP cost, keeps natural gain)"""
	is_defending = true
	# Note: Defer doesn't give AP directly - it just doesn't cost the 1 AP that actions cost
	# The natural +1 AP per turn is what accumulates when deferring


func execute_advance(actions: Array[Dictionary]) -> void:
	"""Advance action: queue multiple actions, spending AP"""
	var ap_cost = actions.size() - 1  # First action is free
	if spend_ap(ap_cost):
		queued_actions = actions.duplicate()


## Combat actions
func take_damage(amount: int, is_magical: bool = false) -> int:
	"""Apply damage considering defense/magic defense and defending state"""
	if not is_alive:
		return 0
	# Use attack^2 / (attack + defense) formula for smoother scaling
	# Defense reduces damage but never makes it negligible.
	# Bug fix (2026-04-30): clamp `amount` to non-negative and guard the
	# divisor so amount=0 + def_value=0 (possible with 0-power debuff
	# pings or a ProtectAll buff stripping all attack) doesn't divide by
	# zero. The max(1, ...) below would still return 1, but the divide
	# itself emits a Godot error and produces NaN.
	amount = max(0, amount)

	## Tick 442: shared_damage passive — passives.json authors
	## meta_effects.boss_damage_share = 0.5 with description "When
	## controlling a boss, damage is split 50/50 between you and
	## the boss". Pre-fix the meta_effect was decoration only.
	## boss_control_swap (Bossbinder Mind Swap) sets a
	## _mind_swap_controller meta on the target when it adds the
	## mind_swap status; if that controller has shared_damage
	## equipped, redirect that share of the incoming damage to
	## them before the boss's defense reduction. Reentrancy:
	## controller can't ALSO be mid-redirect (their own mind_swap
	## status gates it), and the per-call _in_shared_damage_redirect
	## flag prevents A→B→A infinite recursion if both ever carry
	## the swap.
	if amount > 0 and has_status("mind_swap") and has_meta("_mind_swap_controller") \
			and not (has_meta("_in_shared_damage_redirect") and get_meta("_in_shared_damage_redirect")):
		var ctrl_v: Variant = get_meta("_mind_swap_controller")
		if ctrl_v is Combatant and (ctrl_v as Combatant).is_alive:
			var ctrl: Combatant = ctrl_v as Combatant
			var share: float = ctrl._get_passive_meta_effect_sum("boss_damage_share")
			if share > 0.0:
				var redirect_amount: int = int(round(amount * clampf(share, 0.0, 1.0)))
				if redirect_amount > 0:
					set_meta("_in_shared_damage_redirect", true)
					ctrl.take_damage(redirect_amount, is_magical)
					set_meta("_in_shared_damage_redirect", false)
					amount = max(0, amount - redirect_amount)
					print("[SHARED_DAMAGE] %d redirected to controller %s" % [redirect_amount, ctrl.combatant_name])

	var def_value = get_buffed_stat("defense", defense) if not is_magical else int(get_buffed_stat("defense", defense) * 0.5)
	var denom = max(1, amount + def_value)
	var actual_damage = int((amount * amount) / float(denom))
	actual_damage = max(1, actual_damage)  # Always at least 1 damage

	# Defending reduces damage by 50%
	if is_defending:
		actual_damage = int(actual_damage * 0.5)

	# Exposed status (from group attacks) increases damage taken by 50%
	if has_status("exposed"):
		actual_damage = int(actual_damage * 1.5)

	# Tick 114: apply the global damage_multiplier from game_constants.
	# Scriptweaver writes this knob to nudge incoming damage globally
	# (player + enemy alike). Pre-fix the constant was set in defaults
	# but no code path read it, so Scriptweaver edits were cosmetic.
	# Defensive pattern matches the tick 109/110/113 multipliers:
	# .get(key, 1.0) + clampf [0.1, 10.0]. Runtime lookup keeps this
	# function preload-safe for unit tests (GameState autoload may
	# not be present in pure-class tests).
	var gs_node: Node = get_tree().root.get_node_or_null("GameState") if get_tree() else null
	if gs_node and "game_constants" in gs_node:
		var dmg_mult: float = clampf(
			float(gs_node.game_constants.get("damage_multiplier", 1.0)),
			0.1, 10.0)
		actual_damage = int(actual_damage * dmg_mult)

	## Tick 386: damage_absorb status converts incoming damage to
	## healing 1:1 while active. Applied by the fill_the_void ability
	## (effect=damage_absorb, duration=2). Pre-fix the effect fell
	## through to push_warning — the ability burned 12 MP for nothing.
	## Duration controls when absorb wears off. Lethal-tick guard
	## doesn't apply since absorb returns 0 — caller sees "no damage
	## taken" and skips the die() branch downstream.
	if has_status("damage_absorb") and actual_damage > 0:
		var absorbed: int = actual_damage
		var old_hp_absorb: int = current_hp
		current_hp = min(max_hp, current_hp + absorbed)
		var healed: int = current_hp - old_hp_absorb
		if healed > 0:
			hp_changed.emit(old_hp_absorb, current_hp)
		# Emit status_tick_heal so BattleScene shows the green popup —
		# tagged with "damage_absorb" so the popup label can distinguish.
		if status_tick_heal != null and healed > 0:
			status_tick_heal.emit(healed, "damage_absorb")
		print("%s absorbed %d damage (healed %d)" % [combatant_name, absorbed, healed])
		return 0  # no damage taken

	var old_hp = current_hp
	current_hp = max(0, current_hp - actual_damage)

	## Tick 439: death_resistance passive — meta_effects.death_resist
	## _chance gives a roll to survive a killing blow at 1 HP.
	## Pre-fix the passive description claimed "75% chance to survive
	## a killing blow with 1 HP" but no code path read the meta
	## effect — the passive was pure decoration. Only applies on the
	## lethal hit (current_hp went from > 0 to 0) and on a successful
	## chance roll. The clamp at 1 leaves the combatant alive with a
	## sliver of HP, matching the description.
	if current_hp <= 0 and old_hp > 0:
		var resist_chance: float = _get_passive_meta_effect_sum("death_resist_chance")
		if resist_chance > 0.0 and randf() < clampf(resist_chance, 0.0, 1.0):
			current_hp = 1
			print("[DEATH_RESIST] %s survives a killing blow!" % combatant_name)
	# Flip is_alive BEFORE emitting hp_changed so any UI listener (e.g.
	# BattleUIManager.update_character_status) sees the correct state
	# and grays out the member on the lethal hit. Previously the ordering
	# was hp_changed -> die(), so on the last party death the UI sample
	# happened while is_alive was still true — the last member never
	# grayed out.
	if current_hp <= 0:
		is_alive = false
	# Tick 301: guard the emit on actual change. take_damage(0) is a
	# real call path — int-truncation on a 0.5x resistance against
	# 1-damage attacks, or damage_multiplier set to 0 by Scriptweaver,
	# or 100%-block by a passive — each case left old_hp == current_hp
	# but still re-emitted, prompting redundant UI redraws. Matches
	# the ap_changed (tick 286) and heal (tick 288) guard pattern.
	if current_hp != old_hp:
		hp_changed.emit(old_hp, current_hp)

	# Taking damage wakes up sleeping targets
	if has_status("sleep") and actual_damage > 0:
		remove_status("sleep")

	if current_hp <= 0:
		die()

	return actual_damage


func heal(amount: int) -> int:
	"""Heal HP, returns actual amount healed. Curse reduces healing by 50%.
	Tick 114: applies the global healing_multiplier from game_constants
	so Scriptweaver edits actually scale healing across the entire
	game. Pre-fix the constant was a cosmetic flag flip — no consumer."""
	if not is_alive:
		return 0

	## Tick 368: reject negative amounts. Pre-fix heal(-30) would
	## silently DRAIN 30 HP via the current_hp = min(max, hp + -30)
	## arithmetic, bypass the damage path entirely (no die() check,
	## no damage_dealt signal, no shake/popup), then return -30 — the
	## caller would emit healing_done(target, -30) producing a misleading
	## "+(-30) HP!" popup. A typo'd ability/item or Scriptweaver edit
	## with negative heal would silently exploit this.
	if amount < 0:
		push_warning("[Combatant] heal() called with negative amount %d on %s — refused, returning 0 (use take_damage for HP loss)" % [amount, combatant_name])
		return 0

	var heal_amount = amount
	if has_status("curse"):
		heal_amount = int(heal_amount * 0.5)

	# Global healing multiplier — defensive pattern matching tick 109/110/113.
	var gs_node: Node = get_tree().root.get_node_or_null("GameState") if get_tree() else null
	if gs_node and "game_constants" in gs_node:
		var heal_mult: float = clampf(
			float(gs_node.game_constants.get("healing_multiplier", 1.0)),
			0.1, 10.0)
		heal_amount = int(heal_amount * heal_mult)

	## Tick 373: passive healing_multiplier wiring. Pre-fix passive
	## `healing_boost` (data/passives.json: healing_multiplier=1.5) had
	## ZERO effect on healing — PassiveSystem.get_passive_mods
	## accumulated the multiplier into the total_mods dict but
	## Combatant.heal() only read game_constants["healing_multiplier"]
	## (Scriptweaver knob), never the passive's value. Players equipped
	## the passive seeing "+50% healing" in the description and got
	## nothing. Same defensive [0.1, 10.0] clamp as the game_constants
	## read above so a broken passive can't black-hole or runaway
	## healing.
	if has_node("/root/PassiveSystem"):
		var passive_mods: Dictionary = get_node("/root/PassiveSystem").get_passive_mods(self)
		var passive_heal_mult: float = clampf(
			float(passive_mods.get("healing_multiplier", 1.0)),
			0.1, 10.0)
		heal_amount = int(heal_amount * passive_heal_mult)

	var old_hp = current_hp
	current_hp = min(max_hp, current_hp + heal_amount)
	var healed = current_hp - old_hp
	# Tick 288: emit hp_changed only on actual change. Pre-fix heal()
	# fired hp_changed even when current_hp was already at max_hp (the
	# clamp pinned it; healed = 0). UI listeners then ran the redraw
	# path uselessly. Matches tick-286 ap_changed guard pattern.
	if healed != 0:
		hp_changed.emit(old_hp, current_hp)
	return healed


func restore_mp(amount: int) -> int:
	"""Restore MP, returns actual amount restored"""
	if not is_alive:
		return 0
	## Tick 368: same negative-amount guard as heal() above. Pre-fix
	## restore_mp(-15) silently drained 15 MP and returned -15 — caller
	## would emit healing_done(target, -15) producing a misleading
	## negative-amount popup. Use spend_mp for legitimate MP drain.
	if amount < 0:
		push_warning("[Combatant] restore_mp() called with negative amount %d on %s — refused, returning 0 (use spend_mp for MP drain)" % [amount, combatant_name])
		return 0
	var old_mp = current_mp
	current_mp = min(max_mp, current_mp + amount)
	return current_mp - old_mp


func spend_mp(amount: int) -> bool:
	"""Try to spend MP, returns false if insufficient"""
	if not is_alive:
		return false
	## Tick 370: refuse negative amounts. Pre-fix spend_mp(-5) returned
	## true (`current_mp < -5` is always false for non-negative MP)
	## then ran `current_mp -= -5`, GRANTING 5 MP through the spend
	## path and bypassing max_mp clamp. Callers using the bool return
	## as "MP cost paid?" gate would let a character cast for free AND
	## gain MP — beyond max_mp, even. Symmetric with tick 368's
	## restore_mp guard and tick 369's spend_ap guard. Use restore_mp
	## for legitimate MP gain (it clamps to max_mp correctly).
	if amount < 0:
		push_warning("[Combatant] spend_mp() called with negative amount %d on %s — refused, returning false (use restore_mp for MP gain)" % [amount, combatant_name])
		return false
	if current_mp < amount:
		return false
	current_mp -= amount
	return true


func die() -> void:
	"""Handle death"""
	# Tick 283: emit hp_changed alongside died IF current_hp wasn't
	# already 0. Pre-fix die() was called from BattleManager's
	# PERMAKILL ability path with no hp_changed signal — so UI
	# listeners (BattleUIManager) updating the HP bar via hp_changed
	# never saw the lethal drop. The bar stayed at the pre-permakill
	# HP value until the next unrelated event triggered a redraw.
	#
	# The guard avoids double-emit on the take_damage → die() path
	# (take_damage already emits hp_changed before calling die at
	# its line ~242). Matches take_damage's is_alive-before-emit
	# ordering so UI listeners see the post-death state on the
	# sample tick.
	var old_hp = current_hp
	is_alive = false
	current_hp = 0
	if old_hp != 0:
		hp_changed.emit(old_hp, current_hp)
	died.emit()


func revive(hp_amount: int = 0) -> void:
	"""Revive with specified HP (or 50% max if not specified)"""
	## Tick 421: refuse revive when permakilled. The permakilled status
	## is the canonical "this PC cannot come back" marker — set by the
	## permanent_death meta_effect (tick 354) AND by the
	## can_cause_permadeath flag enforcement (this tick). Pre-fix
	## Phoenix Down / revive abilities silently brought permakilled
	## PCs back, defeating the "HIGH RISK" design promise of the
	## permanent_death ability and the permadeath_reaper monster.
	if "permakilled" in status_effects:
		print("[REVIVE] refused — %s is permakilled" % combatant_name)
		return
	is_alive = true
	if hp_amount > 0:
		current_hp = min(hp_amount, max(1, max_hp))
	else:
		current_hp = max(1, max_hp / 2)  # Ensure minimum 1 HP
	hp_changed.emit(0, current_hp)


## MRU tracking — push an ability to the front of the recent list, dedupe, cap at MRU_SIZE
func record_ability_use(ability_id: String) -> void:
	if ability_id == "":
		return
	# Pinned abilities don't pollute the MRU list
	if ability_id in pinned_abilities:
		return
	if ability_id in recent_abilities:
		recent_abilities.erase(ability_id)
	recent_abilities.push_front(ability_id)
	if recent_abilities.size() > MRU_SIZE:
		recent_abilities.resize(MRU_SIZE)


## Returns the abilities to show in the top-level quick-access slots:
## pins first (in pin order), then MRU fills any remaining slots.
func get_quick_slot_abilities(num_slots: int = MRU_SIZE) -> Array[String]:
	var result: Array[String] = []
	for ability_id in pinned_abilities:
		if result.size() >= num_slots:
			break
		result.append(ability_id)
	for ability_id in recent_abilities:
		if result.size() >= num_slots:
			break
		if ability_id not in result:
			result.append(ability_id)
	return result


## Status effects
func add_status(status: String, duration: int = 3) -> void:
	# Tick 285: refresh duration when re-applying the same status.
	# Pre-fix this was a silent no-op when the status already existed —
	# the player couldn't extend a beneficial DOT (regen) or refresh
	# a debuff. Inconsistent with add_buff/add_debuff which both
	# refresh on re-apply. status_added.emit fires only on the
	# first add (UI doesn't need a "refresh" notification — the
	# status icon is already showing).
	if status in status_effects:
		status_durations[status] = duration
		print("%s refreshed status: %s (%d turns)" % [combatant_name, status, duration])
		return
	status_effects.append(status)
	status_durations[status] = duration
	status_added.emit(status)
	print("%s gained status: %s (%d turns)" % [combatant_name, status, duration])


func remove_status(status: String) -> void:
	if status in status_effects:
		status_effects.erase(status)
		status_durations.erase(status)
		status_removed.emit(status)


func has_status(status: String) -> bool:
	return status in status_effects


## Tick 439: sum a passive meta_effect across equipped_passives.
## Used by take_damage's death_resistance check (death_resist_chance
## meta_effect) but designed generically so future passive
## meta_effects (encounter_skip_chance, boss_damage_share, etc.) can
## reuse it. Returns 0.0 when PassiveSystem autoload isn't present
## (tests, preload context). Sums across all sources so a future
## stacked-passive build adds them.
func _get_passive_meta_effect_sum(key: String) -> float:
	if equipped_passives.is_empty():
		return 0.0
	var tree: SceneTree = get_tree() if has_method("get_tree") else null
	var ps: Node = tree.root.get_node_or_null("PassiveSystem") if tree else null
	if ps == null or not ps.has_method("get_passive"):
		return 0.0
	var total: float = 0.0
	for passive_id in equipped_passives:
		var passive: Dictionary = ps.get_passive(str(passive_id))
		if passive.is_empty():
			continue
		var me: Variant = passive.get("meta_effects", {})
		if not (me is Dictionary):
			continue
		total += float(me.get(key, 0.0))
	return total


## Buffs and Debuffs
func add_buff(effect: String, stat: String, modifier: float, duration: int) -> void:
	"""Add a temporary buff. Refreshes duration if same effect exists; upgrades modifier if stronger."""
	for existing in active_buffs:
		if existing["effect"] == effect:
			existing["remaining_turns"] = duration
			existing["duration"] = duration
			if modifier > existing["modifier"]:
				existing["modifier"] = modifier
			print("%s refreshed %s (%.1fx %s for %d turns)" % [combatant_name, effect, existing["modifier"], stat, duration])
			return
	var buff = {
		"effect": effect,
		"stat": stat,
		"modifier": modifier,
		"duration": duration,
		"remaining_turns": duration
	}
	active_buffs.append(buff)
	print("%s gained %s (%.1fx %s for %d turns)" % [combatant_name, effect, modifier, stat, duration])


func add_debuff(effect: String, stat: String, modifier: float, duration: int) -> void:
	"""Add a temporary debuff. Refreshes duration if same effect exists; upgrades to stronger (lower) modifier."""
	for existing in active_debuffs:
		if existing["effect"] == effect:
			existing["remaining_turns"] = duration
			existing["duration"] = duration
			if modifier < existing["modifier"]:
				existing["modifier"] = modifier
			print("%s refreshed %s (%.1fx %s for %d turns)" % [combatant_name, effect, existing["modifier"], stat, duration])
			return
	var debuff = {
		"effect": effect,
		"stat": stat,
		"modifier": modifier,
		"duration": duration,
		"remaining_turns": duration
	}
	active_debuffs.append(debuff)
	print("%s suffered %s (%.1fx %s for %d turns)" % [combatant_name, effect, modifier, stat, duration])


func get_buffed_stat(stat_name: String, base_value: int) -> int:
	"""Get stat value with buffs/debuffs applied. Clamped to [25%, 400%] of base, minimum 1."""
	var final_value = float(base_value)

	# Apply buffs
	for buff in active_buffs:
		if buff["stat"] == stat_name:
			final_value *= buff["modifier"]

	# Apply debuffs
	for debuff in active_debuffs:
		if debuff["stat"] == stat_name:
			final_value *= debuff["modifier"]

	# Cap: buffs can at most 4x a stat, debuffs can at most reduce to 25%
	final_value = clampf(final_value, base_value * 0.25, base_value * 4.0)
	# Minimum 1 only if base stat is positive (defense=0 should stay 0)
	if base_value > 0:
		return maxi(1, int(final_value))
	return int(final_value)


func update_buff_durations() -> void:
	"""Decrease buff/debuff durations, remove expired ones"""
	# Process damage-over-time effects
	# Same ordering fix as take_damage(): flip is_alive BEFORE emitting
	# hp_changed so UI listeners see the correct state on the lethal tick
	# and can gray the sprite in a single pass.
	## Tick 143: status-effect ticks fire status_tick_damage /
	## status_tick_heal so BattleScene can spawn a popup. Pre-fix
	## only hp_changed fired — UI updated the HP bar but never
	## showed the floating number, so status ticks felt invisible.
	if "poison" in status_effects and is_alive:
		## Tick 380: festered status doubles poison damage. Applied by
		## the fester ability (effect="amplify_poison"). Festered alone
		## does nothing — it amplifies poison ticks when both are
		## active. Stays in status_effects independently so a
		## festered-then-poison combo (apply fester first, then poison)
		## also amplifies, rewarding strategic ordering.
		var poison_damage = max(1, int(max_hp * 0.05))  # 5% max HP per turn
		if "festered" in status_effects:
			poison_damage *= 2
		var old_hp_poison = current_hp
		current_hp = max(0, current_hp - poison_damage)
		if current_hp <= 0:
			is_alive = false
		# Tick 302: guard the emit on actual change. Parity with regen
		# below (line ~511) which already gated on healed > 0.
		# Spurious-emit cases: current_hp was already 0 entering the
		# tick (alive-but-at-zero window from a mid-tick revive race),
		# or max_hp == 0 → max(0, 0-1) == 0 (boss with zeroed max_hp).
		if current_hp != old_hp_poison:
			hp_changed.emit(old_hp_poison, current_hp)
			status_tick_damage.emit(poison_damage, "poison")
			print("%s takes %d poison damage!" % [combatant_name, poison_damage])
		if current_hp <= 0:
			die()

	if "burning" in status_effects and is_alive:
		var burn_damage = max(1, int(max_hp * 0.08))  # 8% max HP per turn (fire burns harder than poison)
		var old_hp_burn = current_hp
		current_hp = max(0, current_hp - burn_damage)
		if current_hp <= 0:
			is_alive = false
		# Tick 302: same parity guard as poison above.
		if current_hp != old_hp_burn:
			hp_changed.emit(old_hp_burn, current_hp)
			status_tick_damage.emit(burn_damage, "burn")
			print("%s takes %d burn damage!" % [combatant_name, burn_damage])
		if current_hp <= 0:
			die()

	## Tick 379: lightning DOT — applied by static_field ability.
	## Pre-fix the status was authored but no consumer ticked damage;
	## now mirrors the poison/burn shape at 4% max_hp per turn (lighter
	## than burn's 8% and poison's 5% — static feels like persistent
	## zaps, not a sear). Same lethal-tick guard ordering as the
	## sister DOTs above so a static-kill grays the sprite cleanly.
	if "static" in status_effects and is_alive:
		var static_damage = max(1, int(max_hp * 0.04))
		var old_hp_static = current_hp
		current_hp = max(0, current_hp - static_damage)
		if current_hp <= 0:
			is_alive = false
		if current_hp != old_hp_static:
			hp_changed.emit(old_hp_static, current_hp)
			status_tick_damage.emit(static_damage, "static")
			print("%s takes %d static damage!" % [combatant_name, static_damage])
		if current_hp <= 0:
			die()

	## Tick 383: memory_leak DOT — applied by memory_leak ability.
	## Pre-fix the status was authored but had no consumer (the cast
	## landed 0.5x upfront damage but the advertised 4-turn DOT was
	## silently dropped). 3% max_hp per turn — lighter than burn/poison/
	## static because memory_leak already has upfront damage and lasts
	## a full 4 turns by default (12% total). Mirror lethal-tick guard
	## ordering of the sister DOTs above.
	if "memory_leak" in status_effects and is_alive:
		var leak_damage = max(1, int(max_hp * 0.03))
		var old_hp_leak = current_hp
		current_hp = max(0, current_hp - leak_damage)
		if current_hp <= 0:
			is_alive = false
		if current_hp != old_hp_leak:
			hp_changed.emit(old_hp_leak, current_hp)
			status_tick_damage.emit(leak_damage, "memory_leak")
			print("%s takes %d memory_leak damage!" % [combatant_name, leak_damage])
		if current_hp <= 0:
			die()

	# Process heal-over-time effects
	if "regen" in status_effects and is_alive:
		## Tick 436: read the authored regen_per_turn override stored
		## on meta when the regen status was applied (BattleManager
		## "regen" support arm). Falls back to the 5%-max-hp default
		## when no override is set — keeps existing regen-applying
		## abilities (regen as a buff effect from non-regenerate
		## sources) at their original feel.
		var override_amount: int = int(get_meta("_regen_per_turn", 0)) if has_method("get_meta") else 0
		var regen_heal: int = max(1, override_amount) if override_amount > 0 else max(1, int(max_hp * 0.05))
		var old_hp = current_hp
		current_hp = min(max_hp, current_hp + regen_heal)
		var healed = current_hp - old_hp
		if healed > 0:
			hp_changed.emit(old_hp, current_hp)
			status_tick_heal.emit(healed, "regen")
			print("%s regenerates %d HP!" % [combatant_name, healed])
		if current_hp <= 0:
			die()

	# Tick down status effect durations
	var expired_statuses: Array[String] = []
	for status in status_durations:
		if status_durations[status] > 0:  # -1 = permanent
			status_durations[status] -= 1
			if status_durations[status] <= 0:
				expired_statuses.append(status)
	for status in expired_statuses:
		remove_status(status)
		print("%s's %s wore off" % [combatant_name, status])

	# Update buffs
	for i in range(active_buffs.size() - 1, -1, -1):
		active_buffs[i]["remaining_turns"] -= 1
		if active_buffs[i]["remaining_turns"] <= 0:
			print("%s's %s wore off" % [combatant_name, active_buffs[i]["effect"]])
			active_buffs.remove_at(i)

	# Update debuffs
	for i in range(active_debuffs.size() - 1, -1, -1):
		active_debuffs[i]["remaining_turns"] -= 1
		if active_debuffs[i]["remaining_turns"] <= 0:
			print("%s's %s wore off" % [combatant_name, active_debuffs[i]["effect"]])
			active_debuffs.remove_at(i)

	# Update doom counter. Gate on is_alive so a doomed combatant who died
	# earlier in this same update_buff_durations pass (poison / burn lethal
	# tick) doesn't tick doom AGAIN and re-fire died(). Each is_alive guard
	# in the DoT blocks above already prevents the lethal-by-poison ->
	# lethal-by-burn cascade; this is the same defense for doom.
	if doom_counter > 0 and is_alive:
		doom_counter -= 1
		if doom_counter == 0:
			print("%s succumbs to Death Sentence!" % combatant_name)
			die()


## Elemental damage
func calculate_elemental_modifier(element: String) -> float:
	"""Calculate damage multiplier based on elemental affinity"""
	if element.is_empty():
		return 1.0

	if element in elemental_immunities:
		return 0.0
	elif element in elemental_weaknesses:
		return 1.5
	elif element in elemental_resistances:
		return 0.5

	return 1.0


func take_elemental_damage(base_damage: int, element: String) -> int:
	"""Take damage with elemental modifier"""

	## Tick 443: <element>_absorb meta_effect (passives.json).
	## undead_affinity authors meta_effects.dark_absorb = true with
	## description "+40% dark damage, heal from dark attacks", but
	## pre-fix the field was decoration — dark hits chewed HP just
	## like any other element. Generic by element so future
	## fire_absorb / ice_absorb passives (e.g. dragon attunement
	## sets) drop in with no new wire. Conversion is 1:1 (the full
	## base damage becomes healing) so the absorb feels like a
	## reward, not a soft resist. Heal goes through hp_changed +
	## status_tick_heal so the green popup labels the source.
	if not element.is_empty() and _absorbs_element(element):
		var heal_amount: int = max(1, base_damage)
		var old_hp_abs: int = current_hp
		current_hp = min(max_hp, current_hp + heal_amount)
		var healed: int = current_hp - old_hp_abs
		if healed > 0:
			hp_changed.emit(old_hp_abs, current_hp)
			if status_tick_heal != null:
				status_tick_heal.emit(healed, "absorb_" + element)
		print("%s absorbs %d %s damage!" % [combatant_name, healed, element])
		return 0

	var elemental_mod = calculate_elemental_modifier(element)

	## Tick 460: equipment.json special_effects.<element>_resistance.
	## bone_armor (dark_resistance) and dragon_mail (fire_resistance)
	## author the flag, but pre-tick no code read it — the dragon's
	## namesake protection was decoration. Walk the three equipment
	## slots via the BattleManager helper from tick 457 by reaching
	## through the scene tree (Combatant doesn't carry the helper
	## directly). Halve the elemental_mod on a hit so the equipment
	## stacks multiplicatively with the Combatant's existing
	## elemental_resistances list (a piece + a list entry → 0.25x).
	if _has_equipment_resistance(element):
		elemental_mod *= 0.5

	var actual_damage = int(base_damage * elemental_mod)

	if elemental_mod == 0.0:
		print("%s is immune to %s!" % [combatant_name, element])
		return 0
	elif elemental_mod > 1.0:
		print("It's super effective!")
	elif elemental_mod < 1.0:
		print("%s resists %s" % [combatant_name, element])

	return take_damage(actual_damage, true)


## Tick 460: generic check for an <element>_resistance entry on any
## of the combatant's three equipment slots. Returns false cleanly
## when EquipmentSystem isn't available (tests, preload). Bool-
## authored values come through float(true) = 1.0 so the > 0.0
## comparison catches both bool and numeric authoring.
func _has_equipment_resistance(element: String) -> bool:
	if element.is_empty():
		return false
	var tree: SceneTree = get_tree() if has_method("get_tree") else null
	var es: Node = tree.root.get_node_or_null("EquipmentSystem") if tree else null
	if es == null:
		return false
	var key: String = element + "_resistance"
	if equipped_weapon != "" and es.has_method("get_weapon"):
		var w: Dictionary = es.get_weapon(equipped_weapon)
		var w_se: Variant = w.get("special_effects", {})
		if w_se is Dictionary and float(w_se.get(key, 0.0)) > 0.0:
			return true
	if equipped_armor != "" and es.has_method("get_armor"):
		var a: Dictionary = es.get_armor(equipped_armor)
		var a_se: Variant = a.get("special_effects", {})
		if a_se is Dictionary and float(a_se.get(key, 0.0)) > 0.0:
			return true
	if equipped_accessory != "" and es.has_method("get_accessory"):
		var ac: Dictionary = es.get_accessory(equipped_accessory)
		var ac_se: Variant = ac.get("special_effects", {})
		if ac_se is Dictionary and float(ac_se.get(key, 0.0)) > 0.0:
			return true
	return false


## Tick 443: generic elemental absorb gate. <element>_absorb keys
## in passive meta_effects (e.g. dark_absorb on undead_affinity)
## convert damage of that element to healing. Bool-authored values
## come through _get_passive_meta_effect_sum as 1.0 via float(true).
func _absorbs_element(element: String) -> bool:
	if element.is_empty():
		return false
	return _get_passive_meta_effect_sum(element + "_absorb") > 0.0


## Permanent injuries (meta mechanic)
func apply_permanent_injury(injury: Dictionary) -> void:
	"""Apply a permanent stat penalty that persists across saves"""
	permanent_injuries.append(injury)

	if injury.has("stat"):
		var stat = injury["stat"]
		var penalty = injury.get("penalty", 0)

		match stat:
			"max_hp":
				max_hp = max(1, max_hp - penalty)
				# Tick 284: emit hp_changed when the clamp actually drops
				# current_hp. Pre-fix permanent injury silently reduced
				# current_hp below max_hp's new ceiling — UI HP bars
				# didn't refresh until the next take_damage / heal /
				# scene reload sampled the value.
				var old_hp_inj: int = current_hp
				current_hp = min(current_hp, max_hp)
				if current_hp != old_hp_inj:
					hp_changed.emit(old_hp_inj, current_hp)
			"attack":
				attack = max(1, attack - penalty)
			"defense":
				defense = max(1, defense - penalty)
			"magic":
				magic = max(1, magic - penalty)
			"speed":
				speed = max(1, speed - penalty)
			"max_mp":
				# Tick 287: max_mp injury support + clamp emit.
				# Pre-fix not in INJURY_TYPES (BattleManager:3479) but
				# Scriptweaver / custom paths could request it — the
				# match's lack of a branch silently no-op'd. Now mirrors
				# the max_hp clamp logic (no mp_changed signal exists;
				# UI polls current_mp via update_character_status).
				max_mp = max(0, max_mp - penalty)
				current_mp = min(current_mp, max_mp)
			_:
				# Tick 287: surface unknown injury stats. Pre-fix any
				# typo'd or new-stat injury (e.g. "luck" before it was
				# added) silently consumed the permanent_injuries slot
				# without applying its penalty — UI showed the injury
				# in the list but the player's stats were unchanged.
				push_warning("[Combatant] apply_permanent_injury: unknown stat '%s' — no penalty applied, injury still recorded in list (Scriptweaver typo? new stat needing a match arm?)" % stat)


## Turn management
func start_turn() -> void:
	"""Called at the start of this combatant's turn"""
	is_defending = false


func end_turn() -> void:
	"""Called at the end of this combatant's turn"""
	update_buff_durations()


func reset_for_new_round() -> void:
	"""Reset per-round state"""
	is_defending = false


## Utility
func get_hp_percentage() -> float:
	if max_hp <= 0:
		return 0.0
	return float(current_hp) / float(max_hp) * 100.0


func get_mp_percentage() -> float:
	if max_mp <= 0:
		return 0.0
	return float(current_mp) / float(max_mp) * 100.0


func to_dict() -> Dictionary:
	"""Serialize combatant state for saving.
	Bug fix (2026-04-30): expanded to include job, secondary_job, level/exp,
	equipment, inventory, and learned_passives. Previously these were missing,
	so any save → load cycle reset characters to fresh defaults at level 1
	with starter equipment. _sync_party_to_game_state in GameLoop.gd was also
	updated to call this function instead of synthesizing 5 fields by hand."""
	var data: Dictionary = {
		"name": combatant_name,
		"max_hp": max_hp,
		"max_mp": max_mp,
		"current_hp": current_hp,
		"current_mp": current_mp,
		"current_ap": current_ap,
		"attack": attack,
		"defense": defense,
		"magic": magic,
		"speed": speed,
		"job_level": job_level,
		"job_exp": job_exp,
		"status_effects": status_effects.duplicate(),
		## Tick 151: serialize the per-status duration counter. Pre-fix
		## status_effects survived save/load (and rewind) but
		## status_durations did not — so any poison/burn/etc that was
		## active during a Time Mage rewind survived the snapshot but
		## had no tick-down counter, becoming effectively permanent.
		## status_durations is iterated in update_status_durations
		## (line ~474); an empty dict skips the loop entirely.
		"status_durations": status_durations.duplicate(),
		## Tick 152: serialize buff/debuff arrays so a Time Mage
		## mid-battle rewind preserves them. Pre-fix only status_effects
		## persisted across snapshot — buffs/debuffs disappeared on
		## rewind, leaving the combatant in a weaker/stronger state
		## than the snapshot moment. Less catastrophic than the
		## status_durations gap (tick 151) since these clear at battle
		## end naturally, but still wrong for the rewind use-case.
		"active_buffs": active_buffs.duplicate(true),
		"active_debuffs": active_debuffs.duplicate(true),
		"permanent_injuries": permanent_injuries.duplicate(),
		"is_alive": is_alive,
		"learned_abilities": learned_abilities.duplicate(),
		"job_profiles": job_profiles.duplicate(true),
		"secondary_job_id": secondary_job_id,
		"equipped_weapon": equipped_weapon,
		"equipped_armor": equipped_armor,
		"equipped_accessory": equipped_accessory,
		"learned_passives": learned_passives.duplicate(),
		"equipped_passives": equipped_passives.duplicate(),
		"inventory": inventory.duplicate(),
		"doom_counter": doom_counter,
		"pinned_abilities": pinned_abilities.duplicate(),
		"recent_abilities": recent_abilities.duplicate(),
		"autobattle_locked": autobattle_locked,
	}
	# Job is a Dictionary; only its id is stable across runs (the full dict
	# is reconstructed via JobSystem.assign_job in restore).
	if job and job is Dictionary:
		data["job_id"] = job.get("id", "")
	# Synthetic fields for save-slot UI (legacy "level" key, hp pair).
	data["level"] = job_level
	data["job"] = data.get("job_id", "")
	data["hp"] = current_hp
	return data


func from_dict(data: Dictionary) -> void:
	"""Restore combatant state from saved data"""
	## Tick 157: int() coerce + clamp on all scalar stat fields.
	## JSON.parse returns numerics as float; typed-int fields would
	## auto-truncate, but explicit coerce + clamp catches save
	## corruption (negative HP, AP out of [-4, 4] range, level 0,
	## current_hp > max_hp from an interrupted save). Load order
	## matters: max_hp / max_mp loaded BEFORE current_hp / current_mp
	## so the cap-clamp uses the just-loaded max, not the default.
	if data.has("name"):
		combatant_name = data["name"]
	if data.has("max_hp"):
		# Floor at 1 — max_hp = 0 would divide-by-zero in
		# get_hp_percentage and break recalculate_stats's
		# `max(1, max_hp - penalty)` semantics.
		max_hp = max(1, int(data["max_hp"]))
	if data.has("max_mp"):
		max_mp = max(0, int(data["max_mp"]))
	if data.has("current_hp"):
		# Clamp to [0, max_hp]. Negative HP could happen via save
		# corruption; > max_hp could happen when a save was taken
		# during a +max_hp buff and the buff dropped off.
		current_hp = clampi(int(data["current_hp"]), 0, max_hp)
	if data.has("current_mp"):
		current_mp = clampi(int(data["current_mp"]), 0, max_mp)
	if data.has("current_ap"):
		# AP design range: -4 to +4 (CLAUDE.md combat section).
		current_ap = clampi(int(data["current_ap"]), -4, 4)
	if data.has("attack"):
		attack = max(0, int(data["attack"]))
	if data.has("defense"):
		defense = max(0, int(data["defense"]))
	if data.has("magic"):
		magic = max(0, int(data["magic"]))
	if data.has("speed"):
		speed = max(0, int(data["speed"]))
	if data.has("job_level"):
		# Floor at 1 — level 0 would break level_mult calculation
		# (1.0 + (0 - 1) * 0.04 = 0.96) and ability-learning gates.
		job_level = max(1, int(data["job_level"]))
	if data.has("job_exp"):
		job_exp = max(0, int(data["job_exp"]))
	# JSON-roundtrip note: JSON.parse returns generic Array, not Array[T].
	# Assigning to a typed Array[T] field silently fails with a SCRIPT
	# ERROR — the field keeps its prior value (default []). For each
	# Array[String] / Array[Dictionary] field below we coerce element
	# types explicitly via local typed-array build → assign. (2026-05-12:
	# parity audit found status_effects, permanent_injuries,
	# learned_passives, equipped_passives, pinned_abilities, and
	# recent_abilities were all silently lost on save/load.)
	if data.has("status_effects"):
		var typed_status: Array[String] = []
		for s in data["status_effects"]:
			typed_status.append(str(s))
		status_effects = typed_status
	## Tick 151: per-status duration counter. JSON.parse returns
	## numeric values as float, but status_durations is treated as
	## int (decrement-by-1 + > 0 check). Coerce to int on load.
	## Keys come back as String from JSON regardless of original type,
	## which is fine — status names are strings anyway.
	if data.has("status_durations"):
		var typed_durations: Dictionary = {}
		var raw: Dictionary = data["status_durations"]
		for status_key in raw.keys():
			typed_durations[str(status_key)] = int(raw[status_key])
		status_durations = typed_durations
	if data.has("permanent_injuries"):
		var typed_injuries: Array[Dictionary] = []
		for inj in data["permanent_injuries"]:
			if inj is Dictionary:
				typed_injuries.append(inj.duplicate(true))
		permanent_injuries = typed_injuries
	## Tick 152: typed Array[Dictionary] coercion for buffs/debuffs.
	## Same pattern as permanent_injuries above. JSON.parse returns
	## generic Array; direct assignment to Array[Dictionary] silently
	## fails (Combatant comment at to_dict explains the trap). Inner
	## numeric fields (modifier/duration/remaining_turns) come back
	## as float from JSON — duration counters get coerced to int so
	## the > 0 / decrement-by-1 logic in update_buff_durations
	## doesn't drift on float arithmetic.
	if data.has("active_buffs"):
		var typed_buffs: Array[Dictionary] = []
		for b in data["active_buffs"]:
			if b is Dictionary:
				var entry: Dictionary = b.duplicate(true)
				if entry.has("duration"):
					entry["duration"] = int(entry["duration"])
				if entry.has("remaining_turns"):
					entry["remaining_turns"] = int(entry["remaining_turns"])
				typed_buffs.append(entry)
		active_buffs = typed_buffs
	if data.has("active_debuffs"):
		var typed_debuffs: Array[Dictionary] = []
		for d in data["active_debuffs"]:
			if d is Dictionary:
				var entry: Dictionary = d.duplicate(true)
				if entry.has("duration"):
					entry["duration"] = int(entry["duration"])
				if entry.has("remaining_turns"):
					entry["remaining_turns"] = int(entry["remaining_turns"])
				typed_debuffs.append(entry)
		active_debuffs = typed_debuffs
	## Tick 158: derive is_alive from current_hp instead of trusting
	## the saved bool. Pre-fix a corrupted save with current_hp=0 +
	## is_alive=true would leave the combatant "alive but at 0 HP"
	## until the next take_damage call flipped it. Symmetric:
	## current_hp>0 + is_alive=false would leave a "dead but
	## healable" combatant. The pairing IS enforced everywhere else
	## (die sets is_alive=false AND current_hp=0; revive sets
	## is_alive=true AND current_hp>=1) so derivation is sound and
	## seals load against save corruption.
	is_alive = current_hp > 0
	if data.has("learned_abilities"):
		learned_abilities.clear()
		for ability_id in data["learned_abilities"]:
			learned_abilities.append(ability_id)
	if data.has("job_profiles"):
		job_profiles = data["job_profiles"].duplicate(true)
	# Equipment + secondary job + inventory/passives (all expanded
	# 2026-04-30 bug fix — see to_dict comment).
	if data.has("equipped_weapon"):
		equipped_weapon = data["equipped_weapon"]
	if data.has("equipped_armor"):
		equipped_armor = data["equipped_armor"]
	if data.has("equipped_accessory"):
		equipped_accessory = data["equipped_accessory"]
	if data.has("secondary_job_id"):
		secondary_job_id = data["secondary_job_id"]
	if data.has("learned_passives"):
		## Tick 160: dedupe learned_passives on load. No size cap on
		## learned (no slot limit; can know more than you equip) but
		## duplicates would silently double-count toward UI counters /
		## set membership checks that use array length.
		var typed_lp: Array[String] = []
		var seen_lp: Dictionary = {}
		for p in data["learned_passives"]:
			var sid: String = str(p)
			if sid == "" or seen_lp.has(sid):
				continue
			seen_lp[sid] = true
			typed_lp.append(sid)
		learned_passives = typed_lp
	if data.has("equipped_passives"):
		## Tick 160: enforce slot cap + dedupe on load. PassiveSystem.
		## equip_passive enforces both at write time (slot count check,
		## "already equipped" check) but from_dict bypassed those.
		## A corrupted save with 99 entries would propagate to runtime
		## and stack passive multipliers way past the design balance —
		## or include duplicates whose multipliers compound. Cap by
		## keeping first N (chronological-equip preserved, oldest wins).
		var typed_ep: Array[String] = []
		var seen: Dictionary = {}
		for p in data["equipped_passives"]:
			var sid: String = str(p)
			if sid == "" or seen.has(sid):
				continue
			seen[sid] = true
			typed_ep.append(sid)
			if typed_ep.size() >= max_passive_slots:
				break
		equipped_passives = typed_ep
	if data.has("inventory"):
		## Tick 162: int() coerce + filter non-positive + filter empty
		## key. JSON.parse returns numerics as float; downstream
		## add_item/remove_item treat values as int (`+= quantity`
		## auto-truncates on first mutation but UI rendering before
		## any mutation shows fractional counts). remove_item erases
		## entries that drop to ≤ 0 — mirror that on load so a save
		## with `potion: -5` from corruption doesn't sit as a ghost
		## negative entry showing "-5 potions" in the menu. Empty-key
		## entries (e.g. `"": 3`) are phantom rows that iterate UI
		## sites can't render meaningfully.
		## Tick 395: type-guard before the typed-Dict assignment. Pre-fix
		## a corrupted save with `"inventory": null` (or int/string)
		## crashed with `Trying to assign value of type 'X' to a variable
		## of type 'Dictionary'`. Same class as tick 363/364's GameState
		## guards.
		var raw_inv_v: Variant = data["inventory"]
		if raw_inv_v is Dictionary:
			var raw_inv: Dictionary = raw_inv_v
			var typed_inv: Dictionary = {}
			for item_id in raw_inv.keys():
				var key: String = str(item_id)
				if key == "":
					continue
				var qty: int = int(raw_inv[item_id])
				if qty <= 0:
					continue
				typed_inv[key] = qty
			inventory = typed_inv
		else:
			push_warning("[Combatant] from_dict: inventory malformed (type=%s) — keeping defaults" % typeof(raw_inv_v))
	if data.has("doom_counter"):
		## Tick 158: int() coerce + normalize any negative to the
		## canonical -1 sentinel ("not doomed"). All consumers
		## check `> 0` for active countdown and `== 0` for the
		## kill-trigger, so a value like -5 from save corruption
		## isn't directly harmful — but it muddles the contract,
		## and downstream code that later adds a `== -1` check
		## (cleaner alternative to `<= -1`) would silently miss it.
		var raw_doom: int = int(data["doom_counter"])
		doom_counter = -1 if raw_doom < 0 else raw_doom
	if data.has("pinned_abilities"):
		## Tick 161: dedupe + filter empty. Pinned has no documented
		## cap (player-selected) but duplicates would double-render
		## in the quick-slot menu. The add_to_mru helper at line
		## ~314 enforces "Pinned abilities don't pollute the MRU
		## list" but only on the write path — from_dict was
		## bypassing it.
		var typed_pinned: Array[String] = []
		var seen_pinned: Dictionary = {}
		for ability_id in data["pinned_abilities"]:
			var sid: String = str(ability_id)
			if sid == "" or seen_pinned.has(sid):
				continue
			seen_pinned[sid] = true
			typed_pinned.append(sid)
		pinned_abilities = typed_pinned
	if data.has("recent_abilities"):
		## Tick 161: enforce MRU_SIZE cap + dedupe + filter empty
		## + filter pinned-overlap. MRU adds at add_to_mru (line
		## ~310) enforce all four constraints at write but from_dict
		## bypassed them. A corrupted save with 99 entries would
		## propagate, breaking the quick-slot menu's 2-slot layout.
		## Filter pinned-overlap matches add_to_mru's line 314 guard
		## ("Pinned abilities don't pollute the MRU list").
		var typed_recent: Array[String] = []
		var seen_recent: Dictionary = {}
		var pinned_set: Dictionary = {}
		for pid in pinned_abilities:
			pinned_set[pid] = true
		for ability_id in data["recent_abilities"]:
			var sid: String = str(ability_id)
			if sid == "" or seen_recent.has(sid) or pinned_set.has(sid):
				continue
			seen_recent[sid] = true
			typed_recent.append(sid)
			if typed_recent.size() >= MRU_SIZE:
				break
		recent_abilities = typed_recent
	if data.has("autobattle_locked"):
		autobattle_locked = bool(data["autobattle_locked"])

	# Resolve legacy job aliases in loaded data
	var job_system = get_node_or_null("/root/JobSystem")
	if job_system:
		# Resolve job ID in current job dict
		if job and job is Dictionary and job.has("id"):
			job["id"] = job_system.resolve_job_id(job["id"])
		# Resolve secondary job ID
		if secondary_job_id != "":
			secondary_job_id = job_system.resolve_job_id(secondary_job_id)
		if secondary_job and secondary_job is Dictionary and secondary_job.has("id"):
			secondary_job["id"] = job_system.resolve_job_id(secondary_job["id"])
		# Resolve job profile keys (e.g. "fighter:thief" -> "fighter:rogue")
		var resolved_profiles: Dictionary = {}
		for key in job_profiles:
			var parts = key.split(":")
			var resolved_key = job_system.resolve_job_id(parts[0])
			if parts.size() > 1 and parts[1] != "":
				resolved_key += ":" + job_system.resolve_job_id(parts[1])
			else:
				resolved_key += ":" + (parts[1] if parts.size() > 1 else "")
			resolved_profiles[resolved_key] = job_profiles[key]
		job_profiles = resolved_profiles


func learn_ability(ability_id: String) -> bool:
	"""Learn a new ability (from magic shop purchase or level-up).
	Returns true if the ability was newly granted, false if the
	combatant already knew it. tick 58: signature changed from void
	to bool so JobSystem.learn_abilities_for_level can dedupe."""
	if ability_id in learned_abilities:
		return false
	learned_abilities.append(ability_id)
	print("%s learned ability: %s" % [combatant_name, ability_id])
	return true


func has_learned_ability(ability_id: String) -> bool:
	"""Check if this combatant has learned a specific ability"""
	return ability_id in learned_abilities


## Job profile management
func get_profile_key() -> String:
	"""Get current job profile key as 'primary_id:secondary_id'"""
	var primary_id = job.get("id", "fighter") if job else "fighter"
	return "%s:%s" % [primary_id, secondary_job_id]


func save_current_profile() -> void:
	"""Save current equipment, passives, and autobattle to job profile"""
	var key = get_profile_key()
	var profile = {
		"weapon": equipped_weapon,
		"armor": equipped_armor,
		"accessory": equipped_accessory,
		"passives": equipped_passives.duplicate(),
	}
	var abs = get_node_or_null("/root/AutobattleSystem")
	if abs:
		var char_id = combatant_name.to_lower().replace(" ", "_")
		profile["autobattle"] = abs.get_character_script(char_id).duplicate(true)
	job_profiles[key] = profile


func load_profile(key: String) -> void:
	"""Load a saved job profile, equipping items and passives"""
	if not job_profiles.has(key):
		return
	var profile = job_profiles[key]

	equipped_weapon = profile.get("weapon", "")
	equipped_armor = profile.get("armor", "")
	equipped_accessory = profile.get("accessory", "")

	equipped_passives.clear()
	for passive_id in profile.get("passives", []):
		equipped_passives.append(passive_id)

	var abs = get_node_or_null("/root/AutobattleSystem")
	if abs and profile.has("autobattle"):
		var char_id = combatant_name.to_lower().replace(" ", "_")
		abs.set_character_script(char_id, profile["autobattle"].duplicate(true))

	recalculate_stats()


func fork_profile(from_key: String, to_key: String) -> void:
	"""Copy a profile from one key to another (first time with a new combo)"""
	if job_profiles.has(from_key):
		job_profiles[to_key] = job_profiles[from_key].duplicate(true)


## Stat recalculation with modifiers
func recalculate_stats() -> void:
	"""Recalculate all stats based on base stats + modifiers"""
	# Start with base stats
	max_hp = base_max_hp
	max_mp = base_max_mp
	attack = base_attack
	defense = base_defense
	magic = base_magic
	speed = base_speed

	# Apply job modifiers (if JobSystem is available)
	if job and job.has("stat_modifiers"):
		var job_mods = job["stat_modifiers"]
		if job_mods.has("max_hp"):
			max_hp = job_mods["max_hp"]
		if job_mods.has("max_mp"):
			max_mp = job_mods["max_mp"]
		if job_mods.has("attack"):
			attack = job_mods["attack"]
		if job_mods.has("defense"):
			defense = job_mods["defense"]
		if job_mods.has("magic"):
			magic = job_mods["magic"]
		if job_mods.has("speed"):
			speed = job_mods["speed"]

	# Apply job level bonuses (+4% all stats per level)
	var level_mult = 1.0 + (job_level - 1) * 0.04
	max_hp = int(max_hp * level_mult)
	max_mp = int(max_mp * level_mult)
	attack = int(attack * level_mult)
	defense = int(defense * level_mult)
	magic = int(magic * level_mult)
	speed = int(speed * level_mult)

	# Apply passive modifiers (via runtime lookup — autoload identifiers
	# don't resolve in preload() parse contexts used by the test suite,
	# so we keep this runtime-scoped).
	if has_node("/root/PassiveSystem"):
		var passive_mods = get_node("/root/PassiveSystem").get_passive_mods(self)
		max_hp = int(max_hp * passive_mods.get("max_hp_multiplier", 1.0))
		max_mp = int(max_mp * passive_mods.get("max_mp_multiplier", 1.0))
		attack = int(attack * passive_mods.get("attack_multiplier", 1.0))
		defense = int(defense * passive_mods.get("defense_multiplier", 1.0))
		magic = int(magic * passive_mods.get("magic_multiplier", 1.0))
		speed = int(speed * passive_mods.get("speed_multiplier", 1.0))

	# Apply equipment modifiers (same test-preload caveat as above).
	if has_node("/root/EquipmentSystem"):
		var equip_mods = get_node("/root/EquipmentSystem").get_equipment_mods(self)
		max_hp += equip_mods.get("max_hp", 0)
		max_mp += equip_mods.get("max_mp", 0)
		attack += equip_mods.get("attack", 0)
		defense += equip_mods.get("defense", 0)
		magic += equip_mods.get("magic", 0)
		speed += equip_mods.get("speed", 0)

	# Apply permanent injuries (reductions)
	for injury in permanent_injuries:
		if injury.has("stat") and injury.has("penalty"):
			match injury["stat"]:
				"max_hp":
					max_hp = max(1, max_hp - injury["penalty"])
				"attack":
					attack = max(1, attack - injury["penalty"])
				"defense":
					defense = max(1, defense - injury["penalty"])
				"magic":
					magic = max(1, magic - injury["penalty"])
				"speed":
					speed = max(1, speed - injury["penalty"])
				"max_mp":
					# Tick 316: re-apply max_mp injury on every recalc.
					# Pre-fix apply_permanent_injury (tick 287) handled the
					# first application but recalculate_stats was MISSING
					# the max_mp arm — so the very next recalc (equip/
					# unequip/job change) reset max_mp from base + buffs
					# and silently lost the injury penalty. The injury
					# was still in permanent_injuries (visible in the UI)
					# but had zero stat effect from then on. Mirror the
					# floor=0 from apply_permanent_injury since max_mp
					# can legitimately reach 0 (some classes have 0 MP).
					max_mp = max(0, max_mp - injury["penalty"])

	# Clamp current HP/MP to new maxes
	# Same ordering fix as take_damage / update_buff_durations: flip
	# is_alive BEFORE emitting hp_changed so UI listeners see the correct
	# state on a stat-recalc that drops HP to 0 (e.g. unequipping an
	# HP-granting item that would leave current_hp above the new max).
	var old_hp = current_hp
	current_hp = min(current_hp, max_hp)
	var needs_die := current_hp <= 0 and is_alive
	if needs_die:
		is_alive = false
	if current_hp != old_hp:
		hp_changed.emit(old_hp, current_hp)
	if needs_die:
		die()

	var old_mp = current_mp
	current_mp = min(current_mp, max_mp)


func gain_job_exp(amount: int) -> void:
	"""Gain job experience and level up if threshold met.
	Handles multi-level-ups in a single call (e.g. autogrind awards 500+ EXP
	per battle, enough to cross multiple level thresholds). Previously only
	one level-up fired per call, leaving excess EXP stalled at the new level."""
	if amount <= 0:
		return
	job_exp += amount
	# Renamed in tick 55 to avoid shadowing the new `leveled_up` signal.
	var did_level := false
	# Loop while excess EXP crosses the next-level threshold. Each level
	# consumes `job_level * 100` before incrementing, so the threshold grows
	# after each pass. Cap at 99 as a safety (same ceiling used elsewhere).
	while job_exp >= job_level * 100 and job_level < 99:
		job_exp -= job_level * 100
		job_level += 1
		did_level = true
		print("%s reached job level %d!" % [combatant_name, job_level])
		leveled_up.emit(job_level)

	if did_level:
		recalculate_stats()
		# Per-level ability unlocks live in JobSystem (data-driven via
		# the abilities_at_level field on each job). Calling
		# learn_abilities_for_level here grants any newly-eligible
		# abilities and emits ability_learned for each one.
		if JobSystem and JobSystem.has_method("learn_abilities_for_level"):
			JobSystem.learn_abilities_for_level(self, job_level)


func learn_passive(passive_id: String) -> void:
	"""Learn a new passive ability"""
	if not passive_id in learned_passives:
		learned_passives.append(passive_id)
		print("%s learned passive: %s" % [combatant_name, passive_id])


## Inventory management
func add_item(item_id: String, quantity: int = 1) -> void:
	"""Add item(s) to inventory"""
	## Tick 371: refuse negative quantity. Pre-fix add_item(id, -5)
	## silently DRAINED 5 items via `inventory[id] += -5`, mirror of
	## the spend_mp/spend_ap negative-amount footguns. A typo'd reward
	## table, Scriptweaver mod, or sign-bug in a computed drop count
	## could quietly empty inventories. Use remove_item for legitimate
	## inventory drain.
	if quantity < 0:
		push_warning("[Combatant] add_item('%s', %d) on %s — negative quantity refused (use remove_item to drain)" % [item_id, quantity, combatant_name])
		return
	# Refuse empty item_id — would create an empty-key inventory slot
	# that no caller can reference cleanly.
	if item_id == "":
		push_warning("[Combatant] add_item called with empty item_id on %s — refused" % combatant_name)
		return
	if inventory.has(item_id):
		inventory[item_id] += quantity
	else:
		inventory[item_id] = quantity


func remove_item(item_id: String, quantity: int = 1) -> bool:
	"""Remove item(s) from inventory. Returns false if insufficient quantity."""
	## Tick 371: refuse negative quantity. Pre-fix remove_item(id, -5)
	## passed both gates (inventory.has + `inventory[id] < -5` always
	## false) then ran `inventory[id] -= -5` GRANTING 5 items, AND
	## returned true — symmetric to spend_mp's bypass. Use add_item
	## for legitimate inventory gain.
	if quantity < 0:
		push_warning("[Combatant] remove_item('%s', %d) on %s — negative quantity refused (use add_item to grant)" % [item_id, quantity, combatant_name])
		return false
	if not inventory.has(item_id) or inventory[item_id] < quantity:
		return false

	inventory[item_id] -= quantity
	if inventory[item_id] <= 0:
		inventory.erase(item_id)

	return true


func has_item(item_id: String, quantity: int = 1) -> bool:
	"""Check if inventory contains item(s)"""
	return inventory.has(item_id) and inventory[item_id] >= quantity


func get_item_count(item_id: String) -> int:
	"""Get quantity of an item in inventory"""
	return inventory.get(item_id, 0)
