extends Node

## JobSystem - Manages job data, abilities, and job-specific mechanics
## Jobs define what abilities a combatant can use and their stat modifiers

signal job_changed(combatant: Combatant, old_job: Dictionary, new_job: Dictionary)
signal secondary_job_changed(combatant: Combatant, job_id: String)

## Loaded job data
var jobs: Dictionary = {}
var abilities: Dictionary = {}
var job_aliases: Dictionary = {}

## Job categories
enum JobType {
	STARTER,      # Basic jobs (Fighter, Cleric, Mage, Rogue, Bard)
	ADVANCED,     # Unlockable jobs
	META          # Meta jobs (Scriptweaver, Time Mage, etc.)
}


func _ready() -> void:
	_load_job_aliases()
	_load_job_data()
	_load_ability_data()


func _load_job_aliases() -> void:
	"""Load job ID aliases from data/job_aliases.json for backward compatibility"""
	## Tick 165: defensive load mirrors _load_job_data's pattern.
	## Pre-fix every failure mode (file open fail, parse error,
	## root-not-Dictionary) silently no-op'd. Result: old saves
	## with white_mage / black_mage / thief job IDs wouldn't get
	## resolved to cleric / mage / rogue — the player would see
	## "Unknown job" or fall back to fighter defaults without any
	## warning. Now each failure mode pushes a distinct warning so
	## the cause surfaces during dev / hooks.
	var file_path = "res://data/job_aliases.json"
	if not FileAccess.file_exists(file_path):
		push_warning("[JobSystem] job_aliases.json not found at %s — old saves with renamed jobs (white_mage/black_mage/thief) won't migrate" % file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("[JobSystem] job_aliases.json exists but FileAccess.open failed — aliases empty, save migration disabled")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_warning("[JobSystem] job_aliases.json parse error: %s — aliases empty" % json.get_error_message())
		return
	if not (json.data is Dictionary):
		push_warning("[JobSystem] job_aliases.json parsed but root is not a Dictionary — aliases empty")
		return

	job_aliases = json.data
	print("Loaded %d job aliases" % job_aliases.size())


func resolve_job_id(raw_id: String) -> String:
	"""Resolve an old job ID to its current name via aliases. Identity passthrough for non-aliased IDs."""
	return job_aliases.get(raw_id, raw_id)


func _load_job_data() -> void:
	"""Load job definitions from data/jobs.json"""
	var file_path = "res://data/jobs.json"

	# Tick 275: full 4-stage loud-fail (matches BestiarySystem._load_json
	# pattern). Pre-fix the file-missing case used `print()` (invisible
	# in Godot's debug output) and the file-open-fail case silently
	# fell through to defaults. Result: a missing/unreadable jobs.json
	# silently replaced the 14 jobs with the ~5 hardcoded fallback,
	# losing every advanced/meta job (Time Mage, Necromancer, etc.) and
	# the player got no signal that data went wrong.
	if not FileAccess.file_exists(file_path):
		push_warning("[JobSystem] jobs.json not found at %s — falling back to hardcoded defaults (advanced/meta jobs lost)" % file_path)
		_create_default_jobs()
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("[JobSystem] jobs.json exists but FileAccess.open failed — falling back to hardcoded defaults")
		_create_default_jobs()
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_warning("[JobSystem] jobs.json parse error: %s — falling back to hardcoded defaults" % json.get_error_message())
		_create_default_jobs()
		return

	if not (json.data is Dictionary):
		push_warning("[JobSystem] jobs.json parsed but root is not a Dictionary — falling back to hardcoded defaults (286 abilities / 14 jobs would be lost)")
		_create_default_jobs()
		return

	jobs = json.data
	print("Loaded %d jobs" % jobs.size())


func _load_ability_data() -> void:
	"""Load ability definitions from data/abilities.json"""
	var file_path = "res://data/abilities.json"

	if not FileAccess.file_exists(file_path):
		push_warning("[JobSystem] abilities.json not found at %s — falling back to hardcoded defaults" % file_path)
		_create_default_abilities()
		return

	# Tick 275: file-open-fail path now warns instead of silently falling
	# through to defaults (matches the _load_job_data fix above).
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("[JobSystem] abilities.json exists but FileAccess.open failed — falling back to hardcoded defaults")
		_create_default_abilities()
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_warning("[JobSystem] abilities.json parse error: %s — falling back to hardcoded defaults" % json.get_error_message())
		_create_default_abilities()
		return

	if not (json.data is Dictionary):
		push_warning("[JobSystem] abilities.json parsed but root is not a Dictionary — falling back to hardcoded defaults")
		_create_default_abilities()
		return

	abilities = json.data
	print("Loaded %d abilities" % abilities.size())


func _create_default_jobs() -> void:
	"""Create default starter jobs if file doesn't exist"""
	jobs = {
		# Tick 318: all stat_modifiers now include max_mp. Pre-fix every
		# fallback job dropped the field — recalculate_stats's
		# `if job_mods.has("max_mp")` then never fired, so casters fell
		# back to Combatant.base_max_mp default (50) instead of their
		# canonical jobs.json value (cleric 70, mage 80, bard 65...).
		# If jobs.json failed to load (push_warning on missing / parse /
		# non-Dict-root), every caster was silently down 15-30 max MP.
		# Values mirror data/jobs.json exactly.
		"fighter": {
			"id": "fighter",
			"name": "Fighter",
			"type": JobType.STARTER,
			"description": "A warrior skilled in physical combat",
			"stat_modifiers": {
				"max_hp": 120,
				"max_mp": 30,
				"attack": 15,
				"defense": 12,
				"magic": 5,
				"speed": 8
			},
			"abilities": ["power_strike", "provoke"],
			"passive_abilities": ["weapon_mastery"]
		},
		"cleric": {
			"id": "cleric",
			"name": "Cleric",
			"type": JobType.STARTER,
			"description": "A healer who uses restorative magic",
			"stat_modifiers": {
				"max_hp": 80,
				"max_mp": 70,
				"attack": 5,
				"defense": 8,
				"magic": 18,
				"speed": 10
			},
			"abilities": ["cure", "protect"],
			"passive_abilities": ["healing_boost"]
		},
		"mage": {
			"id": "mage",
			"name": "Mage",
			"type": JobType.STARTER,
			"description": "A mage who wields destructive magic",
			"stat_modifiers": {
				"max_hp": 70,
				"max_mp": 80,
				"attack": 5,
				"defense": 6,
				"magic": 20,
				"speed": 9
			},
			"abilities": ["fire", "blizzard", "thunder"],
			"passive_abilities": ["magic_boost"]
		},
		"bard": {
			"id": "bard",
			"name": "Bard",
			"type": JobType.STARTER,
			"description": "A performer who uses songs to buff allies and debuff enemies",
			"stat_modifiers": {
				"max_hp": 85,
				"max_mp": 65,
				"attack": 8,
				"defense": 7,
				"magic": 16,
				"speed": 14
			},
			"abilities": ["battle_hymn", "lullaby", "discord", "inspiring_melody"],
			"passive_abilities": ["encore"]
		},
		# Tick 295: rogue was missing from the defaults fallback —
		# a real gap (rogue is a starter job per CLAUDE.md and ships
		# in every default party). When data/jobs.json was missing or
		# broken, the rogue slot lost stat_modifiers, abilities, and
		# passives — silently degrading to whatever JobMenu / sprite
		# loader fell back to. Stats mirror the live jobs.json shape
		# (90 HP / 13 attack / 16 speed — speed-stat striker).
		"rogue": {
			"id": "rogue",
			"name": "Rogue",
			"type": JobType.STARTER,
			"description": "A nimble striker who relies on speed, evasion, and critical strikes",
			"stat_modifiers": {
				"max_hp": 90,
				"max_mp": 40,
				"attack": 13,
				"defense": 8,
				"magic": 7,
				"speed": 16
			},
			"abilities": ["sneak_attack", "steal", "smoke_bomb", "vanish"],
			"passive_abilities": ["evasion_up"]
		},
		"scriptweaver": {
			"id": "scriptweaver",
			"name": "Scriptweaver",
			"type": JobType.META,
			"description": "A meta job that can edit game formulas and constants",
			"stat_modifiers": {
				"max_hp": 90,
				"max_mp": 60,
				"attack": 10,
				"defense": 10,
				"magic": 15,
				"speed": 12
			},
			"abilities": ["edit_formula", "modify_constant", "analyze_code"],
			"passive_abilities": ["formula_sight", "autobattle_verbs"],
			"meta_powers": {
				"can_edit_damage_formulas": true,
				"can_modify_exp_rates": true,
				"can_view_game_constants": true
			}
		}
	}


func _create_default_abilities() -> void:
	"""Create default abilities if file doesn't exist"""
	abilities = {
		"power_strike": {
			"id": "power_strike",
			"name": "Power Strike",
			"type": "physical",
			"mp_cost": 8,
			"description": "A powerful physical attack dealing 1.5x damage",
			"damage_multiplier": 1.5,
			"target_type": "single_enemy"
		},
		"provoke": {
			"id": "provoke",
			"name": "Provoke",
			"type": "support",
			"mp_cost": 5,
			"description": "Force an enemy to target you",
			"target_type": "single_enemy",
			"effect": "taunt"
		},
		"cure": {
			"id": "cure",
			"name": "Cure",
			"type": "healing",
			"mp_cost": 6,
			"description": "Restore HP to one ally",
			"heal_amount": 50,
			"target_type": "single_ally"
		},
		"cura": {
			"id": "cura",
			"name": "Cura",
			"type": "healing",
			"mp_cost": 12,
			"description": "Restore HP to one ally",
			"heal_amount": 120,
			"target_type": "single_ally"
		},
		"raise": {
			"id": "raise",
			"name": "Raise",
			"type": "revival",
			"mp_cost": 20,
			"description": "Revive a fallen ally with 50% HP",
			"target_type": "dead_ally"
		},
		"fire": {
			"id": "fire",
			"name": "Fire",
			"type": "magic",
			"mp_cost": 8,
			"description": "Fire magic damage to one enemy",
			"damage_multiplier": 2.0,
			"element": "fire",
			"target_type": "single_enemy"
		},
		"blizzard": {
			"id": "blizzard",
			"name": "Blizzard",
			"type": "magic",
			"mp_cost": 8,
			"description": "Ice magic damage to one enemy",
			"damage_multiplier": 2.0,
			"element": "ice",
			"target_type": "single_enemy"
		},
		"thunder": {
			"id": "thunder",
			"name": "Thunder",
			"type": "magic",
			"mp_cost": 8,
			"description": "Lightning magic damage to one enemy",
			"damage_multiplier": 2.0,
			"element": "lightning",
			"target_type": "single_enemy"
		},
		"edit_formula": {
			"id": "edit_formula",
			"name": "Edit Formula",
			"type": "meta",
			"mp_cost": 30,
			"description": "Attempt to rewrite a damage formula. The formulas resist. The corruption is real.",
			"target_type": "self",
			"meta_effect": "formula_modification"
		},
		"modify_constant": {
			"id": "modify_constant",
			"name": "Modify Constant",
			"type": "meta",
			"mp_cost": 25,
			"description": "Change a game constant (EXP rate, drop rate, etc.)",
			"target_type": "self",
			"meta_effect": "constant_modification"
		},
		"analyze_code": {
			"id": "analyze_code",
			"name": "Analyze Code",
			"type": "meta",
			"mp_cost": 15,
			"description": "View the actual game code for current battle logic",
			"target_type": "self",
			"meta_effect": "code_inspection"
		},
		# Tick 296: rogue + bard abilities were missing from defaults
		# fallback. _create_default_jobs (tick 295) lists them in the
		# rogue / bard ability arrays but the actual ability dicts
		# weren't there — assign_job's downstream stat / passive
		# resolution would have surfaced 8 push_warnings on broken
		# data/abilities.json. Stats mirror the live abilities.json
		# shape (verified at tick time; minimal fields for fallback).
		# ---- Rogue ----
		"sneak_attack": {
			"id": "sneak_attack",
			"name": "Sneak Attack",
			"type": "physical",
			"mp_cost": 6,
			"description": "A surprise strike with high critical chance",
			"damage_multiplier": 1.4,
			"crit_chance_bonus": 0.5,
			"target_type": "single_enemy"
		},
		"steal": {
			"id": "steal",
			"name": "Steal",
			"type": "support",
			"mp_cost": 4,
			"description": "Attempt to steal an item from the target",
			"target_type": "single_enemy",
			"effect": "steal_item"
		},
		"smoke_bomb": {
			"id": "smoke_bomb",
			"name": "Smoke Bomb",
			"type": "support",
			"mp_cost": 8,
			"description": "Obscure the field — boost party evasion next turn",
			"target_type": "all_allies",
			"effect": "evasion_up"
		},
		"vanish": {
			"id": "vanish",
			"name": "Vanish",
			"type": "support",
			"mp_cost": 10,
			"description": "Become temporarily untargetable",
			"target_type": "self",
			"effect": "untargetable"
		},
		# ---- Bard ----
		"battle_hymn": {
			"id": "battle_hymn",
			"name": "Battle Hymn",
			"type": "support",
			"mp_cost": 8,
			"description": "Inspire allies — boost attack",
			"target_type": "all_allies",
			"effect": "attack_up"
		},
		"lullaby": {
			"id": "lullaby",
			"name": "Lullaby",
			"type": "status",
			"mp_cost": 10,
			"description": "Put enemies to sleep with a soft melody",
			"target_type": "all_enemies",
			"status_effect": "sleep"
		},
		"discord": {
			"id": "discord",
			"name": "Discord",
			"type": "status",
			"mp_cost": 12,
			"description": "Strike a dissonant chord — enemies take more damage",
			"target_type": "all_enemies",
			"effect": "defense_down"
		},
		"inspiring_melody": {
			"id": "inspiring_melody",
			"name": "Inspiring Melody",
			"type": "support",
			"mp_cost": 14,
			"description": "Restore party morale — grant +1 AP to each ally",
			"target_type": "all_allies",
			"effect": "ap_grant"
		}
	}


## Job management
func assign_job(combatant: Combatant, job_id: String) -> bool:
	"""Assign a job to a combatant"""
	job_id = resolve_job_id(job_id)
	if not jobs.has(job_id):
		## Tick 180: push_warning so this surfaces in CI / editor
		## warnings panel. Pre-fix print() only — silent failure
		## when a save-format-drift or Scriptweaver-corrupted job_id
		## tried to apply (assign_job returned false but nothing
		## upstream surfaced WHY).
		push_warning("[JobSystem] assign_job: job_id '%s' not found in jobs table — assignment failed" % job_id)
		return false

	var job = jobs[job_id]
	var old_job = combatant.job

	combatant.job = job
	_apply_job_stats(combatant, job)

	# Bard joins with their signature piano_scythe if they don't already
	# have a weapon equipped. Doesn't override existing equipment — the
	# player keeps whatever they had on a Bard pick. Inverse (leaving
	# bard) is intentionally a no-op; the scythe stays equipped if the
	# player liked it.
	if job_id == "bard" and combatant.equipped_weapon.is_empty():
		var equipment = get_node_or_null("/root/EquipmentSystem")
		if equipment and equipment.weapons.has("piano_scythe"):
			equipment.equip_weapon(combatant, "piano_scythe")

	# tick 59: retroactively grant any abilities the combatant should
	# already have at their current job_level. Without this, a save
	# loaded post-data-change wouldn't unlock the leveled abilities
	# until the next level-up — soft save break.
	if combatant.job_level > 1:
		learn_abilities_for_level(combatant, combatant.job_level)

	# Item 18 (2026-07-02): base kits are lean now — grant all level-
	# appropriate unlocks on EVERY assignment. Covers save-restore
	# (GameLoop assigns after from_dict), mid-game job swaps (a level-12
	# mage convert gets tier-appropriate spells), and new characters
	# (level 1 grants nothing). Idempotent via learn_ability dedupe.
	learn_abilities_for_level(combatant, combatant.job_level)
	job_changed.emit(combatant, old_job, job)
	return true


## tick 58: data-driven per-level ability unlocks. Reads the optional
## "abilities_at_level" field on a job's data:
##   "abilities_at_level": { "3": ["ability_id"], "6": [...] }
## Grants every ability whose level threshold has been crossed (NOT
## just the current level — covers level jumps from EXP overflow).
## Idempotent: existing learned abilities skip their grant.
##
## Returns the list of ability_ids granted on this call (empty if
## nothing crossed).
func learn_abilities_for_level(combatant: Combatant, new_level: int) -> Array:
	if not combatant or not is_instance_valid(combatant) or not combatant.job:
		return []
	var unlocks: Dictionary = combatant.job.get("abilities_at_level", {})
	if unlocks.is_empty():
		return []
	var granted: Array = []
	for level_key in unlocks.keys():
		var threshold: int = int(level_key)
		if threshold > new_level:
			continue
		var ids: Variant = unlocks[level_key]
		if not (ids is Array):
			continue
		for raw in ids:
			var ability_id: String = str(raw)
			if ability_id == "":
				continue
			# Combatant.learn_ability handles dedupe — if the ability
			# is already known, this no-ops cleanly.
			if combatant.has_method("learn_ability"):
				if combatant.learn_ability(ability_id):
					granted.append(ability_id)
					if combatant.has_signal("ability_learned"):
						combatant.ability_learned.emit(ability_id)
	return granted


## Item 18 dev toggle: ON grants every level-gated ability to the
## party (test without grinding); OFF strips exactly the unlocks
## ABOVE each member's current level — legitimately-earned spells
## stay. Deterministic from data, no grant-markers needed.
func set_dev_full_kits(enabled: bool, party_members: Array) -> void:
	for pc in party_members:
		if pc == null or not is_instance_valid(pc) or not (pc is Combatant):
			continue
		if pc.job == null or not (pc.job is Dictionary):
			continue
		if enabled:
			learn_abilities_for_level(pc, 99)
			continue
		var unlocks: Dictionary = pc.job.get("abilities_at_level", {})
		for level_key in unlocks:
			if int(level_key) <= pc.job_level:
				continue
			for aid in unlocks[level_key]:
				# Shop-bought spells are gold-paid knowledge — never strip.
				if "purchased_abilities" in pc and str(aid) in pc.purchased_abilities:
					continue
				pc.learned_abilities.erase(str(aid))


func assign_secondary_job(combatant: Combatant, job_id: String) -> bool:
	"""Assign a secondary job to a combatant (visual accents + minor stat boost)."""
	job_id = resolve_job_id(job_id)
	if not jobs.has(job_id):
		push_warning("Secondary job '%s' not found" % job_id)
		return false
	combatant.secondary_job = jobs[job_id]
	combatant.secondary_job_id = job_id
	secondary_job_changed.emit(combatant, job_id)
	return true


func _apply_job_stats(combatant: Combatant, job: Dictionary) -> void:
	"""Apply job stat modifiers to combatant"""
	if not job.has("stat_modifiers"):
		return

	var mods = job["stat_modifiers"]

	if mods.has("max_hp"):
		combatant.max_hp = mods["max_hp"]
		combatant.current_hp = combatant.max_hp
	# Tick 328: max_mp was missing from this 5-stat copy. Pre-fix a
	# freshly-assigned job left max_mp at Combatant.base_max_mp (50)
	# instead of the job's canonical value (Cleric 70, Mage 80, Bard
	# 65). The gap only closed when something else triggered
	# recalculate_stats — a level-up, an equip/unequip, or a passive
	# change. Same omission class as ticks 287/316/317/318 — every
	# 5-stat tuple needs to be 6 to include max_mp.
	if mods.has("max_mp"):
		combatant.max_mp = mods["max_mp"]
		combatant.current_mp = combatant.max_mp
	if mods.has("attack"):
		combatant.attack = mods["attack"]
	if mods.has("defense"):
		combatant.defense = mods["defense"]
	if mods.has("magic"):
		combatant.magic = mods["magic"]
	if mods.has("speed"):
		combatant.speed = mods["speed"]


func get_job(job_id: String) -> Dictionary:
	"""Get job data by ID"""
	job_id = resolve_job_id(job_id)
	return jobs.get(job_id, {})


func get_job_abilities(job_id: String) -> Array:
	"""Get all abilities for a job"""
	job_id = resolve_job_id(job_id)
	var job = get_job(job_id)
	if not job.has("abilities"):
		return []
	return job["abilities"]


func get_ability(ability_id: String) -> Dictionary:
	"""Get ability data by ID"""
	return abilities.get(ability_id, {})


## Tick 374: canonical MP-cost resolver. Applies the passive
## `mp_cost_multiplier` mod so passives like `mp_efficiency` (0.75x),
## `magic_amplifier` (2.5x), and `elemental_affinity` (0.75x) actually
## affect ability MP cost. Pre-fix PassiveSystem.get_passive_mods
## accumulated the mod but no caller ever read it — three passives
## were silent no-ops, players saw "-25% MP cost" descriptions and
## got nothing. Symmetric with tick 373's healing_multiplier wiring.
## Clamped to [0.1, 10.0] safety band (matches healing/damage clamps)
## so a typo'd passive can't black-hole or runaway MP cost.
func get_ability_mp_cost(combatant: Combatant, ability_id: String) -> int:
	var ability: Dictionary = get_ability(ability_id)
	if ability.is_empty():
		return 0
	var base: int = int(ability.get("mp_cost", 0))
	if base <= 0:
		return 0
	if combatant == null or not is_instance_valid(combatant):
		return base
	var tree: SceneTree = get_tree() if has_method("get_tree") else null
	var ps: Node = tree.root.get_node_or_null("PassiveSystem") if tree else null
	if ps == null or not ps.has_method("get_passive_mods"):
		return base
	var mods: Dictionary = ps.get_passive_mods(combatant)
	var mult: float = clampf(float(mods.get("mp_cost_multiplier", 1.0)), 0.1, 10.0)
	# max(0, ...) guards against int truncation of a 0.0001 multiplier
	# accidentally rounding to a 0 cost that lets the player spam an
	# expensive ability for free.
	return max(0, int(round(base * mult)))


func can_use_ability(combatant: Combatant, ability_id: String) -> bool:
	"""Check if combatant can use an ability (ability_id is an ability, not a job)"""
	var ability = get_ability(ability_id)
	if ability.is_empty():
		return false

	# Check MP cost — route through get_ability_mp_cost so passive
	# mp_cost_multiplier mods apply (tick 374).
	if ability.has("mp_cost"):
		var cost: int = get_ability_mp_cost(combatant, ability_id)
		if combatant.current_mp < cost:
			return false

	# Check job restrictions (allow if in job abilities OR learned abilities)
	var in_job = combatant.job and combatant.job.has("abilities") and ability_id in combatant.job["abilities"]
	var in_learned = combatant.has_learned_ability(ability_id)
	if not in_job and not in_learned:
		return false

	return true


## Utility
func get_jobs_by_type(type: JobType) -> Array:
	"""Get all jobs of a specific type"""
	var filtered_jobs = []
	for job_id in jobs:
		var job = jobs[job_id]
		if job.get("type", JobType.STARTER) == type:
			filtered_jobs.append(job)
	return filtered_jobs


func get_starter_jobs() -> Array:
	"""Get all starter jobs"""
	return get_jobs_by_type(JobType.STARTER)


func get_meta_jobs() -> Array:
	"""Get all meta jobs"""
	return get_jobs_by_type(JobType.META)


## Tick 467: check whether a job is unlocked for the current save.
## jobs.json authors `unlock_condition` on every advanced/meta job
## (guardian wants chapter 2, ninja wants speed_demon achievement,
## bossbinder wants 10 boss defeats, etc.) but pre-tick no code
## path read it — the JobMenu gated advanced/meta jobs purely on
## debug_log_enabled, which meant either ALL advanced/meta jobs
## were shown or none, with no progression in between.
##
## Resolution shape per condition type:
##   - "story":      checks cutscene_flag_chapterN_complete
##   - "boss_defeat": counts GameState.previously_fought_bosses
##                    (tick 453 populates that list)
##   - "completion": checks game_complete flag (tick 108 sets it
##                    on world6_ending)
##   - "achievement": opt-in flag of the same name in story_flags;
##                    no achievement system yet, so unset = locked
##
## Starters (type 0) are always unlocked. Debug mode also unlocks
## everything (preserves the existing JobMenu shortcut for
## development).
func is_job_unlocked(job_id: String) -> bool:
	var job_data: Dictionary = get_job(job_id)
	if job_data.is_empty():
		return false
	var job_type: int = int(job_data.get("type", 0))
	if job_type == 0:
		return true
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "debug_log_enabled" in gs and bool(gs.debug_log_enabled):
		return true
	var cond: Variant = job_data.get("unlock_condition", {})
	if not (cond is Dictionary) or (cond as Dictionary).is_empty():
		return false
	var ctype: String = str((cond as Dictionary).get("type", ""))
	match ctype:
		"story":
			var chapter: int = int((cond as Dictionary).get("chapter", 0))
			if chapter <= 0:
				return false
			if gs == null or not ("game_constants" in gs):
				return false
			return bool(gs.game_constants.get("cutscene_flag_chapter%d_complete" % chapter, false))
		"boss_defeat":
			var need: int = int((cond as Dictionary).get("boss_count", 1))
			if gs == null or not ("previously_fought_bosses" in gs):
				return false
			return gs.previously_fought_bosses.size() >= need
		"completion":
			if gs == null or not ("game_constants" in gs):
				return false
			return bool(gs.game_constants.get("game_complete", false))
		"achievement":
			var achievement_id: String = str((cond as Dictionary).get("id", ""))
			if achievement_id == "" or gs == null:
				return false
			if gs.has_method("is_story_flag_set"):
				return bool(gs.is_story_flag_set(achievement_id))
			return false
	return false
