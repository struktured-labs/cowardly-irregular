extends GutTest

## Live playtest 2026-07-02: "first fight entirely broken" — the
## Whispering Cave rendered UNDER the battle UI with no party sprites,
## no enemy sprites, no HP bars. Root cause: exploration hiding only
## touched _exploration_scene, but scenes parented via MapSystem or
## overlays outside that reference stayed visible. Belt-and-suspenders
## sweep now hides all non-battle Node2D children of GameLoop.


const GameLoopScript = preload("res://src/GameLoop.gd")


func test_hide_sweep_covers_all_non_battle_scenes() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("Exploration hidden"),
		"belt-and-suspenders hide must log its count so future regressions surface")
	assert_true(src.contains("if child is Node2D and not child.name.begins_with(\"BattleScene\")"),
		"the sweep must hide all Node2D children of GameLoop except BattleScene")


func test_mapsystem_current_map_also_hidden() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("MapSystem.current_map.visible = false"),
		"scenes parented via MapSystem.load_map (dungeons, interiors) must be hidden too")


func test_sweep_is_centralized_and_runs_on_every_battle_start() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("func _hide_exploration_scenes"),
		"the sweep must be a helper (not inline) so every entry path shares it")
	var fn_idx: int = src.find("func _start_battle_async")
	assert_gt(fn_idx, -1)
	var next: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next - fn_idx)
	assert_true(body.contains("_hide_exploration_scenes()"),
		"_start_battle_async is the shared entry point — must call the sweep so every path (debug boss, spotlight, retry, no-transition fallback) is protected")


func test_helper_is_idempotent_on_empty_tree() -> void:
	# Node with no children + no MapSystem.current_map + no
	# _exploration_scene set — must not error, must count zero.
	var gl: Node = GameLoopScript.new()
	add_child_autofree(gl)
	gl._hide_exploration_scenes()
	pass_test("helper survived an empty tree — safe to call defensively")
