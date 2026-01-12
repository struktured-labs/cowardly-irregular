extends Node
class_name SoundManagerClass

## SoundManager - Central audio system for battle and UI sounds
## Generates procedural 8-bit style sounds and manages audio playback

# Audio players for different channels
var _ui_player: AudioStreamPlayer
var _battle_player: AudioStreamPlayer
var _ability_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer

# Music state
var _music_playing: bool = false
var _current_music: String = ""

# Sound definitions - procedural parameters
const SOUNDS = {
	# UI Sounds
	"menu_move": {"freq": 800, "duration": 0.03, "type": "blip"},
	"menu_select": {"freq": 1200, "duration": 0.06, "type": "rising"},
	"menu_cancel": {"freq": 400, "duration": 0.08, "type": "falling"},
	"menu_expand": {"freq": 600, "duration": 0.05, "type": "chord"},
	"advance_queue": {"freq": 50, "duration": 0.4, "type": "explosion"},  # Lower, boomier
	"advance_undo": {"freq": 500, "duration": 0.06, "type": "falling"},
	"defer": {"freq": 300, "duration": 0.1, "type": "low_pulse"},
	"player_turn": {"freq": 880, "duration": 0.2, "type": "da_ding"},

	# Battle Sounds
	"attack_hit": {"freq": 200, "duration": 0.12, "type": "noise_hit"},
	"attack_miss": {"freq": 150, "duration": 0.15, "type": "swoosh"},
	"critical_hit": {"freq": 250, "duration": 0.2, "type": "impact"},
	"damage_taken": {"freq": 180, "duration": 0.1, "type": "thud"},
	"heal": {"freq": 800, "duration": 0.3, "type": "sparkle"},
	"buff": {"freq": 600, "duration": 0.25, "type": "ascending"},
	"debuff": {"freq": 400, "duration": 0.25, "type": "descending"},
	"victory": {"freq": 523, "duration": 0.8, "type": "fanfare"},
	"defeat": {"freq": 200, "duration": 1.0, "type": "sad"},

	# Ability Types (base sounds, can be modified per ability)
	"ability_fire": {"freq": 300, "duration": 0.4, "type": "fire"},
	"ability_ice": {"freq": 600, "duration": 0.35, "type": "ice"},
	"ability_lightning": {"freq": 1200, "duration": 0.3, "type": "electric"},
	"ability_holy": {"freq": 880, "duration": 0.5, "type": "holy"},
	"ability_dark": {"freq": 150, "duration": 0.5, "type": "dark"},
	"ability_physical": {"freq": 250, "duration": 0.15, "type": "slash"},
	"ability_heal": {"freq": 700, "duration": 0.4, "type": "heal"},
}

# Ability sound mappings (ability_id -> sound_key)
var _ability_sounds: Dictionary = {}


func _ready() -> void:
	_setup_audio_players()
	_setup_default_ability_sounds()


func _setup_audio_players() -> void:
	"""Create audio players for different channels"""
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UIPlayer"
	_ui_player.volume_db = -8.0
	_ui_player.bus = "Master"
	add_child(_ui_player)

	_battle_player = AudioStreamPlayer.new()
	_battle_player.name = "BattlePlayer"
	_battle_player.volume_db = -6.0
	_battle_player.bus = "Master"
	add_child(_battle_player)

	_ability_player = AudioStreamPlayer.new()
	_ability_player.name = "AbilityPlayer"
	_ability_player.volume_db = -4.0
	_ability_player.bus = "Master"
	add_child(_ability_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.volume_db = -12.0  # Music quieter than SFX
	_music_player.bus = "Master"
	add_child(_music_player)


func _setup_default_ability_sounds() -> void:
	"""Map abilities to their default sounds based on element/type"""
	# Fire abilities
	_ability_sounds["fire"] = "ability_fire"
	_ability_sounds["fira"] = "ability_fire"
	_ability_sounds["firaga"] = "ability_fire"

	# Ice abilities
	_ability_sounds["blizzard"] = "ability_ice"
	_ability_sounds["blizzara"] = "ability_ice"
	_ability_sounds["blizzaga"] = "ability_ice"

	# Lightning abilities
	_ability_sounds["thunder"] = "ability_lightning"
	_ability_sounds["thundara"] = "ability_lightning"
	_ability_sounds["thundaga"] = "ability_lightning"

	# Holy abilities
	_ability_sounds["cure"] = "ability_heal"
	_ability_sounds["cura"] = "ability_heal"
	_ability_sounds["curaga"] = "ability_heal"
	_ability_sounds["holy"] = "ability_holy"

	# Dark abilities
	_ability_sounds["dark"] = "ability_dark"
	_ability_sounds["drain"] = "ability_dark"

	# Physical abilities
	_ability_sounds["slash"] = "ability_physical"
	_ability_sounds["steal"] = "ability_physical"
	_ability_sounds["mug"] = "ability_physical"


## Public API

func play_ui(sound_key: String) -> void:
	"""Play a UI sound effect"""
	if not SOUNDS.has(sound_key):
		return
	_play_sound(_ui_player, SOUNDS[sound_key])


func play_battle(sound_key: String) -> void:
	"""Play a battle sound effect"""
	if not SOUNDS.has(sound_key):
		return
	_play_sound(_battle_player, SOUNDS[sound_key])


func play_ability(ability_id: String) -> void:
	"""Play sound for an ability (looks up mapping or uses default)"""
	var sound_key = _ability_sounds.get(ability_id, "ability_physical")
	if SOUNDS.has(sound_key):
		_play_sound(_ability_player, SOUNDS[sound_key])


func register_ability_sound(ability_id: String, sound_key: String) -> void:
	"""Register a custom sound for an ability"""
	_ability_sounds[ability_id] = sound_key


## Sound Generation

func _play_sound(player: AudioStreamPlayer, params: Dictionary) -> void:
	"""Generate and play a procedural sound"""
	var sample_rate = 22050
	var duration = params.get("duration", 0.1)
	var freq = params.get("freq", 440.0)
	var sound_type = params.get("type", "blip")

	var generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_rate

	player.stream = generator
	player.play()

	var playback = player.get_stream_playback()
	if not playback:
		return

	var samples = int(sample_rate * duration)

	match sound_type:
		"blip":
			_generate_blip(playback, samples, freq, sample_rate, duration)
		"rising":
			_generate_rising(playback, samples, freq, sample_rate, duration)
		"falling":
			_generate_falling(playback, samples, freq, sample_rate, duration)
		"chord":
			_generate_chord(playback, samples, freq, sample_rate, duration)
		"double_blip":
			_generate_double_blip(playback, samples, freq, sample_rate, duration)
		"boom":
			_generate_boom(playback, samples, freq, sample_rate, duration)
		"explosion":
			_generate_explosion(playback, samples, freq, sample_rate, duration)
		"da_ding":
			_generate_da_ding(playback, samples, freq, sample_rate, duration)
		"low_pulse":
			_generate_low_pulse(playback, samples, freq, sample_rate, duration)
		"noise_hit":
			_generate_noise_hit(playback, samples, freq, sample_rate, duration)
		"swoosh":
			_generate_swoosh(playback, samples, sample_rate, duration)
		"impact":
			_generate_impact(playback, samples, freq, sample_rate, duration)
		"thud":
			_generate_thud(playback, samples, freq, sample_rate, duration)
		"sparkle":
			_generate_sparkle(playback, samples, freq, sample_rate, duration)
		"ascending":
			_generate_ascending(playback, samples, freq, sample_rate, duration)
		"descending":
			_generate_descending(playback, samples, freq, sample_rate, duration)
		"fanfare":
			_generate_fanfare(playback, samples, sample_rate, duration)
		"sad":
			_generate_sad(playback, samples, sample_rate, duration)
		"fire":
			_generate_fire(playback, samples, sample_rate, duration)
		"ice":
			_generate_ice(playback, samples, freq, sample_rate, duration)
		"electric":
			_generate_electric(playback, samples, freq, sample_rate, duration)
		"holy":
			_generate_holy(playback, samples, freq, sample_rate, duration)
		"dark":
			_generate_dark(playback, samples, freq, sample_rate, duration)
		"slash":
			_generate_slash(playback, samples, sample_rate, duration)
		"heal":
			_generate_heal(playback, samples, freq, sample_rate, duration)
		_:
			_generate_blip(playback, samples, freq, sample_rate, duration)


## Sound Generators

func _generate_blip(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = 1.0 - (t / dur)
		var sample = sin(t * freq * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_rising(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var f = freq + (t * 400.0)
		var envelope = 1.0 - (t / dur)
		var sample = sin(t * f * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_falling(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var f = freq - (t * 200.0)
		var envelope = 1.0 - (t / dur)
		var sample = sin(t * max(f, 100) * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_chord(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = 1.0 - (t / dur)
		var sample = sin(t * freq * TAU) * 0.5 + sin(t * freq * 1.5 * TAU) * 0.3
		playback.push_frame(Vector2(sample * envelope, sample * envelope) * 0.25)


func _generate_double_blip(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	var half = samples / 2
	for i in range(samples):
		var t = float(i) / rate
		var local_t = float(i % half) / half
		var envelope = 1.0 - local_t
		var sample = sin(t * freq * TAU) * envelope


func _generate_boom(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	"""Generate a powerful boom sound for Advance action"""
	for i in range(samples):
		var t = float(i) / rate
		# Fast attack, slow decay
		var envelope = pow(1.0 - (t / dur), 1.5) if t < dur * 0.1 else pow(1.0 - (t / dur), 0.8)
		# Low frequency boom with harmonics
		var boom = sin(t * freq * TAU) * 0.5
		boom += sin(t * freq * 0.5 * TAU) * 0.3  # Sub bass
		boom += sin(t * freq * 2 * TAU) * 0.15  # Harmonic
		# Add impact noise at the start
		var impact = randf_range(-0.5, 0.5) * max(0, 1.0 - t * 20) if t < 0.05 else 0.0
		var sample = (boom + impact) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.5)


func _generate_explosion(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	"""Generate an aggressive explosion/bomb sound"""
	for i in range(samples):
		var t = float(i) / rate
		# Sharp attack, rumbling decay
		var attack = 1.0 if t < 0.02 else pow(1.0 - ((t - 0.02) / (dur - 0.02)), 0.6)

		# Very low rumble
		var rumble = sin(t * freq * TAU) * 0.4
		rumble += sin(t * freq * 0.5 * TAU) * 0.5  # Deep sub bass
		rumble += sin(t * freq * 0.25 * TAU) * 0.3  # Even deeper

		# Chaotic noise burst at start
		var noise_intensity = max(0, 1.0 - t * 8)
		var noise = randf_range(-1.0, 1.0) * noise_intensity * 0.7

		# Distortion/crunch
		var crunch = sin(t * freq * 3 * TAU) * 0.2 * max(0, 1.0 - t * 4)

		var sample = (rumble + noise + crunch) * attack
		# Soft clip for extra punch
		sample = clamp(sample * 1.5, -1.0, 1.0)
		playback.push_frame(Vector2(sample, sample) * 0.6)


func _generate_da_ding(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	"""Generate a pleasant da-ding notification sound for player turn"""
	var note1_dur = dur * 0.4
	var note2_start = dur * 0.35
	var note1_freq = freq * 0.75  # Lower note first (G)
	var note2_freq = freq  # Higher note second (A)

	for i in range(samples):
		var t = float(i) / rate
		var sample = 0.0

		# First note (da)
		if t < note1_dur:
			var env1 = sin((t / note1_dur) * PI)
			sample += sin(t * note1_freq * TAU) * env1 * 0.4
			sample += sin(t * note1_freq * 2 * TAU) * env1 * 0.15  # Harmonic

		# Second note (ding) - slightly overlapping
		if t > note2_start:
			var t2 = t - note2_start
			var remaining = dur - note2_start
			var env2 = pow(1.0 - (t2 / remaining), 0.5)
			sample += sin(t2 * note2_freq * TAU) * env2 * 0.5
			sample += sin(t2 * note2_freq * 2 * TAU) * env2 * 0.2  # Harmonic
			sample += sin(t2 * note2_freq * 3 * TAU) * env2 * 0.1  # Bell-like

		playback.push_frame(Vector2(sample, sample) * 0.4)


func _generate_low_pulse(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = sin(t / dur * PI)
		var sample = sin(t * freq * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.4)


func _generate_noise_hit(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = pow(1.0 - (t / dur), 2)
		var noise = randf_range(-1.0, 1.0)
		var tone = sin(t * freq * TAU)
		var sample = (noise * 0.6 + tone * 0.4) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.35)


func _generate_swoosh(playback: AudioStreamGeneratorPlayback, samples: int, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = sin(t / dur * PI)
		var noise = randf_range(-1.0, 1.0)
		playback.push_frame(Vector2(noise * envelope, noise * envelope) * 0.2)


func _generate_impact(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = pow(1.0 - (t / dur), 3)
		var noise = randf_range(-1.0, 1.0) * 0.5
		var tone = sin(t * freq * TAU) * 0.5
		var sample = (noise + tone) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.4)


func _generate_thud(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var f = freq * pow(0.5, t * 10)
		var envelope = pow(1.0 - (t / dur), 2)
		var sample = sin(t * f * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.4)


func _generate_sparkle(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = sin(t / dur * PI)
		var sparkle = sin(t * freq * TAU) * 0.3 + sin(t * freq * 2 * TAU) * 0.2 + sin(t * freq * 3 * TAU) * 0.1
		var shimmer = sin(t * 20 * TAU) * 0.3 + 0.7
		playback.push_frame(Vector2(sparkle * envelope * shimmer, sparkle * envelope * shimmer) * 0.3)


func _generate_ascending(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var f = freq * pow(2.0, t / dur)
		var envelope = sin(t / dur * PI)
		var sample = sin(t * f * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_descending(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var f = freq * pow(0.5, t / dur)
		var envelope = sin(t / dur * PI)
		var sample = sin(t * f * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_fanfare(playback: AudioStreamGeneratorPlayback, samples: int, rate: int, dur: float) -> void:
	# Simple victory jingle: C-E-G-C (octave)
	var notes = [523.25, 659.25, 783.99, 1046.50]  # C5, E5, G5, C6
	var note_dur = dur / 4.0

	for i in range(samples):
		var t = float(i) / rate
		var note_idx = int(t / note_dur) % 4
		var note_t = fmod(t, note_dur)
		var freq = notes[note_idx]
		var envelope = 1.0 - (note_t / note_dur) * 0.5
		var sample = sin(note_t * freq * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.25)


func _generate_sad(playback: AudioStreamGeneratorPlayback, samples: int, rate: int, dur: float) -> void:
	# Descending minor progression
	var freq = 300.0
	for i in range(samples):
		var t = float(i) / rate
		var f = freq * pow(0.7, t / dur)
		var envelope = 1.0 - (t / dur)
		var sample = sin(t * f * TAU) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_fire(playback: AudioStreamGeneratorPlayback, samples: int, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = sin(t / dur * PI)
		var crackle = randf_range(-1.0, 1.0) * 0.4
		var roar = sin(t * 150 * TAU) * 0.3 + sin(t * 200 * TAU) * 0.2
		var sample = (crackle + roar) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.35)


func _generate_ice(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = sin(t / dur * PI)
		var shimmer = sin(t * freq * TAU) * 0.4 + sin(t * freq * 1.5 * TAU) * 0.3
		var crystal = sin(t * 2000 * TAU) * 0.1 * sin(t * 10 * TAU)
		var sample = (shimmer + crystal) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_electric(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = pow(1.0 - (t / dur), 0.5)
		var buzz = sin(t * freq * TAU) * 0.3
		var crackle = randf_range(-1.0, 1.0) * 0.4 if randf() > 0.7 else 0.0
		var sample = (buzz + crackle) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.35)


func _generate_holy(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = sin(t / dur * PI)
		var chord = sin(t * freq * TAU) * 0.3 + sin(t * freq * 1.25 * TAU) * 0.25 + sin(t * freq * 1.5 * TAU) * 0.2
		var shimmer = sin(t * 30 * TAU) * 0.2 + 0.8
		var sample = chord * envelope * shimmer
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_dark(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = sin(t / dur * PI)
		var growl = sin(t * freq * TAU) * 0.4 + sin(t * freq * 0.5 * TAU) * 0.3
		var rumble = randf_range(-0.2, 0.2)
		var sample = (growl + rumble) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.35)


func _generate_slash(playback: AudioStreamGeneratorPlayback, samples: int, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = pow(1.0 - (t / dur), 2)
		var swoosh = randf_range(-1.0, 1.0) * 0.6
		var impact = sin(t * 200 * TAU) * 0.3 if t < 0.05 else 0.0
		var sample = (swoosh + impact) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_heal(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	for i in range(samples):
		var t = float(i) / rate
		var envelope = sin(t / dur * PI)
		var f = freq + sin(t * 5 * TAU) * 50
		var tone = sin(t * f * TAU) * 0.4
		var sparkle = sin(t * f * 2 * TAU) * 0.2 + sin(t * f * 3 * TAU) * 0.1
		var sample = (tone + sparkle) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.3)


## ============================================================================
## MUSIC SYSTEM
## ============================================================================
## Stub implementation - generates procedural 16-bit style battle music
## Replace _generate_battle_music() internals with file loading when real
## music assets are available (e.g., load("res://assets/audio/battle.ogg"))

func play_music(track: String) -> void:
	"""Play a music track (currently only 'battle' is implemented)"""
	if _current_music == track and _music_playing:
		return  # Already playing

	stop_music()
	_current_music = track

	match track:
		"battle":
			_start_battle_music()
		"boss":
			_start_boss_music()
		"danger":
			_start_danger_music()
		"victory":
			_start_victory_music()
		_:
			push_warning("Unknown music track: %s" % track)


func stop_music() -> void:
	"""Stop currently playing music"""
	_music_playing = false
	_current_music = ""
	if _music_player:
		_music_player.stop()


func is_music_playing() -> bool:
	return _music_playing


## Battle Music - Procedural 16-bit Style Loop
## This is a STUB - replace with actual music file when available

var _music_timer: float = 0.0
var _music_buffer: PackedVector2Array = PackedVector2Array()

func _start_battle_music() -> void:
	"""Generate and start looping battle music"""
	_music_playing = true

	# Generate music buffer (12 bars at 140 BPM - 3 sections of 4 bars each)
	var sample_rate = 22050
	var bpm = 140.0
	var beats_per_bar = 4
	var bars = 12  # 3x longer with 3 distinct sections
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * beats_per_bar * bars

	_music_buffer = _generate_battle_music_buffer(sample_rate, total_duration, bpm)

	# Create looping audio stream
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = _music_buffer.size()

	# Convert to 16-bit PCM
	var data = PackedByteArray()
	for frame in _music_buffer:
		var left = int(clamp(frame.x, -1.0, 1.0) * 32767)
		var right = int(clamp(frame.y, -1.0, 1.0) * 32767)
		data.append(left & 0xFF)
		data.append((left >> 8) & 0xFF)
		data.append(right & 0xFF)
		data.append((right >> 8) & 0xFF)

	wav.data = data
	_music_player.stream = wav
	_music_player.play()


func _generate_battle_music_buffer(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate a catchy 16-bit battle theme - 12 bars with 3 distinct sections"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# Musical notes (frequencies in Hz)
	# Using A minor scale for dramatic battle feel
	const NOTE_A3 = 220.0
	const NOTE_B3 = 246.94
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88
	const NOTE_C5 = 523.25
	const NOTE_D5 = 587.33
	const NOTE_E5 = 659.25

	# Section A - Main aggressive riff (bars 1-4)
	var melody_a = [
		NOTE_A4, 0, NOTE_A4, NOTE_C5, NOTE_A4, 0, NOTE_G4, 0,  # Bar 1
		NOTE_F4, 0, NOTE_E4, 0, NOTE_F4, NOTE_G4, NOTE_A4, 0,
		NOTE_A4, 0, NOTE_A4, NOTE_C5, NOTE_E5, 0, NOTE_C5, 0,  # Bar 2
		NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, NOTE_E4, NOTE_D4, 0,
		NOTE_E4, 0, NOTE_E4, NOTE_G4, NOTE_A4, 0, NOTE_G4, 0,  # Bar 3
		NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, NOTE_E4, NOTE_F4, 0,
		NOTE_A4, 0, NOTE_C5, 0, NOTE_A4, 0, NOTE_G4, NOTE_F4,  # Bar 4
		NOTE_E4, 0, NOTE_D4, 0, NOTE_E4, 0, NOTE_A3, 0,
	]

	# Section B - Tension build (bars 5-8)
	var melody_b = [
		NOTE_E4, 0, NOTE_E4, 0, NOTE_E4, NOTE_F4, NOTE_G4, 0,  # Bar 5
		NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0,
		NOTE_D4, 0, NOTE_D4, 0, NOTE_D4, NOTE_E4, NOTE_F4, 0,  # Bar 6
		NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0,
		NOTE_C5, 0, NOTE_B4, 0, NOTE_A4, 0, NOTE_G4, 0,  # Bar 7
		NOTE_F4, NOTE_G4, NOTE_A4, 0, NOTE_B4, NOTE_C5, NOTE_D5, 0,
		NOTE_E5, 0, NOTE_D5, 0, NOTE_C5, 0, NOTE_B4, NOTE_A4,  # Bar 8
		NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0,
	]

	# Section C - Triumphant variation (bars 9-12)
	var melody_c = [
		NOTE_A4, NOTE_A4, NOTE_C5, NOTE_C5, NOTE_E5, NOTE_E5, NOTE_C5, 0,  # Bar 9
		NOTE_A4, 0, NOTE_G4, 0, NOTE_A4, NOTE_C5, NOTE_E5, 0,
		NOTE_D5, 0, NOTE_C5, 0, NOTE_A4, 0, NOTE_G4, 0,  # Bar 10
		NOTE_F4, NOTE_G4, NOTE_A4, NOTE_C5, NOTE_A4, 0, NOTE_G4, 0,
		NOTE_E4, NOTE_E4, NOTE_G4, NOTE_G4, NOTE_A4, NOTE_A4, NOTE_C5, 0,  # Bar 11
		NOTE_E5, 0, NOTE_D5, 0, NOTE_C5, NOTE_B4, NOTE_A4, 0,
		NOTE_A4, 0, NOTE_C5, NOTE_E5, NOTE_A4, 0, NOTE_C5, NOTE_E5,  # Bar 12
		NOTE_A4, NOTE_G4, NOTE_F4, NOTE_E4, NOTE_D4, NOTE_C4, NOTE_D4, NOTE_E4,
	]

	# Full melody (192 16th notes for 12 bars)
	var melody_pattern = melody_a + melody_b + melody_c

	# Bass patterns for each section (48 quarter notes total)
	var bass_a = [
		NOTE_A3, NOTE_A3, NOTE_C4, NOTE_C4,  # Bar 1-2
		NOTE_D4, NOTE_D4, NOTE_E4, NOTE_E4,
		NOTE_F4, NOTE_F4, NOTE_E4, NOTE_E4,  # Bar 3-4
		NOTE_D4, NOTE_C4, NOTE_D4, NOTE_E4,
	]
	var bass_b = [
		NOTE_E4, NOTE_E4, NOTE_D4, NOTE_D4,  # Bar 5-6
		NOTE_C4, NOTE_C4, NOTE_D4, NOTE_D4,
		NOTE_A3, NOTE_A3, NOTE_B3, NOTE_B3,  # Bar 7-8
		NOTE_C4, NOTE_D4, NOTE_E4, NOTE_D4,
	]
	var bass_c = [
		NOTE_A3, NOTE_C4, NOTE_E4, NOTE_C4,  # Bar 9-10
		NOTE_D4, NOTE_D4, NOTE_C4, NOTE_C4,
		NOTE_E4, NOTE_E4, NOTE_A3, NOTE_A3,  # Bar 11-12
		NOTE_C4, NOTE_D4, NOTE_E4, NOTE_A3,
	]
	var bass_pattern = bass_a + bass_b + bass_c

	var sixteenth_duration = beat_duration / 4.0
	var quarter_duration = beat_duration

	for i in range(samples):
		var t = float(i) / rate  # Time in seconds

		# Which note are we on? (wrap around full 12-bar pattern)
		var sixteenth_idx = int(t / sixteenth_duration) % 192  # 12 bars * 16 sixteenths
		var quarter_idx = int(t / quarter_duration) % 48  # 12 bars * 4 quarters

		# Time within current note (for envelope)
		var t_in_sixteenth = fmod(t, sixteenth_duration) / sixteenth_duration
		var t_in_quarter = fmod(t, quarter_duration) / quarter_duration

		var sample = 0.0

		# Melody voice (square wave with envelope)
		var melody_freq = melody_pattern[sixteenth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_sixteenth, 0.3)  # Quick decay
			var melody_wave = _square_wave(t * melody_freq) * 0.25
			sample += melody_wave * melody_env

		# Bass voice (triangle wave, sustained)
		var bass_freq = bass_pattern[quarter_idx] * 0.5  # Octave down
		var bass_env = 0.8 + 0.2 * sin(t_in_quarter * PI)  # Slight pulse
		var bass_wave = _triangle_wave(t * bass_freq) * 0.3
		sample += bass_wave * bass_env

		# Drums (noise-based kick and hi-hat)
		var beat_pos = fmod(t, beat_duration)

		# Kick on 1 and 3
		if beat_pos < 0.05:
			var kick_env = pow(1.0 - beat_pos / 0.05, 2)
			var kick = sin(beat_pos * 80 * TAU) * kick_env * 0.4
			sample += kick

		# Snare on 2 and 4
		var beat_in_bar = int(t / beat_duration) % 4
		if beat_in_bar in [1, 3] and beat_pos < 0.08:
			var snare_env = pow(1.0 - beat_pos / 0.08, 1.5)
			var snare = randf_range(-0.3, 0.3) * snare_env
			sample += snare

		# Hi-hat on off-beats (8th notes)
		var eighth_pos = fmod(t, beat_duration / 2.0)
		if eighth_pos < 0.02:
			var hat_env = pow(1.0 - eighth_pos / 0.02, 3)
			var hat = randf_range(-0.15, 0.15) * hat_env
			sample += hat

		# Soft clip for warmth
		sample = clamp(sample * 1.2, -0.9, 0.9)

		buffer.append(Vector2(sample, sample))

	return buffer


func _start_victory_music() -> void:
	"""Play a short victory fanfare (non-looping)"""
	_music_playing = true

	var sample_rate = 22050
	var duration = 2.0  # 2 second fanfare

	var buffer = _generate_victory_fanfare(sample_rate, duration)

	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED

	var data = PackedByteArray()
	for frame in buffer:
		var left = int(clamp(frame.x, -1.0, 1.0) * 32767)
		var right = int(clamp(frame.y, -1.0, 1.0) * 32767)
		data.append(left & 0xFF)
		data.append((left >> 8) & 0xFF)
		data.append(right & 0xFF)
		data.append((right >> 8) & 0xFF)

	wav.data = data
	_music_player.stream = wav
	_music_player.play()


func _generate_victory_fanfare(rate: int, duration: float) -> PackedVector2Array:
	"""Generate classic JRPG victory fanfare"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)

	# Classic victory: C-E-G-C (rising arpeggio) then chord
	const NOTE_C4 = 261.63
	const NOTE_E4 = 329.63
	const NOTE_G4 = 392.0
	const NOTE_C5 = 523.25

	var note_times = [0.0, 0.15, 0.30, 0.45]  # Arpeggio timing
	var chord_start = 0.6
	var notes = [NOTE_C4, NOTE_E4, NOTE_G4, NOTE_C5]

	for i in range(samples):
		var t = float(i) / rate
		var sample = 0.0

		# Arpeggio phase
		if t < chord_start:
			for j in range(4):
				if t >= note_times[j]:
					var note_t = t - note_times[j]
					var env = pow(max(0, 1.0 - note_t / 0.5), 0.5)
					sample += _square_wave(note_t * notes[j]) * env * 0.2
					sample += _triangle_wave(note_t * notes[j] * 0.5) * env * 0.15

		# Sustained chord phase
		else:
			var chord_t = t - chord_start
			var env = pow(max(0, 1.0 - chord_t / (duration - chord_start)), 0.3)
			for note in notes:
				sample += _triangle_wave(chord_t * note) * env * 0.15
				sample += _square_wave(chord_t * note) * env * 0.1

		sample = clamp(sample, -0.9, 0.9)
		buffer.append(Vector2(sample, sample))

	return buffer


## Boss Battle Music - Intense, menacing theme

func _start_boss_music() -> void:
	"""Generate and start looping boss battle music"""
	_music_playing = true

	# Generate music buffer (16 bars at 150 BPM - faster, more intense)
	var sample_rate = 22050
	var bpm = 150.0
	var beats_per_bar = 4
	var bars = 16  # Longer boss theme
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * beats_per_bar * bars

	_music_buffer = _generate_boss_music_buffer(sample_rate, total_duration, bpm)

	# Create looping audio stream
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = _music_buffer.size()

	# Convert to 16-bit PCM
	var data = PackedByteArray()
	for frame in _music_buffer:
		var left = int(clamp(frame.x, -1.0, 1.0) * 32767)
		var right = int(clamp(frame.y, -1.0, 1.0) * 32767)
		data.append(left & 0xFF)
		data.append((left >> 8) & 0xFF)
		data.append(right & 0xFF)
		data.append((right >> 8) & 0xFF)

	wav.data = data
	_music_player.stream = wav
	_music_player.play()


func _generate_boss_music_buffer(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate intense boss battle theme - D minor, aggressive"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# Notes in D minor (darker, more menacing)
	const NOTE_D3 = 146.83
	const NOTE_E3 = 164.81
	const NOTE_F3 = 174.61
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_Bb3 = 233.08
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_Bb4 = 466.16
	const NOTE_C5 = 523.25
	const NOTE_D5 = 587.33

	# Section A - Ominous intro (bars 1-4)
	var melody_a = [
		NOTE_D4, 0, 0, 0, NOTE_D4, 0, NOTE_E4, NOTE_F4,  # Bar 1
		NOTE_E4, 0, NOTE_D4, 0, 0, 0, 0, 0,
		NOTE_A4, 0, 0, 0, NOTE_A4, 0, NOTE_Bb4, NOTE_A4,  # Bar 2
		NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0,
		NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, NOTE_C4, 0,  # Bar 3
		NOTE_D4, 0, NOTE_E4, NOTE_F4, NOTE_G4, 0, NOTE_A4, 0,
		NOTE_Bb4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, NOTE_E4,  # Bar 4
		NOTE_D4, 0, 0, 0, NOTE_D4, NOTE_E4, NOTE_F4, NOTE_G4,
	]

	# Section B - Aggressive attack (bars 5-8)
	var melody_b = [
		NOTE_A4, NOTE_A4, NOTE_A4, 0, NOTE_Bb4, NOTE_A4, NOTE_G4, 0,  # Bar 5
		NOTE_F4, NOTE_F4, NOTE_E4, NOTE_D4, NOTE_E4, NOTE_F4, NOTE_G4, NOTE_A4,
		NOTE_D5, 0, NOTE_C5, 0, NOTE_Bb4, 0, NOTE_A4, 0,  # Bar 6
		NOTE_G4, NOTE_F4, NOTE_E4, NOTE_D4, NOTE_E4, 0, NOTE_F4, 0,
		NOTE_G4, NOTE_G4, NOTE_A4, NOTE_Bb4, NOTE_A4, 0, NOTE_G4, 0,  # Bar 7
		NOTE_F4, NOTE_E4, NOTE_D4, 0, NOTE_E4, NOTE_F4, NOTE_G4, 0,
		NOTE_A4, 0, NOTE_D5, 0, NOTE_A4, 0, NOTE_G4, NOTE_F4,  # Bar 8
		NOTE_E4, NOTE_D4, NOTE_C4, NOTE_D4, NOTE_E4, NOTE_F4, NOTE_G4, NOTE_A4,
	]

	# Section C - Dark descent (bars 9-12)
	var melody_c = [
		NOTE_D5, 0, NOTE_D5, 0, NOTE_C5, 0, NOTE_Bb4, 0,  # Bar 9
		NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0,
		NOTE_D4, 0, NOTE_E4, 0, NOTE_F4, 0, NOTE_G4, 0,  # Bar 10
		NOTE_A4, 0, NOTE_Bb4, 0, NOTE_A4, NOTE_G4, NOTE_F4, NOTE_E4,
		NOTE_D4, NOTE_D4, NOTE_F4, NOTE_F4, NOTE_A4, NOTE_A4, NOTE_D5, 0,  # Bar 11
		NOTE_C5, NOTE_Bb4, NOTE_A4, NOTE_G4, NOTE_F4, NOTE_E4, NOTE_D4, 0,
		NOTE_A4, 0, NOTE_A4, 0, NOTE_Bb4, NOTE_A4, NOTE_G4, NOTE_F4,  # Bar 12
		NOTE_E4, NOTE_F4, NOTE_G4, NOTE_A4, NOTE_Bb4, NOTE_A4, NOTE_G4, NOTE_F4,
	]

	# Section D - Climax (bars 13-16)
	var melody_d = [
		NOTE_D5, NOTE_D5, NOTE_D5, 0, NOTE_C5, NOTE_C5, NOTE_C5, 0,  # Bar 13
		NOTE_Bb4, NOTE_Bb4, NOTE_A4, NOTE_G4, NOTE_F4, NOTE_E4, NOTE_D4, 0,
		NOTE_A4, NOTE_Bb4, NOTE_A4, NOTE_G4, NOTE_F4, NOTE_E4, NOTE_F4, NOTE_G4,  # Bar 14
		NOTE_A4, 0, NOTE_D5, 0, NOTE_A4, 0, NOTE_F4, 0,
		NOTE_D4, NOTE_F4, NOTE_A4, NOTE_D5, NOTE_A4, NOTE_F4, NOTE_D4, 0,  # Bar 15
		NOTE_E4, NOTE_G4, NOTE_Bb4, NOTE_D5, NOTE_Bb4, NOTE_G4, NOTE_E4, 0,
		NOTE_D5, 0, NOTE_C5, 0, NOTE_Bb4, 0, NOTE_A4, 0,  # Bar 16
		NOTE_G4, NOTE_F4, NOTE_E4, NOTE_D4, NOTE_D4, 0, 0, 0,
	]

	var melody_pattern = melody_a + melody_b + melody_c + melody_d

	# Bass - heavy, pounding (64 quarter notes)
	var bass_pattern = [
		# Section A
		NOTE_D3, NOTE_D3, NOTE_D3, NOTE_D3,
		NOTE_A3, NOTE_A3, NOTE_G3, NOTE_F3,
		NOTE_D3, NOTE_D3, NOTE_F3, NOTE_G3,
		NOTE_Bb3, NOTE_A3, NOTE_G3, NOTE_D3,
		# Section B
		NOTE_D3, NOTE_D3, NOTE_F3, NOTE_F3,
		NOTE_G3, NOTE_G3, NOTE_A3, NOTE_A3,
		NOTE_Bb3, NOTE_Bb3, NOTE_A3, NOTE_G3,
		NOTE_F3, NOTE_E3, NOTE_D3, NOTE_D3,
		# Section C
		NOTE_D3, NOTE_D3, NOTE_C4, NOTE_Bb3,
		NOTE_A3, NOTE_G3, NOTE_F3, NOTE_E3,
		NOTE_D3, NOTE_F3, NOTE_A3, NOTE_D3,
		NOTE_G3, NOTE_A3, NOTE_Bb3, NOTE_A3,
		# Section D
		NOTE_D3, NOTE_D3, NOTE_D3, NOTE_D3,
		NOTE_F3, NOTE_F3, NOTE_A3, NOTE_A3,
		NOTE_D3, NOTE_E3, NOTE_F3, NOTE_G3,
		NOTE_A3, NOTE_Bb3, NOTE_A3, NOTE_D3,
	]

	var sixteenth_duration = beat_duration / 4.0
	var quarter_duration = beat_duration

	for i in range(samples):
		var t = float(i) / rate

		# 256 sixteenths for 16 bars, 64 quarters
		var sixteenth_idx = int(t / sixteenth_duration) % 256
		var quarter_idx = int(t / quarter_duration) % 64

		var t_in_sixteenth = fmod(t, sixteenth_duration) / sixteenth_duration
		var t_in_quarter = fmod(t, quarter_duration) / quarter_duration

		var sample = 0.0

		# Melody - more aggressive square wave
		var melody_freq = melody_pattern[sixteenth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_sixteenth, 0.4)
			var melody_wave = _square_wave(t * melody_freq) * 0.28
			# Add slight detune for thickness
			melody_wave += _square_wave(t * melody_freq * 1.003) * 0.12
			sample += melody_wave * melody_env

		# Bass - heavy triangle + sub
		var bass_freq = bass_pattern[quarter_idx] * 0.5
		var bass_env = 0.9 + 0.1 * sin(t_in_quarter * PI)
		var bass_wave = _triangle_wave(t * bass_freq) * 0.35
		bass_wave += sin(t * bass_freq * 0.5 * TAU) * 0.15  # Sub bass
		sample += bass_wave * bass_env

		# Drums - heavier, more aggressive
		var beat_pos = fmod(t, beat_duration)

		# Double kick pattern
		var kick_pattern = beat_pos < 0.05 or (beat_pos > beat_duration * 0.5 and beat_pos < beat_duration * 0.5 + 0.04)
		if kick_pattern:
			var kick_t = beat_pos if beat_pos < 0.05 else beat_pos - beat_duration * 0.5
			var kick_env = pow(1.0 - kick_t / 0.05, 2)
			var kick = sin(kick_t * 60 * TAU) * kick_env * 0.5
			kick += sin(kick_t * 30 * TAU) * kick_env * 0.3  # Sub kick
			sample += kick

		# Snare on 2 and 4 with extra punch
		var beat_in_bar = int(t / beat_duration) % 4
		if beat_in_bar in [1, 3] and beat_pos < 0.1:
			var snare_env = pow(1.0 - beat_pos / 0.1, 1.2)
			var snare = randf_range(-0.4, 0.4) * snare_env
			snare += sin(beat_pos * 200 * TAU) * snare_env * 0.2
			sample += snare

		# Faster hi-hats (16th notes)
		var sixteenth_pos = fmod(t, beat_duration / 4.0)
		if sixteenth_pos < 0.015:
			var hat_env = pow(1.0 - sixteenth_pos / 0.015, 3)
			var hat = randf_range(-0.12, 0.12) * hat_env
			sample += hat

		# Heavier soft clip
		sample = clamp(sample * 1.4, -0.95, 0.95)

		buffer.append(Vector2(sample, sample))

	return buffer


## Danger Music - Dark, urgent theme when player is about to die

func _start_danger_music() -> void:
	"""Generate and start looping danger/critical HP music"""
	_music_playing = true

	# Generate music buffer (8 bars at 160 BPM - urgent, dark)
	var sample_rate = 22050
	var bpm = 160.0
	var beats_per_bar = 4
	var bars = 8
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * beats_per_bar * bars

	_music_buffer = _generate_danger_music_buffer(sample_rate, total_duration, bpm)

	# Create looping audio stream
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = _music_buffer.size()

	var data = PackedByteArray()
	for frame in _music_buffer:
		var left = int(clamp(frame.x, -1.0, 1.0) * 32767)
		var right = int(clamp(frame.y, -1.0, 1.0) * 32767)
		data.append(left & 0xFF)
		data.append((left >> 8) & 0xFF)
		data.append(right & 0xFF)
		data.append((right >> 8) & 0xFF)

	wav.data = data
	_music_player.stream = wav
	_music_player.play()


func _generate_danger_music_buffer(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate dark, urgent danger theme - chromatic, dissonant, pulsing"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# Dark chromatic notes (E minor with chromatic tension)
	const NOTE_E2 = 82.41
	const NOTE_F2 = 87.31
	const NOTE_G2 = 98.0
	const NOTE_A2 = 110.0
	const NOTE_Bb2 = 116.54
	const NOTE_B2 = 123.47
	const NOTE_C3 = 130.81
	const NOTE_D3 = 146.83
	const NOTE_Eb3 = 155.56
	const NOTE_E3 = 164.81
	const NOTE_F3 = 174.61
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_Bb3 = 233.08
	const NOTE_B3 = 246.94
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_Eb4 = 311.13
	const NOTE_E4 = 329.63
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0

	# Melody - urgent, chromatic, anxious (128 sixteenths for 8 bars)
	var melody = [
		# Bar 1-2: Pulsing urgency
		NOTE_E4, 0, NOTE_E4, 0, NOTE_Eb4, 0, NOTE_E4, 0,
		NOTE_F4, 0, NOTE_E4, 0, NOTE_Eb4, 0, NOTE_D4, 0,
		NOTE_E4, 0, NOTE_E4, 0, NOTE_F4, 0, NOTE_E4, 0,
		NOTE_Eb4, NOTE_D4, NOTE_Eb4, NOTE_E4, NOTE_F4, NOTE_E4, NOTE_Eb4, NOTE_D4,
		# Bar 3-4: Rising tension
		NOTE_B3, 0, NOTE_C4, 0, NOTE_D4, 0, NOTE_Eb4, 0,
		NOTE_E4, 0, NOTE_F4, 0, NOTE_E4, NOTE_Eb4, NOTE_D4, 0,
		NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_Eb4, 0,
		NOTE_D4, NOTE_Eb4, NOTE_E4, NOTE_F4, NOTE_E4, NOTE_Eb4, NOTE_D4, NOTE_C4,
		# Bar 5-6: Dark descent
		NOTE_E4, NOTE_E4, NOTE_Eb4, NOTE_Eb4, NOTE_D4, NOTE_D4, NOTE_C4, 0,
		NOTE_B3, 0, NOTE_C4, 0, NOTE_D4, 0, NOTE_Eb4, 0,
		NOTE_E4, 0, NOTE_E4, 0, NOTE_E4, NOTE_F4, NOTE_E4, NOTE_Eb4,
		NOTE_D4, 0, NOTE_C4, 0, NOTE_B3, 0, NOTE_C4, NOTE_D4,
		# Bar 7-8: Climax pulse
		NOTE_E4, NOTE_E4, NOTE_E4, 0, NOTE_F4, NOTE_E4, NOTE_Eb4, 0,
		NOTE_E4, NOTE_E4, NOTE_E4, 0, NOTE_G4, NOTE_F4, NOTE_E4, 0,
		NOTE_E4, NOTE_Eb4, NOTE_D4, NOTE_Eb4, NOTE_E4, NOTE_F4, NOTE_E4, NOTE_Eb4,
		NOTE_D4, NOTE_C4, NOTE_B3, NOTE_C4, NOTE_D4, NOTE_Eb4, NOTE_E4, 0,
	]

	# Bass - ominous pedal tone with chromatic movement (32 quarters)
	var bass = [
		NOTE_E2, NOTE_E2, NOTE_E2, NOTE_F2,
		NOTE_E2, NOTE_E2, NOTE_Eb3, NOTE_D3,
		NOTE_E2, NOTE_E2, NOTE_G2, NOTE_A2,
		NOTE_Bb2, NOTE_A2, NOTE_G2, NOTE_E2,
		NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2,
		NOTE_F2, NOTE_E2, NOTE_D3, NOTE_C3,
		NOTE_E2, NOTE_E2, NOTE_E2, NOTE_F2,
		NOTE_G2, NOTE_A2, NOTE_B2, NOTE_E2,
	]

	var sixteenth_duration = beat_duration / 4.0
	var quarter_duration = beat_duration

	for i in range(samples):
		var t = float(i) / rate

		var sixteenth_idx = int(t / sixteenth_duration) % 128
		var quarter_idx = int(t / quarter_duration) % 32

		var t_in_sixteenth = fmod(t, sixteenth_duration) / sixteenth_duration
		var t_in_quarter = fmod(t, quarter_duration) / quarter_duration

		var sample = 0.0

		# Melody - harsh square wave with tremolo
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_sixteenth, 0.5)
			# Add tremolo for urgency
			var tremolo = 0.7 + 0.3 * sin(t * 20 * TAU)
			var melody_wave = _square_wave(t * melody_freq) * 0.22 * tremolo
			# Detune for unsettling feel
			melody_wave += _square_wave(t * melody_freq * 1.01) * 0.08
			sample += melody_wave * melody_env

		# Bass - deep, rumbling
		var bass_freq = bass[quarter_idx]
		var bass_env = 0.85 + 0.15 * sin(t_in_quarter * PI)
		var bass_wave = _triangle_wave(t * bass_freq) * 0.4
		bass_wave += sin(t * bass_freq * 0.5 * TAU) * 0.25  # Sub bass
		sample += bass_wave * bass_env

		# Heartbeat-like kick - on every beat, heavy
		var beat_pos = fmod(t, beat_duration)
		if beat_pos < 0.06:
			var kick_env = pow(1.0 - beat_pos / 0.06, 1.5)
			var kick = sin(beat_pos * 50 * TAU) * kick_env * 0.6
			kick += sin(beat_pos * 25 * TAU) * kick_env * 0.4
			sample += kick

		# Anxious hi-hat on every 8th
		var eighth_pos = fmod(t, beat_duration / 2.0)
		if eighth_pos < 0.012:
			var hat_env = pow(1.0 - eighth_pos / 0.012, 3)
			var hat = randf_range(-0.18, 0.18) * hat_env
			sample += hat

		# Noise layer for tension
		var noise_level = 0.03 + 0.02 * sin(t * 2 * TAU)
		sample += randf_range(-noise_level, noise_level)

		# Hard clip for intensity
		sample = clamp(sample * 1.5, -0.98, 0.98)

		buffer.append(Vector2(sample, sample))

	return buffer


## Wave generators for music

func _square_wave(phase: float) -> float:
	"""Generate square wave (classic 8-bit sound)"""
	return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0


func _triangle_wave(phase: float) -> float:
	"""Generate triangle wave (softer 8-bit sound)"""
	var p = fmod(phase, 1.0)
	return 4.0 * abs(p - 0.5) - 1.0
