extends GutTest

## tick 157 regression: Combatant.from_dict must int() coerce and
## clamp all scalar stat fields. JSON.parse returns numerics as
## float — typed-int fields auto-truncate, but explicit coerce +
## clamp also catches save corruption:
##
##   - max_hp = 0 would divide-by-zero in get_hp_percentage and
##     break recalculate_stats's `max(1, max_hp - penalty)` invariant.
##   - current_hp > max_hp (e.g., save taken during +max_hp buff
##     that subsequently dropped) would leak past the bar UI.
##   - current_hp < 0 from corruption would still report alive on
##     `is_alive`-style checks (which only flip on take_damage).
##   - current_ap outside [-4, +4] would break the Defer/Advance
##     queue math (CLAUDE.md combat section locks this range).
##   - job_level = 0 breaks level_mult: 1.0 + (0-1) * 0.04 = 0.96
##     stat multiplier AND ability-learn gates that key off level
##     thresholds.

const COMBATANT := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_max_hp_loads_floored_at_1() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("max_hp = max(1, int(data[\"max_hp\"]))"),
		"max_hp must floor at 1 — zero breaks hp_percentage division and the recalculate_stats max(1, ...) invariant")


func test_current_hp_clamps_against_just_loaded_max_hp() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("current_hp = clampi(int(data[\"current_hp\"]), 0, max_hp)"),
		"current_hp must clamp to [0, max_hp] — catches save-corruption negatives AND post-buff-drop overflow")


func test_current_mp_clamps_against_max_mp() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("current_mp = clampi(int(data[\"current_mp\"]), 0, max_mp)"),
		"current_mp must clamp to [0, max_mp]")


func test_current_ap_clamps_to_negative_4_to_4() -> void:
	# Game-design range per CLAUDE.md combat section.
	var src := _read(COMBATANT)
	assert_true(src.contains("current_ap = clampi(int(data[\"current_ap\"]), -4, 4)"),
		"current_ap must clamp to [-4, 4] — the Defer/Advance system locks this range")


func test_job_level_floored_at_1() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("job_level = max(1, int(data[\"job_level\"]))"),
		"job_level must floor at 1 — zero breaks level_mult AND ability-learn gates")


func test_stat_fields_floored_at_0() -> void:
	# attack/defense/magic/speed/job_exp/max_mp must not go negative.
	var src := _read(COMBATANT)
	for field in ["attack", "defense", "magic", "speed", "job_exp"]:
		var pattern: String = "%s = max(0, int(data[\"%s\"]))" % [field, field]
		assert_true(src.contains(pattern),
			"%s must floor at 0 — negative stat from save corruption would surface as inverted damage" % field)
	assert_true(src.contains("max_mp = max(0, int(data[\"max_mp\"]))"),
		"max_mp must floor at 0 (clamp at 0 vs 1 — Combatants without MP are valid)")


func test_load_ordering_max_before_current() -> void:
	# Critical: max_hp must be loaded BEFORE current_hp so the
	# current_hp clamp uses the just-loaded max, not the default.
	var src := _read(COMBATANT)
	var max_hp_idx: int = src.find("if data.has(\"max_hp\"):")
	var current_hp_idx: int = src.find("if data.has(\"current_hp\"):")
	assert_gt(max_hp_idx, -1, "max_hp load must exist")
	assert_gt(current_hp_idx, -1, "current_hp load must exist")
	assert_lt(max_hp_idx, current_hp_idx,
		"max_hp MUST be loaded BEFORE current_hp — else the clamp uses default max_hp, not the saved value")
	# Same for max_mp / current_mp.
	var max_mp_idx: int = src.find("if data.has(\"max_mp\"):")
	var current_mp_idx: int = src.find("if data.has(\"current_mp\"):")
	assert_lt(max_mp_idx, current_mp_idx,
		"max_mp MUST be loaded BEFORE current_mp")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_current_hp_clamps_to_max_hp() -> void:
	# Save corruption / post-buff-drop scenario: saved current_hp
	# is 200 but max_hp is 100. Must clamp to 100.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"max_hp": 100, "current_hp": 200})
	assert_eq(c.max_hp, 100, "sanity: max_hp loaded")
	assert_eq(c.current_hp, 100,
		"current_hp=200 with max_hp=100 must clamp to 100 — was unbounded pre-tick-157")


func test_runtime_negative_current_hp_clamps_to_0() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"max_hp": 100, "current_hp": -50})
	assert_eq(c.current_hp, 0,
		"negative current_hp must clamp to 0")


func test_runtime_zero_max_hp_floored_to_1() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"max_hp": 0})
	assert_eq(c.max_hp, 1,
		"max_hp=0 must floor to 1 — divide-by-zero defense")


func test_runtime_out_of_range_ap_clamps() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"current_ap": 99})
	assert_eq(c.current_ap, 4,
		"current_ap=99 must clamp to 4 (game design max)")
	c.from_dict({"current_ap": -99})
	assert_eq(c.current_ap, -4,
		"current_ap=-99 must clamp to -4 (game design min)")


func test_runtime_job_level_floored_at_1() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"job_level": 0})
	assert_eq(c.job_level, 1,
		"job_level=0 must floor at 1")
	c.from_dict({"job_level": -5})
	assert_eq(c.job_level, 1,
		"negative job_level must floor at 1")


func test_runtime_negative_stats_floored_at_0() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"attack": -10, "defense": -5, "magic": -3, "speed": -1})
	assert_eq(c.attack, 0, "negative attack must floor at 0")
	assert_eq(c.defense, 0, "negative defense must floor at 0")
	assert_eq(c.magic, 0, "negative magic must floor at 0")
	assert_eq(c.speed, 0, "negative speed must floor at 0")


# ── Non-regression: valid values pass through ───────────────────────────

func test_runtime_in_range_values_pass_through() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({
		"max_hp": 250,
		"max_mp": 100,
		"current_hp": 175,
		"current_mp": 65,
		"current_ap": 2,
		"job_level": 12,
		"job_exp": 350,
		"attack": 45,
		"defense": 38,
		"magic": 22,
		"speed": 30,
	})
	assert_eq(c.max_hp, 250, "valid max_hp passes through")
	assert_eq(c.current_hp, 175, "in-range current_hp passes through")
	assert_eq(c.current_ap, 2, "in-range AP passes through")
	assert_eq(c.job_level, 12, "valid level passes through")
	assert_eq(c.attack, 45, "valid attack passes through")
