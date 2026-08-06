extends GutTest

## Regression: struktured's live session, 2026-07-31 — 52 of the 62 engine errors in one
## play session were
##
##   ERROR: Can't change this state while flushing queries. Use call_deferred() or
##   set_deferred() to change monitoring state instead.
##      at: area_set_shape_disabled (godot_physics_server_2d.cpp:355)
##
## RoamingMonster.deactivate() set `_collision.disabled = true` directly, and it runs INSIDE
## a body_entered dispatch:
##
##   RoamingMonster._on_body_entered -> touched -> MonsterSpawner._on_monster_touched
##     -> <Overworld>._on_roaming_monster_touched -> _on_battle_triggered
##     -> OverworldScene pauses -> monster_spawner.set_enabled(false) -> _despawn_all()
##     -> m.deactivate()            <- shape state changed mid-flush
##
## ⚠️ The synchronous behaviour of deactivate() is LOAD-BEARING and documented: it exists so
## a body_entered queued in the same physics frame cannot leak into a battle after the player
## is safe. That guard is `_active`, which is checked FIRST in _on_body_entered and stays
## synchronous — only the shape disable is deferred. This file pins both halves, because
## deferring the wrong one would reintroduce the leak deactivate() was written to prevent.


func _monster() -> Node2D:
	var RoamingMonsterScript = load("res://src/exploration/RoamingMonster.gd")
	var m = RoamingMonsterScript.new()
	add_child_autofree(m)
	return m


class _BodyStub extends Node2D:
	func set_can_move(_v: bool) -> void:
		pass


func test_deactivate_stops_touches_synchronously() -> void:
	# The load-bearing half: after deactivate(), a body_entered in the SAME frame must not
	# emit `touched`, even though the collision shape is still enabled until end of frame.
	var m := _monster()
	var fired: Array = []
	m.touched.connect(func(_id, _types): fired.append(1))
	var body := _BodyStub.new()
	add_child_autofree(body)

	m.deactivate()
	assert_false(m._active, "deactivate must clear _active synchronously — this is the leak guard")
	m._on_body_entered(body)
	assert_eq(fired.size(), 0,
		"a touch after deactivate() must not reach battle — the guard is _active, not the collision shape")


func test_shape_disable_is_deferred_not_immediate() -> void:
	var m := _monster()
	assert_not_null(m._collision, "precondition: collision shape built in _ready")
	assert_false(m._collision.disabled, "precondition: shape starts enabled")

	m.deactivate()
	# Production frees the node immediately after deactivate() (both callers in
	# MonsterSpawner do). Left processing, _tick_respawn would fire and _respawn() would
	# re-enable the shape, which is not a path deactivate() ever reaches in the game.
	m.set_process(false)
	assert_false(m._collision.disabled,
		"shape must NOT be disabled in the same frame — a direct assignment here runs mid-flush and errors")

	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(m._collision.disabled,
		"the deferred disable must still land — deferring it away entirely would leave the monster collidable")


func test_control_the_shape_can_be_observed_changing() -> void:
	# CONTROL: both assertions above read _collision.disabled. If that property were not
	# actually settable on this node, one would pass vacuously and the other could not fail.
	var m := _monster()
	m._collision.disabled = true
	assert_true(m._collision.disabled, "CONTROL: the shape's disabled flag must be readable and settable")
	m._collision.disabled = false
	assert_false(m._collision.disabled, "CONTROL: and clearable")
