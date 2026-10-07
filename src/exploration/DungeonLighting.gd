class_name DungeonLighting
extends VillageLighting
## A cave has no sky. Same lamp machinery as the village rig, but the ambient is fixed
## per-dungeon instead of tracking the day clock — walking into a cave at noon must not
## light it like a meadow.

## Brightened from (0.30, 0.29, 0.42) -- struktured 2026-10-06: the dungeon pass read as
## too dark to track the player or interactables. Still underground-dark, now legible.
const CAVE_AMBIENT := Color(0.36, 0.35, 0.48)

var ambient: Color = CAVE_AMBIENT
var _flicker_t: float = 0.0
## Kept OUT of _lamps deliberately: _place_torches clears and rebuilds _lamps every floor
## (test_relighting_a_floor_does_not_accumulate_torches), which would delete the player
## light on the first floor change. Tracked by position-follow instead of reparenting onto
## the player, so test_lamps_hang_under_the_modulate_so_they_pierce_the_dark still holds —
## every light stays a direct child of this CanvasModulate.
var _player_light: PointLight2D = null
var _player_light_target: Node2D = null


## Deliberately ignores day_phase AND phase_override: underground is underground. The
## screenshot tool pins a phase on every scene it loads, and a cave must not answer to it.
func tint_now() -> Color:
	return ambient


## Torch/crystal flicker, layered on top of VillageLighting's base energy curve. Two sine
## terms per lamp, phased by its own instance id so torches don't flicker in lockstep.
func _process(delta: float) -> void:
	super._process(delta)
	_flicker_t += delta
	for l in _lamps:
		if is_instance_valid(l):
			var ph: float = float(l.get_instance_id() % 997) * 0.01
			l.energy *= 1.0 + 0.07 * sin(_flicker_t * 9.0 + ph * 30.0) + 0.04 * sin(_flicker_t * 23.0 + ph * 50.0)
	if _player_light != null and is_instance_valid(_player_light) and _player_light_target != null and is_instance_valid(_player_light_target):
		_player_light.position = _player_light_target.position


## A soft light that travels with the player so the immediate surroundings and any
## interactable stay readable regardless of lamp proximity. Position is refreshed every
## frame rather than by reparenting (see _player_light comment above).
func add_player_light(target: Node2D, lamp_color: Color = Color(1.0, 0.93, 0.80), radius: int = 150, energy: float = 0.85) -> PointLight2D:
	var l := PointLight2D.new()
	l.position = target.position
	l.color = lamp_color
	l.texture = _make_light_texture(radius)
	l.energy = energy
	add_child(l)
	_player_light = l
	_player_light_target = target
	return l
