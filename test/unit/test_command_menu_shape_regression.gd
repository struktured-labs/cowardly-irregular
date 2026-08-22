extends GutTest

## Live-build tests for the battle command menu. Every existing menu test greps SOURCE, which
## is why the Bard/Cleric "no Attack row" bug shipped — a source pin cannot see that a job LOST
## a row. These build the real menu for a real job and assert on the rows that come back.
## Playtest 2026-08-22 (struktured): "the menu is too busy", "bard menu is cutoff on bottom".

const SCENE_PATH := "res://src/battle/BattleScene.gd"
const MenuClass = preload("res://src/battle/BattleCommandMenu.gd")


func _scene_with_enemies(n: int = 2) -> Node:
	var scene: Node = load(SCENE_PATH).new()
	add_child_autofree(scene)
	var enemies: Array = []
	for i in n:
		var e := Combatant.new()
		add_child_autofree(e)
		e.combatant_name = "Dummy%d" % i
		e.max_hp = 10
		e.current_hp = 10
		enemies.append(e)
	scene.test_enemies.assign(enemies)
	return scene


func _pc(job_id: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = job_id.capitalize()
	c.max_hp = 30
	c.current_hp = 30
	c.max_mp = 20
	c.current_mp = 20
	c.job = JobSystem.get_job(job_id)
	return c


func _rows(job_id: String) -> Array:
	var scene := _scene_with_enemies()
	var menu = MenuClass.new(scene)
	return menu.build_command_menu_items_with_targets(_pc(job_id))


func _ids(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		if r is Dictionary:
			out.append(str(r.get("id", "")))
	return out


func _find(rows: Array, id: String) -> Dictionary:
	for r in rows:
		if r is Dictionary and str(r.get("id", "")) == id:
			return r
	return {}


func test_the_builder_returns_a_real_menu() -> void:
	## CONTROL: everything below is worthless if the build returns nothing.
	var rows := _rows("bard")
	assert_gt(rows.size(), 3, "CONTROL: the builder produced a real menu")


func test_auto_block_is_one_top_level_row_with_all_three_actions_inside() -> void:
	var rows := _rows("bard")
	var ids := _ids(rows)
	assert_true("auto_menu" in ids, "the collapsed Auto row exists at top level")
	for buried in ["autobattle", "autobattle_edit", "trust_toggle"]:
		assert_false(buried in ids, "%s must NOT be a top-level row any more" % buried)
	var sub: Array = _find(rows, "auto_menu").get("submenu", [])
	var sub_ids := _ids(sub)
	for needed in ["autobattle", "autobattle_edit", "trust_toggle"]:
		assert_true(needed in sub_ids, "%s is still REACHABLE inside Auto (buried, not deleted)" % needed)
