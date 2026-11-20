extends GutTest

## cowir-autogrind's edge flag (msg 2333): permakill exterminations vs
## autogrind battle generation. Recon showed grinds draw from the hardcoded
## BattleEnemySpawner.MONSTER_TYPES roster (NOT encounter pools), so the
## flagged pool-starvation hang was unreachable — but the INVERSE gap was
## real: permakilled species still spawned in grinds. Now the roster draw
## filters them, and total extermination stops the grind CLEANLY (the
## original stuck-in-battle-mode class) instead of emitting an empty battle.

const ControllerScript := preload("res://src/autogrind/AutogrindController.gd")

var _saved_standing: Array = []
var _saved_region: String = ""


## These arms judge the ROSTER draw; a grind reads the zone it stands in first, so whichever file ran before chose the pool.
func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_saved_region = AutogrindSystem.current_region_id
	AutogrindSystem.current_region_id = ""
	_saved_standing = EncounterSystem.current_enemy_pool.duplicate()
	EncounterSystem.current_enemy_pool.clear()


func after_each() -> void:
	AutogrindSystem.current_region_id = _saved_region
	EncounterSystem.current_enemy_pool.clear()
	for id in _saved_standing:
		EncounterSystem.current_enemy_pool.append(str(id))
	AutogrindSystem._test_disable_persistence = false


func _candidate_ids(ctrl: Node) -> Array:
	return ctrl._grind_draw_candidates().map(func(c): return str(c.get("id", "")))


func _with_permakilled(types: Array, fn: Callable) -> void:
	var saved: Array[String] = GameState.permakilled_monster_types.duplicate()
	GameState.permakilled_monster_types.clear()
	for t in types:
		GameState.permakilled_monster_types.append(str(t))
	fn.call()
	GameState.permakilled_monster_types.clear()
	for x in saved:
		GameState.permakilled_monster_types.append(x)


func test_grind_draws_exclude_permakilled_species() -> void:
	var ctrl = ControllerScript.new()
	add_child_autofree(ctrl)
	var roster_ids: Array = BattleEnemySpawner.MONSTER_TYPES.map(func(mt): return str(mt.get("id", "")))
	assert_gt(roster_ids.size(), 2, "sanity: roster loaded")
	var banned: String = roster_ids[0]
	assert_true(_candidate_ids(ctrl).has(banned), "CONTROL: '%s' is in the pool this grind draws, or banning it proves nothing" % banned)
	_with_permakilled([banned], func():
		for i in range(24):
			for e in ctrl._generate_scaled_enemies():
				assert_ne(str(e.get("id", "")), banned,
					"permakilled '%s' must never spawn in a grind draw" % banned)
	)


func test_total_extermination_draws_empty_not_hang() -> void:
	var ctrl = ControllerScript.new()
	add_child_autofree(ctrl)
	var roster_ids: Array = BattleEnemySpawner.MONSTER_TYPES.map(func(mt): return str(mt.get("id", "")))
	for id in _candidate_ids(ctrl):
		assert_true(roster_ids.has(id), "CONTROL: the draw is the roster, so exterminating the roster empties it (found '%s')" % id)
	assert_gt(ctrl._generate_scaled_enemies().size(), 0, "CONTROL: with nothing exterminated the grind draws someone")
	_with_permakilled(roster_ids, func():
		assert_eq(ctrl._generate_scaled_enemies().size(), 0,
			"full-roster extermination must draw EMPTY (the launch site converts it to a clean stop)")
	)


func test_launch_site_stops_cleanly_on_empty() -> void:
	var src := FileAccess.get_file_as_string("res://src/autogrind/AutogrindController.gd")
	var i := src.find("var enemies = _generate_scaled_enemies()")
	var block := src.substr(i, 400)
	assert_true("is_empty()" in block and "stop_grind(" in block,
		"the battle-launch site must clean-stop on an empty draw — never emit an empty grind battle (the original stuck-battle class)")


func test_a_standing_pool_outside_the_roster_is_still_exterminated_by_name() -> void:
	var ctrl = ControllerScript.new()
	add_child_autofree(ctrl)
	var roster_ids: Array = BattleEnemySpawner.MONSTER_TYPES.map(func(mt): return str(mt.get("id", "")))
	var outsider := ""
	for id in EncounterSystem.monster_database:
		if not roster_ids.has(str(id)) and not ctrl._base_data_for_id(str(id)).is_empty():
			outsider = str(id)
			break
	assert_ne(outsider, "", "CONTROL: some catalog species is not on the roster")
	EncounterSystem.current_enemy_pool.append(outsider)
	assert_eq(_candidate_ids(ctrl), [outsider], "CONTROL: the grind draws where it stands")
	_with_permakilled(roster_ids, func():
		assert_gt(ctrl._generate_scaled_enemies().size(), 0, "exterminating the roster does not empty a place the roster never fed; the old arm passed or failed on this by run order")
	)
	_with_permakilled([outsider], func():
		assert_eq(ctrl._generate_scaled_enemies().size(), 0, "its own species exterminated, the place is empty")
	)
