extends Area2D
class_name VillageElevator
## Two-endpoint platform: press-A rides the player between a bottom and a top tier, bypassing stairs entirely.

enum Style { BRASS, HAZARD, NEON }

const TILE_SIZE := 32
const RIDE_TIME := 0.35
const LOCK_ID := "village_elevator"

@export var style: int = Style.BRASS
@export var bottom_position: Vector2 = Vector2.ZERO
@export var top_position: Vector2 = Vector2.ZERO
@export var sfx_key: String = "steam_hiss"

var _busy := false


static func create(elevator_style: int, bottom: Vector2, top: Vector2, sfx: String) -> VillageElevator:
	var e := VillageElevator.new()
	e.style = elevator_style
	e.bottom_position = bottom
	e.top_position = top
	e.sfx_key = sfx
	e.name = "Elevator_%s_%d_%d" % [Style.keys()[elevator_style], int(bottom.x), int(bottom.y)]
	return e


func _ready() -> void:
	position = bottom_position
	_setup_visuals()
	_setup_collision()


func _setup_collision() -> void:
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 1.5, TILE_SIZE * 1.5)
	collision.shape = shape
	add_child(collision)
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	monitorable = true


func _setup_visuals() -> void:
	var bottom_pad := Sprite2D.new()
	bottom_pad.name = "BottomPad"
	bottom_pad.texture = ImageTexture.create_from_image(_draw_pad())
	add_child(bottom_pad)
	var top_pad := Sprite2D.new()
	top_pad.name = "TopPad"
	top_pad.texture = ImageTexture.create_from_image(_draw_pad())
	top_pad.position = top_position - bottom_position
	add_child(top_pad)


## Procedural pad art, style-keyed same as EnvironmentTileSets' approach — a bordered plate with a style accent.
func _draw_pad() -> Image:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base: Color
	var trim: Color
	match style:
		Style.HAZARD:
			base = Color(0.30, 0.30, 0.32)
			trim = Color(0.85, 0.45, 0.10)
		Style.NEON:
			base = Color(0.06, 0.08, 0.12)
			trim = Color(0.25, 0.95, 0.95)
		_:
			base = Color(0.45, 0.30, 0.12)
			trim = Color(0.80, 0.62, 0.26)
	img.fill(base)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, trim)
		img.set_pixel(x, TILE_SIZE - 1, trim)
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, trim)
		img.set_pixel(TILE_SIZE - 1, y, trim)
	if style == Style.HAZARD:
		for i in range(0, TILE_SIZE * 2, 6):
			for x in range(TILE_SIZE):
				var y := i - x
				if y >= 3 and y < TILE_SIZE - 3:
					img.set_pixel(x, y, trim)
	else:
		for x in range(6, TILE_SIZE - 6, 6):
			for y in range(6, TILE_SIZE - 6, 6):
				img.set_pixel(x, y, trim)
	return img


## Rides the player to the FAR endpoint — nearest endpoint to the caller is the origin, the other is the destination.
func interact(player: Node2D) -> void:
	if _busy:
		return
	_busy = true
	var to_bottom: float = player.global_position.distance_to(bottom_position)
	var to_top: float = player.global_position.distance_to(top_position)
	var origin: Vector2 = bottom_position if to_bottom <= to_top else top_position
	var destination: Vector2 = top_position if to_bottom <= to_top else bottom_position
	InputLockManager.push_lock(LOCK_ID)
	if SoundManager:
		SoundManager.play_ui(sfx_key)
	var car := Sprite2D.new()
	car.texture = ImageTexture.create_from_image(_draw_pad())
	car.global_position = origin
	get_parent().add_child(car)
	var tween := create_tween()
	tween.tween_property(car, "global_position", destination, RIDE_TIME)
	await tween.finished
	car.queue_free()
	if player.has_method("teleport"):
		player.teleport(destination)
	else:
		player.global_position = destination
	InputLockManager.pop_lock(LOCK_ID)
	_busy = false
