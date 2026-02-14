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

func _animate_fire(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Fire spell - dramatic explosion with rising flames, scaled by power"""
	var particles: Array[Sprite2D] = []
	# Scale particle count by power (12 at min, 36 at max)
	var particle_count = int(lerp(12, 36, (power - POWER_MIN) / (POWER_MAX - POWER_MIN)))

	# Initial flash/explosion - size scales with power
	var flash_size = lerp(80, 180, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	var flash = ColorRect.new()
	flash.size = Vector2(flash_size, flash_size)
	flash.position = Vector2(-flash_size / 2, -flash_size / 2)
	flash.color = Color(1.0, 0.6, 0.0, 0.0)
	effect.add_child(flash)

	# Screen shake scales with power
	var shake_intensity = lerp(4.0, 15.0, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	var shake_duration = lerp(0.2, 0.5, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	_trigger_screen_shake(shake_intensity, shake_duration)

	# Explosion ring - scale with power
	var ring = _create_explosion_ring(Color(1.0, 0.5, 0.0))
	ring.scale = Vector2.ZERO
	effect.add_child(ring)

	# Particle spread and rise scale with power
	var base_spread = lerp(10, 20, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	for i in range(particle_count):
		var particle = _create_fire_particle()
		var angle = randf() * TAU
		var dist = randf_range(0, base_spread)
		particle.position = Vector2(cos(angle) * dist, sin(angle) * dist)
		# Scale particle size with power
		particle.scale = Vector2(power * 0.8, power * 0.8)
		effect.add_child(particle)
		particles.append(particle)

	# Duration scales slightly with power (bigger = slower for impact)
	var duration = lerp(0.6, 1.0, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	var tween = create_tween()
	tween.set_parallel(true)

	# Flash intensity scales with power
	var flash_alpha = lerp(0.4, 0.8, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	tween.tween_property(flash, "color:a", flash_alpha, 0.05)
	tween.tween_property(flash, "color:a", 0.0, 0.15).set_delay(0.05)

	# Ring expansion scales with power
	var ring_scale = lerp(2.0, 4.0, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	tween.tween_property(ring, "scale", Vector2(ring_scale, ring_scale), 0.3)
	tween.tween_property(ring, "modulate:a", 0.0, 0.2).set_delay(0.15)

	# Particle movement scales with power
	var rise_mult = lerp(0.7, 1.5, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	var spread_mult = lerp(0.7, 1.5, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	for i in range(particles.size()):
		var p = particles[i]
		var delay = randf() * 0.15
		var rise = randf_range(50, 100) * rise_mult
		var spread = randf_range(-30, 30) * spread_mult

		tween.tween_property(p, "position:y", p.position.y - rise, duration).set_delay(delay)
		tween.tween_property(p, "position:x", p.position.x + spread, duration).set_delay(delay)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.5).set_delay(delay + duration * 0.4)
		tween.tween_property(p, "scale", p.scale * Vector2(2.0, 2.5), duration).set_delay(delay)
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
	"""Trigger screen shake effect"""
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
		var original_offset = camera.offset
		var shake_tween = create_tween()
		var steps = int(duration * 30)
		for i in range(steps):
			var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
			shake_tween.tween_property(camera, "offset", original_offset + offset, duration / steps)
		shake_tween.tween_property(camera, "offset", original_offset, 0.05)


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
	"""Ice spell - crystalline shards forming"""
	var particles: Array[Sprite2D] = []
	var particle_count = 8

	for i in range(particle_count):
		var particle = _create_ice_particle()
		var angle = (float(i) / particle_count) * TAU
		particle.position = Vector2(cos(angle), sin(angle)) * 30
		particle.rotation = angle + PI / 2
		particle.scale = Vector2.ZERO
		effect.add_child(particle)
		particles.append(particle)

	var duration = 0.5
	var tween = create_tween()
	tween.set_parallel(true)

	# Crystals form inward then shatter outward
	for i in range(particles.size()):
		var p = particles[i]
		var delay = float(i) * 0.05

		# Form
		tween.tween_property(p, "scale", Vector2(1.0, 1.0), duration * 0.4).set_delay(delay)
		tween.tween_property(p, "position", p.position * 0.5, duration * 0.4).set_delay(delay)

		# Shatter outward
		tween.tween_property(p, "position", p.position * 2, duration * 0.4).set_delay(delay + duration * 0.5)
		tween.tween_property(p, "modulate:a", 0.0, duration * 0.3).set_delay(delay + duration * 0.6)

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
	"""Lightning spell - dramatic multi-bolt strike with bright flash, scaled by power"""
	# Bolt count scales with power (2 at min, 5 at max)
	var bolt_count = int(lerp(2, 5, (power - POWER_MIN) / (POWER_MAX - POWER_MIN)))
	var bolts: Array[Sprite2D] = []
	var bolt_spread = lerp(10, 25, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	for i in range(bolt_count):
		var bolt = _create_lightning_bolt()
		bolt.modulate.a = 0.0
		bolt.position.x = randf_range(-bolt_spread, bolt_spread)
		bolt.rotation = randf_range(-0.2, 0.2)
		bolt.scale = Vector2(power * 0.8, power * 0.9)
		effect.add_child(bolt)
		bolts.append(bolt)

	# Bright flash effect - size scales with power
	var flash_size = lerp(200, 400, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	var flash = ColorRect.new()
	flash.size = Vector2(flash_size, flash_size)
	flash.position = Vector2(-flash_size / 2, -flash_size / 2)
	flash.color = Color(1.0, 1.0, 0.9, 0.0)
	effect.add_child(flash)

	# Electric sparks at impact point - count scales with power
	var spark_count = int(lerp(8, 20, (power - POWER_MIN) / (POWER_MAX - POWER_MIN)))
	var sparks: Array[Sprite2D] = []
	for i in range(spark_count):
		var spark = _create_spark()
		spark.position = Vector2(randf_range(-10, 10), randf_range(-5, 5))
		spark.modulate.a = 0.0
		spark.scale = Vector2(power, power)
		effect.add_child(spark)
		sparks.append(spark)

	# Screen shake scales with power
	var shake_intensity = lerp(8.0, 18.0, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	var shake_duration = lerp(0.15, 0.4, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	_trigger_screen_shake(shake_intensity, shake_duration)

	var duration = lerp(0.4, 0.7, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	var tween = create_tween()
	tween.set_parallel(true)

	# Intense flash - alpha scales with power
	var flash_alpha = lerp(0.6, 1.0, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	tween.tween_property(flash, "color:a", flash_alpha, 0.03)
	tween.tween_property(flash, "color:a", 0.0, 0.15).set_delay(0.03)

	# Bolts flash rapidly - more flicker cycles for higher power
	var flicker_count = int(lerp(2, 4, (power - POWER_MIN) / (POWER_MAX - POWER_MIN)))
	for i in range(bolts.size()):
		var bolt = bolts[i]
		var delay = float(i) * 0.02
		for f in range(flicker_count):
			var fd = delay + float(f) * 0.04
			tween.tween_property(bolt, "modulate:a", 1.0, 0.02).set_delay(fd)
			tween.tween_property(bolt, "modulate:a", 0.3, 0.02).set_delay(fd + 0.02)
		tween.tween_property(bolt, "modulate:a", 0.0, 0.15).set_delay(delay + 0.15)

	# Sparks fly outward - distance scales with power
	var spark_dist_mult = lerp(0.7, 1.5, (power - POWER_MIN) / (POWER_MAX - POWER_MIN))
	for i in range(sparks.size()):
		var spark = sparks[i]
		var angle = (float(i) / sparks.size()) * TAU
		var dist = randf_range(30, 60) * spark_dist_mult
		var end_pos = Vector2(cos(angle) * dist, sin(angle) * dist)

		tween.tween_property(spark, "modulate:a", 1.0, 0.05).set_delay(0.05)
		tween.tween_property(spark, "position", end_pos, 0.2).set_delay(0.05)
		tween.tween_property(spark, "modulate:a", 0.0, 0.15).set_delay(0.2)

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
	"""Create lightning bolt sprite"""
	var sprite = Sprite2D.new()
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

	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position.y = -40  # Center on target
	return sprite


func _animate_holy(effect: Node2D, on_complete: Callable, power: float = 1.0) -> void:
	"""Holy spell - radiant light beams"""
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
	var particle_count = 6

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
		tween.tween_property(p, "position:y", p.position.y - 50, duration * 0.7).set_delay(delay)
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
	var particle_count = 6

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
		tween.tween_property(p, "position:y", p.position.y + 40, duration * 0.6).set_delay(delay)
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
