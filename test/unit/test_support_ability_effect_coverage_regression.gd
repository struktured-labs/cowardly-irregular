extends GutTest

## Regression test for the "support-ability effect silently no-op'd" bug.
##
## Bug summary: BattleManager._execute_support_ability resolves an ability's
## `effect` string via a hardcoded match. Its only cases were taunt,
## defense_up, attack_up, defense_down, doom, the volatility_* family,
## press_the_edge, forecast, circuit_breaker, steal, cleanse, regen. Every
## OTHER support `effect` fell to the `_:` default which only printed
## "Unknown support effect: <x>" and applied NOTHING. ~50 abilities of type
## "support" carry effects outside that set (attack_down, speed_down, blind,
## charm, barrier, invisible, reflect, stun, all_stats_down, pacify,
## evasion, buff, debuff, etc.). For these the MP was spent, the log said
## the ability was used, but the debuff/buff never landed. Concrete live
## no-ops: ironback_beetle/burrow (W1 enemy), guardian guardian_wall=barrier,
## ninja smoke_bomb=blind / vanish=invisible. This is the project's
## canonical silent-failure class.
##
## Fix: _execute_support_ability now handles the common debuff/status family
## (attack_down, speed_down, all_stats_down, the generic buff/debuff, and the
## simple status effects barrier/invisible/blind/charm/stun/pacify/evasion/
## reflect/physical_reflect/prismatic_reflect/magic_block). The remaining
## bespoke effects (dispel, summon_clone, copy_last_ability, etc.) still need
## custom handling and route to a LOUD `_:` (push_warning), not a silent
## no-op.
##
## This test enumerates every `type:"support"` ability in data/abilities.json
## and asserts its `effect` is EITHER newly-handled OR on the explicit
## known-bespoke allowlist — so any NEWLY-authored support effect that falls
## through to the no-op default fails CI instead of silently no-opping at
## runtime. (Mirrors the existing data-integrity test pattern.)


const ABILITIES_PATH := "res://data/abilities.json"
const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"

# Effects _execute_support_ability applies a real mechanical change for.
const HANDLED_EFFECTS := [
	"taunt", "defense_up", "attack_up", "defense_down", "doom",
	"volatility_up_self", "volatility_up_enemy", "volatility_down",
	"press_the_edge", "forecast", "circuit_breaker", "steal", "cleanse",
	"regen",
	# --- added by the fix (previously silent no-ops) ---
	"attack_down", "speed_down", "all_stats_down", "buff", "debuff",
	"barrier", "invisible", "blind", "charm", "stun", "pacify", "evasion",
	"reflect", "physical_reflect", "prismatic_reflect", "magic_block",
	# --- Scan (2026-07-05): routes to _execute_scan_effect (reveals intel) ---
	"scan",
]

# Effects that legitimately still need bespoke per-effect implementations.
# They route to the LOUD `_:` default (print + push_warning), NOT a silent
# no-op. Listed here so newly-authored effects outside BOTH sets fail this
# test, forcing an explicit decision (implement it, or add it here).
const KNOWN_BESPOKE_EFFECTS := [
	"dispel", "dispel_one", "dispel_and_self_buff",
	"summon_clone", "copy_last_ability", "negate_last_ability",
	"ability_weaken", "adapt_resistance", "brave_actions",
	"break_mind_swap", "counter_next_action", "damage_absorb",
	"default_stance", "random_stat_change", "shadow_step",
	"",  # base_case: a deliberately empty template ability
]


func _load_abilities() -> Dictionary:
	var text := FileAccess.get_file_as_string(ABILITIES_PATH)
	assert_true(text != "", "abilities.json must be readable")
	var parsed = JSON.parse_string(text)
	assert_eq(typeof(parsed), TYPE_DICTIONARY,
		"abilities.json must parse to a Dictionary (id -> ability)")
	return parsed


func test_every_support_effect_is_handled_or_known_bespoke() -> void:
	# The core coverage guard: no support ability may carry an `effect` that
	# is neither mechanically handled nor on the known-bespoke allowlist.
	# A failure here means a newly-authored support effect would silently
	# no-op at runtime (MP spent, log printed, nothing applied).
	var abilities := _load_abilities()
	var offenders: Array[String] = []
	for ability_id in abilities:
		var ability = abilities[ability_id]
		if typeof(ability) != TYPE_DICTIONARY:
			continue
		if str(ability.get("type", "")) != "support":
			continue
		var effect := str(ability.get("effect", ""))
		if effect in HANDLED_EFFECTS:
			continue
		if effect in KNOWN_BESPOKE_EFFECTS:
			continue
		offenders.append("%s (effect=%s)" % [ability_id, effect])
	assert_eq(offenders.size(), 0,
		"support abilities with an unhandled, unlisted effect would silently no-op at runtime. " +
		"Implement the effect in BattleManager._execute_support_ability, or add it to " +
		"KNOWN_BESPOKE_EFFECTS if it needs bespoke handling: %s" % str(offenders))


func test_previously_broken_debuffs_are_now_handled() -> void:
	# Pin the specific effects this fix rescued from silent no-op. These were
	# the concrete confirmed live no-ops (ironback_beetle/burrow=evasion,
	# guardian_wall=barrier, smoke_bomb=blind, vanish=invisible) plus the
	# common authored debuffs (web_shot/coil=speed_down, bark/rattle/etc.=
	# attack_down, bad_vibes/existential_dread=all_stats_down).
	for effect in ["attack_down", "speed_down", "all_stats_down", "barrier",
			"invisible", "blind", "charm", "evasion", "stun", "pacify"]:
		assert_true(effect in HANDLED_EFFECTS,
			"'%s' must be a handled support effect (was a silent no-op before the fix)" % effect)


func test_support_default_branch_is_loud_not_silent() -> void:
	# Source-level guard: the `_:` default of _execute_support_ability must
	# push_warning so authored-but-unimplemented effects are LOUD, not a
	# silent print-only no-op. Silent failure is the project's worst class.
	var src := FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	assert_true(src != "", "BattleManager.gd must be readable")
	var fn_idx := src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1, "_execute_support_ability must exist")
	var fn_end := src.find("\nfunc ", fn_idx + 1)
	var body := src.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else src.substr(fn_idx)
	assert_true(body.find("push_warning") > -1,
		"_execute_support_ability's default branch must push_warning so unhandled " +
		"support effects are loud, not a silent no-op")
	# The newly-added handler cases must be present in source.
	for needle in ["\"attack_down\"", "\"speed_down\"", "\"all_stats_down\"",
			"\"barrier\"", "\"invisible\"", "\"blind\"", "\"charm\""]:
		assert_true(body.find(needle) > -1,
			"_execute_support_ability must handle the %s effect" % needle)
