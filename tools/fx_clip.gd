extends SceneTree

## Plays one data/vfx_sequences.json sequence on a small battle stage, for --write-movie capture.
## Run through tools/fx_clip.sh (it owns the sandbox, xvfb, the pad jail and the encode).
## Args: --seq=<id> --speed=<engine time_scale, default 0.375 = the 1.5x default> --seed=<int>
## The sprites are the artist's own strips, loaded read-only; FX are layered over them.

const FX := preload("res://src/battle/FractalFX.gd")
const VIEW := Vector2(1280, 720)

var _cam: Camera2D
var _shake_tw: Tween


func _init() -> void:
	var seq_id := "fire_fractal"
	var speed := 0.375
	var seed := 399
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seq="):
			seq_id = a.get_slice("=", 1)
		elif a.begins_with("--speed="):
			speed = float(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed = int(a.get_slice("=", 1))
	await process_frame
	await process_frame
	var seq: Dictionary = FX.load_sequence(seq_id)
	if seq.is_empty():
		push_error("[FXCLIP] no sequence '%s' in %s" % [seq_id, FX.SEQUENCES_PATH])
		quit(2)
		return
	var physical := seq_id.begins_with("strike")
	var stage := Node2D.new()
	root.add_child(stage)
	_backdrop(stage)
	_cam = Camera2D.new()
	_cam.position = VIEW * 0.5
	stage.add_child(_cam)
	_cam.make_current()

	var job := "fighter" if physical else "mage"
	var anim := "attack" if physical else "cast"
	var caster := _strip("res://assets/sprites/jobs/%s/%s.png" % [job, anim], 256, 8.0)
	var idle := _strip("res://assets/sprites/jobs/%s/idle.png" % job, 256, 8.0)
	var target := _strip("res://assets/sprites/monsters/goblin.png", 128, 8.0, 0, 2)
	if caster == null or target == null or idle == null:
		push_error("[FXCLIP] a sprite strip failed to load")
		quit(3)
		return
	## Party on the right facing left, enemies on the left: the game's own battle layout.
	caster.position = Vector2(930, 430)
	caster.flip_h = true
	target.position = Vector2(360, 445)
	target.scale = Vector2(2.0, 2.0)
	stage.add_child(target)
	stage.add_child(caster)
	caster.sprite_frames.add_animation("idle")
	for i in idle.sprite_frames.get_frame_count("default"):
		caster.sprite_frames.add_frame("idle", idle.sprite_frames.get_frame_texture("default", i))
	caster.play("idle")
	target.play("default")

	var layer := Node2D.new()
	layer.z_index = 50
	stage.add_child(layer)
	_caption(stage, "%s  ·  %s  ·  battle speed %sx (engine %s)" % [
		seq_id, str(seq.get("label", "")), String.num(speed * 4.0), String.num(speed)])

	await _wait_real(0.35)
	Engine.time_scale = speed
	var fx = FX.new(layer, seed)
	fx.actors = {"caster": caster, "target": target}
	fx.on_shake = _shake
	caster.play("default")
	caster.animation_finished.connect(func() -> void: caster.play("idle"), CONNECT_ONE_SHOT)
	var hand := caster.position + Vector2(-70, -20)
	var total: float = fx.play(seq, Vector2(caster.position.x - 40, caster.position.y) if physical else hand,
		target.position + Vector2(0, -10))
	print("[FXCLIP] seq=%s speed=%s total_battle_s=%.2f real_s=%.2f" % [seq_id, str(speed), total, total / speed])
	await create_timer(total).timeout
	await _wait_real(0.6)
	print("[FXCLIP] done seq=%s flames=%d" % [seq_id, fx.spawned])
	Engine.time_scale = 1.0
	quit(0)


func _wait_real(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _strip(path: String, frame: int, fps: float, first: int = 0, last: int = -1) -> AnimatedSprite2D:
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", fps)
	frames.set_animation_loop("default", false)
	var n := int(tex.get_width() / frame)
	if last < 0:
		last = n - 1
	for i in range(first, last + 1):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * frame, 0, frame, frame)
		frames.add_frame("default", at)
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s


func _backdrop(stage: Node2D) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.63, 1.0])
	g.colors = PackedColorArray([Color(0.05, 0.04, 0.12), Color(0.12, 0.09, 0.2),
		Color(0.16, 0.12, 0.1), Color(0.07, 0.05, 0.05)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	var bg := Sprite2D.new()
	bg.texture = gt
	bg.centered = false
	bg.position = Vector2(-64, -64)
	bg.scale = Vector2((VIEW.x + 128) / 8.0, (VIEW.y + 128) / 256.0)
	stage.add_child(bg)


func _caption(stage: Node2D, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(16, VIEW.y - 34)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9, 0.85))
	stage.add_child(l)


func _shake(intensity: float, dur: float) -> void:
	if _shake_tw != null and _shake_tw.is_valid():
		_shake_tw.kill()
	_shake_tw = _cam.create_tween()
	var steps := maxi(int(dur / 0.03), 2)
	for i in steps:
		var fall := 1.0 - float(i) / float(steps)
		_shake_tw.tween_property(_cam, "offset",
			Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensity * fall, dur / steps)
	_shake_tw.tween_property(_cam, "offset", Vector2.ZERO, 0.03)
