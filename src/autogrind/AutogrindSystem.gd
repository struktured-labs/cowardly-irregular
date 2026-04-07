extends Node

## AutogrindSystem - Automated battle grinding with escalating risk/reward
## The more efficient you grind, the more dangerous it becomes
##
## Autogrind rules are party-level: IF [party condition] THEN [profile assignments]
## This mirrors the autobattle system but operates on the whole party:
##   Autobattle = per-character: IF [char condition] THEN [combat action]
##   Autogrind  = per-party:     IF [party condition] THEN [autobattle profile set]

signal grind_started()
signal grind_stopped(results: Dictionary)
signal battle_completed(battle_num: int, results: Dictionary)
signal efficiency_increased(new_multiplier: float)
signal corruption_increased(level: float)
signal interrupt_triggered(reason: String)
signal meta_boss_spawned(boss_name: String)
signal system_collapse()
signal region_cracked(region_id: String, crack_level: int)
signal region_advanced(from_region: String, to_region: String, world_num: int)
signal autobattle_interrupted(reason: String)
signal autogrind_rules_changed()
signal fatigue_event(event_type: String, description: String)

## World region progression order (world_num -> overworld map_id)
const WORLD_REGIONS: Array[Dictionary] = [
	{"world": 1, "region": "overworld", "name": "Medieval Overworld"},
	{"world": 2, "region": "suburban_overworld", "name": "Suburban Overworld"},
	{"world": 3, "region": "steampunk_overworld", "name": "Steampunk Overworld"},
	{"world": 4, "region": "industrial_overworld", "name": "Industrial Overworld"},
	{"world": 5, "region": "futuristic_overworld", "name": "Futuristic Overworld"},
	{"world": 6, "region": "abstract_overworld", "name": "Abstract Overworld"},
]

## System fatigue
var fatigue_events_triggered: int = 0
const FATIGUE_BATTLE_THRESHOLD: int = 30
const FATIGUE_CHANCE: float = 0.05

## Grind state
var is_grinding: bool = false
var battles_completed: int = 0
var total_exp_gained: int = 0
var total_items_gained: Dictionary = {}

## Efficiency system
var efficiency_multiplier: float = 1.0  # Increases rewards but also danger
var max_efficiency: float = 10.0
var efficiency_growth_rate: float = 0.1  # Per battle

## Region crack detection
var region_crack_levels: Dictionary = {}  # {region_id: crack_level}
var current_region_id: String = ""
var consecutive_wins: int = 0
var wins_to_crack_region: int = 20  # Wins needed to "crack" a region
var reward_penalty_per_crack: float = 0.15  # -15% rewards per crack level

## Meta-adaptation when cracked
var adaptation_on_crack: bool = true  # Monsters adapt when region cracked

## Danger scaling
var monster_adaptation_level: float = 0.0  # Enemies get stronger
var meta_corruption_level: float = 0.0     # Reality starts breaking
var corruption_threshold: float = 5.0      # When system collapse occurs

## Interrupt conditions
var interrupt_rules: Dictionary = {
	"hp_threshold": 20.0,      # Stop if any party member HP < 20%
	"party_death": true,       # Stop if any party member dies
	"item_depleted": true,     # Stop if healing items run out
	"corruption_limit": 4.5,   # Stop before system collapse
	"max_battles": 100         # Safety limit
}

## Permadeath staking (optional high-risk mode)
var permadeath_staking_enabled: bool = false
var permadeath_multiplier: float = 3.0  # 3x rewards but permanent death on wipe

## Meta-boss triggers
var meta_bosses_enabled: bool = true
var meta_boss_spawn_chance: float = 0.0  # Increases with corruption

## System collapse tracking
var collapse_count: int = 0                    # How many times collapse has occurred
var post_collapse_debuff_battles: int = 0      # Remaining battles with reduced max_efficiency

## Permadeath persistence — names of permanently dead characters (loaded/saved via user://autogrind/)
var permadead_characters: Array[String] = []
var permadeath_enabled: bool = false  # Alias for permadeath_staking_enabled (for UI binding)

## Adaptive AI pattern database
## {region_id: {ability_frequency: {}, target_priority: {}, common_opener: "", counter_strategy: "", battles_analyzed: int}}
var learned_patterns: Dictionary = {}

## Battle configuration for grinding
var grind_enemy_template: Dictionary = {}
var grind_party: Array[Combatant] = []

## ═══════════════════════════════════════════════════════════════════════
## COMBAT SATURATION INDEX (CSI) - Diminishing returns per region
## ═══════════════════════════════════════════════════════════════════════

## CSI constants
const CSI_BASE_GROWTH: float = 0.0025   # Base CSI growth per encounter
const CSI_DECAY_RATE: float = 0.01      # CSI decay per hour away from region
const YIELD_MIN: float = 0.35           # Minimum yield multiplier (never fully zero)
const YIELD_K: float = 2.0              # Yield decay steepness
const AA_ALPHA: float = 0.002           # Automation affinity EMA smoothing factor

## Per-region CSI values {region_id: float 0.0-1.0}
var _region_csi: Dictionary = {}

## Timestamps of last visit per region for decay calculation {region_id: float (unix time)}
var _csi_timestamps: Dictionary = {}

## Automation Affinity - meta tracking of how much the player automates (0.0-1.0)
var _automation_affinity: float = 0.0

## Time-based risk/reward multiplier breakpoints: [minutes, multiplier]
const TIME_MULTIPLIER_CURVE: Array = [
	[0.0, 1.0],
	[5.0, 1.5],
	[10.0, 2.0],
	[20.0, 3.0],
]

## Grind session statistics for per-minute rate tracking
var _grind_stats: Dictionary = {
	"start_time": 0.0,
	"total_exp": 0,
	"total_gold": 0,
	"total_jp": 0,
	"total_encounters": 0,
	"elapsed_seconds": 0.0
}

## Session history — last N completed grind sessions (persisted)
const MAX_SESSION_HISTORY: int = 10
const SESSION_HISTORY_PATH: String = "user://autogrind_history.json"
var session_history: Array = []  # Array of session summary dicts

## ═══════════════════════════════════════════════════════════════════════
## ADAPTIVE AI - Pattern Learning & Counter Strategy
## ═══════════════════════════════════════════════════════════════════════

func update_learned_patterns(region_id: String, battle_summary: Dictionary) -> void:
	"""Update pattern database with battle results"""
	if not learned_patterns.has(region_id):
		learned_patterns[region_id] = {
			"ability_frequency": {},
			"target_priority": {},
			"common_opener": "",
			"counter_strategy": "",
			"battles_analyzed": 0
		}

	var patterns = learned_patterns[region_id]

	if patterns["battles_analyzed"] >= 100:
		return

	patterns["battles_analyzed"] += 1

	# Merge ability frequencies — cap at 50 unique entries
	var ability_freq = patterns["ability_frequency"]
	for ability_id in battle_summary.get("ability_frequency", {}):
		var count = battle_summary["ability_frequency"][ability_id]
		if ability_freq.has(ability_id) or ability_freq.size() < 50:
			ability_freq[ability_id] = ability_freq.get(ability_id, 0) + count

	# Merge target priorities — cap at 50 unique entries
	var target_prio = patterns["target_priority"]
	for ttype in battle_summary.get("target_priority", {}):
		var count = battle_summary["target_priority"][ttype]
		if target_prio.has(ttype) or target_prio.size() < 50:
			target_prio[ttype] = target_prio.get(ttype, 0) + count

	# Track most common opener
	var opener = battle_summary.get("common_opener", "")
	if not opener.is_empty():
		patterns["common_opener"] = opener  # Most recent opener

	# Determine counter strategy
	patterns["counter_strategy"] = _determine_counter_strategy(patterns)


func _determine_counter_strategy(patterns: Dictionary) -> String:
	"""Determine best counter strategy based on learned patterns"""
	var abilities = patterns.get("ability_frequency", {})
	var targets = patterns.get("target_priority", {})

	# Find most used ability type
	var max_ability = ""
	var max_count = 0
	for ability_id in abilities:
		if abilities[ability_id] > max_count:
			max_count = abilities[ability_id]
			max_ability = ability_id

	# Determine counter based on patterns
	if max_ability.begins_with("fire") or max_ability == "fire":
		return "fire_resist"
	elif max_ability.begins_with("ice") or max_ability == "ice" or max_ability == "blizzard":
		return "ice_resist"
	elif max_ability.begins_with("thunder") or max_ability == "thunder":
		return "lightning_resist"
	elif max_ability == "cure" or max_ability == "heal":
		return "focus_healer"
	elif max_ability == "power_strike" or max_ability == "slash":
		return "defense_boost"

	# Check target patterns
	var lowest_hp_focus = targets.get("lowest_hp", 0)
	var total_targets = 0
	for t in targets.values():
		total_targets += t

	if total_targets > 0 and float(lowest_hp_focus) / total_targets > 0.7:
		return "rotate_aggro"

	return "generic_counter"


func get_adaptation_level_for_region(region_id: String) -> int:
	"""Get how adapted enemies are to player strategies in a region"""
	if not learned_patterns.has(region_id):
		return 0
	var battles = learned_patterns[region_id].get("battles_analyzed", 0)
	if battles >= 20:
		return 3  # Fully adapted
	elif battles >= 10:
		return 2  # Moderately adapted
	elif battles >= 5:
		return 1  # Slightly adapted
	return 0


func get_counter_strategy(region_id: String) -> String:
	"""Get the current counter strategy for a region"""
	if not learned_patterns.has(region_id):
		return ""
	return learned_patterns[region_id].get("counter_strategy", "")


func get_learned_patterns_for_region(region_id: String) -> Dictionary:
	"""Get all learned patterns for a region"""
	if not learned_patterns.has(region_id):
		return {}
	return learned_patterns[region_id]


## ═══════════════════════════════════════════════════════════════════════
## COMBAT SATURATION INDEX (CSI) - Diminishing Returns Per Region
## ═══════════════════════════════════════════════════════════════════════

func update_csi(region_id: String, encounter_type: String = "normal") -> void:
	"""Update CSI for a region after an encounter.
	DCSI = base_growth * encounter_weight * mode_weight * level_weight
	CSI is clamped to [0.0, 1.0]."""
	if not _region_csi.has(region_id):
		_region_csi[region_id] = 0.0

	# Encounter weight: normal=1.0, elite=2.0
	var encounter_weight: float = 1.0
	if encounter_type == "elite":
		encounter_weight = 2.0

	# Mode weight: autogrind=1.08, manual=1.0
	var mode_weight: float = 1.08 if is_grinding else 1.0

	# Level weight: scale by adaptation level (higher adaptation = faster saturation)
	var level_weight: float = 1.0 + monster_adaptation_level * 0.1

	var delta_csi: float = CSI_BASE_GROWTH * encounter_weight * mode_weight * level_weight

	# Smooth diminishing returns: growth scales down as CSI approaches 1.0
	# At CSI 0.0 = full growth, CSI 0.5 = 75% growth, CSI 0.8 = 36% growth, CSI 0.95 = 10% growth
	var current_csi = _region_csi[region_id]
	delta_csi *= (1.0 - current_csi * current_csi)

	_region_csi[region_id] = clampf(_region_csi[region_id] + delta_csi, 0.0, 1.0)

	# Record timestamp for this region
	_csi_timestamps[region_id] = Time.get_unix_time_from_system()


func get_yield_multiplier(region_id: String) -> float:
	"""Compute yield multiplier from CSI using exponential decay.
	Y(csi) = Y_min + (1 - Y_min) * exp(-k * csi)
	Returns a value in [Y_min, 1.0] -- higher CSI means lower yield."""
	var csi: float = get_csi(region_id)
	return YIELD_MIN + (1.0 - YIELD_MIN) * exp(-YIELD_K * csi)


func decay_all_csi(hours_elapsed: float) -> void:
	"""Decay CSI for all regions based on time away.
	CSI = max(0, CSI - decay_rate * hours_away)
	Called when loading a save or returning to a region."""
	if hours_elapsed <= 0.0:
		return
	for region_id in _region_csi.keys():
		var decay_amount: float = CSI_DECAY_RATE * hours_elapsed
		_region_csi[region_id] = maxf(0.0, _region_csi[region_id] - decay_amount)


func decay_csi(delta_seconds: float) -> void:
	if is_grinding:
		return
	# Real-time decay should match offline rate: CSI_DECAY_RATE per hour = CSI_DECAY_RATE/3600 per second
	var decay_per_sec = CSI_DECAY_RATE / 3600.0
	for region_id in _region_csi.keys():
		_region_csi[region_id] = maxf(0.0, _region_csi[region_id] - decay_per_sec * delta_seconds)


func get_csi(region_id: String) -> float:
	"""Get current CSI for a region (0.0 if never visited)."""
	return _region_csi.get(region_id, 0.0)


func update_automation_affinity(signal_type: String) -> void:
	"""Update automation affinity using exponential moving average.
	AA = (1 - alpha) * AA + alpha * S
	signal_type: "manual" (S=0), "autobattle" (S=0.3), "autogrind" (S=1.0)"""
	var s: float = 0.0
	match signal_type:
		"manual":
			s = 0.0
		"autobattle":
			s = 0.3
		"autogrind":
			s = 1.0
	_automation_affinity = (1.0 - AA_ALPHA) * _automation_affinity + AA_ALPHA * s


func get_automation_affinity() -> float:
	"""Get current automation affinity (0.0-1.0). Higher = more automated playstyle."""
	return _automation_affinity


func check_fatigue_event() -> Dictionary:
	if battles_completed < FATIGUE_BATTLE_THRESHOLD:
		return {}
	if randf() > FATIGUE_CHANCE:
		return {}

	fatigue_events_triggered += 1
	var event_type = ["screen_glitch", "enemy_boost", "party_debuff", "mp_drain", "item_loss", "exp_surge"][randi() % 6]
	var description = ""

	match event_type:
		"screen_glitch":
			description = "System instability detected — visual artifacts"
		"enemy_boost":
			description = "Enemies adapting — next battle +20% stats"
		"party_debuff":
			description = "System fatigue — party member weakened"
		"mp_drain":
			description = "System interference — MP reserves fluctuating"
		"item_loss":
			description = "Inventory anomaly — items corrupted"
		"exp_surge":
			description = "Reality fold — experience amplified!"

	fatigue_event.emit(event_type, description)
	return {"type": event_type, "description": description}


func check_fatigue_collapse() -> bool:
	if battles_completed < 50:
		return false
	if fatigue_events_triggered < 5:
		return false
	return randf() < 0.03


func get_grind_stats() -> Dictionary:
	"""Get grind session statistics with per-minute rates.
	Returns {exp_per_min, gold_per_min, jp_per_min, encounters_per_min,
	         total_exp, total_gold, total_encounters, elapsed_seconds}"""
	var elapsed: float = _grind_stats["elapsed_seconds"]
	if is_grinding and _grind_stats["start_time"] > 0.0:
		elapsed = Time.get_unix_time_from_system() - _grind_stats["start_time"]

	var minutes: float = maxf(elapsed / 60.0, 0.0001)  # Avoid division by zero

	var csi_val = get_csi(current_region_id) if not current_region_id.is_empty() else 0.0
	var yield_val = get_yield_multiplier(current_region_id) if not current_region_id.is_empty() else 1.0

	return {
		"exp_per_min": _grind_stats["total_exp"] / minutes,
		"gold_per_min": _grind_stats["total_gold"] / minutes,
		"jp_per_min": _grind_stats["total_jp"] / minutes,
		"encounters_per_min": _grind_stats["total_encounters"] / minutes,
		"total_exp": _grind_stats["total_exp"],
		"total_gold": _grind_stats["total_gold"],
		"total_encounters": _grind_stats["total_encounters"],
		"elapsed_seconds": elapsed,
		"fatigue_events_triggered": fatigue_events_triggered,
		"csi": csi_val,
		"yield_multiplier": yield_val,
		"automation_affinity": _automation_affinity,
	}


func get_time_multiplier() -> float:
	if not is_grinding or _grind_stats["start_time"] <= 0.0:
		return 1.0

	var elapsed_min = (Time.get_unix_time_from_system() - _grind_stats["start_time"]) / 60.0

	for i in range(TIME_MULTIPLIER_CURVE.size() - 1):
		var bp_start = TIME_MULTIPLIER_CURVE[i]
		var bp_end = TIME_MULTIPLIER_CURVE[i + 1]
		if elapsed_min <= bp_end[0]:
			var t = (elapsed_min - bp_start[0]) / max(bp_end[0] - bp_start[0], 0.001)
			return lerpf(bp_start[1], bp_end[1], clampf(t, 0.0, 1.0))

	return TIME_MULTIPLIER_CURVE[-1][1]


## ═══════════════════════════════════════════════════════════════════════
## CONTROLLER INTERFACE - Methods called by AutogrindController
## ═══════════════════════════════════════════════════════════════════════

func pre_battle_check() -> String:
	"""Check interrupt conditions before starting a battle.
	Returns empty string if OK to fight, or a reason string to stop."""
	return _check_interrupt_conditions()


func should_spawn_meta_boss() -> bool:
	"""Check if a meta-boss should spawn based on corruption level.
	Uses meta_boss_spawn_chance which scales with meta_corruption_level."""
	if not meta_bosses_enabled:
		return false
	return randf() < meta_boss_spawn_chance


func create_scaled_enemy_data(base_data: Dictionary) -> Dictionary:
	"""Scale a single enemy's stats by monster_adaptation_level.
	Returns a new dictionary with scaled stats."""
	var scaled: Dictionary = base_data.duplicate(true)
	var adaptation_bonus: float = monster_adaptation_level * 0.15  # +15% stats per level

	# Scale stats dictionary if present
	if scaled.has("stats"):
		var stats: Dictionary = scaled["stats"]
		for stat_key in stats.keys():
			if stats[stat_key] is int or stats[stat_key] is float:
				stats[stat_key] = int(stats[stat_key] * (1.0 + adaptation_bonus))

	# Also scale top-level stats (for backward compatibility with _create_adapted_enemy)
	for key in ["max_hp", "attack", "defense", "magic"]:
		if scaled.has(key):
			scaled[key] = int(scaled[key] * (1.0 + adaptation_bonus))

	# Apply meta-corruption effects
	if meta_corruption_level >= 2.0:
		scaled["corruption_effects"] = _get_corruption_effects()

	# Apply learned counter strategies for current region
	if not current_region_id.is_empty():
		var counter = get_counter_strategy(current_region_id)
		if counter != "":
			scaled["counter_strategy"] = counter

	return scaled


func on_battle_victory(exp_gained: int, items_gained: Dictionary = {}) -> void:
	"""Handle a battle victory during autogrind.
	Updates stats, CSI, efficiency, checks thresholds."""
	battles_completed += 1
	consecutive_wins += 1
	tick_post_collapse_debuff()

	# Apply yield multiplier from CSI
	var yield_mult: float = 1.0
	if not current_region_id.is_empty():
		yield_mult = get_yield_multiplier(current_region_id)

	# Apply region crack penalty
	var crack_penalty: float = _get_region_crack_penalty()

	# Combined reward scaling
	var reward_scale: float = yield_mult * (1.0 - crack_penalty)
	var adjusted_exp: int = int(exp_gained * reward_scale * get_time_multiplier())

	total_exp_gained += adjusted_exp

	# Track items
	for item_id in items_gained:
		var quantity = items_gained[item_id]
		if total_items_gained.has(item_id):
			total_items_gained[item_id] += quantity
		else:
			total_items_gained[item_id] = quantity

	# Award EXP to party
	for member in grind_party:
		if member is Combatant and member.is_alive:
			member.gain_job_exp(adjusted_exp)

	# Derive JP: 1 base JP per battle, scaled by yield and efficiency
	var jp_gained: int = maxi(1, int(1.0 * reward_scale * efficiency_multiplier))

	# Update grind stats tracking
	_grind_stats["total_exp"] += adjusted_exp
	_grind_stats["total_gold"] += int(items_gained.get("gold", 0) * reward_scale)
	_grind_stats["total_jp"] += jp_gained
	_grind_stats["total_encounters"] += 1

	# Update CSI for current region
	if not current_region_id.is_empty():
		update_csi(current_region_id)

	# Update automation affinity
	update_automation_affinity("autogrind")

	# Check region crack
	_check_region_crack()

	# Increase efficiency and danger
	_increase_efficiency()

	# Log if yield is significantly reduced
	if yield_mult < 0.7 or crack_penalty > 0:
		print("[AUTOGRIND] Yield: %.0f%% (CSI: %.2f, Crack: -%.0f%%)" % [
			reward_scale * 100.0, get_csi(current_region_id), crack_penalty * 100.0
		])

	battle_completed.emit(battles_completed, {
		"victory": true,
		"exp_gained": adjusted_exp,
		"items_gained": items_gained,
		"yield_multiplier": yield_mult
	})


func on_battle_defeat() -> void:
	"""Handle a battle defeat during autogrind.
	Resets consecutive wins, checks permadeath, stops grind."""
	consecutive_wins = 0
	_grind_stats["total_encounters"] += 1
	tick_post_collapse_debuff()

	# Update automation affinity (still autogrinding even on defeat)
	update_automation_affinity("autogrind")

	if permadeath_staking_enabled or permadeath_enabled:
		_trigger_permadeath()
		return  # _trigger_permadeath calls stop_autogrind

	stop_autogrind("Party defeated")


## ═══════════════════════════════════════════════════════════════════════
## AUTOGRIND PROFILES - Party-level rule management
## ═══════════════════════════════════════════════════════════════════════

## Autogrind profiles (named rulesets for party-level automation)
## Format: {profiles: [{name: String, rules: Array}, ...], active: int}
var autogrind_profiles: Dictionary = {}

## Max profiles (GBA-style limit)
const MAX_AUTOGRIND_PROFILES: int = 8

## Max rules per profile
const MAX_AUTOGRIND_RULES: int = 12

## Max conditions per rule (AND chain)
const MAX_AUTOGRIND_CONDITIONS: int = 3

## Max actions per rule (profile assignments)
const MAX_AUTOGRIND_ACTIONS: int = 4

## Party-level condition types for autogrind rules
const PARTY_CONDITION_TYPES = {
	"party_hp_avg": "Party HP Avg",
	"party_mp_avg": "Party MP Avg",
	"party_hp_min": "Lowest HP %",
	"alive_count": "Alive Count",
	"battles_done": "Battles Done",
	"corruption": "Corruption",
	"efficiency": "Efficiency",
	"always": "Always"
}

## Operators (shared with autobattle)
const OPERATORS = {
	"<": "Less Than",
	"<=": "Less or Equal",
	"==": "Equal",
	">=": "Greater or Equal",
	">": "Greater Than",
	"!=": "Not Equal"
}

## Autogrind action types
const AUTOGRIND_ACTION_TYPES = {
	"switch_profile": "Switch Profile",
	"stop_grinding": "Stop Grinding"
}

## Default autogrind profile templates
const DEFAULT_AUTOGRIND_TEMPLATES = ["Standard Grind", "Safe Grind", "Aggressive Grind"]


func _ready() -> void:
	_load_autogrind_profiles()
	_load_learned_patterns()
	_load_csi_data()
	_load_permadead_characters()
	_load_session_history()


## Autogrind control
func start_autogrind(party: Array[Combatant], enemy_template: Dictionary, config: Dictionary = {}) -> void:
	"""Start automated grinding session"""
	if is_grinding:
		print("Autogrind already active!")
		return

	is_grinding = true
	battles_completed = 0
	total_exp_gained = 0
	total_items_gained.clear()
	efficiency_multiplier = 1.0
	monster_adaptation_level = 0.0
	meta_corruption_level = 0.0
	meta_boss_spawn_chance = 0.0

	grind_party = party.duplicate()
	grind_enemy_template = enemy_template.duplicate()

	# Initialize grind stats tracking
	_grind_stats = {
		"start_time": Time.get_unix_time_from_system(),
		"total_exp": 0,
		"total_gold": 0,
		"total_jp": 0,
		"total_encounters": 0,
		"elapsed_seconds": 0.0
	}

	# Decay CSI for regions based on time since last visit
	if not current_region_id.is_empty() and _csi_timestamps.has(current_region_id):
		var now: float = Time.get_unix_time_from_system()
		var last_visit: float = _csi_timestamps[current_region_id]
		var hours_away: float = (now - last_visit) / 3600.0
		if hours_away > 0.0:
			decay_all_csi(hours_away)

	# Apply custom config
	if config.has("interrupt_rules"):
		for key in config["interrupt_rules"]:
			interrupt_rules[key] = config["interrupt_rules"][key]

	if config.has("permadeath_staking"):
		var pd_enabled: bool = config["permadeath_staking"]
		permadeath_staking_enabled = pd_enabled
		permadeath_enabled = pd_enabled
		if pd_enabled:
			efficiency_growth_rate = 0.15  # 50% boost for permadeath staking

	grind_started.emit()
	print("=== AUTOGRIND STARTED ===")
	print("Efficiency: %.1fx | Corruption: %.2f | CSI: %.3f" % [
		efficiency_multiplier, meta_corruption_level,
		get_csi(current_region_id) if not current_region_id.is_empty() else 0.0
	])


func stop_autogrind(reason: String = "Manual stop") -> void:
	"""Stop autogrind and return results"""
	if not is_grinding:
		return

	is_grinding = false

	# Finalize grind stats elapsed time
	if _grind_stats["start_time"] > 0.0:
		_grind_stats["elapsed_seconds"] = Time.get_unix_time_from_system() - _grind_stats["start_time"]

	var stats: Dictionary = get_grind_stats()
	var results = {
		"battles_completed": battles_completed,
		"total_exp_gained": total_exp_gained,
		"total_items_gained": total_items_gained.duplicate(),
		"final_efficiency": efficiency_multiplier,
		"corruption_level": meta_corruption_level,
		"stop_reason": reason,
		"automation_affinity": _automation_affinity,
		"csi": get_csi(current_region_id) if not current_region_id.is_empty() else 0.0,
		"yield_multiplier": get_yield_multiplier(current_region_id) if not current_region_id.is_empty() else 1.0,
		"grind_stats": stats
	}

	grind_stopped.emit(results)

	# Record session in history
	_record_session(results, stats)

	print("=== AUTOGRIND STOPPED ===")
	print("Reason: %s" % reason)
	print("Battles: %d | EXP: %d | Efficiency: %.1fx" % [
		battles_completed, total_exp_gained, efficiency_multiplier
	])
	print("Yield: %.0f%% | AA: %.3f | EXP/min: %.1f" % [
		results["yield_multiplier"] * 100.0, _automation_affinity, stats["exp_per_min"]
	])



func _run_automated_battle() -> void:
	"""Run a single automated battle"""
	battles_completed += 1

	# Create adapted enemy (gets stronger with monster_adaptation_level)
	var enemy = _create_adapted_enemy()

	# Simulate battle (in full implementation, this would run actual battle)
	var battle_result = _simulate_battle(grind_party, [enemy])

	# Process results
	_process_battle_results(battle_result)

	# Increase efficiency and danger
	_increase_efficiency()

	battle_completed.emit(battles_completed, battle_result)


func _create_adapted_enemy() -> Dictionary:
	"""Create enemy adapted to player's efficiency (gets stronger)"""
	var enemy = grind_enemy_template.duplicate(true)

	# Apply monster adaptation (enemies scale with efficiency)
	var adaptation_bonus = monster_adaptation_level * 0.15  # +15% stats per level
	enemy["max_hp"] = int(enemy.get("max_hp", 100) * (1.0 + adaptation_bonus))
	enemy["attack"] = int(enemy.get("attack", 10) * (1.0 + adaptation_bonus))
	enemy["defense"] = int(enemy.get("defense", 10) * (1.0 + adaptation_bonus))
	enemy["magic"] = int(enemy.get("magic", 10) * (1.0 + adaptation_bonus))

	# Apply meta-corruption effects (enemies gain weird abilities)
	if meta_corruption_level >= 2.0:
		enemy["corruption_effects"] = _get_corruption_effects()

	return enemy


func _get_corruption_effects() -> Array:
	"""Get corruption-based enemy modifications"""
	var effects = []

	if meta_corruption_level >= 2.0:
		effects.append("reality_bending")  # Damage ignores defense

	if meta_corruption_level >= 3.0:
		effects.append("time_distortion")  # Acts twice per turn

	if meta_corruption_level >= 4.0:
		effects.append("stat_drain")  # Permanently reduces player stats

	return effects


func _simulate_battle(party: Array, enemies: Array) -> Dictionary:
	"""Simulate a battle (simplified for autogrind)"""
	# In full implementation, this would run actual battle
	# For now, simulate based on stats

	var party_power = 0.0
	for member in party:
		if member is Combatant:
			party_power += member.attack + member.magic + member.defense

	var enemy_power = 0.0
	for enemy in enemies:
		enemy_power += enemy.get("attack", 10) + enemy.get("magic", 10) + enemy.get("defense", 10)

	# Victory if party is stronger (with some randomness)
	var victory = (party_power > enemy_power * 0.8) and randf() < 0.9

	# Calculate rewards with efficiency multiplier
	var exp_gained = int(50 * efficiency_multiplier)
	if permadeath_staking_enabled:
		exp_gained = int(exp_gained * permadeath_multiplier)

	var items_gained = {}
	if victory and randf() < 0.3 * efficiency_multiplier:
		items_gained["potion"] = 1

	return {
		"victory": victory,
		"exp_gained": exp_gained,
		"items_gained": items_gained
	}


func _process_battle_results(result: Dictionary) -> void:
	"""Process battle results and update grind stats"""
	if result["victory"]:
		# Track consecutive wins for region crack detection
		consecutive_wins += 1
		_check_region_crack()

		# Apply region crack penalty to rewards
		var crack_penalty = _get_region_crack_penalty()
		var adjusted_exp = int(result["exp_gained"] * (1.0 - crack_penalty))

		total_exp_gained += adjusted_exp

		# Add items
		for item_id in result["items_gained"]:
			var quantity = result["items_gained"][item_id]
			if total_items_gained.has(item_id):
				total_items_gained[item_id] += quantity
			else:
				total_items_gained[item_id] = quantity

		# Award EXP to party
		for member in grind_party:
			if member is Combatant and member.is_alive:
				member.gain_job_exp(adjusted_exp)

		# Show penalty if region is cracked
		if crack_penalty > 0:
			print("[color=yellow]Region cracked! Rewards reduced by %.0f%%[/color]" % (crack_penalty * 100))
	else:
		# Defeat - reset consecutive wins
		consecutive_wins = 0

		# Check permadeath
		if permadeath_staking_enabled:
			_trigger_permadeath()
		stop_autogrind("Party defeated")


func _increase_efficiency() -> void:
	"""Increase efficiency multiplier and associated dangers"""
	var old_efficiency = efficiency_multiplier

	# Increase efficiency
	efficiency_multiplier = min(efficiency_multiplier + efficiency_growth_rate, max_efficiency)

	# Increase monster adaptation
	monster_adaptation_level += 0.05

	# Increase meta-corruption (danger!)
	var corruption_gain = 0.02 * efficiency_multiplier
	meta_corruption_level += corruption_gain

	# Increase meta-boss spawn chance
	meta_boss_spawn_chance = min(meta_corruption_level * 0.05, 0.3)

	if efficiency_multiplier > old_efficiency:
		efficiency_increased.emit(efficiency_multiplier)

	if meta_corruption_level >= corruption_threshold:
		_trigger_system_collapse()

	corruption_increased.emit(meta_corruption_level)


func _check_interrupt_conditions() -> String:
	"""Check if any interrupt conditions are met, returns reason or empty string"""
	# Check HP threshold
	if interrupt_rules.get("hp_threshold", 0) > 0:
		for member in grind_party:
			if member is Combatant and member.get_hp_percentage() < interrupt_rules["hp_threshold"]:
				return "HP threshold reached (%d%%)" % interrupt_rules["hp_threshold"]

	# Check party death
	if interrupt_rules.get("party_death", false):
		for member in grind_party:
			if member is Combatant and not member.is_alive:
				return "Party member died"

	# Check item depletion
	if interrupt_rules.get("item_depleted", false):
		var has_healing_items = false
		for member in grind_party:
			if member is Combatant:
				if member.get_item_count("potion") > 0 or member.get_item_count("hi_potion") > 0:
					has_healing_items = true
					break
		if not has_healing_items:
			return "Healing items depleted"

	# Check corruption limit
	if meta_corruption_level >= interrupt_rules.get("corruption_limit", 999.0):
		return "Corruption limit reached (%.1f)" % meta_corruption_level

	# Check max battles
	if battles_completed >= interrupt_rules.get("max_battles", 999):
		return "Max battles reached (%d)" % battles_completed

	return ""


func build_meta_boss_enemy_data(is_collapse_boss: bool = false) -> Dictionary:
	"""Load autogrind-spawnable monsters from monsters.json and build scaled enemy data.
	If is_collapse_boss, prefer null_entity/corrupted_sprite monsters; otherwise pick
	from the pool of autogrind_spawned monsters weighted by corruption level."""
	var monsters_path := "res://data/monsters.json"
	var file := FileAccess.open(monsters_path, FileAccess.READ)
	if not file:
		push_warning("[AUTOGRIND] Could not open monsters.json — falling back to generated boss data")
		return _build_fallback_meta_boss(is_collapse_boss)

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("[AUTOGRIND] Failed to parse monsters.json")
		return _build_fallback_meta_boss(is_collapse_boss)

	var all_monsters: Dictionary = json.data if json.data is Dictionary else {}

	# Separate collapse-candidate bosses from regular meta-boss pool
	var collapse_pool: Array = []
	var regular_pool: Array = []
	for monster_id in all_monsters:
		var m: Dictionary = all_monsters[monster_id]
		if not m.get("autogrind_spawned", false):
			continue
		var is_glitch: bool = m.get("glitch_enemy", false) or m.get("meta_enemy", false)
		if is_glitch:
			collapse_pool.append(m)
		else:
			regular_pool.append(m)

	var chosen: Dictionary
	if is_collapse_boss and not collapse_pool.is_empty():
		chosen = collapse_pool[randi() % collapse_pool.size()]
	elif not regular_pool.is_empty():
		chosen = regular_pool[randi() % regular_pool.size()]
	elif not collapse_pool.is_empty():
		chosen = collapse_pool[randi() % collapse_pool.size()]
	else:
		return _build_fallback_meta_boss(is_collapse_boss)

	# Build standardised enemy data dict from monsters.json entry
	var stats: Dictionary = chosen.get("stats", {})
	var enemy_data := {
		"id": chosen.get("id", "meta_boss"),
		"name": chosen.get("name", "Meta-Boss"),
		"color": Color(0.8, 0.2, 0.8),  # Purple tint for meta enemies
		"stats": stats.duplicate(true),
		"max_hp": stats.get("max_hp", 400),
		"attack": stats.get("attack", 30),
		"defense": stats.get("defense", 20),
		"magic": stats.get("magic", 25),
		"speed": stats.get("speed", 14),
		"exp_reward": chosen.get("exp_reward", 250),
		"gold_reward": chosen.get("gold_reward", 200),
		"abilities": chosen.get("abilities", []),
		"weaknesses": chosen.get("weaknesses", []),
		"resistances": chosen.get("resistances", []),
		"is_meta_boss": true,
		"is_collapse_boss": is_collapse_boss,
		"can_cause_permadeath": chosen.get("can_cause_permadeath", false),
		"drop_table": chosen.get("drop_table", [])
	}

	# Scale by corruption level (collapse bosses get extra scaling)
	var scale_factor := 1.0 + (meta_corruption_level * 0.2)
	if is_collapse_boss:
		scale_factor *= 1.5
	for stat_key in ["max_hp", "attack", "defense", "magic", "speed"]:
		if enemy_data.has(stat_key):
			enemy_data[stat_key] = int(enemy_data[stat_key] * scale_factor)

	# Collapse boss gets corruption effects automatically
	if is_collapse_boss:
		enemy_data["corruption_effects"] = _get_corruption_effects()

	return enemy_data


func _build_fallback_meta_boss(is_collapse_boss: bool) -> Dictionary:
	"""Fallback boss when monsters.json cannot be read"""
	var name_str := "NULL::ENTITY" if is_collapse_boss else _generate_meta_boss_name()
	var hp := int(600 * (1.0 + meta_corruption_level * 0.2))
	if is_collapse_boss:
		hp = int(hp * 1.5)
	return {
		"id": "null_entity" if is_collapse_boss else "meta_boss_generated",
		"name": name_str,
		"color": Color(0.5, 0.0, 0.8),
		"stats": {"max_hp": hp, "max_mp": 100, "attack": 40, "defense": 30, "magic": 35, "speed": 16},
		"max_hp": hp,
		"attack": 40,
		"defense": 30,
		"magic": 35,
		"speed": 16,
		"exp_reward": 500,
		"gold_reward": 300,
		"abilities": [],
		"weaknesses": [],
		"resistances": [],
		"is_meta_boss": true,
		"is_collapse_boss": is_collapse_boss,
		"can_cause_permadeath": is_collapse_boss,
		"drop_table": []
	}


func _spawn_meta_boss() -> Dictionary:
	"""Spawn a meta-boss due to corruption.
	Returns the enemy data dictionary so AutogrindController can launch a real battle.
	Does NOT stop the grind — the caller decides what to do with the result."""
	var boss_data := build_meta_boss_enemy_data(false)
	meta_boss_spawned.emit(boss_data.get("name", "Meta-Boss"))
	print("[AUTOGRIND] META-BOSS SPAWNED: %s (HP: %d)" % [boss_data["name"], boss_data["max_hp"]])
	return boss_data


func _generate_meta_boss_name() -> String:
	"""Generate creepy meta-boss name based on corruption"""
	var prefixes := ["Glitch", "Corrupted", "Fragmented", "Recursive", "Null"]
	var suffixes := ["Witness", "Observer", "Process", "Handler", "Exception"]
	return "%s %s" % [
		prefixes[randi() % prefixes.size()],
		suffixes[randi() % suffixes.size()]
	]


func on_meta_boss_victory(boss_data: Dictionary) -> void:
	"""Called by AutogrindController after the party defeats a meta-boss.
	Reduces corruption and awards bonus rewards."""
	var corruption_reduction := 0.5 + meta_corruption_level * 0.1
	meta_corruption_level = maxf(0.0, meta_corruption_level - corruption_reduction)
	print("[AUTOGRIND] Meta-boss defeated! Corruption reduced by %.2f (now %.2f)" % [
		corruption_reduction, meta_corruption_level
	])
	# Bonus EXP from meta-boss
	var bonus_exp: int = boss_data.get("exp_reward", 250)
	for member in grind_party:
		if member is Combatant and member.is_alive:
			member.gain_job_exp(bonus_exp)
	total_exp_gained += bonus_exp
	_grind_stats["total_exp"] += bonus_exp
	battle_completed.emit(battles_completed, {
		"victory": true,
		"exp_gained": bonus_exp,
		"items_gained": {},
		"meta_boss_defeated": true,
		"boss_name": boss_data.get("name", "Meta-Boss")
	})


func on_meta_boss_defeat(boss_data: Dictionary) -> void:
	"""Called by AutogrindController after the party loses to a meta-boss.
	Significantly increases corruption."""
	var corruption_increase := 1.5
	meta_corruption_level += corruption_increase
	consecutive_wins = 0
	print("[AUTOGRIND] Meta-boss defeated the party! Corruption increased by %.1f (now %.2f)" % [
		corruption_increase, meta_corruption_level
	])
	# Check if this now triggers system collapse
	if meta_corruption_level >= corruption_threshold:
		_trigger_system_collapse()


func _trigger_system_collapse() -> void:
	"""Trigger system collapse event (max corruption reached).
	Spawns a collapse boss. After the fight (win or lose), applies lasting penalties."""
	system_collapse.emit()
	collapse_count += 1

	# Lower corruption_threshold for every collapse (min 2.0)
	corruption_threshold = maxf(2.0, corruption_threshold - 0.5)

	print("[AUTOGRIND] === SYSTEM COLLAPSE (count: %d) ===" % collapse_count)
	print("[AUTOGRIND] Threshold lowered to %.1f" % corruption_threshold)
	print("[AUTOGRIND] Reality is fragmenting...")


func apply_post_collapse_penalty() -> void:
	"""Apply lasting post-collapse penalty: reduced max_efficiency for 10 battles.
	Called by AutogrindController after a collapse boss battle concludes."""
	# Reset corruption to 0 regardless of win/lose
	meta_corruption_level = 0.0
	meta_boss_spawn_chance = 0.0

	# Apply efficiency debuff for next 10 battles
	post_collapse_debuff_battles = 10
	var debuffed_max := maxf(2.0, max_efficiency * 0.5)
	max_efficiency = debuffed_max
	efficiency_multiplier = minf(efficiency_multiplier, max_efficiency)
	print("[AUTOGRIND] Post-collapse penalty: max_efficiency capped at %.1f for %d battles" % [
		max_efficiency, post_collapse_debuff_battles
	])


func tick_post_collapse_debuff() -> void:
	"""Decrement the post-collapse debuff counter after each battle.
	Called from on_battle_victory / on_battle_defeat."""
	if post_collapse_debuff_battles <= 0:
		return
	post_collapse_debuff_battles -= 1
	if post_collapse_debuff_battles == 0:
		# Restore original max_efficiency
		max_efficiency = 10.0
		print("[AUTOGRIND] Post-collapse debuff expired — max_efficiency restored to %.1f" % max_efficiency)


func _trigger_permadeath() -> void:
	"""Handle permadeath when staking is enabled.
	Kills the lowest-HP alive party member permanently and persists the death."""
	print("[AUTOGRIND] === PERMADEATH TRIGGERED ===")
	print("[AUTOGRIND] The grind claims a soul...")

	# Find the alive member with the lowest current HP
	var victim: Combatant = null
	var lowest_hp := INF
	for member in grind_party:
		if member is Combatant and member.is_alive:
			var hp := float(member.current_hp)
			if hp < lowest_hp:
				lowest_hp = hp
				victim = member

	if victim == null:
		# Full wipe — mark everyone permanently dead
		for member in grind_party:
			if member is Combatant:
				member.is_alive = false
				_persist_permadeath(member.combatant_name)
		stop_autogrind("PERMADEATH - Full party wipe with staking enabled")
		return

	# Kill only the lowest-HP member
	victim.is_alive = false
	victim.current_hp = 0
	_persist_permadeath(victim.combatant_name)
	print("[AUTOGRIND] %s has been permanently lost!" % victim.combatant_name)
	stop_autogrind("PERMADEATH - %s fell during staked autogrind" % victim.combatant_name)


func _persist_permadeath(character_name: String) -> void:
	"""Record a permanent character death in the permadead list and save to disk."""
	if character_name in permadead_characters:
		return
	permadead_characters.append(character_name)
	_save_permadead_characters()

	# Also record in GameState player_party data if the character exists there
	var game_state = get_node_or_null("/root/GameState")
	if game_state and "player_party" in game_state:
		for entry in game_state.player_party:
			if entry is Dictionary and entry.get("name", "") == character_name:
				entry["permadead"] = true
				break

	print("[AUTOGRIND] Persisted permadeath for: %s" % character_name)


func is_character_permadead(character_name: String) -> bool:
	"""Check if a character is permanently dead."""
	return character_name in permadead_characters


func _save_permadead_characters() -> void:
	"""Write the permadead list to user://autogrind/permadead.json"""
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("autogrind"):
		dir.make_dir("autogrind")

	var file := FileAccess.open("user://autogrind/permadead.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"permadead": permadead_characters}, "\t"))
		file.close()


func _load_permadead_characters() -> void:
	"""Load the permadead list from user://autogrind/permadead.json"""
	var save_path := "user://autogrind/permadead.json"
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		var names: Array = json.data.get("permadead", [])
		for n in names:
			if n is String and not n in permadead_characters:
				permadead_characters.append(n)
		print("[AUTOGRIND] Loaded %d permadead characters" % permadead_characters.size())
	file.close()


## Configuration
func set_interrupt_rule(rule_name: String, value: Variant) -> void:
	"""Set an interrupt rule"""
	interrupt_rules[rule_name] = value
	print("Interrupt rule set: %s = %s" % [rule_name, value])


func enable_permadeath_staking(enabled: bool) -> void:
	"""Enable/disable permadeath staking"""
	permadeath_staking_enabled = enabled
	permadeath_enabled = enabled
	if enabled:
		# 50% efficiency bonus while permadeath staking is active
		efficiency_growth_rate = 0.15
	else:
		efficiency_growth_rate = 0.1
	print("[AUTOGRIND] Permadeath staking: %s (growth rate: %.2f, %.1fx rewards)" % [
		"ENABLED" if enabled else "disabled",
		efficiency_growth_rate,
		permadeath_multiplier if enabled else 1.0
	])


## Region crack system
func set_current_region(region_id: String) -> void:
	"""Set the current region for crack tracking"""
	if current_region_id != region_id:
		current_region_id = region_id
		consecutive_wins = 0  # Reset on region change

		if not region_crack_levels.has(region_id):
			region_crack_levels[region_id] = 0


func _check_region_crack() -> void:
	"""Check if region should crack (player has mastered it)"""
	if current_region_id.is_empty():
		return

	if consecutive_wins >= wins_to_crack_region:
		# Region cracked! Increase crack level
		var old_level = region_crack_levels.get(current_region_id, 0)
		region_crack_levels[current_region_id] = old_level + 1
		consecutive_wins = 0  # Reset for next crack level

		var new_level = region_crack_levels[current_region_id]
		region_cracked.emit(current_region_id, new_level)

		print("[color=red]═══ REGION CRACKED ═══[/color]")
		print("The game has detected you've mastered this area!")
		print("Crack Level: %d" % new_level)
		print("Monsters will adapt - rewards decreased %.0f%%" % (new_level * reward_penalty_per_crack * 100))
		print("[color=yellow]Move to a new area or devise new strategies![/color]")

		# Apply meta-adaptation
		if adaptation_on_crack:
			_apply_meta_adaptation(new_level)


func _apply_meta_adaptation(crack_level: int) -> void:
	"""Apply meta-adaptation when region is cracked"""
	# Increase monster adaptation significantly
	monster_adaptation_level += crack_level * 0.3  # +30% stats per crack level

	# Monsters gain new behaviors
	print("[color=purple]Monsters are adapting...[/color]")
	if crack_level >= 1:
		print("  - Enemies now counter your common strategies")
	if crack_level >= 2:
		print("  - Enemies prioritize interrupting your autobattle logic")
	if crack_level >= 3:
		print("  - Enemies exploit weaknesses in your script")
		# Could trigger corruption increase
		meta_corruption_level += 0.5


func _get_region_crack_penalty() -> float:
	"""Get reward penalty based on region crack level"""
	if current_region_id.is_empty():
		return 0.0

	var crack_level = region_crack_levels.get(current_region_id, 0)
	return min(crack_level * reward_penalty_per_crack, 0.75)  # Max 75% penalty


func get_region_crack_level(region_id: String) -> int:
	"""Get crack level for a region"""
	return region_crack_levels.get(region_id, 0)


func is_region_cracked(region_id: String) -> bool:
	"""Check if a region is cracked"""
	return region_crack_levels.get(region_id, 0) > 0


func get_current_world_index() -> int:
	"""Get the WORLD_REGIONS index for the current region."""
	for i in range(WORLD_REGIONS.size()):
		if WORLD_REGIONS[i]["region"] == current_region_id:
			return i
	return 0


func get_next_region() -> Dictionary:
	"""Get the next region in world progression order. Returns empty if at end or locked."""
	var current_idx = get_current_world_index()
	var next_idx = current_idx + 1
	if next_idx >= WORLD_REGIONS.size():
		return {}  # Already at final world
	var next = WORLD_REGIONS[next_idx]
	# Check if the world is unlocked
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if not gs.is_world_unlocked(next["world"]):
			return {}  # World not unlocked yet
	return next


func advance_to_next_region() -> Dictionary:
	"""Advance to the next region if available. Returns the new region info or empty."""
	var next = get_next_region()
	if next.is_empty():
		return {}
	var old_region = current_region_id
	set_current_region(next["region"])
	region_advanced.emit(old_region, next["region"], next["world"])
	print("[AUTOGRIND] Advanced from %s to %s (World %d)" % [old_region, next["region"], next["world"]])
	return next


## Autobattle interrupt system
func check_autobattle_interrupt(combatant: Combatant) -> String:
	"""Check if autobattle should interrupt to manual control"""
	# Check HP danger
	if combatant.get_hp_percentage() < 30.0:
		return "Low HP - interrupting to manual control"

	# Check if about to die (enemy can one-shot)
	# In full implementation, would calculate enemy damage

	# Check if surrounded (multiple enemies targeting)
	# In full implementation, would check battle state

	return ""  # No interrupt


func interrupt_to_manual(reason: String) -> void:
	"""Interrupt autobattle/autogrind to manual control"""
	if is_grinding:
		stop_autogrind(reason)

	autobattle_interrupted.emit(reason)
	print("[color=orange]⚠ AUTOBATTLE INTERRUPTED ⚠[/color]")
	print("Reason: %s" % reason)
	print("Switching to manual control...")

	# In full implementation, would disable autobattle and return control to player


## ═══════════════════════════════════════════════════════════════════════
## AUTOGRIND PROFILE MANAGEMENT
## ═══════════════════════════════════════════════════════════════════════

func _ensure_autogrind_profiles() -> void:
	"""Ensure autogrind profiles are initialized"""
	if autogrind_profiles.is_empty() or not autogrind_profiles.has("profiles"):
		autogrind_profiles = _create_default_autogrind_profiles()


func _create_default_autogrind_profiles() -> Dictionary:
	"""Create default autogrind profile set"""
	var profile_list = []

	for i in range(DEFAULT_AUTOGRIND_TEMPLATES.size()):
		var profile_name = DEFAULT_AUTOGRIND_TEMPLATES[i]
		var profile_rules = _create_default_autogrind_rules() if i == 0 else _create_empty_autogrind_rules()
		profile_list.append({"name": profile_name, "rules": profile_rules})

	return {"profiles": profile_list, "active": 0}


func _create_default_autogrind_rules() -> Array:
	"""Create a sensible default autogrind ruleset"""
	return [
		# If party HP is critically low, switch everyone to defensive profiles
		{
			"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
			"actions": [
				{"type": "switch_profile", "character_id": "hero", "profile_index": 1},
				{"type": "switch_profile", "character_id": "mira", "profile_index": 0}
			],
			"enabled": true
		},
		# If only 2 members alive, stop grinding
		{
			"conditions": [{"type": "alive_count", "op": "<=", "value": 2}],
			"actions": [{"type": "stop_grinding"}],
			"enabled": true
		},
		# Default: use standard profiles
		{
			"conditions": [{"type": "always"}],
			"actions": [
				{"type": "switch_profile", "character_id": "hero", "profile_index": 0},
				{"type": "switch_profile", "character_id": "mira", "profile_index": 0}
			],
			"enabled": true
		}
	]


func _create_empty_autogrind_rules() -> Array:
	"""Create minimal empty autogrind ruleset"""
	return [
		{
			"conditions": [{"type": "always"}],
			"actions": [{"type": "switch_profile", "character_id": "hero", "profile_index": 0}],
			"enabled": true
		}
	]


func get_autogrind_rules() -> Array:
	"""Get active autogrind rules"""
	_ensure_autogrind_profiles()
	var data = autogrind_profiles
	var active_idx = data.get("active", 0)
	var profiles = data.get("profiles", [])
	if active_idx < profiles.size():
		return profiles[active_idx].get("rules", [])
	return _create_empty_autogrind_rules()


func set_autogrind_rules(rules: Array) -> void:
	"""Set active autogrind rules"""
	_ensure_autogrind_profiles()
	var active_idx = autogrind_profiles.get("active", 0)
	var profiles = autogrind_profiles.get("profiles", [])
	if active_idx < profiles.size():
		profiles[active_idx]["rules"] = rules
	_save_autogrind_profiles()
	autogrind_rules_changed.emit()


func get_autogrind_profiles() -> Array:
	"""Get all autogrind profiles"""
	_ensure_autogrind_profiles()
	return autogrind_profiles.get("profiles", [])


func get_active_autogrind_profile_index() -> int:
	"""Get index of active autogrind profile"""
	_ensure_autogrind_profiles()
	return autogrind_profiles.get("active", 0)


func get_active_autogrind_profile_name() -> String:
	"""Get name of active autogrind profile"""
	_ensure_autogrind_profiles()
	var active_idx = autogrind_profiles.get("active", 0)
	var profiles = autogrind_profiles.get("profiles", [])
	if active_idx < profiles.size():
		return profiles[active_idx].get("name", "Default")
	return "Default"


func set_active_autogrind_profile(index: int) -> void:
	"""Set active autogrind profile by index"""
	_ensure_autogrind_profiles()
	var profiles = autogrind_profiles.get("profiles", [])
	if index >= 0 and index < profiles.size():
		autogrind_profiles["active"] = index
		_save_autogrind_profiles()
		autogrind_rules_changed.emit()


func create_new_autogrind_profile(name: String = "") -> int:
	"""Create a new autogrind profile, returns index or -1 if at max"""
	_ensure_autogrind_profiles()
	var profiles = autogrind_profiles.get("profiles", [])

	if profiles.size() >= MAX_AUTOGRIND_PROFILES:
		return -1

	if name.is_empty():
		name = "Custom %d" % (profiles.size() + 1)

	profiles.append({
		"name": name,
		"rules": _create_empty_autogrind_rules()
	})

	_save_autogrind_profiles()
	return profiles.size() - 1


func rename_autogrind_profile(index: int, new_name: String) -> bool:
	"""Rename an autogrind profile"""
	_ensure_autogrind_profiles()
	var profiles = autogrind_profiles.get("profiles", [])

	if index < 0 or index >= profiles.size() or new_name.is_empty():
		return false

	profiles[index]["name"] = new_name
	_save_autogrind_profiles()
	return true


func delete_autogrind_profile(index: int) -> bool:
	"""Delete an autogrind profile (cannot delete last one)"""
	_ensure_autogrind_profiles()
	var profiles = autogrind_profiles.get("profiles", [])

	if profiles.size() <= 1 or index < 0 or index >= profiles.size():
		return false

	profiles.remove_at(index)

	var active = autogrind_profiles.get("active", 0)
	if active >= profiles.size():
		autogrind_profiles["active"] = profiles.size() - 1
	elif active > index:
		autogrind_profiles["active"] = active - 1

	_save_autogrind_profiles()
	return true


## ═══════════════════════════════════════════════════════════════════════
## AUTOGRIND RULE EVALUATION
## ═══════════════════════════════════════════════════════════════════════

func evaluate_autogrind_rules(party: Array) -> Dictionary:
	"""Evaluate autogrind rules against current party state.
	Returns the first matching rule's action set, or empty dict if none match."""
	var rules = get_autogrind_rules()

	for rule in rules:
		if not rule.get("enabled", true):
			continue

		if _evaluate_party_rule(party, rule):
			return rule

	return {}


func _evaluate_party_rule(party: Array, rule: Dictionary) -> bool:
	"""Evaluate a party-level rule (AND chain of conditions)"""
	var conditions = rule.get("conditions", [])
	if conditions.size() == 0:
		return true

	for condition in conditions:
		if not _evaluate_party_condition(party, condition):
			return false

	return true


func _evaluate_party_condition(party: Array, condition: Dictionary) -> bool:
	"""Evaluate a single party-level condition"""
	var cond_type = condition.get("type", "always")
	var op = condition.get("op", "==")
	var value = condition.get("value", 0)

	match cond_type:
		"party_hp_avg":
			var avg = _get_party_hp_avg(party)
			return _compare_op(avg, op, value)

		"party_mp_avg":
			var avg = _get_party_mp_avg(party)
			return _compare_op(avg, op, value)

		"party_hp_min":
			var min_hp = _get_party_hp_min(party)
			return _compare_op(min_hp, op, value)

		"alive_count":
			var count = _get_alive_count(party)
			return _compare_op(count, op, value)

		"battles_done":
			return _compare_op(battles_completed, op, value)

		"corruption":
			return _compare_op(meta_corruption_level, op, value)

		"efficiency":
			return _compare_op(efficiency_multiplier, op, value)

		"always":
			return true

	return false


func _compare_op(a: float, op: String, b: float) -> bool:
	"""Compare two values with string operator"""
	match op:
		"<": return a < b
		"<=": return a <= b
		"==": return a == b
		">=": return a >= b
		">": return a > b
		"!=": return a != b
	return false


func _get_party_hp_avg(party: Array) -> float:
	"""Get average HP percentage of alive party members"""
	var total = 0.0
	var count = 0
	for member in party:
		if member is Combatant and member.is_alive:
			total += member.get_hp_percentage()
			count += 1
	return total / max(count, 1)


func _get_party_mp_avg(party: Array) -> float:
	"""Get average MP percentage of alive party members"""
	var total = 0.0
	var count = 0
	for member in party:
		if member is Combatant and member.is_alive:
			total += member.get_mp_percentage()
			count += 1
	return total / max(count, 1)


func _get_party_hp_min(party: Array) -> float:
	"""Get lowest HP percentage in party"""
	var min_hp = 100.0
	for member in party:
		if member is Combatant and member.is_alive:
			min_hp = min(min_hp, member.get_hp_percentage())
	return min_hp


func _get_alive_count(party: Array) -> int:
	"""Get number of alive party members"""
	var count = 0
	for member in party:
		if member is Combatant and member.is_alive:
			count += 1
	return count


func apply_autogrind_actions(actions: Array) -> void:
	"""Apply autogrind rule actions (switch profiles, stop grinding, heal party, flee, etc.)"""
	for action in actions:
		var action_type = action.get("type", "")

		match action_type:
			"switch_profile":
				var char_id = action.get("character_id", "")
				var profile_idx = action.get("profile_index", 0)
				if char_id != "":
					var autobattle = get_node_or_null("/root/AutobattleSystem")
					if autobattle:
						autobattle.set_active_profile(char_id, profile_idx)
					print("[AUTOGRIND] Switched %s to profile %d" % [char_id, profile_idx])

			"stop_grinding":
				stop_autogrind("Autogrind rule triggered stop")

			"heal_party":
				# Restore 30% of max HP and MP for each living party member
				var heal_pct: float = action.get("value", 30.0) / 100.0
				for member in grind_party:
					if member is Combatant and member.is_alive:
						var hp_restore: int = int(member.max_hp * heal_pct)
						var mp_restore: int = int(member.max_mp * heal_pct)
						member.current_hp = min(member.current_hp + hp_restore, member.max_hp)
						member.current_mp = min(member.current_mp + mp_restore, member.max_mp)
				print("[AUTOGRIND] heal_party: restored %.0f%% HP/MP to living party members" % (heal_pct * 100.0))

			"flee_battle":
				# flee_battle is handled by AutogrindController (_skip_next_battle flag).
				# If apply_autogrind_actions is called directly (e.g. from old code paths),
				# fall back to stopping the grind so the action is never silently ignored.
				print("[AUTOGRIND] flee_battle action reached AutogrindSystem directly — stopping grind as fallback")
				stop_autogrind("Flee triggered by autogrind rule")


## ═══════════════════════════════════════════════════════════════════════
## AUTOGRIND PROFILE SAVE/LOAD
## ═══════════════════════════════════════════════════════════════════════

func _load_autogrind_profiles() -> void:
	"""Load autogrind profiles from file"""
	var save_path = "user://autogrind/profiles.json"

	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("autogrind"):
		dir.make_dir("autogrind")

	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(json_string) == OK:
				var data = json.data
				if data is Dictionary and data.has("profiles"):
					autogrind_profiles = data
					print("Loaded autogrind profiles (%d)" % data.get("profiles", []).size())
					return

	# No saved profiles, will create defaults on first access
	autogrind_profiles = {}


func _save_autogrind_profiles() -> void:
	"""Save autogrind profiles to file"""
	var save_path = "user://autogrind/profiles.json"

	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("autogrind"):
		dir.make_dir("autogrind")

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(autogrind_profiles, "\t")
		file.store_string(json_string)
		file.close()

	# Also save learned patterns and CSI data
	_save_learned_patterns()
	_save_csi_data()


func _save_learned_patterns() -> void:
	"""Save learned patterns to file"""
	var save_path = "user://autogrind/learned_patterns.json"

	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("autogrind"):
		dir.make_dir("autogrind")

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(learned_patterns, "\t")
		file.store_string(json_string)
		file.close()


func _load_learned_patterns() -> void:
	"""Load learned patterns from file"""
	var save_path = "user://autogrind/learned_patterns.json"

	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(json_string) == OK:
				var data = json.data
				if data is Dictionary:
					learned_patterns = data
					print("Loaded learned patterns (%d regions)" % data.size())
					return

	# No saved patterns
	learned_patterns = {}


## ═══════════════════════════════════════════════════════════════════════
## CSI / AUTOMATION AFFINITY SAVE/LOAD
## ═══════════════════════════════════════════════════════════════════════

func _save_csi_data() -> void:
	"""Save CSI and automation affinity data to file"""
	var save_path = "user://autogrind/csi_data.json"

	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("autogrind"):
		dir.make_dir("autogrind")

	var data = {
		"region_csi": _region_csi,
		"csi_timestamps": _csi_timestamps,
		"automation_affinity": _automation_affinity
	}

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data, "\t")
		file.store_string(json_string)
		file.close()


func _load_csi_data() -> void:
	"""Load CSI and automation affinity data from file"""
	var save_path = "user://autogrind/csi_data.json"

	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(json_string) == OK:
				var data = json.data
				if data is Dictionary:
					_region_csi = data.get("region_csi", {})
					_csi_timestamps = data.get("csi_timestamps", {})
					_automation_affinity = data.get("automation_affinity", 0.0)

					# Apply time-based decay since last save
					var now: float = Time.get_unix_time_from_system()
					for region_id in _csi_timestamps.keys():
						var last_time: float = _csi_timestamps[region_id]
						var hours_away: float = (now - last_time) / 3600.0
						if hours_away > 0.0 and _region_csi.has(region_id):
							_region_csi[region_id] = maxf(0.0, _region_csi[region_id] - CSI_DECAY_RATE * hours_away)

					print("Loaded CSI data (AA: %.3f, regions: %d)" % [
						_automation_affinity, _region_csi.size()
					])
					return

	# No saved CSI data
	_region_csi = {}
	_csi_timestamps = {}
	_automation_affinity = 0.0


func save_data() -> Dictionary:
	"""Serialize all persistent autogrind state for save files.
	Returns a dictionary suitable for JSON serialization."""
	# Save profiles and patterns to their own files
	_save_autogrind_profiles()

	return {
		"region_csi": _region_csi.duplicate(),
		"csi_timestamps": _csi_timestamps.duplicate(),
		"automation_affinity": _automation_affinity,
		"region_crack_levels": region_crack_levels.duplicate(),
		"current_region_id": current_region_id,
		"learned_patterns": learned_patterns.duplicate(true),
		"grind_stats": _grind_stats.duplicate()
	}


func load_data(data: Dictionary) -> void:
	"""Restore persistent autogrind state from a save file dictionary.
	Applies CSI decay based on time since last save."""
	if not data is Dictionary:
		return

	# Restore CSI data
	_region_csi = data.get("region_csi", {}).duplicate()
	_csi_timestamps = data.get("csi_timestamps", {}).duplicate()
	_automation_affinity = data.get("automation_affinity", 0.0)
	region_crack_levels = data.get("region_crack_levels", {}).duplicate()
	current_region_id = data.get("current_region_id", "")
	_grind_stats = data.get("grind_stats", {
		"start_time": 0.0,
		"total_exp": 0,
		"total_gold": 0,
		"total_jp": 0,
		"total_encounters": 0,
		"elapsed_seconds": 0.0
	}).duplicate()

	# Restore learned patterns
	var saved_patterns = data.get("learned_patterns", {})
	if saved_patterns is Dictionary and not saved_patterns.is_empty():
		learned_patterns = saved_patterns.duplicate(true)

	# Apply time-based CSI decay since last save
	var now: float = Time.get_unix_time_from_system()
	for region_id in _csi_timestamps.keys():
		var last_time: float = _csi_timestamps[region_id]
		var hours_away: float = (now - last_time) / 3600.0
		if hours_away > 0.0 and _region_csi.has(region_id):
			_region_csi[region_id] = maxf(0.0, _region_csi[region_id] - CSI_DECAY_RATE * hours_away)

	print("Loaded autogrind data (AA: %.3f, CSI regions: %d)" % [
		_automation_affinity, _region_csi.size()
	])


## ═══════════════════════════════════════════════════════════════════════
## SESSION HISTORY
## ═══════════════════════════════════════════════════════════════════════

func _record_session(results: Dictionary, stats: Dictionary) -> void:
	"""Record a completed grind session to history."""
	var entry = {
		"timestamp": Time.get_datetime_string_from_system(),
		"battles": results.get("battles_completed", 0),
		"total_exp": results.get("total_exp_gained", 0),
		"efficiency": results.get("final_efficiency", 1.0),
		"corruption": results.get("corruption_level", 0.0),
		"region": current_region_id,
		"reason": results.get("stop_reason", "Unknown"),
		"duration_sec": stats.get("elapsed_seconds", _grind_stats.get("elapsed_seconds", 0.0)),
		"exp_per_min": stats.get("exp_per_min", 0.0),
		"gold": stats.get("total_gold", 0),
		"collapses": collapse_count,
		"permadeaths": permadead_characters.size(),
	}
	session_history.append(entry)
	if session_history.size() > MAX_SESSION_HISTORY:
		session_history.remove_at(0)
	_save_session_history()


func get_session_history() -> Array:
	"""Get the session history array (most recent last)."""
	return session_history


func _save_session_history() -> void:
	"""Persist session history to file."""
	var file = FileAccess.open(SESSION_HISTORY_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(session_history, "\t"))
		file.close()


func _load_session_history() -> void:
	"""Load session history from file."""
	if not FileAccess.file_exists(SESSION_HISTORY_PATH):
		return
	var file = FileAccess.open(SESSION_HISTORY_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Array:
		session_history = json.data
		print("[AUTOGRIND] Loaded %d session history entries" % session_history.size())
	file.close()
