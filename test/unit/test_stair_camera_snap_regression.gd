extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## Taking the stairs teleports you onto the other staircase while the camera
## is still smoothing toward the one you left. The view then slides across
## the dungeon for the whole movement lock. Puzzle warps already snap
## (DragonCave.puzzle_warp_to); the stair change did not.
##
## Measured before the fix, Whispering Cave floor 1 -> 2: the player moved
## 314px and one frame later the view was still 297px behind them.
## reset_smoothing() commits on the camera's next update, so the read is
## one process frame later. Smoothing speed is zeroed first: at the live
## speed of 8 a long frame lerps the whole gap and a missed snap looks
## like a cut. Speed 0 cannot catch up; only the snap can.

const WHISPERING := preload("res://src/maps/dungeons/WhisperingCave.gd")
const FIRE_CAVE := preload("res://src/maps/dungeons/FireDragonCave.gd")
const _DIRECTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]

var _viewport: SubViewport
var _held_floors: Dictionary = {}
var _floor_was_present: Dictionary = {}


func before_each() -> void:
	for a in _DIRECTIONS:
		Input.action_release(a)
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	_viewport.size = Vector2i(640, 360)
	add_child(_viewport)
	_hold_floor_keys()


func after_each() -> void:
	_restore_floor_keys()
	if _viewport and is_instance_valid(_viewport):
		_viewport.queue_free()
	for a in _DIRECTIONS:
		Input.action_release(a)


func _hold_floor_keys() -> void:
	_held_floors = {}
	_floor_was_present = {}
	if GameState == null:
		return
	# The stair writes this key; leaving it set makes the next map test load floor 2.
	for key in ["whispering_cave_floor", "fire_dragon_cave_floor"]:
		var present: bool = GameState.game_constants.has(key)
		_floor_was_present[key] = present
		if present:
			_held_floors[key] = GameState.game_constants[key]
			GameState.game_constants.erase(key)


func _restore_floor_keys() -> void:
	if GameState == null:
		return
	for key in _floor_was_present:
		if _floor_was_present[key]:
			GameState.game_constants[key] = _held_floors[key]
		else:
			GameState.game_constants.erase(key)


func _clamped_view_center(cam: Camera2D, landing: Vector2) -> Vector2:
	var vp_size: Vector2 = cam.get_viewport().get_visible_rect().size
	var half := Vector2(vp_size.x / (2.0 * cam.zoom.x), vp_size.y / (2.0 * cam.zoom.y))
	var center := landing
	center.x = clampf(center.x, cam.limit_left + half.x, cam.limit_right - half.x)
	center.y = clampf(center.y, cam.limit_top + half.y, cam.limit_bottom - half.y)
	return center


func _settle(cave: Node) -> void:
	_viewport.add_child(cave)
	for _i in 8:
		await get_tree().process_frame


## The view center must already be on the landing the moment the teleport happens.
func _assert_the_view_is_on_the_landing(cave: Node, target_floor: int) -> void:
	var player: Node2D = cave.player
	var cam: Camera2D = cave.camera
	assert_not_null(player, "the cave built a player")
	assert_not_null(cam, "the cave built a camera")
	var origin: Vector2 = player.global_position
	var settled: float = cam.get_screen_center_position().distance_to(origin)
	assert_lt(settled, 1.0,
		"CONTROL: the camera must already be on the player before the stair — a snap cannot be told from a camera that never tracked (gap %.1f)" % settled)
	assert_true(cam.position_smoothing_enabled,
		"CONTROL: these stairs only whip the view while smoothing is on")
	cam.position_smoothing_speed = 0.0
	cave._transition_to_floor(target_floor, "up")
	await get_tree().process_frame
	var landing: Vector2 = player.global_position
	var moved: float = landing.distance_to(origin)
	assert_gt(moved, 64.0,
		"CONTROL: this stair must land far enough away that the view has somewhere to lag (moved %.1f)" % moved)
	# Edge landings cannot be framed on the player; the snap owes the limit-clamped center.
	var expected: Vector2 = _clamped_view_center(cam, landing)
	assert_gt(expected.distance_to(origin), 64.0,
		"CONTROL: the clamped view must actually travel, or a camera that never moved still looks snapped")
	var gap: float = cam.get_screen_center_position().distance_to(expected)
	assert_lt(gap, 1.0,
		"the view is still %.0fpx from where this landing can be framed, after a %.0fpx stair teleport — it kept smoothing in from the stair you left" % [gap, moved])
	# The transition awaits 0.8s of timers. Let it finish before the cave is freed.
	await get_tree().create_timer(1.0).timeout


func test_whispering_cave_stairs_snap_the_camera() -> void:
	var cave = WHISPERING.new()
	await _settle(cave)
	await _assert_the_view_is_on_the_landing(cave, 2)


func test_dragon_cave_stairs_snap_the_camera() -> void:
	var cave = FIRE_CAVE.new()
	await _settle(cave)
	await _assert_the_view_is_on_the_landing(cave, 2)


## Both caves call play_area_music from _ready, which writes the music autoload.
func after_all() -> void:
	SoundState.restore()
