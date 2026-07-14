extends GutTest

## tick 443: undead_affinity passive's meta_effects.dark_absorb now
## actually converts dark damage to healing.
##
## Pre-fix passives.json authored:
##   undead_affinity: {meta_effects: {dark_absorb: true}}
##   description: "+40% dark damage, heal from dark attacks"
## but no code path read the field — dark hits ate HP like any other
## element. The "heal from dark attacks" promise was decoration.
##
## Fix is generic across elements (<element>_absorb), so future
## fire_absorb / ice_absorb passives drop in with no new wire.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, max_hp: int = 100) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": max_hp, "max_mp": 50,
		"attack": 10, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_absorb_helper_exists() -> void:
	var src := _read(COMBATANT_PATH)
	assert_true(src.contains("func _absorbs_element"),
		"Combatant must declare _absorbs_element helper")
	assert_true(src.contains("_get_passive_meta_effect_sum(element + \"_absorb\")"),
		"_absorbs_element must query the generic <element>_absorb meta_effect key")


func test_take_elemental_damage_short_circuits_on_absorb() -> void:
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func take_elemental_damage")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_absorbs_element(element)"),
		"take_elemental_damage must consult _absorbs_element before applying damage")
	# Heal path must hit hp_changed.
	assert_true(body.contains("hp_changed.emit"),
		"absorb path must emit hp_changed so UI updates")
	# Must short-circuit (return 0) before the elemental_mod path.
	var absorb_idx: int = body.find("_absorbs_element(element)")
	var mod_idx: int = body.find("calculate_elemental_modifier(element)")
	assert_gt(absorb_idx, -1)
	assert_gt(mod_idx, -1)
	assert_lt(absorb_idx, mod_idx,
		"absorb check must come BEFORE the elemental_mod path so absorption beats resistance/immunity")


func test_data_still_authors_dark_absorb() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("undead_affinity"))
	var me: Variant = data["undead_affinity"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_true(bool(me.get("dark_absorb", false)),
		"undead_affinity must still author dark_absorb")


func test_runtime_no_passive_takes_damage() -> void:
	# Regression guard: a combatant without undead_affinity must
	# still take dark damage normally.
	var c: Combatant = _make("Mortal", 100)
	c.current_hp = 50
	c.equipped_passives = []
	c.take_elemental_damage(20, "dark")
	assert_lt(c.current_hp, 50,
		"vanilla combatant must take dark damage — fix must not silently absorb for everyone")


func test_runtime_with_passive_heals_from_dark() -> void:
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("undead_affinity"):
		pending("undead_affinity passive required")
		return
	var c: Combatant = _make("Lich", 200)
	c.current_hp = 100
	c.equipped_passives = ["undead_affinity"]
	c.take_elemental_damage(30, "dark")
	assert_gt(c.current_hp, 100,
		"undead_affinity-equipped combatant must HEAL from dark damage")


func test_runtime_other_element_still_hurts_absorb_user() -> void:
	# Absorb is element-specific. A combatant with dark_absorb still
	# takes fire damage normally.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("undead_affinity"):
		pending("undead_affinity passive required")
		return
	var c: Combatant = _make("LichB", 200)
	c.current_hp = 100
	c.equipped_passives = ["undead_affinity"]
	c.take_elemental_damage(30, "fire")
	assert_lt(c.current_hp, 100,
		"undead_affinity must NOT absorb non-dark elements — wire must be element-specific")


func test_runtime_absorb_clamps_to_max_hp() -> void:
	# Edge case: heal can't exceed max_hp.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("undead_affinity"):
		pending("undead_affinity passive required")
		return
	var c: Combatant = _make("LichC", 100)
	c.current_hp = 95
	c.equipped_passives = ["undead_affinity"]
	c.take_elemental_damage(50, "dark")
	assert_eq(c.current_hp, 100,
		"absorb heal must clamp to max_hp — no overheal")
