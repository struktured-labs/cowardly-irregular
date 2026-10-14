extends GutTest

## Every world warp played the DEPARTED world's overworld bed, with its stinger, before the
## destination's (2026-10-14). struktured's 10-13 session on v3.33.684-alpha, 3 warps of 3:
##
##     352 [TELEPORT] Warping to: Steampunk Region (steampunk_overworld)
##     354 [MUSIC] Playing from manifest: overworld_suburban      <- the world he LEFT
##     363 [MUSIC] Playing from manifest: overworld_steampunk     <- correct, 9 lines later
##
## It is NOT the destination logic and NOT the world-suffix cache. `_on_teleport_requested` runs
## `_teardown_overworld_menu_widget()` BEFORE `_on_area_transition`, and the teardown's bug-2801
## restore sees `_current_music == "menu"` and reinstates `_pre_menu_music_state` — the snapshot
## taken when the player OPENED the menu, i.e. where they were. Warp 3 proves it: teleporting to
## Harmonia played `overworld_industrial` first, because industrial is where he stood.
##
## The restore is CORRECT for a normal menu close and arm 2 keeps it that way. On a teleport it is
## wrong (the departed world) and pointless (the transition sets music a beat later).
##
## ⚠️ KNOWN SIBLING, NOT FIXED HERE AND NOT SILENTLY: `_on_settings_teleport_requested` has the
## OPPOSITE emit order — its own docstring says the settings menu emits `closed` BEFORE
## `teleport_requested`, so that restore has already run by the time the teleport is known and no
## flag set in the handler can suppress it. It needs a one-line change in SettingsMenu, another
## lane's file. All three of his warps came through the overworld menu, which is this path.

const GameLoopScript := preload("res://src/GameLoop.gd")

## _derive_current_scene_music_key asks the exploration scene for its area. A bare GameLoop has none,
## so it returns "" and the restore's SECOND stage is unreachable — the blind spot this stub removes.
class _SceneStub extends Node:
	func _get_music_area_id() -> String:
		return "village"

var _gl: Node = null
var _sm = null


func before_each() -> void:
	_sm = SoundManager
	_gl = GameLoopScript.new()


func after_each() -> void:
	if is_instance_valid(_gl):
		_gl.free()
	if _sm != null:
		_sm.stop_music()


func test_the_members_this_file_drives_exist() -> void:
	assert_not_null(_sm, "SoundManager autoload missing")
	assert_not_null(_gl, "GameLoop did not instantiate")
	assert_true("_teleport_transition_pending" in _gl, "the suppression flag is gone")
	assert_true("_pre_menu_music_state" in _gl, "the snapshot this guard loads is gone")
	assert_true(_gl.has_method("_teardown_overworld_menu_widget"), "the teardown is gone")
	for m in ["capture_music_state", "restore_music_state", "play_area_music", "play_music"]:
		assert_true(_sm.has_method(m), "SoundManager.%s is gone" % m)


## Puts the engine in the state a teleport finds: an area bed snapshotted, menu music playing over it.
func _arm_menu_over_area() -> Dictionary:
	_sm.play_area_music("overworld")
	## AWAITED, and the control arm is what forced it: capture_music_state() records `playing`, and
	## restore_music_state NO-OPS on a not-playing snapshot. Capturing in the same frame as the play
	## call gave playing=false, so the restore never ran and the DEFECT arm passed on anything.
	await get_tree().create_timer(0.15).timeout
	var snap: Dictionary = _sm.capture_music_state()
	assert_true(bool(snap.get("playing", false)),
		"CONTROL: the snapshot must be PLAYING or restore_music_state no-ops and this file measures nothing")
	_sm.play_music("menu")
	return snap


## CONTROL FIRST, and it is load-bearing twice: it proves the teardown REACHES its restore on a bare
## instance (a GDScript error above it would abort the function and every later arm would pass
## vacuously), and it is bug 2801's own invariant — a normal close must get OFF menu.
func test_a_normal_menu_close_still_restores_the_field_bed() -> void:
	var snap: Dictionary = await _arm_menu_over_area()
	assert_eq(_sm._current_music, "menu", "CONTROL: menu music must be playing before the teardown")
	_gl._pre_menu_music_state = snap
	_gl._teleport_transition_pending = false
	_gl._teardown_overworld_menu_widget()
	assert_ne(_sm._current_music, "menu",
		"a normal menu close no longer restores the field bed — bug 2801 regressed, the menu bed bleeds into the overworld")


## THE DEFECT: with a teleport in flight the pre-menu bed must NOT come back.
func test_a_teleport_does_not_restore_the_bed_of_the_world_being_left() -> void:
	var snap: Dictionary = await _arm_menu_over_area()
	_gl._pre_menu_music_state = snap
	_gl._teleport_transition_pending = true
	_gl._teardown_overworld_menu_widget()
	## ASSERTED DIRECTLY, not against snap["track"]: capture_music_state() reports `track` as whatever
	## _current_music happened to be, and his own stinger log shows it EMPTY for an area bed
	## ({"track": "", "area": "village"}). A != "" comparison would pass whether or not the restore ran.
	assert_true(snap.get("area", "") != "" or snap.get("track", "") != "",
		"CONTROL: the snapshot captured nothing, so there is no bed for a restore to bring back")
	assert_eq(_sm._current_music, "menu",
		"the teardown restored the pre-menu bed during a teleport — the world the player is LEAVING, which is what he heard on all three warps (got %s)" % _sm._current_music)


## THE ARMING, which every arm above is blind to because they set the flag DIRECTLY. Without this a
## mutation deleting the `= true` in the handler leaves this whole file green and the defect returns.
## ORDERING is the assertion, not presence: armed AFTER the teardown call is armed too late, because
## the teardown is where the restore lives.
func test_the_teleport_handler_arms_the_flag_before_the_teardown() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 0, "could not read GameLoop")
	var at: int = src.find("func _on_teleport_requested")
	assert_gt(at, -1, "the teleport handler is gone")
	var nxt: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, nxt - at) if nxt > at else src.substr(at)
	var armed: int = body.find("_teleport_transition_pending = true")
	var teardown: int = body.find("_teardown_overworld_menu_widget()")
	assert_gt(armed, -1, "the handler no longer arms the suppression flag, so the teardown will restore the departed world's bed again")
	assert_gt(teardown, -1, "the handler no longer calls the teardown — this guard's subject moved")
	assert_lt(armed, teardown, "the flag is armed AFTER the teardown, which is too late: the restore it suppresses has already run")


## STAGE 2 OF THE RESTORE, which every arm above is blind to: they all exercise the SNAPSHOT restore,
## and a bare GameLoop has no _exploration_scene, so _derive_current_scene_music_key() returns "" and
## the fallback can never fire whatever the flag does. It is a REAL second route to the same symptom —
## it runs when the snapshot no-ops (empty or not-playing), so a player who opens the menu while a bed
## is stopped and then teleports reaches it, and it asks the OLD scene for its area.
func test_the_fallback_stage_is_suppressed_too() -> void:
	var stub := _SceneStub.new()
	add_child_autofree(stub)
	_gl._exploration_scene = stub
	_sm.play_music("menu")
	## EMPTY by construction, so stage 1 cannot act and only stage 2 can move the music.
	_gl._pre_menu_music_state = {}
	assert_eq(_sm._current_music, "menu", "CONTROL: menu music must be playing before the teardown")
	_gl._teleport_transition_pending = true
	_gl._teardown_overworld_menu_widget()
	assert_eq(_sm._current_music, "menu",
		"the FALLBACK stage ran during a teleport and asked the OLD scene for its area — the departed world's bed, by the second route (got %s)" % _sm._current_music)
	## And the same state with no teleport MUST reach it, or the arm above passes because stage 2 is
	## simply unreachable rather than because the flag suppressed it.
	_gl._exploration_scene = stub
	_sm.play_music("menu")
	_gl._pre_menu_music_state = {}
	_gl._teleport_transition_pending = false
	_gl._teardown_overworld_menu_widget()
	assert_ne(_sm._current_music, "menu",
		"CONTROL: without a teleport the fallback must fire, or this arm proves nothing")


## The flag must not leak: a teleport followed by an ordinary close still restores.
func test_the_suppression_does_not_outlive_its_teleport() -> void:
	var snap: Dictionary = await _arm_menu_over_area()
	_gl._pre_menu_music_state = snap
	_gl._teleport_transition_pending = true
	_gl._teardown_overworld_menu_widget()
	assert_false(_gl._teleport_transition_pending, "the flag survived its teardown and would suppress the NEXT ordinary close")
	var snap2: Dictionary = await _arm_menu_over_area()
	_gl._pre_menu_music_state = snap2
	_gl._teardown_overworld_menu_widget()
	assert_ne(_sm._current_music, "menu", "the next ordinary close did not restore — the flag leaked")
