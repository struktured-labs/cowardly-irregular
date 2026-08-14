extends Node
## Shared battle-feel primitives (autoload). Consolidates shake/flash/hitstop/knockback so juice stops accreting into BattleScene; every effect here degrades by presentation_tier() and NONE of it touches Engine.time_scale (watchdog + double-scaling history — all stops are visual speed_scale freezes).

enum Tier { FULL, REDUCED, MINIMAL, OFF }

const FLASH_SHADER := preload("res://src/shaders/battle_sprite_flash.gdshader")
const BURST_POOL_SIZE := 3

## In-scene nodes registered by BattleScene for the current battle; null outside battle
var camera_rig: BattleCameraRig = null
var burst_host: Node = null

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


func add_trauma(amount: float, dir: Vector2 = Vector2.ZERO, sustain: float = 0.0) -> void:
	if camera_rig:
		camera_rig.add_trauma(amount, dir, sustain)


func punch_zoom(pivot: Vector2, strength: float = 0.03, duration: float = 0.14) -> void:
	if camera_rig:
		camera_rig.punch_zoom(pivot, strength, duration)


## Visual-only hitstop: freezes AnimatedSprite2D playback, never Engine.time_scale
func hitstop(sprites: Array, duration: float = 0.07) -> void:
	var frozen: Array = []
	for s in sprites:
		if s is AnimatedSprite2D and is_instance_valid(s) and s.speed_scale != 0.0:
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
	if not is_instance_valid(sprite):
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
	for e in _burst_pool:
		if is_instance_valid(e):
			e.queue_free()
	_burst_pool.clear()
