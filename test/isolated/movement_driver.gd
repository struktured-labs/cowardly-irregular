extends Node

## Test helper: drives a CharacterBody2D from a REAL _physics_process callback.
## move_and_slide() called from an `await physics_frame` continuation is not
## reliably inside the physics context — under host load it integrates with
## the variable IDLE delta instead of the fixed physics delta, which made
## every distance-parity assert scatter (the 2026-07 deploy-gate flake saga).

var target: CharacterBody2D = null
var vel: Vector2 = Vector2.ZERO
var steps_remaining: int = 0


func _physics_process(_delta: float) -> void:
	if steps_remaining <= 0 or target == null or not is_instance_valid(target):
		return
	target.velocity = vel
	target.move_and_slide()
	steps_remaining -= 1


func drive(p_target: CharacterBody2D, p_vel: Vector2, steps: int) -> void:
	target = p_target
	vel = p_vel
	steps_remaining = steps


func done() -> bool:
	return steps_remaining <= 0
