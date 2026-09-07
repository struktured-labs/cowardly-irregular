extends GutTest

## struktured playtest 2026-07-11, three reports with one root class —
## cutscene input was never exclusive and Mode 7 state leaked across scenes:
## 1. Pressing A to advance dialogue near a save point fired the save-point
##    interact ("Cannot save mid-cutscene" toast spam) and could trigger NPC
##    LLM dialogue OVER the cutscene — _freeze_player only set the legacy
##    can_move flag via MapSystem.get_player(), which is null on overworld
##    scenes, and never touched InputLockManager (the canonical gate that
##    OverworldPlayer._can_move actually consults).
## 2. A wandering villager strolled through the party mid-cutscene —
##    WanderingNPC._process had no lock awareness.
## 3. Villages felt like "bad object detection" — Mode7Overlay.is_active
##    (a STATIC) stayed true after leaving the overworld, giving villages
##    the 2x horizontal movement boost; doors became near-impossible to hit.

const Mode7Script := preload("res://src/exploration/Mode7Overlay.gd")


func test_cutscene_freeze_pushes_the_canonical_lock() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var freeze := src.substr(src.find("func _freeze_player"),
		src.find("func _unfreeze_player") - src.find("func _freeze_player"))
	assert_true("push_lock(\"cutscene\")" in freeze,
		"_freeze_player must push the InputLockManager 'cutscene' lock — the legacy flag alone leaks interacts")
	var unfreeze := src.substr(src.find("func _unfreeze_player"), 400)
	assert_true("pop_lock(\"cutscene\")" in unfreeze,
		"_unfreeze_player must pop the same lock or exploration stays frozen forever")


func test_wandering_npc_freezes_under_input_lock() -> void:
	var npc = load("res://src/exploration/WanderingNPC.gd").new()
	add_child_autofree(npc)
	var pts: Array[Vector2] = [Vector2.ZERO, Vector2(100, 0)]
	npc._patrol_points = pts
	npc._current_target = 1
	npc.global_position = Vector2.ZERO
	InputLockManager.push_lock("test_cutscene")
	npc._process(0.5)
	assert_eq(npc.global_position, Vector2.ZERO,
		"a locked frame must not move the wanderer — it walked through the party mid-cutscene")
	InputLockManager.pop_lock("test_cutscene")
	npc._process(0.5)
	assert_ne(npc.global_position, Vector2.ZERO, "unlocked frames must resume the patrol")


func test_mode7_static_cleared_on_cleanup_and_by_villages() -> void:
	Mode7Script.is_active = true
	var overlay = Mode7Script.new()
	add_child_autofree(overlay)
	overlay.cleanup()
	assert_false(Mode7Script.is_active,
		"cleanup() must clear the is_active static — stale true gave villages the 2x boost")
	Mode7Script.is_active = true
	for path in ["res://src/maps/villages/BaseVillage.gd", "res://src/maps/interiors/BaseInterior.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_true("Mode7Overlay.is_active = false" in src,
			"%s must defensively clear the Mode 7 static in _ready" % path)
	Mode7Script.is_active = false
