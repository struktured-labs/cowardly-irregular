extends GutTest

## Regression tests for OverworldNPC.gd delegating to NPCDialogue/CutsceneDialogue
## (2026-05-20 commits c7cc594 + this test).
##
## Bug 1: Village dialogue boxes were cut off near screen edges because
## they were drawn as a Control child of the NPC Node2D with hardcoded
## relative offsets — when the NPC sat near a viewport edge, the panel
## drew off-screen.
##
## Bug 2: Gamepad ui_accept didn't advance cutscene dialogue (mouse
## click did). OverworldNPC's _input was intercepting ui_accept on every
## frame the player was nearby, leaving nothing for CutsceneDialogue's
## own _input handler.
##
## Fix: OverworldNPC._start_dialogue now creates an NPCDialogue (which
## wraps CutsceneDialogue) and awaits say_lines(). _input only
## intercepts ui_accept to OPEN dialogue — after that CutsceneDialogue
## handles advance/close itself via its CanvasLayer-rooted _input.
## Both bugs resolve as a side-effect of the CanvasLayer-anchored
## dialogue panel (screen-fixed, full-width, gamepad-friendly).


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_overworld_npc_delegates_dialogue_to_npc_dialogue() -> void:
	"""OverworldNPC._start_dialogue must instantiate NPCDialogue and
	await its say_lines — that's the canvas-layer-rooted dialogue
	path. The Node2D-relative local panel must NOT be the production
	render target."""
	var src = _read("res://src/exploration/OverworldNPC.gd")
	# Look for the NPCDialogue class load and call.
	assert_true(src.find("NPCDialogue.gd") != -1,
		"OverworldNPC must load NPCDialogue (regression: village dialogue cut-off + gamepad input bug)")
	assert_true(src.find("say_lines") != -1,
		"OverworldNPC must call NPCDialogue.say_lines() with the dialogue lines")


func test_overworld_npc_input_only_intercepts_to_open_dialogue() -> void:
	"""_input must NOT intercept ui_accept while dialogue is open —
	otherwise CutsceneDialogue's own _input never sees the gamepad
	press and the player can't advance via controller."""
	var src = _read("res://src/exploration/OverworldNPC.gd")
	# The fix uses "not _is_talking" guard in the input handler.
	# A regression that removed the guard would intercept ui_accept
	# during conversation, blocking CutsceneDialogue's advance path.
	assert_true(src.find("not _is_talking") != -1,
		"OverworldNPC._input must guard with 'not _is_talking' (regression: gamepad couldn't advance dialogue)")


func test_overworld_npc_freezes_player_during_dialogue() -> void:
	"""Matching WanderingNPC, OverworldNPC should freeze the player
	while talking — otherwise the player can walk away mid-dialogue
	and end up in weird states (NPC trigger area exit while text
	queue still active)."""
	var src = _read("res://src/exploration/OverworldNPC.gd")
	assert_true(src.find("set_can_move(false)") != -1,
		"OverworldNPC must freeze player on dialogue open (set_can_move(false))")
	assert_true(src.find("set_can_move(true)") != -1,
		"OverworldNPC must unfreeze player on dialogue close (set_can_move(true))")


func test_wandering_npc_uses_same_dialogue_path() -> void:
	"""Sanity check: WanderingNPC was the proven NPCDialogue user
	(working gamepad input, no cut-off). If WanderingNPC ever stops
	using NPCDialogue, the dialogue path I aligned OverworldNPC to
	has drifted — re-evaluate the migration."""
	var src = _read("res://src/exploration/WanderingNPC.gd")
	assert_true(src.find("NPCDialogue") != -1,
		"WanderingNPC must still use NPCDialogue (reference implementation for OverworldNPC migration)")


func test_cutscene_dialogue_accepts_gamepad_ui_accept() -> void:
	"""CutsceneDialogue (the underlying renderer for NPCDialogue) must
	listen for ui_accept in its _input. Without this, no MCP, no fix,
	no migration helps — the panel becomes click-only."""
	var src = _read("res://src/cutscene/CutsceneDialogue.gd")
	assert_true(src.find('is_action_pressed("ui_accept")') != -1,
		"CutsceneDialogue must check ui_accept (gamepad/keyboard advance)")
