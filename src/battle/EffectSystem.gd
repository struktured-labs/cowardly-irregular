extends Node
class_name EffectSystemClass

## EffectSystem - Handles visual spell effects in battle
## 12-bit style particle effects for abilities

## Effect types
enum EffectType {
	FIRE,
	ICE,
	LIGHTNING,
	HOLY,
	DARK,
	HEAL,
	PHYSICAL,
	BUFF,
	DEBUFF,
	POISON,
	MP_RESTORE  # Blue sparkle effect for ether/mana restoration
}

## Active effects container
var _effects_container: Node2D = null

## Battle background reference for environmental tint reactions
## Set by BattleScene after creating its background
var battle_background: Node = null

## Screen shake state — prevents overlapping tweens from drifting the camera
var _shake_tween: Tween = null
var _original_camera_offset: Vector2 = Vector2.ZERO
var _is_shaking: bool = false

## Texture cache for particle sprites (avoids regenerating identical images)
## Key: texture type string, Value: ImageTexture
static var _texture_cache: Dictionary = {}


func _ready() -> void:
	# Create container for effect nodes
	_effects_container = Node2D.new()
	_effects_container.name = "EffectsContainer"
	_effects_container.z_index = 50  # Render on top of sprites
	add_child(_effects_container)


func _exit_tree() -> void:
	"""Cleanup effects container when node is freed"""
	if _effects_container and is_instance_valid(_effects_container):
		# Free all child effects
		for child in _effects_container.get_children():
			if is_instance_valid(child):
				child.queue_free()
		_effects_container.queue_free()
	_effects_container = null


## Get a cached texture or generate and cache it
static func _get_cached_texture(cache_key: String, generator: Callable) -> ImageTexture:
	"""Return cached ImageTexture if available, otherwise generate, cache, and return."""
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var texture = generator.call()
	_texture_cache[cache_key] = texture
	return texture


## Clear the texture cache
static func clear_texture_cache() -> void:
	_texture_cache.clear()


## Power scaling constants
const POWER_MIN: float = 0.5  # Minimum effect scale for weak spells
const POWER_MAX: float = 2.0  # Maximum effect scale for powerful spells


func spawn_effect(effect_type: EffectType, position: Vector2, on_complete: Callable = Callable(), power: float = 1.0) -> void:
	"""Spawn a visual effect at the given position with optional power scaling"""
	var effect = _create_effect(effect_type)
	effect.position = position
	_effects_container.add_child(effect)

	# Clamp power to reasonable range
	power = clamp(power, POWER_MIN, POWER_MAX)

	# Play sound for the effect with power-based volume
	_play_effect_sound(effect_type, power)

	# Start the effect animation
	_animate_effect(effect, effect_type, on_complete, power)


func spawn_effect_on_target(effect_type: EffectType, target_sprite: Node2D, on_complete: Callable = Callable(), power: float = 1.0) -> void:
	"""Spawn effect on a target sprite with power scaling"""
	if not is_instance_valid(target_sprite):
		if on_complete.is_valid():
			on_complete.call()
		return
	spawn_effect(effect_type, target_sprite.global_position, on_complete, power)


func spawn_ability_effect(ability_id: String, target_position: Vector2, on_complete: Callable = Callable(), power: float = 1.0) -> void:
	"""Spawn effect based on ability ID with power scaling"""
	var effect_type = _get_effect_type_for_ability(ability_id)
	# Auto-scale power based on ability tier
	var auto_power = _get_ability_power_tier(ability_id)
	spawn_effect(effect_type, target_position, on_complete, auto_power if power == 1.0 else power)


func _get_ability_power_tier(ability_id: String) -> float:
	"""Get power tier based on ability name suffix (basic -> -a -> -aga)"""
	# Tier 3 spells (most powerful)
	if ability_id.ends_with("aga") or ability_id in ["holy", "flare", "ultima", "megalixir"]:
		return 1.8
	# Tier 2 spells
	if ability_id.ends_with("a") or ability_id in ["cura", "fira", "blizzara", "thundara", "hi_ether"]:
		return 1.3
	# Tier 1 spells (basic)
	return 1.0


func _get_effect_type_for_ability(ability_id: String) -> EffectType:
	"""Map ability ID to effect type"""
	# Fire abilities
	if ability_id in ["fire", "fira", "firaga", "flame_strike"]:
		return EffectType.FIRE

	# Ice abilities
	if ability_id in ["blizzard", "blizzara", "blizzaga", "ice_lance"]:
		return EffectType.ICE

	# Lightning abilities
	if ability_id in ["thunder", "thundara", "thundaga", "shock"]:
		return EffectType.LIGHTNING

	# Holy abilities
	if ability_id in ["holy", "divine_light", "smite"]:
		return EffectType.HOLY

	# Dark abilities
	if ability_id in ["dark", "drain", "darkness", "shadow_bolt", "life_drain"]:
		return EffectType.DARK

	# Heal abilities
	if ability_id in ["cure", "cura", "curaga", "heal", "regen"]:
		return EffectType.HEAL

	# MP restore abilities
	if ability_id in ["ether", "hi_ether", "mega_ether", "elixir", "megalixir"]:
		return EffectType.MP_RESTORE

	# Buff abilities
	if ability_id in ["protect", "shell", "haste", "brave", "faith"]:
		return EffectType.BUFF

	# Debuff abilities
	if ability_id in ["slow", "dispel", "break", "weaken"]:
		return EffectType.DEBUFF

	# Poison abilities
	if ability_id in ["poison", "bio", "venom"]:
		return EffectType.POISON

	# Default to physical
	return EffectType.PHYSICAL


func _play_effect_sound(effect_type: EffectType, power: float = 1.0) -> void:
	"""Play appropriate sound for effect with power-based volume and pitch"""
	var sound_key = ""
	match effect_type:
		EffectType.FIRE:
			sound_key = "ability_fire"
		EffectType.ICE:
			sound_key = "ability_ice"
		EffectType.LIGHTNING:
			sound_key = "ability_lightning"
		EffectType.HOLY:
			sound_key = "ability_holy"
		EffectType.DARK:
			sound_key = "ability_dark"
		EffectType.HEAL:
			sound_key = "ability_heal"
		EffectType.MP_RESTORE:
			sound_key = "ability_heal"  # Reuse heal sound for MP restore
		EffectType.BUFF:
			sound_key = "buff"
		EffectType.DEBUFF:
			sound_key = "debuff"
		EffectType.POISON:
			sound_key = "ability_dark"
		EffectType.PHYSICAL:
			sound_key = "attack_hit"

	if sound_key != "" and SoundManager:
		# Scale volume based on power (more powerful = slightly louder)
		var volume_db = lerp(-3.0, 3.0, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
		# Lower pitch for more powerful spells (sounds heavier/bigger)
		var pitch = lerp(1.1, 0.9, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
		SoundManager.play_battle_scaled(sound_key, volume_db, pitch)


func _create_effect(effect_type: EffectType) -> Node2D:
	"""Create effect container node"""
	var effect = Node2D.new()
	effect.name = "Effect_%s" % EffectType.keys()[effect_type]
	return effect


func _animate_effect(effect: Node2D, effect_type: EffectType, on_complete: Callable, power: float = 1.0) -> void:
	"""Animate the effect based on type with power scaling"""
	match effect_type:
		EffectType.FIRE:
			_animate_fire(effect, on_complete, power)
		EffectType.ICE:
			_animate_ice(effect, on_complete, power)
		EffectType.LIGHTNING:
			_animate_lightning(effect, on_complete, power)
		EffectType.HOLY:
			_animate_holy(effect, on_complete, power)
		EffectType.DARK:
			_animate_dark(effect, on_complete, power)
		EffectType.HEAL:
			_animate_heal(effect, on_complete, power)
		EffectType.MP_RESTORE:
			_animate_mp_restore(effect, on_complete, power)
		EffectType.BUFF:
			_animate_buff(effect, on_complete, power)
		EffectType.DEBUFF:
			_animate_debuff(effect, on_complete, power)
		EffectType.POISON:
			_animate_poison(effect, on_complete, power)
		EffectType.PHYSICAL:
			_animate_physical(effect, on_complete, power)


## Effect Animations

func _tint_battle_background(tint_color: Color, duration: float = 0.3) -> void:
	"""Briefly tint the battle background then restore it (environmental spell reaction)"""
	if not battle_background or not is_instance_valid(battle_background):
		return
	var tween = create_tween()
	# Snap to tint color then fade back to neutral over duration
	tween.tween_property(battle_background, "modulate", tint_color, duration * 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(battle_background, "modulate", Color.WHITE, duration * 0.85).set_trans(Tween.TRANS_SINE)


func _animate_fire(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Fire spell — FF6-style eruption: screen flash, explosion ring, flame columns, massive particles"""
	var power_t = clampf((power - POWER_MIN) / (POWER_MAX - POWER_MIN), 0.0, 1.0)

	# Environmental reaction: warm orange-red background tint
	_tint_battle_background(Color(1.3, 0.7, 0.5, 1.0), 0.4)

	# Screen-filling flash (fix: start invisible, add mouse_filter)
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.5, 0.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 50
	effect.add_child(flash)

	# Big screen shake
	var shake_intensity = lerp(6.0, 20.0, power_t)
	var shake_duration = lerp(0.3, 0.7, power_t)
	_trigger_screen_shake(shake_intensity, shake_duration)

	# Double explosion ring (inner fast, outer slow)
	var ring1 = _create_explosion_ring(Color(1.0, 0.5, 0.0))
	ring1.scale = Vector2.ZERO
	effect.add_child(ring1)
	var ring2 = _create_explosion_ring(Color(1.0, 0.3, 0.0, 0.6))
	ring2.scale = Vector2.ZERO
	effect.add_child(ring2)

	# Massive particle burst — 40-100 particles in two waves
	var particles: Array[Sprite2D] = []
	var particle_count = int(lerp(40, 100, power_t))
	var base_spread = lerp(25, 60, power_t)
	for i in range(particle_count):
		var particle = _create_fire_particle()
		var angle = randf() * TAU
		var dist = randf_range(0, base_spread)
		particle.position = Vector2(cos(angle) * dist, sin(angle) * dist)
		particle.scale = Vector2(power * 1.2, power * 1.2)
		effect.add_child(particle)
		particles.append(particle)

	var duration = lerp(0.8, 1.3, power_t)
	var tween = create_tween()
	tween.set_parallel(true)

	# Screen flash: bright burst then fade
	var flash_alpha = lerp(0.5, 0.9, power_t)
	tween.tween_property(flash, "color:a", flash_alpha, 0.04)
	tween.tween_property(flash, "color:a", 0.0, 0.2).set_delay(0.04)

	# Double ring expansion
	var ring_scale = lerp(3.0, 6.0, power_t)
	tween.tween_property(ring1, "scale", Vector2(ring_scale, ring_scale), 0.25)
	tween.tween_property(ring1, "modulate:a", 0.0, 0.2).set_delay(0.1)
	tween.tween_property(ring2, "scale", Vector2(ring_scale * 1.3, ring_scale * 1.3), 0.4).set_delay(0.08)
	tween.tween_property(ring2, "modulate:a", 0.0, 0.25).set_delay(0.2)

	# Particles: explosive outward burst + upward rise
	var rise_mult = lerp(1.0, 2.5, power_t)
	var spread_mult = lerp(1.0, 2.5, power_t)
	for i in range(particles.size()):
		var p = particles[i]
		var wave = 0.0 if i < particle_count / 2 else 0.12  # Second wave delayed
		var delay = randf() * 0.1 + wave
		var rise = randf_range(80, 180) * rise_mult
		var spread = randf_range(-60, 60) * spread_mult

		tween.tween_property(p, "position:y", p.position.y - rise, duration).set_delay(delay)
		tween.tween_property(p, "position:x", p.position.x + spread, duration).set_delay(delay)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.4).set_delay(delay + duration * 0.5)
		tween.tween_property(p, "scale", p.scale * Vector2(2.5, 3.0), duration).set_delay(delay)
		tween.tween_property(p, "rotation", randf_range(-PI, PI), duration).set_delay(delay)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_explosion_ring(color: Color) -> Sprite2D:
	"""Create an expanding ring effect"""
	var sprite = Sprite2D.new()
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center = size / 2
	for y in range(size):
		for x in range(size):
			var dist = sqrt(pow(x - center, 2) + pow(y - center, 2))
			if dist > 20 and dist < 28:
				var alpha = 1.0 - abs(dist - 24) / 4.0
				var c = color
				c.a = alpha * 0.8
				img.set_pixel(x, y, c)

	sprite.texture = ImageTexture.create_from_image(img)
	return sprite


func _trigger_screen_shake(intensity: float, duration: float) -> void:
	"""Trigger screen shake effect. Kills any running shake first to prevent camera drift."""
	var viewport = get_viewport()
	if not viewport:
		return

	var camera = viewport.get_camera_2d()
	if not camera:
		# Try to find any Camera2D in the tree
		var cameras = get_tree().get_nodes_in_group("camera")
		if cameras.size() > 0:
			camera = cameras[0]

	if camera:
		# Kill any in-progress shake and restore the camera before starting a new one
		if _shake_tween != null and _shake_tween.is_valid() and _shake_tween.is_running():
			_shake_tween.kill()
			camera.offset = _original_camera_offset

		# Only record the baseline offset when we are not already shaking
		if not _is_shaking:
			_original_camera_offset = camera.offset

		_is_shaking = true
		_shake_tween = create_tween()
		var steps = int(duration * 30)
		for i in range(steps):
			var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
			_shake_tween.tween_property(camera, "offset", _original_camera_offset + offset, duration / steps)
		_shake_tween.tween_property(camera, "offset", _original_camera_offset, 0.05)
		_shake_tween.tween_callback(func() -> void: _is_shaking = false)


func _create_fire_particle() -> Sprite2D:
	"""Create a single fire particle sprite (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("fire_particle", func():
		return _generate_fire_particle_texture()
	)
	sprite.modulate.a = 0.9
	return sprite


static func _generate_fire_particle_texture() -> ImageTexture:
	"""Generate the fire particle texture (called once, then cached)."""
	var size = 16
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var colors = [
		Color(1.0, 0.9, 0.2),  # Yellow core
		Color(1.0, 0.5, 0.0),  # Orange
		Color(0.9, 0.2, 0.0),  # Red
	]

	var center = size / 2
	for y in range(size):
		for x in range(size):
			var dist = sqrt(pow(x - center, 2) + pow(y - center + 2, 2))
			if dist < 6:
				var color_idx = int(dist / 2) % colors.size()
				var color = colors[color_idx]
				color.a = 1.0 - (dist / 6.0) * 0.5
				img.set_pixel(x, y, color)

	return ImageTexture.create_from_image(img)


func _animate_ice(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Ice spell — FF6-style: screen freeze flash, crystal ring formation, massive shatter burst"""
	var power_t = clampf((power - POWER_MIN) / (POWER_MAX - POWER_MIN), 0.0, 1.0)

	# Environmental reaction: cold blue desaturation
	_tint_battle_background(Color(0.65, 0.75, 1.0, 1.0), 0.4)

	# Screen flash — icy white-blue
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.7, 0.85, 1.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 50
	effect.add_child(flash)

	# Screen shake
	_trigger_screen_shake(lerp(4.0, 16.0, power_t), lerp(0.2, 0.5, power_t))

	# Crystal ring — 16-32 shards in concentric formation
	var particles: Array[Sprite2D] = []
	var shard_count = int(lerp(16, 40, power_t))
	var ring_radius = lerp(30, 60, power_t)

	# Inner ring (converge then shatter)
	for i in range(shard_count):
		var particle = _create_ice_particle()
		var angle = (float(i) / shard_count) * TAU
		particle.position = Vector2(cos(angle), sin(angle)) * ring_radius * 1.5
		particle.rotation = angle + PI / 2
		particle.scale = Vector2(power * 0.8, power * 1.2)  # Elongated shards
		effect.add_child(particle)
		particles.append(particle)

	# Outer scattered crystals for volume
	var scatter_count = int(lerp(12, 30, power_t))
	for i in range(scatter_count):
		var particle = _create_ice_particle()
		particle.position = Vector2(randf_range(-80, 80), randf_range(-80, 80)) * (1.0 + power_t)
		particle.rotation = randf() * TAU
		particle.scale = Vector2(power * 0.5, power * 0.5)
		particle.modulate.a = 0.0
		effect.add_child(particle)
		particles.append(particle)

	var duration = lerp(0.7, 1.2, power_t)
	var tween = create_tween()
	tween.set_parallel(true)

	# Icy screen flash
	tween.tween_property(flash, "color:a", lerp(0.3, 0.7, power_t), 0.05)
	tween.tween_property(flash, "color:a", 0.0, 0.25).set_delay(0.05)

	# Phase 1: Inner ring converges to center
	for i in range(shard_count):
		var p = particles[i]
		var delay = float(i) * 0.02
		var converged = p.position * 0.3
		tween.tween_property(p, "position", converged, duration * 0.35).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# Phase 2: Explosive shatter outward
	for i in range(shard_count):
		var p = particles[i]
		var shatter_angle = (float(i) / shard_count) * TAU + randf_range(-0.3, 0.3)
		var shatter_dist = randf_range(100, 200) * (1.0 + power_t)
		var shatter_pos = Vector2(cos(shatter_angle), sin(shatter_angle)) * shatter_dist
		var shatter_delay = duration * 0.4
		tween.tween_property(p, "position", shatter_pos, duration * 0.4).set_delay(shatter_delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.25).set_delay(shatter_delay + duration * 0.2)
		tween.tween_property(p, "rotation", p.rotation + randf_range(-PI, PI), duration * 0.4).set_delay(shatter_delay)

	# Outer scattered crystals fade in during convergence, shatter with the rest
	for i in range(shard_count, particles.size()):
		var p = particles[i]
		tween.tween_property(p, "modulate:a", 0.7, duration * 0.3).set_delay(0.1)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.3).set_delay(duration * 0.5)
		tween.tween_property(p, "scale", p.scale * 2.0, duration * 0.4).set_delay(duration * 0.4)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_ice_particle() -> Sprite2D:
	"""Create a single ice crystal sprite (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("ice_particle", func():
		var size = 20
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var colors = [Color(0.9, 0.95, 1.0), Color(0.5, 0.8, 1.0), Color(0.3, 0.5, 0.9)]
		var center = size / 2
		for y in range(size):
			for x in range(size):
				var dx = abs(x - center)
				var dy = abs(y - center)
				if dx + dy < 8:
					var dist = dx + dy
					var color_idx = int(dist / 3) % colors.size()
					img.set_pixel(x, y, colors[color_idx])
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _animate_lightning(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Lightning spell — CT-style: strobe flash, multi-bolt strike, electric spark shower"""
	var power_t = clampf((power - POWER_MIN) / (POWER_MAX - POWER_MIN), 0.0, 1.0)

	# Environmental reaction: blinding white strobe
	_tint_battle_background(Color(2.0, 2.0, 2.5, 1.0), 0.06)

	# Screen-filling white-yellow flash
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 1.0, 0.9, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 50
	effect.add_child(flash)

	# Heavy screen shake
	_trigger_screen_shake(lerp(10.0, 25.0, power_t), lerp(0.2, 0.5, power_t))

	# Multi-bolt strike — 3-8 bolts, staggered
	var bolt_count = int(lerp(3, 8, power_t))
	var bolts: Array[Sprite2D] = []
	var bolt_spread = lerp(20, 50, power_t)
	for i in range(bolt_count):
		var bolt = _create_lightning_bolt()
		bolt.modulate.a = 0.0
		bolt.position.x = randf_range(-bolt_spread, bolt_spread)
		bolt.rotation = randf_range(-0.25, 0.25)
		bolt.scale = Vector2(power * 1.2, power * 1.5)  # Taller bolts
		effect.add_child(bolt)
		bolts.append(bolt)

	# Massive spark shower — 20-50 sparks
	var spark_count = int(lerp(20, 50, power_t))
	var sparks: Array[Sprite2D] = []
	for i in range(spark_count):
		var spark = _create_spark()
		spark.position = Vector2(randf_range(-20, 20), randf_range(-10, 10))
		spark.modulate.a = 0.0
		spark.scale = Vector2(power * 1.2, power * 1.2)
		effect.add_child(spark)
		sparks.append(spark)

	var duration = lerp(0.5, 0.9, power_t)
	var tween = create_tween()
	tween.set_parallel(true)

	# Strobe flash — rapid on/off for electric feel
	tween.tween_property(flash, "color:a", lerp(0.7, 1.0, power_t), 0.02)
	tween.tween_property(flash, "color:a", 0.1, 0.03).set_delay(0.02)
	tween.tween_property(flash, "color:a", lerp(0.5, 0.8, power_t), 0.02).set_delay(0.05)
	tween.tween_property(flash, "color:a", 0.0, 0.15).set_delay(0.07)

	# Bolts flash with rapid flicker — staggered strikes
	var flicker_count = int(lerp(3, 5, power_t))
	for i in range(bolts.size()):
		var bolt = bolts[i]
		var delay = float(i) * 0.04  # Staggered bolt strikes
		for f in range(flicker_count):
			var fd = delay + float(f) * 0.035
			tween.tween_property(bolt, "modulate:a", 1.0, 0.015).set_delay(fd)
			tween.tween_property(bolt, "modulate:a", 0.2, 0.02).set_delay(fd + 0.015)
		tween.tween_property(bolt, "modulate:a", 0.0, 0.12).set_delay(delay + 0.2)

	# Sparks explode outward in all directions
	var spark_dist = lerp(1.0, 2.5, power_t)
	for i in range(sparks.size()):
		var spark = sparks[i]
		var angle = (float(i) / sparks.size()) * TAU + randf_range(-0.3, 0.3)
		var dist = randf_range(40, 120) * spark_dist
		var end_pos = Vector2(cos(angle) * dist, sin(angle) * dist)

		var spark_delay = 0.04 + randf() * 0.06
		tween.tween_property(spark, "modulate:a", 1.0, 0.03).set_delay(spark_delay)
		tween.tween_property(spark, "position", end_pos, 0.25).set_delay(spark_delay)
		tween.tween_property(spark, "modulate:a", 0.0, 0.12).set_delay(spark_delay + 0.15)
		tween.tween_property(spark, "scale", spark.scale * 0.3, 0.2).set_delay(spark_delay + 0.1)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_spark() -> Sprite2D:
	"""Create a small electric spark (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("spark", func():
		var size = 8
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var colors = [Color(1.0, 1.0, 0.5), Color(0.8, 0.9, 1.0), Color(0.5, 0.7, 1.0)]
		var center = size / 2
		for y in range(size):
			for x in range(size):
				var dist = sqrt(pow(x - center, 2) + pow(y - center, 2))
				if dist < 3:
					var idx = int(dist) % colors.size()
					img.set_pixel(x, y, colors[idx])
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _create_lightning_bolt() -> Sprite2D:
	"""Create lightning bolt sprite (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("lightning_bolt_40x80", func():
		var width = 40
		var height = 80
		var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))

		# Draw jagged bolt (12-bit style)
		var bolt_color = Color(1.0, 1.0, 0.5)
		var glow_color = Color(0.5, 0.5, 1.0, 0.5)

		var x = width / 2
		for y in range(height):
			# Jagged path
			if y % 8 < 4:
				x += randi_range(-3, 3)
			x = clamp(x, 5, width - 5)

			# Draw bolt with glow
			for dx in range(-3, 4):
				var px = x + dx
				if px >= 0 and px < width:
					if abs(dx) <= 1:
						img.set_pixel(px, y, bolt_color)
					else:
						img.set_pixel(px, y, glow_color)

		return ImageTexture.create_from_image(img)
	)
	sprite.position.y = -40  # Center on target
	return sprite


func _animate_holy(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Holy spell - radiant light beams"""
	# Environmental reaction: warm golden brightening
	_tint_battle_background(Color(1.4, 1.35, 1.1, 1.0), 0.7)

	var particles: Array[Sprite2D] = []
	var ray_count = 8

	# Create rays
	for i in range(ray_count):
		var ray = _create_holy_ray()
		var angle = (float(i) / ray_count) * TAU
		ray.rotation = angle
		ray.scale = Vector2(0.5, 0.0)
		effect.add_child(ray)
		particles.append(ray)

	# Create center glow
	var glow = _create_holy_glow()
	glow.scale = Vector2.ZERO
	effect.add_child(glow)

	var duration = 0.7
	var tween = create_tween()
	tween.set_parallel(true)

	# Center glow expands
	tween.tween_property(glow, "scale", Vector2(1.5, 1.5), duration * 0.5)
	tween.tween_property(glow, "modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.4)

	# Rays extend outward
	for i in range(particles.size()):
		var ray = particles[i]
		var delay = float(i) * 0.03
		tween.tween_property(ray, "scale", Vector2(0.5, 1.0), duration * 0.4).set_delay(delay)
		tween.tween_property(ray, "modulate:a", 0.0, duration * 0.3).set_delay(delay + duration * 0.5)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_holy_ray() -> Sprite2D:
	"""Create a holy light ray"""
	var sprite = Sprite2D.new()
	var width = 8
	var height = 60
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center = width / 2
	for y in range(height):
		var fade = 1.0 - (float(y) / height)
		for x in range(width):
			var dist = abs(x - center)
			if dist < 3:
				var alpha = fade * (1.0 - dist / 3.0)
				var color = Color(1.0, 1.0, 0.8, alpha)
				img.set_pixel(x, y, color)

	sprite.texture = ImageTexture.create_from_image(img)
	sprite.offset.y = -height / 2
	return sprite


func _create_holy_glow() -> Sprite2D:
	"""Create holy center glow"""
	var sprite = Sprite2D.new()
	var size = 40
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center = size / 2
	for y in range(size):
		for x in range(size):
			var dist = sqrt(pow(x - center, 2) + pow(y - center, 2))
			if dist < center:
				var alpha = 1.0 - (dist / center)
				var color = Color(1.0, 1.0, 0.9, alpha * 0.8)
				img.set_pixel(x, y, color)

	sprite.texture = ImageTexture.create_from_image(img)
	return sprite


func _animate_dark(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Dark spell - swirling shadows"""
	# Environmental reaction: background dims to near-black briefly
	_tint_battle_background(Color(0.4, 0.35, 0.5, 1.0), 0.6)

	var particles: Array[Sprite2D] = []
	var particle_count = 10

	for i in range(particle_count):
		var particle = _create_dark_particle()
		var angle = randf() * TAU
		var dist = randf_range(20, 40)
		particle.position = Vector2(cos(angle), sin(angle)) * dist
		effect.add_child(particle)
		particles.append(particle)

	var duration = 0.6
	var tween = create_tween()
	tween.set_parallel(true)

	# Shadows spiral inward
	for i in range(particles.size()):
		var p = particles[i]
		var delay = randf() * 0.2

		tween.tween_property(p, "position", Vector2.ZERO, duration * 0.6).set_delay(delay)
		tween.tween_property(p, "rotation", p.rotation + TAU, duration).set_delay(delay)
		tween.tween_property(p, "scale", Vector2(0.5, 0.5), duration * 0.6).set_delay(delay)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.3).set_delay(delay + duration * 0.6)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_dark_particle() -> Sprite2D:
	"""Create a dark wisp particle (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("dark_particle", func():
		var size = 24
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var center = size / 2
		for y in range(size):
			for x in range(size):
				var dist = sqrt(pow(x - center, 2) + pow(y - center, 2))
				if dist < 10:
					var alpha = 1.0 - (dist / 10.0)
					img.set_pixel(x, y, Color(0.2, 0.1, 0.3, alpha * 0.8))
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _animate_heal(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Heal spell - rising sparkles"""
	var particles: Array[Sprite2D] = []
	var particle_count = 15

	for i in range(particle_count):
		var particle = _create_heal_particle()
		particle.position = Vector2(randf_range(-25, 25), randf_range(10, 30))
		particle.modulate.a = 0.0
		effect.add_child(particle)
		particles.append(particle)

	var duration = 0.8
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(particles.size()):
		var p = particles[i]
		var delay = randf() * 0.3
		var rise = randf_range(50, 80)

		tween.tween_property(p, "modulate:a", 1.0, 0.1).set_delay(delay)
		tween.tween_property(p, "position:y", p.position.y - rise, duration * 0.7).set_delay(delay)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.3).set_delay(delay + duration * 0.5)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_heal_particle() -> Sprite2D:
	"""Create a heal sparkle particle (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("heal_particle", func():
		var size = 12
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var center = size / 2
		var colors = [Color(0.5, 1.0, 0.5), Color(0.8, 1.0, 0.8)]
		for y in range(2, size - 2):
			for x in range(center - 1, center + 2):
				img.set_pixel(x, y, colors[0] if abs(y - center) > 2 else colors[1])
		for x in range(2, size - 2):
			for y in range(center - 1, center + 2):
				img.set_pixel(x, y, colors[0] if abs(x - center) > 2 else colors[1])
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _animate_buff(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Buff spell - upward arrows/sparkles"""
	var particles: Array[Sprite2D] = []
	var particle_count = clamp(int(15 * power), 5, 30)
	var rise_height = 50.0 * power

	for i in range(particle_count):
		var particle = _create_buff_arrow()
		var x_offset = (float(i) - particle_count / 2.0) * 12
		particle.position = Vector2(x_offset, 20)
		particle.modulate.a = 0.0
		effect.add_child(particle)
		particles.append(particle)

	var duration = 0.5
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(particles.size()):
		var p = particles[i]
		var delay = float(i) * 0.05

		tween.tween_property(p, "modulate:a", 1.0, 0.1).set_delay(delay)
		tween.tween_property(p, "position:y", p.position.y - rise_height, duration * 0.7).set_delay(delay)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.3).set_delay(delay + duration * 0.5)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_buff_arrow() -> Sprite2D:
	"""Create an upward arrow for buff effect (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("buff_arrow", func():
		var size = 16
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var color = Color(0.3, 0.8, 1.0)
		var center = size / 2
		for y in range(4, size):
			for x in range(center - 2, center + 3):
				img.set_pixel(x, y, color)
		for i in range(4):
			for x in range(center - i, center + i + 1):
				if x >= 0 and x < size:
					img.set_pixel(x, 3 - i + 4, color)
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _animate_debuff(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Debuff spell - downward arrows"""
	var particles: Array[Sprite2D] = []
	var particle_count = clamp(int(15 * power), 5, 30)
	var drop_height = 40.0 * power

	for i in range(particle_count):
		var particle = _create_debuff_arrow()
		var x_offset = (float(i) - particle_count / 2.0) * 12
		particle.position = Vector2(x_offset, -30)
		particle.modulate.a = 0.0
		effect.add_child(particle)
		particles.append(particle)

	var duration = 0.5
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(particles.size()):
		var p = particles[i]
		var delay = float(i) * 0.05

		tween.tween_property(p, "modulate:a", 1.0, 0.1).set_delay(delay)
		tween.tween_property(p, "position:y", p.position.y + drop_height, duration * 0.6).set_delay(delay)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.3).set_delay(delay + duration * 0.5)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_debuff_arrow() -> Sprite2D:
	"""Create a downward arrow for debuff effect (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("debuff_arrow", func():
		var size = 16
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var color = Color(0.8, 0.3, 0.8)
		var center = size / 2
		for y in range(0, size - 4):
			for x in range(center - 2, center + 3):
				img.set_pixel(x, y, color)
		for i in range(4):
			for x in range(center - i, center + i + 1):
				if x >= 0 and x < size:
					img.set_pixel(x, size - 4 + i, color)
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _animate_poison(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Poison spell - bubbling toxic particles"""
	var particles: Array[Sprite2D] = []
	var particle_count = 10

	for i in range(particle_count):
		var particle = _create_poison_bubble()
		particle.position = Vector2(randf_range(-20, 20), randf_range(0, 20))
		particle.scale = Vector2(0.3, 0.3)
		effect.add_child(particle)
		particles.append(particle)

	var duration = 0.6
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(particles.size()):
		var p = particles[i]
		var delay = randf() * 0.3
		var rise = randf_range(30, 50)

		tween.tween_property(p, "scale", Vector2(1.0, 1.0), duration * 0.3).set_delay(delay)
		tween.tween_property(p, "position:y", p.position.y - rise, duration * 0.6).set_delay(delay)
		tween.tween_property(p, "scale", Vector2(0.0, 0.0), duration * 0.2).set_delay(delay + duration * 0.6)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_poison_bubble() -> Sprite2D:
	"""Create a poison bubble particle (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("poison_bubble", func():
		var size = 12
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var center = size / 2
		var color = Color(0.4, 0.7, 0.2)
		var highlight = Color(0.6, 0.9, 0.4)
		for y in range(size):
			for x in range(size):
				var dist = sqrt(pow(x - center, 2) + pow(y - center, 2))
				if dist < 5:
					img.set_pixel(x, y, highlight if dist < 2 else color)
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _animate_physical(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Physical hit - dramatic slash with impact burst"""
	# Multiple slash lines for more impact
	var slashes: Array[Sprite2D] = []
	for i in range(3):
		var slash = _create_slash_effect()
		slash.scale = Vector2(0.3, 0.3)
		slash.modulate.a = 0.0
		slash.rotation = randf_range(-0.3, 0.3)
		effect.add_child(slash)
		slashes.append(slash)

	# Impact burst
	var burst = _create_impact_burst()
	burst.scale = Vector2.ZERO
	burst.modulate.a = 0.8
	effect.add_child(burst)

	# Hit sparks
	var sparks: Array[Sprite2D] = []
	for i in range(8):
		var spark = _create_hit_spark()
		spark.modulate.a = 0.0
		effect.add_child(spark)
		sparks.append(spark)

	# Small screen shake
	_trigger_screen_shake(5.0, 0.15)

	var duration = 0.35
	var tween = create_tween()
	tween.set_parallel(true)

	# Slashes appear in quick succession
	for i in range(slashes.size()):
		var slash = slashes[i]
		var delay = float(i) * 0.04
		tween.tween_property(slash, "modulate:a", 1.0, 0.03).set_delay(delay)
		tween.tween_property(slash, "scale", Vector2(1.5, 1.5), duration * 0.5).set_delay(delay)
		tween.tween_property(slash, "modulate:a", 0.0, duration * 0.4).set_delay(delay + 0.1)

	# Burst expands
	tween.tween_property(burst, "scale", Vector2(1.8, 1.8), 0.15)
	tween.tween_property(burst, "modulate:a", 0.0, 0.15).set_delay(0.1)

	# Sparks fly outward
	for i in range(sparks.size()):
		var spark = sparks[i]
		var angle = (float(i) / sparks.size()) * TAU + randf_range(-0.3, 0.3)
		var dist = randf_range(25, 50)
		var end_pos = Vector2(cos(angle) * dist, sin(angle) * dist)

		tween.tween_property(spark, "modulate:a", 1.0, 0.03).set_delay(0.05)
		tween.tween_property(spark, "position", end_pos, 0.2).set_delay(0.05)
		tween.tween_property(spark, "modulate:a", 0.0, 0.1).set_delay(0.15)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_impact_burst() -> Sprite2D:
	"""Create impact burst sprite (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("impact_burst", func():
		var size = 48
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var center = size / 2
		for angle_idx in range(8):
			var angle = (float(angle_idx) / 8) * TAU
			for dist in range(5, 22):
				var x = int(center + cos(angle) * dist)
				var y = int(center + sin(angle) * dist)
				if x >= 0 and x < size and y >= 0 and y < size:
					var alpha = 1.0 - (float(dist - 5) / 17.0)
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _create_hit_spark() -> Sprite2D:
	"""Create a small hit spark (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("hit_spark", func():
		var size = 6
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var center = size / 2
		for y in range(size):
			for x in range(size):
				var dist = sqrt(pow(x - center, 2) + pow(y - center, 2))
				if dist < 2.5:
					var alpha = 1.0 - dist / 2.5
					img.set_pixel(x, y, Color(1.0, 1.0, 0.8, alpha))
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _create_slash_effect() -> Sprite2D:
	"""Create a slash impact sprite (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("slash_effect", func():
		var size = 48
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var color = Color(1.0, 1.0, 1.0)
		var center = size / 2
		for i in range(-15, 16):
			var x1 = center + i
			var y1 = center - 15 + abs(i) / 2
			var x2 = center + i
			var y2 = center + 15 - abs(i) / 2
			if x1 >= 0 and x1 < size and y1 >= 0 and y1 < size:
				img.set_pixel(x1, y1, color)
			if x2 >= 0 and x2 < size and y2 >= 0 and y2 < size:
				img.set_pixel(x2, y2, color)
		for i in range(-12, 13):
			var px = center + i
			var py = center
			if px >= 0 and px < size:
				img.set_pixel(px, py, color)
				if py + 1 < size:
					img.set_pixel(px, py + 1, color)
		return ImageTexture.create_from_image(img)
	)
	return sprite


func _animate_mp_restore(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""MP restore spell - rising blue sparkles"""
	var particles: Array[Sprite2D] = []
	var particle_count = 15

	for i in range(particle_count):
		var particle = _create_mp_particle()
		particle.position = Vector2(randf_range(-25, 25), randf_range(10, 30))
		particle.modulate.a = 0.0
		effect.add_child(particle)
		particles.append(particle)

	var duration = 0.8
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(particles.size()):
		var p = particles[i]
		var delay = randf() * 0.3
		var rise = randf_range(50, 80)

		tween.tween_property(p, "modulate:a", 1.0, 0.1).set_delay(delay)
		tween.tween_property(p, "position:y", p.position.y - rise, duration * 0.7).set_delay(delay)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.3).set_delay(delay + duration * 0.5)
		# Add slight shimmer rotation
		tween.tween_property(p, "rotation", randf_range(-0.5, 0.5), duration).set_delay(delay)

	tween.chain().tween_callback(func():
		effect.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)


func _create_mp_particle() -> Sprite2D:
	"""Create a blue MP sparkle particle (uses cached texture)"""
	var sprite = Sprite2D.new()
	sprite.texture = _get_cached_texture("mp_particle", func():
		var size = 12
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var center = size / 2
		var colors = [Color(0.3, 0.6, 1.0), Color(0.5, 0.8, 1.0), Color(0.8, 0.9, 1.0)]
		for y in range(2, size - 2):
			for x in range(center - 1, center + 2):
				img.set_pixel(x, y, colors[2] if abs(y - center) <= 1 else colors[0])
		for x in range(2, size - 2):
			for y in range(center - 1, center + 2):
				img.set_pixel(x, y, colors[2] if abs(x - center) <= 1 else colors[0])
		for offset in [[-2, -2], [2, -2], [-2, 2], [2, 2]]:
			var px = center + offset[0]
			var py = center + offset[1]
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, colors[1])
		return ImageTexture.create_from_image(img)
	)
	return sprite
