extends Node
class_name ZoneParticles

## ZoneParticles — ambient particle effects per overworld zone.
## Falling leaves in forest, snowflakes in ice, dust in desert, etc.

var _emitter: CPUParticles2D
var _current_zone: String = ""
var _player_ref: Node2D

const ZONE_CONFIGS: Dictionary = {
	"forest": {
		"color": Color(0.4, 0.7, 0.2, 0.6),
		"amount": 20,
		"lifetime": 3.0,
		"gravity": Vector2(15.0, 40.0),
		"scale_min": 0.4,
		"scale_max": 0.8,
	},
	"ice": {
		"color": Color(0.85, 0.92, 1.0, 0.7),
		"amount": 30,
		"lifetime": 4.0,
		"gravity": Vector2(5.0, 20.0),
		"scale_min": 0.2,
		"scale_max": 0.5,
	},
	"desert": {
		"color": Color(0.8, 0.7, 0.5, 0.4),
		"amount": 15,
		"lifetime": 2.5,
		"gravity": Vector2(30.0, 10.0),
		"scale_min": 0.3,
		"scale_max": 0.6,
	},
	"swamp": {
		"color": Color(0.3, 0.5, 0.2, 0.5),
		"amount": 12,
		"lifetime": 3.5,
		"gravity": Vector2(3.0, 8.0),
		"scale_min": 0.3,
		"scale_max": 0.7,
	},
	"volcanic": {
		"color": Color(1.0, 0.4, 0.1, 0.5),
		"amount": 10,
		"lifetime": 2.0,
		"gravity": Vector2(5.0, -15.0),  # Embers rise
		"scale_min": 0.2,
		"scale_max": 0.4,
	},
}


func setup(parent: Node, player: Node2D) -> void:
	_player_ref = player
	_emitter = CPUParticles2D.new()
	_emitter.name = "ZoneParticles"
	_emitter.z_index = 3
	_emitter.emitting = false
	_emitter.one_shot = false
	_emitter.explosiveness = 0.0
	_emitter.randomness = 0.5
	_emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_emitter.emission_rect_extents = Vector2(300, 200)
	parent.add_child(_emitter)


func update_zone(zone: String) -> void:
	if zone == _current_zone:
		return
	_current_zone = zone

	if not ZONE_CONFIGS.has(zone):
		_emitter.emitting = false
		return

	var cfg = ZONE_CONFIGS[zone]
	_emitter.color = cfg["color"]
	_emitter.amount = cfg["amount"]
	_emitter.lifetime = cfg["lifetime"]
	_emitter.gravity = cfg["gravity"]
	_emitter.scale_amount_min = cfg["scale_min"]
	_emitter.scale_amount_max = cfg["scale_max"]
	_emitter.initial_velocity_min = 5.0
	_emitter.initial_velocity_max = 15.0
	_emitter.emitting = true


func update_position(player_pos: Vector2) -> void:
	if _emitter:
		_emitter.global_position = player_pos + Vector2(0, -100)
