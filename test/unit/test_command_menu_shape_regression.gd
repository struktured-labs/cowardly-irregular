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


func test_scan_is_not_an_intrinsic_menu_row_for_any_job() -> void:
	## struktured 2026-08-22: "scan should be an ability not intrinsic to a player".
	## It lives in the Rogue's kit; nobody gets weakness intel just for having a turn.
	for job_id in ["fighter", "mage", "cleric", "rogue", "bard"]:
		var ids := _ids(_rows(job_id))
		assert_false("scan_menu" in ids, "%s must not get a free intrinsic Scan row" % job_id)


func test_scan_ability_still_reveals_through_the_shared_reader() -> void:
	## The reveal must survive losing the menu path: BattleUIManager ORs its own
	## _revealed_enemies dict with the intel_revealed meta that the ability sets, so the
	## ability alone is sufficient. Guarding the OR, because dropping either side is silent.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true("intel_revealed" in src, "the UI still reads the meta the scan ABILITY sets")
	assert_true("_revealed_enemies" in src, "and still reads the attack-based reveal")


func test_every_job_can_attack_from_the_menu() -> void:
	## THE BUG (struktured 2026-08-22, on Bard): "the bard can attack in auto mode but
	## otherwise cant". free_move REPLACED Attack, so Mage/Cleric/Bard had no basic attack
	## in the menu while autobattle called basic_attack directly and did. Cleric and Mage
	## carried the identical defect unreported — which is why this asserts over ALL jobs,
	## not the one that got noticed.
	for job_id in ["fighter", "mage", "cleric", "rogue", "bard"]:
		var ids := _ids(_rows(job_id))
		var has_attack: bool = ("attack_menu" in ids) or ("attack" in ids)
		assert_true(has_attack, "%s must be able to attack from the command menu" % job_id)


func test_ability_free_move_jobs_keep_BOTH_attack_and_their_free_move() -> void:
	## The fix must not go the other way and cost them their job identity move.
	var expected := {"mage": "Channel", "cleric": "Pray", "bard": "Riff"}
	for job_id in expected:
		var rows := _rows(job_id)
		var ids := _ids(rows)
		assert_true("attack_menu" in ids or "attack" in ids, "%s kept Attack" % job_id)
		var labels := ""
		for r in rows:
			if r is Dictionary:
				labels += str(r.get("label", "")) + "|"
		assert_true(str(expected[job_id]) in labels,
			"%s still has its free move %s" % [job_id, expected[job_id]])


func test_basic_attack_jobs_get_exactly_one_attack_row_with_their_own_label() -> void:
	## Fighter/Rogue must NOT gain a duplicate: their free_move IS the attack.
	var expected := {"fighter": "Attack", "rogue": "Strike"}
	for job_id in expected:
		var rows := _rows(job_id)
		var n := 0
		for r in rows:
			if r is Dictionary and str(r.get("id", "")) in ["attack_menu", "attack"]:
				n += 1
				assert_eq(str(r.get("label", "")), str(expected[job_id]),
					"%s's attack row keeps its own label" % job_id)
		assert_eq(n, 1, "%s has exactly one attack row, not a duplicate" % job_id)
