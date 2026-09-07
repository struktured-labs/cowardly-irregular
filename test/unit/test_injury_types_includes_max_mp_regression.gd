extends GutTest

## tick 317: BattleManager.INJURY_TYPES now includes max_mp arms so
## MP-heavy classes (Cleric/Mage/Bard) get real injury risk.
##
## Pre-fix INJURY_TYPES had only max_hp/attack/defense/magic/speed.
## Combatant.apply_permanent_injury added max_mp support in tick 287
## and recalculate_stats made it durable in tick 316, but the natural
## injury roll (_roll_permanent_injury at line ~3508) never produced
## max_mp injuries because no template existed. Caster classes had
## ZERO max_mp-injury exposure regardless of how many times they got
## KO'd — a stealth lopsided design where physical chars accumulated
## meaningful penalties while casters could KO with impunity.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: max_mp arms exist in INJURY_TYPES ───────────────────

func test_injury_types_includes_max_mp() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var const_idx: int = src.find("const INJURY_TYPES")
	assert_gt(const_idx, -1)
	# Slice to the closing bracket — the const is a single literal Array.
	var close_idx: int = src.find("]", const_idx)
	assert_gt(close_idx, -1)
	var body: String = src.substr(const_idx, close_idx - const_idx)
	assert_true(body.contains("\"stat\": \"max_mp\""),
		"INJURY_TYPES must include at least one max_mp arm — pre-fix MP-heavy classes had zero exposure to MP-injury risk")


# ── Source pin: there are at least 2 max_mp arms (matches the pattern) ─

func test_max_mp_arms_count_matches_pattern() -> void:
	# The existing arms come in pairs (2× max_hp, 2× attack, 2× defense,
	# 2× magic, 2× speed). The fix should maintain symmetry — 2 max_mp.
	var src := _read(BATTLE_MANAGER_PATH)
	var const_idx: int = src.find("const INJURY_TYPES")
	var close_idx: int = src.find("]", const_idx)
	var body: String = src.substr(const_idx, close_idx - const_idx)
	var max_mp_count: int = body.count("\"stat\": \"max_mp\"")
	assert_gte(max_mp_count, 2,
		"INJURY_TYPES should have at least 2 max_mp arms (matches the pairing of every other stat). Found: %d" % max_mp_count)


# ── Behavioral: roll_permanent_injury can produce a max_mp injury ───

func test_roll_can_produce_max_mp_injury() -> void:
	# Drive _roll_permanent_injury enough times to statistically hit a
	# max_mp arm. With ~2/12 = ~17% probability per roll, 200 rolls give
	# < 1e-15 chance of missing.
	var bm_script: GDScript = load(BATTLE_MANAGER_PATH)
	var bm: Object = bm_script.new()
	add_child_autofree(bm)

	# Set current_round so the injury dict includes it (irrelevant for
	# this test, but the field is read in _roll_permanent_injury).
	bm.current_round = 1

	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Object = combatant_script.new()
	add_child_autofree(c)
	c.job_level = 1
	c.base_max_mp = 80
	c.max_mp = 80
	c.current_mp = 80

	var saw_max_mp: bool = false
	for i in range(200):
		var inj: Dictionary = bm._roll_permanent_injury(c)
		if inj.get("stat", "") == "max_mp":
			saw_max_mp = true
			# Sanity: the penalty must be >= 1 (matches _roll's max(1, penalty)).
			assert_gte(int(inj.get("penalty", 0)), 1,
				"max_mp injury penalty must be at least 1")
			# Sanity: penalty must scale with level (level 1 base ~5-7).
			# At level 1, level_scale = 1.05 → penalty ~5-7.
			assert_lte(int(inj.get("penalty", 0)), 10,
				"max_mp injury penalty at level 1 must be in the 5-10 band")
			break
	assert_true(saw_max_mp,
		"200 _roll_permanent_injury calls must hit at least one max_mp arm — pre-fix it was statistically impossible (no template)")


# ── Behavioral: existing arms still work (no regression) ────────────

func test_existing_arms_still_present() -> void:
	# Regression guard: don't break the existing 10 arms.
	var src := _read(BATTLE_MANAGER_PATH)
	var const_idx: int = src.find("const INJURY_TYPES")
	var close_idx: int = src.find("]", const_idx)
	var body: String = src.substr(const_idx, close_idx - const_idx)
	for stat in ["max_hp", "attack", "defense", "magic", "speed"]:
		var marker: String = "\"stat\": \"%s\"" % stat
		var count: int = body.count(marker)
		assert_gte(count, 2,
			"existing arm '%s' must have at least 2 entries (pre-fix had 2; the max_mp addition must not regress them). Found: %d" % [stat, count])
