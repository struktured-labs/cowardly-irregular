extends Node
class_name SoundManagerClass

## SoundManager - Central audio system for battle and UI sounds
## Generates procedural 8-bit style sounds and manages audio playback

# Audio players for different channels
var _ui_player: AudioStreamPlayer
var _battle_player: AudioStreamPlayer
var _ability_player: AudioStreamPlayer

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
