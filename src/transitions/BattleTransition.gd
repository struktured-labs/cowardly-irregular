extends CanvasLayer

## BattleTransition - Dramatic encounter transitions with per-monster effects
## Inspired by classic JRPG encounter animations

signal transition_started(effect_name: String)
signal transition_midpoint()  # When screen is fully covered
signal transition_finished()

## Transition types
enum TransitionType {
	SHATTER,      # Screen breaks into pieces
	SPIRAL,       # Spinning vortex into battle
	ZOOM_BURST,   # Rapid zoom with flash
	SHAKE_FLASH,  # Violent shaking with strobe
	DRIP,         # Screen melts/drips away
	CURTAIN,      # Theater curtain opening
	PIXELATE,     # Pixel dissolve
	SLICE,        # Horizontal slices separate
	RADIAL_WIPE,  # Clock-like wipe
	SHOCKWAVE     # Expanding ring distortion
}

## Monster type to transition mapping
const MONSTER_TRANSITIONS: Dictionary = {
	"slime": TransitionType.DRIP,
	"bat": TransitionType.SPIRAL,
	"goblin": TransitionType.SHAKE_FLASH,
	"skeleton": TransitionType.SHATTER,
	"ghost": TransitionType.PIXELATE,
	"specter": TransitionType.PIXELATE,
	"spider": TransitionType.RADIAL_WIPE,
	"wolf": TransitionType.ZOOM_BURST,
	"dire_wolf": TransitionType.ZOOM_BURST,
	"snake": TransitionType.SLICE,
	"viper": TransitionType.SLICE,
	"troll": TransitionType.SHAKE_FLASH,
	"cave_troll": TransitionType.SHAKE_FLASH,
	"fungoid": TransitionType.DRIP,
	"imp": TransitionType.SPIRAL,
	"witch": TransitionType.CURTAIN,
	"elemental": TransitionType.SHOCKWAVE,
	"boss": TransitionType.SHATTER,
	"miniboss": TransitionType.ZOOM_BURST,
}

## Transition duration
@export var transition_duration: float = 0.8

## Visual elements
var _overlay: ColorRect
var _effect_container: Control
var _fragments: Array[Control] = []
var _is_transitioning: bool = false

## Screen capture for effects
var _screen_texture: ImageTexture
var _viewport_size: Vector2


func _ready() -> void:
	layer = 100  # Above everything
	_setup_overlay()


func _setup_overlay() -> void:
	_effect_container = Control.new()
	_effect_container.name = "EffectContainer"
	_effect_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effect_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effect_container)

	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = Color.BLACK
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.modulate.a = 0.0
	add_child(_overlay)


## Play battle transition based on enemy type
func play_battle_transition(enemy_types: Array) -> void:
	if _is_transitioning:
		return

	_is_transitioning = true
	_viewport_size = get_viewport().get_visible_rect().size
	_current_enemy_types = enemy_types  # Store for sound generation

	# Determine transition type from first enemy
	var transition_type = _get_transition_for_enemies(enemy_types)
	var type_name = TransitionType.keys()[transition_type]

	print("[TRANSITION] Playing %s transition for enemies: %s" % [type_name, enemy_types])
	transition_started.emit(type_name)

	# Play monster-specific encounter sound
	_play_encounter_sound(transition_type)

	# Execute the transition
	match transition_type:
		TransitionType.SHATTER:
			await _play_shatter()
		TransitionType.SPIRAL:
			await _play_spiral()
		TransitionType.ZOOM_BURST:
			await _play_zoom_burst()
		TransitionType.SHAKE_FLASH:
			await _play_shake_flash()
		TransitionType.DRIP:
			await _play_drip()
		TransitionType.CURTAIN:
			await _play_curtain()
		TransitionType.PIXELATE:
			await _play_pixelate()
		TransitionType.SLICE:
			await _play_slice()
		TransitionType.RADIAL_WIPE:
			await _play_radial_wipe()
		TransitionType.SHOCKWAVE:
			await _play_shockwave()

	transition_midpoint.emit()


## Fade out after battle transition (to reveal battle scene)
func fade_out() -> void:
	var tween = create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, 0.3)
	await tween.finished
	_cleanup_effects()
	_is_transitioning = false
	transition_finished.emit()


func _get_transition_for_enemies(enemy_types: Array) -> TransitionType:
	if enemy_types.is_empty():
		return TransitionType.SHAKE_FLASH

	# Check for boss/miniboss first
	for enemy_type in enemy_types:
		var type_lower = str(enemy_type).to_lower()
		if "boss" in type_lower:
			return MONSTER_TRANSITIONS.get("boss", TransitionType.SHATTER)

	# Use first enemy's transition
	var first_type = str(enemy_types[0]).to_lower()
	# Remove suffixes like "_a", "_b", numbers
	first_type = first_type.rstrip("_abcdefghij0123456789 ")

	return MONSTER_TRANSITIONS.get(first_type, TransitionType.SHAKE_FLASH)


## Monster-specific sound profiles
const MONSTER_SOUNDS: Dictionary = {
	"slime": {"base_freq": 200, "mod": "gloop", "pitch": 0.8},
	"bat": {"base_freq": 1200, "mod": "screech", "pitch": 1.2},
	"goblin": {"base_freq": 400, "mod": "growl", "pitch": 1.0},
	"skeleton": {"base_freq": 800, "mod": "rattle", "pitch": 1.1},
	"ghost": {"base_freq": 600, "mod": "wail", "pitch": 0.9},
	"specter": {"base_freq": 500, "mod": "wail", "pitch": 0.85},
	"spider": {"base_freq": 900, "mod": "skitter", "pitch": 1.3},
	"wolf": {"base_freq": 300, "mod": "howl", "pitch": 0.7},
	"dire_wolf": {"base_freq": 250, "mod": "howl", "pitch": 0.6},
	"snake": {"base_freq": 1000, "mod": "hiss", "pitch": 1.4},
	"viper": {"base_freq": 1100, "mod": "hiss", "pitch": 1.5},
	"troll": {"base_freq": 150, "mod": "roar", "pitch": 0.5},
	"cave_troll": {"base_freq": 120, "mod": "roar", "pitch": 0.45},
	"fungoid": {"base_freq": 350, "mod": "squelch", "pitch": 0.9},
	"imp": {"base_freq": 700, "mod": "cackle", "pitch": 1.3},
	"witch": {"base_freq": 550, "mod": "cackle", "pitch": 1.1},
	"elemental": {"base_freq": 400, "mod": "rumble", "pitch": 0.8},
	"boss": {"base_freq": 100, "mod": "doom", "pitch": 0.4},
	"miniboss": {"base_freq": 180, "mod": "doom", "pitch": 0.55},
}

var _current_enemy_types: Array = []

func _play_encounter_sound(transition_type: TransitionType) -> void:
	# Generate monster-specific encounter sound
	var sound_profile = _get_sound_profile_for_enemies(_current_enemy_types)
	var sound = _generate_monster_sound(sound_profile, transition_type)
	if sound:
		var player = AudioStreamPlayer.new()
		player.stream = sound
		player.volume_db = -6.0
		add_child(player)
		player.play()
		player.finished.connect(func(): player.queue_free())


func _get_sound_profile_for_enemies(enemy_types: Array) -> Dictionary:
	if enemy_types.is_empty():
		return {"base_freq": 400, "mod": "growl", "pitch": 1.0}

	var first_type = str(enemy_types[0]).to_lower()
	first_type = first_type.rstrip("_abcdefghij0123456789 ")

	# Check for boss
	for enemy_type in enemy_types:
		var type_lower = str(enemy_type).to_lower()
		if "boss" in type_lower:
			return MONSTER_SOUNDS.get("boss", MONSTER_SOUNDS["boss"])

	return MONSTER_SOUNDS.get(first_type, {"base_freq": 400, "mod": "growl", "pitch": 1.0})


func _generate_monster_sound(profile: Dictionary, transition_type: TransitionType) -> AudioStream:
	var sample_rate = 22050
	var duration = 0.5
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_8_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(samples)

	var base_freq = profile.get("base_freq", 400)
	var mod_type = profile.get("mod", "growl")
	var pitch = profile.get("pitch", 1.0)

	for i in range(samples):
		var t = float(i) / sample_rate
		var env = 1.0 - t / duration  # Basic envelope
		var sample = 0.0

		match mod_type:
			"gloop":
				# Bubbly, gloopy slime sound
				var freq = base_freq * (1.0 + sin(t * 15) * 0.3)
				sample = sin(t * freq * TAU * pitch) * env
				sample += sin(t * freq * 0.5 * TAU * pitch) * 0.3 * env
				sample *= sin(t * 8) * 0.5 + 0.5  # Bubbling

			"screech":
				# High-pitched bat screech
				var freq = base_freq * (1.0 + t * 2)
				sample = sin(t * freq * TAU * pitch) * env
				sample += sin(t * freq * 1.5 * TAU * pitch) * 0.4 * env
				if fmod(t * 40, 1.0) < 0.3:
					sample *= 1.5

			"growl":
				# Low rumbling growl
				var freq = base_freq * (1.0 - t * 0.3)
				sample = sin(t * freq * TAU * pitch) * env
				sample += randf_range(-0.2, 0.2) * env  # Noise
				sample += sin(t * freq * 2 * TAU * pitch) * 0.2 * env

			"rattle":
				# Bone rattling sound
				var freq = base_freq
				sample = sin(t * freq * TAU * pitch) * env
				if fmod(t * 30, 1.0) < 0.2:
					sample += randf_range(-0.6, 0.6)
				sample *= 0.5 + sin(t * 25) * 0.5

			"wail":
				# Ghostly wail with vibrato
				var freq = base_freq * (1.0 + sin(t * 6) * 0.15)
				sample = sin(t * freq * TAU * pitch) * env
				sample += sin(t * freq * 1.5 * TAU * pitch) * 0.3 * env
				sample *= 0.7 + sin(t * 3) * 0.3  # Tremolo

			"skitter":
				# Rapid clicking/skittering
				var freq = base_freq
				sample = sin(t * freq * TAU * pitch) * env * 0.5
				if fmod(t * 50, 1.0) < 0.15:
					sample += randf_range(-0.8, 0.8)

			"howl":
				# Wolf howl - rising then falling
				var howl_env = sin(t / duration * PI)
				var freq = base_freq * (1.0 + howl_env * 0.5)
				sample = sin(t * freq * TAU * pitch) * howl_env
				sample += sin(t * freq * 1.5 * TAU * pitch) * 0.2 * howl_env

			"hiss":
				# Snake hissing
				var freq = base_freq
				sample = sin(t * freq * TAU * pitch) * env * 0.3
				sample += randf_range(-0.5, 0.5) * env  # White noise hiss
				sample *= 0.6 + sin(t * 20) * 0.4

			"roar":
				# Deep troll roar
				var freq = base_freq * (1.0 + sin(t * 4) * 0.1)
				sample = sin(t * freq * TAU * pitch) * env
				sample += sin(t * freq * 2 * TAU * pitch) * 0.5 * env
				sample += sin(t * freq * 0.5 * TAU * pitch) * 0.7 * env
				sample += randf_range(-0.15, 0.15) * env

			"squelch":
				# Fungoid squelching
				var freq = base_freq * (1.0 - sin(t * 12) * 0.2)
				sample = sin(t * freq * TAU * pitch) * env
				sample *= sin(t * 10) * 0.5 + 0.5
				sample += sin(t * freq * 0.3 * TAU) * 0.3 * env

			"cackle":
				# Imp/witch cackling
				var freq = base_freq * (1.0 + fmod(t * 8, 0.125) * 4)
				sample = sin(t * freq * TAU * pitch) * env
				if fmod(t * 12, 1.0) < 0.3:
					sample *= 1.5
					freq *= 1.2

			"rumble":
				# Elemental deep rumble
				var freq = base_freq
				sample = sin(t * freq * TAU * pitch) * env
				sample += sin(t * freq * 0.5 * TAU * pitch) * 0.8 * env
				sample += sin(t * freq * 0.25 * TAU * pitch) * 0.5 * env
				sample += randf_range(-0.1, 0.1) * env

			"doom":
				# Boss doom sound - ominous
				var freq = base_freq * (1.0 + t * 0.5)
				sample = sin(t * freq * TAU * pitch) * env
				sample += sin(t * freq * 2 * TAU * pitch) * 0.4 * env
				sample += sin(t * freq * 0.5 * TAU * pitch) * 0.6 * env
				sample += sin(t * freq * 4 * TAU * pitch) * 0.2 * env
				# Add sub-bass
				sample += sin(t * base_freq * 0.25 * TAU) * 0.5 * env

		# Convert to 8-bit unsigned
		data[i] = int(clamp((sample * 0.4 + 0.5) * 255, 0, 255))

	audio.data = data
	return audio


## SHATTER - Screen breaks into triangular pieces
func _play_shatter() -> void:
	_clear_fragments()

	var fragment_count = 24
	var colors = [Color(0.1, 0.1, 0.15), Color(0.15, 0.12, 0.2), Color(0.08, 0.08, 0.12)]

	# Create triangular fragments
	for i in range(fragment_count):
		var fragment = ColorRect.new()
		var size = Vector2(randf_range(80, 200), randf_range(80, 200))
		fragment.size = size
		fragment.position = Vector2(
			randf_range(-100, _viewport_size.x),
			randf_range(-100, _viewport_size.y)
		)
		fragment.color = colors[i % colors.size()]
		fragment.rotation = randf_range(-0.5, 0.5)
		fragment.modulate.a = 0.0
		_effect_container.add_child(fragment)
		_fragments.append(fragment)

	# Animate fragments crashing in
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(_fragments.size()):
		var fragment = _fragments[i]
		var delay = randf_range(0, 0.15)
		var target_pos = fragment.position
		var start_pos = target_pos + Vector2(randf_range(-300, 300), -500)
		fragment.position = start_pos

		tween.tween_property(fragment, "position", target_pos, 0.3).set_delay(delay).set_ease(Tween.EASE_IN)
		tween.tween_property(fragment, "modulate:a", 1.0, 0.1).set_delay(delay)
		tween.tween_property(fragment, "rotation", fragment.rotation + randf_range(-0.3, 0.3), 0.3).set_delay(delay)

	await tween.finished

	# Flash white
	_overlay.color = Color.WHITE
	_overlay.modulate.a = 1.0
	await get_tree().create_timer(0.05).timeout
	_overlay.color = Color.BLACK

	# Fade fragments to black
	var fade_tween = create_tween()
	fade_tween.tween_property(_effect_container, "modulate", Color.BLACK, 0.2)
	await fade_tween.finished


## SPIRAL - Spinning vortex
func _play_spiral() -> void:
	_clear_fragments()

	var center = _viewport_size / 2
	var ring_count = 12
	var segments_per_ring = 16

	# Create spiral segments
	for ring in range(ring_count):
		var radius = 50 + ring * 80
		for seg in range(segments_per_ring):
			var angle = (float(seg) / segments_per_ring) * TAU
			var segment = ColorRect.new()
			segment.size = Vector2(60, 30)
			segment.pivot_offset = segment.size / 2
			segment.position = center + Vector2(cos(angle), sin(angle)) * radius - segment.size / 2
			segment.rotation = angle + PI / 2
			segment.color = Color(0.1 + ring * 0.02, 0.05, 0.15 + ring * 0.03)
			segment.modulate.a = 0.0
			_effect_container.add_child(segment)
			_fragments.append(segment)

	# Spiral animation
	var tween = create_tween()
	var total_duration = transition_duration * 0.8

	for i in range(_fragments.size()):
		var fragment = _fragments[i]
		var ring = i / segments_per_ring
		var delay = ring * 0.04

		tween.parallel().tween_property(fragment, "modulate:a", 1.0, 0.1).set_delay(delay)
		tween.parallel().tween_property(fragment, "rotation", fragment.rotation + TAU * 2, total_duration).set_delay(delay)
		tween.parallel().tween_property(fragment, "position", center - fragment.size / 2, total_duration).set_delay(delay).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(fragment, "scale", Vector2(0.1, 0.1), total_duration).set_delay(delay).set_ease(Tween.EASE_IN)

	await tween.finished
	_overlay.modulate.a = 1.0


## ZOOM_BURST - Rapid zoom with flash
func _play_zoom_burst() -> void:
	_clear_fragments()

	var center = _viewport_size / 2

	# Create radial lines
	var line_count = 32
	for i in range(line_count):
		var angle = (float(i) / line_count) * TAU
		var line = ColorRect.new()
		line.size = Vector2(8, _viewport_size.length())
		line.pivot_offset = Vector2(line.size.x / 2, 0)
		line.position = center
		line.rotation = angle
		line.color = Color(1.0, 0.9, 0.7) if i % 2 == 0 else Color(0.9, 0.7, 0.5)
		line.modulate.a = 0.0
		line.scale = Vector2(1, 0)
		_effect_container.add_child(line)
		_fragments.append(line)

	# Flash and zoom
	var tween = create_tween()

	# Lines shoot out
	for i in range(_fragments.size()):
		var fragment = _fragments[i]
		var delay = randf_range(0, 0.05)
		tween.parallel().tween_property(fragment, "modulate:a", 1.0, 0.05).set_delay(delay)
		tween.parallel().tween_property(fragment, "scale:y", 1.5, 0.2).set_delay(delay).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.15).timeout

	# Flash
	_overlay.color = Color.WHITE
	_overlay.modulate.a = 1.0
	await get_tree().create_timer(0.08).timeout
	_overlay.color = Color.BLACK

	await tween.finished


## SHAKE_FLASH - Violent shaking with strobe
func _play_shake_flash() -> void:
	var original_offset = _effect_container.position
	var shake_intensity = 20.0
	var flash_count = 6

	# Shake and flash
	for i in range(flash_count):
		# Shake
		_effect_container.position = original_offset + Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)

		# Flash
		_overlay.color = Color.WHITE if i % 2 == 0 else Color.RED
		_overlay.modulate.a = 0.8 if i % 2 == 0 else 0.6

		await get_tree().create_timer(0.06).timeout
		shake_intensity *= 1.2

	# Final flash to black
	_effect_container.position = original_offset
	_overlay.color = Color.WHITE
	_overlay.modulate.a = 1.0
	await get_tree().create_timer(0.05).timeout
	_overlay.color = Color.BLACK


## DRIP - Screen melts/drips away
func _play_drip() -> void:
	_clear_fragments()

	var column_count = 32
	var column_width = _viewport_size.x / column_count

	# Create dripping columns
	for i in range(column_count):
		var column = ColorRect.new()
		column.size = Vector2(column_width + 2, _viewport_size.y)
		column.position = Vector2(i * column_width - 1, -_viewport_size.y)
		column.color = Color(0.2, 0.15, 0.3) if i % 2 == 0 else Color(0.15, 0.1, 0.25)
		_effect_container.add_child(column)
		_fragments.append(column)

	# Drip animation with varying speeds
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(_fragments.size()):
		var column = _fragments[i]
		var delay = randf_range(0, 0.3)
		var speed = randf_range(0.3, 0.6)
		# Wavy delay based on position
		delay += sin(i * 0.5) * 0.1 + 0.1

		tween.tween_property(column, "position:y", 0, speed).set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	await tween.finished
	_overlay.modulate.a = 1.0


## CURTAIN - Theater curtain opening (in reverse - closing)
func _play_curtain() -> void:
	_clear_fragments()

	# Left curtain
	var left_curtain = ColorRect.new()
	left_curtain.size = Vector2(_viewport_size.x / 2 + 20, _viewport_size.y)
	left_curtain.position = Vector2(-_viewport_size.x / 2 - 20, 0)
	left_curtain.color = Color(0.4, 0.1, 0.15)
	_effect_container.add_child(left_curtain)
	_fragments.append(left_curtain)

	# Right curtain
	var right_curtain = ColorRect.new()
	right_curtain.size = Vector2(_viewport_size.x / 2 + 20, _viewport_size.y)
	right_curtain.position = Vector2(_viewport_size.x, 0)
	right_curtain.color = Color(0.5, 0.12, 0.18)
	_effect_container.add_child(right_curtain)
	_fragments.append(right_curtain)

	# Add curtain folds (vertical lines)
	for curtain_idx in [0, 1]:
		var base_curtain = _fragments[curtain_idx]
		for fold in range(8):
			var fold_line = ColorRect.new()
			fold_line.size = Vector2(4, _viewport_size.y)
			fold_line.position = Vector2(fold * 35 + 10, 0)
			fold_line.color = Color(0.25, 0.05, 0.08)
			base_curtain.add_child(fold_line)

	# Curtains close
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(left_curtain, "position:x", 0, transition_duration * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(right_curtain, "position:x", _viewport_size.x / 2, transition_duration * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	await tween.finished
	_overlay.modulate.a = 1.0


## PIXELATE - Pixel dissolve
func _play_pixelate() -> void:
	_clear_fragments()

	var grid_size = 16
	var pixel_size = Vector2(_viewport_size.x / grid_size, _viewport_size.y / grid_size)

	# Create pixel grid
	for y in range(grid_size):
		for x in range(grid_size):
			var pixel = ColorRect.new()
			pixel.size = pixel_size + Vector2(2, 2)
			pixel.position = Vector2(x * pixel_size.x - 1, y * pixel_size.y - 1)
			# Vary colors slightly
			var shade = randf_range(0.05, 0.2)
			pixel.color = Color(shade, shade * 0.8, shade * 1.2)
			pixel.modulate.a = 0.0
			_effect_container.add_child(pixel)
			_fragments.append(pixel)

	# Random pixel appearance
	var tween = create_tween()
	var shuffled_indices = range(_fragments.size())
	shuffled_indices.shuffle()

	for i in range(shuffled_indices.size()):
		var idx = shuffled_indices[i]
		var fragment = _fragments[idx]
		var delay = float(i) / _fragments.size() * transition_duration * 0.6
		tween.parallel().tween_property(fragment, "modulate:a", 1.0, 0.05).set_delay(delay)

	await tween.finished
	_overlay.modulate.a = 1.0


## SLICE - Horizontal slices separate
func _play_slice() -> void:
	_clear_fragments()

	var slice_count = 12
	var slice_height = _viewport_size.y / slice_count

	# Create slices
	for i in range(slice_count):
		var slice_rect = ColorRect.new()
		slice_rect.size = Vector2(_viewport_size.x, slice_height + 2)
		slice_rect.position = Vector2(0, i * slice_height - 1)
		slice_rect.color = Color(0.12, 0.1, 0.15) if i % 2 == 0 else Color(0.08, 0.06, 0.1)
		slice_rect.modulate.a = 0.0
		_effect_container.add_child(slice_rect)
		_fragments.append(slice_rect)

	# Slices slide in alternating directions
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(_fragments.size()):
		var slice_frag = _fragments[i]
		var direction = -1 if i % 2 == 0 else 1
		var start_x = direction * _viewport_size.x
		slice_frag.position.x = start_x

		var delay = i * 0.03
		tween.tween_property(slice_frag, "modulate:a", 1.0, 0.05).set_delay(delay)
		tween.tween_property(slice_frag, "position:x", 0.0, 0.15).set_delay(delay).set_ease(Tween.EASE_OUT)

	# Quick flash between slices
	await get_tree().create_timer(0.1).timeout
	_overlay.color = Color.WHITE
	_overlay.modulate.a = 0.3
	await get_tree().create_timer(0.02).timeout
	_overlay.modulate.a = 0.0

	await tween.finished
	_overlay.color = Color.BLACK
	_overlay.modulate.a = 1.0


## RADIAL_WIPE - Clock-like wipe
func _play_radial_wipe() -> void:
	_clear_fragments()

	var center = _viewport_size / 2
	var segment_count = 24
	var radius = _viewport_size.length()

	# Create pie segments
	for i in range(segment_count):
		var angle_start = (float(i) / segment_count) * TAU - PI / 2
		var angle_end = (float(i + 1) / segment_count) * TAU - PI / 2

		# Use a polygon for pie shape
		var segment = Polygon2D.new()
		var points = PackedVector2Array()
		points.append(center)

		# Arc points
		var arc_steps = 4
		for j in range(arc_steps + 1):
			var angle = lerp(angle_start, angle_end, float(j) / arc_steps)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)

		segment.polygon = points
		segment.color = Color(0.15, 0.1, 0.2) if i % 2 == 0 else Color(0.1, 0.08, 0.15)
		segment.modulate.a = 0.0
		_effect_container.add_child(segment)
		_fragments.append(segment)

	# Reveal segments in sequence (clock wipe)
	var tween = create_tween()
	for i in range(_fragments.size()):
		var fragment = _fragments[i]
		var delay = float(i) / _fragments.size() * transition_duration * 0.7
		tween.parallel().tween_property(fragment, "modulate:a", 1.0, 0.08).set_delay(delay)

	await tween.finished
	_overlay.modulate.a = 1.0


## SHOCKWAVE - Expanding ring distortion
func _play_shockwave() -> void:
	_clear_fragments()

	var center = _viewport_size / 2
	var ring_count = 8

	# Create expanding rings
	for i in range(ring_count):
		var ring = _create_ring(center, 50 + i * 20, 20 + i * 5)
		ring.modulate.a = 0.0
		ring.scale = Vector2(0.1, 0.1)
		_effect_container.add_child(ring)
		_fragments.append(ring)

	# Rings expand outward
	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(_fragments.size()):
		var ring = _fragments[i]
		var delay = i * 0.05
		var target_scale = 4.0 + i * 0.5

		tween.tween_property(ring, "modulate:a", 1.0, 0.1).set_delay(delay)
		tween.tween_property(ring, "scale", Vector2(target_scale, target_scale), 0.4).set_delay(delay).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring, "modulate:a", 0.5, 0.3).set_delay(delay + 0.2)

	await get_tree().create_timer(0.3).timeout

	# Flash
	_overlay.color = Color(0.8, 0.6, 1.0)
	_overlay.modulate.a = 1.0
	await get_tree().create_timer(0.05).timeout
	_overlay.color = Color.BLACK


func _create_ring(center: Vector2, radius: float, thickness: float) -> Polygon2D:
	var ring = Polygon2D.new()
	var points = PackedVector2Array()
	var segments = 32

	# Outer circle
	for i in range(segments + 1):
		var angle = float(i) / segments * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	# Inner circle (reverse order for hole)
	for i in range(segments, -1, -1):
		var angle = float(i) / segments * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * (radius - thickness))

	ring.polygon = points
	ring.color = Color(0.6, 0.4, 0.8, 0.8)
	return ring


func _clear_fragments() -> void:
	for fragment in _fragments:
		if is_instance_valid(fragment):
			fragment.queue_free()
	_fragments.clear()


func _cleanup_effects() -> void:
	_clear_fragments()
	_effect_container.modulate = Color.WHITE
