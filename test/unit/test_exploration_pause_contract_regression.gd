extends GutTest

## Regression for the tavern input-leak CLASS (user-reported 2026-06-04; re-hit
## 2026-08-14 in ShopInterior + InnInterior).
##
## GameLoop guards every exploration suspend/resume with
## `if _exploration_scene.has_method("pause")` — a scene missing pause()/resume()
## is SILENTLY skipped. The OverworldMenu doesn't change current_state (stays
## EXPLORATION) and OverworldPlayer polls Input in _physics_process, so with the
## menu or autobattle editor open the player keeps walking behind it: D-pad menu
## navigation visibly moves the character, the exit door auto-fires a scene
## change under the open UI, and _start_exploration's pop_all() then strips the
## menu's lock — battles trigger with the menu still up.
##
## The 2026-06-04 fix patched only TavernInterior and pinned a HAND-LIST of 5
## scripts; ShopInterior and InnInterior (same shape, same hole) were never on
## it. This version derives the list from GameLoop.gd itself — every map script
## GameLoop references must declare or inherit BOTH methods, so the next sibling
## cannot be born outside the net.

const GL_PATH := "res://src/GameLoop.gd"

## GameLoop references these from the scanned dirs but never mounts them as
## _exploration_scene — the only entries allowed to skip the contract.
const NOT_MOUNTED_SCENES := {
	"res://src/exploration/SavePoint.gd": "interactable prop spawned INSIDE scenes",
	"res://src/exploration/VillageShop.gd": "shop counter UI helper, not a scene",
}


func _mounted_scene_paths() -> Array:
	var src := FileAccess.get_file_as_string(GL_PATH)
	var re := RegEx.new()
	re.compile("res://src/(maps|exploration)/[A-Za-z_/]+\\.gd")
	var paths := {}
	for m in re.search_all(src):
		var p: String = m.get_string()
		if not NOT_MOUNTED_SCENES.has(p):
			paths[p] = true
	return paths.keys()


func _chain_source(path: String) -> String:
	var script: Script = load(path)
	assert_not_null(script, "script should load: %s" % path)
	var text := ""
	while script:
		text += FileAccess.get_file_as_string(script.resource_path)
		script = script.get_base_script()
	return text


func test_every_gameloop_mounted_scene_declares_or_inherits_pause_and_resume() -> void:
	var paths := _mounted_scene_paths()
	# Wrong-shape-zero control: the derivation must NAME known members, not just count.
	for known in ["res://src/maps/interiors/ShopInterior.gd",
			"res://src/maps/interiors/InnInterior.gd",
			"res://src/maps/interiors/TavernInterior.gd",
			"res://src/exploration/OverworldScene.gd"]:
		assert_true(known in paths, "derived list must contain %s" % known)
	assert_gte(paths.size(), 50, "derivation regressed — GameLoop mounts 50+ map scripts (59 at authoring)")
	for path in paths:
		var chain := _chain_source(path)
		assert_true("func pause(" in chain,
			"%s must declare/inherit pause() — has_method guard silently skips it (tavern class)" % path)
		assert_true("func resume(" in chain,
			"%s must declare/inherit resume() — else the menu-close resume is silently skipped" % path)


func test_shop_and_inn_pause_actually_push_the_lock() -> void:
	# Runtime half: the new methods must reach the controller's lock, not just exist.
	var ControllerScript = preload("res://src/exploration/OverworldController.gd")
	for path in ["res://src/maps/interiors/ShopInterior.gd", "res://src/maps/interiors/InnInterior.gd"]:
		var scene: Node2D = load(path).new()  # no add_child: _ready builds a full interior, not needed here
		autofree(scene)
		var controller = ControllerScript.new()
		add_child_autofree(controller)
		await get_tree().physics_frame
		scene.controller = controller
		scene.pause()
		assert_true(InputLockManager.has_lock("exploration_paused"),
			"%s.pause() must push the exploration lock" % path)
		scene.resume()
		assert_false(InputLockManager.has_lock("exploration_paused"),
			"%s.resume() must pop the exploration lock" % path)


func test_autobattle_menu_action_never_strands_on_null_target() -> void:
	# 2026-08-14: "autobattle" with a null target tore the menu down and opened
	# nothing — player stranded paused with no UI. Teardown must be target-guarded
	# and the null path must degrade to the plain close (which resumes).
	var src := FileAccess.get_file_as_string(GL_PATH)
	var arm_start := src.find("\"autobattle\":")
	var arm_end := src.find("\"autobattle_toggle\":", arm_start)
	assert_gt(arm_start, -1, "autobattle menu-action arm must exist")
	assert_gt(arm_end, arm_start, "autobattle_toggle arm must follow")
	var arm := src.substr(arm_start, arm_end - arm_start)
	var guard := arm.find("if target:")
	var teardown := arm.find("_teardown_overworld_menu_widget()")
	assert_gt(guard, -1, "arm must branch on target")
	assert_gt(teardown, guard, "teardown must sit INSIDE the target guard — unguarded teardown strands the player")
	assert_true("_on_overworld_menu_closed()" in arm,
		"the null-target path must degrade to the plain close (resume + HUD restore)")
