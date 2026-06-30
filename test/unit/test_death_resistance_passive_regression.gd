extends GutTest

## tick 439: death_resistance passive's meta_effects.
## death_resist_chance now actually gives a roll to survive a
## killing blow at 1 HP.
##
## Pre-fix passives.json authored:
##   death_resistance: {meta_effects: {death_resist_chance: 0.75}}
##   description: "75% chance to survive a killing blow with 1 HP"
## but no code path read the meta_effect — the passive was pure
## decoration; players equipped it expecting a survival roll and
## got nothing.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_helper_exists() -> void:
	var src := _read(COMBATANT_PATH)
	assert_true(src.contains("func _get_passive_meta_effect_sum"),
		"Combatant must declare _get_passive_meta_effect_sum helper")


func test_take_damage_uses_helper() -> void:
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func take_damage")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_get_passive_meta_effect_sum(\"death_resist_chance\")"),
		"take_damage must consult the helper for death_resist_chance")
	# Survives at 1 HP (not 0 or full).
	assert_true(body.contains("current_hp = 1"),
		"survive path must set current_hp = 1")


func test_lethal_only_check() -> void:
	# Pin that the check fires only on the lethal hit (old_hp > 0
	# AND current_hp <= 0). Non-lethal damage must NOT trigger a roll
	# (would waste the chance).
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func take_damage")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if current_hp <= 0 and old_hp > 0:"),
		"death_resist check must gate on lethal hit (old_hp > 0 AND current_hp <= 0)")


func test_data_still_authors_death_resist() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("death_resistance"))
	var me: Variant = data["death_resistance"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(float(me.get("death_resist_chance", 0.0)), 0.0,
		"death_resistance must still author meta_effects.death_resist_chance > 0")


func test_runtime_no_passive_dies_normally() -> void:
	# Regression guard: a combatant WITHOUT death_resistance must
	# die normally from a lethal hit.
	var c: Combatant = _make("Vanilla")
	c.current_hp = 10
	c.equipped_passives = []
	c.take_damage(99999, false)
	assert_false(c.is_alive,
		"vanilla combatant must die from lethal hit — fix must not silently grant baseline survival")


func test_runtime_with_passive_can_survive() -> void:
	# With death_resistance at 0.75 chance, ~75% of 20 lethal hits
	# should survive. We test the helper directly to bypass RNG —
	# pin the helper returns the authored value.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("death_resistance"):
		pending("death_resistance passive required")
		return
	var c: Combatant = _make("Resilient")
	c.equipped_passives = ["death_resistance"]
	var sum: float = c._get_passive_meta_effect_sum("death_resist_chance")
	assert_gt(sum, 0.0,
		"_get_passive_meta_effect_sum must return the authored death_resist_chance")
	# Behavioral: with chance = 1.0 (force success), the combatant
	# must survive a killing blow. We can't safely mutate the
	# passive data, so we test the helper returns >0 and trust the
	# RNG branch — see the take_damage_uses_helper source pin for
	# wire-level verification.


func test_runtime_survival_force_via_meta_override() -> void:
	# Force a survival outcome by inflating the chance via a custom
	# passive that authors death_resist_chance = 2.0 (clamps to 1.0
	# inside the take_damage check). End-to-end: take_damage doesn't
	# kill — current_hp clamps to 1.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	# Temporarily inject a guaranteed-survive passive.
	var prior_has: bool = ps.passives.has("__tick439_guaranteed_resist__")
	var prior_def: Dictionary = ps.passives.get("__tick439_guaranteed_resist__", {})
	ps.passives["__tick439_guaranteed_resist__"] = {
		"name": "Test Guaranteed Resist",
		"meta_effects": {"death_resist_chance": 1.0},
	}
	var c: Combatant = _make("Tester")
	c.current_hp = 50
	c.equipped_passives = ["__tick439_guaranteed_resist__"]
	c.take_damage(99999, false)
	assert_true(c.is_alive,
		"100% death_resist_chance must guarantee survival")
	assert_eq(c.current_hp, 1,
		"survival must leave current_hp = 1 (not 0, not max)")
	# Restore.
	if prior_has:
		ps.passives["__tick439_guaranteed_resist__"] = prior_def
	else:
		ps.passives.erase("__tick439_guaranteed_resist__")
