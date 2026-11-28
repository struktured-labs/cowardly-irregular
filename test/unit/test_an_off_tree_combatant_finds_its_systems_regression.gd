extends GutTest

## A combatant outside the scene tree (every headless battle's enemies, Combatant.x10_ratio's own note) looked up
## PassiveSystem, EquipmentSystem, JobSystem and AutobattleSystem by "/root/…", which finds nothing from off-tree and
## logs an engine error. So off-tree it silently skipped its gear and passive stat mods, its passive healing and the
## job-alias resolution on load (325 such errors in the .846 gate). Each arm builds twins, one in the tree and one
## never added, and asks that they agree. The seat counts the engine error in this file's own log (GUT cannot see it).

const BASE := {"name": "Twin", "max_hp": 500, "max_mp": 50, "attack": 40, "defense": 20, "magic": 30, "speed": 10}


func _twin(in_tree: bool) -> Combatant:
	var c := Combatant.new()
	if in_tree:
		add_child_autofree(c)
	else:
		autofree(c)
	c.initialize(BASE.duplicate())
	return c


func _pair() -> Array:
	var on := _twin(true)
	var off := _twin(false)
	assert_true(on.is_inside_tree(), "CONTROL: one twin is in the tree")
	assert_false(off.is_inside_tree(), "CONTROL: the other twin never enters it")
	return [on, off]


func test_an_off_tree_combatant_wears_its_gear() -> void:
	var p := _pair()
	var bare: int = (p[1] as Combatant).attack
	for c in p:
		c.equipped_weapon = "bronze_sword"
		c.recalculate_stats()
	assert_gt((p[0] as Combatant).attack, bare, "CONTROL: the bronze sword adds attack in the tree")
	assert_eq((p[1] as Combatant).attack, (p[0] as Combatant).attack, "an off-tree combatant must wear the same gear as one in the tree")


func test_an_off_tree_combatant_keeps_its_passive_stat_mods() -> void:
	var p := _pair()
	var bare: int = (p[1] as Combatant).attack
	for c in p:
		c.equipped_passives.append("weapon_mastery")
		c.recalculate_stats()
	assert_gt((p[0] as Combatant).attack, bare, "CONTROL: weapon_mastery raises attack in the tree")
	assert_eq((p[1] as Combatant).attack, (p[0] as Combatant).attack, "an off-tree combatant must keep its passive stat mods")


func test_an_off_tree_combatant_heals_through_its_passive() -> void:
	var p := _pair()
	var bare: int = (p[1] as Combatant).heal_preview(100)
	for c in p:
		c.equipped_passives.append("healing_boost")
	var on: int = (p[0] as Combatant).heal_preview(100)
	assert_gt(on, bare, "CONTROL: healing_boost raises a heal in the tree")
	assert_eq((p[1] as Combatant).heal_preview(100), on, "an off-tree combatant must heal through its own passive")


func test_an_off_tree_combatant_resolves_a_legacy_job_on_load() -> void:
	var p := _pair()
	for c in p:
		c.from_dict({"name": "Twin", "job": {"id": "white_mage"}})
	assert_eq(str((p[0] as Combatant).job.get("id", "")), "cleric", "CONTROL: in the tree an old white_mage save loads as cleric")
	assert_eq(str((p[1] as Combatant).job.get("id", "")), "cleric", "an off-tree combatant must resolve the same legacy job id")


func test_combatant_names_no_system_by_absolute_path() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	assert_gt(src.length(), 1000, "CONTROL: Combatant's source was read")
	var reached := 0
	for line in src.split("\n"):
		var code: String = line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains("\"/root/"):
			reached += 1
	assert_eq(reached, 0, "Combatant must find its systems through _system(), not a \"/root/…\" path that is blind off-tree")
