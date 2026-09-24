extends RefCounted
class_name HeadlessBattleResolver

## HeadlessBattleResolver — Pure math battle resolution for ludicrous speed autogrind.
## No scene tree, no rendering, no timers. Resolves a full battle in <1ms.

const MAX_ROUNDS = 50
const ACTION_SPEEDS = {"attack": 5, "ability": 10, "item": 8, "defend": 0, "defer": 0}

## Twin of BattleManager.PRIORITY_OFFSET — same name, same value, same meaning: SUBTRACTED from a
## priority action's speed so it outruns the queue while priority actions still sort against each
## other. The two are independent declarations BY CONSTRUCTION and must agree in VALUE, not in type:
## live's is a float on a scale of `base - speed*0.5` plus CTB jitter, this one an int on `base -
## speed`, which is twice as sensitive to speed — so live's "larger than any reachable speed_value"
## does NOT transfer and was re-derived here. Measured 2026-09-16 over BOTH corpora, because deriving
## a speed ceiling from jobs alone is blind to the faster half: max authored speed is 30 and it is a
## MONSTER (masterite_tempo_abstract); the fastest job is ninja at 18. With Combatant.gd:1634's
## +4%/level multiplier, 4.92 at job_level 99, that is ~148 — so 1000 keeps a ~7x margin. The margin
## arm recomputes this from jobs.json AND monsters.json every run rather than trusting this line.
## RETIREMENT CONDITION: the day the grind adopts live's speed formula (halved speed + jitter), the
## two consts collapse into one and this note goes with them.
const PRIORITY_OFFSET: int = 1000

## Formation definitions (mirrored from BattleCommandMenu.FORMATIONS)
const FORMATIONS = [
	{"id": "four_heroes", "required_jobs": ["fighter", "cleric", "mage", "rogue"], "min_members": 4, "ap_cost": 2},
	{"id": "arcane_tempest", "required_jobs": ["mage", "cleric", "bard"], "min_members": 3, "ap_cost": 3},
	{"id": "blade_storm", "required_jobs": ["fighter", "rogue", "ninja"], "min_members": 3, "ap_cost": 2},
	{"id": "iron_wall", "required_jobs": ["fighter", "guardian", "cleric"], "min_members": 3, "ap_cost": 2},
	{"id": "shadow_strike", "required_jobs": ["rogue", "ninja"], "min_members": 2, "ap_cost": 2},
	{"id": "chaos_theory", "required_jobs": ["speculator", "bard"], "min_members": 2, "ap_cost": 3},
]

## Group attack cooldown — don't spam every round
const GROUP_ATTACK_COOLDOWN = 3
## Every per-battle meta this file sets. Cleared at the battle boundary alongside live's seven
## fields — cowir-battle's ec70e8e43 extended live's clear from FIELDS to METAS after
## _summon_followup kept a lingering eidolon hitting in the NEXT encounter. A const rather than a
## literal so test_autogrind_a_battle_starts_clean_regression can compare it against the set_meta
## calls in this file and red when a fourth appears unlisted.
##
## ⚠️ A CONST OF THIS NAME EXISTS TWICE, IN TWO ENGINES, WITH DELIBERATELY DIFFERENT CONTENTS.
## BattleManager has its own (ec70e8e43): 12+ keys including _summon_followup,
## _mind_swap_controller, _steal_response_consumed, _boss_face_index, plus PREFIX support for
## composed keys (a trailing "_" clears every meta carrying it). This list is a strict SUBSET and is
## meant to be — it is derived from what THIS file sets, which the arm named above enforces, and the
## grind has no summon, no mind-swap and no boss faces. DO NOT UNIFY THEM: the name matching is the
## trap, and CLAUDE.md's case (b) is exactly this shape — divergent, and invisible at authoring.
## Same name, two engines, arrived at independently within an hour; neither copied the other.
##
## RETIREMENT CONDITION, so this note cannot quietly become permanent (@cowir-music's form): the day
## the two engines' per-battle state is genuinely the same set, these two collapse into one and this
## comment goes with them. Until then the lists disagree BY CONSTRUCTION, not by drift.
const PER_BATTLE_METAS: Array[String] = ["_next_attack_multiplier", "_regen_per_turn", "_damage_absorb_budget"]
var _rounds_since_group_attack: int = 99

var _player_party: Array = []
var _enemy_party: Array = []
var _current_round: int = 0
var _battle_log: Array[String] = []
## The grind battle's terrain, set by the caller. Live gets one via BattleScene.set_terrain; this
## engine was handed the same string and dropped it, so a cave grind scaled nothing.
var terrain: String = "plains"
## SNAPSHOT, not a live read. GameState._advance_weather ROLLS RANDOMLY during _process, so asking
## it per cast made this engine's damage move between runs — measured, it broke a sibling's ratchet.
## "clear" carries no modifier, so every existing caller stays exactly as deterministic as before.
var weather: String = "clear"
## BattleManager:230. Steal gold scales with the victim's max HP on both sides of the port.
const STEAL_GOLD_HP_DIVISOR: float = 500.0
var _stolen_gold: int = 0


func resolve_battle(player_party: Array, enemy_party: Array) -> Dictionary:
	_player_party = player_party
	_enemy_party = enemy_party
	_current_round = 0
	_battle_log.clear()
	_rounds_since_group_attack = 99
	_stolen_gold = 0

	## A BATTLE STARTS CLEAN, mirroring BattleManager.start_battle:519-534 field for field and with
	## the same scope (all combatants, not just the party). Live's own comment says why: so nothing
	## "can't leak into the next encounter." This file cleared NONE of it, and the grind is the engine
	## where that compounds — AutogrindController holds `_party` as Combatant OBJECTS (:34), populated
	## once in start_grind and reused for EVERY battle of the session. So a buff won in battle 1 made
	## the party stronger than live for battles 2..N, a poison kept ticking into fights the game would
	## have started clean, and a doom_counter — lethal since cowir-battle's 48a70e4dd — could kill in a
	## battle live had already disarmed. Enemies are rebuilt per battle, so only the party accumulated.
	## NOT cleared, because live does not: HP, MP and permanent_injuries. A grind that healed the party
	## between fights would be a worse bug than the leak it replaced; there is an arm for that.
	for combatant in (_player_party + _enemy_party):
		if combatant == null or not is_instance_valid(combatant):
			continue
		if "active_buffs" in combatant:
			combatant.active_buffs.clear()
		if "active_debuffs" in combatant:
			combatant.active_debuffs.clear()
		if "status_effects" in combatant:
			combatant.status_effects.clear()
		if "status_durations" in combatant:
			combatant.status_durations.clear()
		if "is_defending" in combatant:
			combatant.is_defending = false
		## -1 is the "not doomed" sentinel (Combatant.gd:84). 0 is a LIVE counter — live sets -1 here
		## and its comment records that 0 was the bug.
		if "doom_counter" in combatant:
			combatant.doom_counter = -1
		## Metas too, tracking live. Cleared AFTER the fields on purpose: _regen_per_turn and
		## _damage_absorb_budget are bounded by statuses cleared just above, so dropping the status
		## without its meta leaves a number nothing owns — which is how the ward went uncapped.
		for meta_key in PER_BATTLE_METAS:
			if combatant.has_meta(meta_key):
				combatant.remove_meta(meta_key)

	## Tick 145: mark encountered monsters as seen in the bestiary,
	## mirroring BattleScene._show_battle_quip. Pre-fix autogrind
	## battles never updated the bestiary — a player running
	## autogrind for hours could face hundreds of monster types
	## without any of them showing up in their bestiary.
	# Tick 260: pass current map id so the "Last seen: <location>"
	# bestiary hint reflects autogrind encounters too.
	var loc: String = ""
	if MapSystem and "current_map_id" in MapSystem:
		loc = str(MapSystem.current_map_id)
	for enemy in _enemy_party:
		if not is_instance_valid(enemy):
			continue
		var mtype: String = ""
		if enemy.has_method("get_meta") and enemy.has_meta("monster_type"):
			mtype = str(enemy.get_meta("monster_type", ""))
		if mtype != "":
			BestiarySystem.mark_seen(mtype, loc)

	# Edge case: empty or all-dead party = immediate defeat
	var alive_players = _player_party.filter(func(c): return c.is_alive)
	if alive_players.is_empty():
		_log("No alive party members — immediate defeat")
		return _build_results(false)

	# Edge case: no enemies = immediate victory with 0 EXP
	if _enemy_party.is_empty():
		_log("No enemies — immediate victory")
		return _build_results(true)

	# Temporarily register parties in BattleManager so AutobattleSystem
	# target-resolution (_get_enemies_for / _get_allies_for) works correctly.
	# Engine.has_singleton("BattleManager") is ALWAYS FALSE for autoloads in
	# Godot 4 — fetch from scene tree root, then fall back to _get_autoload
	# for the test harness path.
	var tree = Engine.get_main_loop()
	var bm: Node = null
	if tree is SceneTree and (tree as SceneTree).root != null:
		bm = (tree as SceneTree).root.get_node_or_null("BattleManager")
	if not bm:
		bm = _get_autoload("BattleManager")
	var _bm_player_backup: Array = []
	var _bm_enemy_backup: Array = []
	## `turn` / TURN_COUNT rule conditions read BattleManager.current_round, whose only writers are
	## on the live path — so a grind evaluated them against a frozen number and every turn-gated
	## rule was permanently true or permanently false. Borrow and restore it like the parties.
	var _bm_round_backup: int = 0
	if bm:
		_bm_player_backup = bm.player_party.duplicate()
		_bm_enemy_backup = bm.enemy_party.duplicate()
		_bm_round_backup = bm.current_round
		bm.player_party.clear()
		bm.enemy_party.clear()
		for c in _player_party:
			bm.player_party.append(c)
		for c in _enemy_party:
			bm.enemy_party.append(c)

	while _current_round < MAX_ROUNDS:
		_current_round += 1
		if bm:
			bm.current_round = _current_round

		_tick_round_start()

		var actions = _selection_phase()

		actions.sort_custom(func(a, b): return a.get("speed", 0) < b.get("speed", 0))

		for action in actions:
			_execute_action(action)

			if _all_dead(_enemy_party):
				if bm:
					_restore_bm(bm, _bm_player_backup, _bm_enemy_backup, _bm_round_backup)
				return _build_results(true)
			if _all_dead(_player_party):
				if bm:
					_restore_bm(bm, _bm_player_backup, _bm_enemy_backup, _bm_round_backup)
				return _build_results(false)

	# Cadence #19: MAX_ROUNDS exhaustion used to _build_results(false) silently — no log, no diagnostic. A player rule facing an unkillable enemy (healing boss, wrong element, undertuned party) would grind to a halt reporting defeats forever with no reason. Now: log + push_warning + termination_reason in results so callers can distinguish "died fair and square" from "battle timed out".
	_log("Battle exhausted MAX_ROUNDS=%d without resolution — treating as defeat" % MAX_ROUNDS)
	push_warning("[HeadlessBattleResolver] Battle stalemated at MAX_ROUNDS=%d — party may be undertuned for this encounter, or enemy has a heal/regen loop this ruleset can't break" % MAX_ROUNDS)
	if bm:
		_restore_bm(bm, _bm_player_backup, _bm_enemy_backup, _bm_round_backup)
	return _build_results(false, "stalemate")


func _restore_bm(bm, player_backup: Array, enemy_backup: Array, round_backup: int = 0) -> void:
	bm.current_round = round_backup
	bm.player_party.clear()
	bm.enemy_party.clear()
	for c in player_backup:
		bm.player_party.append(c)
	for c in enemy_backup:
		bm.enemy_party.append(c)


func _get_autoload(name: String) -> Object:
	var tree = Engine.get_main_loop()
	if tree and tree.root:
		return tree.root.get_node_or_null("/root/" + name)
	return null


func _tick_round_start() -> void:
	for combatant in _player_party + _enemy_party:
		if not combatant.is_alive:
			continue
		combatant.is_defending = false
		combatant.end_turn()
		## NO DEBT PAYMENT HERE. Live pays it inside the SELECTION loop (BattleManager:1604), where the
		## same branch also forfeits the turn. Paying at round start AND granting the natural +1 below
		## made debt recover at 2 AP/round and cost nothing — @cowir-battle, 2026-09-16.


func _selection_phase() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	_rounds_since_group_attack += 1

	# Try group attack first (cooldown, AP check, formation match)
	var group_action = _try_group_attack()
	if not group_action.is_empty():
		actions.append(group_action)
		# Group attack consumes all players' turns — skip to enemies
		for enemy in _enemy_party:
			if not enemy.is_alive:
				continue
			## Live pays AP debt and FORFEITS the turn in one branch (BattleManager:1604): its `continue`
			## skips the natural gain at :1635 as well as the action. Advance's whole cost model is that
			## debt is the price, so a grind where debt is free grades an Advance-heavy script better than
			## it plays.
			if enemy.current_ap < 0:
				enemy.gain_ap(1)
				_log("%s pays AP debt (now %d) and forfeits the turn" % [enemy.combatant_name, enemy.current_ap])
				continue
			enemy.gain_ap(1)
			var skip = _check_status_skip(enemy)
			if skip != "":
				if skip == "confuse_attack":
					var confused_action = _confused_attack(enemy)
					confused_action["combatant"] = enemy
					confused_action["speed"] = _speed_for(confused_action, enemy)
					actions.append(confused_action)
				continue
			var a = _select_enemy_action(enemy)
			a["combatant"] = enemy
			a["speed"] = _speed_for(a, enemy)
			actions.append(a)
		return actions

	for combatant in _player_party:
		if not combatant.is_alive:
			continue
		## Live pays AP debt and FORFEITS the turn in one branch (BattleManager:1604): its `continue`
		## skips the natural gain at :1635 as well as the action. Advance's whole cost model is that
		## debt is the price, so a grind where debt is free grades an Advance-heavy script better than
		## it plays.
		## ⚠️ DECLARED while measuring this, NOT fixed: live's natural gain is not always 1. Under the
		## `bp_instability` corruption effect it rolls 0/+1/+2 for PARTY members (BattleManager:1630).
		## No CODE site in the autogrind stack reads that key — AutogrindSystem passes `corruption_effects`
		## around as an opaque dict and attaches it to ENEMY data (:645, :1022, :1262); the only key it
		## names is stat_drain. So there is no party-side consumer to extend, and a corrupted AP economy
		## is flat in the grind. (Stated as "no code site" rather than a grep count, because this comment
		## now contains the word and would falsify its own count.)
		##
		## LEFT ALONE for @cowir-battle's reason, which is better than the one I first wrote: the jitter
		## is SYMMETRIC — 0/+1/+2, mean exactly 1 — so modelling it moves the VARIANCE of what autogrind
		## reports and not the EXPECTATION. A build measured over hundreds of battles scores the same and
		## reads noisier: a real cost against no change in the answer. The AP-debt bug above is the
		## opposite and that is why it was fixed — it moved the MEAN, and graded Advance builds better
		## than they play. The discriminator: model it when it moves the expectation, declare it when it
		## only moves the spread. The 45-passive category is the first kind and still outstanding.
		if combatant.current_ap < 0:
			combatant.gain_ap(1)
			_log("%s pays AP debt (now %d) and forfeits the turn" % [combatant.combatant_name, combatant.current_ap])
			continue
		combatant.gain_ap(1)

		# Status effect checks — match BattleManager behavior
		var skip = _check_status_skip(combatant)
		if skip != "":
			if skip == "confuse_attack":
				# Confused: attack random target (ally or enemy)
				var confused_action = _confused_attack(combatant)
				confused_action["combatant"] = combatant
				confused_action["speed"] = _speed_for(confused_action, combatant)
				actions.append(confused_action)
			continue

		var abs_node = _get_autoload("AutobattleSystem")
		var raw: Array[Dictionary] = []
		if abs_node:
			raw = abs_node.execute_grid_autobattle(combatant)
		else:
			raw = [_default_attack_action(combatant, _enemy_party)]

		if raw.size() == 1:
			var a = raw[0].duplicate()
			a["combatant"] = combatant
			a["speed"] = _speed_for(a, combatant)
			actions.append(a)
		elif raw.size() > 1:
			## ASK the live rule, never restate it. BattleManager.billed_ap is declared the one
			## authority ("Every readout must ask this rather than computing `queued` itself") after
			## two UI surfaces each rolled their own subtraction and both misreported a full-bank
			## turn. This resolver was a third: it charged size-1 at EVERY size, so a 3-action
			## Advance cost 2 AP here and 3 in the game it simulates — cheaper automation than
			## manual play, which is the yield tax inverted.
			## The cap is the live rule too: this line restated _apply_full_bank_rule under the comment above.
			var ruled: Array = BattleManager._apply_full_bank_rule(combatant, raw)["actions"]
			## Copied element-wise: the rule returns raw's own typed array today, but one rebuilt untyped would abort here.
			var kept: Array[Dictionary] = []
			for sub in ruled:
				kept.append(sub)
			raw = kept
			var ap_cost: int = BattleManager.billed_ap(combatant.current_ap, raw.size())
			if combatant.can_brave(ap_cost):
				combatant.spend_ap(ap_cost)
				for sub in raw:
					var a = sub.duplicate()
					a["combatant"] = combatant
					a["speed"] = _speed_for(a, combatant)
					actions.append(a)
			else:
				var a = raw[0].duplicate()
				a["combatant"] = combatant
				a["speed"] = _speed_for(a, combatant)
				actions.append(a)

	for enemy in _enemy_party:
		if not enemy.is_alive:
			continue
		## Live pays AP debt and FORFEITS the turn in one branch (BattleManager:1604): its `continue`
		## skips the natural gain at :1635 as well as the action. Advance's whole cost model is that
		## debt is the price, so a grind where debt is free grades an Advance-heavy script better than
		## it plays.
		if enemy.current_ap < 0:
			enemy.gain_ap(1)
			_log("%s pays AP debt (now %d) and forfeits the turn" % [enemy.combatant_name, enemy.current_ap])
			continue
		enemy.gain_ap(1)

		# Status effect checks for enemies too
		var skip = _check_status_skip(enemy)
		if skip != "":
			if skip == "confuse_attack":
				var confused_action = _confused_attack(enemy)
				confused_action["combatant"] = enemy
				confused_action["speed"] = _speed_for(confused_action, enemy)
				actions.append(confused_action)
			continue

		var a = _select_enemy_action(enemy)
		a["combatant"] = enemy
		a["speed"] = _speed_for(a, enemy)
		actions.append(a)

	return actions


func _speed_for(action: Dictionary, combatant) -> int:
	var base = ACTION_SPEEDS.get(action.get("type", "attack"), 5)
	var speed_value: int = base - combatant.speed
	## quick_strike is the only author, is described "always goes first", and the grind sorted it by
	## ordinary speed — so a grinding Ninja's signature move landed mid-queue.
	if _ability_has_priority(str(action.get("ability_id", ""))):
		speed_value -= PRIORITY_OFFSET
	return speed_value


## True when the ability authors `priority` — read at SELECTION time, so it has no executor arm.
func _ability_has_priority(ability_id: String) -> bool:
	if ability_id == "":
		return false
	var js = _get_autoload("JobSystem")
	if not js or not js.has_method("get_ability"):
		return false
	return bool(js.get_ability(ability_id).get("priority", false))


## ═══════════════════════════════════════════════════════════════════════
## GROUP ATTACKS
## ═══════════════════════════════════════════════════════════════════════

func _try_group_attack() -> Dictionary:
	"""Attempt a group attack if conditions are met. Returns action dict or empty."""
	if _rounds_since_group_attack < GROUP_ATTACK_COOLDOWN:
		return {}

	var alive = _player_party.filter(func(c): return c.is_alive)
	if alive.size() < 2:
		return {}

	# Check for formation special first (most powerful)
	var formation = _detect_formation(alive)
	if not formation.is_empty():
		var ap_cost = formation["ap_cost"]
		if alive.all(func(c): return c.current_ap >= ap_cost):
			_rounds_since_group_attack = 0
			return _execute_group_formation(alive, formation)

	# Check for all-out attack (any 2+ alive party, 1 AP each)
	if alive.size() >= 2 and alive.all(func(c): return c.current_ap >= 1):
		# Only use all-out if multiple enemies alive (AoE value)
		var alive_enemies = _enemy_party.filter(func(e): return e.is_alive)
		if alive_enemies.size() >= 2:
			_rounds_since_group_attack = 0
			return _execute_group_physical(alive, "all_out_attack")

	return {}


func _detect_formation(alive_party: Array) -> Dictionary:
	"""Check if party jobs match any formation. Returns best match or empty."""
	var party_jobs: Array = []
	for m in alive_party:
		var job_id = m.job.get("id", "") if m.job else ""
		if job_id != "" and job_id not in party_jobs:
			party_jobs.append(job_id)

	for formation in FORMATIONS:
		if alive_party.size() < formation["min_members"]:
			continue
		var all_present = true
		for req_job in formation["required_jobs"]:
			if req_job not in party_jobs:
				all_present = false
				break
		if all_present:
			return formation
	return {}


## Live's post-fix form (BattleManager `_living_count` / `_group_scale`, cowir-battle 6b89ecf4b): a
## pooled strike scales on the LIVING roster, never the rostered one.
## ⚠️ DEAD CODE IN THIS FILE TODAY, and recorded as such rather than dressed as a repair: both
## callers pass `alive`, filtered one line above in the same frame, and the blade_storm loop damages
## ENEMIES — nothing can kill a participant mid-execution. Live's gap is real because its roster is
## fixed at SELECTION and execution is speed-sorted; this resolver has no such gap.
## 🔑 ALIGNED ANYWAY because the two engines had started computing DIFFERENTLY, and in OPPOSITE
## directions: live pre-fix made the strike stronger when a member died, this file makes it weaker
## (blade_storm CONSUMES a hit on a dead attacker via its `continue`). Two engines disagreeing about
## the SIGN of an error from one authored formation is the failure this resolver exists to prevent.
func _living(participants: Array) -> Array:
	return participants.filter(func(p): return p is Combatant and p.is_alive)


func _execute_group_physical(participants: Array, group_type: String) -> Dictionary:
	"""Execute all-out attack — AoE physical damage to all enemies."""
	var total_power = 0.0
	for p in participants:
		if p is Combatant and p.is_alive:
			p.spend_ap(1)
			total_power += p.get_buffed_stat("attack", p.attack)

	var scale = pow(maxi(1, _living(participants).size()), 1.5)
	var alive_enemies = _enemy_party.filter(func(e): return e.is_alive)

	for enemy in alive_enemies:
		var raw_damage = int(total_power * scale / max(1.0, float(alive_enemies.size())))
		var mitigated = max(1, raw_damage)
		enemy.take_damage(mitigated)
		_log("%s hits %s for %d!" % [group_type, enemy.combatant_name, mitigated])

	_log("GROUP: %s with %d participants!" % [group_type, participants.size()])
	return {"type": "group_done", "combatant": participants[0], "speed": -99}


func _execute_group_formation(participants: Array, formation: Dictionary) -> Dictionary:
	"""Execute a formation special based on party composition."""
	var formation_id = formation["id"]
	var ap_cost = formation["ap_cost"]
	var alive_enemies = _enemy_party.filter(func(e): return e.is_alive)

	for p in participants:
		if p is Combatant and p.is_alive:
			p.spend_ap(ap_cost)

	var scale = pow(maxi(1, _living(participants).size()), 1.5)

	match formation_id:
		"four_heroes":
			var total_power = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_power += (p.get_buffed_stat("attack", p.attack) + p.get_buffed_stat("magic", p.magic)) * 0.5
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_power * scale / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage)
				_log("Four Heroes strikes %s for %d!" % [enemy.combatant_name, damage])
			for p in participants:
				if p is Combatant and p.is_alive:
					p.heal(int(p.max_hp * 0.25))
			_log("FORMATION: Four Heroes — balanced strike + 25% party heal!")

		"arcane_tempest":
			var total_magic = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_magic += p.get_buffed_stat("magic", p.magic)
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_magic * scale / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage, true)
				_log("Arcane Tempest blasts %s for %d!" % [enemy.combatant_name, damage])
			_log("FORMATION: Arcane Tempest — raw magic ignores resistances!")

		"blade_storm":
			## Budget AND selection both from the living roster, mirroring live's post-fix form. Fixing
			## only the budget left a rostered corpse still selectable, and `continue` then CONSUMED
			## the hit — six budgeted, four thrown. My own "was the first instance the only one",
			## failed minutes after writing it down, and caught by the arm's numbers rather than by it
			## going red: 197 vs 154 inside a tolerance I had set too loose.
			var storm_living = _living(participants)
			var hit_count = storm_living.size() * 2
			for _hit in range(hit_count):
				if storm_living.is_empty(): break
				var attacker = storm_living[randi() % storm_living.size()]
				if alive_enemies.is_empty(): break
				var target = alive_enemies[randi() % alive_enemies.size()]
				if not target.is_alive: continue
				var base_dmg = int(attacker.get_buffed_stat("attack", attacker.attack) * 0.7)
				if randf() < 0.3:
					base_dmg = int(base_dmg * 1.5)
				var damage = max(1, base_dmg)
				target.take_damage(damage)
				_log("Blade Storm hits %s for %d!" % [target.combatant_name, damage])
			_log("FORMATION: Blade Storm — %d rapid strikes!" % hit_count)

		"iron_wall":
			for p in participants:
				if p is Combatant and p.is_alive:
					p.add_buff("iron_wall_def", "defense", 1.5, 3)
			var total_atk = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_atk += p.get_buffed_stat("attack", p.attack)
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_atk * scale * 0.6 / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage)
				_log("Iron Wall crushes %s for %d!" % [enemy.combatant_name, damage])
			_log("FORMATION: Iron Wall — DEF +50%% (3 turns) + crushing blow!")

		"shadow_strike":
			var total_atk = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_atk += p.get_buffed_stat("attack", p.attack)
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var full_hp_bonus = 2.0 if enemy.current_hp == enemy.max_hp else 1.0
				var damage = max(1, int(total_atk * scale * full_hp_bonus / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage)
				_log("Shadow Strike hits %s for %d!" % [enemy.combatant_name, damage])
			_log("FORMATION: Shadow Strike — 2x on full HP!")

		"chaos_theory":
			var roll = randf()
			if roll < 0.4:
				var total_power = 0.0
				for p in participants:
					if p is Combatant and p.is_alive:
						total_power += (p.get_buffed_stat("attack", p.attack) + p.get_buffed_stat("magic", p.magic))
				for enemy in alive_enemies:
					if not enemy.is_alive: continue
					var damage = max(1, int(total_power * scale * 1.5 / max(1.0, float(alive_enemies.size()))))
					enemy.take_damage(damage, true)
				_log("FORMATION: Chaos Theory — JACKPOT! Massive damage!")
			elif roll < 0.7:
				for p in participants:
					if p is Combatant and p.is_alive:
						p.add_buff("chaos_atk", "attack", 1.3, 3)
						p.add_buff("chaos_def", "defense", 1.3, 3)
						p.add_buff("chaos_spd", "speed", 1.3, 3)
				_log("FORMATION: Chaos Theory — party buffed! ATK/DEF/SPD +30%%!")
			elif roll < 0.9:
				var total_power = 0.0
				for p in participants:
					if p is Combatant and p.is_alive:
						total_power += p.get_buffed_stat("attack", p.attack)
				for enemy in alive_enemies:
					if not enemy.is_alive: continue
					var damage = max(1, int(total_power * scale * 0.8 / max(1.0, float(alive_enemies.size()))))
					enemy.take_damage(damage)
				for p in participants:
					if p is Combatant and p.is_alive:
						p.heal(int(p.max_hp * 0.15))
				_log("FORMATION: Chaos Theory — moderate damage + party heal!")
			else:
				for p in participants:
					if p is Combatant and p.is_alive:
						p.take_damage(int(p.max_hp * 0.1))
				_log("FORMATION: Chaos Theory — BACKFIRE! Party takes recoil!")

		_:
			return _execute_group_physical(participants, "formation")

	return {"type": "group_done", "combatant": participants[0], "speed": -99}


## Check status effects that skip a combatant's turn.
## Returns "" if no skip, "skip" to skip silently, "confuse_attack" for confusion.
func _check_status_skip(combatant) -> String:
	if combatant.has_status("stun"):
		# Same clock as BattleManager: one skipped action per authored point, then clear.
		var remaining: int = int(combatant.status_durations.get("stun", 1))
		if remaining <= 1:
			combatant.remove_status("stun")
		else:
			combatant.status_durations["stun"] = remaining - 1
		_log("%s is stunned and cannot act!" % combatant.combatant_name)
		return "skip"

	if combatant.has_status("sleep"):
		if randf() < 0.3:
			combatant.remove_status("sleep")
			_log("%s woke up!" % combatant.combatant_name)
			return ""
		else:
			_log("%s is asleep..." % combatant.combatant_name)
			return "skip"

	if combatant.has_status("confuse"):
		if randf() < 0.4:
			combatant.remove_status("confuse")
			_log("%s snapped out of confusion!" % combatant.combatant_name)
			return ""
		else:
			_log("%s is confused and attacks wildly!" % combatant.combatant_name)
			return "confuse_attack"

	if combatant.has_status("fear"):
		if randf() < 0.25:
			combatant.remove_status("fear")
			_log("%s overcame their fear!" % combatant.combatant_name)
		elif randf() < 0.5:
			_log("%s is paralyzed with fear!" % combatant.combatant_name)
			return "skip"

	## puppy_eyes applies charm; live skips the turn unless randf() < 0.35 breaks it. Fear falls through into this check, matching live's order.
	if combatant.has_status("charm"):
		if randf() < 0.35:
			combatant.remove_status("charm")
			_log("%s broke free from charm!" % combatant.combatant_name)
		else:
			_log("%s is charmed and won't act!" % combatant.combatant_name)
			return "skip"

	return ""


## Confused attack: hit a random target from either side.
func _confused_attack(combatant) -> Dictionary:
	var all_alive: Array = []
	for p in _player_party:
		if p.is_alive:
			all_alive.append(p)
	for e in _enemy_party:
		if e.is_alive:
			all_alive.append(e)
	if all_alive.is_empty():
		return {"type": "defer"}
	var target = all_alive[randi() % all_alive.size()]
	return {"type": "attack", "target": target}


func _default_attack_action(combatant, enemies: Array) -> Dictionary:
	var alive = enemies.filter(func(e): return e.is_alive)
	if alive.is_empty():
		return {"type": "defer"}
	alive.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	return {"type": "attack", "target": alive[0]}


func _select_enemy_action(enemy) -> Dictionary:
	var alive_players = _player_party.filter(func(p): return p.is_alive)
	if alive_players.is_empty():
		return {"type": "defer"}

	if enemy.current_hp < enemy.max_hp * 0.30:
		var heal_ability = _find_heal_ability(enemy)
		if heal_ability != "":
			var mp_cost = _get_ability_mp_cost(heal_ability)
			if enemy.current_mp >= mp_cost:
				return {"type": "ability", "ability_id": heal_ability, "targets": [enemy]}

	## A self-heal is not an attack, so taunt does not replace it. Offensive picks lock first.
	var focus = _find_taunter(enemy, alive_players)
	if focus == null:
		alive_players.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		focus = alive_players[0]

	if enemy.current_mp > 0:
		var atk_ability = _find_attack_ability(enemy)
		if atk_ability != "":
			var mp_cost = _get_ability_mp_cost(atk_ability)
			if enemy.current_mp >= mp_cost:
				return {"type": "ability", "ability_id": atk_ability, "targets": [focus]}

	return {"type": "attack", "target": focus}


## Twin of BattleManager._find_taunter. provoke writes `taunted_<caster>` onto the victim and live's
## _choose_target locks the victim's next offensive action onto that caster. The grind wrote the key
## and still picked lowest HP, so a shipped Provoke template did nothing in a grind. A dead or
## absent name falls through to the next status, then to the ordinary pick.
func _find_taunter(attacker, targets: Array):
	if attacker == null or not is_instance_valid(attacker):
		return null
	if not ("status_effects" in attacker):
		return null
	for status in attacker.status_effects:
		if typeof(status) != TYPE_STRING:
			continue
		if not status.begins_with("taunted_"):
			continue
		var taunter_name: String = status.substr(len("taunted_"))
		for t in targets:
			if is_instance_valid(t) and t.is_alive and t.combatant_name == taunter_name:
				return t
	return null


func _find_heal_ability(combatant) -> String:
	var js = _get_autoload("JobSystem")
	if not js:
		return ""
	for ability_id in combatant.learned_abilities:
		var ability = js.get_ability(ability_id) if js.has_method("get_ability") else {}
		# `type` is the field abilities author (289/289); `category` is authored by NONE, so this read was constant "" and no enemy ever healed in a headless battle.
		## The `category` fallback is orphaned — 0 of 289 in abilities.json and 0 in JobSystem's
		## hardcoded table author it; all 289 author `type`. Harmless to keep and safe to drop,
		## unlike the `power` inversion below where the FALLBACK is the live read. Same three
		## sites here (:704 :718 :1121); stat_modifier/modifier in BattleManager IS real (50/7),
		## which is why these are indistinguishable by eye.
		if str(ability.get("type", ability.get("category", ""))) == "healing":
			return ability_id
	return ""


func _find_attack_ability(combatant) -> String:
	var js = _get_autoload("JobSystem")
	if not js:
		return ""
	var best_id = ""
	var best_power = 0.0
	for ability_id in combatant.learned_abilities:
		var ability = js.get_ability(ability_id) if js.has_method("get_ability") else {}
		# Both keys were dead: `category` authored 0/289 (the field is `type`) and `power` 0/289 (it is `damage_multiplier`), so the guard never passed and this returned "" on every call — enemies fell through to a basic attack for the whole battle.
		var cat := str(ability.get("type", ability.get("category", "")))
		if cat in ["magic", "physical"]:
			## ⛔ INVERTED: `power` is authored by NOTHING — 0 of 289 in abilities.json and 0 in
			## JobSystem._create_default_abilities. `damage_multiplier` carries all 161. The fallback
			## is the ONLY live read; deleting it as legacy zeroes every damage number in this engine.
			## BattleManager.estimate_ability_breakdown found this first and fixed its own site; it
			## also divides `power` by 10, so the four sites disagree on SCALE as well as order.
			var power := float(ability.get("power", ability.get("damage_multiplier", 0.0)))
			if power > best_power:
				best_power = power
				best_id = ability_id
	return best_id


func _get_ability_mp_cost(ability_id: String) -> int:
	var js = _get_autoload("JobSystem")
	if not js:
		return 0
	var ability = js.get_ability(ability_id) if js.has_method("get_ability") else {}
	return ability.get("mp_cost", 0)


func _execute_action(action: Dictionary) -> void:
	var combatant = action.get("combatant")
	if not combatant or not combatant.is_alive:
		return

	match action.get("type", "attack"):
		"attack":
			var target = action.get("target")
			if target and target.is_alive:
				var dmg = _resolve_attack(combatant, target)
				_log("%s attacks %s for %d" % [combatant.combatant_name, target.combatant_name, dmg])

		"ability":
			var ability_id = action.get("ability_id", "")
			var targets = action.get("targets", [])
			if ability_id != "" and targets.size() > 0:
				_resolve_ability(combatant, ability_id, targets)

		"item":
			var item_id = action.get("item_id", "")
			var targets = action.get("targets", [])
			if item_id != "" and targets.size() > 0:
				_resolve_item(combatant, item_id, targets[0])

		"defer":
			combatant.is_defending = true
			_log("%s defers" % combatant.combatant_name)

		"group_done":
			pass  # Already executed during selection phase


## Twin of Combatant._has_equipment_resistance. PRESENCE across the three slots, not a sum: live
## tests `> 0.0` and multiplies by a flat 0.5, and both authoring pieces carry `true`, so a sum
## would be a second formula that agrees only by accident of the authored values.
##
## ⛔ WHY THIS ARRIVED LATE, recorded because the reason is worse than the omission: this lane
## MEASURED live's callers of take_elemental_damage, reported "only _tick_summon_followup", and
## DECLARED both resistance keys non-gaps in the gear census on that basis. There are two callers.
## The magic executor is the other one. The census then counted those two as "declared" and reached
## zero ignored — a closed census resting on a wrong measurement.
func _has_equipment_resistance(combatant, element: String) -> bool:
	if combatant == null or not is_instance_valid(combatant) or element == "":
		return false
	var es = _get_autoload("EquipmentSystem")
	if es == null:
		return false
	var key: String = element + "_resistance"
	for slot in [["equipped_weapon", "get_weapon"], ["equipped_armor", "get_armor"], ["equipped_accessory", "get_accessory"]]:
		var field: String = str(slot[0])
		var getter: String = str(slot[1])
		if not (field in combatant) or str(combatant.get(field)) == "":
			continue
		if not es.has_method(getter):
			continue
		var piece: Dictionary = es.call(getter, str(combatant.get(field)))
		var se: Variant = piece.get("special_effects", {})
		if se is Dictionary and float((se as Dictionary).get(key, 0.0)) > 0.0:
			return true
	return false


## Twin of BattleManager._sum_equipment_special_effect (:5434). Walks the three equipment slots and
## sums the requested key, returning 0.0 cleanly when the combatant has no gear, the autoload is
## absent, or the key is unauthored. A grinding party's gear did NOTHING before this: the resolver
## read 0 of the 15 keys equipment.json authors, so the grind reported survivability and rewards for
## a party wearing no equipment effects at all.
## ⚠️ Four of the fifteen keys are read in live by CONSTRUCTION (element + "_damage_bonus"), so a
## literal census of either engine under-reports them — @cowir-battle's third shape, which is why
## this helper takes the key as an argument rather than matching names.
func _sum_equipment_special_effect(combatant, key: String) -> float:
	if combatant == null or not is_instance_valid(combatant):
		return 0.0
	var es = _get_autoload("EquipmentSystem")
	if es == null:
		return 0.0
	var total: float = 0.0
	for slot in [["equipped_weapon", "get_weapon"], ["equipped_armor", "get_armor"], ["equipped_accessory", "get_accessory"]]:
		var field: String = str(slot[0])
		var getter: String = str(slot[1])
		if not (field in combatant) or str(combatant.get(field)) == "":
			continue
		if not es.has_method(getter):
			continue
		var piece: Dictionary = es.call(getter, str(combatant.get(field)))
		var se: Variant = piece.get("special_effects", {})
		if se is Dictionary:
			total += float((se as Dictionary).get(key, 0.0))
	return total


func _resolve_attack(attacker, target) -> int:
	if not target or not target.is_alive:
		return 0

	## peace_sign applies pacify. Live refuses the swing and leaves the status; the grind was hitting anyway.
	if attacker.has_status("pacify"):
		_log("%s is pacified and cannot attack!" % attacker.combatant_name)
		return 0

	## BLIND: the live engine adds 0.40 to the miss rate (BattleManager's attack miss check) and this
	## resolver applied the status and then ignored it — the Bard's Riff inflicts blind on a 70% roll,
	## so his signature disruption did nothing in a grind while doing its job in a live fight.
	## INVISIBLE and SHADOW_STEP on the TARGET: the live engine misses outright and the status falls
	## off on the swing — "the swing reveals them" (_target_dodges_physical). Both were applied in a
	## grind and read by nobody, the same shape blind had, and both are cast by SHIPPED presets:
	## ninja_defensive spends 12 MP on vanish, ninja_balanced and ninja_aggressive 8 on shadow_step.
	## Checked before the miss ROLL rather than folded into it, because live does not roll at all.
	## ⚠️ Written as two LITERAL has_status calls rather than a loop over a list, deliberately. The
	## parity guard derives its ignored-status set by scanning both engines for has_status("…") and a
	## loop variable is invisible to it — the first draft of this fix used one, and the guard went on
	## reporting `invisible` as ignored while the code honoured it. A composed writer under a literal
	## scan is the exact shape that guard exists to catch, so the implementation reads the way the
	## measurement does.
	if _target_dodges_physical(attacker, target):
		return 0
	## null_entity authors immunities=["physical"] and is in the abstract grind pool. Live returns
	## here, before the miss roll and before barrier, so a swing deals 0 and does not break the ward.
	if _monster_immune_to_category(target, "physical"):
		_log("%s is immune to physical — %s's attack passes through!" % [target.combatant_name, attacker.combatant_name])
		return 0

	var base_miss: float = 0.10
	if attacker.has_status("blind"):
		base_miss += 0.40
	var miss_chance = max(0.02, min(0.60, base_miss - (attacker.speed - target.speed) * 0.05))
	if randf() < miss_chance:
		_log("%s misses %s!" % [attacker.combatant_name, target.combatant_name])
		return 0

	var damage = float(attacker.get_buffed_stat("attack", attacker.attack))
	## A feared swing that was not skipped still happens, at half. Live halves the base stat before variance.
	if attacker.has_status("fear"):
		damage = float(int(damage * 0.5))
	## ONE-SHOT, consumed as live consumes it (BattleManager:4374-4377) — a charged strike pays off
	## once, not on every swing for the rest of the battle.
	damage *= _take_charged_multiplier(attacker)
	damage *= randf_range(0.85, 1.15)

	## SHADOW_STEP on the ATTACKER: a guaranteed crit live (_calculate_crit_chance returns 1.0 up
	## front). The Ninja's whole setup move is "step into the shadows so the next swing crits", and
	## in a grind it bought nothing at all.
	## equipment critical_bonus, clamped at 0.50 on its own and then folded in UNDER the same total
	## cap live applies (BattleManager:5423 caps base+speed+passive+equip+buff at 0.50) — added after
	## the min would let gear exceed a ceiling live never lets it cross.
	var equip_crit: float = clampf(_sum_equipment_special_effect(attacker, "critical_bonus"), 0.0, 0.50)
	var crit_chance = min(0.50, 0.05 + attacker.speed * 0.01 + equip_crit)
	var is_crit = randf() < crit_chance
	if attacker.has_status("shadow_step"):
		is_crit = true
	if is_crit:
		damage *= 1.5
		_log("Critical hit!")

	## Pre-mitigation and BEFORE the line below, mirroring live's order in _execute_attack.
	damage = float(_apply_lens_execute_bonus(attacker, target, int(damage)))

	## returned_sword's Familiar Weight, mirroring BattleManager:4498 — applied to the PRE-mitigation
	## damage, exactly where live applies it, because this file's defense formula is quadratic and
	## scaling `actual` instead would give a different number for the same gear.
	damage = float(_apply_familiar_weight_bonus(attacker, target, int(damage)))

	## guardian_wall nullifies this one swing and breaks. Checked after the number exists, before
	## take_damage, and the on-hit riders below do not run — same place live returns.
	if target.has_status("barrier"):
		target.remove_status("barrier")
		_log("%s's Barrier absorbs the attack!" % target.combatant_name)
		return 0

	## reflect and physical_reflect bounce the pre-defense swing onto the attacker. Live does not
	## remove them here; the duration tick does. A spell is not bounced — that is prismatic_reflect.
	if target.has_status("reflect") or target.has_status("physical_reflect"):
		var bounced: int = attacker.take_damage(int(damage), false)
		_log("%s's Reflect bounces %d damage back to %s!" % [target.combatant_name, bounced, attacker.combatant_name])
		return 0

	var def_val = float(target.get_buffed_stat("defense", target.defense))
	# Guard divisor (mirrors Combatant.take_damage). attack 0 + defense 0
	# combinations are reachable: get_buffed_stat returns 0 for base 0
	# (the maxi(1, …) clamp only applies when base > 0), so a base-0
	# attack stat × base-0 defense produces a 0/0 NaN that int() casts
	# to a sentinel — silent garbage damage in autogrind sims.
	var denom = maxf(1.0, damage + def_val)
	var actual = int((damage * damage) / denom)
	actual = max(1, actual)
	if target.is_defending:
		actual = actual / 2

	var dealt: int = target.take_damage(actual)
	## the_absence authors heals_from_damage. Live heals from the number that landed, after the hit.
	_maybe_heal_from_damage(target, dealt, "")
	## Live calls this from _execute_attack ONLY — the BASIC attack. Deliberately NOT added to
	## _resolve_attack_with_power, which is this file's ability-damage path: an ability that happens to
	## deal physical damage does not proc a weapon's on-hit status in live, and wiring it there would
	## be the axis-2 error this lane's ledger exists to catch — a key read on the wrong executor.
	_apply_equipment_on_hit_status(attacker, target)
	return actual


## Twin of BattleManager._apply_familiar_weight_bonus (:3120). returned_sword's "Familiar Weight":
## +10% damage against any enemy the party has SEEN or DEFEATED, or that lives in the item's own
## static ledger. Live applies it from TWO sites — _execute_attack (:4498) and
## _execute_physical_ability (:4915) — so this file does too.
##
## 🔑 THE MOST GRIND-RELEVANT GEAR EFFECT IN THE GAME, and it was invisible to this lane's gear
## census because HALF OF IT LIVES OUTSIDE `special_effects`: the bonus is a special_effect, the seed
## list is a TOP-LEVEL equipment field. A census keyed on special_effects could only ever see one
## half. Found by applying @cowir-battle's "the predicate is a corpus" to my own census.
##
## ⚠️ A grind fills the bestiary faster than any other play, so `bestiary_hit` is true of nearly
## everything after the first few battles — this is worth MORE in a grind than in a normal fight,
## which is the opposite of how it reads from the item description.
func _apply_familiar_weight_bonus(attacker, target, damage: int) -> int:
	if attacker == null or target == null or damage <= 0:
		return damage
	var bonus: float = _sum_equipment_special_effect(attacker, "familiar_weight_bonus")
	if bonus <= 0.0:
		return damage
	if not target.has_method("get_meta") or not target.has_meta("monster_type"):
		return damage
	var mtype: String = str(target.get_meta("monster_type", ""))
	if mtype == "":
		return damage
	var bs = _get_autoload("BestiarySystem")
	var bestiary_hit: bool = false
	if bs and bs.has_method("is_seen") and bs.has_method("is_defeated"):
		bestiary_hit = bs.is_seen(mtype) or bs.is_defeated(mtype)
	var seed_hit: bool = mtype in _familiar_weight_static_seed(attacker)
	if not (bestiary_hit or seed_hit):
		return damage
	return int(round(damage * (1.0 + bonus)))


## Union of the familiar_weight_static_seed arrays on all three slots, mirroring :3144. A TOP-LEVEL
## equipment field rather than a special_effect, which is exactly why the gear census missed it.
func _familiar_weight_static_seed(combatant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if combatant == null:
		return out
	var es = _get_autoload("EquipmentSystem")
	if es == null:
		return out
	for slot in [["equipped_weapon", "get_weapon"], ["equipped_armor", "get_armor"], ["equipped_accessory", "get_accessory"]]:
		var field: String = str(slot[0])
		if not (field in combatant):
			continue
		var eid: String = str(combatant.get(field))
		if eid == "" or not es.has_method(str(slot[1])):
			continue
		var entry: Dictionary = es.call(str(slot[1]), eid)
		var raw: Variant = entry.get("familiar_weight_static_seed", [])
		if not (raw is Array):
			continue
		for m in (raw as Array):
			var mstr: String = str(m)
			if mstr != "" and not (mstr in out):
				out.append(mstr)
	return out


## Twin of BattleManager._monster_immune_to_category. monsters.json `immunities` is a damage class,
## not an element: null_entity authors ["physical"] and live deals 0 on a swing and on a physical
## ability. Not inside take_damage — a group attack calls that on both engines and neither one
## asks, so a Limit Break still lands.
func _monster_immune_to_category(target, category: String) -> bool:
	if target == null or not is_instance_valid(target) or category == "":
		return false
	if not target.has_method("get_meta") or not target.has_meta("monster_type"):
		return false
	var mtype := str(target.get_meta("monster_type", ""))
	if mtype == "":
		return false
	var enc = _get_autoload("EncounterSystem")
	if enc == null or not ("monster_database" in enc):
		return false
	var db: Variant = enc.monster_database
	if not (db is Dictionary) or not (db as Dictionary).has(mtype):
		return false
	var immunities: Variant = (db[mtype] as Dictionary).get("immunities", [])
	if not (immunities is Array):
		return false
	return category in immunities


## Twin of BattleManager._monster_phase_out_check. null_entity authors phase_out at 20% and sits in
## the abstract pool the grind draws. Live misses the swing and the spell; a grind always connected.
## Not consumed, and not inside take_damage — a group attack calls that on both engines and neither asks.
func _monster_phase_out_check(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method("get_meta"):
		return false
	var mtype := str(target.get_meta("monster_type", ""))
	if mtype == "":
		return false
	var enc = _get_autoload("EncounterSystem")
	if enc == null or not ("monster_database" in enc):
		return false
	var db: Variant = enc.monster_database
	if not (db is Dictionary) or not (db as Dictionary).has(mtype):
		return false
	var sb: Variant = (db[mtype] as Dictionary).get("special_behavior", {})
	if not (sb is Dictionary):
		return false
	var behavior := sb as Dictionary
	if not bool(behavior.get("phase_out", false)):
		return false
	var chance: float = clampf(float(behavior.get("phase_out_chance", 0.2)), 0.0, 1.0)
	return randf() < chance


## Twin of BattleManager._target_dodges_physical (:9046), and EXTRACTED for live's own reason: live
## calls it from TWO sites — _execute_attack (:4391) and _execute_physical_ability (:4853) — so a
## physical ABILITY can be dodged exactly as a basic swing can. This resolver had the logic inline in
## _resolve_attack and the physical-ability arm had NO dodge check at all, so a grinding party's
## power_strike, cleave and slash could never be evaded while the real game's can.
##
## Evasion status (0.6, not consumed) and phase_out both live here, so a physical ability and a basic
## swing miss for the same reasons. Passive evasion is still absent — that is the passives ruling.
##
## ⚠️ The speed-based miss chance stays in _resolve_attack and is deliberately NOT moved in. Live
## keeps it out of this function too: an ability is DODGED, never fumbled — a physical ability that
## inherited the basic attack's speed-miss would be harder to land in the grind than in the game.
func _target_dodges_physical(attacker, target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	## ⚠️ LITERAL has_status calls rather than a loop, deliberately. The parity guard derives its
	## ignored-status set by scanning both engines for has_status("…"), and a loop variable is
	## invisible to it — the first draft of this fix used one, and the guard went on reporting
	## `invisible` as ignored while the code honoured it.
	if target.has_status("invisible"):
		target.remove_status("invisible")
		_log("%s strikes thin air — %s was invisible!" % [attacker.combatant_name, target.combatant_name])
		return true
	if target.has_status("shadow_step"):
		target.remove_status("shadow_step")
		_log("%s strikes thin air — %s had stepped into shadow!" % [attacker.combatant_name, target.combatant_name])
		return true
	## Burrow's evasion is a 60% physical dodge in live and was only a badge in the grind. Not consumed on a swing — duration ticks it off.
	if target.has_status("evasion") and randf() < 0.6:
		_log("%s evades %s's attack!" % [target.combatant_name, attacker.combatant_name])
		return true
	## After the evasion status and before gear, matching live: a phase-out is a miss, not a dodge
	## that spends a status. null_entity authors 0.2. A monster without the flag never rolls.
	if _monster_phase_out_check(target):
		_log("%s phases out — %s's attack passes through nothing!" % [target.combatant_name, attacker.combatant_name])
		return true
	## equipment evasion_bonus is a SEPARATE roll in live (:9106), not folded into the miss chance —
	## elven_cloak plus a passive gives two independent chances to dodge. Same clamp.
	var equip_dodge: float = clampf(_sum_equipment_special_effect(target, "evasion_bonus"), 0.0, 0.50)
	if equip_dodge > 0.0 and randf() < equip_dodge:
		_log("%s evades %s's attack!" % [target.combatant_name, attacker.combatant_name])
		return true
	return false


## Twin of BattleManager.ON_HIT_STATUSES (:4574) — same keys, same statuses, same durations.
## poison_dagger authors poison_chance 0.25, sleep_dagger authors sleep_chance 0.20, and a grinding
## party's daggers gave their stat bonus while the headline gimmick did nothing.
## Table-driven for live's reason rather than mine: a new on-hit chance drops in by extending the
## const, and the two engines stay comparable entry-for-entry instead of by reading two loops.
const ON_HIT_STATUSES: Array = [
	{"key": "poison_chance", "status": "poison", "duration": 3},
	{"key": "sleep_chance", "status": "sleep", "duration": 2},
]


## Mirrors BattleManager._apply_equipment_on_hit_status:4581, called AFTER the damage lands so the
## status piles on the hit. Each chance rolls independently, and the TARGET's status_resistance is
## subtracted here exactly as live subtracts it — the same clamp-the-RESULT form, never a cap on the
## resist itself, which live applies nowhere.
func _apply_equipment_on_hit_status(attacker, target) -> void:
	if attacker == null or target == null or not is_instance_valid(target) or not target.is_alive:
		return
	for entry in ON_HIT_STATUSES:
		var chance: float = _sum_equipment_special_effect(attacker, str(entry["key"]))
		if chance <= 0.0:
			continue
		var resist: float = _sum_equipment_special_effect(target, "status_resistance")
		var effective: float = clampf(chance - resist, 0.0, 1.0)
		if effective <= 0.0 or randf() >= effective:
			continue
		target.add_status(str(entry["status"]), int(entry["duration"]))
		_log("%s inflicts %s on %s (on-hit)" % [attacker.combatant_name, str(entry["status"]), target.combatant_name])


## Canonical effect -> the STAT it moves, mirroring BattleManager's own arm names.
##
## ⛔ THE MAGNITUDE IS NOT HERE, AND USED TO BE. This table returned [stat, modifier] with ONE
## hardcoded number per effect — every down 0.75, every up 1.5 — and the caller OVERWROTE the
## authored value it had already read one line earlier. abilities.json authors nine distinct
## magnitudes across these effects, so 25 of the 30 support abilities that reach this function
## ground at the wrong strength: shell_guard "massively boosting defense" at an authored 2.5 was
## 1.5 (-40%), web_shot 0.5 was 0.75, and battle_hymn's 1.25 was buffed UP to 1.5. The grind pulled
## every authored value toward one number, making the strong ones weak and the weak ones strong.
## @cowir-battle found it; the same hardcode-under-a-reader shape as this file's own MP-drain bug.
##
## ⚠️ magic_up / speed_up / magic_down are mapped here and LIVE HAS NO ARM FOR THEM (its 45-arm
## match has attack/defense/magic_defense/volatility only). Nothing authors them on a support-typed
## ability today, so the divergence is unreachable rather than fixed — pinned by an arm that reds if
## anyone authors one, because the grind would buff where the real game push_warnings and fizzles.
## ⚠️ ONE ARM PER EFFECT, not `"attack_up", "attack_down":` grouped — deliberately, and the same
## reason `_target_dodges_physical` spells out two literal has_status calls. The inert-ally census
## DERIVES this map from this function's source with `"([a-z_]+)":\s*return`, so a grouped arm hides
## every name but the last: grouping these ten made six of them vanish from that census and turned
## its control red. The implementation reads the way the measurement reads.
func _effect_to_stat(effect: String) -> String:
	match effect:
		"attack_up": return "attack"
		"defense_up": return "defense"
		"magic_up": return "magic"
		"speed_up": return "speed"
		"magic_defense_up": return "magic_defense"
		"attack_down": return "attack"
		"defense_down": return "defense"
		"magic_down": return "magic"
		"speed_down": return "speed"
		## magic_defense_down mirrors live's Soul Sap arm. Unreachable from HERE today (soul_wail is
		## magic-typed), but its absence made this table the only stat map missing one of live's.
		"magic_defense_down": return "magic_defense"
		"volatility_down": return "volatility"
	return ""


## Same side = both in the player party, or neither. Used to refuse friendly fire from an
## ability type this resolver does not model.
func _is_same_side(a, b) -> bool:
	return (a in _player_party) == (b in _player_party)


func _resolve_ability(caster, ability_id: String, targets: Array) -> void:
	var js = _get_autoload("JobSystem")
	var ability: Dictionary = {}
	if js and js.has_method("get_ability"):
		ability = js.get_ability(ability_id)

	## An id JobSystem cannot resolve returns {}, and `type` then defaults to "magic" below — so a
	## typo'd or removed ability in an autobattle script DEALT MAGIC DAMAGE, to an ally when the
	## script aimed it at one. Found by a census control asserting an unknown id is a no-op.
	## You cannot resolve what you cannot read: do nothing, and do not charge MP for it.
	if ability.is_empty():
		_log("%s: unknown ability '%s' — no effect" % [caster.combatant_name, ability_id])
		return

	## ⛔ THE GRIND IGNORED SILENCE ENTIRELY — this file never called JobSystem.can_use_ability, so a
	## silenced character kept casting while live refuses at BattleManager:4669. Mirrors live exactly,
	## including that the TURN IS CONSUMED and no MP is spent: live logs and returns before its own
	## spend. Checked here rather than at selection because this is the one point every cast passes.
	if caster.has_status("silence"):
		_log("%s is silenced — %s won't come out" % [caster.combatant_name, ability_id])
		return

	var mp_cost = ability.get("mp_cost", 5)
	if not caster.spend_mp(mp_cost):
		_log("%s has no MP for %s" % [caster.combatant_name, ability_id])
		return

	## Tick 393: dispatch on `type` (the canonical abilities.json
	## schema field) instead of `category` (which no ability authors).
	## Pre-fix `ability.get("category", "magic")` always returned the
	## "magic" default for every ability, so the `match category:` arm
	## always fired the magic-damage branch — heal abilities dealt
	## magic damage to the target instead of healing, support abilities
	## did nothing useful, etc. Major divergence between live combat
	## and autogrind simulation that silently corrupted reward
	## calculations whenever a non-physical-non-magic ability fired.
	##
	## Also accept `damage_multiplier` as a power fallback so abilities
	## that author the canonical magic-shape field aren't reading the
	## default 1.0 (which would silently nerf eidolon casts and similar).
	var category = ability.get("type", ability.get("category", "magic"))
	## A healing ability that heals OVER TIME reaches the wrong arm otherwise. `regenerate` authors
	## `effect: regen` with `regen_per_turn: 40` and NO heal_amount, so the healing arm's fallback healed
	## magic x power ONCE and ticked nothing. Live routes exactly this shape to its support executor
	## (cowir-battle dcfb2158). Re-pointed rather than copied: the support arm below already owns what
	## an `effect` means, and duplicating it here is how two definitions of "regen" start to drift.
	if category == "healing" and str(ability.get("effect", "")) != "" and int(ability.get("heal_amount", 0)) <= 0:
		category = "support"
	var power = ability.get("power", ability.get("damage_multiplier", 1.0))
	var element = ability.get("element", "")
	## Live runs the damage step `hits` times (BattleManager:4854) for the 5 abilities that author it —
	## all monster-side, all drawn from the same pools the grind draws from, so the grind was taking a
	## third of the authored damage from them. Third instance of this file's field-mismatch class.
	var hits: int = max(1, int(ability.get("hits", 1)))
	## Live heals the caster for this share of the damage it actually dealt (BattleManager:5121). Four
	## POOLED monsters drain — specter, pipe_phantom, shadow_knight, bone_warden — and the Necromancer's
	## drain_life is a player build. Neither side healed in the grind.
	var drain_pct: float = float(ability.get("drain_percentage", 0))
	## Multiplies the POWER, so it must land before either damage arm reads it.
	power = float(power) * _missing_hp_multiplier(caster, ability)

	match category:
		"healing":
			for target in targets:
				if target and target.is_alive:
					## `heal_amount` is what healing abilities author (6/7; regenerate is a regen
					## effect with none) — `power`/`damage_multiplier` are authored by 0 of 7, so
					## this read the 1.0 default and healed magic*1 instead of the authored value.
					## cure at magic 20: 20 HP here vs 1300 live. Same field-mismatch class the two
					## comments above document, on the arm nobody revisited. Formula mirrors
					## BattleManager:5227 so headless and live agree.
					var authored = int(ability.get("heal_amount", 0))
					var heal_amount = int(authored * (1.0 + caster.get_buffed_stat("magic", caster.magic) / 20.0)) if authored > 0 else int(caster.get_buffed_stat("magic", caster.magic) * power)
					heal_amount = max(1, heal_amount)
					var healed = target.heal(heal_amount)
					_log("%s heals %s for %d" % [caster.combatant_name, target.combatant_name, healed])

		"magic":
			## Same gate as the basic swing, after the MP spend above — live charges the spell and then fizzles it.
			if caster.has_status("pacify"):
				_log("%s is pacified — the spell fizzles!" % caster.combatant_name)
				return
			## BEFORE the loop and ONCE, mirroring BattleManager:4969 — an AoE gets the boosted
			## multiplier on every target and the charge clears a single time, not per target.
			power = float(power) * _take_charged_multiplier(caster)
			## Accumulated ACROSS the cast, because live's recoil is proportional to the whole volley
			## (BattleManager:4981/5172) — stack_overflow hits all_enemies and pays 20% of the total.
			var total_for_recoil: int = 0
			for target in targets:
				if target and target.is_alive:
					## Before Magic Block, matching live: a phase-out misses the spell and leaves the ward up.
					if _monster_phase_out_check(target):
						_log("%s phases out — %s's spell finds nothing!" % [target.combatant_name, caster.combatant_name])
						continue
					## access_denied cancels this one spell and breaks, before the roll. A swing is not a spell.
					if target.has_status("magic_block"):
						target.remove_status("magic_block")
						_log("%s's Magic Block cancels the spell!" % target.combatant_name)
						continue
					var base_dmg = int(caster.get_buffed_stat("magic", caster.magic) * power)
					## Doubles, mirroring BattleManager:5054 — live's own comment calls it "a rough
					## compensation for take_damage's defense formula" rather than a true-damage path, and
					## the grind must compensate the same way or phantom_byte lands at half strength here.
					if bool(ability.get("ignores_defense", false)):
						base_dmg *= 2
					## Rolled BEFORE the elemental multiplier, mirroring BattleManager:5013-5015 — live
					## applies it to `damage` ahead of the terrain/element path, and the order changes the
					## spread once a weakness or resistance is in play. type_error authors 2.0, so its roll
					## spans [0, 2x] where every other spell sits near 1.0; forgotten_variable (POOLED)
					## casts it, and a grind met a predictable attacker where the real game met a swingy one.
					var variance: float = float(ability.get("damage_variance", 0.0))
					if variance > 0.0:
						base_dmg = int(base_dmg * randf_range(0.0, variance))
					## Before terrain, mirroring live's order in _execute_magic_ability.
					base_dmg = _apply_lens_execute_bonus(caster, target, base_dmg)
					## TERRAIN + WEATHER, mirroring BattleManager:5274-5278 — live's ONLY application of
					## either, in its magic executor, right here after the variance roll. The grind was
					## handed a terrain by GameLoop and never read it: a cave grind fired fire at full
					## strength while the same party in the same cave took 0.75x one speed setting away.
					## Asked with an explicit terrain so live's cached battle state is never consulted.
					if element != "":
						base_dmg = int(base_dmg
							* BattleManager.get_terrain_damage_modifier(element, terrain)
							* BattleManager.get_weather_damage_modifier(element, weather))
					## Equipment element damage bonus, mirroring BattleManager:5089. Live builds the key by
					## CONCATENATION — `element + "_damage_bonus"` — which is why a literal census of either
					## engine reports flame_sword's 1.5 as unread: four of the five keys occur ZERO times in
					## src/. @cowir-battle's derived-key shape, and the reason I retracted a wrong "inert"
					## finding about exactly these five last night.
					## ⚠️ MULTIPLIES, it does not add: live writes `multiplier *= elem_bonus`, so flame_sword's
					## 1.5 is a 1.5x scale rather than +150%. Skipped for element-less abilities, matching
					## live's "no fire scroll, no fire bonus" intent.
					if element != "":
						var elem_bonus: float = _sum_equipment_special_effect(caster, element + "_damage_bonus")
						if elem_bonus > 0.0:
							base_dmg = int(base_dmg * elem_bonus)
					## Same one-hit ward as the basic swing. A blocked spell does not reach elemental math.
					if target.has_status("barrier"):
						target.remove_status("barrier")
						_log("%s's Barrier absorbs the spell!" % target.combatant_name)
						continue
					## prismatic_reflect bounces this spell onto the caster and stays up. Live sends it
					## to the caster, not to a random combatant, and does not bounce a physical swing.
					if target.has_status("prismatic_reflect"):
						var bounced: int = caster.take_damage(base_dmg, true)
						_log("%s's Prismatic Reflect bounces %d magic damage to %s!" % [target.combatant_name, bounced, caster.combatant_name])
						continue
					var elem_mod = target.calculate_elemental_modifier(element) if element != "" else 1.0
					## ⛔ EQUIPMENT RESISTANCE, mirroring Combatant.take_elemental_damage:  live's magic
					## arm routes through that function (BattleManager:5270) and it does
					## `elemental_mod *= 0.5` when the target's gear names <element>_resistance. This arm
					## called calculate_elemental_modifier alone, so dragon_mail and bone_armor did
					## nothing in a grind while halving the same hit in a real fight.
					## ⚠️ PRESENCE, NOT MAGNITUDE — live checks `> 0.0` on any slot and applies a flat
					## 0.5. Both pieces author `true`, so summing the value would be a different
					## formula that happens to agree today.
					if element != "" and _has_equipment_resistance(target, element):
						elem_mod *= 0.5
					var actual = int(base_dmg * elem_mod)
					actual = max(1, actual)
					if target.is_defending:
						actual = actual / 2
					## ONE HIT, deliberately. Live reads `hits` only in _execute_physical_ability, so
					## temporal_strike (magic, hits=2) strikes ONCE in the real game. I looped here in
					## 04f2b2f8 and the grind hit harder than the game it simulates — @cowir-battle 2d14d92d.
					var dealt: int = target.take_damage(actual, true)
					_drain_to(caster, dealt, drain_pct, ability_id)
					## PER TARGET and gated on damage landing, mirroring BattleManager:5085-5090 — so
					## memory_drain (all_enemies) stacks its restore across the party exactly as live does.
					_siphon_mp(caster, ability, dealt, ability_id)
					## Same conversion as the basic swing. Holy skips inside the helper, matching live.
					_maybe_heal_from_damage(target, dealt, str(element))
					_log("%s casts %s on %s for %d" % [caster.combatant_name, ability_id, target.combatant_name, dealt])
					total_for_recoil += dealt
					_maybe_inflict_status(caster, target, ability, ability_id)
			_recoil_to(caster, ability, total_for_recoil, ability_id)

		"physical":
			## MP is already spent. Live still rolls mug's steal after the fizzle, because that roll sits outside the executor.
			var pacified_strike: bool = bool(caster.has_status("pacify"))
			if pacified_strike:
				_log("%s is pacified and cannot strike!" % caster.combatant_name)
			for target in targets:
				if pacified_strike:
					break
				if target and target.is_alive:
					## Live gates the dodge on `ignores_evasion` and calls _target_dodges_physical here
					## (:4853) exactly as it does for a basic swing. Without this the grind's physical
					## abilities could NEVER be evaded — invisible, shadow_step and an elven_cloak all
					## worked against an ordinary attack and did nothing against power_strike.
					if not bool(ability.get("ignores_evasion", false)):
						if _target_dodges_physical(caster, target):
							continue
					## Same gate as the basic swing. A physical ability is not a spell, so magic still lands.
					if _monster_immune_to_category(target, "physical"):
						_log("%s is immune to physical — %s's strike passes through!" % [target.combatant_name, caster.combatant_name])
						continue
					## Same half as the basic swing, on the base stat before power. Magic is not halved in live.
					var scaled: int = _scaled_base(caster, ability)
					if caster.has_status("fear"):
						scaled = int(scaled * 0.5)
					var base_dmg = int(scaled * power)
					## Second call site, mirroring BattleManager:4915. Live applies Familiar Weight to a
					## physical ABILITY's damage as well as a basic swing, and wiring only one site is
					## the mistake this file's dodge fix was written for an hour ago.
					base_dmg = _apply_familiar_weight_bonus(caster, target, base_dmg)
					## The ability's OWN crit roll, mirroring BattleManager:4795. `backstab` authors 0.3 and
					## is a Rogue ability, so a grind testing a crit build never saw its signature land.
					## Default 0.0 — an ability opts IN, exactly as live does, so nothing else starts critting.
					## ⚠️ 1.5 FLAT, matching this file's own basic-attack crit. Live adds PassiveSystem's
					## crit_damage_bonus on top and the grind mirrors it on NEITHER crit path; declared here
					## rather than silently halved, because closing it is one change for both paths.
					## ⛔ AND THAT IS ONE INSTANCE OF A CATEGORY GAP, measured 2026-09-16: this file models
					## ZERO passives. 45 authored, 12 distinct stat_mods keys (attack/magic/defense/speed/
					## max_hp/max_mp multipliers, mp_cost_multiplier, crit_chance, crit_damage_bonus,
					## evasion, healing_multiplier, steal_chance), and exactly ONE of the 45 carries a job
					## restriction — so essentially any party member can equip any of them. Live consumes
					## them (attack_multiplier alone has 10 BattleManager sites; mp_cost_multiplier routes
					## through JobSystem.get_ability_mp_cost, which this file does NOT call — its own
					## _get_ability_mp_cost reads the raw authored number). So a passive BUILD evaluated in
					## a grind is evaluated without its passives. Not wired here because it is a port, not
					## a repair: it changes party strength and therefore the reward economy, which is
					## struktured's call — the same reasoning that left summon_* declared.
					if randf() < float(ability.get("crit_chance", 0.0)):
						base_dmg = int(base_dmg * 1.5)
						_log("%s crits with %s" % [caster.combatant_name, ability_id])
					## One barrier eats the whole ability, including a multi-hit, then breaks. Live checks
					## once before the hits loop, so this does too.
					if target.has_status("barrier"):
						target.remove_status("barrier")
						_log("%s's Barrier absorbs the hit!" % target.combatant_name)
						continue
					## One bounce of the pre-defense hit, not one per `hits`. The status is not spent.
					if target.has_status("reflect") or target.has_status("physical_reflect"):
						var bounced: int = caster.take_damage(base_dmg, false)
						_log("%s's Reflect bounces %d damage to %s!" % [target.combatant_name, bounced, caster.combatant_name])
						continue
					## HP DELTA, not the helper's return: _resolve_attack_with_power returns its computed
					## figure and take_damage then applies the defense formula AGAIN, so the return runs
					## high. Live drains a share of what was ACTUALLY dealt, and the log should say so too.
					## Per hit, then heal, then sum the GROSS deltas. A heal after the loop would
					## shrink the logged total, and a non-absorbing target must keep today's number.
					var dmg: int = 0
					for _h in hits:
						if not target.is_alive:
							break
						var hit_before: int = target.current_hp
						_resolve_attack_with_power(caster, target, base_dmg)
						var hit_dealt: int = hit_before - target.current_hp
						dmg += hit_dealt
						_maybe_heal_from_damage(target, hit_dealt, "")
					## NO DRAIN HERE, deliberately: live reads drain_percentage only in _execute_magic_ability, so
					## dark_slash (physical, 30%) heals its caster in NEITHER engine. Draining here would make the
					## grind heal bone_warden and shadow_knight where the game does not (@cowir-battle 2d14d92d).
					_log("%s uses %s on %s for %d" % [caster.combatant_name, ability_id, target.combatant_name, dmg])
					_maybe_inflict_status(caster, target, ability, ability_id)
			## mug is "attack and steal in one action"; the grind's physical arm read neither `steals`
			## nor success_rate, so a Rogue's mug was a plain hit. After the damage, exactly as live
			## (BattleManager:4650) — which also means a target killed by the hit cannot be robbed.
			if bool(ability.get("steals", false)):
				_roll_steal(caster, ability, targets, float(ability.get("success_rate", 0.5)))

		"mp_restore":
			## pray (single_ally) and channel (self) had no arm and fell to the default, which
			## DAMAGED the ally they restore. Arm from cowir-battle's a0e74614 — the authored
			## mp_amount is the source and `power` is only the fallback, mirroring the healing
			## arm and avoiding the field-mismatch class this file documents twice already.
			for target in targets:
				if target and target.is_alive:
					var authored_mp := int(ability.get("mp_amount", 0))
					var mp_amount := authored_mp if authored_mp > 0 else int(caster.get_buffed_stat("magic", caster.magic) * power)
					var restored = target.restore_mp(max(1, mp_amount))
					_log("%s restores %d MP to %s" % [caster.combatant_name, restored, target.combatant_name])

		"revival":
			## Mirrors BattleManager._execute_revival_ability:5470-5477 — authored
			## revive_percentage of max_hp, living targets skipped. Routed through
			## Combatant.revive so a permakilled PC stays dead in a grind too.
			var revive_pct := float(ability.get("revive_percentage", 50))
			for target in targets:
				if target == null or not is_instance_valid(target) or target.is_alive:
					continue
				target.revive(int(target.max_hp * revive_pct / 100.0))
				_log("%s revives %s with %d HP" % [caster.combatant_name, target.combatant_name, target.current_hp])

		"support", "song", "status":
			## BattleManager:4424 groups these three in one arm; headless had only "support", so
			## every song fell to the `_:` damage default below — battle_hymn cost the ally it
			## buffs 25 HP. Grouping alone is not enough: the support path reads stat/modifier
			## and songs author `effect`, so discord would have BUFFED the enemy's attack.
			for target in targets:
				if target == null or not target.is_alive:
					continue
				var duration = int(ability.get("duration", 3))
				var effect := str(ability.get("effect", ""))
				var stat = ability.get("stat", "")
				## Live's read, key order and default included (BattleManager:5752). The default was
				## 1.5 here against live's 1.0 — a phantom buff for an ability authoring neither key.
				## No ability authors BOTH, measured, so the order is cosmetic and the twin reads alike.
				var modifier = float(ability.get("stat_modifier", ability.get("modifier", 1.0)))
				if stat == "" and effect != "":
					var mapped: String = _effect_to_stat(effect)
					if mapped != "":
						stat = mapped
					elif effect == "all_stats_down":
						## Mirrors BattleManager:5887. Four DISTINCT names on purpose — add_debuff
						## keys on the name and refreshes in place, so one shared name would
						## debuff a single stat and look like it worked.
						## `modifier` above, not a third local re-read with a third default: this line
						## spelled the same lookup with 0.75 where live uses its shared 1.0.
						target.add_debuff("Despair (ATK)", "attack", modifier, duration)
						target.add_debuff("Despair (DEF)", "defense", modifier, duration)
						target.add_debuff("Despair (SPD)", "speed", modifier, duration)
						target.add_debuff("Despair (MAG)", "magic", modifier, duration)
						_log("%s uses %s on %s (all stats down)" % [caster.combatant_name, ability_id, target.combatant_name])
						continue
					elif effect == "taunt":
						## provoke is in a SHIPPED autobattle template and headless had no arm, so it
						## fell to the generic add_status below and gave the enemy a status literally
						## named "taunt" — a key live NEVER creates and nothing anywhere reads. Live
						## composes `taunted_<caster>` (BattleManager:5911) and reads the prefix back in
						## _find_taunter:2983. Same junk-key shape as the cleanse arm below (cowir-battle).
						## _select_enemy_action reads this key back through _find_taunter, the grind's twin of
						## live's _choose_target lock. Player scripts do not retarget: live's autobattle
						## resolver does not consult taunt either.
						target.add_status("taunted_%s" % caster.combatant_name)
						_log("%s taunts %s into focusing on them!" % [caster.combatant_name, target.combatant_name])
						continue
					elif effect == "cleanse":
						## Esuna is in the DEFAULT cleric script and two presets, and headless had no
						## arm for it — so it fell to the generic add_status below and gave the ally a
						## junk status called "cleanse" while the blind it was cast to cure stayed on.
						## One list, BattleManager.ESUNA_AILMENTS. The has_status call takes a loop
						## variable, so a literal has_status("x") scan cannot see membership.
						var cleansed: Array[String] = []
						for ailment in BattleManager.ESUNA_AILMENTS:
							if target.has_status(ailment):
								cleansed.append(ailment)
								target.remove_status(ailment)
						if target.doom_counter > 0:
							target.doom_counter = 0
							if not cleansed.has("doom"):
								cleansed.append("doom")
						if cleansed.is_empty():
							_log("%s uses %s on %s (nothing to cleanse)" % [caster.combatant_name, ability_id, target.combatant_name])
						else:
							_log("%s cleanses %s (%s)" % [caster.combatant_name, target.combatant_name, ", ".join(cleansed)])
						continue
					elif effect == "mp_restore_and_ap":
						## Live reads BOTH keys (BattleManager:6123-6124). This arm HARDCODED 25% where
						## inspiring_melody authors 5%, so a grinding Bard's song restored FIVE TIMES the MP
						## the game grants. The ap_gain half was right only by COINCIDENCE — the literal 1
						## equalled live's default, so an ability authoring 2 would still have paid 1.
						var mp_pct: float = float(ability.get("mp_restore_percent", 0.05))
						var ap_gain: int = int(ability.get("ap_gain", 1))
						if mp_pct > 0.0:
							var mp_restored: int = int(target.max_mp * mp_pct)
							if mp_restored > 0:
								target.restore_mp(mp_restored)
						if ap_gain != 0:
							target.gain_ap(ap_gain)
						_log("%s uses %s on %s (+%d AP, +%d%% MP)" % [caster.combatant_name, ability_id, target.combatant_name, ap_gain, int(mp_pct * 100)])
						continue
					elif effect == "damage_absorb":
						## Combatant.take_damage:349 reads `_damage_absorb_budget` and treats ABSENT as
						## UNLIMITED (-1). The unmodelled-effect else below DID add the status — so the ward
						## was live in the grind with no cap, and fill_the_void made an 8000 HP POOLED enemy
						## (the_absence, abstract_overworld) immune AND self-healing for two full rounds.
						## That is live's own pre-2026-09-10 bug, which it fixed by making absorb_amount a
						## BUDGET; the grind never got the fix because it never read the key. BattleManager:5860.
						## An omitted absorb_amount still means unlimited, on both sides.
						target.add_status("damage_absorb", duration)
						if ability.has("absorb_amount"):
							target.set_meta("_damage_absorb_budget", maxi(0, int(ability["absorb_amount"])))
						elif target.has_meta("_damage_absorb_budget"):
							target.remove_meta("_damage_absorb_budget")
						_log("%s wards %s (absorbs %d for %d turns)" % [caster.combatant_name, target.combatant_name, int(ability.get("absorb_amount", -1)), duration])
						continue
					elif effect == "steal":
						## Fell to the else below and gave the victim a junk status called "steal" while the
						## gold never moved — the cleanse class, one arm down. Live's support default is 1.0
						## (BattleManager:5609's local), NOT mug's 0.5; `steal` authors 0.5 explicitly either way.
						_roll_steal(caster, ability, [target], float(ability.get("success_rate", 1.0)))
						continue
					elif effect == "erase" or effect == "dispel":
						## Live's support executor has an arm for these; the grind's else would add an inert key.
						var dispelled: int = target.dispel()
						_log("%s strips %s's enhancements (%d cleared)" % [caster.combatant_name, target.combatant_name, dispelled])
						continue
					elif effect == "regen":
						## Combatant.end_turn ticks "regen" and reads an authored override off
						## `_regen_per_turn`, falling back to 5% of max HP when absent — so adding the
						## status alone would heal the DEFAULT, not the authored 40. Live sets both
						## (BattleManager's regen arm); so do we, or the amount silently differs.
						target.add_status("regen", duration)
						if target.has_method("set_meta"):
							target.set_meta("_regen_per_turn", int(ability.get("regen_per_turn", 0)))
						_log("%s grants regen to %s (%d/turn for %d)" % [caster.combatant_name, target.combatant_name, int(ability.get("regen_per_turn", 0)), duration])
						continue
					else:
						## Live owns a ~40-arm effect table; headless deliberately does NOT mirror
						## it. An effect we do not model is a NO-OP, never damage.
						target.add_status(effect, duration)
						_log("%s uses %s on %s (%s)" % [caster.combatant_name, ability_id, target.combatant_name, effect])
						continue
				if stat == "":
					stat = "attack"
				if modifier >= 1.0:
					target.add_buff(ability_id, stat, modifier, duration)
				else:
					target.add_debuff(ability_id, stat, modifier, duration)
				_log("%s uses %s on %s" % [caster.combatant_name, ability_id, target.combatant_name])
			## ONCE per cast, after the loop — live calls it once with the whole target list, and a
			## per-target call would roll howl's 0.3 fear separately for each enemy it already covers.
			_apply_secondary_effect(caster, ability, targets, ability_id)
			## Stored on the CASTER for its next swing, mirroring BattleManager:6326 — burrow authors 1.5
			## and ironback_beetle (POOLED) casts it, so the telegraph never paid off in a grind.
			var nam: float = float(ability.get("next_attack_multiplier", 0.0))
			if nam > 0.0 and caster != null and caster.is_alive:
				caster.set_meta("_next_attack_multiplier", nam)
				_log("%s charges its next strike (x%.1f) with %s" % [caster.combatant_name, nam, ability_id])

		"meta":
			## Live routes these to _execute_meta_ability (BattleManager:6427), which matches on
			## `meta_effect` and does reality manipulation — battle-log narrative plus
			## GameState.add_corruption(corruption_risk). It deals NO DAMAGE on any branch. Without
			## this arm all 24 meta abilities fell to the default below, and the EIGHT that target the
			## opposing side reached its damaging branch: permakill · mind_swap · boss_puppet ·
			## control_override · mutual_destruction (single_enemy) and corrupt_save · save_deletion ·
			## time_stop (all_enemies). Measured before the fix: permakill invented 395 damage, and
			## save_deletion took a 5000 HP party member to 3805.
			##
			## ⛔ REACHABLE VIA THE PLAYER, NOT THE META BOSS — I published the opposite and it was wrong.
			## The enemy path has exactly two ability routes and BOTH filter by type:
			## _find_attack_ability takes only ["magic", "physical"], _find_heal_ability only "healing".
			## So permadeath_reaper can never SELECT save_deletion in a grind, however reachable the
			## monster is — I proved the arm damages by calling _resolve_ability directly and then
			## claimed the AI takes that path. It does not.
			## What IS reachable: AutobattleSystem applies NO type filter (0 sites, against 108
			## mentions of "ability"), so a player rule naming a meta ability routes straight here.
			## Five are single_enemy and in a job kit today — permakill (necromancer), mind_swap,
			## boss_puppet, control_override, mutual_destruction (bossbinder). A scripted Necromancer
			## was dealing 395 phantom damage per permakill.
			##
			## NOT PORTING THE MECHANICS: save deletion, permakill and mind-swap are save-side and
			## scene-side, and corruption_risk / corruption_amount are already DECLARED in the ledger
			## as struktured's stakes ruling. A no-op is this file's own stated rule for an effect it
			## does not model — "never damage" — applied one level up, at the TYPE.
			for target in targets:
				if target == null or not is_instance_valid(target):
					continue
				_log("%s uses %s on %s (meta — unmodelled here, and never damage)" % [caster.combatant_name, ability_id, target.combatant_name])
			if targets.is_empty():
				_log("%s uses %s (meta — unmodelled here)" % [caster.combatant_name, ability_id])

		_:
			## Was: magic damage to targets[0]. AutobattleSystem builds targets from target_type,
			## so an all_allies ability arrived holding the PARTY and this attacked them. 39
			## abilities author a type with no arm, so the blast radius was never just the Bard.
			##
			## ⛔ THIS SENTENCE CARRIED A COUNT AND THE COUNT WENT STALE. It read "39 abilities … (meta 24
			## · summon 7 · song 4 · mp_restore 2 · revival 1 · escape 1)" until 2026-09-16, and by then
			## song, mp_restore and revival had arms and so did meta. Measured that day: EIGHT abilities
			## across TWO types — escape 1, summon 7. I READ THIS COMMENT WHILE ADDING THE META ARM,
			## noticed it was stale, and moved on; @cowir-sprites having the same thing falsified by their
			## own commit five days earlier is what sent me back.
			##
			## So the LIVE number is gone rather than refreshed — what stands above is dated provenance for
			## a set that is recomputed elsewhere, which is @cowir-music's test: not "is there a number"
			## but "would a reader quote this as true TODAY". test_autogrind_inert_ability_census PARSES the
			## armed types out of this match block and maintains the population against abilities.json —
			## a live count that cannot drift, in a file whose job is keeping it honest. A count in prose
			## here is a second declarer of a fact that already has a self-retiring one.
			var target = targets[0] if targets.size() > 0 else null
			if target and target.is_alive:
				if _is_same_side(caster, target):
					_log("%s uses %s on %s (unmodelled type — no effect)" % [caster.combatant_name, ability_id, target.combatant_name])
				else:
					var base_dmg = int(caster.get_buffed_stat("magic", caster.magic) * power)
					target.take_damage(max(1, base_dmg), true)
					_log("%s uses %s on %s" % [caster.combatant_name, ability_id, target.combatant_name])


## The status a DAMAGING ability inflicts, on the same roll the live engine makes.
##
## ⛔ Headless dealt the damage and dropped the status entirely: 68 abilities author `effect_chance`
## (0.2 to 1.0) and the grind honoured none of them, in EITHER direction — the Bard's Riff never
## blinded, plague_bite never poisoned at its authored 1.0, and no enemy ever stunned the party. A
## player spends hours in the grind, so this is not a corner.
##
## Mirrors BattleManager:4899-4920 — the parity anchor, including both of its aliases and its
## deliberate 0.0 default (a damaging ability opts IN to a status by authoring a chance; only
## `random_debuff` defaults to 1.0, because two abilities present the debuff as their headline and
## omit the key). Kept as literal arms rather than a shared helper for the reason this file's other
## mirrors are: the two engines are separate implementations, and the parity guard scans both.
const _RANDOM_DEBUFF_POOL := ["poison", "blind", "burn", "confuse", "fear", "silence", "curse"]


## The magic/physical half of stat-down application, mirroring BattleManager._apply_stat_down.
## Returns true when the effect WAS a stat-down, so the caller falls through to add_status only for
## real statuses. Names match live's exactly — add_debuff keys on the NAME and refreshes in place,
## so a different spelling would stack where live refreshes.
##
## ⚠️ SEPARATE FROM _effect_to_stat ON PURPOSE. That one serves the SUPPORT arm, where the ability's
## whole point is the buff; this serves the magic/physical arms, where the stat-down rides on a
## damaging hit behind an effect_chance roll. Live splits them the same way, and collapsing them
## would merge two executors that apply the same names under different conditions.
##
## ⚠️ `magic_down` IS DELIBERATELY ABSENT, matching live: it has no owner on either path, so giving
## it one here would invent a debuff name rather than mirror one. corruption_wave still writes a
## token in BOTH engines, which is agreement rather than a gap. @cowir-battle holds that call.
func _apply_stat_down(target, effect: String, stat_modifier: float, duration: int) -> bool:
	match effect:
		"defense_down":
			target.add_debuff("Armor Break", "defense", stat_modifier, duration)
		"magic_defense_down":
			target.add_debuff("Soul Sap", "magic_defense", stat_modifier, duration)
		"attack_down":
			target.add_debuff("Weaken", "attack", stat_modifier, duration)
		"speed_down":
			target.add_debuff("Slow", "speed", stat_modifier, duration)
		"all_stats_down":
			target.add_debuff("Despair (ATK)", "attack", stat_modifier, duration)
			target.add_debuff("Despair (DEF)", "defense", stat_modifier, duration)
			target.add_debuff("Despair (SPD)", "speed", stat_modifier, duration)
			target.add_debuff("Despair (MAG)", "magic", stat_modifier, duration)
		_:
			return false
	return true


func _maybe_inflict_status(caster, target, ability: Dictionary, ability_id: String) -> void:
	if target == null or not target.is_alive:
		return
	var effect := str(ability.get("effect", ""))
	if effect == "":
		return
	var chance: float = float(ability.get("effect_chance", 1.0 if effect == "random_debuff" else 0.0))
	## Equipment status_resistance, mirroring BattleManager:5002 (and :4592, which uses the identical
	## formula so the two live sites cannot drift). @cowir-battle's resist_ring fix is the live half:
	## the ring had ONE reader, on the ATTACKER's on-hit path, so it only ever resisted the party's own
	## daggers. Every status a player actually suffers arrives on this route in both engines.
	## ⚠️ NOT clamped like its neighbours, and deliberately: evasion_bonus and critical_bonus clamp
	## their INPUT to 0.50 because live caps those at their own sites. Live caps status_resistance
	## NOWHERE — it clamps the RESULT to [0,1]. Copying the neighbouring line's shape would invent a
	## ceiling the real game does not have. Today's only author is resist_ring at 0.3, so an invented
	## input cap would be unobservable, which is exactly why it is written down here.
	var resist: float = _sum_equipment_special_effect(target, "status_resistance")
	var effective: float = clampf(chance - resist, 0.0, 1.0)
	if effective <= 0.0 or randf() >= effective:
		return
	var status_to_add := effect
	if effect == "random_debuff":
		status_to_add = _RANDOM_DEBUFF_POOL[randi() % _RANDOM_DEBUFF_POOL.size()]
	## freeze aliases to stun and burn to burning — the DoT ticks only "burning", and both aliases
	## are applied at the same point live applies them, so the cleanse lists match too.
	if status_to_add == "freeze":
		status_to_add = "stun"
	if status_to_add == "burn":
		status_to_add = "burning"
	## ⛔ THE GRIND MODELLED DISPEL NOT AT ALL, so void_breath (Umbraxis, 28 MP, all enemies) and
	## null_touch (null_entity, POOLED in abstract_overworld) stripped nothing here after live was
	## fixed. An ACTION, not a status token — same shape as doom, and it returns like live does.
	if status_to_add == "erase" or status_to_add == "dispel":
		var cleared: int = target.dispel()
		_log("%s strips %s's enhancements (%d cleared)" % [caster.combatant_name, target.combatant_name, cleared])
		return
	## ability_silence lands as "silence" — the key both engines' gates read.
	if status_to_add == "ability_silence":
		status_to_add = "silence"
	## Twin of BattleManager:5098 — the authored effect name is not the key Combatant ticks.
	if status_to_add == "amplify_poison":
		status_to_add = "festered"
	if status_to_add == "memory_leak_status":
		status_to_add = "memory_leak"
	## doom is a COUNTER, not a status, in both engines: Combatant.doom_counter ticks down and KOs,
	## and this file already CURES it in the cleanse arm while nothing could ever set it.
	if status_to_add == "doom":
		target.doom_counter = int(ability.get("countdown", 3))
		_log("%s dooms %s in %d (%s)" % [caster.combatant_name, target.combatant_name, target.doom_counter, ability_id])
		return
	## ⛔ A STAT-DOWN IS A DEBUFF, NOT A STATUS TOKEN. Mirrors BattleManager._apply_stat_down, which
	## @cowir-battle added to live's _apply_ability_status — the twin of THIS function. Before that
	## both engines wrote an inert token here and AGREED, which I measured and published as "no gap".
	## Their fix made live right and opened the divergence on the very path I had declared safe.
	var stat_modifier: float = float(ability.get("stat_modifier", ability.get("modifier", 1.0)))
	if _apply_stat_down(target, status_to_add, stat_modifier, int(ability.get("duration", 3))):
		_log("%s applies %s to %s (%s, x%.2f)" % [caster.combatant_name, status_to_add, target.combatant_name, ability_id, stat_modifier])
		return
	target.add_status(status_to_add, int(ability.get("duration", 3)))
	_log("%s inflicts %s on %s (%s)" % [caster.combatant_name, status_to_add, target.combatant_name, ability_id])

## Drains a share of damage ACTUALLY DEALT back to the caster, mirroring BattleManager:5121-5123.
## Takes the accumulated total so a multi-hit drain heals off the whole volley, as live does.
func _drain_to(caster, damage_dealt: int, drain_pct: float, ability_id: String) -> void:
	if drain_pct <= 0.0 or damage_dealt <= 0:
		return
	var drained: int = int(damage_dealt * drain_pct / 100.0)
	if drained <= 0:
		return
	var healed: int = caster.heal(drained)
	_log("%s drains %d HP with %s" % [caster.combatant_name, healed, ability_id])



## The stat a physical ability computes its damage FROM, and the missing-HP multiplier, mirroring
## BattleManager:4736-4758.
##
## ⛔ Headless used `attack` for every physical ability, so guard_strike on a high-defense caster dealt
## poverty damage — the live engine's own words for the same bug when IT had it (tick 437). rat_guard
## (pooled) casts guard_strike; throw_shuriken and last_stand_ability are job abilities.
##
## ⛔ `target_defense` and `most_used_ability` are NOT here, and that is deliberate: LIVE reads neither
## (0 references), so `complement` and `player_knowledge` scale from attack in both engines. Wiring
## them here alone would push the simulation past the game it simulates. Declared, with an arm that
## reds if live starts reading either.
func _scaled_base(caster, ability: Dictionary) -> int:
	match str(ability.get("scales_with", "")):
		"defense":
			return int(caster.get_buffed_stat("defense", caster.defense))
		"speed":
			return int(caster.get_buffed_stat("speed", caster.speed))
		_:
			return int(caster.get_buffed_stat("attack", caster.attack))


## Linear from 1.0x at full HP to max_multiplier at zero, exactly as live computes it. Separate from
## _scaled_base because it multiplies the POWER rather than swapping the base stat.
func _missing_hp_multiplier(caster, ability: Dictionary) -> float:
	if str(ability.get("scales_with", "")) != "missing_hp" or caster.max_hp <= 0:
		return 1.0
	var hp_pct: float = float(caster.current_hp) / float(caster.max_hp)
	var max_mult: float = float(ability.get("max_multiplier", 5.0))
	return 1.0 + (1.0 - hp_pct) * (max_mult - 1.0)

## The SECOND effect a support ability authors, on the same roll the live engine makes.
##
## ⛔ 9 abilities author `secondary_effect` and the grind honoured none — so a spider's web_shot only
## slowed and never stunned, a wolf's howl never frightened the party, and enrage was a free attack
## buff with no defense penalty. Six of the casters are POOLED monsters a grind draws every session.
##
## Mirrors BattleManager:6368 — its target groups, its `secondary_chance` default of 1.0, its
## `secondary_modifier` default of 0.7, and its fall-through to add_status for a name that is not a
## stat. Called from the support arm ONLY, which is where live calls it (_execute_support_ability is
## its single call site): `subset_drain` (magic) and `toxic_embrace` (physical) therefore keep their
## secondaries dropped HERE TOO, because live drops them. Applying them only in the grind would make
## the grind harsher than the game it simulates, which is this file's own failure mode inverted.
const _SECONDARY_STAT_BUFF_MAP: Dictionary = {
	"attack_up": ["attack", "Secondary Attack Up"],
	"defense_up": ["defense", "Secondary Defense Up"],
	"magic_up": ["magic", "Secondary Magic Up"],
	"speed_up": ["speed", "Secondary Speed Up"],
	"magic_defense_up": ["magic_defense", "Secondary Magic Defense Up"],
}
const _SECONDARY_STAT_DEBUFF_MAP: Dictionary = {
	"attack_down": ["attack", "Secondary Attack Down"],
	"defense_down": ["defense", "Secondary Defense Down"],
	"magic_down": ["magic", "Secondary Magic Down"],
	"speed_down": ["speed", "Secondary Speed Down"],
	"magic_defense_down": ["magic_defense", "Secondary Magic Defense Down"],
}


## Live pays the PLAYER for a landed steal — BattleManager:6147 (the support `steal` effect) and
## :4655 (mug's steal half), both GameState.add_gold, which applies gold_multiplier itself.
## PARTY SIDE ONLY here, deliberately: live has no caster-side check, so an enemy's steal pays the
## party it just robbed. That is reachable — goblin/spiteful_crow/conveyor_gremlin author `steal`
## across 7 pools, and "support" is in UTILITY_ABILITY_TYPES, which the brute and assassin AI both
## draw from. Mirroring it into an engine that runs hundreds of unattended battles turns a per-fight
## bug into a gold fountain, so the enemy side is declared in the ledger rather than copied.
## ⚠️ HALF of live's rate, and the other half is a RULING rather than an omission. Mirrors
## BattleManager._steal_success_rate:5503 — `clampf(base + equip + passive, 0.0, 1.0)` — with the
## EQUIPMENT term wired and the PASSIVE term deliberately absent: `steal_chance` is one of the 12
## stat_mods keys in the 45-passive scoping call, declared and waiting on struktured. Wiring the
## equipment half alone does not skew the grind the way a half-ported Speculator would, because both
## terms ADD to the same rate: modelling one moves the number toward live, never past it.
## RETIREMENT CONDITION: when the passives ruling lands, this composes all three and the note goes.
func _roll_steal(caster, ability: Dictionary, targets: Array, base_rate: float) -> void:
	var party_side: bool = _player_party.has(caster)
	var rate: float = clampf(base_rate + _sum_equipment_special_effect(caster, "steal_bonus"), 0.0, 1.0)
	for target in targets:
		if target == null or not is_instance_valid(target) or not target.is_alive:
			continue
		if randf() >= rate:
			_log("%s fails to steal from %s" % [caster.combatant_name, target.combatant_name])
			continue
		## BattleManager:6147 verbatim. rogue_lockward's first_steal_guaranteed and steal_response are
		## NOT ported: it is the only monster authoring either, and it is neither pooled nor
		## autogrind_spawned, so no grind can field it by any of the four spawn forms.
		var amount: int = randi_range(5, 50) * (1 + int(target.max_hp / STEAL_GOLD_HP_DIVISOR))
		if party_side:
			_stolen_gold += amount
		_log("%s steals %d gold from %s" % [caster.combatant_name, amount, target.combatant_name])


func _apply_secondary_effect(caster, ability: Dictionary, primary_targets: Array, ability_id: String) -> void:
	var sec_effect: String = str(ability.get("secondary_effect", ""))
	if sec_effect == "":
		return
	var sec_chance: float = clampf(float(ability.get("secondary_chance", 1.0)), 0.0, 1.0)
	if sec_chance <= 0.0:
		return
	var sec_targets: Array = []
	## Sides resolved by MEMBERSHIP, from the caster out. A grind resolves monster casts too, so a
	## fixed `_enemy_party` here would make a wolf's howl frighten its own pack.
	var caster_is_player: bool = _player_party.has(caster)
	var foes: Array = _enemy_party if caster_is_player else _player_party
	var allies: Array = _player_party if caster_is_player else _enemy_party
	match str(ability.get("secondary_target", "")):
		"all_enemies":
			for c in foes:
				if c != null and c.is_alive:
					sec_targets.append(c)
		"all_allies":
			for c in allies:
				if c != null and c.is_alive:
					sec_targets.append(c)
		"self":
			if caster != null and caster.is_alive:
				sec_targets.append(caster)
		_:
			for t in primary_targets:
				if t != null and t.is_alive:
					sec_targets.append(t)
	if sec_targets.is_empty():
		return
	var sec_modifier: float = float(ability.get("secondary_modifier", 0.7))
	var sec_duration: int = int(ability.get("duration", 3))
	for t in sec_targets:
		if randf() >= sec_chance:
			continue
		if _SECONDARY_STAT_BUFF_MAP.has(sec_effect):
			var b: Array = _SECONDARY_STAT_BUFF_MAP[sec_effect]
			t.add_buff(b[1], b[0], sec_modifier, sec_duration)
		elif _SECONDARY_STAT_DEBUFF_MAP.has(sec_effect):
			var d: Array = _SECONDARY_STAT_DEBUFF_MAP[sec_effect]
			t.add_debuff(d[1], d[0], sec_modifier, sec_duration)
		else:
			t.add_status(sec_effect, sec_duration)
		_log("%s: secondary %s on %s (%s)" % [caster.combatant_name, sec_effect, t.combatant_name, ability_id])



## The MP a damaging magic ability siphons back to its caster, mirroring BattleManager:5085.
##
## ⛔ Two POOLED monsters advertise an MP siphon and got nothing in the grind: data_wraith's data_drain
## (20) and the_absence's memory_drain (15, all_enemies). Live refills the caster per damaging hit, so
## they keep casting; here they ran dry and stopped, and the grind's version of those fights was
## weaker than the game's — which is what the safety limits are calibrated against.
##
## Magic arm ONLY, because live reads drain_mp only in _execute_magic_ability and both owners are
## type=magic. Adding it elsewhere would make the grind harsher than the game it simulates.
func _siphon_mp(caster, ability: Dictionary, damage_dealt: int, ability_id: String) -> void:
	var amount: int = int(ability.get("drain_mp", 0))
	if amount <= 0 or damage_dealt <= 0 or caster == null or not caster.is_alive:
		return
	var restored: int = caster.restore_mp(amount)
	if restored > 0:
		_log("%s siphons %d MP with %s" % [caster.combatant_name, restored, ability_id])



## The self-damage a magic ability costs its caster, mirroring BattleManager:5171-5174.
##
## ⛔ The FIRST parity gap in this file that made the grind HARDER than the game. stack_overflow is
## 3.0x to all_enemies with a 20% recoil, and recursive_loop (POOLED) casts it — so in the grind that
## monster paid nothing for its biggest attack and survived fights the real game kills it in. Live's
## own comment records the same field being unread on ITS side once: "stack_overflow dealt 3.0x to all
## enemies for free, defeating the catastrophic-damage / 20%-recoil tradeoff design."
##
## After the loop and proportional to the WHOLE volley, not per target — an all_enemies cast pays once
## on the total. Skipped when the caster died to something else this cast, as live skips it.
func _recoil_to(caster, ability: Dictionary, total_dealt: int, ability_id: String) -> void:
	var pct: float = float(ability.get("damage_to_self_pct", 0.0))
	if pct <= 0.0 or total_dealt <= 0 or caster == null or not caster.is_alive:
		return
	var recoil: int = max(1, int(round(total_dealt * pct)))
	caster.take_damage(recoil, true)
	_log("%s takes %d recoil from %s" % [caster.combatant_name, recoil, ability_id])



## Reads and CLEARS a stored next-attack multiplier, returning 1.0 when there is none.
##
## ⛔ Live SETS this in _execute_support_ability (:6326) and CONSUMES it on BOTH the basic-attack path
## (:4374) and the magic path (:4969) — two consumers, one producer. The grind had none of the three,
## so burrow was a wasted turn: ironback_beetle (POOLED) telegraphed and then hit for the same damage.
##
## One-shot BY CONSTRUCTION — the clear lives here rather than at each call site, so a third consumer
## cannot forget it and leave a permanent bonus running.
func _take_charged_multiplier(combatant) -> float:
	if combatant == null or not combatant.has_method("get_meta"):
		return 1.0
	var stored: float = float(combatant.get_meta("_next_attack_multiplier", 0.0))
	if stored <= 0.0:
		return 1.0
	combatant.set_meta("_next_attack_multiplier", 0.0)
	return stored


## Arbiter's Final Word, mirroring BattleManager._apply_lens_execute_bonus — +bonus damage against a
## target ALREADY below the threshold. Live reads the HP fraction BEFORE this hit lands ("finish the
## wounded", not "reward whatever this hit leaves behind"), and so does this.
## Live applies it on all three damage paths; this engine applied it on none, so an equipped Arbiter
## did nothing in a grind while adding 50% to the same swing in a real fight.
func _apply_lens_execute_bonus(attacker, target, damage: int) -> int:
	if attacker == null or target == null or not is_instance_valid(target) or target.max_hp <= 0:
		return damage
	## DELEGATES rather than reimplementing. @cowir-battle extracted live's arithmetic into
	## lens_execute_multiplier so the preview could quote the bonus without inheriting the executor's
	## emit; my port predated that and held a second copy of one authored number. One table, one
	## formula — the same choice made for terrain, and the reason neither can drift.
	if not BattleManager.has_method("lens_execute_multiplier"):
		return damage
	var mult: float = float(BattleManager.lens_execute_multiplier(attacker, target))
	if mult <= 1.0:
		return damage
	## The emit stays on THIS side, exactly as it does in live's executor.
	_log("%s moves to finish it." % attacker.combatant_name)
	return int(damage * mult)


## Twin of BattleManager._maybe_heal_from_damage. the_absence authors
## special_behavior.heals_from_damage (30%) and sits in abstract_overworld, a pool
## the grind draws. Live converts a share of the damage that landed into healing;
## holy skips. Not inside take_damage — a group attack calls that on both engines
## and neither one asks, so a Limit Break still lands in full.
func _maybe_heal_from_damage(target, damage_amount: int, element: String) -> void:
	if target == null or not is_instance_valid(target) or not target.is_alive:
		return
	if damage_amount <= 0:
		return
	if not target.has_method("get_meta") or not target.has_meta("monster_type"):
		return
	var mtype := str(target.get_meta("monster_type", ""))
	if mtype == "":
		return
	var enc = _get_autoload("EncounterSystem")
	if enc == null or not ("monster_database" in enc):
		return
	var db: Variant = enc.monster_database
	if not (db is Dictionary) or not (db as Dictionary).has(mtype):
		return
	var sb: Variant = (db[mtype] as Dictionary).get("special_behavior", {})
	if not (sb is Dictionary) or not bool((sb as Dictionary).get("heals_from_damage", false)):
		return
	if element == "holy":
		return
	var pct: float = clampf(float((sb as Dictionary).get("heal_percentage", 0.3)), 0.0, 1.0)
	if pct <= 0.0:
		return
	var heal_amount: int = int(round(float(damage_amount) * pct))
	if heal_amount <= 0:
		return
	var healed: int = target.heal(heal_amount)
	if healed > 0:
		_log("%s absorbs the impact — heals %d HP!" % [target.combatant_name, healed])


func _resolve_attack_with_power(attacker, target, base_damage: int) -> int:
	if not target or not target.is_alive:
		return 0
	## Live's _execute_physical_ability applies it to the pre-mitigation damage; this file's defense
	## formula is quadratic, so scaling the mitigated number would not be the same port.
	var def_val = float(target.get_buffed_stat("defense", target.defense))
	var dmg = float(_apply_lens_execute_bonus(attacker, target, base_damage))
	# Same divisor guard as _resolve_attack — see comment there.
	var denom = maxf(1.0, dmg + def_val)
	var actual = int((dmg * dmg) / denom)
	actual = max(1, actual)
	if target.is_defending:
		actual = actual / 2
	target.take_damage(actual)
	return actual


func _resolve_item(user, item_id: String, target) -> void:
	## Same one-bag rule as BattleManager._execute_item, so a grind spends what a live battle would.
	var bag: Array = _player_party if user in _player_party else [user]
	if ItemSystem.party_item_count(bag, item_id) <= 0:
		return
	ItemSystem.take_party_item(user, bag, item_id)

	## Tick 394: route through ItemSystem.use_item so autogrind item
	## use matches live battle exactly. Pre-fix hardcoded handlers
	## for potion (50), hi_potion (200), ether (30), hi_ether (100)
	## and a unconditional heal(50) default. The default silently
	## mishandled every other item:
	##   - mega_potion silently healed 50 instead of 100
	##   - phoenix_down silently healed 50 instead of reviving
	##   - holy_water / bomb_fragment / etc silently healed 50
	##     instead of damaging an enemy
	##   - power_drink / speed_tonic silently healed 50 instead of
	##     applying their buff
	## All silently corrupted autogrind reward / tier calculations.
	if target == null or not target.is_alive:
		return
	var its = _get_autoload("ItemSystem")
	if its != null and its.has_method("use_item"):
		var typed_targets: Array[Combatant] = [target]
		its.use_item(user, item_id, typed_targets)
		_log("%s uses %s on %s" % [user.combatant_name, item_id, target.combatant_name])
		return
	# Fallback: ItemSystem unavailable. Original hardcoded list.
	match item_id:
		"potion":
			target.heal(50)
		"hi_potion":
			target.heal(200)
		"ether":
			target.restore_mp(30)
		"hi_ether":
			target.restore_mp(100)
		_:
			target.heal(50)
	_log("%s uses %s on %s (fallback path — ItemSystem missing)" % [user.combatant_name, item_id, target.combatant_name])


func _all_dead(party: Array) -> bool:
	for combatant in party:
		if combatant.is_alive:
			return false
	return true


func _build_results(victory: bool, termination_reason: String = "") -> Dictionary:
	var exp = 0
	var gold = 0
	# authored rewards, same as live battles — stat-derived formulas broke the full-parity ruling both directions
	var mdb: Dictionary = {}
	if EncounterSystem and not EncounterSystem.monster_database.is_empty():
		mdb = EncounterSystem.monster_database
	if victory:
		## Cadence #23 — reward_multiplier parity with BM._get_battle_reward_multiplier, under
		## struktured's 2026-07-01 full-parity ruling ("automation isn't cheating — it's
		## enlightenment"; ludicrous/headless MUST receive the same yields as live).
		##
		## ⛔ THIS COMPUTES 1.0 AND ALWAYS HAS. Corrected 2026-09-17 — the note here used to state the
		## parity as FIXED, which told every reader it works.
		## `reward_multiplier` is authored by ZERO of the 106 monsters in monsters.json, so the mdb
		## lookup below can only ever return its default. The single author in the tree is
		## EncounterSystem's hand-built Hero Mimic dict (2.5x), which never enters monsters.json.
		##
		## ⚠️ AND THERE IS NO DIVERGENCE TO FIX: live's BM._get_battle_reward_multiplier reads
		## `enemy.get("_enemy_data")`, a property NOTHING in src/ ever writes and Combatant does not
		## declare — so live returns 1.0 unconditionally too. Both engines agree by accident while the
		## feature is dead end to end. Reported to the BattleManager/EncounterSystem owner; the live
		## half is not this file's to fix.
		##
		## Kept rather than deleted: the loop is correct the day a monster authors the field, and
		## test_hbr_reward_multiplier_parity pins BOTH triggers so this note cannot go quietly stale.
		var reward_multiplier: float = 1.0
		for enemy in _enemy_party:
			var mt_key: String = str(enemy.get_meta("monster_type", "")) if enemy.has_method("get_meta") and enemy.has_meta("monster_type") else ""
			var mrow: Dictionary = mdb.get(mt_key, {})
			var em: float = float(mrow.get("reward_multiplier", 1.0))
			if em > reward_multiplier:
				reward_multiplier = em
		for enemy in _enemy_party:
			var mt_key: String = str(enemy.get_meta("monster_type", "")) if enemy.has_method("get_meta") and enemy.has_meta("monster_type") else ""
			var mrow: Dictionary = mdb.get(mt_key, {})
			exp += int(float(mrow.get("exp_reward", 25)) * reward_multiplier)
			gold += int(float(mrow.get("gold_reward", int(enemy.max_hp * 0.3 + enemy.defense))) * reward_multiplier)
			## Tick 146: mark defeated. mark_seen happened at the top
			## of resolve_battle (tick 145); this is the kill credit.
			# Tick 260: forward location through the defeat call too.
			if not is_instance_valid(enemy):
				continue
			if enemy.has_method("get_meta") and enemy.has_meta("monster_type"):
				var mtype: String = str(enemy.get_meta("monster_type", ""))
				if mtype != "":
					var defeat_loc: String = ""
					if MapSystem and "current_map_id" in MapSystem:
						defeat_loc = str(MapSystem.current_map_id)
					BestiarySystem.mark_defeated(mtype, defeat_loc)
		# Tick 341: parallel to tick 340 — apply game_constants
		# ["exp_multiplier"] and ["gold_multiplier"] so Scriptweaver /
		# RebalanceDaemon nudges affect the headless autogrind path too.
		# Pre-fix this returned raw enemy-stat sums; AutogrindSystem.on_
		# battle_victory consumed exp directly via gain_job_exp without
		# the multiplier, so a knob set to 2.0 had ZERO effect on
		# headless autogrind. Same defensive clampf([0.1, 10.0]) band
		# as BattleManager line ~431 and the live-autogrind fix in
		# GameLoop._on_autogrind_battle_ended.
		var gs: Object = null
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			gs = tree.root.get_node_or_null("GameState")
		if gs != null and "game_constants" in gs:
			var exp_mult: float = clampf(
				float(gs.game_constants.get("exp_multiplier", 1.0)),
				0.1, 10.0)
			var gold_mult: float = clampf(
				float(gs.game_constants.get("gold_multiplier", 1.0)),
				0.1, 10.0)
			exp = int(exp * exp_mult)
			gold = int(gold * gold_mult)

	## Credited whether or not the party won. Every other reward here is victory-only, but live
	## calls add_gold the MOMENT the steal lands, so gold taken off a monster survives a wipe.
	## Multiplied separately for that reason, with add_gold's own clamp (GameState:1059).
	if _stolen_gold > 0:
		var steal_mult: float = 1.0
		var gs_s: Object = null
		var tree_s: SceneTree = Engine.get_main_loop() as SceneTree
		if tree_s != null and tree_s.root != null:
			gs_s = tree_s.root.get_node_or_null("GameState")
		if gs_s != null and "game_constants" in gs_s:
			steal_mult = clampf(float(gs_s.game_constants.get("gold_multiplier", 1.0)), 0.1, 10.0)
		gold += int(_stolen_gold * steal_mult)

	# Drop parity with BattleManager (~line 596): pre-fix ludicrous mode gave EXP+gold
	# but ZERO item drops — rare_item_found never fired and inventory_items interrupts
	# were dead in headless. Same chance * drop_rate_mult * reward_multiplier math.
	var drops: Dictionary = {"item_drops": {}, "rare_drops": []}
	if victory:
		var enemy_types: Array = []
		for enemy in _enemy_party:
			if is_instance_valid(enemy) and enemy.has_method("get_meta") and enemy.has_meta("monster_type"):
				var mt: String = str(enemy.get_meta("monster_type", ""))
				if mt != "":
					enemy_types.append(mt)
		var monsters_data: Dictionary = {}
		var drop_rate_mult: float = 1.0
		var tree2: SceneTree = Engine.get_main_loop() as SceneTree
		if tree2 != null and tree2.root != null:
			var enc: Node = tree2.root.get_node_or_null("EncounterSystem")
			if enc != null and "monster_database" in enc:
				monsters_data = enc.monster_database
			var gs2: Node = tree2.root.get_node_or_null("GameState")
			if gs2 != null and "game_constants" in gs2:
				drop_rate_mult = clampf(
					float(gs2.game_constants.get("drop_rate_multiplier", 1.0)),
					0.1, 10.0)
		drops = _roll_drop_tables(enemy_types, monsters_data, drop_rate_mult)

	return {
		"victory": victory,
		"rounds": _current_round,
		"exp_gained": exp,
		"gold_gained": gold,
		"item_drops": drops["item_drops"],
		"rare_drops": drops["rare_drops"],
		"log": _battle_log.duplicate(),
		"player_party": _player_party,
		## ⛔ DO NOT READ THIS. GameLoop._resolve_headless_battle frees every enemy three lines after
		## resolve_battle returns (`for e in enemies: e.free()`), so by the time any consumer could
		## touch this key it holds FREED Combatants. Zero consumers in src/ or test/ today, which is
		## the only reason it is harmless; test_autogrind_headless_drops reds if one appears.
		## player_party is safe by contrast — the caller owns those and does not free them.
		"enemy_party": _enemy_party,
		"termination_reason": termination_reason,  # cadence #19: "" = normal (victory or fair defeat), "stalemate" = MAX_ROUNDS exhausted
	}


## Pure drop-roll over monster drop_tables. rand_func injectable for deterministic tests.
## Returns {"item_drops": {item_id: qty}, "rare_drops": [{item, chance}]} — rare = base chance < 0.10.
static func _roll_drop_tables(enemy_types: Array, monsters_data: Dictionary, drop_rate_mult: float, rand_func: Callable = Callable()) -> Dictionary:
	var item_drops: Dictionary = {}
	var rare_drops: Array = []
	for mt in enemy_types:
		if not monsters_data.has(mt):
			continue
		var record: Dictionary = monsters_data[mt]
		var reward_mult: float = float(record.get("reward_multiplier", 1.0))
		for drop in record.get("drop_table", []):
			var chance: float = float(drop.get("chance", 0.0))
			var roll: float = rand_func.call() if rand_func.is_valid() else randf()
			if roll < chance * drop_rate_mult * reward_mult:
				var item_id: String = str(drop.get("item", ""))
				if item_id == "":
					continue
				item_drops[item_id] = int(item_drops.get(item_id, 0)) + 1
				if chance < 0.10:
					rare_drops.append({"item": item_id, "chance": chance})
	return {"item_drops": item_drops, "rare_drops": rare_drops}


func _log(text: String) -> void:
	_battle_log.append(text)
