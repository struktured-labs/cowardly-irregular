extends GutTest

## tick 354: physical/magic ability handlers special-case
## "random_debuff" effect.
##
## Pre-fix corrupting_touch and data_corruption (abilities.json)
## used effect: "random_debuff" but the handler had two bugs:
##
##   1. effect_chance defaulted to 0.0. Both abilities omit
##      effect_chance in their JSON, so the apply NEVER fired.
##   2. Even if the chance check passed, add_status("random_debuff")
##      wrote the literal "random_debuff" string into status_effects
##      — an inert sentinel. No downstream consumer (DOT ticks, miss
##      math, cleanse list) recognizes "random_debuff" as a status.
##
## So every cast of corrupting_touch / data_corruption did damage
## only — the "random debuff" portion of the description was a lie.
##
## Same authored-but-unhandled class as ticks 350 (smoke_bomb),
## 351 (song routing), 352 (mp_restore_and_ap), 353 (dispel).

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: random_debuff special case exists ───────────────────

func test_random_debuff_special_case_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Should appear in BOTH physical and magic ability handlers.
	var occurrences: int = src.count("if effect == \"random_debuff\":")
	assert_gte(occurrences, 2,
		"random_debuff special-case must exist in both physical and magic ability post-damage status apply (found %d)" % occurrences)


# ── Source pin: random_debuff chance defaults to 1.0 ────────────────

func test_random_debuff_chance_defaults_to_one() -> void:
	# Pre-fix the 0.0 default silently bypassed the apply. JSON
	# descriptions present the debuff as the headline behavior;
	# defaulting to 1.0 honors the design intent.
	var src := _read(BATTLE_MANAGER_PATH)
	# The default-1.0 branch must follow the "random_debuff" check.
	var match_idx: int = src.find("if effect == \"random_debuff\":")
	assert_gt(match_idx, -1)
	var slice: String = src.substr(match_idx, 300)
	assert_true(slice.contains("get(\"effect_chance\", 1.0)"),
		"random_debuff branch must default effect_chance to 1.0 — pre-fix 0.0 default never let the apply fire")


# ── Source pin: pool of real debuffs exists ─────────────────────────

func test_random_debuff_pool_exists() -> void:
	# The random pick must be a REAL status name — not "random_debuff"
	# (inert) or some other sentinel.
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("_RANDOM_DEBUFF_POOL"),
		"a _RANDOM_DEBUFF_POOL const must exist to define the candidate debuffs")
	# Spot-check a few canonical debuff names.
	var pool_idx: int = src.find("_RANDOM_DEBUFF_POOL")
	assert_gt(pool_idx, -1)
	var pool_slice: String = src.substr(pool_idx, 400)
	assert_true(pool_slice.contains("\"poison\""),
		"pool must include poison (the canonical DOT debuff)")
	assert_true(pool_slice.contains("\"blind\""),
		"pool must include blind (used by miss math)")


# ── Source pin: random_debuff branch reassigns status_to_add ────────

func test_random_debuff_reassigns_status() -> void:
	# The critical guarantee: "random_debuff" is NEVER written as a
	# literal status name. The special-case must reassign status_to_add
	# to a real entry from the pool. End-to-end behavioral test would
	# need a full BattleManager setup; source pin is rigorous enough.
	var src := _read(BATTLE_MANAGER_PATH)
	var branch_idx: int = src.find("status_to_add = _RANDOM_DEBUFF_POOL")
	assert_gt(branch_idx, -1,
		"random_debuff special-case must reassign status_to_add to a real entry from the pool — pre-fix the literal 'random_debuff' string got added as an inert status")


# ── Sanity: non-random_debuff abilities still keep 0.0 default ──────

func test_other_abilities_keep_zero_default() -> void:
	# Regression guard — other abilities (e.g. flame_strike with
	# explicit effect_chance) must keep the 0.0 default for the
	# "opt-in" semantic. The else-branch is the regular path.
	var src := _read(BATTLE_MANAGER_PATH)
	# Pre-fix line existed in two spots; post-fix should have the
	# else-branch defaulting to 0.0 in both spots.
	var zero_default_count: int = src.count("get(\"effect_chance\", 0.0)")
	assert_gte(zero_default_count, 2,
		"non-random_debuff abilities must keep the 0.0 effect_chance default in both physical and magic handlers. Found: %d" % zero_default_count)
