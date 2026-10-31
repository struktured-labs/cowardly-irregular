extends GutTest

## Issue #399 prototype guard: FractalFX's recursion must really be self-similar and bounded, every
## authored phase must name a kind the runner has, and the physical layer must leave the actor
## sprites exactly as it found them (artist frames are read, never edited). Sequences run at engine
## speed 4 so the arms wait well under a second of real time.

const FX := preload("res://src/battle/FractalFX.gd")
const FX_SRC := "res://src/battle/FractalFX.gd"

var _saved_scale := 1.0
var _layer: Node2D


func before_each() -> void:
	_saved_scale = Engine.time_scale
	Engine.time_scale = 4.0
	_layer = Node2D.new()
	add_child_autofree(_layer)


func after_each() -> void:
	Engine.time_scale = _saved_scale


func _settle(battle_seconds: float) -> void:
	await get_tree().create_timer(battle_seconds + 0.1).timeout


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
	await _settle(total)
	assert_eq(fx.spawned, 39, "depth 2 of a 3-burst is 3 + 9 + 27 flames")


func test_depth_is_bounded_by_the_flame_cap() -> void:
	var fx = FX.new(_layer, 7)
	var seq := {"phases": [{"kind": "emit", "count": 8, "arc": 360, "radius": 20, "life": 0.12,
		"depth": 6, "child_at": 0.5, "bloom": false}]}
	var total: float = fx.play(seq, Vector2.ZERO, Vector2.ZERO)
	await _settle(total)
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
	await _settle(total + 0.4)
	var after := [caster.position, caster.material, caster.speed_scale, caster.sprite_frames,
		target.position, target.material, target.speed_scale, target.scale]
	for i in before.size():
		assert_eq(after[i], before[i], "actor field %d must be restored once the strike ends" % i)
	assert_eq(caster.sprite_frames.get_frame_count("default"), 4, "the caster's own frames are untouched")


func test_a_dropped_instance_still_plays_its_later_phases() -> void:
	## Callers drop the FractalFX right after play(); delayed phases are bound to it. Flames live
	## 0.3-0.9 battle s; checked at 0.15 and 0.6, each far from a frame boundary at speed 4.
	var seq := {"phases": [{"at": 0.3, "kind": "emit", "count": 4, "radius": 10, "life": 0.6, "bloom": false}]}
	FX.new(_layer, 7).play(seq, Vector2.ZERO, Vector2.ZERO)
	await get_tree().create_timer(0.15).timeout
	assert_eq(_layer.get_child_count(), 0, "CONTROL: nothing yet before the phase's start")
	await get_tree().create_timer(0.45).timeout
	assert_eq(_layer.get_child_count(), 4, "the 0.3 s phase must still fire after the caller let go")


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
