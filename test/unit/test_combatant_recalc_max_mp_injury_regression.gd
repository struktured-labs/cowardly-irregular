extends GutTest

## tick 316: recalculate_stats now re-applies max_mp permanent
## injuries on every recalc.
##
## Pre-fix tick 287 added max_mp support to apply_permanent_injury
## (immediate first application) but recalculate_stats's match-on-
## injury-stat was MISSING the max_mp arm. The very next recalc
## (any equip/unequip/job change/level up — anything that touches
## stats) reset max_mp from base + job_mods + level_mult + passives
## + equipment and silently dropped the injury penalty. The injury
## itself was still in permanent_injuries (visible in the UI) but
## had ZERO stat effect from then on — players who took an MP-
## reducing injury could erase it just by re-equipping anything.
##
## Same silent-fail class as tick 287's unknown-stat warning: the
## injury list said "you have this", but the stats didn't reflect it.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: max_mp arm exists in recalculate_stats ──────────────

func test_recalculate_stats_has_max_mp_arm() -> void:
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func recalculate_stats")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Find the permanent-injury match.
	var inj_match_idx: int = body.find("for injury in permanent_injuries:")
	assert_gt(inj_match_idx, -1, "permanent_injuries loop must exist")
	# Slice to the end of that block.
	var inj_body: String = body.substr(inj_match_idx, 2000)
	assert_true(inj_body.contains("\"max_mp\":"),
		"recalculate_stats's permanent_injuries match must include a max_mp arm — pre-fix max_mp injuries silently reset on every recalc")


# ── Source pin: max_mp uses floor=0 (not 1) ─────────────────────────

func test_max_mp_arm_uses_floor_zero() -> void:
	# Some classes have legitimately 0 MP; floor=1 would mis-treat them.
	# apply_permanent_injury uses floor=0 — recalc must match.
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func recalculate_stats")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Find the max_mp arm body.
	var arm_idx: int = body.find("\"max_mp\":")
	assert_gt(arm_idx, -1)
	# Read 1500 chars after — generous to cover the 11-line comment block
	# (~800 chars) plus the actual code line. 400 chars was too tight.
	var arm_body: String = body.substr(arm_idx, 1500)
	assert_true(arm_body.contains("max(0, max_mp - injury[\"penalty\"])"),
		"max_mp arm must use floor=0 (matches apply_permanent_injury at line ~631)")


# ── Behavioral: max_mp injury survives a recalc ─────────────────────

func test_max_mp_injury_persists_through_recalculate() -> void:
	var combatant_script: GDScript = load(COMBATANT_PATH)
	var c: Object = combatant_script.new()
	add_child_autofree(c)

	# Seed bare base stats so the recalc's reset is observable.
	c.base_max_hp = 100
	c.base_max_mp = 50
	c.base_attack = 10
	c.base_defense = 10
	c.base_magic = 10
	c.base_speed = 10
	c.max_mp = 50
	c.current_mp = 50

	# Apply a max_mp injury (penalty 15). Initial application happens
	# via apply_permanent_injury.
	c.apply_permanent_injury({"stat": "max_mp", "penalty": 15})
	assert_eq(c.max_mp, 35,
		"initial apply_permanent_injury(max_mp) must drop max_mp by 15 (tick 287)")

	# Now force a recalc — this is what equip/unequip/job change does.
	c.recalculate_stats()

	# Pre-tick-316: the recalc reset max_mp from base (50) and didn't
	# re-apply the injury, leaving max_mp at 50 — injury silently
	# erased. Post-fix: injury survives, max_mp stays at 35.
	assert_eq(c.max_mp, 35,
		"after recalculate_stats, max_mp injury must still be applied (pre-fix: silently restored to 50, injury became cosmetic-only)")


# ── Sanity: other injury stats already work (no regression) ─────────

func test_max_hp_injury_still_survives_recalc() -> void:
	# Regression guard: don't break the existing max_hp arm.
	var combatant_script: GDScript = load(COMBATANT_PATH)
	var c: Object = combatant_script.new()
	add_child_autofree(c)

	c.base_max_hp = 100
	c.base_max_mp = 50
	c.max_hp = 100

	c.apply_permanent_injury({"stat": "max_hp", "penalty": 20})
	c.recalculate_stats()
	assert_eq(c.max_hp, 80,
		"max_hp injury must persist through recalc (existing behavior, not regressed by the max_mp fix)")
