extends Node
class_name SoundManagerClass

## SoundManager - Central audio system for battle and UI sounds
## Generates procedural 8-bit style sounds and manages audio playback

# Audio players for different channels
var _ui_player: AudioStreamPlayer
var _battle_player: AudioStreamPlayer
var _ability_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer  # Second player for crossfade
var _crossfade_tween: Tween = null

# Music state
var _music_playing: bool = false
var _current_music: String = ""
const CROSSFADE_DURATION: float = 0.5  # Seconds for crossfade
var _music_base_db: float = -12.0  # Base volume for music

# Music cache - stores pre-generated AudioStreamWAV for each monster type
var _music_cache: Dictionary = {}

# Sound definitions - procedural parameters
const SOUNDS = {
	# UI Sounds
	"menu_move": {"freq": 800, "duration": 0.03, "type": "blip"},
	"menu_select": {"freq": 1200, "duration": 0.06, "type": "rising"},
	"menu_cancel": {"freq": 400, "duration": 0.08, "type": "falling"},
	"menu_expand": {"freq": 600, "duration": 0.05, "type": "chord"},
	"menu_open": {"freq": 500, "duration": 0.1, "type": "ascending"},  # Shop/Inn open
	"advance_queue": {"freq": 50, "duration": 0.4, "type": "explosion"},  # Lower, boomier
	"advance_undo": {"freq": 500, "duration": 0.06, "type": "falling"},
	"defer": {"freq": 300, "duration": 0.1, "type": "low_pulse"},
	"player_turn": {"freq": 880, "duration": 0.2, "type": "da_ding"},
	"autobattle_on": {"freq": 600, "duration": 0.15, "type": "ascending"},
	"autobattle_off": {"freq": 500, "duration": 0.15, "type": "descending"},
	"autobattle_open": {"freq": 440, "duration": 0.2, "type": "chord"},
	"autobattle_close": {"freq": 350, "duration": 0.15, "type": "falling"},
	"chest_open": {"freq": 700, "duration": 0.25, "type": "sparkle"},  # Treasure chest

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
	_music_player.volume_db = _music_base_db
	_music_player.bus = "Master"
	add_child(_music_player)

	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.name = "MusicPlayerB"
	_music_player_b.volume_db = -80.0  # Start silent
	_music_player_b.bus = "Master"
	add_child(_music_player_b)


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


func play_battle_scaled(sound_key: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	"""Play a battle sound with volume and pitch scaling for power-based effects"""
	if not SOUNDS.has(sound_key):
		return
	var params = SOUNDS[sound_key].duplicate()
	# Apply volume scaling
	params["volume_db"] = volume_db
	# Apply pitch scaling to frequency
	if params.has("freq"):
		params["freq"] = params["freq"] * pitch_scale
	_play_sound(_battle_player, params)


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
	var volume_db = params.get("volume_db", 0.0)

	var generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_rate

	player.stream = generator
	player.volume_db = volume_db
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
	"""Play a music track with crossfade transition"""
	if _current_music == track and _music_playing:
		return  # Already playing

	# Kill any existing crossfade
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_music_player_b.stop()

	# If music is playing, crossfade: move old stream to B player and fade out
	if _music_playing and _music_player.playing:
		_music_player_b.stream = _music_player.stream
		_music_player_b.volume_db = _music_player.volume_db
		_music_player_b.pitch_scale = _music_player.pitch_scale
		_music_player_b.play(_music_player.get_playback_position())
		_music_player.stop()

		# Fade out old track on B
		_crossfade_tween = create_tween()
		_crossfade_tween.tween_property(_music_player_b, "volume_db", -40.0, CROSSFADE_DURATION)
		_crossfade_tween.tween_callback(func(): _music_player_b.stop())

	_current_music = track

	match track:
		"title":
			_start_title_music()
		"battle":
			_start_battle_music()
		"boss":
			_start_boss_music()
		"boss_rat_king":
			_start_rat_king_music()
		"danger":
			_start_danger_music()
		"victory":
			_start_victory_music()
		"game_over":
			_start_game_over_music()
		# Monster-specific battle themes
		"battle_slime":
			_start_monster_music("slime")
		"battle_bat":
			_start_monster_music("bat")
		"battle_mushroom":
			_start_monster_music("mushroom")
		"battle_imp":
			_start_monster_music("imp")
		"battle_goblin":
			_start_monster_music("goblin")
		"battle_skeleton":
			_start_monster_music("skeleton")
		"battle_wolf":
			_start_monster_music("wolf")
		"battle_ghost":
			_start_monster_music("ghost")
		"battle_snake":
			_start_monster_music("snake")
		_:
			# Fallback: unknown battle tracks use generic battle music
			if track.begins_with("battle_"):
				var monster = track.substr(7)
				# Try stripping prefixes (cave_bat → bat, forest_spider → spider)
				var parts = monster.split("_")
				var base_name = parts[-1] if parts.size() > 1 else monster
				var base_track = "battle_" + base_name
				if base_track != track and base_track in ["battle_slime", "battle_bat", "battle_mushroom", "battle_imp", "battle_goblin", "battle_skeleton", "battle_wolf", "battle_ghost", "battle_snake"]:
					print("[MUSIC] Mapping %s → %s" % [track, base_track])
					play_music(base_track)
				else:
					print("[MUSIC] No specific theme for %s, using default battle music" % track)
					_start_battle_music()
			elif track.begins_with("boss"):
				print("[MUSIC] Unknown boss track %s, using generic boss music" % track)
				_start_boss_music()
			else:
				push_warning("Unknown music track: %s" % track)


func stop_music() -> void:
	"""Stop currently playing music"""
	_music_playing = false
	_current_music = ""
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	if _music_player:
		_music_player.stop()
	if _music_player_b:
		_music_player_b.stop()


func is_music_playing() -> bool:
	return _music_playing


## Danger intensity system - modulates music when party is hurt
var _danger_intensity: float = 0.0  # 0.0 = safe, 1.0 = critical
var _danger_tween: Tween = null

func set_danger_intensity(intensity: float) -> void:
	"""Set danger intensity (0.0 = safe, 1.0 = critical)
	   This affects music pitch, tempo feel, and adds urgency"""
	var new_intensity = clamp(intensity, 0.0, 1.0)

	# Skip if no change
	if abs(new_intensity - _danger_intensity) < 0.05:
		return

	# Smooth transition
	if _danger_tween and _danger_tween.is_valid():
		_danger_tween.kill()

	_danger_tween = create_tween()
	_danger_tween.tween_method(_apply_danger_intensity, _danger_intensity, new_intensity, 0.5)


func _apply_danger_intensity(intensity: float) -> void:
	"""Apply danger intensity to music playback"""
	_danger_intensity = intensity

	if not _music_player:
		return

	# Pitch shift: normal (1.0) to slightly higher (1.15) as danger increases
	# Higher pitch = more urgent feeling
	var pitch_scale = 1.0 + intensity * 0.15
	_music_player.pitch_scale = pitch_scale

	# Volume boost at high danger (slightly louder, more in-your-face)
	var volume_boost = intensity * 3.0  # Up to +3dB at max danger
	_music_player.volume_db = -12.0 + volume_boost


func get_danger_intensity() -> float:
	return _danger_intensity


func reset_danger() -> void:
	"""Reset danger to safe level"""
	set_danger_intensity(0.0)
	if _music_player:
		_music_player.pitch_scale = 1.0
		_music_player.volume_db = -12.0


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
	"""Play victory fanfare intro then loop into 80s rock victory theme"""
	_music_playing = true

	var sample_rate = 22050
	var bpm = 140.0
	var beat_duration = 60.0 / bpm

	# Fanfare intro: 2 seconds (non-looping)
	var intro_duration = 2.0
	var intro_buffer = _generate_victory_fanfare(sample_rate, intro_duration)

	# Rock loop: 8 bars at 140 BPM
	var bars = 8
	var loop_duration = beat_duration * 4 * bars
	var loop_buffer = _generate_victory_rock_loop(sample_rate, loop_duration, bpm)

	# Combine intro + loop
	var full_buffer = PackedVector2Array()
	full_buffer.append_array(intro_buffer)
	full_buffer.append_array(loop_buffer)

	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = intro_buffer.size()  # Loop starts after fanfare
	wav.loop_end = full_buffer.size()

	var data = PackedByteArray()
	for frame in full_buffer:
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
	"""Generate classic JRPG victory fanfare (intro)"""
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

		# Arpeggio phase — clean square wave per note
		if t < chord_start:
			for j in range(4):
				if t >= note_times[j]:
					var note_t = t - note_times[j]
					var env = pow(max(0, 1.0 - note_t / 0.5), 0.5)
					sample += _square_wave(note_t * notes[j]) * env * 0.25

		# Sustained chord phase — triangle only for smooth sustain
		else:
			var chord_t = t - chord_start
			var env = pow(max(0, 1.0 - chord_t / (duration - chord_start)), 0.3)
			for note in notes:
				sample += _triangle_wave(chord_t * note) * env * 0.18

		sample = clamp(sample, -0.9, 0.9)
		buffer.append(Vector2(sample, sample))

	return buffer


func _generate_victory_rock_loop(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate 80s rock victory loop — power chords, driving drums, synth lead"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm
	var bar_duration = beat_duration * 4

	# Notes (A major key — triumphant 80s rock)
	const A2 = 110.0
	const B2 = 123.47
	const D3 = 146.83
	const E3 = 164.81
	const A3 = 220.0
	const B3 = 246.94
	const Cs4 = 277.18
	const D4 = 293.66
	const E4 = 329.63
	const Fs4 = 369.99
	const A4 = 440.0
	const B4 = 493.88
	const Cs5 = 554.37
	const E5 = 659.25

	# Power chord progression (root + fifth): A - D - E - A | A - D - E - D
	var chord_roots = [A2, D3, E3, A2, A2, D3, E3, D3]
	var chord_fifths = [E3, A3, B3, E3, E3, A3, B3, A3]

	# Lead melody over 8 bars (notes per beat, 32 beats total)
	# Catchy pentatonic riff with 80s synth feel
	var lead_notes = [
		A4, Cs5, E5, Cs5,   B4, A4, Fs4, E4,   # Bar 1-2: ascending riff
		A4, B4, Cs5, E5,    Cs5, B4, A4, Fs4,   # Bar 3-4: variation
		E4, Fs4, A4, B4,    Cs5, B4, A4, E4,    # Bar 5-6: lower register
		Fs4, A4, B4, Cs5,   E5, Cs5, B4, A4,    # Bar 7-8: build to loop point
	]

	for i in range(samples):
		var t = float(i) / rate
		var beat = t / beat_duration
		var bar = int(t / bar_duration) % 8
		var beat_in_bar = fmod(t, bar_duration) / beat_duration
		var sample_l = 0.0
		var sample_r = 0.0

		# === DRUMS ===
		var beat_pos = fmod(t, beat_duration)
		var sixteenth = fmod(t, beat_duration / 4.0)

		# Kick on beats 1 and 3
		if (int(beat) % 4 == 0 or int(beat) % 4 == 2) and beat_pos < 0.08:
			var kick_env = 1.0 - beat_pos / 0.08
			var kick_freq = 80.0 * (1.0 + kick_env * 2.0)
			var kick = sin(beat_pos * kick_freq * TAU) * kick_env * 0.35
			sample_l += kick
			sample_r += kick

		# Snare on beats 2 and 4 (80s gated reverb snare!)
		if (int(beat) % 4 == 1 or int(beat) % 4 == 3) and beat_pos < 0.12:
			var snare_env = pow(1.0 - beat_pos / 0.12, 0.4)
			var noise = (randf() * 2.0 - 1.0)
			var snare_tone = sin(beat_pos * 200.0 * TAU) * 0.3
			var snare = (noise * 0.3 + snare_tone) * snare_env * 0.28
			sample_l += snare
			sample_r += snare

		# Hi-hat on every eighth note
		if fmod(t, beat_duration / 2.0) < 0.02:
			var hat_pos = fmod(t, beat_duration / 2.0)
			var hat_env = 1.0 - hat_pos / 0.02
			var hat = (randf() * 2.0 - 1.0) * hat_env * 0.1
			sample_l += hat
			sample_r += hat

		# === BASS (power chord root, 80s distorted) ===
		var root = chord_roots[bar]
		var bass_phase = t * root
		var bass = _square_wave(bass_phase) * 0.12
		bass += _triangle_wave(bass_phase * 0.5) * 0.08  # Sub octave
		# Eighth note pulse pattern
		var eighth_env = 1.0 - fmod(t, beat_duration / 2.0) / (beat_duration / 2.0) * 0.4
		bass *= eighth_env
		sample_l += bass
		sample_r += bass

		# === POWER CHORDS (distorted rhythm guitar, panned) ===
		var fifth = chord_fifths[bar]
		var chord_env = 0.8
		# Palm mute pattern: short on off-beats, sustained on downbeats
		if int(beat_in_bar * 2) % 2 == 0:
			chord_env = 0.9
		else:
			var off_t = fmod(t, beat_duration / 2.0)
			chord_env = max(0.0, 0.9 - off_t * 4.0)

		var guitar_l = _pulse_wave(t * root * 2, 0.3) * chord_env * 0.07
		guitar_l += _pulse_wave(t * fifth * 2, 0.35) * chord_env * 0.06
		guitar_l += _square_wave(t * root * 4) * chord_env * 0.03  # Octave up

		var guitar_r = _pulse_wave(t * root * 2 + 0.01, 0.35) * chord_env * 0.07
		guitar_r += _pulse_wave(t * fifth * 2 + 0.01, 0.3) * chord_env * 0.06
		guitar_r += _square_wave(t * root * 4 + 0.01) * chord_env * 0.03

		sample_l += guitar_l
		sample_r += guitar_r

		# === SYNTH LEAD (80s saw-style with vibrato) ===
		var lead_idx = int(beat) % 32
		var lead_note = lead_notes[lead_idx]
		var lead_t = fmod(t, beat_duration)
		# Note envelope: sharp attack, sustain, short release at end of beat
		var lead_env = min(1.0, lead_t * 20.0)  # Fast attack
		lead_env *= max(0.0, 1.0 - max(0.0, lead_t - beat_duration * 0.8) / (beat_duration * 0.2))
		# Vibrato (classic 80s)
		var vibrato = sin(t * 5.5 * TAU) * 0.008
		var lead_phase = t * lead_note * (1.0 + vibrato)
		var lead = _pulse_wave(lead_phase, 0.4) * lead_env * 0.1
		lead += _triangle_wave(lead_phase) * lead_env * 0.06
		# Pan lead slightly right
		sample_l += lead * 0.7
		sample_r += lead * 1.0

		# === MIX ===
		sample_l = clamp(sample_l, -0.95, 0.95)
		sample_r = clamp(sample_r, -0.95, 0.95)
		buffer.append(Vector2(sample_l, sample_r))

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


## Rat King Music - Sneaky, dodgy theme for the rat boss

func _start_rat_king_music() -> void:
	"""Generate and start looping sneaky rat king boss music"""
	_music_playing = true

	# Generate music buffer (16 bars at 140 BPM - sneaky, slightly faster than normal)
	var sample_rate = 22050
	var bpm = 140.0
	var beats_per_bar = 4
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * beats_per_bar * bars

	_music_buffer = _generate_rat_king_music_buffer(sample_rate, total_duration, bpm)

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


func _generate_rat_king_music_buffer(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate sneaky rat king theme - E minor, staccato, dodgy feel"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# Notes in E minor (sneaky, mysterious)
	const NOTE_E2 = 82.41   # Bass
	const NOTE_B2 = 123.47
	const NOTE_E3 = 164.81
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_B3 = 246.94
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_Fs4 = 369.99  # F#
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88
	const NOTE_C5 = 523.25
	const NOTE_D5 = 587.33
	const NOTE_E5 = 659.25

	# Section A - Sneaky intro with staccato notes (bars 1-4)
	var melody_a = [
		NOTE_E4, 0, 0, NOTE_E4, 0, 0, NOTE_G4, 0,        # Bar 1 - tiptoeing
		NOTE_Fs4, 0, 0, 0, NOTE_E4, 0, 0, 0,
		NOTE_B3, 0, 0, NOTE_B3, 0, 0, NOTE_D4, 0,        # Bar 2
		NOTE_C4, 0, 0, 0, NOTE_B3, 0, 0, 0,
		NOTE_E4, 0, NOTE_G4, 0, NOTE_Fs4, 0, NOTE_E4, 0, # Bar 3 - quick scurry
		NOTE_D4, 0, NOTE_E4, 0, NOTE_Fs4, 0, NOTE_G4, 0,
		NOTE_A4, 0, 0, NOTE_G4, 0, NOTE_Fs4, 0, NOTE_E4, # Bar 4
		0, 0, 0, 0, NOTE_E4, 0, NOTE_D4, 0,
	]

	# Section B - More aggressive, the rat reveals himself (bars 5-8)
	var melody_b = [
		NOTE_E4, NOTE_E4, 0, NOTE_E4, NOTE_E4, 0, NOTE_G4, 0, # Bar 5 - chittering
		NOTE_A4, 0, NOTE_G4, 0, NOTE_Fs4, 0, NOTE_E4, 0,
		NOTE_B4, 0, 0, NOTE_A4, 0, 0, NOTE_G4, 0,        # Bar 6
		NOTE_Fs4, 0, NOTE_G4, 0, NOTE_A4, 0, NOTE_B4, 0,
		NOTE_E5, 0, NOTE_D5, 0, NOTE_C5, 0, NOTE_B4, 0,  # Bar 7 - angry squeak
		NOTE_A4, 0, NOTE_G4, 0, NOTE_Fs4, 0, NOTE_E4, 0,
		NOTE_E4, NOTE_Fs4, NOTE_G4, NOTE_A4, NOTE_B4, 0, 0, 0, # Bar 8
		NOTE_A4, NOTE_G4, NOTE_Fs4, NOTE_E4, NOTE_D4, 0, 0, 0,
	]

	# Section C - Royal pomposity (the crown) (bars 9-12)
	var melody_c = [
		NOTE_B4, 0, NOTE_B4, 0, NOTE_B4, NOTE_A4, NOTE_G4, 0, # Bar 9 - majestic attempt
		NOTE_Fs4, 0, NOTE_G4, 0, NOTE_A4, 0, NOTE_B4, 0,
		NOTE_E5, 0, 0, 0, NOTE_D5, 0, 0, 0,             # Bar 10 - holding note
		NOTE_C5, 0, NOTE_B4, 0, NOTE_A4, 0, NOTE_G4, 0,
		NOTE_Fs4, NOTE_G4, NOTE_A4, NOTE_B4, NOTE_C5, NOTE_B4, NOTE_A4, NOTE_G4, # Bar 11
		NOTE_Fs4, NOTE_E4, NOTE_D4, NOTE_C4, NOTE_B3, 0, 0, 0,
		NOTE_E4, 0, 0, 0, NOTE_E4, 0, NOTE_Fs4, NOTE_G4, # Bar 12
		NOTE_A4, NOTE_B4, NOTE_A4, NOTE_G4, NOTE_Fs4, 0, NOTE_E4, 0,
	]

	# Section D - Dodging and weaving (bars 13-16)
	var melody_d = [
		NOTE_E4, 0, NOTE_G4, 0, NOTE_E4, 0, NOTE_B3, 0,  # Bar 13 - erratic
		NOTE_E4, 0, NOTE_A4, 0, NOTE_E4, 0, NOTE_D4, 0,
		NOTE_C4, NOTE_D4, NOTE_E4, NOTE_Fs4, NOTE_G4, NOTE_A4, NOTE_B4, NOTE_C5, # Bar 14
		NOTE_B4, NOTE_A4, NOTE_G4, NOTE_Fs4, NOTE_E4, NOTE_D4, NOTE_C4, NOTE_B3,
		NOTE_E4, 0, 0, NOTE_E4, 0, 0, NOTE_E4, NOTE_E4,  # Bar 15 - building
		NOTE_Fs4, NOTE_Fs4, NOTE_G4, NOTE_G4, NOTE_A4, NOTE_A4, NOTE_B4, 0,
		NOTE_E5, 0, 0, 0, 0, 0, NOTE_E4, NOTE_E4,        # Bar 16 - resolve
		NOTE_E4, 0, 0, 0, 0, 0, 0, 0,
	]

	# Bass line - stalking, predatory feel
	var bass_pattern = [
		NOTE_E2, 0, NOTE_E2, 0, NOTE_E3, 0, NOTE_E2, 0,
		NOTE_B2, 0, NOTE_B2, 0, NOTE_E3, 0, NOTE_B2, 0,
	]

	for i in range(samples):
		var t = float(i) / rate
		var sample = 0.0

		# Position within the beat for drums
		var beat_pos = fmod(t, beat_duration)
		var current_beat = int(t / beat_duration)
		var bar = current_beat / 8  # 8 melody notes per bar (16th notes effectively)

		# Determine which section we're in
		var melody_note = 0.0
		var section_beat = current_beat % 64  # 64 beats per section (4 bars of 16)

		if bar < 4:
			if section_beat < melody_a.size():
				melody_note = melody_a[section_beat]
		elif bar < 8:
			if section_beat < melody_b.size():
				melody_note = melody_b[section_beat]
		elif bar < 12:
			if section_beat < melody_c.size():
				melody_note = melody_c[section_beat]
		else:
			if section_beat < melody_d.size():
				melody_note = melody_d[section_beat]

		# Staccato melody - short, punchy notes
		if melody_note > 0:
			var note_t = beat_pos
			# Very short envelope for staccato effect
			var staccato_length = beat_duration * 0.4
			if note_t < staccato_length:
				var env = pow(1.0 - note_t / staccato_length, 2.5)
				# Square wave with slight detuning for sneaky feel
				var sq = sign(sin(t * melody_note * TAU)) * 0.15 * env
				# Add slight vibrato for creepiness
				var vibrato = sin(t * 6.0) * 3.0
				sq += sign(sin(t * (melody_note + vibrato) * TAU)) * 0.08 * env
				sample += sq

		# Sneaky bass - pizzicato style
		var bass_beat = current_beat % 16
		if bass_beat < bass_pattern.size():
			var bass_freq = bass_pattern[bass_beat]
			if bass_freq > 0:
				var bass_t = beat_pos
				var bass_env = pow(1.0 - bass_t / (beat_duration * 0.5), 2) if bass_t < beat_duration * 0.5 else 0.0
				# Triangle wave for plucky bass
				var bass = (2.0 * abs(2.0 * fmod(t * bass_freq, 1.0) - 1.0) - 1.0) * 0.2 * bass_env
				sample += bass

		# Light, shuffling drums - more hi-hat focused
		# Kick on 1 and 3, but lighter
		if current_beat % 4 in [0, 2] and beat_pos < 0.03:
			var kick_env = pow(1.0 - beat_pos / 0.03, 2)
			var kick = sin(beat_pos * 55 * TAU) * kick_env * 0.25
			sample += kick

		# Snare rim click on 2 and 4 (quiet, sneaky)
		if current_beat % 4 in [1, 3] and beat_pos < 0.02:
			var rim_env = pow(1.0 - beat_pos / 0.02, 3)
			var rim = sin(beat_pos * 800 * TAU) * rim_env * 0.15
			sample += rim

		# Rapid hi-hats (16th notes, very quiet for tiptoeing feel)
		var sixteenth_pos = fmod(t, beat_duration / 4.0)
		if sixteenth_pos < 0.008:
			var hat_env = pow(1.0 - sixteenth_pos / 0.008, 4)
			var hat = randf_range(-0.08, 0.08) * hat_env
			sample += hat

		# Occasional shaker/scratch sound (rat scurrying)
		if current_beat % 8 == 3 and beat_pos > beat_duration * 0.5 and beat_pos < beat_duration * 0.7:
			var scratch_t = (beat_pos - beat_duration * 0.5) / (beat_duration * 0.2)
			var scratch = randf_range(-0.1, 0.1) * (1.0 - scratch_t)
			sample += scratch

		# Soft clip
		sample = clamp(sample * 1.2, -0.85, 0.85)

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


func _pulse_wave(phase: float, duty: float = 0.25) -> float:
	"""Generate pulse wave with variable duty cycle (softer than square)"""
	return 1.0 if fmod(phase, 1.0) < duty else -1.0


func _soft_square(phase: float) -> float:
	"""Square wave with rounded edges (less harsh)"""
	var p = fmod(phase, 1.0)
	# Use tanh to round the edges
	return tanh(sin(p * TAU) * 3.0)


func _sine_wave(phase: float) -> float:
	"""Pure sine wave (smoothest, least harsh)"""
	return sin(fmod(phase, 1.0) * TAU)


## Volume control

func set_music_volume(normalized: float) -> void:
	"""Set music volume (0.0 to 1.0)"""
	var db = linear_to_db(clamp(normalized, 0.0, 1.0)) if normalized > 0.01 else -80.0
	_music_base_db = db
	_music_player.volume_db = db


func set_sfx_volume(normalized: float) -> void:
	"""Set SFX volume (0.0 to 1.0) — applies to UI, battle, and ability players"""
	var db = linear_to_db(clamp(normalized, 0.0, 1.0)) if normalized > 0.01 else -80.0
	_ui_player.volume_db = db
	_battle_player.volume_db = db
	_ability_player.volume_db = db


func _warm_wave(phase: float) -> float:
	"""Warm analog-style wave (sine + slight harmonics)"""
	var p = fmod(phase, 1.0)
	return sin(p * TAU) * 0.7 + sin(p * TAU * 2) * 0.2 + sin(p * TAU * 3) * 0.1


## Monster-Specific Battle Music

# Monster music parameters - each monster has unique feel
# 24 bars = 3 sections of 8 bars each (A-B-C structure, fast generation)
const MONSTER_MUSIC_PARAMS = {
	"slime": {
		"bpm": 128, "bars": 24, "key": "C_major",
		"style": "bouncy", "bass_style": "bounce"
	},
	"bat": {
		"bpm": 170, "bars": 24, "key": "D_minor",
		"style": "frantic", "bass_style": "fast"
	},
	"mushroom": {
		"bpm": 90, "bars": 24, "key": "E_minor",
		"style": "creepy", "bass_style": "drone"
	},
	"imp": {
		"bpm": 160, "bars": 24, "key": "F_minor",
		"style": "chaotic", "bass_style": "chromatic"
	},
	"goblin": {
		"bpm": 140, "bars": 24, "key": "A_minor",
		"style": "tribal", "bass_style": "drums"
	},
	"skeleton": {
		"bpm": 120, "bars": 24, "key": "B_minor",
		"style": "spooky", "bass_style": "staccato"
	},
	"wolf": {
		"bpm": 150, "bars": 24, "key": "E_minor",
		"style": "tense", "bass_style": "prowl"
	},
	"ghost": {
		"bpm": 100, "bars": 24, "key": "G_minor",
		"style": "ethereal", "bass_style": "floating"
	},
	"snake": {
		"bpm": 135, "bars": 24, "key": "C_minor",
		"style": "slither", "bass_style": "serpent"
	}
}

func _start_monster_music(monster_type: String) -> void:
	"""Start monster-specific battle music (uses cache for instant playback)"""
	_music_playing = true

	# Check cache first
	if _music_cache.has(monster_type):
		_music_player.stream = _music_cache[monster_type]
		_music_player.play()
		return

	# Generate and cache if not found
	var wav = _generate_and_cache_music(monster_type)
	_music_player.stream = wav
	_music_player.play()


func _generate_and_cache_music(monster_type: String) -> AudioStreamWAV:
	"""Generate music for a monster type and cache it"""
	var params = MONSTER_MUSIC_PARAMS.get(monster_type, MONSTER_MUSIC_PARAMS["slime"])
	var sample_rate = 16000  # Lower rate = faster generation, fine for 8-bit style
	var bpm = float(params["bpm"])
	var bars = params["bars"]
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	var buffer = _generate_monster_music_buffer(sample_rate, total_duration, bpm, monster_type)

	# Create looping audio stream
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buffer.size()

	var data = PackedByteArray()
	for frame in buffer:
		var left = int(clamp(frame.x, -1.0, 1.0) * 32767)
		var right = int(clamp(frame.y, -1.0, 1.0) * 32767)
		data.append(left & 0xFF)
		data.append((left >> 8) & 0xFF)
		data.append(right & 0xFF)
		data.append((right >> 8) & 0xFF)

	wav.data = data
	_music_cache[monster_type] = wav
	return wav


func _generate_monster_music_buffer(rate: int, duration: float, bpm: float, monster_type: String) -> PackedVector2Array:
	"""Generate battle music with monster-specific character - now with counter-melody and dynamics"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm
	var params = MONSTER_MUSIC_PARAMS.get(monster_type, MONSTER_MUSIC_PARAMS["slime"])

	# Get melody, counter-melody, and bass based on monster type
	var melody = _get_monster_melody(monster_type)
	var counter = _get_monster_counter_melody(monster_type)
	var bass_notes = _get_monster_bass(monster_type)
	var total_bars = params["bars"]

	for i in range(samples):
		var t = float(i) / rate
		var beat_pos = fmod(t / beat_duration, 4.0)
		var bar = int(t / (beat_duration * 4)) % total_bars
		var section = bar / 8  # Which 8-bar section (0-5)
		var sample = 0.0

		# Dynamic volume based on section (build and release)
		var section_dynamics = [0.85, 0.9, 1.0, 0.95, 1.0, 0.9]  # Subtle dynamics
		var dyn = section_dynamics[section % 6] if section < 6 else 0.9

		# Melody (sixteenth notes, style-dependent)
		var melody_idx = (bar * 16 + int(beat_pos * 4)) % melody.size()
		var melody_note = melody[melody_idx]
		if melody_note > 0:
			var note_phase = fmod(t * melody_note, 1.0)
			var wave = _get_monster_wave(note_phase, params["style"])
			var env = _get_monster_envelope(beat_pos, params["style"])
			sample += wave * 0.28 * env * dyn

		# Counter-melody (eighth notes, comes in on section 2+)
		if section >= 1 and counter.size() > 0:
			var counter_idx = (bar * 8 + int(beat_pos * 2)) % counter.size()
			var counter_note = counter[counter_idx]
			if counter_note > 0:
				var counter_phase = fmod(t * counter_note, 1.0)
				var counter_wave = _triangle_wave(counter_phase)
				var counter_env = 0.7 + 0.3 * (1.0 - fmod(beat_pos * 2, 1.0))
				# Pan counter-melody slightly for stereo width
				var counter_vol = 0.15 * counter_env * (dyn * 0.8)
				sample += counter_wave * counter_vol

		# Bass (quarter notes) - with occasional octave jumps
		var bass_idx = (bar * 4 + int(beat_pos)) % bass_notes.size()
		var bass_note = bass_notes[bass_idx]
		if bass_note > 0:
			# Octave variation on strong beats in later sections
			var bass_freq = bass_note
			if section >= 3 and int(beat_pos) == 0 and bar % 4 == 0:
				bass_freq *= 2.0  # Octave up on downbeat every 4 bars
			var bass_phase = fmod(t * bass_freq, 1.0)
			var bass_wave = _soft_square(bass_phase) * 0.6 + _triangle_wave(bass_phase) * 0.4
			var bass_env = _get_bass_envelope(beat_pos, params["bass_style"])
			sample += bass_wave * 0.22 * bass_env * dyn

		# Drums (style-dependent) with fills
		var drum_vol = 0.25 * dyn
		# Add fills at end of sections
		if bar % 8 == 7 and beat_pos >= 3.0:
			drum_vol *= 1.3  # Louder fill
		sample += _get_monster_drums(beat_pos, t, params["style"]) * drum_vol

		# Soft clip for warmth
		sample = clamp(sample * 1.15, -0.92, 0.92)
		buffer.append(Vector2(sample, sample))

	return buffer


func _get_monster_wave(phase: float, style: String) -> float:
	"""Get waveform based on monster style - using softer tones"""
	match style:
		"bouncy":
			# Warm, rounded sound for slimes
			return _warm_wave(phase) * 0.7 + _triangle_wave(phase) * 0.3
		"frantic":
			# Fast but not harsh - pulse wave with harmonics
			return _soft_square(phase) * 0.6 + _sine_wave(phase * 2) * 0.3 + _triangle_wave(phase) * 0.1
		"chaotic":
			# Unpredictable but still musical
			return _pulse_wave(phase, 0.35) * 0.5 + _warm_wave(phase) * 0.4 + _triangle_wave(phase * 1.5) * 0.1
		"creepy":
			# Unsettling but smooth
			return _sine_wave(phase) * 0.6 + _triangle_wave(phase * 1.5) * 0.3 + _pulse_wave(phase * 0.5, 0.2) * 0.1
		"spooky":
			# Hollow, ghostly tone
			return _triangle_wave(phase) * 0.5 + _sine_wave(phase) * 0.4 + _pulse_wave(phase * 2, 0.15) * 0.1
		"ethereal":
			# Pure, floating - mostly sine
			return _sine_wave(phase) * 0.7 + _sine_wave(phase * 1.5) * 0.2 + _triangle_wave(phase * 0.5) * 0.1
		"tribal":
			# Punchy but warm
			return _warm_wave(phase) * 0.5 + _soft_square(phase) * 0.3 + _triangle_wave(phase) * 0.2
		"tense":
			# Driving but not piercing
			return _soft_square(phase) * 0.5 + _triangle_wave(phase) * 0.3 + _sine_wave(phase * 2) * 0.2
		"slither":
			# Wavering, serpentine
			var bend = sin(phase * TAU * 0.5) * 0.15
			return _warm_wave(phase + bend) * 0.6 + _sine_wave(phase * 1.5 + bend) * 0.4
		_:
			return _warm_wave(phase)


func _get_monster_envelope(beat_pos: float, style: String) -> float:
	"""Get amplitude envelope based on monster style"""
	var sub_beat = fmod(beat_pos * 4, 1.0)
	match style:
		"bouncy":
			return 1.0 - sub_beat * 0.5  # Quick decay, bouncy feel
		"frantic", "chaotic":
			return 0.7 + randf() * 0.3  # Erratic
		"creepy":
			return 0.5 + sin(beat_pos * TAU) * 0.3  # Wavering
		"spooky":
			return 1.0 - sub_beat * 0.7  # Staccato
		"ethereal":
			return 0.6 + sin(beat_pos * TAU * 0.5) * 0.3  # Floating
		"tribal":
			return 1.0 if sub_beat < 0.3 else 0.4  # Punchy
		"tense":
			return 0.8 - sub_beat * 0.3
		"slither":
			return 0.7 + sin(beat_pos * TAU * 2) * 0.2  # Undulating
		_:
			return 1.0 - sub_beat * 0.5


func _get_bass_envelope(beat_pos: float, bass_style: String) -> float:
	"""Get bass envelope based on style"""
	var sub_beat = fmod(beat_pos, 1.0)
	match bass_style:
		"bounce":
			return 1.0 if sub_beat < 0.25 else 0.3  # Short punchy
		"fast":
			return 0.8 - sub_beat * 0.4
		"drone":
			return 0.6 + sin(beat_pos * TAU * 0.25) * 0.2  # Sustained
		"chromatic":
			return 0.7 + randf() * 0.2
		"drums":
			return 1.0 if sub_beat < 0.15 else 0.2  # Very punchy
		"staccato":
			return 1.0 if sub_beat < 0.1 else 0.0  # Bone rattles
		"prowl":
			return 0.5 + (1.0 - sub_beat) * 0.4  # Stalking
		"floating":
			return 0.4 + sin(beat_pos * TAU) * 0.2  # Ethereal bass
		"serpent":
			return 0.6 - sub_beat * 0.2 + sin(sub_beat * TAU * 3) * 0.1
		_:
			return 1.0 - sub_beat * 0.5


func _get_monster_drums(beat_pos: float, t: float, style: String) -> float:
	"""Get drum pattern based on monster style - rich, varied patterns"""
	var sub_beat = fmod(beat_pos, 1.0)
	var beat_num = int(beat_pos)
	var bar_beat = beat_num % 4  # Which beat in the 4-beat bar
	var sample = 0.0

	# Helper for kick drum with pitch sweep
	var kick_time = sub_beat
	var kick_pitch = 150.0 * pow(0.3, kick_time * 20)  # Pitch drops quickly
	var kick_env = pow(max(0, 1.0 - kick_time * 15), 2)

	# Helper for snare
	var snare_time = sub_beat
	var snare_env = pow(max(0, 1.0 - snare_time * 12), 1.5)

	# Helper for hi-hat (16th note position)
	var sixteenth = fmod(beat_pos * 4, 1.0)
	var hat_env = pow(max(0, 1.0 - sixteenth * 25), 3)

	match style:
		"bouncy":
			# Funky slime groove - kick on 1 and the "and" of 2, snare on 2 and 4
			var kick_hits = [0, 1.5]  # Beat 1 and "and" of 2
			for hit in kick_hits:
				if abs(beat_pos - int(beat_pos / 4) * 4 - hit) < 0.08:
					sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.7
					sample += sin(kick_time * kick_pitch * 0.5 * TAU) * kick_env * 0.4  # Sub
			# Snare on 2 and 4
			if bar_beat in [1, 3] and sub_beat < 0.1:
				sample += randf_range(-0.5, 0.5) * snare_env
				sample += sin(snare_time * 200 * TAU) * snare_env * 0.3
			# Bouncy hi-hats - accented on off-beats
			if sixteenth < 0.08:
				var hat_accent = 0.3 if int(beat_pos * 4) % 2 == 1 else 0.15
				sample += randf_range(-hat_accent, hat_accent) * hat_env

		"frantic":
			# Breakbeat-style for bats - fast, syncopated
			# Kick on 1, ghost kick on "e" of 2, kick on 3
			var kick_pattern = [0.0, 1.25, 2.0, 3.5]
			for hit in kick_pattern:
				if abs(fmod(beat_pos, 4.0) - hit) < 0.06:
					sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.8
					sample += sin(kick_time * kick_pitch * 0.5 * TAU) * kick_env * 0.3
			# Snare on 2 and 4 with ghost notes
			if bar_beat in [1, 3] and sub_beat < 0.08:
				sample += randf_range(-0.6, 0.6) * snare_env
				sample += sin(snare_time * 180 * TAU) * snare_env * 0.25
			# Ghost snare on "a" of 1 and 3
			if bar_beat in [0, 2] and sub_beat > 0.7 and sub_beat < 0.85:
				sample += randf_range(-0.2, 0.2) * pow(1.0 - (sub_beat - 0.7) * 7, 2)
			# 16th note hi-hats with accents
			if sixteenth < 0.05:
				var accent = 0.4 if int(beat_pos * 4) % 4 == 0 else 0.2
				sample += randf_range(-accent, accent) * hat_env

		"creepy":
			# Sparse, unsettling mushroom beat - irregular timing
			# Deep kick only on beat 1
			if bar_beat == 0 and sub_beat < 0.12:
				sample += sin(kick_time * kick_pitch * 0.8 * TAU) * kick_env * 0.6
				sample += sin(kick_time * 40 * TAU) * kick_env * 0.5  # Very low sub
			# Weird off-beat hit on the "and" of 3
			if abs(fmod(beat_pos, 4.0) - 2.5) < 0.08:
				sample += randf_range(-0.3, 0.3) * snare_env * 0.7
			# Ambient crackle
			sample += randf_range(-0.03, 0.03) * (0.5 + sin(t * 0.3) * 0.5)
			# Occasional shaker on 8ths
			if fmod(beat_pos * 2, 1.0) < 0.04 and randf() < 0.6:
				sample += randf_range(-0.12, 0.12) * pow(1.0 - fmod(beat_pos * 2, 1.0) * 25, 2)

		"chaotic":
			# Imp chaos - semi-random but groovy
			# Base kick on 1 and 3
			if bar_beat in [0, 2] and sub_beat < 0.07:
				sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.75
				sample += sin(kick_time * kick_pitch * 0.5 * TAU) * kick_env * 0.35
			# Random extra kicks
			if randf() < 0.08 and sub_beat < 0.05:
				sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.4
			# Snare on 2 and 4 with random flams
			if bar_beat in [1, 3] and sub_beat < 0.09:
				sample += randf_range(-0.55, 0.55) * snare_env
			# Random percussion hits
			if randf() < 0.12:
				sample += randf_range(-0.25, 0.25) * hat_env
			# Chaotic hi-hats
			if sixteenth < 0.06:
				sample += randf_range(-0.25, 0.25) * hat_env * (0.5 + randf() * 0.5)

		"tribal":
			# Heavy goblin war drums - four-on-floor with toms
			# Kick every beat with extra punch
			if sub_beat < 0.08:
				sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.9
				sample += sin(kick_time * kick_pitch * 0.5 * TAU) * kick_env * 0.5
				sample += sin(kick_time * 60 * TAU) * kick_env * 0.4  # Sub boom
			# Heavy snare on 2 and 4
			if bar_beat in [1, 3] and sub_beat < 0.1:
				sample += randf_range(-0.7, 0.7) * snare_env
				sample += sin(snare_time * 170 * TAU) * snare_env * 0.35
			# Tom fills - descending on beat 4
			if bar_beat == 3:
				var tom_freqs = [200.0, 150.0, 120.0, 90.0]
				var tom_idx = int(sub_beat * 4) % 4
				if fmod(sub_beat * 4, 1.0) < 0.15:
					var tom_t = fmod(sub_beat * 4, 1.0)
					var tom_env = pow(1.0 - tom_t * 7, 2)
					sample += sin(tom_t * tom_freqs[tom_idx] * TAU) * tom_env * 0.5
			# 8th note shaker
			if fmod(beat_pos * 2, 1.0) < 0.04:
				sample += randf_range(-0.2, 0.2) * pow(1.0 - fmod(beat_pos * 2, 1.0) * 25, 2)

		"spooky":
			# Skeleton bone rattles - sparse with rattling fills
			# Hollow kick on 1 and 3
			if bar_beat in [0, 2] and sub_beat < 0.06:
				sample += sin(kick_time * 100 * TAU) * kick_env * 0.5
				sample += sin(kick_time * 50 * TAU) * kick_env * 0.3
			# Rim shot on 2 and 4
			if bar_beat in [1, 3] and sub_beat < 0.04:
				sample += sin(snare_time * 400 * TAU) * snare_env * 0.4
			# Bone rattles - 16th note fills
			if sixteenth < 0.06:
				var rattle_vol = 0.2 if int(beat_pos * 4) % 2 == 0 else 0.35
				sample += randf_range(-rattle_vol, rattle_vol) * hat_env
			# Occasional longer rattle on beat 4
			if bar_beat == 3 and sub_beat > 0.5:
				sample += randf_range(-0.15, 0.15) * (1.0 - (sub_beat - 0.5) * 2)

		"tense":
			# Wolf hunting groove - driving and relentless
			# Kick on every beat, extra hit on "and" of 4
			if sub_beat < 0.06:
				sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.8
				sample += sin(kick_time * kick_pitch * 0.5 * TAU) * kick_env * 0.4
			if abs(fmod(beat_pos, 4.0) - 3.5) < 0.06:
				sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.6
			# Snare on 2 and 4 with buildup
			if bar_beat in [1, 3] and sub_beat < 0.08:
				sample += randf_range(-0.6, 0.6) * snare_env
				sample += sin(snare_time * 190 * TAU) * snare_env * 0.3
			# Driving 8th note hats
			if fmod(beat_pos * 2, 1.0) < 0.05:
				var eighth_env = pow(1.0 - fmod(beat_pos * 2, 1.0) * 20, 2.5)
				sample += randf_range(-0.3, 0.3) * eighth_env
			# Ride bell accent on beat 1
			if bar_beat == 0 and sub_beat < 0.1:
				sample += sin(sub_beat * 800 * TAU) * pow(1.0 - sub_beat * 10, 2) * 0.25

		"ethereal":
			# Ghost floating - minimal, reverb-tail sounds
			# Soft thud only on beat 1
			if bar_beat == 0 and sub_beat < 0.15:
				sample += sin(kick_time * 60 * TAU) * pow(max(0, 1.0 - kick_time * 8), 1.5) * 0.4
			# Shimmering cymbal swell
			var swell = sin(beat_pos * TAU * 0.25) * 0.5 + 0.5
			sample += randf_range(-0.06, 0.06) * swell
			# Soft brush on 3
			if bar_beat == 2 and sub_beat < 0.2:
				sample += randf_range(-0.15, 0.15) * pow(1.0 - sub_beat * 5, 2)
			# Wind-like texture
			sample += sin(t * 0.7) * randf_range(-0.02, 0.02)

		"slither":
			# Snake sinuous groove - triplet feel, hissing
			# Kick with slither - beat 1 and "ah" of 2
			if bar_beat == 0 and sub_beat < 0.07:
				sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.7
				sample += sin(kick_time * kick_pitch * 0.5 * TAU) * kick_env * 0.35
			if abs(fmod(beat_pos, 4.0) - 1.67) < 0.08:  # Triplet timing
				sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.5
			# Hissing hi-hat - triplet feel
			var triplet_pos = fmod(beat_pos * 3, 1.0)
			if triplet_pos < 0.08:
				var hiss_env = pow(1.0 - triplet_pos * 12, 3)
				sample += randf_range(-0.25, 0.25) * hiss_env
			# Shaker/rattle on off-triplets
			if triplet_pos > 0.3 and triplet_pos < 0.4:
				sample += randf_range(-0.12, 0.12)
			# Occasional snap on 3
			if bar_beat == 2 and sub_beat < 0.03:
				sample += sin(snare_time * 300 * TAU) * snare_env * 0.35
		_:
			# Default groove
			if sub_beat < 0.06:
				sample += sin(kick_time * kick_pitch * TAU) * kick_env * 0.6
			if bar_beat in [1, 3] and sub_beat < 0.08:
				sample += randf_range(-0.4, 0.4) * snare_env

	return sample


func _get_monster_melody(monster_type: String) -> Array:
	"""Get melody pattern for monster type - 6 sections of 32 notes each (192 total)
	   Each melody uses JRPG-style hooks with memorable motifs and proper phrase structure"""
	# Base frequencies - full chromatic set
	const C4 = 261.63; const Cs4 = 277.18; const D4 = 293.66; const Ds4 = 311.13
	const E4 = 329.63; const F4 = 349.23; const Fs4 = 369.99; const G4 = 392.0
	const Gs4 = 415.30; const A4 = 440.0; const As4 = 466.16; const B4 = 493.88
	const C5 = 523.25; const Cs5 = 554.37; const D5 = 587.33; const Ds5 = 622.25
	const E5 = 659.25; const F5 = 698.46; const G5 = 783.99; const A5 = 880.0
	# Flats as aliases
	const Eb4 = Ds4; const Bb4 = As4; const Ab4 = Gs4; const Db4 = Cs4; const Gb4 = Fs4
	const Eb5 = Ds5; const Bb3 = 233.08

	match monster_type:
		"slime":
			# BOUNCY C MAJOR - Dragon Quest style, super catchy!
			# Hook: C-E-G-E-C  (the "boing" motif)
			return [
				# Section A (bars 1-2) - THE HOOK - this is the earworm
				C4, 0, E4, G4, E4, 0, C4, 0,  G4, E4, C4, E4, G4, 0, 0, 0,
				C4, 0, E4, G4, E4, 0, C4, 0,  G4, 0, C5, G4, E4, C4, 0, 0,
				# Section A repeat (bars 3-4) - hook with variation
				C4, 0, E4, G4, E4, 0, C4, 0,  G4, E4, C4, E4, G4, 0, 0, 0,
				E4, G4, C5, 0, G4, E4, G4, 0,  E4, 0, C4, 0, 0, 0, 0, 0,
				# Section B (bars 5-6) - ascending energy, builds tension
				E4, 0, E4, 0, G4, 0, G4, 0,  A4, 0, A4, 0, C5, 0, 0, 0,
				C5, 0, B4, 0, A4, 0, G4, 0,  A4, G4, E4, 0, C4, 0, 0, 0,
				# Section B variation (bars 7-8) - higher climax
				G4, 0, G4, 0, C5, 0, C5, 0,  D5, 0, E5, 0, D5, C5, 0, 0,
				C5, 0, G4, 0, E4, 0, G4, 0,  C4, E4, G4, C5, G4, 0, 0, 0,
				# Section C (bars 9-10) - playful call and response
				C5, E5, C5, 0, G4, 0, 0, 0,  E4, G4, E4, 0, C4, 0, 0, 0,
				C5, E5, C5, 0, G4, E4, G4, 0,  C4, E4, G4, E4, C4, 0, 0, 0,
				# Section C variation (bars 11-12) - bounce finale
				E4, 0, G4, 0, C5, 0, E5, 0,  C5, G4, E4, G4, C5, 0, 0, 0,
				E5, D5, C5, 0, G4, 0, E4, 0,  C4, 0, E4, G4, C4, 0, 0, 0]
		"bat":
			# FRANTIC D MINOR - Castlevania/Mega Man style, urgent and driving
			# Hook: D-F-A-D (rising) then rapid D-Eb-D (flutter)
			return [
				# Section A - THE FLUTTER HOOK
				D4, 0, F4, A4, D5, A4, F4, 0,  D4, Eb4, D4, 0, D4, Eb4, D4, 0,
				D4, 0, F4, A4, D5, 0, A4, F4,  D4, Eb4, D4, Eb4, D4, 0, 0, 0,
				# Section A repeat with higher tension
				D4, 0, F4, A4, D5, A4, F4, 0,  D4, Eb4, D4, 0, F4, Eb4, D4, 0,
				A4, 0, D5, 0, A4, F4, D4, Eb4,  D4, 0, F4, 0, D4, 0, 0, 0,
				# Section B - frantic ascending panic
				D4, F4, A4, 0, D5, 0, F5, D5,  A4, 0, F4, D4, Eb4, D4, 0, 0,
				A4, A4, D5, D5, A4, A4, F4, 0,  D4, Eb4, F4, Eb4, D4, 0, 0, 0,
				# Section B intensified - breakneck speed feel
				D5, A4, D5, A4, F4, D4, F4, D4,  Eb4, D4, Eb4, D4, F4, 0, 0, 0,
				D5, 0, A4, 0, F4, D4, Eb4, D4,  F4, A4, D5, A4, D4, 0, 0, 0,
				# Section C - swooping dive-bomb runs
				D5, A4, F4, D4, 0, D4, F4, A4,  D5, 0, A4, F4, D4, 0, 0, 0,
				A4, D5, A4, F4, D4, Eb4, F4, A4,  D4, 0, F4, A4, D5, 0, 0, 0,
				# Section C finale - return to hook
				D4, 0, F4, A4, D5, A4, F4, D4,  Eb4, D4, 0, Eb4, D4, 0, 0, 0,
				D5, A4, F4, D4, Eb4, D4, F4, A4,  D4, Eb4, D4, 0, D4, 0, 0, 0]
		"mushroom":
			# CREEPY E MINOR - sparse, unsettling, Silent Hill vibes
			# Hook: E...G...B... (slow, haunting intervals)
			return [
				# Section A - THE DREAD MOTIF - lots of silence
				E4, 0, 0, 0, 0, 0, G4, 0,  0, 0, 0, 0, B4, 0, 0, 0,
				0, 0, E4, 0, 0, 0, 0, 0,  Fs4, 0, 0, E4, 0, 0, 0, 0,
				# Section A with dissonance
				E4, 0, 0, 0, 0, 0, G4, 0,  0, 0, Fs4, 0, 0, 0, E4, 0,
				0, 0, 0, 0, G4, 0, 0, 0,  0, E4, 0, 0, 0, 0, 0, 0,
				# Section B - rising unease
				B4, 0, 0, 0, 0, 0, G4, 0,  0, 0, E4, 0, 0, 0, 0, 0,
				Fs4, 0, 0, G4, 0, 0, 0, 0,  E4, 0, 0, 0, 0, 0, 0, 0,
				# Section B - chromatic creep
				E4, 0, 0, F4, 0, 0, Fs4, 0,  0, G4, 0, 0, 0, 0, 0, 0,
				B4, 0, 0, 0, 0, Fs4, 0, 0,  E4, 0, 0, 0, 0, 0, 0, 0,
				# Section C - brief climax then decay
				E5, 0, 0, 0, B4, 0, 0, 0,  G4, 0, 0, E4, 0, 0, 0, 0,
				0, 0, G4, 0, 0, 0, E4, 0,  0, 0, 0, 0, 0, 0, 0, 0,
				# Section C - return to stillness
				E4, 0, 0, 0, 0, 0, 0, 0,  G4, 0, 0, 0, 0, 0, E4, 0,
				0, 0, 0, 0, 0, 0, 0, 0,  E4, 0, 0, 0, 0, 0, 0, 0]
		"imp":
			# CHAOTIC F MINOR - mischievous, chromatic, Kefka vibes
			# Hook: F-Gb-Ab-Bb-Ab-Gb-F (chromatic laugh)
			return [
				# Section A - THE LAUGH MOTIF
				F4, 0, Gb4, 0, Ab4, 0, Bb4, Ab4,  Gb4, F4, 0, 0, F4, 0, 0, 0,
				F4, 0, Gb4, 0, Ab4, Bb4, Ab4, Gb4,  F4, 0, Ab4, 0, F4, 0, 0, 0,
				# Section A with tricks
				Ab4, Bb4, Ab4, Gb4, F4, Gb4, Ab4, 0,  F4, 0, Gb4, F4, 0, 0, 0, 0,
				F4, Gb4, Ab4, Bb4, 0, Ab4, Gb4, F4,  Gb4, 0, F4, 0, 0, 0, 0, 0,
				# Section B - chaotic dance
				Bb4, 0, Ab4, Gb4, F4, 0, Gb4, Ab4,  Bb4, Ab4, Gb4, F4, 0, 0, 0, 0,
				F4, Ab4, F4, Gb4, F4, Ab4, Bb4, 0,  Ab4, Gb4, F4, 0, 0, 0, 0, 0,
				# Section B - wild leaps
				F4, 0, Bb4, 0, F4, 0, Gb4, Ab4,  Bb4, 0, Ab4, 0, Gb4, F4, 0, 0,
				Ab4, Bb4, Ab4, 0, Gb4, F4, Gb4, 0,  F4, 0, Ab4, 0, F4, 0, 0, 0,
				# Section C - frenzied finale
				F4, Gb4, Ab4, Bb4, Ab4, Gb4, F4, 0,  Gb4, Ab4, Bb4, Ab4, Gb4, F4, 0, 0,
				Bb4, Ab4, Gb4, F4, Gb4, Ab4, F4, 0,  Ab4, Gb4, F4, 0, 0, 0, 0, 0,
				# Section C - return to laugh
				F4, 0, Gb4, 0, Ab4, 0, Bb4, Ab4,  Gb4, F4, 0, Gb4, F4, 0, 0, 0,
				Ab4, Bb4, Ab4, Gb4, F4, 0, Ab4, F4,  Gb4, F4, 0, 0, F4, 0, 0, 0]
		"goblin":
			# TRIBAL A MINOR - war drums, pentatonic, primal
			# Hook: A-C-A-G-E (war chant)
			return [
				# Section A - THE WAR CHANT
				A4, 0, C5, 0, A4, 0, G4, E4,  A4, 0, 0, 0, A4, 0, 0, 0,
				A4, 0, C5, 0, A4, 0, G4, E4,  G4, A4, 0, 0, 0, 0, 0, 0,
				# Section A with response
				A4, 0, C5, 0, A4, 0, G4, E4,  A4, 0, C5, A4, G4, 0, 0, 0,
				E4, G4, A4, 0, C5, A4, G4, E4,  A4, 0, 0, 0, 0, 0, 0, 0,
				# Section B - battle intensifies
				A4, A4, C5, C5, A4, A4, G4, G4,  E4, E4, G4, G4, A4, 0, 0, 0,
				C5, A4, G4, E4, G4, A4, C5, 0,  A4, G4, E4, 0, A4, 0, 0, 0,
				# Section B - marching stomp
				A4, 0, A4, 0, C5, 0, C5, 0,  A4, 0, G4, 0, E4, 0, A4, 0,
				G4, A4, C5, A4, G4, E4, G4, A4,  0, 0, A4, 0, 0, 0, 0, 0,
				# Section C - victory surge
				C5, 0, E5, 0, C5, 0, A4, G4,  A4, C5, A4, G4, E4, 0, 0, 0,
				A4, C5, E5, C5, A4, G4, A4, 0,  E4, G4, A4, 0, 0, 0, 0, 0,
				# Section C - return to war chant
				A4, 0, C5, 0, A4, 0, G4, E4,  A4, 0, C5, 0, A4, 0, 0, 0,
				E4, G4, A4, C5, A4, G4, E4, G4,  A4, 0, 0, 0, A4, 0, 0, 0]
		"skeleton":
			# SPOOKY B MINOR - Castlevania bone-rattling, staccato
			# Hook: B-D-B..Fs-B (bone clatter)
			return [
				# Section A - THE BONE RATTLE
				B4, 0, 0, D5, 0, B4, 0, 0,  Fs4, 0, 0, B4, 0, 0, 0, 0,
				B4, 0, 0, D5, 0, B4, 0, 0,  Fs4, B4, 0, 0, 0, 0, 0, 0,
				# Section A with echo
				B4, 0, 0, D5, 0, B4, 0, 0,  Fs4, 0, 0, 0, B4, 0, 0, 0,
				D5, 0, B4, 0, 0, Fs4, 0, 0,  B4, 0, 0, 0, 0, 0, 0, 0,
				# Section B - creaking joints
				Fs4, 0, 0, 0, B4, 0, 0, 0,  D5, 0, 0, 0, B4, 0, 0, 0,
				Fs4, 0, B4, 0, D5, 0, B4, 0,  Fs4, 0, 0, 0, 0, 0, 0, 0,
				# Section B - shambling march
				B4, D5, B4, 0, 0, Fs4, 0, 0,  B4, 0, D5, 0, B4, 0, 0, 0,
				Fs4, B4, D5, B4, Fs4, 0, B4, 0,  0, 0, 0, 0, 0, 0, 0, 0,
				# Section C - death approaches
				D5, 0, 0, B4, 0, 0, Fs4, 0,  0, B4, 0, 0, D5, 0, 0, 0,
				B4, Fs4, B4, D5, B4, 0, 0, 0,  Fs4, 0, B4, 0, 0, 0, 0, 0,
				# Section C - return to rattle
				B4, 0, 0, D5, 0, B4, 0, 0,  Fs4, 0, 0, B4, 0, 0, 0, 0,
				D5, B4, Fs4, 0, B4, 0, D5, 0,  B4, 0, 0, 0, B4, 0, 0, 0]
		"wolf":
			# TENSE E MINOR - stalking, building, predatory
			# Hook: E-G-B-E (pack hunting motif)
			return [
				# Section A - THE PROWL
				E4, 0, E4, 0, G4, 0, E4, 0,  B4, 0, G4, E4, 0, 0, 0, 0,
				E4, 0, E4, 0, G4, 0, B4, G4,  E4, 0, 0, 0, 0, 0, 0, 0,
				# Section A - circling
				E4, G4, E4, 0, B4, G4, E4, 0,  G4, E4, 0, 0, E4, 0, 0, 0,
				E4, 0, G4, 0, B4, 0, G4, E4,  B4, G4, E4, 0, 0, 0, 0, 0,
				# Section B - tension builds
				B4, 0, E5, 0, B4, 0, G4, 0,  E4, 0, G4, 0, B4, 0, 0, 0,
				E5, B4, G4, E4, G4, B4, E5, 0,  B4, G4, E4, 0, 0, 0, 0, 0,
				# Section B - the chase
				E4, G4, B4, E5, B4, G4, E4, G4,  B4, E5, B4, G4, E4, 0, 0, 0,
				E5, 0, B4, 0, G4, 0, E4, G4,  B4, 0, E4, 0, 0, 0, 0, 0,
				# Section C - the strike
				E5, E5, B4, B4, G4, G4, E4, 0,  G4, B4, E5, 0, B4, G4, 0, 0,
				E4, 0, G4, B4, E5, B4, G4, E4,  G4, 0, E4, 0, 0, 0, 0, 0,
				# Section C - return to prowl
				E4, 0, E4, 0, G4, 0, E4, 0,  B4, 0, G4, E4, G4, 0, 0, 0,
				B4, G4, E4, 0, G4, E4, B4, 0,  E4, 0, 0, 0, E4, 0, 0, 0]
		"ghost":
			# ETHEREAL G MINOR - floating, otherworldly, melancholic
			# Hook: G...Bb...D (rising wail)
			return [
				# Section A - THE WAIL
				G4, 0, 0, 0, 0, 0, Bb4, 0,  0, 0, 0, 0, D5, 0, 0, 0,
				0, 0, Bb4, 0, 0, 0, G4, 0,  0, 0, 0, 0, 0, 0, 0, 0,
				# Section A - drifting
				D5, 0, 0, 0, 0, 0, Bb4, 0,  0, 0, G4, 0, 0, 0, 0, 0,
				0, 0, 0, 0, G4, 0, 0, Bb4,  0, 0, 0, 0, 0, 0, 0, 0,
				# Section B - spectral dance
				G4, 0, Bb4, 0, D5, 0, Bb4, 0,  G4, 0, 0, 0, 0, 0, 0, 0,
				D5, 0, 0, Bb4, 0, 0, G4, 0,  0, 0, Bb4, 0, 0, 0, 0, 0,
				# Section B - ascending spirit
				G4, 0, 0, Bb4, 0, 0, D5, 0,  0, F5, 0, 0, D5, 0, 0, 0,
				0, 0, Bb4, 0, 0, 0, G4, 0,  0, 0, 0, 0, 0, 0, 0, 0,
				# Section C - full manifestation
				D5, 0, Bb4, 0, G4, 0, Bb4, D5,  0, 0, Bb4, 0, G4, 0, 0, 0,
				G4, Bb4, D5, 0, Bb4, G4, 0, 0,  D5, 0, 0, 0, 0, 0, 0, 0,
				# Section C - fade to nothing
				G4, 0, 0, 0, 0, 0, 0, 0,  Bb4, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, G4, 0, 0, 0,  0, 0, 0, 0, G4, 0, 0, 0]
		"snake":
			# SLITHERING C MINOR - serpentine, winding, hypnotic
			# Hook: C-Eb-G-Eb-C (coiling motif)
			return [
				# Section A - THE COIL
				C4, 0, Eb4, 0, G4, 0, Eb4, C4,  0, G4, Eb4, C4, 0, 0, 0, 0,
				C4, 0, Eb4, G4, Eb4, C4, 0, Eb4,  G4, Eb4, C4, 0, 0, 0, 0, 0,
				# Section A - winding
				G4, Eb4, C4, Eb4, G4, Eb4, C4, 0,  Eb4, 0, G4, 0, Eb4, C4, 0, 0,
				C4, Eb4, G4, 0, Eb4, C4, Eb4, G4,  C4, 0, 0, 0, 0, 0, 0, 0,
				# Section B - rising threat
				Eb4, G4, Eb5, G4, Eb4, C4, Eb4, 0,  G4, 0, Eb4, C4, 0, 0, 0, 0,
				C4, 0, Eb4, 0, G4, Eb4, C4, Eb4,  G4, Eb4, C4, 0, 0, 0, 0, 0,
				# Section B - strike preparation
				G4, 0, G4, 0, Eb5, 0, G4, 0,  Eb4, 0, C4, 0, Eb4, G4, 0, 0,
				Eb5, G4, Eb4, C4, Eb4, G4, Eb5, 0,  G4, Eb4, C4, 0, 0, 0, 0, 0,
				# Section C - the strike!
				Eb5, 0, 0, 0, G4, 0, 0, 0,  Eb4, 0, 0, 0, C4, 0, 0, 0,
				C4, Eb4, G4, Eb5, G4, Eb4, C4, 0,  Eb4, G4, C4, 0, 0, 0, 0, 0,
				# Section C - retreat and coil
				C4, 0, Eb4, 0, G4, 0, Eb4, C4,  0, Eb4, G4, Eb4, C4, 0, 0, 0,
				G4, Eb4, C4, 0, Eb4, 0, C4, 0,  Eb4, G4, C4, 0, C4, 0, 0, 0]
		_:
			# Default C major
			return [C4, 0, E4, G4, E4, 0, C4, 0, G4, E4, C4, E4, G4, 0, 0, 0,
					C4, 0, E4, G4, E4, 0, C4, 0, G4, 0, C5, G4, E4, C4, 0, 0,
					C4, 0, E4, G4, E4, 0, C4, 0, G4, E4, C4, E4, G4, 0, 0, 0,
					E4, G4, C5, 0, G4, E4, G4, 0, E4, 0, C4, 0, 0, 0, 0, 0,
					E4, 0, E4, 0, G4, 0, G4, 0, A4, 0, A4, 0, C5, 0, 0, 0,
					C5, 0, B4, 0, A4, 0, G4, 0, A4, G4, E4, 0, C4, 0, 0, 0]


func _get_monster_counter_melody(monster_type: String) -> Array:
	"""Get counter-melody pattern (eighth notes) - adds harmonic depth
	   Plays harmonizing notes that complement the main melody"""
	const C4 = 261.63; const D4 = 293.66; const E4 = 329.63; const F4 = 349.23
	const G4 = 392.0; const A4 = 440.0; const B4 = 493.88; const C5 = 523.25
	const Eb4 = 311.13; const Bb4 = 466.16; const Ab4 = 415.30; const Fs4 = 369.99
	const Gb4 = 369.99; const D5 = 587.33

	match monster_type:
		"slime":
			# Harmonizing thirds and fifths - bouncy feel
			return [
				E4, 0, G4, 0, C5, 0, G4, 0,  E4, 0, C5, 0, G4, 0, E4, 0,
				G4, 0, E4, 0, G4, 0, C5, 0,  G4, 0, E4, 0, C5, G4, E4, 0,
				C5, 0, G4, 0, E4, 0, G4, C5,  G4, E4, G4, 0, E4, 0, C5, 0,
				E4, G4, C5, G4, E4, 0, G4, 0,  C5, 0, G4, 0, E4, 0, 0, 0]
		"bat":
			# Urgent, syncopated counter-melody
			return [
				F4, 0, A4, 0, F4, 0, D4, 0,  A4, F4, D4, 0, F4, 0, A4, 0,
				D4, A4, F4, 0, A4, 0, D4, F4,  A4, 0, F4, 0, D4, 0, A4, 0,
				A4, D5, A4, F4, D4, 0, F4, A4,  D4, 0, F4, 0, A4, 0, D4, 0,
				F4, 0, D4, F4, A4, D5, A4, F4,  D4, F4, A4, 0, D4, 0, 0, 0]
		"mushroom":
			# Sparse, unsettling harmonies
			return [
				0, 0, G4, 0, 0, 0, B4, 0,  0, 0, 0, 0, E4, 0, 0, 0,
				0, 0, 0, 0, Fs4, 0, 0, 0,  0, 0, G4, 0, 0, 0, 0, 0,
				B4, 0, 0, 0, 0, 0, G4, 0,  0, 0, E4, 0, 0, 0, 0, 0,
				0, 0, Fs4, 0, 0, 0, E4, 0,  0, 0, 0, 0, 0, 0, 0, 0]
		"imp":
			# Chromatic chaos companion
			return [
				Ab4, 0, F4, 0, Gb4, 0, Ab4, Bb4,  Ab4, Gb4, F4, 0, Ab4, 0, F4, 0,
				Bb4, Ab4, Gb4, 0, F4, Gb4, Ab4, 0,  F4, 0, Ab4, 0, Gb4, 0, F4, 0,
				F4, 0, Ab4, Bb4, Ab4, 0, Gb4, F4,  Ab4, 0, Gb4, F4, Ab4, 0, 0, 0,
				Gb4, Ab4, F4, 0, Ab4, Bb4, Ab4, Gb4,  F4, 0, Ab4, 0, F4, 0, 0, 0]
		"goblin":
			# Pentatonic war harmony
			return [
				C5, 0, A4, 0, E4, 0, G4, 0,  A4, 0, C5, 0, A4, 0, G4, 0,
				E4, G4, A4, 0, G4, E4, C5, 0,  A4, 0, G4, 0, E4, 0, A4, 0,
				A4, 0, C5, 0, A4, G4, E4, 0,  G4, A4, C5, 0, A4, 0, 0, 0,
				E4, 0, G4, A4, C5, A4, G4, E4,  A4, 0, G4, 0, A4, 0, 0, 0]
		"skeleton":
			# Sparse bone harmonics
			return [
				D5, 0, 0, B4, 0, 0, Fs4, 0,  0, B4, 0, 0, 0, 0, 0, 0,
				Fs4, 0, 0, 0, B4, 0, 0, D5,  0, 0, B4, 0, 0, 0, 0, 0,
				B4, 0, 0, Fs4, 0, 0, D5, 0,  B4, 0, 0, 0, Fs4, 0, 0, 0,
				0, 0, B4, 0, D5, 0, 0, B4,  Fs4, 0, 0, 0, B4, 0, 0, 0]
		"wolf":
			# Hunting pack harmonies
			return [
				G4, 0, B4, 0, E4, 0, G4, 0,  B4, 0, E4, 0, G4, 0, B4, 0,
				E4, 0, G4, B4, E4, 0, G4, 0,  B4, G4, E4, 0, G4, 0, 0, 0,
				B4, 0, G4, 0, E4, G4, B4, 0,  G4, 0, E4, 0, B4, 0, G4, 0,
				E4, G4, B4, G4, E4, 0, G4, B4,  E4, 0, G4, 0, E4, 0, 0, 0]
		"ghost":
			# Ethereal floating harmonies
			return [
				0, 0, Bb4, 0, 0, 0, D5, 0,  0, 0, G4, 0, 0, 0, 0, 0,
				D5, 0, 0, 0, Bb4, 0, 0, 0,  G4, 0, 0, 0, 0, 0, 0, 0,
				0, 0, G4, 0, 0, Bb4, 0, 0,  D5, 0, 0, 0, Bb4, 0, 0, 0,
				G4, 0, 0, Bb4, 0, 0, 0, 0,  0, 0, G4, 0, 0, 0, 0, 0]
		"snake":
			# Slithering thirds
			return [
				Eb4, 0, G4, 0, C5, 0, G4, Eb4,  0, C5, G4, 0, Eb4, 0, 0, 0,
				G4, 0, Eb4, 0, C5, G4, Eb4, 0,  C5, 0, G4, 0, Eb4, 0, 0, 0,
				C5, G4, Eb4, 0, G4, 0, Eb4, C5,  G4, 0, Eb4, 0, C5, 0, 0, 0,
				Eb4, 0, G4, C5, G4, Eb4, 0, G4,  C5, 0, G4, 0, Eb4, 0, 0, 0]
		_:
			return []


func _get_monster_bass(monster_type: String) -> Array:
	"""Get bass pattern for monster type - 6 sections of 8 notes each (48 total)"""
	const C2 = 65.41; const D2 = 73.42; const E2 = 82.41; const F2 = 87.31
	const G2 = 98.0; const A2 = 110.0; const B2 = 123.47; const C3 = 130.81
	const Eb2 = 77.78; const Bb2 = 116.54; const Fs2 = 92.50; const Ab2 = 103.83
	const Gb2 = 92.50

	match monster_type:
		"slime":
			# Bouncy bass - 6 sections for full 48 bars
			return [C2, G2, C2, G2, C2, E2, G2, C2,  # Section A
					C2, G2, C2, G2, E2, G2, C2, G2,  # Section A'
					C2, E2, G2, C3, G2, E2, C2, G2,  # Section B - higher
					E2, G2, C3, G2, E2, C2, G2, E2,  # Section B'
					E2, G2, C2, G2, E2, C2, G2, E2,  # Section C - variation
					C2, G2, E2, G2, C2, E2, G2, C2]  # Section C' - return
		"bat":
			# Frantic bass - 6 sections
			return [D2, D2, A2, D2, D2, F2, A2, D2,  # Section A
					D2, A2, D2, F2, D2, A2, F2, D2,  # Section A'
					D2, F2, D2, A2, F2, D2, A2, D2,  # Section B - ascending
					A2, F2, D2, F2, A2, D2, F2, A2,  # Section B'
					A2, D2, F2, D2, A2, F2, D2, F2,  # Section C - swooping
					D2, A2, D2, F2, D2, A2, F2, D2]  # Section C' - chaotic
		"mushroom":
			# Droning bass - 6 sections
			return [E2, E2, E2, E2, B2, E2, E2, E2,  # Section A - drone
					E2, E2, E2, E2, E2, E2, B2, E2,  # Section A'
					E2, Fs2, E2, E2, E2, G2, E2, E2,  # Section B - subtle
					E2, E2, G2, E2, Fs2, E2, E2, E2,  # Section B'
					B2, E2, G2, E2, Fs2, E2, E2, E2,  # Section C - movement
					E2, E2, E2, E2, E2, E2, E2, E2]  # Section C' - decay
		"imp":
			# Chromatic bass - 6 sections
			return [F2, Eb2, F2, G2, F2, Eb2, F2, Bb2,  # Section A
					F2, Gb2, F2, Eb2, F2, G2, F2, Bb2,  # Section A'
					Ab2, Gb2, F2, Gb2, Ab2, Bb2, Ab2, F2,  # Section B - trickster
					Bb2, Ab2, Gb2, F2, Gb2, Ab2, Bb2, Ab2,  # Section B'
					Bb2, Ab2, Gb2, F2, Gb2, Ab2, F2, Gb2,  # Section C - dance
					F2, Gb2, Ab2, Bb2, Ab2, Gb2, F2, F2]  # Section C' - wild
		"goblin":
			# Tribal bass - 6 sections
			return [A2, A2, E2, A2, A2, G2, E2, A2,  # Section A - war
					A2, E2, A2, G2, A2, E2, G2, A2,  # Section A'
					E2, G2, A2, A2, G2, E2, A2, G2,  # Section B - battle
					A2, G2, E2, G2, A2, G2, E2, A2,  # Section B'
					A2, A2, A2, A2, G2, G2, E2, E2,  # Section C - march
					A2, G2, E2, G2, A2, E2, G2, A2]  # Section C' - stomp
		"skeleton":
			# Staccato bass - 6 sections
			return [B2, 0, B2, 0, Fs2, 0, B2, 0,  # Section A - rattle
					B2, 0, Fs2, 0, B2, 0, D2, 0,  # Section A'
					Fs2, 0, B2, 0, D2, 0, B2, 0,  # Section B - creak
					D2, 0, B2, 0, Fs2, 0, D2, 0,  # Section B'
					B2, D2, 0, B2, Fs2, 0, B2, 0,  # Section C - shamble
					B2, 0, D2, 0, Fs2, 0, B2, 0]  # Section C' - march
		"wolf":
			# Prowling bass - 6 sections
			return [E2, E2, G2, E2, B2, E2, G2, E2,  # Section A - prowl
					G2, E2, B2, G2, E2, G2, B2, E2,  # Section A' - stalk
					E2, G2, B2, E2, G2, B2, E2, G2,  # Section B - chase
					B2, G2, E2, G2, B2, E2, G2, E2,  # Section B' - howl
					B2, E2, B2, E2, G2, E2, B2, E2,  # Section C - pack
					E2, G2, E2, B2, E2, G2, E2, E2]  # Section C' - hunt
		"ghost":
			# Sparse floating bass - 6 sections
			return [G2, 0, G2, 0, D2, 0, G2, 0,  # Section A - haunt
					D2, 0, G2, 0, Bb2, 0, G2, 0,  # Section A' - drift
					G2, 0, D2, 0, G2, 0, Bb2, 0,  # Section B - wail
					Bb2, 0, G2, 0, D2, 0, G2, 0,  # Section B' - moan
					D2, 0, Bb2, 0, G2, 0, D2, 0,  # Section C - apparition
					G2, 0, 0, 0, D2, 0, 0, G2]  # Section C' - fade
		"snake":
			# Serpentine bass - 6 sections
			return [C2, Eb2, G2, Eb2, C2, G2, Eb2, C2,  # Section A - slither
					G2, Eb2, C2, Eb2, G2, C2, Eb2, G2,  # Section A' - coil
					C2, G2, Eb2, C2, Eb2, G2, C2, Eb2,  # Section B - strike
					Eb2, G2, Eb2, C2, Eb2, C2, G2, C2,  # Section B' - retreat
					G2, C2, Eb2, G2, C2, Eb2, G2, Eb2,  # Section C - hypnotic
					C2, Eb2, C2, G2, Eb2, C2, Eb2, C2]  # Section C' - constrict
		_:
			return [C2, G2, C2, G2, C2, E2, G2, C2,
					C2, E2, G2, C3, G2, E2, C2, G2,
					E2, G2, C2, G2, E2, C2, G2, E2,
					C2, G2, E2, G2, C2, E2, G2, C2]


## Game Over Music - Short sad ditty (does not loop)

func _start_game_over_music() -> void:
	"""Generate and play a short game over ditty (no loop)"""
	_music_playing = true

	# Short death ditty - about 3 seconds
	var sample_rate = 22050
	var bpm = 60.0  # Slow, mournful
	var duration = 3.0

	var buffer = _generate_game_over_buffer(sample_rate, duration, bpm)

	# Create non-looping audio stream
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED  # No loop - plays once

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


func _generate_game_over_buffer(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate a short, sad game over ditty - descending, mournful"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)

	# Notes for sad descending melody (D minor)
	const NOTE_D3 = 146.83
	const NOTE_C3 = 130.81
	const NOTE_Bb2 = 116.54
	const NOTE_A2 = 110.0
	const NOTE_G2 = 98.0
	const NOTE_F2 = 87.31
	const NOTE_D2 = 73.42

	const NOTE_D4 = 293.66
	const NOTE_C4 = 261.63
	const NOTE_Bb3 = 233.08
	const NOTE_A3 = 220.0
	const NOTE_G3 = 196.0
	const NOTE_F3 = 174.61
	const NOTE_D3_HIGH = 146.83

	# Melody notes with timing (note, duration in beats)
	# Classic "dun dun dun duuun" descending pattern
	var melody_events = [
		{"note": NOTE_D4, "start": 0.0, "dur": 0.4},
		{"note": NOTE_C4, "start": 0.5, "dur": 0.4},
		{"note": NOTE_Bb3, "start": 1.0, "dur": 0.4},
		{"note": NOTE_A3, "start": 1.5, "dur": 1.2},  # Hold
		{"note": NOTE_G3, "start": 2.0, "dur": 0.3},
		{"note": NOTE_F3, "start": 2.4, "dur": 0.5},
		{"note": NOTE_D3_HIGH, "start": 2.9, "dur": 0.8},  # Final low note, fade
	]

	# Bass notes
	var bass_events = [
		{"note": NOTE_D3, "start": 0.0, "dur": 1.0},
		{"note": NOTE_Bb2, "start": 1.0, "dur": 1.0},
		{"note": NOTE_D2, "start": 2.0, "dur": 1.5},
	]

	var beat_duration = 60.0 / bpm

	for i in range(samples):
		var t = float(i) / rate
		var beat_pos = t / beat_duration
		var sample = 0.0

		# Global fade out envelope
		var global_env = 1.0 - (t / duration) * 0.5

		# Melody
		for event in melody_events:
			var note_start = event["start"] * beat_duration
			var note_dur = event["dur"] * beat_duration
			if t >= note_start and t < note_start + note_dur:
				var note_t = t - note_start
				var note_env = 1.0 - (note_t / note_dur)  # Linear decay
				note_env = note_env * note_env  # Squared for faster decay
				var freq = event["note"]
				var phase = note_t * freq
				# Triangle wave for mournful sound
				var wave = _triangle_wave(phase)
				sample += wave * 0.35 * note_env

		# Bass
		for event in bass_events:
			var note_start = event["start"] * beat_duration
			var note_dur = event["dur"] * beat_duration
			if t >= note_start and t < note_start + note_dur:
				var note_t = t - note_start
				var note_env = 1.0 - (note_t / note_dur) * 0.7
				var freq = event["note"]
				var phase = note_t * freq
				# Square wave for bass
				var wave = _square_wave(phase)
				sample += wave * 0.2 * note_env

		# Apply global envelope
		sample *= global_env

		# Soft clip
		sample = clamp(sample, -0.9, 0.9)

		buffer.append(Vector2(sample, sample))

	return buffer


## ============================================================
## AREA MUSIC - Exploration themes for different areas
## ============================================================

var _current_area: String = ""

func play_area_music(area_type: String) -> void:
	"""Play appropriate music for an exploration area"""
	if _current_area == area_type and _music_playing:
		return  # Already playing

	_current_area = area_type
	stop_music()

	match area_type:
		"overworld":
			_start_overworld_music()
		"village", "harmonia_village":
			_start_village_music()
		"cave", "dungeon", "whispering_cave":
			_start_cave_music()
		_:
			_start_overworld_music()


func _start_overworld_music() -> void:
	"""Generate peaceful overworld exploration theme"""
	_music_playing = true
	print("[MUSIC] Playing overworld theme")

	var sample_rate = 22050
	var bpm = 100.0
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_overworld_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _start_village_music() -> void:
	"""Generate peaceful village theme"""
	_music_playing = true
	print("[MUSIC] Playing village theme")

	var sample_rate = 22050
	var bpm = 80.0
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_village_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _start_cave_music() -> void:
	"""Generate mysterious dungeon/cave theme"""
	_music_playing = true
	print("[MUSIC] Playing cave/dungeon theme")

	var sample_rate = 22050
	var bpm = 90.0
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_cave_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _start_title_music() -> void:
	"""Generate majestic EarthBound-style trippy title theme"""
	_music_playing = true
	print("[MUSIC] Playing title theme")

	var sample_rate = 22050
	var bpm = 72.0  # Slow and majestic
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_title_music_buffer(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _generate_title_music_buffer(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate majestic yet trippy EarthBound-style title music
	   Features: detuned pads, wobbly bass, unexpected chord changes, phasing"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# Majestic chord progression with unexpected changes (EarthBound-style)
	# Cmaj7 -> Em7 -> Fmaj7 -> G7 -> Am7 -> Dm7 -> Emaj(!) -> G7sus4
	var chords = [
		[261.63, 329.63, 392.00, 493.88],  # Cmaj7
		[329.63, 392.00, 493.88, 587.33],  # Em7
		[349.23, 440.00, 523.25, 659.25],  # Fmaj7
		[392.00, 493.88, 587.33, 698.46],  # G7
		[440.00, 523.25, 659.25, 783.99],  # Am7
		[293.66, 349.23, 440.00, 523.25],  # Dm7
		[329.63, 415.30, 493.88, 622.25],  # Emaj (unexpected!)
		[392.00, 523.25, 587.33, 698.46],  # G7sus4
	]

	# Trippy melody - pentatonic with chromatic passing tones
	var melody_notes = [
		523.25, 587.33, 659.25, 783.99, 880.00,  # Bar 1-2: ascending
		830.61, 783.99, 698.46, 659.25, 587.33,  # Bar 3-4: chromatic descent
		523.25, 0, 659.25, 0, 783.99, 0, 880.00, 0,  # Bar 5-6: staccato
		987.77, 880.00, 783.99, 739.99, 698.46, 659.25, 622.25, 587.33,  # Bar 7-8: cascade
		523.25, 587.33, 659.25, 523.25, 493.88, 440.00, 392.00, 349.23,  # Bar 9-10
		329.63, 392.00, 440.00, 493.88, 523.25, 587.33, 659.25, 783.99,  # Bar 11-12
		880.00, 0, 783.99, 0, 698.46, 0, 659.25, 0,  # Bar 13-14: breathing space
		587.33, 523.25, 493.88, 440.00, 392.00, 349.23, 329.63, 293.66,  # Bar 15-16: resolve
	]

	# Sub-bass with wobble (very EarthBound)
	var bass_notes = [
		65.41, 65.41, 82.41, 82.41,  # C, C, E, E
		87.31, 87.31, 98.00, 98.00,  # F, F, G, G
		110.00, 110.00, 73.42, 73.42,  # A, A, D, D
		82.41, 82.41, 98.00, 98.00,   # E, E, G, G
	]

	var quarter_dur = beat_duration
	var eighth_dur = beat_duration / 2.0

	for i in range(samples):
		var t = float(i) / rate
		var beat_idx = int(t / quarter_dur) % 64
		var eighth_idx = int(t / eighth_dur) % 128
		var bar_idx = int(t / (quarter_dur * 4)) % 16
		var chord_idx = int(t / (quarter_dur * 8)) % 8
		var t_in_beat = fmod(t, quarter_dur) / quarter_dur

		var sample = 0.0

		# === Pad layer (detuned for trippy feel) ===
		var chord = chords[chord_idx]
		var pad_env = 0.6  # Sustained
		# Main pad voices with slight detuning
		for note_idx in range(chord.size()):
			var freq = chord[note_idx] * 0.5  # One octave down
			var detune = sin(t * 0.3 + note_idx * 1.5) * 0.008  # Slow wobble
			var phase_offset = sin(t * 0.7 + note_idx) * 0.1  # Phasing

			# Saw-ish pad with filtering
			var pad_wave = _triangle_wave(t * freq * (1.0 + detune) + phase_offset)
			pad_wave += _triangle_wave(t * freq * (1.0 - detune * 0.5) + phase_offset) * 0.5
			sample += pad_wave * 0.08 * pad_env

		# === Melody layer ===
		var melody_idx = eighth_idx % melody_notes.size()
		var melody_freq = melody_notes[melody_idx]
		if melody_freq > 0:
			# Envelope with gentle attack
			var mel_attack = min(t_in_beat * 4.0, 1.0)
			var mel_decay = pow(1.0 - t_in_beat, 0.3)
			var mel_env = mel_attack * mel_decay

			# Sine with slight vibrato (trippy)
			var vibrato = sin(t * 5.5) * 0.015
			sample += sin(t * melody_freq * (1.0 + vibrato) * TAU) * 0.15 * mel_env
			# Add harmonics for richer sound
			sample += sin(t * melody_freq * 2.0 * TAU) * 0.04 * mel_env
			sample += _triangle_wave(t * melody_freq * 1.5) * 0.03 * mel_env

		# === Sub-bass with wobble ===
		var bass_idx = beat_idx % bass_notes.size()
		var bass_freq = bass_notes[bass_idx]
		# Wobble effect (very EarthBound)
		var wobble_rate = 3.0 + sin(t * 0.1) * 1.5  # Varying wobble speed
		var wobble = sin(t * wobble_rate * TAU) * 0.3 + 0.7
		sample += sin(t * bass_freq * TAU) * 0.25 * wobble
		# Add subtle distortion harmonics
		sample += sin(t * bass_freq * 2.0 * TAU) * 0.05 * wobble

		# === Ethereal high layer (sparkles) ===
		if bar_idx % 2 == 0:
			var sparkle_time = fmod(t * 3.7, 1.0)
			if sparkle_time < 0.1:
				var sparkle_freq = 1760.0 + sin(t * 11) * 200  # Random-ish pitch
				var sparkle_env = pow(1.0 - sparkle_time / 0.1, 2)
				sample += sin(sparkle_time * sparkle_freq * TAU) * 0.03 * sparkle_env

		# === Phaser sweep (trippy texture) ===
		var sweep_freq = 0.15 + sin(t * 0.05) * 0.1  # Very slow sweep
		var sweep = sin(t * sweep_freq * TAU + sin(t * 2.3) * 0.5)
		sample *= 0.85 + sweep * 0.15  # Subtle phase modulation

		# === Soft noise bed for atmosphere ===
		sample += randf_range(-0.015, 0.015)

		# Soft clip for warmth
		sample = tanh(sample * 1.2) * 0.85
		sample = clamp(sample, -0.9, 0.9)
		buffer.append(Vector2(sample, sample))

	return buffer


func _create_and_play_looping_wav(buffer: PackedVector2Array, sample_rate: int) -> void:
	"""Helper to create looping WAV from buffer"""
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buffer.size()

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


func _generate_overworld_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate adventurous overworld theme - C major, uplifting"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	const NOTE_C3 = 130.81
	const NOTE_E3 = 164.81
	const NOTE_F3 = 174.61
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88
	const NOTE_C5 = 523.25

	var melody = [
		NOTE_C4, 0, NOTE_E4, 0, NOTE_G4, 0, NOTE_E4, 0, NOTE_C4, 0, NOTE_D4, 0, NOTE_E4, 0, 0, 0,
		NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, NOTE_C4, 0, NOTE_D4, 0, NOTE_E4, 0, NOTE_C4, 0, 0, 0,
		NOTE_G4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, NOTE_E4, 0, 0, 0,
		NOTE_C4, 0, NOTE_E4, 0, NOTE_G4, 0, NOTE_C5, 0, NOTE_G4, 0, NOTE_E4, 0, NOTE_C4, 0, 0, 0,
		NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, NOTE_E4, 0, NOTE_F4, 0, 0, 0,
		NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, NOTE_C4, 0, NOTE_D4, 0, NOTE_E4, 0, 0, 0,
		NOTE_E4, 0, NOTE_F4, 0, NOTE_G4, 0, NOTE_A4, 0, NOTE_B4, 0, NOTE_A4, 0, NOTE_G4, 0, 0, 0,
		NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, NOTE_C4, 0, NOTE_D4, NOTE_E4, 0, 0,
	]

	var bass = [
		NOTE_C3, NOTE_C3, NOTE_G3, NOTE_G3, NOTE_C3, NOTE_C3, NOTE_G3, NOTE_G3,
		NOTE_F3, NOTE_F3, NOTE_C3, NOTE_C3, NOTE_G3, NOTE_G3, NOTE_C3, NOTE_C3,
		NOTE_A3, NOTE_A3, NOTE_F3, NOTE_F3, NOTE_G3, NOTE_G3, NOTE_C3, NOTE_C3,
		NOTE_E3, NOTE_E3, NOTE_G3, NOTE_G3, NOTE_A3, NOTE_A3, NOTE_G3, NOTE_G3,
	]

	var sixteenth_dur = beat_duration / 4.0
	var quarter_dur = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_dur) % 128
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur

		var sample = 0.0

		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_sixteenth, 0.4)
			sample += _triangle_wave(t * melody_freq) * 0.25 * melody_env

		var bass_freq = bass[quarter_idx] * 0.5
		sample += _square_wave(t * bass_freq) * 0.15

		var beat_pos = fmod(t, beat_duration)
		if beat_pos < 0.03 and int(t / beat_duration) % 2 == 0:
			sample += sin(beat_pos * 60 * TAU) * pow(1.0 - beat_pos / 0.03, 2) * 0.15

		sample = clamp(sample, -0.9, 0.9)
		buffer.append(Vector2(sample, sample))

	return buffer


func _generate_village_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate warm village theme - F major, pastoral"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	const NOTE_F3 = 174.61
	const NOTE_A3 = 220.0
	const NOTE_Bb3 = 233.08
	const NOTE_C4 = 261.63
	const NOTE_E4 = 329.63
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_Bb4 = 466.16
	const NOTE_C5 = 523.25

	var melody = [
		NOTE_F4, NOTE_A4, NOTE_C5, NOTE_A4, NOTE_F4, 0, NOTE_G4, NOTE_A4,
		NOTE_Bb4, NOTE_A4, NOTE_G4, NOTE_F4, NOTE_E4, 0, NOTE_F4, 0,
		NOTE_C4, 0, NOTE_E4, NOTE_F4, NOTE_G4, NOTE_A4, NOTE_Bb4, 0,
		NOTE_A4, NOTE_G4, NOTE_F4, 0, NOTE_F4, 0, 0, 0,
		NOTE_A4, NOTE_G4, NOTE_F4, NOTE_E4, NOTE_F4, NOTE_G4, NOTE_A4, 0,
		NOTE_Bb4, NOTE_A4, NOTE_G4, 0, NOTE_F4, 0, NOTE_G4, 0,
		NOTE_C5, NOTE_Bb4, NOTE_A4, NOTE_G4, NOTE_F4, NOTE_E4, NOTE_F4, 0,
		NOTE_F4, 0, 0, 0, 0, 0, 0, 0,
	]

	var bass = [
		NOTE_F3, NOTE_F3, NOTE_C4, NOTE_C4, NOTE_F3, NOTE_F3, NOTE_C4, NOTE_C4,
		NOTE_Bb3, NOTE_Bb3, NOTE_F3, NOTE_F3, NOTE_C4, NOTE_C4, NOTE_F3, NOTE_F3,
		NOTE_A3, NOTE_A3, NOTE_F3, NOTE_F3, NOTE_Bb3, NOTE_Bb3, NOTE_C4, NOTE_C4,
		NOTE_F3, NOTE_F3, NOTE_C4, NOTE_C4, NOTE_F3, NOTE_F3, NOTE_F3, NOTE_F3,
	]

	var eighth_dur = beat_duration / 2.0
	var quarter_dur = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var eighth_idx = int(t / eighth_dur) % 64
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_eighth = fmod(t, eighth_dur) / eighth_dur

		var sample = 0.0

		var melody_freq = melody[eighth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_eighth, 0.3)
			sample += _triangle_wave(t * melody_freq) * 0.22 * melody_env
			sample += sin(t * melody_freq * TAU) * 0.08 * melody_env

		var bass_freq = bass[quarter_idx] * 0.5
		sample += sin(t * bass_freq * TAU) * 0.12

		sample = clamp(sample, -0.9, 0.9)
		buffer.append(Vector2(sample, sample))

	return buffer


func _generate_cave_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate tense cave theme - E minor, mysterious"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	const NOTE_E2 = 82.41
	const NOTE_B2 = 123.47
	const NOTE_A3 = 220.0
	const NOTE_G3 = 196.0
	const NOTE_B3 = 246.94
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88

	var melody = [
		NOTE_E4, 0, 0, 0, 0, 0, NOTE_D4, 0, 0, 0, 0, 0, NOTE_E4, 0, 0, 0,
		0, 0, NOTE_G4, 0, 0, 0, NOTE_F4, 0, NOTE_E4, 0, 0, 0, 0, 0, 0, 0,
		NOTE_B4, 0, 0, 0, NOTE_A4, 0, 0, 0, NOTE_G4, 0, 0, 0, NOTE_F4, 0, NOTE_E4, 0,
		0, 0, 0, 0, NOTE_D4, 0, NOTE_E4, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		NOTE_E4, 0, NOTE_F4, 0, NOTE_E4, 0, 0, 0, NOTE_D4, 0, NOTE_E4, 0, 0, 0, 0, 0,
		NOTE_A4, 0, 0, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, 0, 0, 0, 0, 0, 0,
		NOTE_B3, 0, NOTE_C4, 0, NOTE_D4, 0, NOTE_E4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, 0, 0,
		NOTE_E4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	]

	var bass = [
		NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_B2,
		NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_B2, NOTE_B2, NOTE_E2, NOTE_E2,
		NOTE_E2, NOTE_E2, NOTE_A3, NOTE_A3, NOTE_G3, NOTE_G3, NOTE_E2, NOTE_E2,
		NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2,
	]

	var sixteenth_dur = beat_duration / 4.0
	var quarter_dur = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_dur) % 128
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur

		var sample = 0.0

		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_sixteenth, 0.5)
			sample += _triangle_wave(t * melody_freq) * 0.18 * melody_env
			sample += _triangle_wave(t * melody_freq * 1.008) * 0.08 * melody_env

		var bass_freq = bass[quarter_idx] * 0.5
		sample += sin(t * bass_freq * TAU) * 0.2
		sample += _square_wave(t * bass_freq) * 0.08

		var drip_time = fmod(t * 1.7, 2.5)
		if drip_time < 0.03:
			sample += sin(drip_time * 2000 * TAU) * pow(1.0 - drip_time / 0.03, 2) * 0.1

		sample += randf_range(-0.02, 0.02)
		sample = clamp(sample, -0.9, 0.9)
		buffer.append(Vector2(sample, sample))

	return buffer


## Piano melody for tavern interaction
func play_piano_melody() -> void:
	"""Play a procedural piano melody for the tavern piano"""
	var sample_rate = 22050
	var duration = 3.0
	var buffer = _generate_piano_melody(sample_rate, duration)

	# Create non-looping audio
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

	# Use ability player for one-shot sounds
	_ability_player.stream = wav
	_ability_player.play()


func _generate_piano_melody(rate: int, duration: float) -> PackedVector2Array:
	"""Generate a simple piano melody - Chopin-esque"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)

	# Piano frequencies - C major broken chords with melody
	# Note frequencies (Hz)
	var C4 = 261.63
	var D4 = 293.66
	var E4 = 329.63
	var F4 = 349.23
	var G4 = 392.00
	var A4 = 440.00
	var B4 = 493.88
	var C5 = 523.25
	var D5 = 587.33
	var E5 = 659.25
	var G5 = 783.99

	# Melody pattern (notes with timing)
	var melody = [
		{"note": E5, "start": 0.0, "dur": 0.4},
		{"note": D5, "start": 0.4, "dur": 0.4},
		{"note": C5, "start": 0.8, "dur": 0.6},
		{"note": G4, "start": 1.4, "dur": 0.3},
		{"note": A4, "start": 1.7, "dur": 0.3},
		{"note": B4, "start": 2.0, "dur": 0.3},
		{"note": C5, "start": 2.3, "dur": 0.7},
	]

	# Bass/accompaniment (arpeggiated chords)
	var bass = [
		{"note": C4, "start": 0.0, "dur": 0.2},
		{"note": E4, "start": 0.15, "dur": 0.2},
		{"note": G4, "start": 0.3, "dur": 0.2},
		{"note": C4, "start": 0.8, "dur": 0.2},
		{"note": E4, "start": 0.95, "dur": 0.2},
		{"note": G4, "start": 1.1, "dur": 0.2},
		{"note": F4, "start": 1.4, "dur": 0.2},
		{"note": A4, "start": 1.55, "dur": 0.2},
		{"note": G4, "start": 2.0, "dur": 0.2},
		{"note": B4, "start": 2.15, "dur": 0.2},
		{"note": D5, "start": 2.3, "dur": 0.4},
	]

	for i in range(samples):
		var t = float(i) / rate
		var sample = 0.0

		# Process melody notes
		for note in melody:
			var note_t = t - note["start"]
			if note_t >= 0 and note_t < note["dur"] * 1.5:  # Sustain + decay
				# Piano-like envelope (sharp attack, gradual decay)
				var attack = min(note_t * 50.0, 1.0)  # Fast attack
				var decay = pow(0.4, note_t * 2.0)    # Gradual decay
				var env = attack * decay

				# Piano tone (fundamental + harmonics)
				var freq = note["note"]
				var tone = sin(t * freq * TAU) * 0.6
				tone += sin(t * freq * 2.0 * TAU) * 0.25  # 2nd harmonic
				tone += sin(t * freq * 3.0 * TAU) * 0.1   # 3rd harmonic
				tone += sin(t * freq * 4.0 * TAU) * 0.05  # 4th harmonic

				sample += tone * env * 0.25

		# Process bass notes
		for note in bass:
			var note_t = t - note["start"]
			if note_t >= 0 and note_t < note["dur"] * 1.5:
				var attack = min(note_t * 50.0, 1.0)
				var decay = pow(0.5, note_t * 3.0)
				var env = attack * decay

				var freq = note["note"]
				var tone = sin(t * freq * TAU) * 0.5
				tone += sin(t * freq * 2.0 * TAU) * 0.2

				sample += tone * env * 0.15

		# Soft reverb simulation (simple delay mix)
		# Note: For a real implementation, you'd use a proper reverb

		sample = clamp(sample, -0.95, 0.95)
		buffer.append(Vector2(sample, sample))

	return buffer
