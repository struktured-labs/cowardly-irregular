extends GutTest

## Regression test for the tavern input-leak bug (user-reported 2026-06-04,
## re-applied from commit 2ca618a).
##
## Bug: TavernInterior extends Node2D directly (NOT BaseVillage) and originally
## defined neither pause() nor resume(). GameLoop guards every suspend/resume
## call with `if _exploration_scene.has_method("pause")` (see GameLoop.gd lines
## 384-385, 551-552, 587-588, 623-624, 725, 1129-1134, 2879-2880, ...), so the
## call was SILENTLY skipped in the tavern. The OverworldMenu does not change
## current_state (stays EXPLORATION) and OverworldPlayer movement is read by
## polling Input.is_action_pressed() in _physics_process — unaffected by the
## menu's set_input_as_handled(). So with the menu open the player kept walking
## behind it and could walk into the exit door (require_interaction=false,
## auto-triggers on body_entered), firing a full scene change under the open UI.
##
## Fix: TavernInterior now defines pause()/resume() that delegate to
## controller.pause_exploration()/resume_exploration() (which push/pop the
## InputLockManager 'exploration_paused' lock), mirroring BaseVillage.
##
## These are source-level contract assertions: EVERY exploration scene
## reachable from GameLoop._start_exploration() (villages via BaseVillage,
## caves, the tavern interior, and the overworld scene) MUST declare both
## pause() and resume(). This catches the silent-skip class (has_method false)
## that a runtime test would miss, and would have caught the original bug.


## Every exploration-scene script GameLoop mounts as _exploration_scene.
const EXPLORATION_SCENE_SCRIPTS := [
	"res://src/maps/villages/BaseVillage.gd",
	"res://src/maps/dungeons/DragonCave.gd",
	"res://src/maps/dungeons/WhisperingCave.gd",
	"res://src/maps/interiors/TavernInterior.gd",
	"res://src/exploration/OverworldScene.gd",
]


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_every_exploration_scene_declares_pause_and_resume() -> void:
	"""GameLoop suspends/resumes exploration via has_method('pause')/
	has_method('resume'). Any scene missing either method is silently
	skipped — the tavern input-leak bug. Guard the whole contract here."""
	for path in EXPLORATION_SCENE_SCRIPTS:
		var text = _read(path)
		assert_true(text.find("func pause()") != -1,
			"%s MUST declare func pause() (regression: silent has_method skip leaks input)" % path)
		assert_true(text.find("func resume()") != -1,
			"%s MUST declare func resume() (regression: silent has_method skip leaks input)" % path)


func test_tavern_pause_delegates_to_controller() -> void:
	"""TavernInterior.pause()/resume() must forward to the controller's
	pause_exploration()/resume_exploration() (which push/pop the
	InputLockManager 'exploration_paused' lock). A no-op pause() would
	satisfy has_method() but still leak input — assert the delegation."""
	var text = _read("res://src/maps/interiors/TavernInterior.gd")
	assert_true(text.find("controller.pause_exploration()") != -1,
		"TavernInterior.pause() must call controller.pause_exploration() (regression 2026-06-04)")
	assert_true(text.find("controller.resume_exploration()") != -1,
		"TavernInterior.resume() must call controller.resume_exploration() (regression 2026-06-04)")


func test_overworld_controller_exposes_pause_resume_exploration() -> void:
	"""Defensive: the delegation targets must exist on OverworldController,
	or every scene's pause()/resume() is a silent no-op (has_method guard
	inside each scene falls through)."""
	var text = _read("res://src/exploration/OverworldController.gd")
	assert_true(text.find("func pause_exploration()") != -1,
		"OverworldController must declare func pause_exploration() (delegation target)")
	assert_true(text.find("func resume_exploration()") != -1,
		"OverworldController must declare func resume_exploration() (delegation target)")
