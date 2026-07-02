extends GutTest

## Live playtest 2026-07-02: "first fight entirely broken" — the
## Whispering Cave rendered UNDER the battle UI with no party sprites,
## no enemy sprites, no HP bars. Root cause: exploration hiding only
## touched _exploration_scene, but scenes parented via MapSystem or
## overlays outside that reference stayed visible. Belt-and-suspenders
## sweep now hides all non-battle Node2D children of GameLoop.


func test_hide_sweep_covers_all_non_battle_scenes() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	# The sweep must exist and skip the battle scene.
	assert_true(src.contains("Exploration hidden"),
		"belt-and-suspenders hide must exist so future regressions log a count")
	assert_true(src.contains("if child is Node2D and not child.name.begins_with(\"BattleScene\")"),
		"the sweep must hide all Node2D children of GameLoop except BattleScene")


func test_mapsystem_current_map_also_hidden() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("MapSystem.current_map.visible = false"),
		"scenes parented via MapSystem.load_map (dungeons, interiors) must be hidden too")
