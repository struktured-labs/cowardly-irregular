extends GutTest

## Issue #399 prototype guard: FractalFX's recursion must really be self-similar and bounded, every
## authored phase must name a kind the runner has, and the physical layer must leave the actor
## sprites exactly as it found them (artist frames are read, never edited). Arms wait for a
## CONDITION under a real-time bound, never for a timer: a slow frame mid-suite can jump a whole
## recursion level (measured: 12 of 39 at engine speed 4 with a fixed wait).

const FX := preload("res://src/battle/FractalFX.gd")
const FX_SRC := "res://src/battle/FractalFX.gd"

var _saved_scale := 1.0
var _layer: Node2D


func before_each() -> void:
	_saved_scale = Engine.time_scale
	Engine.time_scale = 1.0
	_layer = Node2D.new()
	add_child_autofree(_layer)


func after_each() -> void:
	Engine.time_scale = _saved_scale


## True once `cond` holds; false if `bound_s` real seconds pass first.
func _until(cond: Callable, bound_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(bound_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _quiet() -> bool:
	return _layer.get_child_count() == 0


## Derived from the runner's own match arms, so a new kind is covered the day it is written.
func _known_kinds() -> Array:
	var src := FileAccess.get_file_as_string(FX_SRC)
	var body := src.substr(src.find("func _run("))
	body = body.substr(0, body.find("\nfunc ", 1))
	var kinds: Array = []
	var re := RegEx.new()
	re.compile("(?m)^\\t\\t\"([a-z_]+)\":")
	for m in re.search_all(body):
		kinds.append(m.get_string(1))
	return kinds


func test_every_authored_phase_names_a_kind_the_runner_has() -> void:
	var kinds := _known_kinds()
	assert_gt(kinds.size(), 8, "CONTROL: the derivation must find the runner's arms")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(FX.SEQUENCES_PATH))
	assert_true(raw is Dictionary, "vfx_sequences.json must parse")
	var seqs: Dictionary = raw.get("sequences", {})
	assert_gt(seqs.size(), 0, "there must be sequences to judge")
	for id in seqs:
		var phases: Array = seqs[id].get("phases", [])
		assert_gt(phases.size(), 0, "%s has no phases" % id)
		for ph in phases:
			assert_true(str(ph.get("kind", "")) in kinds,
				"%s uses kind '%s', which FractalFX._run has no arm for" % [id, ph.get("kind", "")])


func test_a_burst_recurses_into_copies_of_itself() -> void:
	## count 3, depth 2, no blooms: exactly 3 + 9 + 27 flames, the self-similar count.
	var fx = FX.new(_layer, 7)
	var seq := {"phases": [{"kind": "emit", "count": 3, "arc": 360, "radius": 30, "life": 0.2,
		"depth": 2, "child_at": 0.5, "bloom": false}]}
	var total: float = fx.play(seq, Vector2.ZERO, Vector2(100, 100))
	assert_gt(total, 0.2, "the duration must include the recursion, not just the first life")
	assert_true(await _until(func() -> bool: return fx.spawned >= 39 and _quiet(), 5.0),
		"the burst must recurse and finish within 5 real seconds (spawned %d)" % fx.spawned)
	assert_eq(fx.spawned, 39, "depth 2 of a 3-burst is 3 + 9 + 27 flames")


func test_depth_is_bounded_by_the_flame_cap() -> void:
	var fx = FX.new(_layer, 7)
	var seq := {"phases": [{"kind": "emit", "count": 8, "arc": 360, "radius": 20, "life": 0.12,
		"depth": 6, "child_at": 0.5, "bloom": false}]}
	fx.play(seq, Vector2.ZERO, Vector2.ZERO)
	assert_true(await _until(func() -> bool: return fx.spawned > 0 and _quiet(), 8.0), "the capped burst must finish")
	assert_gt(fx.spawned, 500, "CONTROL: an uncapped depth-6 8-burst would want ~300k flames")
	assert_lte(fx.spawned, FX.FLAME_CAP, "one cast must never allocate past FLAME_CAP")


func test_the_physical_layer_leaves_the_actors_as_it_found_them() -> void:
	var caster := _actor(Vector2(900, 400))
	var target := _actor(Vector2(300, 400))
	var before := [caster.position, caster.material, caster.speed_scale, caster.sprite_frames,
		target.position, target.material, target.speed_scale, target.scale]
	var fx = FX.new(_layer, 7)
	fx.actors = {"caster": caster, "target": target}
	var seq: Dictionary = FX.load_sequence("strike_impact")
	assert_false(seq.is_empty(), "strike_impact must be authored")
	var total: float = fx.play(seq, caster.position, target.position)
	var t0 := Time.get_ticks_msec()
	## Only the two actors left, and the whole timeline elapsed: every tween has had its end frame.
	assert_true(await _until(func() -> bool:
		return _layer.get_child_count() == 2 and Time.get_ticks_msec() - t0 > int((total + 0.3) * 1000.0), 6.0),
		"the strike must finish within 6 real seconds")
	var after := [caster.position, caster.material, caster.speed_scale, caster.sprite_frames,
		target.position, target.material, target.speed_scale, target.scale]
	for i in before.size():
		assert_eq(after[i], before[i], "actor field %d must be restored once the strike ends" % i)
	assert_eq(caster.sprite_frames.get_frame_count("default"), 4, "the caster's own frames are untouched")


func test_a_dropped_instance_still_plays_its_later_phases() -> void:
	## Callers drop the FractalFX right after play(); delayed phases are bound to it.
	var seq := {"phases": [{"at": 0.3, "kind": "emit", "count": 4, "radius": 10, "life": 0.6, "bloom": false}]}
	FX.new(_layer, 7).play(seq, Vector2.ZERO, Vector2.ZERO)
	assert_eq(_layer.get_child_count(), 0, "CONTROL: a delayed phase spawns nothing at play()")
	assert_true(await _until(func() -> bool: return _layer.get_child_count() == 4, 3.0),
		"the 0.3 s phase must still fire after the caller let go")


func _actor(pos: Vector2) -> AnimatedSprite2D:
	var frames := SpriteFrames.new()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	for i in 4:
		frames.add_frame("default", tex)
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.position = pos
	_layer.add_child(s)
	return s
