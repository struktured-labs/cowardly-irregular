extends GutTest

## face_actor's `toward` took only an actor id, while camera_focus takes an id OR an [x,y] mark —
## so "turn to the doorway" meant hand-computing a compass direction that breaks when the mark
## moves. `toward` now resolves through the same helper (id or point) and WARNS on an
## unresolvable target instead of silently facing nowhere. Found on the way: face_toward
## subtracted the actor's LOCAL position from a GLOBAL target (authored marks and other puppets'
## global_position both are), so on any offset stage the puppet faced the wrong way.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node


func before_each() -> void:
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func after_each() -> void:
	if _d and is_instance_valid(_d):
		_d._active = false


func _puppet(id: String, parent: Node, local_pos: Vector2 = Vector2.ZERO) -> CutsceneActor:
	var a := CutsceneActor.build(id, {"kind": "npc", "archetype": "old_man"})
	parent.add_child(a)
	a.position = local_pos
	_d._actors[id] = a
	return a


func test_toward_a_point_faces_the_point() -> void:
	var a := _puppet("m", self)
	_d._step_face_actor({"type": "face_actor", "id": "m", "toward": [100, 0]})
	assert_eq(a._facing, CutsceneActor.Dir.RIGHT, "a mark to the right → RIGHT")
	_d._step_face_actor({"type": "face_actor", "id": "m", "toward": [0, -100]})
	assert_eq(a._facing, CutsceneActor.Dir.UP, "a mark above → UP")
	a.free()


func test_toward_an_actor_still_faces_that_actor() -> void:
	# ARM+: the point path must not have replaced the id path.
	var a := _puppet("m", self)
	var b := _puppet("t", self, Vector2(-80, 0))
	_d._step_face_actor({"type": "face_actor", "id": "m", "toward": "t"})
	assert_eq(a._facing, CutsceneActor.Dir.LEFT, "the other puppet is to the left → LEFT")
	a.free()
	b.free()


func test_toward_an_unknown_target_leaves_the_facing_alone() -> void:
	var a := _puppet("m", self)
	a.set_facing_name("up")
	_d._step_face_actor({"type": "face_actor", "id": "m", "toward": "nobody_here"})
	assert_eq(a._facing, CutsceneActor.Dir.UP, "an unresolvable target warns and changes nothing")
	a.free()


func test_dir_still_works_without_toward() -> void:
	var a := _puppet("m", self)
	_d._step_face_actor({"type": "face_actor", "id": "m", "dir": "left"})
	assert_eq(a._facing, CutsceneActor.Dir.LEFT)
	a.free()


func test_facing_is_computed_in_global_space_on_an_offset_stage() -> void:
	# Stage at x=1000; puppet at local (0,0) = global (1000,0); mark at global x=900 is to its LEFT.
	# The old local-space subtraction (900 - 0 > 0) faced RIGHT.
	var stage := Node2D.new()
	stage.position = Vector2(1000, 0)
	add_child_autofree(stage)
	var a := _puppet("m", stage)
	_d._step_face_actor({"type": "face_actor", "id": "m", "toward": [900, 0]})
	assert_eq(a._facing, CutsceneActor.Dir.LEFT, "global target minus global position → LEFT")
	var b := _puppet("t", stage, Vector2(50, 0))  # global (1050, 0): to the right of m
	_d._step_face_actor({"type": "face_actor", "id": "m", "toward": "t"})
	assert_eq(a._facing, CutsceneActor.Dir.RIGHT, "another puppet resolves through its global position too")
