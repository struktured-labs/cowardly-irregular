extends Node

## On arrival, shifts a room camera so the player and the room's keeper share one frame; eases back to plain follow once the player walks.

## A sprite drawn at position p spans p.y - SPRITE_UP .. p.y + SPRITE_DOWN (48 px frames, centred, lifted 8 px).
const SPRITE_UP := 32.0
const SPRITE_DOWN := 16.0
const SPRITE_HALF_W := 16.0
## Per-frame moves at or above this are a placement (spawn, restored tile), not a step.
const PLACEMENT_PX := 24.0
## A walk this far from the arrival point hands the camera back.
const LEAVE_PX := 4.0
const SETTLE_TIME := 0.35

var camera: Camera2D
var player: Node2D
var keeper: Node2D
var _anchor := Vector2.INF
var _released := false


## Wires the focus to a room; a null camera, player or keeper leaves plain follow alone.
func setup(cam: Camera2D, who: Node2D, kept: Node2D) -> bool:
	camera = cam
	player = who
	keeper = kept
	name = "EntryFocus"
	return cam != null and who != null and kept != null


## The camera's limits as a rect.
static func limits_of(cam: Camera2D) -> Rect2:
	return Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top)


## Where the view lands for a given centre once the limits clamp it (the engine clamps before it adds `offset`).
static func clamped_view(center: Vector2, view: Vector2, limits: Rect2) -> Rect2:
	var pos := center - view * 0.5
	pos.x = clampf(pos.x, limits.position.x, maxf(limits.position.x, limits.end.x - view.x))
	pos.y = clampf(pos.y, limits.position.y, maxf(limits.position.y, limits.end.y - view.y))
	return Rect2(pos, view)


## The rect both sprites occupy.
static func pair_rect(player_pos: Vector2, keeper_pos: Vector2) -> Rect2:
	var r := Rect2(player_pos - Vector2(SPRITE_HALF_W, SPRITE_UP), Vector2(SPRITE_HALF_W * 2.0, SPRITE_UP + SPRITE_DOWN))
	return r.merge(Rect2(keeper_pos - Vector2(SPRITE_HALF_W, SPRITE_UP), Vector2(SPRITE_HALF_W * 2.0, SPRITE_UP + SPRITE_DOWN)))


## Camera offset that frames player and keeper together, or ZERO when plain follow already shows both or they cannot share one view.
static func framing_offset(player_pos: Vector2, keeper_pos: Vector2, view: Vector2, limits: Rect2) -> Vector2:
	var base := clamped_view(player_pos, view, limits)
	var pair := pair_rect(player_pos, keeper_pos)
	if base.encloses(pair) or pair.size.x > view.x or pair.size.y > view.y:
		return Vector2.ZERO
	var want := clamped_view(pair.get_center(), view, limits)
	return want.position - base.position


func _view_size() -> Vector2:
	return camera.get_viewport_rect().size / camera.zoom


func _process(_delta: float) -> void:
	if _released or not is_instance_valid(camera) or not is_instance_valid(player) or not is_instance_valid(keeper):
		return
	var at := player.global_position
	if _anchor == Vector2.INF or at.distance_to(_anchor) >= PLACEMENT_PX:
		_anchor = at
		camera.offset = framing_offset(at, keeper.global_position, _view_size(), limits_of(camera))
		return
	if at.distance_to(_anchor) > LEAVE_PX:
		_release()


func _release() -> void:
	_released = true
	var tw := create_tween()
	tw.tween_property(camera, "offset", Vector2.ZERO, SETTLE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(queue_free)
