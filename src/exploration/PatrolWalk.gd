class_name PatrolWalk
extends RefCounted

## The ONE walk-between-points loop. A WanderingNPC's patrol on the field and an interior NPC's stroll both step
## through this, so there is one place that decides how a figure walks to a point, rests there and moves on.

const ARRIVE_PX := 4.0

var points: Array[Vector2] = []
## Per point: rest on arrival? Empty = rest at every point, as a patrol always has. A stroll rests only at its spots.
var rests: Array = []
var speed: float = 40.0
var pause_min: float = 2.0
var pause_max: float = 5.0
## null = the global generator, as the patrol has always used; a seeded one makes a stroll repeat exactly.
var rng: RandomNumberGenerator = null
var target: int = 0
var paused: bool = false
var pause_left: float = 0.0
## Set by step(): did the figure move this tick, and which way.
var moving: bool = false
var heading: Vector2 = Vector2.ZERO
## While `holding`, the figure walks on to point `hold_at` and stays there (an NPC with business holds its mark).
var hold_at: int = -1
var holding: bool = false


func is_held() -> bool:
	return holding and paused and target == hold_at


## The position after `delta` seconds, from `pos`.
func step(pos: Vector2, delta: float) -> Vector2:
	moving = false
	if points.size() < 2:
		return pos
	if paused:
		if is_held():
			return pos
		pause_left -= delta
		if pause_left <= 0.0:
			paused = false
			target = (target + 1) % points.size()
		return pos
	var to: Vector2 = points[target] - pos
	if to.length() < ARRIVE_PX:
		if _rests_here():
			paused = true
			pause_left = _roll()
		else:
			target = (target + 1) % points.size()
		return pos
	heading = to.normalized()
	moving = true
	return pos + heading * speed * delta


func _rests_here() -> bool:
	if holding:
		return target == hold_at
	return rests.is_empty() or (target < rests.size() and bool(rests[target]))


func _roll() -> float:
	return rng.randf_range(pause_min, pause_max) if rng != null else randf_range(pause_min, pause_max)
