extends GutTest

## tick 376: BattleManager._get_crit_multiplier now reads
## PassiveSystem.get_passive_mods's crit_damage_bonus accumulator
## instead of hardcoding a check for "devastating_criticals" (which
## was never in passives.json — the +2.0 multiplier branch was dead
## code that could never fire).
##
## Pre-fix:
##   if "devastating_criticals" in attacker.equipped_passives:
##       base_mult = 2.0
##
## The passive was referenced by name but never authored in data.
## Latent design intent died on the floor — every crit was a flat 1.5x
## regardless of build.
##
## Post-fix:
##   var bonus = PassiveSystem.get_passive_mods(attacker).get(
##       "crit_damage_bonus", 0.0)
##   base_mult += clampf(bonus, 0.0, 1.5)
##
## And data/passives.json now ships `devastating_criticals` with
## crit_damage_bonus=0.5 — restoring the +2.0x crit at the data level
## while letting any future passive add to the bonus.
##
## Closes the third PassiveSystem wiring gap closed in this session
## (tick 373 healing_multiplier, tick 374 mp_cost_multiplier, tick 375
## crit_chance + evasion, tick 376 crit_damage_bonus).

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: hardcoded check removed ─────────────────────────────

func test_hardcoded_devastating_check_removed() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _get_crit_multiplier")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The dead `in equipped_passives` literal check must be gone.
	assert_false(body.contains("\"devastating_criticals\" in attacker.equipped_passives"),
		"hardcoded `\"devastating_criticals\" in equipped_passives` check must be removed")
	# The +2.0 assignment must be gone too.
	assert_false(body.contains("base_mult = 2.0"),
		"hardcoded `base_mult = 2.0` override must be removed")


# ── Source pin: accumulator read in place ───────────────────────────

func test_accumulator_read_in_place() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _get_crit_multiplier")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("get_passive_mods(attacker)"),
		"_get_crit_multiplier must consult PassiveSystem.get_passive_mods")
	assert_true(body.contains("mods.get(\"crit_damage_bonus\""),
		"_get_crit_multiplier must read crit_damage_bonus from the accumulator")
	# Clamp prevents stacked-passive damage explosions.
	assert_true(body.contains("0.0, 1.5"),
		"crit_damage_bonus must clamp to [0.0, 1.5] safety band")


# ── Source pin: devastating_criticals in passives.json ──────────────

func test_devastating_criticals_in_passives_data() -> void:
	# The fix on the code side requires the passive to actually exist.
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	assert_false(raw.is_empty(), "passives.json must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "passives.json root must be a Dictionary")
	var data: Dictionary = parsed
	assert_true(data.has("devastating_criticals"),
		"data/passives.json must include devastating_criticals (was referenced in code but never authored)")
	var passive: Dictionary = data["devastating_criticals"]
	var stat_mods: Dictionary = passive.get("stat_mods", {})
	assert_true(stat_mods.has("crit_damage_bonus"),
		"devastating_criticals must have stat_mods.crit_damage_bonus")
	assert_gt(float(stat_mods.get("crit_damage_bonus", 0.0)), 0.0,
		"crit_damage_bonus must be > 0 to actually buff crit damage")


# ── Behavioral: no passives = base 1.5x ─────────────────────────────

func test_no_passives_base_crit_multiplier() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "Vanilla", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 0,
	})
	add_child_autofree(c)
	c.equipped_passives = []
	var mult: float = bm._get_crit_multiplier(c)
	assert_almost_eq(mult, 1.5, 0.001,
		"no passives must give base 1.5x crit multiplier — fix must not silently buff baseline")


# ── Behavioral: devastating_criticals stacks the bonus ──────────────

func test_devastating_criticals_actually_boosts() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if bm == null or ps == null:
		pending("BattleManager + PassiveSystem autoloads required")
		return
	if not ps.passives.has("devastating_criticals"):
		pending("data/passives.json must include devastating_criticals (the whole point of the fix)")
		return
	var authored_bonus: float = float(ps.passives["devastating_criticals"].get("stat_mods", {}).get("crit_damage_bonus", 0.0))
	assert_gt(authored_bonus, 0.0,
		"devastating_criticals must author a positive crit_damage_bonus")

	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "Cracker", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 0,
	})
	add_child_autofree(c)
	c.equipped_passives = ["devastating_criticals"]
	var mult: float = bm._get_crit_multiplier(c)
	var expected: float = 1.5 + authored_bonus
	assert_almost_eq(mult, expected, 0.001,
		"devastating_criticals must give 1.5 + bonus crit multiplier")
	assert_gt(mult, 1.5,
		"crit multiplier must be > 1.5 base — was 1.5 flat pre-fix because the dead check could never fire")
