extends GutTest

## cowir-autogrind's edge flag (msg 2333): permakill exterminations vs
## autogrind battle generation. Recon showed grinds draw from the hardcoded
## BattleEnemySpawner.MONSTER_TYPES roster (NOT encounter pools), so the
## flagged pool-starvation hang was unreachable — but the INVERSE gap was
## real: permakilled species still spawned in grinds. Now the roster draw
## filters them, and total extermination stops the grind CLEANLY (the
## original stuck-in-battle-mode class) instead of emitting an empty battle.

const ControllerScript := preload("res://src/autogrind/AutogrindController.gd")


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
