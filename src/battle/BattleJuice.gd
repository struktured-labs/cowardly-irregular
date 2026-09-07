extends Node
## Shared battle-feel primitives (autoload). Consolidates shake/flash/hitstop/knockback so juice stops accreting into BattleScene; every effect here degrades by presentation_tier() and NONE of it touches Engine.time_scale (watchdog + double-scaling history — all stops are visual speed_scale freezes).

enum Tier { FULL, REDUCED, MINIMAL, OFF }

const FLASH_SHADER := preload("res://src/shaders/battle_sprite_flash.gdshader")
const BURST_POOL_SIZE := 3

## In-scene nodes registered by BattleScene for the current battle; null outside battle
var camera_rig: BattleCameraRig = null
var burst_host: Node = null
var env_background: Node = null

## Per-feature bells-and-whistles registry (struktured: "ridiculous menu of toggles") — unknown names default TRUE so new juice works before the menu knows it; accessibility masters (reduce_flashes/screen_shake_enabled) rank above flags
var flags: Dictionary = {}


func flag(feature: String) -> bool:
	if GameState and "battle_fx_flags" in GameState and GameState.battle_fx_flags.has(feature):
		return bool(GameState.battle_fx_flags[feature])
	return bool(flags.get(feature, true))

var _burst_pool: Array = []


## Boundaries deliberately equal the three legacy gate constants (Full Render 0.55, round banner 1.0, bubbles 4.0) so migrating old gate lines is behavior-identical.
static func presentation_tier(time_scale: float = Engine.time_scale, turbo: bool = false, autogrind: bool = false) -> Tier:
	if turbo or autogrind or time_scale >= 4.0:
		return Tier.OFF
	if time_scale <= 0.55:
		return Tier.FULL
	if time_scale <= 1.0:
		return Tier.REDUCED
	return Tier.MINIMAL


## Tier for the CURRENT battle, read off the registered context so every consumer agrees; outside battle burst_host is null and this equals presentation_tier() with both modes false.
func battle_tier() -> Tier:
	var turbo := false
	var autogrind := false
	if burst_host and is_instance_valid(burst_host):
		if "turbo_mode" in burst_host:
			turbo = bool(burst_host.turbo_mode)
		if "autogrind_console_mode" in burst_host:
			autogrind = bool(burst_host.autogrind_console_mode)
	return presentation_tier(Engine.time_scale, turbo, autogrind)


func add_trauma(amount: float, dir: Vector2 = Vector2.ZERO, sustain: float = 0.0) -> void:
	if camera_rig:
		camera_rig.add_trauma(amount, dir, sustain)
	# Heavy hits thump the arena itself (bass-thump pulse; struktured "try it" 2026-08-14)
	if amount >= 0.3 and env_background and is_instance_valid(env_background) and flag("env_pulse") and battle_tier() != Tier.OFF:
		env_background.pulse(amount)


func punch_zoom(pivot: Vector2, strength: float = 0.03, duration: float = 0.14) -> void:
	if camera_rig and flag("camera_zoom"):
		camera_rig.punch_zoom(pivot, strength, duration)


## Visual-only hitstop: freezes AnimatedSprite2D playback, never Engine.time_scale
func hitstop(sprites: Array, duration: float = 0.07) -> void:
	var frozen: Array = []
	for s in sprites:
		if is_instance_valid(s) and s is AnimatedSprite2D and s.speed_scale != 0.0:
			s.speed_scale = 0.0
			frozen.append(s)
	if frozen.is_empty():
		return
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		for s in frozen:
			if is_instance_valid(s):
				s.speed_scale = 1.0)


func flash_sprite(sprite: Node2D, color: Color = Color.WHITE, hold: float = 0.0, fade: float = 0.12) -> void:
	if not is_instance_valid(sprite):
		return
	var mat := _flash_material_of(sprite)
	if mat:
		mat.set_shader_parameter("flash_color", color)
		mat.set_shader_parameter("flash_amount", 1.0)
		var t := create_tween()
		if hold > 0.0:
			t.tween_interval(hold)
		t.tween_method(func(v: float) -> void:
			if is_instance_valid(sprite) and sprite.material is ShaderMaterial:
				sprite.material.set_shader_parameter("flash_amount", v), 1.0, 0.0, fade)
	else:
		# Fallback for sprites without the flash material: legacy HDR-modulate flash
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0) if color.is_equal_approx(Color.WHITE) else color
		var t := create_tween()
		if hold > 0.0:
			t.tween_interval(hold)
		t.tween_property(sprite, "modulate", Color.WHITE, fade)


func knockback(sprite: Node2D, dir: float, mag_x: float = 6.0, pop_y: float = 0.0) -> void:
	if not is_instance_valid(sprite):
		return
	var home: Vector2 = sprite.get_meta("home_position", sprite.position)
	var t := create_tween()
	t.tween_property(sprite, "position:x", home.x + dir * mag_x, 0.05)
	if pop_y != 0.0:
		t.parallel().tween_property(sprite, "position:y", home.y - pop_y, 0.05)
	t.tween_property(sprite, "position", home, 0.15).set_ease(Tween.EASE_OUT)


func squash(sprite: Node2D, x: float = 1.12, y: float = 0.88, snap: float = 0.03, settle: float = 0.10) -> void:
	if not is_instance_valid(sprite) or not flag("squash_stretch"):
		return
	# Multiply the stored base scale, never assign absolutes — sprite base scales are heterogeneous
	var base: Vector2 = sprite.get_meta("base_scale", sprite.scale)
	var t := create_tween()
	t.tween_property(sprite, "scale", Vector2(base.x * x, base.y * y), snap)
	t.tween_property(sprite, "scale", base, settle).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func spawn_burst(pos: Vector2, dir: Vector2, count: int, color: Color, speed: float = 250.0) -> void:
	if burst_host == null or count <= 0:
		return
	var emitter := _next_burst_emitter()
	if emitter == null:
		return
	emitter.global_position = pos
	emitter.amount = count
	emitter.direction = dir if dir != Vector2.ZERO else Vector2(0, -1)
	emitter.initial_velocity_min = speed * 0.7
	emitter.initial_velocity_max = speed * 1.3
	emitter.modulate = color
	emitter.restart()


## Ghost/afterimage of a sprite's current frame — fades and frees itself (promoted from BattleScene for steal/lunge reuse)
func spawn_ghost(src: AnimatedSprite2D, alpha: float = 0.45, fade: float = 0.18) -> void:
	if not is_instance_valid(src) or src.sprite_frames == null or not src.sprite_frames.has_animation(src.animation):
		return
	var tex := src.sprite_frames.get_frame_texture(src.animation, src.frame)
	if tex == null or src.get_parent() == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.global_position = src.global_position
	ghost.scale = src.scale
	ghost.flip_h = src.flip_h
	ghost.z_index = src.z_index - 1
	ghost.modulate = Color(1, 1, 1, alpha)
	src.get_parent().add_child(ghost)
	var gt := create_tween()
	gt.tween_property(ghost, "modulate:a", 0.0, fade)
	gt.tween_callback(ghost.queue_free)


static func ensure_flash_material(sprite: CanvasItem) -> ShaderMaterial:
	if sprite.material is ShaderMaterial and (sprite.material as ShaderMaterial).shader == FLASH_SHADER:
		return sprite.material
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	sprite.material = mat
	return mat


func _flash_material_of(sprite: Node2D) -> ShaderMaterial:
	if sprite is CanvasItem and sprite.material is ShaderMaterial and (sprite.material as ShaderMaterial).shader == FLASH_SHADER:
		return sprite.material
	return null


func _next_burst_emitter() -> CPUParticles2D:
	for e in _burst_pool:
		if is_instance_valid(e) and not e.emitting:
			return e
	if _burst_pool.size() >= BURST_POOL_SIZE:
		var first = _burst_pool[0]
		return first if is_instance_valid(first) else null
	var emitter := _make_burst_emitter()
	burst_host.add_child(emitter)
	_burst_pool.append(emitter)
	return emitter


func _make_burst_emitter() -> CPUParticles2D:
	# CPU particles by design: one code path, no WebGL2 first-emission compile hitch, trivial at <=20-particle bursts
	var emitter := CPUParticles2D.new()
	emitter.one_shot = true
	emitter.emitting = false
	emitter.lifetime = 0.25
	emitter.local_coords = false
	emitter.spread = 30.0
	emitter.gravity = Vector2(0, 400)
	emitter.scale_amount_min = 2.0
	emitter.scale_amount_max = 4.0
	emitter.z_index = 40
	return emitter


func clear_battle_context() -> void:
	camera_rig = null
	burst_host = null
	env_background = null
	for e in _burst_pool:
		if is_instance_valid(e):
			e.queue_free()
	_burst_pool.clear()
