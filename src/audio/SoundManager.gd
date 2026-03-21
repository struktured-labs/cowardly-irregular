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

# Area music WAV cache - stores fully built AudioStreamWAV per area so re-entering
# an area replays instantly without regenerating thousands of samples.
static var _area_wav_cache: Dictionary = {}

# Music manifest - file-based tracks take priority over procedural generation
static var _music_manifest: Dictionary = {}
static var _manifest_loaded: bool = false

# SFX manifest - file-based SFX take priority over procedural generation
static var _sfx_manifest: Dictionary = {}
static var _sfx_manifest_loaded: bool = false
# Cache loaded AudioStream objects so we only hit disk once per key
static var _sfx_stream_cache: Dictionary = {}

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
	# Autogrind tier transition sounds
	"tier_zoom_out": {"freq": 320, "duration": 0.22, "type": "tier_zoom_out"},   # Tier 1 -> Dashboard
	"tier_zoom_in": {"freq": 520, "duration": 0.18, "type": "tier_zoom_in"},    # Dashboard -> Tier 1

	# Battle Sounds
	"attack_hit": {"freq": 200, "duration": 0.12, "type": "noise_hit"},
	"attack_miss": {"freq": 150, "duration": 0.15, "type": "swoosh"},
	"critical_hit": {"freq": 250, "duration": 0.2, "type": "impact"},
	"damage_taken": {"freq": 180, "duration": 0.1, "type": "thud"},
	"enemy_death": {"freq": 180, "duration": 0.35, "type": "dying_fall"},
	"heal": {"freq": 800, "duration": 0.3, "type": "sparkle"},
	"buff": {"freq": 600, "duration": 0.25, "type": "ascending"},
	"debuff": {"freq": 400, "duration": 0.25, "type": "descending"},
	"victory": {"freq": 523, "duration": 0.8, "type": "fanfare"},
	"defeat": {"freq": 200, "duration": 1.0, "type": "sad"},
	# Status effect sounds
	"status_poison": {"freq": 220, "duration": 0.3, "type": "woozy"},
	"status_sleep": {"freq": 300, "duration": 0.4, "type": "woozy"},
	"status_confuse": {"freq": 500, "duration": 0.3, "type": "woozy"},
	"status_paralyze": {"freq": 800, "duration": 0.25, "type": "crackle_lock"},
	# Round transition sounds
	"phase_select": {"freq": 660, "duration": 0.07, "type": "blip"},
	"phase_execute": {"freq": 440, "duration": 0.12, "type": "low_pulse"},

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
	_load_sfx_manifest()
	_setup_audio_players()
	_setup_default_ability_sounds()


func _exit_tree() -> void:
	# Cleanup tweens to prevent callbacks on freed nodes
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_crossfade_tween = null
	if _danger_tween and _danger_tween.is_valid():
		_danger_tween.kill()
	_danger_tween = null
	if _corruption_tween and _corruption_tween.is_valid():
		_corruption_tween.kill()
	_corruption_tween = null


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


## SFX Manifest (file-based SFX take priority over procedural)

static func _load_sfx_manifest() -> void:
	if _sfx_manifest_loaded:
		return
	_sfx_manifest_loaded = true
	var file = FileAccess.open("res://data/sfx_manifest.json", FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed and parsed.has("sfx"):
		_sfx_manifest = parsed["sfx"]
		if _sfx_manifest.size() > 0:
			print("[SFX] Loaded sfx manifest: %d sounds" % _sfx_manifest.size())


func _try_play_sfx_from_manifest(player: AudioStreamPlayer, sound_key: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	"""Try to play a file-based SFX from the manifest. Returns true if successful."""
	if not _sfx_manifest.has(sound_key):
		return false
	var entry = _sfx_manifest[sound_key]
	var path = entry.get("file", "")
	if path == "":
		return false
	if not path.begins_with("res://"):
		path = "res://" + path

	# Check stream cache first
	if _sfx_stream_cache.has(sound_key):
		var cached_stream = _sfx_stream_cache[sound_key]
		if cached_stream:
			player.stream = cached_stream
			player.volume_db = volume_db
			player.pitch_scale = pitch_scale
			player.play()
			return true
		else:
			# Cached null = file doesn't exist, fall through to procedural
			return false

	# Try loading from disk
	if not FileAccess.file_exists(path):
		_sfx_stream_cache[sound_key] = null  # Cache miss
		return false
	var stream = load(path) as AudioStream
	if not stream:
		push_warning("[SFX] Failed to load: %s" % path)
		_sfx_stream_cache[sound_key] = null
		return false
	_sfx_stream_cache[sound_key] = stream
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return true


## Public API

func play_ui(sound_key: String) -> void:
	"""Play a UI sound effect — file-based if available, else procedural"""
	if _try_play_sfx_from_manifest(_ui_player, sound_key):
		return
	if not SOUNDS.has(sound_key):
		return
	_play_sound(_ui_player, SOUNDS[sound_key])


func play_battle(sound_key: String) -> void:
	"""Play a battle sound effect — file-based if available, else procedural"""
	if _try_play_sfx_from_manifest(_battle_player, sound_key):
		return
	if not SOUNDS.has(sound_key):
		return
	_play_sound(_battle_player, SOUNDS[sound_key])


func play_battle_scaled(sound_key: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	"""Play a battle sound with volume and pitch scaling for power-based effects"""
	if _try_play_sfx_from_manifest(_battle_player, sound_key, volume_db, pitch_scale):
		return
	if not SOUNDS.has(sound_key):
		return
	# Validate pitch scale to prevent invalid frequencies
	pitch_scale = clamp(pitch_scale, 0.1, 10.0)
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
	if _try_play_sfx_from_manifest(_ability_player, sound_key):
		return
	if SOUNDS.has(sound_key):
		_play_sound(_ability_player, SOUNDS[sound_key])


func register_ability_sound(ability_id: String, sound_key: String) -> void:
	"""Register a custom sound for an ability"""
	_ability_sounds[ability_id] = sound_key


func play_status(status_name: String) -> void:
	"""Play sound for a status effect application (poison, sleep, confuse, paralyze, etc.)"""
	var key = "status_" + status_name.to_lower()
	if _try_play_sfx_from_manifest(_battle_player, key):
		return
	if SOUNDS.has(key):
		_play_sound(_battle_player, SOUNDS[key])
	else:
		# Fallback: generic descending blip for unknown statuses
		_play_sound(_battle_player, {"freq": 350, "duration": 0.2, "type": "descending"})


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
		"dying_fall":
			_generate_dying_fall(playback, samples, freq, sample_rate, duration)
		"woozy":
			_generate_woozy(playback, samples, freq, sample_rate, duration)
		"crackle_lock":
			_generate_crackle_lock(playback, samples, freq, sample_rate, duration)
		"tier_zoom_out":
			_generate_tier_zoom_out(playback, samples, freq, sample_rate, duration)
		"tier_zoom_in":
			_generate_tier_zoom_in(playback, samples, freq, sample_rate, duration)
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


func _generate_dying_fall(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	"""Enemy death: pitch rapidly falls and fades — classic SNES monster defeat chirp"""
	for i in range(samples):
		var t = float(i) / rate
		# Pitch drops fast at the start, then levels off at a low rumble
		var f = freq * pow(0.15, t / dur)
		f = max(f, 40.0)
		# Sharp attack, then decays into silence
		var envelope = pow(1.0 - (t / dur), 1.5)
		# Square-ish wave for retro crunch
		var square = sign(sin(t * f * TAU)) * 0.5
		# Add some noise at the moment of impact
		var noise = randf_range(-0.3, 0.3) * max(0.0, 1.0 - t * 6.0)
		var sample = (square + noise) * envelope
		playback.push_frame(Vector2(sample, sample) * 0.35)


func _generate_woozy(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	"""Status ailment (poison/sleep/confuse): warbling pitch wobble, murky tone"""
	for i in range(samples):
		var t = float(i) / rate
		# Slow wobble — detune effect
		var wobble = sin(t * 4.0 * TAU) * 40.0
		var f = freq + wobble
		# Bell-curve envelope — swell and fade
		var envelope = sin(t / dur * PI)
		# Slightly detuned second harmonic for queasy feel
		var tone = sin(t * f * TAU) * 0.45 + sin(t * f * 1.04 * TAU) * 0.25
		var sample = tone * envelope
		playback.push_frame(Vector2(sample, sample) * 0.28)


func _generate_crackle_lock(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	"""Paralyze: electric crackle that stutters and locks — high-frequency snap"""
	for i in range(samples):
		var t = float(i) / rate
		var envelope = pow(1.0 - (t / dur), 0.8)
		# Stutter pattern: brief silence windows simulate the "lock" of paralysis
		var stutter = 1.0 if fmod(t * 18.0, 1.0) > 0.35 else 0.0
		# High buzz with random crackle
		var buzz = sin(t * freq * TAU) * 0.35
		var crackle = randf_range(-1.0, 1.0) * 0.5 if randf() > 0.55 else 0.0
		var sample = (buzz + crackle) * envelope * stutter
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _generate_tier_zoom_out(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	"""Tier 1 -> Dashboard: whoosh sweep downward, wide stereo spread.
	   Frequency slides from high to low (zooming out perspective)."""
	for i in range(samples):
		var t = float(i) / rate
		var progress = t / dur
		# Pitch sweeps from 2x to 0.4x — steep downward swoop
		var sweep_freq = freq * (2.0 - progress * 1.6)
		var envelope = sin(progress * PI)
		# Noise whoosh underneath — the "air rush" of pulling back
		var noise = randf_range(-1.0, 1.0) * 0.3 * envelope
		var tone = _triangle_wave(t * sweep_freq) * 0.5 * envelope
		var s = (tone + noise) * 0.35
		# Stereo spread: left leads, right slightly delayed for width
		var l = s * (1.0 - progress * 0.3)
		var r = s * (0.7 + progress * 0.3)
		playback.push_frame(Vector2(l, r))


func _generate_tier_zoom_in(playback: AudioStreamGeneratorPlayback, samples: int, freq: float, rate: int, dur: float) -> void:
	"""Dashboard -> Tier 1: sharp rising snap, focused center.
	   Quick ascending blip with a percussive attack — snapping back in."""
	for i in range(samples):
		var t = float(i) / rate
		var progress = t / dur
		# Fast rise then hold — "snap into focus"
		var sweep_freq = freq * (0.5 + progress * 1.2)
		# Sharp attack, quick decay
		var envelope = pow(1.0 - progress, 1.8) if progress > 0.1 else progress * 10.0
		var tone = _pulse_wave(t * sweep_freq, 0.3) * 0.55 * envelope
		# Tight transient click at start
		var click = randf_range(-0.4, 0.4) * max(0.0, 1.0 - progress * 12.0)
		var s = (tone + click) * 0.38
		playback.push_frame(Vector2(s, s))


## ============================================================================
## MUSIC SYSTEM
## ============================================================================
## Stub implementation - generates procedural 16-bit style battle music
## Replace _generate_battle_music() internals with file loading when real
## music assets are available (e.g., load("res://assets/audio/battle.ogg"))

static func _load_music_manifest() -> void:
	if _manifest_loaded:
		return
	_manifest_loaded = true
	var file = FileAccess.open("res://data/music_manifest.json", FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed and parsed.has("tracks"):
		_music_manifest = parsed["tracks"]
		if _music_manifest.size() > 0:
			print("[MUSIC] Loaded music manifest: %d tracks" % _music_manifest.size())


func _try_play_from_manifest(track_id: String) -> bool:
	_load_music_manifest()
	if not _music_manifest.has(track_id):
		return false
	var entry = _music_manifest[track_id]
	var path = entry.get("file", "")
	if path == "":
		return false
	if not path.begins_with("res://"):
		path = "res://" + path
	if not FileAccess.file_exists(path):
		return false
	var stream = load(path) as AudioStream
	if not stream:
		push_warning("[MUSIC] Failed to load audio file: %s" % path)
		return false
	# Set looping based on manifest (default true for music)
	var should_loop = entry.get("loop", true)
	if stream is AudioStreamOggVorbis:
		stream.loop = should_loop
	_music_player.stream = stream
	_music_player.volume_db = _music_base_db
	_music_player.play()
	_music_playing = true
	print("[MUSIC] Playing from manifest: %s (%s) loop=%s" % [track_id, path, should_loop])
	return true


func _get_current_world_suffix() -> String:
	"""Map current area to world suffix for manifest track lookup.
	When _current_area is empty (cleared by play_music for battle/victory),
	returns the last known world suffix so battle music stays world-aware."""
	match _current_area:
		"overworld", "village", "harmonia_village", "cave", "dungeon", "whispering_cave":
			return "medieval"
		"overworld_suburban", "maple_heights_village":
			return "suburban"
		"overworld_steampunk", "brasston_village":
			return "steampunk"
		"overworld_industrial", "rivet_row_village":
			return "industrial"
		"overworld_futuristic", "node_prime_village":
			return "digital"
		"overworld_abstract", "vertex_village":
			return "abstract"
		_:
			# During battles, _current_area is cleared — use persisted suffix
			return _current_world_suffix


func play_music(track: String) -> void:
	"""Play a music track with crossfade transition"""
	if _current_music == track and _music_playing:
		return  # Already playing

	# Clear area tracking so play_area_music() doesn't skip after battle/victory
	_current_area = ""

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

	# Try manifest first — file-based music always takes priority
	_load_music_manifest()
	var manifest_track_id = track
	# Map generic track names to world-specific manifest keys
	match track:
		"battle":
			manifest_track_id = "battle_" + _current_world_suffix
		"boss":
			manifest_track_id = "boss_" + _current_world_suffix
		"danger":
			manifest_track_id = "danger_" + _current_world_suffix
	if _music_manifest.has(manifest_track_id):
		if _try_play_from_manifest(manifest_track_id):
			return

	# Universal music cache — skip expensive generation if this track was already built
	if _music_cache.has(track):
		_music_player.stream = _music_cache[track]
		_music_playing = true
		_music_player.play()
		return

	match track:
		"title":
			_start_title_music()
		"autogrind":
			_start_autogrind_music()
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
		# Terrain-specific battle themes
		"battle_suburban":
			_start_suburban_battle_music()
		"battle_urban":
			_start_urban_battle_music()
		"battle_industrial":
			_start_industrial_battle_music()
		"battle_digital":
			_start_digital_battle_music()
		"battle_void":
			_start_void_battle_music()
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

	# Cache the generated stream for instant replay on future calls
	if _music_player.stream and not _music_cache.has(track):
		_music_cache[track] = _music_player.stream


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

## Corruption audio degradation - as autogrind corruption rises, audio degrades
var _corruption_intensity: float = 0.0  # 0.0 = clean, 1.0 = fully corrupted
var _corruption_tween: Tween = null

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


## Corruption audio degradation - ties into autogrind meta-awareness theme.
## As corruption rises in the grind system, the music subtly degrades:
##   Low corruption  (0.0-0.3): clean, no change
##   Mid corruption  (0.3-0.6): slight detune, hint of pitch drift
##   High corruption (0.6-1.0): heavy detune, pitch wobble, volume flicker

func set_corruption_intensity(intensity: float) -> void:
	"""Set corruption intensity (0.0 = clean, 1.0 = fully corrupted).
	   Maps to autogrind meta_corruption_level / corruption_threshold.
	   Call this each time the autogrind battle ends to update audio degradation."""
	var new_intensity = clamp(intensity, 0.0, 1.0)

	if abs(new_intensity - _corruption_intensity) < 0.04:
		return

	if _corruption_tween and _corruption_tween.is_valid():
		_corruption_tween.kill()

	_corruption_tween = create_tween()
	_corruption_tween.tween_method(_apply_corruption_intensity, _corruption_intensity, new_intensity, 1.5)


func _apply_corruption_intensity(intensity: float) -> void:
	"""Apply corruption degradation to the active music player."""
	_corruption_intensity = intensity

	if not _music_player:
		return

	# Pitch: starts clean, drifts downward with a slow wobble at high corruption.
	# At full corruption: ~half-semitone flat with a 0.8 Hz LFO wobble.
	var flat_offset = -intensity * 0.03
	var wobble_depth = intensity * intensity * 0.018  # quadratic — subtle until high
	var wobble_phase = Time.get_ticks_msec() / 1000.0
	var wobble = sin(wobble_phase * TAU * 0.8) * wobble_depth
	_music_player.pitch_scale = 1.0 + flat_offset + wobble

	# Volume: subtle flicker at high corruption (reality destabilizing)
	var vol_noise = 0.0
	if intensity > 0.6:
		vol_noise = randf_range(0.0, (intensity - 0.6) * 4.0)
	_music_player.volume_db = _music_base_db - vol_noise


func get_corruption_intensity() -> float:
	return _corruption_intensity


func reset_corruption() -> void:
	"""Reset corruption degradation to clean level"""
	if _corruption_tween and _corruption_tween.is_valid():
		_corruption_tween.kill()
	_corruption_intensity = 0.0
	if _music_player:
		_music_player.pitch_scale = 1.0
		_music_player.volume_db = _music_base_db


## Battle Music - Procedural 16-bit Style Loop
## This is a STUB - replace with actual music file when available

var _music_timer: float = 0.0
var _music_buffer: PackedVector2Array = PackedVector2Array()

func _start_battle_music() -> void:
	"""Generate and start looping battle music (cached after first generation)"""
	_music_playing = true
	var suffix = _get_current_world_suffix()
	if _try_play_from_manifest("battle_" + suffix):
		return

	if _music_cache.has("battle_generic"):
		_music_player.stream = _music_cache["battle_generic"]
		_music_player.play()
		return

	# Generate 4 passes (48 bars) for a full loop with dynamic arc:
	#   Pass 0 (bars  1-12): intense opening, clean drums
	#   Pass 1 (bars 13-24): enhanced — harmony voice, extra 16th hats, heavier toms
	#   Pass 2 (bars 25-36): groove half — relaxed classic backbeat, mellow melody octave-down, warm pad
	#   Pass 3 (bars 37-48): groove half repeat — same groove, harmony pad added
	# On loop, returning to pass 0 feels fresh due to the contrast with pass 3.
	var sample_rate = 22050
	var bpm = 140.0
	var beats_per_bar = 4
	var bars = 48  # 4 passes of 12 bars each
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
	_music_cache["battle_generic"] = wav
	_music_player.stream = wav
	_music_player.play()


func _generate_battle_music_buffer(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate a catchy 16-bit battle theme - 48 bars (4 x 12-bar passes).
	Passes 0-1: intense opening with aggressive drums and full-register melody.
	Passes 2-3: groovy second half with classic backbeat, octave-down melody, warm pad."""
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

	# Lead guitar (bars 9-12 only) — finger tapping arpeggios, high register
	const NOTE_A5 = 880.0
	const NOTE_G5 = 783.99
	const NOTE_F5 = 698.46
	const NOTE_B5 = 987.77
	var lead_pattern = [
		NOTE_A4, NOTE_E5, NOTE_A5, NOTE_E5,  NOTE_A4, NOTE_E5, NOTE_A5, NOTE_E5,  # Bar 9: Am tap
		NOTE_A4, NOTE_C5, NOTE_A5, NOTE_C5,  NOTE_E5, NOTE_A5, NOTE_E5, NOTE_C5,
		NOTE_C5, NOTE_G5, NOTE_E5, NOTE_G5,  NOTE_C5, NOTE_E5, NOTE_G5, NOTE_E5,  # Bar 10: C→Dm tap
		NOTE_D5, NOTE_A5, NOTE_F5, NOTE_A5,  NOTE_D5, NOTE_F5, NOTE_A5, NOTE_F5,
		NOTE_E5, NOTE_B5, NOTE_G5, NOTE_B5,  NOTE_E5, NOTE_G5, NOTE_B5, NOTE_G5,  # Bar 11: Em→Am tap
		NOTE_A4, NOTE_E5, NOTE_A5, NOTE_E5,  NOTE_A4, NOTE_A5, NOTE_E5, NOTE_A5,
		NOTE_A4, NOTE_E5, NOTE_A5, NOTE_G5,  NOTE_A4, NOTE_C5, NOTE_A5, NOTE_E5,  # Bar 12: sweep resolve
		NOTE_A5, NOTE_E5, NOTE_A5, NOTE_G5,  NOTE_A5, 0, NOTE_A5, 0,
	]

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

		# Which 12-bar pass are we in?
		# Pass 0 = bars  1-12 (intense, clean)
		# Pass 1 = bars 13-24 (enhanced — harmony, 16th hats, heavier toms)
		# Pass 2 = bars 25-36 (groove half — relaxed backbeat, mellow octave-down melody, warm pad)
		# Pass 3 = bars 37-48 (groove half + pad harmony)
		var pass_num = int(t / (beat_duration * 4 * 12))  # 12 bars per pass
		var bar_in_pass = int(t / (beat_duration * 4)) % 12  # bar within current 12-bar pass
		var is_groove_half = pass_num >= 2  # Second 24 bars: relaxed groove

		# Which note are we on? (wrap around full 12-bar pattern)
		var sixteenth_idx = int(t / sixteenth_duration) % 192  # 12 bars * 16 sixteenths
		var quarter_idx = int(t / quarter_duration) % 48  # 12 bars * 4 quarters

		# Time within current note (for envelope)
		var t_in_sixteenth = fmod(t, sixteenth_duration) / sixteenth_duration
		var t_in_quarter = fmod(t, quarter_duration) / quarter_duration

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY ---
		var melody_freq = melody_pattern[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_duration
			var melody_env = _adsr(note_t, 0.005, 0.04, 0.6, sixteenth_duration * 0.7, sixteenth_duration)

			if is_groove_half:
				# Groove half: melody drops an octave for a mellow, warm feel.
				# Use a softer triangle-dominant tone instead of bright pulse.
				var gmel_freq = melody_freq * 0.5  # One octave down
				var gvfreq = _vibrato_freq(gmel_freq, t, 4.5, 0.0008, 0.40)
				var gmel_wave = _triangle_wave(t * gvfreq) * 0.60
				gmel_wave += _pulse_wave(t * gvfreq, 0.30) * 0.28  # Softer pulse duty
				gmel_wave += _triangle_wave(t * gvfreq * 2.0) * 0.10  # Octave shimmer
				var gmel_vol = 0.17 if sixteenth_idx >= 128 else 0.20  # No lead-duck needed
				var gmv = gmel_wave * melody_env * gmel_vol
				sample_l += gmv * 0.80
				sample_r += gmv * 0.68
			else:
				# Intense half: original bright SNES lead with vibrato + detuned chorus.
				var melody_vol = 0.10 if sixteenth_idx >= 128 else 0.22  # Duck for lead
				var vfreq = _vibrato_freq(melody_freq, t, 5.5, 0.001, 0.35)
				var lead_wave = _pulse_wave(t * vfreq, 0.25) * 0.55
				lead_wave += _pulse_wave(t * vfreq * pow(2.0, 6.0 / 1200.0), 0.25) * 0.28  # +6 cents
				lead_wave += _triangle_wave(t * vfreq * 2.0) * 0.12  # Octave shimmer
				var mv = lead_wave * melody_env * melody_vol
				sample_l += mv * 0.85
				sample_r += mv * 0.72

		# --- PASS 1 HARMONY: Extra voice a 3rd above melody on pass 1 (enhanced repeat) ---
		if pass_num == 1 and melody_freq > 0:
			var harm_freq = melody_freq * 1.2599  # Minor 3rd up
			var harm_vfreq = _vibrato_freq(harm_freq, t, 5.5, 0.001, 0.40)
			var harm_wave = _triangle_wave(t * harm_vfreq) * 0.45
			harm_wave += sin(t * harm_vfreq * TAU) * 0.25
			var harm_note_t = t_in_sixteenth * sixteenth_duration
			var harm_env = _adsr(harm_note_t, 0.005, 0.04, 0.6, sixteenth_duration * 0.7, sixteenth_duration)
			harm_wave *= harm_env * 0.11
			sample_l += harm_wave * 0.45
			sample_r += harm_wave * 0.90

		# --- GROOVE HALF WARM PAD: Sustained chord texture under the mellow melody ---
		# A minor chord: A + C + E, triangle sine blend, slow attack, long sustain.
		# Adds warmth and body so the groove half doesn't feel thin.
		if is_groove_half:
			var pad_root = 220.0  # A3
			var pad_third = 261.63  # C4 (minor 3rd)
			var pad_fifth = 329.63  # E4
			# Slow vibrato for that SNES string pad feel
			var pad_vibrato = 1.0 + sin(t * TAU * 4.8) * 0.0006
			var pad_r = _triangle_wave(t * pad_root * pad_vibrato) * 0.30
			pad_r += sin(t * pad_root * pad_vibrato * TAU) * 0.20
			var pad_t3 = _triangle_wave(t * pad_third * pad_vibrato) * 0.22
			pad_t3 += sin(t * pad_third * pad_vibrato * TAU) * 0.15
			var pad_t5 = _triangle_wave(t * pad_fifth * pad_vibrato) * 0.18
			pad_t5 += sin(t * pad_fifth * pad_vibrato * TAU) * 0.12
			# Slightly detuned upper voice for width (pass 3 only, adds pad harmony)
			var pad_upper: float = 0.0
			if pass_num == 3:
				pad_upper = _triangle_wave(t * pad_root * 2.0 * (1.0 + sin(t * TAU * 4.2) * 0.0005)) * 0.12
			var pad_mix = (pad_r + pad_t3 + pad_t5 + pad_upper) * 0.055
			# Gentle fade-in at start of groove half (first 0.5 beat)
			var groove_t_in_pass = fmod(t, beat_duration * 4.0 * 12.0)
			var pad_fade_in = min(groove_t_in_pass / (beat_duration * 0.5), 1.0)
			pad_mix *= pad_fade_in
			# Spread wide: pad is spacious
			sample_l += pad_mix * 0.80
			sample_r += pad_mix * 1.0

		# --- BASS: Triangle overdrive + sub octave, center ---
		var bass_freq = bass_pattern[quarter_idx] * 0.5  # Octave down
		var bass_note_t = t_in_quarter * quarter_duration
		var bass_env = _adsr(bass_note_t, 0.003, 0.08, 0.75, quarter_duration * 0.8, quarter_duration)
		if is_groove_half:
			# Groove half: gentler bass — use lower drive level for a rounder, less aggressive tone.
			# The _snes_bass function uses tanh(tri * 2.2) internally; we compensate by scaling
			# the output down and relying more on the sub component for warmth over punch.
			var bass_raw = _snes_bass(t, bass_freq)
			var bass_val = bass_raw * 0.17 * bass_env  # 0.22 → 0.17 (less driven feel)
			sample_l += bass_val
			sample_r += bass_val
		else:
			var bass_val = _snes_bass(t, bass_freq) * 0.22 * bass_env
			sample_l += bass_val
			sample_r += bass_val

		# --- DRUMS ---
		var beat_pos = fmod(t, beat_duration)
		var beat_in_bar = int(t / beat_duration) % 4

		if is_groove_half:
			# -------------------------------------------------------
			# GROOVE DRUMS: Classic SNES RPG backbeat — clean and steady.
			# No tom fills, no double kicks, no extra 16ths, no crashes.
			# Kick: beats 1 and 3.
			# Snare: beats 2 and 4 (standard backbeat).
			# Hi-hat: every 8th note (closed), open hi-hat on "and" of beat 4.
			# -------------------------------------------------------

			# Kick: beats 1 and 3 only — clean, moderate volume
			if beat_in_bar in [0, 2] and beat_pos < 0.10:
				var kick = _snes_kick(beat_pos, 0.090)
				sample_l += kick * 0.48
				sample_r += kick * 0.48

			# Snare: classic backbeat on 2 and 4 — slightly softer than intense half
			if beat_in_bar in [1, 3] and beat_pos < 0.10:
				var snare = _snes_snare(beat_pos, 0.090)
				sample_l += snare * 0.72
				sample_r += snare * 0.78

			# Hi-hat: closed on every 8th note
			var eighth_pos_g = fmod(t, beat_duration / 2.0)
			var eighth_count_g = int(t / (beat_duration / 2.0)) % 2
			# Open hi-hat on the "and" of beat 4 (beat_in_bar == 3, off-beat 8th)
			var is_and_of_beat4 = (beat_in_bar == 3) and (eighth_count_g == 1)
			if eighth_pos_g < 0.045:
				var hat_g = _snes_hihat(eighth_pos_g, 0.018, is_and_of_beat4)
				# Pan slightly right for that classic stereo feel
				sample_l += hat_g * 0.58
				sample_r += hat_g * 0.88

		else:
			# -------------------------------------------------------
			# INTENSE DRUMS: Original aggressive patterns for passes 0-1.
			# -------------------------------------------------------

			# Crash cymbal on bar 1 of pass 1 (the enhanced repeat)
			if pass_num == 1 and bar_in_pass == 0 and beat_pos < 0.22:
				var crash = _snes_crash(beat_pos, 0.20) * 0.55
				sample_l += crash * 0.80
				sample_r += crash

			# Kick on beats 1 and 3
			if beat_pos < 0.10:
				var kick = _snes_kick(beat_pos, 0.095)
				# Slightly heavier in pass 1 bars 5-8
				if pass_num == 1 and bar_in_pass >= 4 and bar_in_pass < 8:
					kick *= 1.15
				sample_l += kick * 0.55
				sample_r += kick * 0.55

			# Double kick on "and" of beat 4 in pass 1 (every even bar)
			if pass_num == 1 and bar_in_pass % 2 == 0:
				var double_kick_pos = fmod(t - beat_duration * 3.5, beat_duration)
				if double_kick_pos >= 0.0 and double_kick_pos < 0.08:
					var dk = _snes_kick(double_kick_pos, 0.075) * 0.50
					sample_l += dk
					sample_r += dk

			# Snare on 2 and 4
			if beat_in_bar in [1, 3] and beat_pos < 0.10:
				var snare = _snes_snare(beat_pos, 0.095)
				sample_l += snare * 0.85
				sample_r += snare * 0.92

			# Hi-hat on every 8th note, open on off-beats
			var eighth_pos = fmod(t, beat_duration / 2.0)
			var is_on_beat = fmod(t / (beat_duration / 2.0), 2.0) < 1.0
			if eighth_pos < 0.045:
				var hat = _snes_hihat(eighth_pos, 0.018, not is_on_beat)
				sample_l += hat * 0.65
				sample_r += hat * 1.0

			# Extra 16th-note hi-hats in pass 1 (between the 8th notes)
			if pass_num == 1:
				var sixteenth_pos_hat = fmod(t, beat_duration / 4.0)
				var sixteenth_count = int(t / (beat_duration / 4.0)) % 4
				if sixteenth_count % 2 == 1 and sixteenth_pos_hat < 0.015:
					var extra_hat = _snes_hihat(sixteenth_pos_hat, 0.012, false) * 0.35
					sample_l += extra_hat * 0.60
					sample_r += extra_hat * 0.95

			# Tom fills on last beat of bar 4 and bar 8 (in every intense pass)
			if beat_in_bar == 3 and bar_in_pass % 4 == 3:
				var sub_beat = fmod(beat_pos * 4.0, 1.0)
				var sub_idx = int(beat_pos * 4.0) % 4
				var tom_pitches = [200.0, 150.0, 110.0, 80.0]
				if sub_beat < 0.12:
					var tom_vol = 0.50 if pass_num == 0 else 0.70
					var tom = _snes_tom(sub_beat * (beat_duration / 4.0), tom_pitches[sub_idx], 0.10) * tom_vol
					sample_l += tom * 0.85
					sample_r += tom * 0.95

		# --- LEAD GUITAR: Tapping arpeggios bars 9-12, panned right (intense half only) ---
		if not is_groove_half and sixteenth_idx >= 128:
			var lead_idx = sixteenth_idx - 128
			var lead_freq = lead_pattern[lead_idx]
			if lead_freq > 0:
				var lead_env = sqrt(max(1.0 - t_in_sixteenth, 0.0))
				var lead_raw = _pulse_wave(t * lead_freq, 0.25) * 0.50
				lead_raw += _square_wave(t * lead_freq * 2.0) * 0.30
				lead_raw += _square_wave(t * lead_freq * 1.004) * 0.18  # Slight detune
				lead_raw += _sine_wave(t * lead_freq * 3.0) * 0.08  # 12th shimmer
				var lead_dist = clamp(lead_raw * 2.5, -1.0, 1.0)
				var lead_vol = lead_dist * lead_env * 0.32
				sample_l += lead_vol * 0.65
				sample_r += lead_vol * 1.0

		# --- COUNTER-MELODY: Triangle, panned right, enters section B (intense half only) ---
		if not is_groove_half and sixteenth_idx >= 64 and sixteenth_idx < 128:
			var cm_idx = sixteenth_idx - 64
			var cm_freq = melody_pattern[cm_idx]
			if cm_freq > 0:
				cm_freq *= 1.25  # Approximate major third up
				var cm_env = pow(1.0 - t_in_sixteenth, 0.5)
				var cm = _triangle_wave(t * cm_freq) * 0.10 * cm_env
				sample_l += cm * 0.5
				sample_r += cm * 0.9

		# Soft clip for warmth.
		# Groove half: lighter drive + lower ceiling for dynamic contrast (~1.5 dB quieter).
		if is_groove_half:
			sample_l = tanh(sample_l * 0.95) * 0.78
			sample_r = tanh(sample_r * 0.95) * 0.78
		else:
			sample_l = tanh(sample_l * 1.15) * 0.88
			sample_r = tanh(sample_r * 1.15) * 0.88
		buffer.append(Vector2(sample_l, sample_r))

	# Post-process: reverb for SNES room depth
	return _apply_reverb(buffer, 0.25, 0.14)


func _start_victory_music() -> void:
	"""Play victory fanfare intro then loop into 80s rock victory theme"""
	_music_playing = true
	if _try_play_from_manifest("victory"):
		return

	var sample_rate = 22050
	var bpm = 140.0
	var beat_duration = 60.0 / bpm

	# Fanfare intro: 2 seconds (non-looping)
	var intro_duration = 2.0
	var intro_buffer = _generate_victory_fanfare(sample_rate, intro_duration)

	# Metal loop: 16 bars at 160 BPM — rhythm builds, then tapping lead shreds
	bpm = 160.0
	beat_duration = 60.0 / bpm
	var bars = 16
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
		var sample_l = 0.0
		var sample_r = 0.0

		# Arpeggio phase — SNES brass-style pulse notes
		if t < chord_start:
			for j in range(4):
				if t >= note_times[j]:
					var note_t = t - note_times[j]
					var env = pow(max(0, 1.0 - note_t / 0.5), 0.4)
					# Brass fanfare: pulse + detuned copy
					var freq = notes[j]
					var voice = _pulse_wave(note_t * freq, 0.25) * 0.50
					voice += _pulse_wave(note_t * freq * pow(2.0, 7.0 / 1200.0), 0.25) * 0.25
					voice += _triangle_wave(note_t * freq * 2.0) * 0.12  # Octave shimmer
					var v = voice * env * 0.22
					# Stereo spread: low notes left, high notes right
					var pan = float(j) / 3.0  # 0..1
					sample_l += v * (1.0 - pan * 0.3)
					sample_r += v * (0.7 + pan * 0.3)

		# Sustained chord phase — lush SNES string-pad sustain
		else:
			var chord_t = t - chord_start
			var env = pow(max(0, 1.0 - chord_t / (duration - chord_start)), 0.25)
			for ni in range(notes.size()):
				var note = notes[ni]
				# Layered triangle + detuned + sine for string-pad warmth
				var vib = 1.0 + sin(chord_t * 5.2 * TAU) * 0.007
				var v = _triangle_wave(chord_t * note * vib) * 0.40
				v += _triangle_wave(chord_t * note * pow(2.0, 5.0 / 1200.0)) * 0.22
				v += sin(chord_t * note * TAU) * 0.18
				v *= env * 0.16
				# Stereo spread for chorus width
				var pan = float(ni) / float(notes.size() - 1)
				sample_l += v * (1.0 - pan * 0.25)
				sample_r += v * (0.75 + pan * 0.25)

		sample_l = tanh(sample_l * 1.1) * 0.88
		sample_r = tanh(sample_r * 1.1) * 0.88
		buffer.append(Vector2(sample_l, sample_r))

	# Fanfare gets generous reverb for that triumphant hall sound
	return _apply_reverb(buffer, 0.40, 0.20)


func _generate_victory_rock_loop(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate epic metal victory loop — heavy riffs, double kick, shred lead"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm
	var bar_duration = beat_duration * 4

	# E minor / E power chord key — classic metal
	const E2 = 82.41
	const G2 = 98.0
	const A2 = 110.0
	const B2 = 123.47
	const C3 = 130.81
	const D3 = 146.83
	const E3 = 164.81
	const G3 = 196.0
	const A3 = 220.0
	const B3 = 246.94
	const D4 = 293.66
	const E4 = 329.63
	const G4 = 392.0
	const A4 = 440.0
	const B4 = 493.88
	const D5 = 587.33
	const E5 = 659.25
	const G5 = 783.99

	# Galloping power chord progression: E - G - A - B | E - G - A - E (triumphant metal)
	var chord_roots = [E2, G2, A2, B2, E2, G2, A2, E2]
	var chord_fifths = [B2, D3, E3, G2 * 1.5, B2, D3, E3, B2]

	# Melodic lead (bars 1-8): 1 note per beat (32 positions, repeats for bars 9-16 rhythm)
	var lead_notes = [
		E5, D5, B4, A4,   G4, A4, B4, D5,   # Bar 1-2: descend then climb
		E5, G5, E5, D5,   B4, D5, E5, G5,   # Bar 3-4: high register
		A4, B4, D5, E5,   D5, B4, A4, G4,   # Bar 5-6: run up and down
		E4, G4, A4, B4,   D5, E5, G5, E5,   # Bar 7-8: build to climax
	]

	# Tapping arpeggios (bars 9-16): 64 sixteenth notes, wide intervals, E minor
	# Classic Van Halen-style: low-mid-HIGH-mid groups
	const A5 = 880.0
	const B5 = 987.77
	var tapping = [
		E4, B4, E5, B4,   E4, B4, E5, B4,   # Bar 9: Em arp tap
		E4, G4, E5, G4,   E4, G5, E5, G5,
		G4, D5, G5, D5,   G4, D5, G5, D5,   # Bar 10: G arp tap
		G4, B4, G5, B4,   G4, B4, G5, B4,
		A4, E5, A5, E5,   A4, E5, A5, E5,   # Bar 11: Am arp tap
		A4, D5, A5, D5,   A4, E5, A5, E5,
		B4, E5, B5, E5,   B4, G5, B5, G5,   # Bar 12: Bm arp tap
		E4, B4, E5, B4,   E5, G5, A5, B5,
		E4, B4, E5, B4,   E4, G5, E5, G5,   # Bar 13: Em repeat with variation
		E4, G4, E5, G4,   G5, E5, G5, E5,
		A4, E5, A5, E5,   A4, G5, A5, G5,   # Bar 14: Am variation
		A4, D5, A5, D5,   A4, E5, A5, E5,
		B4, E5, B5, E5,   B4, G5, B5, G5,   # Bar 15: Bm climax
		G4, D5, G5, D5,   A4, E5, A5, E5,
		E4, B4, E5, G5,   E4, G4, E5, B4,   # Bar 16: resolve back to Em
		E4, B4, E5, B4,   E5, G5, E5, B4,
	]

	for i in range(samples):
		var t = float(i) / rate
		var beat = t / beat_duration
		var bar = int(t / bar_duration) % 16
		var beat_in_bar = fmod(t, bar_duration) / beat_duration
		var sample_l = 0.0
		var sample_r = 0.0

		# === DRUMS (double kick metal) ===
		var beat_pos = fmod(t, beat_duration)
		var eighth_pos = fmod(t, beat_duration / 2.0)

		# Double kick: every eighth note (metal gallop)
		if eighth_pos < 0.06:
			var kick_env = pow(1.0 - eighth_pos / 0.06, 1.5)
			var kick_freq = 60.0 * (1.0 + kick_env * 3.0)
			var kick = sin(eighth_pos * kick_freq * TAU) * kick_env * 0.30
			# Add low-end punch
			kick += _triangle_wave(eighth_pos * 40.0) * kick_env * 0.15
			sample_l += kick
			sample_r += kick

		# Snare on 2 and 4 — tight, metallic
		if (int(beat) % 4 == 1 or int(beat) % 4 == 3) and beat_pos < 0.08:
			var snare_env = pow(1.0 - beat_pos / 0.08, 0.6)
			var noise = (randf() * 2.0 - 1.0)
			var snare_body = sin(beat_pos * 250.0 * TAU) * 0.25
			var snare_ring = sin(beat_pos * 400.0 * TAU) * 0.1 * snare_env
			var snare = (noise * 0.35 + snare_body + snare_ring) * snare_env * 0.25
			sample_l += snare
			sample_r += snare

		# Crash cymbal on bar 1 and 5 (beat 0)
		var total_beat = int(beat) % 32
		if (total_beat == 0 or total_beat == 16) and beat_pos < 0.5:
			var crash_env = pow(max(0.0, 1.0 - beat_pos / 0.5), 2.0)
			var crash = (randf() * 2.0 - 1.0) * crash_env * 0.12
			sample_l += crash
			sample_r += crash

		# Sixteenth note hi-hat (fast metal hat)
		var sixteenth_pos = fmod(t, beat_duration / 4.0)
		if sixteenth_pos < 0.012:
			var hat_env = 1.0 - sixteenth_pos / 0.012
			var hat = (randf() * 2.0 - 1.0) * hat_env * 0.07
			sample_l += hat
			sample_r += hat

		# === BASS (aggressive, distorted) ===
		var root = chord_roots[bar % 8]
		var bass_phase = t * root
		# Heavy distorted bass: square + clipped triangle
		var bass_raw = _square_wave(bass_phase) * 0.5 + _triangle_wave(bass_phase) * 0.3
		var bass = clamp(bass_raw * 2.0, -1.0, 1.0) * 0.14  # Overdrive clipping
		bass += _triangle_wave(bass_phase * 0.5) * 0.06  # Sub octave rumble
		# Gallop rhythm: emphasis on 1-and-a pattern
		var gallop_pos = fmod(t, beat_duration)
		var gallop_env = 0.7
		if gallop_pos < beat_duration * 0.15:
			gallop_env = 1.0  # Downbeat accent
		elif gallop_pos > beat_duration * 0.5 and gallop_pos < beat_duration * 0.65:
			gallop_env = 0.9  # "And" accent
		elif gallop_pos > beat_duration * 0.75 and gallop_pos < beat_duration * 0.9:
			gallop_env = 0.85  # "A" accent
		bass *= gallop_env
		sample_l += bass
		sample_r += bass

		# === RHYTHM GUITAR (heavy distorted power chords, panned hard L/R) ===
		var fifth = chord_fifths[bar % 8]
		# Galloping palm-mute pattern
		var chord_env = 0.3
		var gallop_t = fmod(t, beat_duration)
		if gallop_t < beat_duration * 0.12:
			chord_env = 1.0  # Down
		elif gallop_t > beat_duration * 0.5 and gallop_t < beat_duration * 0.62:
			chord_env = 0.9  # And
		elif gallop_t > beat_duration * 0.75 and gallop_t < beat_duration * 0.87:
			chord_env = 0.85  # A

		# Distorted guitar: stack harmonics and clip
		var gtr_raw_l = _square_wave(t * root * 2) * 0.4
		gtr_raw_l += _square_wave(t * fifth * 2) * 0.35
		gtr_raw_l += _pulse_wave(t * root * 4, 0.3) * 0.15  # Octave harmonic
		gtr_raw_l = clamp(gtr_raw_l * 2.5, -1.0, 1.0)  # Hard clip distortion

		var gtr_raw_r = _square_wave(t * root * 2 + 0.005) * 0.4
		gtr_raw_r += _square_wave(t * fifth * 2 + 0.005) * 0.35
		gtr_raw_r += _pulse_wave(t * root * 4 + 0.005, 0.35) * 0.15
		gtr_raw_r = clamp(gtr_raw_r * 2.5, -1.0, 1.0)

		var gtr_vol = 0.06 if bar >= 8 else 0.10  # Duck rhythm for tapping lead
		sample_l += gtr_raw_l * chord_env * gtr_vol
		sample_r += gtr_raw_r * chord_env * gtr_vol

		# === LEAD GUITAR ===
		if bar < 8:
			# Bars 1-8: melodic lead (1 note per beat, moderate volume)
			var lead_beat_idx = int(beat) % 32
			var lead_note = lead_notes[lead_beat_idx]
			var lead_t = fmod(t, beat_duration)
			var lead_env = min(1.0, lead_t * 30.0)
			lead_env *= max(0.0, 1.0 - max(0.0, lead_t - beat_duration * 0.85) / (beat_duration * 0.15))
			var lead_phase = t * lead_note
			var lead_raw = _square_wave(lead_phase) * 0.5 + _pulse_wave(lead_phase, 0.35) * 0.3
			lead_raw += _square_wave(lead_phase * 2.0) * 0.1
			var lead = clamp(lead_raw * 2.0, -1.0, 1.0) * lead_env * 0.15
			sample_l += lead * 0.6
			sample_r += lead * 1.0
		else:
			# Bars 9-16: TAPPING ARPEGGIOS — screaming, fast, loud
			var sixteenth_duration = beat_duration / 4.0
			var tap_sixteenth = int(fmod(t, bar_duration * 8) / sixteenth_duration)
			var tap_idx = tap_sixteenth % tapping.size()
			var tap_freq = tapping[tap_idx]
			if tap_freq > 0:
				var tap_t = fmod(t, sixteenth_duration) / sixteenth_duration
				# Tapping: percussive attack, sqrt decay
				var tap_env = sqrt(max(1.0 - tap_t, 0.0))
				# Bright screaming tone: pulse + octave harmonic + hard clip
				var tap_raw = _pulse_wave(t * tap_freq, 0.25) * 0.45
				tap_raw += _square_wave(t * tap_freq * 2.0) * 0.30  # Octave up harmonic
				tap_raw += _square_wave(t * tap_freq * 1.003) * 0.15  # Slight detune
				tap_raw += _sine_wave(t * tap_freq * 3.0) * 0.10  # 12th harmonic shimmer
				var tap = clamp(tap_raw * 3.0, -1.0, 1.0) * tap_env * 0.22
				sample_l += tap * 0.7
				sample_r += tap * 1.0

		# === MIX ===
		sample_l = tanh(sample_l * 1.1) * 0.92
		sample_r = tanh(sample_r * 1.1) * 0.92
		buffer.append(Vector2(sample_l, sample_r))

	# Victory rock: short arena reverb
	return _apply_reverb(buffer, 0.28, 0.12)


## Boss Battle Music - Intense, menacing theme

func _start_boss_music() -> void:
	"""Generate and start looping boss battle music"""
	_music_playing = true
	var suffix = _get_current_world_suffix()
	if _try_play_from_manifest("boss_" + suffix):
		return

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

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: Aggressive SNES lead with vibrato + detuned layer ---
		var melody_freq = melody_pattern[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_duration
			var melody_env = _adsr(note_t, 0.004, 0.035, 0.65, sixteenth_duration * 0.75, sixteenth_duration)
			# Boss lead: harsh pulse + detuned square for menace (depth halved, delay increased)
			var vfreq = _vibrato_freq(melody_freq, t, 5.0, 0.001, 0.35)
			var mel = _pulse_wave(t * vfreq, 0.25) * 0.50
			mel += _square_wave(t * vfreq * 1.004) * 0.28   # Thick detune
			mel += _square_wave(t * vfreq * 0.997) * 0.15   # Lower detune for width
			mel += _triangle_wave(t * vfreq * 2.0) * 0.08   # Octave shimmer
			mel = tanh(mel * 1.6) * 0.7  # Light saturation for bite
			mel *= melody_env * 0.24
			sample_l += mel * 0.80
			sample_r += mel * 0.95

		# --- BASS: Heavy overdrive bass, center ---
		var bass_freq = bass_pattern[quarter_idx] * 0.5
		var bass_note_t = t_in_quarter * quarter_duration
		var bass_env = _adsr(bass_note_t, 0.003, 0.06, 0.80, quarter_duration * 0.85, quarter_duration)
		var bass_val = _snes_bass(t, bass_freq) * 0.28 * bass_env
		sample_l += bass_val
		sample_r += bass_val

		# --- DRUMS: Double-kick boss pattern with proper SNES drums ---
		var beat_pos = fmod(t, beat_duration)

		# Double kick: downbeat + half-beat
		if beat_pos < 0.10:
			var kick = _snes_kick(beat_pos, 0.095)
			sample_l += kick * 0.65
			sample_r += kick * 0.65

		var half_beat_pos = beat_pos - beat_duration * 0.5
		if half_beat_pos >= 0.0 and half_beat_pos < 0.09:
			var kick2 = _snes_kick(half_beat_pos, 0.085) * 0.80  # Slightly softer second kick
			sample_l += kick2 * 0.65
			sample_r += kick2 * 0.65

		# Snare on 2 and 4 with extra punch
		var beat_in_bar = int(t / beat_duration) % 4
		if beat_in_bar in [1, 3] and beat_pos < 0.11:
			var snare = _snes_snare(beat_pos, 0.105)
			# Boss snare: boost volume + add extra crack layer
			var crack = randf_range(-0.2, 0.2) * pow(max(0.0, 1.0 - beat_pos * 20.0), 2)
			sample_l += (snare + crack) * 0.90
			sample_r += (snare + crack) * 0.92

		# 16th note hi-hats for driving urgency
		var sixteenth_pos = fmod(t, beat_duration / 4.0)
		if sixteenth_pos < 0.025:
			var hat = _snes_hihat(sixteenth_pos, 0.022, false)
			sample_l += hat * 0.70
			sample_r += hat * 1.0

		# Crash accent on bar 1 of each 4-bar phrase
		var phrase_beat = int(t / beat_duration) % 16
		if phrase_beat == 0 and beat_pos < 0.35:
			var crash_env = pow(max(0.0, 1.0 - beat_pos / 0.35), 2.5)
			var crash_noise = randf_range(-0.15, 0.15) * crash_env
			sample_l += crash_noise
			sample_r += crash_noise

		# Tom fills on last beat of bars 4 and 8 (every 4-bar phrase end)
		var bar_in_loop = int(t / (beat_duration * 4)) % 16
		if beat_in_bar == 3 and bar_in_loop % 4 == 3:
			var sub_beat_pos = fmod(beat_pos * 4.0, 1.0)
			var sub_idx = int(beat_pos * 4.0) % 4
			var tom_pitches_b = [220.0, 160.0, 120.0, 85.0]
			if sub_beat_pos < 0.12:
				var tom_b = _snes_tom(sub_beat_pos * (beat_duration / 4.0), tom_pitches_b[sub_idx], 0.10) * 0.65
				sample_l += tom_b * 0.80
				sample_r += tom_b * 0.95

		# Soft clip + tanh warmth
		sample_l = tanh(sample_l * 1.3) * 0.88
		sample_r = tanh(sample_r * 1.3) * 0.88
		buffer.append(Vector2(sample_l, sample_r))

	# Post-process: light reverb for boss arena depth
	return _apply_reverb(buffer, 0.30, 0.15)


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
				# Second voice slightly detuned for thickness (not vibrato)
				sq += sign(sin(t * (melody_note * 1.005) * TAU)) * 0.06 * env
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

		# Occasional shaker/scratch sound (rat scurrying) - panned randomly
		if current_beat % 8 == 3 and beat_pos > beat_duration * 0.5 and beat_pos < beat_duration * 0.7:
			var scratch_t = (beat_pos - beat_duration * 0.5) / (beat_duration * 0.2)
			var scratch = randf_range(-0.1, 0.1) * (1.0 - scratch_t)
			sample += scratch

		# Slight stereo: melody slightly left, bass center
		var s = tanh(sample * 1.18) * 0.84
		buffer.append(Vector2(s * 0.92, s))

	return _apply_reverb(buffer, 0.22, 0.12)


## Danger Music - Dark, urgent theme when player is about to die

func _start_danger_music() -> void:
	"""Generate and start looping danger/critical HP music — world-specific"""
	_music_playing = true
	var suffix = _get_current_world_suffix()
	if _try_play_from_manifest("danger_" + suffix):
		return
	if _try_play_from_manifest("danger"):
		return

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

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: Harsh chromatic lead - panic and urgency ---
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_duration
			var melody_env = _adsr(note_t, 0.003, 0.030, 0.70, sixteenth_duration * 0.80, sixteenth_duration)
			# Danger lead: detuned squares for dissonant urgency
			var mel = _square_wave(t * melody_freq) * 0.50
			mel += _square_wave(t * melody_freq * 1.008) * 0.28  # Chromatic beating
			mel += _pulse_wave(t * melody_freq, 0.30) * 0.20    # Narrow pulse for tension
			mel = tanh(mel * 1.4) * 0.8  # Light clip for edge
			mel *= melody_env * 0.22
			sample_l += mel * 0.88
			sample_r += mel * 0.88

		# --- BASS: Deep rumbling pedal, very heavy ---
		var bass_freq = bass[quarter_idx]
		var bass_env = 0.85 + 0.15 * sin(t_in_quarter * PI)
		var bass_val = _snes_bass(t, bass_freq * 0.5) * 0.32 * bass_env
		sample_l += bass_val
		sample_r += bass_val

		# --- DRUMS: Heartbeat kick on every beat, urgent hats + variation ---
		var beat_pos = fmod(t, beat_duration)
		var beat_in_bar_d = int(t / beat_duration) % 4
		var bar_in_loop_d = int(t / (beat_duration * 4)) % 8

		# Heavy heartbeat kick on every single beat
		if beat_pos < 0.10:
			var kick = _snes_kick(beat_pos, 0.095) * 0.75
			sample_l += kick
			sample_r += kick

		# Anxious 8th-note hi-hats (closed)
		var eighth_pos = fmod(t, beat_duration / 2.0)
		if eighth_pos < 0.020:
			var hat = _snes_hihat(eighth_pos, 0.018, false) * 0.65
			sample_l += hat * 0.80
			sample_r += hat * 1.0

		# 16th-note hi-hat accents between 8th notes (off-16ths) — adds urgency
		var sixteenth_pos_d = fmod(t, beat_duration / 4.0)
		var sixteenth_count_d = int(t / (beat_duration / 4.0)) % 4
		if sixteenth_count_d % 2 == 1 and sixteenth_pos_d < 0.015:
			var extra_hat_d = _snes_hihat(sixteenth_pos_d, 0.012, false) * 0.40
			sample_l += extra_hat_d * 0.72
			sample_r += extra_hat_d * 0.95

		# Tom fill on last beat of bar 4 and bar 8
		# beat_pos is time in seconds (0..beat_duration), sixteenth_pos_d is within a 16th
		if beat_in_bar_d == 3 and bar_in_loop_d % 4 == 3:
			var sub_idx_d = int(beat_pos / (beat_duration / 4.0)) % 4  # which 16th (0-3)
			var tom_pitches_d = [210.0, 155.0, 115.0, 80.0]
			if sixteenth_pos_d < 0.12:
				var tom_d = _snes_tom(sixteenth_pos_d, tom_pitches_d[sub_idx_d], 0.11) * 0.60
				sample_l += tom_d * 0.85
				sample_r += tom_d

		# Tension noise bed (swelling)
		var noise_level = 0.025 + 0.018 * sin(t * 1.8 * TAU)
		var noise = randf_range(-noise_level, noise_level)
		sample_l += noise
		sample_r += noise * 0.85

		# Hard clip for urgency
		sample_l = clamp(tanh(sample_l * 1.4) * 0.92, -0.96, 0.96)
		sample_r = clamp(tanh(sample_r * 1.4) * 0.92, -0.96, 0.96)
		buffer.append(Vector2(sample_l, sample_r))

	# Short reverb only - danger should feel dry and close
	return _apply_reverb(buffer, 0.15, 0.10)


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


## ============================================================================
## SNES-QUALITY SYNTHESIS HELPERS
## These upgrade the sound from "Atari potato" to "Super Nintendo warmth"
## ============================================================================

func _adsr(t: float, attack: float, decay: float, sustain: float, release_start: float, release_end: float) -> float:
	"""Full ADSR envelope.
	   attack: time in seconds to reach peak
	   decay: time in seconds from peak to sustain level
	   sustain: level (0-1) held during sustain phase
	   release_start: time in seconds when release begins
	   release_end: time in seconds when sound fully fades"""
	if t < 0.0:
		return 0.0
	elif t < attack:
		return t / attack
	elif t < attack + decay:
		var d = (t - attack) / decay
		return 1.0 - d * (1.0 - sustain)
	elif t < release_start:
		return sustain
	elif t < release_end:
		var r = (t - release_start) / (release_end - release_start)
		return sustain * (1.0 - r)
	else:
		return 0.0


func _vibrato_freq(base_freq: float, t: float, rate: float = 5.5, depth: float = 0.001, delay: float = 0.30) -> float:
	"""Vibrato disabled. Returns base_freq unchanged."""
	return base_freq


func _chorus_voice(t: float, freq: float, detune_cents: float, wave_type: String = "triangle") -> float:
	"""Single detuned oscillator voice for chorus layering.
	   detune_cents: cents of pitch offset (100 cents = 1 semitone)
	   Layer multiple calls with opposite detune signs for warmth."""
	var detuned_freq = freq * pow(2.0, detune_cents / 1200.0)
	match wave_type:
		"square":
			return _square_wave(t * detuned_freq)
		"pulse25":
			return _pulse_wave(t * detuned_freq, 0.25)
		"soft_square":
			return _soft_square(t * detuned_freq)
		"sine":
			return sin(t * detuned_freq * TAU)
		_:  # triangle
			return _triangle_wave(t * detuned_freq)


func _snes_lead(t: float, freq: float, vibrato_delay: float = 0.40) -> float:
	"""Classic SNES lead tone: pulse wave + detuned copy. Vibrato removed."""
	# Primary: 25% pulse wave (SNES-like nasal lead)
	var voice1 = _pulse_wave(t * freq, 0.25) * 0.5
	# Secondary: slightly detuned pulse for chorus warmth (3 cents)
	var voice2 = _pulse_wave(t * freq * pow(2.0, 3.0 / 1200.0), 0.25) * 0.25
	# Tertiary: triangle octave up for shimmer
	var voice3 = _triangle_wave(t * freq * 2.0) * 0.15
	return voice1 + voice2 + voice3


func _snes_bass(t: float, freq: float) -> float:
	"""SNES-style punchy bass: triangle overdrive + sub doubling.
	   Triangle clipped softly = warm overdrive without harshness."""
	var tri = _triangle_wave(t * freq)
	# Soft overdrive: tanh for warm saturation
	var driven = tanh(tri * 2.2) * 0.6
	# Sub octave reinforcement
	var sub = sin(t * freq * 0.5 * TAU) * 0.35
	return driven + sub


func _snes_kick(beat_pos: float, duration: float = 0.08) -> float:
	"""Proper SNES-style kick: pitch-sweeping sine (200Hz→40Hz) + noise burst.
	   This is the 'thwump' sound, not a buzzy low sine."""
	if beat_pos >= duration:
		return 0.0
	var t = beat_pos / duration
	var env = pow(1.0 - t, 1.5)
	# Pitch exponentially sweeps from high to low
	var pitch = 180.0 * pow(0.15, t) + 35.0
	var tone = sin(beat_pos * pitch * TAU) * env * 0.7
	# Short noise burst at attack for punch
	var noise_env = max(0.0, 1.0 - beat_pos * 25.0)
	var noise = randf_range(-0.3, 0.3) * noise_env
	return tone + noise


func _snes_snare(beat_pos: float, duration: float = 0.09) -> float:
	"""SNES-style snare: bandpass-ish noise + mid-frequency tone body.
	   Mix of white noise + 180-220Hz sine for body."""
	if beat_pos >= duration:
		return 0.0
	var t = beat_pos / duration
	var env = pow(1.0 - t, 1.2)
	# Noise component (the 'crack')
	var noise = randf_range(-0.6, 0.6) * env * 0.55
	# Tonal body (the 'snare wire ring')
	var body = sin(beat_pos * 195.0 * TAU) * env * 0.25
	var ring = sin(beat_pos * 380.0 * TAU) * env * 0.12
	return noise + body + ring


func _snes_hihat(hat_pos: float, duration: float = 0.018, is_open: bool = false) -> float:
	"""Very short high-frequency noise burst for hi-hat."""
	var dur = 0.045 if is_open else duration
	if hat_pos >= dur:
		return 0.0
	var env = pow(1.0 - hat_pos / dur, 3.0)
	return randf_range(-0.18, 0.18) * env


func _snes_tom(beat_pos: float, pitch_hz: float = 150.0, duration: float = 0.10) -> float:
	"""SNES-style tom: pitch-sweeping sine (like kick but higher pitched, shorter).
	   pitch_hz: starting pitch (150=hi-tom, 100=mid-tom, 70=lo-tom)"""
	if beat_pos >= duration:
		return 0.0
	var t = beat_pos / duration
	var env = pow(1.0 - t, 1.2)
	# Pitch sweeps from pitch_hz down by about 60%
	var pitch = pitch_hz * pow(0.40, t)
	var tone = sin(beat_pos * pitch * TAU) * env * 0.65
	# Light noise attack for initial transient
	var noise_env = max(0.0, 1.0 - beat_pos * 30.0)
	var noise = randf_range(-0.2, 0.2) * noise_env
	return tone + noise


func _snes_crash(crash_pos: float, duration: float = 0.20) -> float:
	"""SNES-style crash cymbal: white noise burst with longer decay."""
	if crash_pos >= duration:
		return 0.0
	var env = pow(1.0 - crash_pos / duration, 1.8)
	# High-frequency noise with slight metallic shimmer
	var noise = randf_range(-0.25, 0.25) * env
	var shimmer = sin(crash_pos * 3800.0 * TAU) * env * 0.06
	var shimmer2 = sin(crash_pos * 5700.0 * TAU) * env * 0.03
	return noise + shimmer + shimmer2


func _apply_reverb(buffer: PackedVector2Array, room_size: float = 0.3, wet: float = 0.18, sample_rate: int = 22050) -> PackedVector2Array:
	"""Simple Schroeder-style reverb simulation via multiple delay taps.
	   Runs as a post-process on a completed buffer.
	   room_size: 0-1 (0=tight, 1=huge hall)
	   wet: 0-1 mix of reverb signal (0.12-0.25 is natural)
	   sample_rate: the rate the buffer was generated at (default 22050)"""
	var size = buffer.size()
	if size == 0:
		return buffer

	# Delay tap times in samples - prime-ish multiples for good diffusion
	# Uses actual sample_rate so delays stay correct at 16000 or 22050 Hz
	var base_rate = sample_rate
	var delays = [
		int(base_rate * 0.029 * (0.5 + room_size * 0.5)),  # ~29ms early reflection
		int(base_rate * 0.043 * (0.5 + room_size * 0.5)),  # ~43ms
		int(base_rate * 0.067 * (0.5 + room_size * 0.5)),  # ~67ms
		int(base_rate * 0.101 * (0.5 + room_size * 0.5)),  # ~101ms
	]
	var gains = [0.5, 0.35, 0.25, 0.15]

	# Allpass comb filters (feedback delays) for diffusion
	var comb_delays = [
		int(base_rate * 0.0297 * (0.6 + room_size * 0.4)),
		int(base_rate * 0.0371 * (0.6 + room_size * 0.4)),
	]
	var comb_gain = 0.55 + room_size * 0.15

	# Build reverb tail into a separate buffer
	var rev = PackedVector2Array()
	rev.resize(size)

	# Early reflections (delay taps)
	for tap_i in range(delays.size()):
		var d = delays[tap_i]
		var g = gains[tap_i] * wet
		for s in range(size):
			var src = s - d
			if src >= 0:
				var v = buffer[src]
				var cur = rev[s]
				# Swap channels slightly for stereo diffusion
				rev[s] = Vector2(cur.x + v.x * g, cur.y + v.y * g * 0.92)

	# Simple feedback comb for tail decay
	for ci in range(comb_delays.size()):
		var d = comb_delays[ci]
		var g = comb_gain * wet * 0.4
		var prev_l = 0.0
		var prev_r = 0.0
		for s in range(size):
			var src = s - d
			if src >= 0:
				prev_l = rev[src].x
				prev_r = rev[src].y
			var cur = rev[s]
			rev[s] = Vector2(cur.x + prev_l * g, cur.y + prev_r * g)

	# Mix dry + reverb, apply final limiting
	var out = PackedVector2Array()
	out.resize(size)
	for s in range(size):
		var dry = buffer[s]
		var r = rev[s]
		var l_out = clamp(dry.x + r.x, -0.98, 0.98)
		var r_out = clamp(dry.y + r.y, -0.98, 0.98)
		out[s] = Vector2(l_out, r_out)

	return out


func _stereo_spread(sample_l: float, sample_r: float, pan: float) -> Vector2:
	"""Pan a stereo signal. pan: -1.0 (full left) to +1.0 (full right).
	   Uses constant-power panning law."""
	var angle = (pan + 1.0) * 0.25 * PI  # 0 to PI/2
	return Vector2(sample_l * cos(angle), sample_r * sin(angle))


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
	"""Start monster-specific battle music — unique per monster type"""
	_music_playing = true

	# Check cache first (monster-specific proc-gen themes)
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
		var sample_l = 0.0
		var sample_r = 0.0

		# Dynamic volume based on section (build and release)
		var section_dynamics = [0.85, 0.9, 1.0, 0.95, 1.0, 0.9]
		var dyn = section_dynamics[section % 6] if section < 6 else 0.9

		# --- MELODY: SNES-quality lead with vibrato + detuned chorus ---
		var melody_idx = (bar * 16 + int(beat_pos * 4)) % melody.size()
		var melody_note = melody[melody_idx]
		if melody_note > 0:
			var note_phase = fmod(t * melody_note, 1.0)
			var base_wave = _get_monster_wave(note_phase, params["style"])
			# Add detuned second voice for chorus warmth
			var detune_phase = fmod(t * melody_note * pow(2.0, 6.0 / 1200.0), 1.0)
			var detune_wave = _get_monster_wave(detune_phase, params["style"])
			# Add subtle vibrato on lead voice
			var vib_freq = melody_note * (1.0 + sin(t * 5.2 * TAU) * 0.002 * clamp((t - 0.30) * 10.0, 0.0, 1.0))
			var vib_wave = sin(t * vib_freq * TAU) * 0.12  # Sine shimmer
			var env = _get_monster_envelope(beat_pos, params["style"])
			var mel_vol = (base_wave * 0.65 + detune_wave * 0.25 + vib_wave) * 0.26 * env * dyn
			# Pan melody left
			sample_l += mel_vol * 0.92
			sample_r += mel_vol * 0.72

		# --- COUNTER-MELODY: Harmonizing voice, panned right ---
		if section >= 1 and counter.size() > 0:
			var counter_idx = (bar * 8 + int(beat_pos * 2)) % counter.size()
			var counter_note = counter[counter_idx]
			if counter_note > 0:
				var counter_phase = fmod(t * counter_note, 1.0)
				var counter_wave = _triangle_wave(counter_phase)
				# Slight vibrato on counter-melody too
				counter_wave += sin(t * counter_note * (1.0 + sin(t * 5.0 * TAU) * 0.002 * clamp((t - 0.30) * 10.0, 0.0, 1.0)) * TAU) * 0.15
				var counter_env = 0.7 + 0.3 * (1.0 - fmod(beat_pos * 2, 1.0))
				var counter_vol = counter_wave * 0.14 * counter_env * (dyn * 0.8)
				# Pan counter-melody right
				sample_l += counter_vol * 0.55
				sample_r += counter_vol * 1.0

		# --- BASS: SNES-quality overdrive bass ---
		var bass_idx = (bar * 4 + int(beat_pos)) % bass_notes.size()
		var bass_note = bass_notes[bass_idx]
		if bass_note > 0:
			var bass_freq = bass_note
			if section >= 3 and int(beat_pos) == 0 and bar % 4 == 0:
				bass_freq *= 2.0  # Octave up on downbeat every 4 bars
			var bass_env = _get_bass_envelope(beat_pos, params["bass_style"])
			var bass_val = _snes_bass(t, bass_freq) * 0.20 * bass_env * dyn
			sample_l += bass_val
			sample_r += bass_val

		# --- DRUMS: SNES kick/snare with crash and tom fills ---
		var drum_raw = _get_monster_drums(beat_pos, t, params["style"])
		var drum_vol = 0.90 * dyn  # Scale applied inside _get_monster_drums already
		if bar % 8 == 7 and beat_pos >= 3.0:
			drum_vol *= 1.25  # Louder fill
		# Drums center with slight right bias for snare crack
		sample_l += drum_raw * drum_vol * 0.88
		sample_r += drum_raw * drum_vol * 0.95

		# Crash cymbal on bar 1 of each 8-bar section
		if bar % 8 == 0 and beat_pos < 0.18:
			# Convert fractional beat to time: crash_pos = fraction within first beat * beat_duration
			var crash_t_m = beat_pos * beat_duration
			var crash_m = _snes_crash(crash_t_m, 0.18) * 0.45 * dyn
			sample_l += crash_m * 0.80
			sample_r += crash_m

		# Tom fill descending on the last beat of every 4th bar
		var beat_in_bar_m = int(beat_pos)
		if bar % 4 == 3 and beat_in_bar_m == 3:
			# sub_beat_m: fraction within beat 4 (0.0 to 1.0)
			var sub_beat_m = beat_pos - 3.0  # 0.0 to 1.0
			var sub_idx_m = int(sub_beat_m * 4.0) % 4  # which 16th note (0-3)
			var sub_16th_pos = fmod(sub_beat_m * 4.0, 1.0)  # position within 16th note
			var tom_pitches_m = [160.0, 120.0, 90.0, 65.0]
			# Hit at the start of each 16th note within the tom fill
			if sub_16th_pos < 0.15:
				var tom_time = sub_16th_pos * beat_duration * 0.25  # time within 16th note
				var tom_m = _snes_tom(tom_time, tom_pitches_m[sub_idx_m], 0.09) * 0.50 * dyn
				sample_l += tom_m * 0.85
				sample_r += tom_m * 0.95

		# Warm tanh soft clip
		sample_l = tanh(sample_l * 1.12) * 0.88
		sample_r = tanh(sample_r * 1.12) * 0.88
		buffer.append(Vector2(sample_l, sample_r))

	# Reverb scaled by style - sparse styles get more, frantic less
	var reverb_amount = 0.13
	match params["style"]:
		"ethereal": reverb_amount = 0.22
		"creepy": reverb_amount = 0.20
		"spooky": reverb_amount = 0.18
		"tribal": reverb_amount = 0.10
		"frantic": reverb_amount = 0.08
	return _apply_reverb(buffer, 0.25, reverb_amount, rate)


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
	if _try_play_from_manifest("game_over"):
		return

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
var _current_world_suffix: String = "medieval"
var _pending_music_area: String = ""

func play_area_music(area_type: String) -> void:
	"""Play appropriate music for an exploration area.
	Generation is deferred to the next frame so it does not block scene setup."""
	if _current_area == area_type and _music_playing:
		return  # Already playing

	_current_area = area_type
	_current_world_suffix = _get_current_world_suffix()
	_pending_music_area = area_type
	stop_music()

	call_deferred("_start_area_music_deferred", area_type)


func _start_area_music_deferred(area_type: String) -> void:
	"""Actually generate and start music - called deferred so scene renders first."""
	if _pending_music_area != area_type:
		return  # A newer area was requested before this ran; skip stale call

	match area_type:
		"overworld":
			_start_overworld_music()
		"overworld_suburban":
			_start_suburban_music()
		"overworld_steampunk":
			_start_steampunk_music()
		"overworld_industrial":
			_start_industrial_music()
		"overworld_futuristic":
			_start_futuristic_music()
		"overworld_abstract":
			_start_abstract_music()
		"village", "harmonia_village":
			_start_village_music()
		"maple_heights_village":
			_start_village_world_music("suburban")
		"brasston_village":
			_start_village_world_music("steampunk")
		"rivet_row_village":
			_start_village_world_music("industrial")
		"node_prime_village":
			_start_village_world_music("digital")
		"vertex_village":
			_start_village_world_music("abstract")
		"cave", "dungeon", "whispering_cave":
			_start_cave_music()
		_:
			_start_overworld_music()


func _start_overworld_music() -> void:
	"""Generate peaceful overworld exploration theme"""
	_music_playing = true
	if _try_play_from_manifest("overworld_medieval"):
		return
	print("[MUSIC] Playing overworld theme")
	if _play_area_wav_cached("overworld"):
		return

	var sample_rate = 22050
	var bpm = 100.0
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_overworld_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "overworld")


func _start_village_music() -> void:
	"""Generate peaceful village theme"""
	_music_playing = true
	if _try_play_from_manifest("village_medieval"):
		return
	print("[MUSIC] Playing village theme")
	if _play_area_wav_cached("village"):
		return

	var sample_rate = 22050
	var bpm = 80.0
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_village_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "village")


func _start_village_world_music(world_suffix: String) -> void:
	"""Play world-specific village music from manifest, fall back to generic village"""
	_music_playing = true
	if _try_play_from_manifest("village_" + world_suffix):
		return
	_start_village_music()


func _start_cave_music() -> void:
	"""Generate mysterious dungeon/cave theme"""
	_music_playing = true
	if _try_play_from_manifest("dungeon_medieval"):
		return
	print("[MUSIC] Playing cave/dungeon theme")
	if _play_area_wav_cached("cave"):
		return

	var sample_rate = 22050
	var bpm = 90.0
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_cave_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "cave")


func _start_title_music() -> void:
	"""Generate majestic EarthBound-style trippy title theme"""
	_music_playing = true
	if _try_play_from_manifest("title"):
		return
	print("[MUSIC] Playing title theme")
	if _play_area_wav_cached("title"):
		return

	var sample_rate = 22050
	var bpm = 72.0  # Slow and majestic
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_title_music_buffer(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "title")


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
			var vibrato = sin(t * 5.5) * 0.006
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


func _create_and_play_looping_wav(buffer: PackedVector2Array, sample_rate: int, area_cache_key: String = "") -> void:
	"""Helper to create looping WAV from buffer. Caches the result by area_cache_key if provided."""
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

	if area_cache_key != "":
		_area_wav_cache[area_cache_key] = wav

	_music_player.stream = wav
	_music_player.play()


func _play_area_wav_cached(area_key: String) -> bool:
	"""Play a cached area WAV if available. Returns true on cache hit."""
	if _area_wav_cache.has(area_key):
		print("[MUSIC] Cache hit for area: %s" % area_key)
		_music_player.stream = _area_wav_cache[area_key]
		_music_player.play()
		_music_playing = true
		return true
	return false


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
		var t_in_quarter = fmod(t, quarter_dur) / quarter_dur

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: SNES triangle lead with vibrato, panned slightly left ---
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_dur
			var melody_env = _adsr(note_t, 0.008, 0.055, 0.70, sixteenth_dur * 0.75, sixteenth_dur)
			# Warm overworld lead: vibrato triangle + detuned copy for chorus (depth halved)
			var vfreq = _vibrato_freq(melody_freq, t, 4.8, 0.001, 0.35)
			var mel = _triangle_wave(t * vfreq) * 0.55
			mel += _triangle_wave(t * vfreq * pow(2.0, 5.0 / 1200.0)) * 0.28  # +5 cents
			mel += _triangle_wave(t * vfreq * pow(2.0, -4.0 / 1200.0)) * 0.18  # -4 cents
			mel += sin(t * vfreq * TAU) * 0.12  # Sine for roundness
			mel *= melody_env * 0.20
			# Counter-harmony a 6th above (SNES layered voices)
			var harm_freq = melody_freq * 1.667  # Major 6th
			var harm = _triangle_wave(t * _vibrato_freq(harm_freq, t, 4.8, 0.001, 0.35)) * 0.12 * melody_env
			sample_l += mel * 0.90 + harm * 0.45
			sample_r += mel * 0.75 + harm * 0.90

		# --- BASS: Warm triangle overdrive + sub, center ---
		var bass_freq = bass[quarter_idx] * 0.5
		var bass_note_t = t_in_quarter * quarter_dur
		var bass_env = _adsr(bass_note_t, 0.004, 0.10, 0.72, quarter_dur * 0.82, quarter_dur)
		var bass_val = _snes_bass(t, bass_freq) * 0.19 * bass_env
		sample_l += bass_val
		sample_r += bass_val

		# --- DRUMS: Light walking rhythm ---
		var beat_pos = fmod(t, beat_duration)
		var beat_in_bar = int(t / beat_duration) % 4

		# Gentle kick on beats 1 and 3 only
		if beat_in_bar in [0, 2] and beat_pos < 0.09:
			var kick = _snes_kick(beat_pos, 0.085) * 0.60
			sample_l += kick
			sample_r += kick

		# Soft snare on 2 and 4
		if beat_in_bar in [1, 3] and beat_pos < 0.09:
			var snare = _snes_snare(beat_pos, 0.085) * 0.55
			sample_l += snare * 0.85
			sample_r += snare

		# Light hi-hat on off-beats (8ths)
		var eighth_pos = fmod(t, beat_duration / 2.0)
		if eighth_pos < 0.020:
			var hat = _snes_hihat(eighth_pos, 0.018, false) * 0.50
			sample_l += hat * 0.70
			sample_r += hat

		# tanh soft limiting
		sample_l = tanh(sample_l * 1.10) * 0.85
		sample_r = tanh(sample_r * 1.10) * 0.85
		buffer.append(Vector2(sample_l, sample_r))

	# Reverb: medium hall for open-air overworld feel
	return _apply_reverb(buffer, 0.35, 0.16)


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
		var t_in_quarter = fmod(t, quarter_dur) / quarter_dur

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: Warm flute-like lead with vibrato ---
		var melody_freq = melody[eighth_idx]
		if melody_freq > 0:
			var note_t = t_in_eighth * eighth_dur
			var melody_env = _adsr(note_t, 0.012, 0.06, 0.78, eighth_dur * 0.80, eighth_dur)
			# Flute-like: sine + triangle with warm vibrato (depth halved)
			var vfreq = _vibrato_freq(melody_freq, t, 4.5, 0.001, 0.35)
			var mel = sin(t * vfreq * TAU) * 0.55         # Sine fundamental (flute)
			mel += _triangle_wave(t * vfreq) * 0.32       # Triangle for body
			mel += sin(t * vfreq * 2.0 * TAU) * 0.10     # Octave harmonic
			mel *= melody_env * 0.20
			# Harmony a third above for warmth (pastoral feel)
			var h_freq = _vibrato_freq(melody_freq * 1.25, t, 4.5, 0.001, 0.35)
			var harm = (sin(t * h_freq * TAU) * 0.6 + _triangle_wave(t * h_freq) * 0.3) * melody_env * 0.10
			# Lead slightly left, harmony slightly right
			sample_l += mel * 0.95 + harm * 0.40
			sample_r += mel * 0.75 + harm * 1.0

		# --- BASS: Pizzicato-style (short decay pluck) ---
		var bass_freq = bass[quarter_idx] * 0.5
		var bass_note_t = t_in_quarter * quarter_dur
		# Short pluck envelope: fast attack, fast decay (pizzicato)
		var pluck_env = exp(-bass_note_t * 8.0)
		var bass_val = sin(t * bass_freq * TAU) * 0.55 + _triangle_wave(t * bass_freq) * 0.30
		bass_val *= 0.16 * pluck_env
		sample_l += bass_val
		sample_r += bass_val

		# --- PERCUSSION: Very light (triangle/woodblock only) ---
		var beat_pos = fmod(t, beat_duration)
		var beat_in_bar = int(t / beat_duration) % 4

		# Soft kick on beat 1 only
		if beat_in_bar == 0 and beat_pos < 0.07:
			var kick = _snes_kick(beat_pos, 0.065) * 0.38
			sample_l += kick
			sample_r += kick

		# Woodblock-like rim on 2 and 4
		if beat_in_bar in [1, 3] and beat_pos < 0.015:
			var rim_env = pow(1.0 - beat_pos / 0.015, 3.0)
			var rim = sin(beat_pos * 900.0 * TAU) * rim_env * 0.09
			sample_l += rim * 0.80
			sample_r += rim

		# Shaker / triangle bell on 8th notes (very quiet)
		var eighth_pos = fmod(t, beat_duration / 2.0)
		if eighth_pos < 0.012:
			var shaker = randf_range(-0.06, 0.06) * pow(1.0 - eighth_pos / 0.012, 3.0)
			sample_l += shaker * 0.75
			sample_r += shaker

		# Soft limit
		sample_l = tanh(sample_l * 1.05) * 0.82
		sample_r = tanh(sample_r * 1.05) * 0.82
		buffer.append(Vector2(sample_l, sample_r))

	# Warm hall reverb for cozy village feel
	return _apply_reverb(buffer, 0.28, 0.18)


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
		var t_in_quarter = fmod(t, quarter_dur) / quarter_dur

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: Eerie hollow lead (triangle + slow vibrato) ---
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_dur
			var melody_env = _adsr(note_t, 0.015, 0.08, 0.60, sixteenth_dur * 0.70, sixteenth_dur)
			# Hollow cave lead: triangle with slight vibrato + detuned copy (depth halved)
			var vfreq = _vibrato_freq(melody_freq, t, 3.8, 0.001, 0.35)
			var mel = _triangle_wave(t * vfreq) * 0.55
			mel += _triangle_wave(t * vfreq * 1.008) * 0.30  # Detuned for eerie beating
			mel += sin(t * vfreq * TAU) * 0.15               # Sine for hollow quality
			mel *= melody_env * 0.18
			# Pan slightly to alternate ears for cave echo effect
			sample_l += mel * 0.92
			sample_r += mel * 0.72

		# --- BASS: Deep drone pedal tone ---
		var bass_freq = bass[quarter_idx] * 0.5
		var bass_note_t = t_in_quarter * quarter_dur
		var bass_env = _adsr(bass_note_t, 0.008, 0.12, 0.85, quarter_dur * 0.88, quarter_dur)
		# Pure deep sine for cave resonance
		var bass_tone = sin(t * bass_freq * TAU) * 0.65 + sin(t * bass_freq * 0.5 * TAU) * 0.25
		var bass_val = bass_tone * 0.20 * bass_env
		sample_l += bass_val
		sample_r += bass_val

		# --- PERCUSSION: Very sparse ---
		var beat_pos = fmod(t, beat_duration)
		var beat_in_bar = int(t / beat_duration) % 4

		# Deep cave thud on beat 1 only
		if beat_in_bar == 0 and beat_pos < 0.10:
			var kick = _snes_kick(beat_pos, 0.095) * 0.40
			sample_l += kick
			sample_r += kick

		# --- DRIP EFFECT: Stereo panned cave drips ---
		var drip_time_l = fmod(t * 1.7, 2.5)
		if drip_time_l < 0.035:
			var drip_env = pow(1.0 - drip_time_l / 0.035, 2.5)
			var drip_l = sin(drip_time_l * 1800.0 * TAU) * drip_env * 0.08
			sample_l += drip_l

		var drip_time_r = fmod(t * 1.3 + 0.8, 2.1)
		if drip_time_r < 0.035:
			var drip_env = pow(1.0 - drip_time_r / 0.035, 2.5)
			var drip_r = sin(drip_time_r * 2200.0 * TAU) * drip_env * 0.07
			sample_r += drip_r

		# Subtle cave ambience noise
		sample_l += randf_range(-0.012, 0.012)
		sample_r += randf_range(-0.012, 0.012)

		sample_l = tanh(sample_l * 1.05) * 0.84
		sample_r = tanh(sample_r * 1.05) * 0.84
		buffer.append(Vector2(sample_l, sample_r))

	# Large reverb for cave/dungeon echo
	return _apply_reverb(buffer, 0.50, 0.22)


## ============================================================
## SUBURBAN MUSIC - EarthBound-inspired 90s suburban themes
## ============================================================

func _start_suburban_music() -> void:
	"""Generate EarthBound-inspired suburban overworld theme - cheerful with eerie undercurrent"""
	_music_playing = true
	if _try_play_from_manifest("overworld_suburban"):
		return
	print("[MUSIC] Playing suburban overworld theme")
	if _play_area_wav_cached("suburban"):
		return

	var sample_rate = 22050
	var bpm = 120.0  # Upbeat walking-around-town pace
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_suburban_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "suburban")


func _generate_suburban_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate EarthBound-style suburban overworld theme - G major, bright and bouncy.
	   Features: bouncy bass, mellow triangle lead, light percussion, slightly 'off' undercurrent.
	   Think Onett theme - happy on the surface, subtly eerie underneath."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# G major with occasional blue notes for that EarthBound "off" feeling
	const NOTE_G2 = 98.0
	const NOTE_A2 = 110.0
	const NOTE_B2 = 123.47
	const NOTE_C3 = 130.81
	const NOTE_D3 = 146.83
	const NOTE_E3 = 164.81
	const NOTE_Fs3 = 185.0
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_B3 = 246.94
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_Fs4 = 369.99
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88
	const NOTE_Bb3 = 233.08  # Blue note - slightly eerie
	const NOTE_Eb4 = 311.13  # Blue note

	# Melody - bouncy, cheerful, with occasional unexpected notes
	# 128 sixteenth notes = 8 bars of 4/4
	var melody = [
		# Bar 1 - Bright opening phrase
		NOTE_G4, 0, NOTE_B4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_E4, 0, NOTE_D4, 0, NOTE_E4, 0, 0, 0,
		# Bar 2 - Playful bounce
		NOTE_D4, 0, NOTE_E4, 0, NOTE_G4, 0, NOTE_A4, 0, NOTE_B4, 0, 0, 0, NOTE_A4, 0, 0, 0,
		# Bar 3 - Slightly off (blue note snuck in)
		NOTE_G4, 0, NOTE_Fs4, 0, NOTE_E4, 0, NOTE_Eb4, 0, NOTE_D4, 0, 0, 0, NOTE_E4, 0, NOTE_G4, 0,
		# Bar 4 - Resolution
		NOTE_A4, 0, 0, 0, NOTE_G4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		# Bar 5 - Second phrase, higher energy
		NOTE_B4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_E4, 0, NOTE_G4, 0, NOTE_A4, 0, NOTE_B4, 0, 0, 0,
		# Bar 6 - Syncopated bounce
		0, 0, NOTE_A4, 0, 0, 0, NOTE_G4, 0, NOTE_E4, 0, NOTE_D4, 0, NOTE_E4, 0, NOTE_G4, 0,
		# Bar 7 - Eerie detour (more blue notes)
		NOTE_Bb3, 0, NOTE_C4, 0, NOTE_D4, 0, NOTE_Eb4, 0, NOTE_D4, 0, NOTE_C4, 0, NOTE_B3, 0, 0, 0,
		# Bar 8 - Return to bright
		NOTE_D4, 0, NOTE_G4, 0, NOTE_Fs4, 0, NOTE_G4, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	]

	# Bass - bouncy, walking bassline (EarthBound style)
	# 32 quarter notes = 8 bars
	var bass = [
		NOTE_G2, NOTE_B2, NOTE_D3, NOTE_B2, NOTE_G2, NOTE_A2, NOTE_B2, NOTE_D3,
		NOTE_C3, NOTE_E3, NOTE_G3, NOTE_E3, NOTE_C3, NOTE_D3, NOTE_E3, NOTE_G3,
		NOTE_G2, NOTE_B2, NOTE_D3, NOTE_G3, NOTE_Fs3, NOTE_E3, NOTE_D3, NOTE_B2,
		NOTE_C3, NOTE_D3, NOTE_G2, NOTE_A2, NOTE_B2, NOTE_D3, NOTE_G2, NOTE_G2,
	]

	var sixteenth_dur = beat_duration / 4.0
	var quarter_dur = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_dur) % 128
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur
		var t_in_quarter = fmod(t, quarter_dur) / quarter_dur

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: Mellow EarthBound triangle lead with chorus + vibrato ---
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_dur
			var melody_env = _adsr(note_t, 0.010, 0.06, 0.72, sixteenth_dur * 0.78, sixteenth_dur)
			var vfreq = _vibrato_freq(melody_freq, t, 4.5, 0.001, 0.35)
			# EarthBound-style: triangle lead with detuned warmth
			var mel = _triangle_wave(t * vfreq) * 0.55
			mel += _triangle_wave(t * vfreq * pow(2.0, 5.0 / 1200.0)) * 0.28  # +5 cents chorus
			mel += _pulse_wave(t * vfreq * 0.5, 0.4) * 0.08  # Sub-octave character
			mel += sin(t * vfreq * TAU) * 0.10  # Sine for smoothness
			mel *= melody_env * 0.18
			sample_l += mel * 0.88
			sample_r += mel * 0.78

		# --- BASS: Bouncy EarthBound funk bass (quick pluck decay) ---
		var bass_freq = bass[quarter_idx]
		# Faster decay for EarthBound funk bounce
		var pluck_env = exp(-t_in_quarter * quarter_dur * 5.5)
		var bass_val = (_square_wave(t * bass_freq * 0.5) * 0.55 + sin(t * bass_freq * 0.5 * TAU) * 0.35) * 0.16 * pluck_env
		sample_l += bass_val
		sample_r += bass_val

		# --- PERCUSSION: Snappy EarthBound drum machine ---
		var beat_pos = fmod(t, quarter_dur)
		var beat_in_bar = int(t / quarter_dur) % 4

		# Lighter kick on 1 and 3
		if beat_in_bar in [0, 2] and beat_pos < 0.075:
			var kick = _snes_kick(beat_pos, 0.070) * 0.48
			sample_l += kick
			sample_r += kick

		# Snappy rim-style snare on 2 and 4
		if beat_in_bar in [1, 3] and beat_pos < 0.065:
			var snare = _snes_snare(beat_pos, 0.060) * 0.55
			sample_l += snare * 0.82
			sample_r += snare

		# Tight 8th note hi-hat with off-beat accent
		var eighth_pos = fmod(t, quarter_dur * 0.5)
		var is_offbeat = fmod(t / (quarter_dur * 0.5), 2.0) >= 1.0
		if eighth_pos < 0.018:
			var hat = _snes_hihat(eighth_pos, 0.016, false) * (0.65 if is_offbeat else 0.40)
			sample_l += hat * 0.72
			sample_r += hat

		# --- EERIE UNDERCURRENT: Wandering low tone (EarthBound signature) ---
		var eerie_freq = 82.0 + sin(t * 0.3) * 5.0
		var eerie = sin(t * eerie_freq * TAU) * 0.012 * (0.5 + 0.5 * sin(t * 0.7))
		sample_l += eerie * 0.85
		sample_r += eerie * 1.15  # Slightly more on right for unsettling feel

		sample_l = tanh(sample_l * 1.08) * 0.85
		sample_r = tanh(sample_r * 1.08) * 0.85
		buffer.append(Vector2(sample_l, sample_r))

	# Light suburban reverb - not too big, just a small room
	return _apply_reverb(buffer, 0.22, 0.13)


func _start_suburban_battle_music() -> void:
	"""Generate EarthBound-style funky/psychedelic suburban battle theme"""
	_music_playing = true
	if _try_play_from_manifest("battle_suburban"):
		return
	print("[MUSIC] Playing suburban battle theme")

	var sample_rate = 22050
	var bpm = 140.0  # Urgent, energetic
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_suburban_battle_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _generate_suburban_battle_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate EarthBound-style suburban battle theme - E minor, funky and psychedelic.
	   Features: syncopated bassline, quirky lead, driving drums, chromatic runs.
	   Think fighting a Cranky Lady or Skate Punk - quirky and intense."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# E minor with chromatic/blues accents for funky psychedelic feel
	const NOTE_E2 = 82.41
	const NOTE_G2 = 98.0
	const NOTE_A2 = 110.0
	const NOTE_B2 = 123.47
	const NOTE_D3 = 146.83
	const NOTE_E3 = 164.81
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_Bb3 = 233.08
	const NOTE_B3 = 246.94
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_Ds4 = 311.13  # Blue note
	const NOTE_E4 = 329.63
	const NOTE_Fs4 = 369.99
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88
	const NOTE_C5 = 523.25
	const NOTE_D5 = 587.33
	const NOTE_E5 = 659.26

	# Melody - quirky, syncopated, chromatic runs
	# 128 sixteenth notes = 8 bars of 4/4
	var melody = [
		# Bar 1 - Punchy opening riff
		NOTE_E4, 0, NOTE_E4, NOTE_G4, 0, NOTE_A4, 0, NOTE_B4, NOTE_A4, 0, NOTE_G4, 0, NOTE_E4, 0, 0, 0,
		# Bar 2 - Funky syncopation
		0, NOTE_D4, 0, NOTE_E4, 0, 0, NOTE_G4, 0, NOTE_Fs4, 0, NOTE_E4, 0, NOTE_Ds4, 0, NOTE_E4, 0,
		# Bar 3 - Chromatic ascending run
		NOTE_E4, NOTE_Fs4, NOTE_G4, NOTE_A4, NOTE_B4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_E4, 0, NOTE_D4, 0, 0, 0,
		# Bar 4 - Call and response
		NOTE_B4, 0, NOTE_C5, 0, NOTE_B4, 0, NOTE_A4, 0, 0, 0, NOTE_G4, 0, NOTE_E4, 0, 0, 0,
		# Bar 5 - Higher energy second phrase
		NOTE_E5, 0, NOTE_D5, 0, NOTE_B4, 0, 0, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_A4, 0, NOTE_B4, 0,
		# Bar 6 - Psychedelic bend feel (chromatic descent)
		NOTE_D5, 0, NOTE_C5, 0, NOTE_B4, 0, NOTE_Bb3, 0, NOTE_A3, 0, NOTE_B3, 0, NOTE_E4, 0, 0, 0,
		# Bar 7 - Driving repeated notes
		NOTE_E4, NOTE_E4, 0, NOTE_G4, NOTE_G4, 0, NOTE_A4, NOTE_A4, 0, NOTE_B4, 0, NOTE_A4, NOTE_G4, 0, NOTE_E4, 0,
		# Bar 8 - Resolution with attitude
		NOTE_B4, 0, NOTE_A4, NOTE_G4, NOTE_E4, 0, NOTE_D4, 0, NOTE_E4, 0, 0, 0, 0, 0, 0, 0,
	]

	# Bass - funky, syncopated, EarthBound-style walking/slapping
	# 32 quarter notes = 8 bars
	var bass = [
		NOTE_E2, NOTE_E2, NOTE_G2, NOTE_A2, NOTE_E2, NOTE_B2, NOTE_A2, NOTE_G2,
		NOTE_E2, NOTE_E2, NOTE_D3, NOTE_E3, NOTE_D3, NOTE_B2, NOTE_A2, NOTE_G2,
		NOTE_A2, NOTE_A2, NOTE_B2, NOTE_D3, NOTE_E3, NOTE_E3, NOTE_D3, NOTE_B2,
		NOTE_E2, NOTE_G2, NOTE_A2, NOTE_B2, NOTE_E2, NOTE_E2, NOTE_E2, NOTE_E2,
	]

	var sixteenth_dur = beat_duration / 4.0
	var quarter_dur = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_dur) % 128
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur
		var t_in_quarter = fmod(t, quarter_dur) / quarter_dur

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: Nasal EarthBound battle lead with chorus ---
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_dur
			var melody_env = _adsr(note_t, 0.004, 0.032, 0.68, sixteenth_dur * 0.78, sixteenth_dur)
			# EarthBound battle: narrow pulse (nasal) + detuned copy
			var mel = _pulse_wave(t * melody_freq, 0.28) * 0.55
			mel += _pulse_wave(t * melody_freq * 1.008, 0.30) * 0.28  # Detuned
			mel += _square_wave(t * melody_freq * 0.998) * 0.15        # Slight wide detune
			mel = tanh(mel * 1.3) * 0.78  # Light saturation
			mel *= melody_env * 0.20
			sample_l += mel * 0.85
			sample_r += mel * 0.80

		# --- BASS: Punchy EarthBound slap bass ---
		var bass_freq = bass[quarter_idx] * 0.5
		var pluck_env = exp(-t_in_quarter * quarter_dur * 4.0)  # Tight pluck
		var bass_val = _snes_bass(t, bass_freq) * 0.18 * pluck_env
		sample_l += bass_val
		sample_r += bass_val

		# --- DRUMS: Driving EarthBound funky drums ---
		var beat_pos = fmod(t, quarter_dur)
		var beat_in_bar = int(t / quarter_dur) % 4

		# Kick on 1 and 3
		if beat_in_bar in [0, 2] and beat_pos < 0.080:
			var kick = _snes_kick(beat_pos, 0.075) * 0.55
			sample_l += kick
			sample_r += kick

		# Crisp snare on 2 and 4
		if beat_in_bar in [1, 3] and beat_pos < 0.075:
			var snare = _snes_snare(beat_pos, 0.070) * 0.70
			sample_l += snare * 0.80
			sample_r += snare

		# Funky 16th note hi-hat (accented off-beats)
		var sixteenth_pos = fmod(t, sixteenth_dur)
		var local_sixteenth = int(t / sixteenth_dur) % 4
		if sixteenth_pos < 0.020:
			var is_offbeat = local_sixteenth % 2 != 0
			var hat = _snes_hihat(sixteenth_pos, 0.018, false) * (0.80 if is_offbeat else 0.45)
			sample_l += hat * 0.72
			sample_r += hat

		# Tom fill on last beat of every 4th bar
		var bar_sb = int(t / (quarter_dur * 4)) % 8
		if beat_in_bar == 3 and bar_sb % 4 == 3:
			# sixteenth_pos is already computed: fmod(t, sixteenth_dur)
			var sub_idx_sb = int(beat_pos / sixteenth_dur) % 4  # which 16th within beat
			var tom_pitches_sb = [190.0, 145.0, 105.0, 75.0]
			if sixteenth_pos < 0.13:
				var tom_sb = _snes_tom(sixteenth_pos, tom_pitches_sb[sub_idx_sb], 0.10) * 0.55
				sample_l += tom_sb * 0.80
				sample_r += tom_sb * 0.90

		# Crash on bar 1 of loop
		var abs_bar_sb = int(t / (quarter_dur * 4)) % 16
		if abs_bar_sb == 0 and beat_in_bar == 0 and beat_pos < 0.20:
			var crash_sb = _snes_crash(beat_pos, 0.18) * 0.45
			sample_l += crash_sb * 0.80
			sample_r += crash_sb

		# Psychedelic warble (EarthBound signature texture)
		var warble_freq = 330.0 + sin(t * 3.0) * 30.0
		var warble = sin(t * warble_freq * TAU) * 0.016 * (0.5 + 0.5 * sin(t * 1.5))
		sample_l += warble * 0.80
		sample_r += warble * 1.20  # More right for EarthBound psychedelic width

		sample_l = tanh(sample_l * 1.12) * 0.87
		sample_r = tanh(sample_r * 1.12) * 0.87
		buffer.append(Vector2(sample_l, sample_r))

	return _apply_reverb(buffer, 0.20, 0.11)


## ============================================================
## STEAMPUNK MUSIC - Victorian clockwork adventure themes
## ============================================================

func _start_steampunk_music() -> void:
	"""Generate Victorian steampunk overworld theme - brass-like, march-like, clockwork"""
	_music_playing = true
	if _try_play_from_manifest("overworld_steampunk"):
		return
	print("[MUSIC] Playing steampunk overworld theme")
	if _play_area_wav_cached("steampunk"):
		return

	var sample_rate = 22050
	var bpm = 105.0  # March-like, dignified pace
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_steampunk_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "steampunk")


func _generate_steampunk_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate Victorian steampunk overworld theme - Bb major, brass and clockwork.
	   Features: brass-like square waves, ticking clock percussion, pipe organ undertones,
	   march rhythm. Like exploring a clockwork city full of gears and steam."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# Bb major / F mixolydian - adventurous, brass-band feel
	const NOTE_Bb1 = 58.27
	const NOTE_F2 = 87.31
	const NOTE_Bb2 = 116.54
	const NOTE_C3 = 130.81
	const NOTE_D3 = 146.83
	const NOTE_Eb3 = 155.56
	const NOTE_F3 = 174.61
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_Bb3 = 233.08
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_Eb4 = 311.13
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_Bb4 = 466.16
	const NOTE_C5 = 523.25
	const NOTE_D5 = 587.33

	# Melody - stately brass fanfare, march-like
	# 128 sixteenth notes = 8 bars of 4/4
	var melody = [
		# Bar 1 - Brass fanfare opening
		NOTE_Bb4, 0, 0, 0, NOTE_D5, 0, 0, 0, NOTE_C5, 0, NOTE_Bb4, 0, NOTE_A4, 0, 0, 0,
		# Bar 2 - March-like dotted rhythm
		NOTE_Bb4, 0, 0, NOTE_A4, 0, 0, NOTE_G4, 0, 0, 0, NOTE_F4, 0, 0, 0, 0, 0,
		# Bar 3 - Ascending brass line
		NOTE_F4, 0, NOTE_G4, 0, NOTE_A4, 0, NOTE_Bb4, 0, NOTE_C5, 0, 0, 0, NOTE_D5, 0, 0, 0,
		# Bar 4 - Resolution with trill feel
		NOTE_C5, 0, NOTE_Bb4, 0, NOTE_C5, 0, NOTE_Bb4, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		# Bar 5 - Second phrase, more adventurous
		NOTE_D5, 0, 0, 0, NOTE_C5, 0, NOTE_Bb4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, 0, 0,
		# Bar 6 - Clockwork-like mechanical repetition
		NOTE_G4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_A4, 0, NOTE_Bb4, 0, NOTE_C5, 0, NOTE_Bb4, 0, 0, 0,
		# Bar 7 - Low brass countermelody
		NOTE_D4, 0, NOTE_F4, 0, NOTE_Bb4, 0, 0, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_Eb4, 0,
		# Bar 8 - Grand cadence
		NOTE_F4, 0, 0, 0, NOTE_Bb4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	]

	# Bass - steady march bass, oom-pah style
	# 32 quarter notes = 8 bars
	var bass = [
		NOTE_Bb2, NOTE_F2, NOTE_Bb2, NOTE_F2, NOTE_Bb2, NOTE_F2, NOTE_C3, NOTE_F2,
		NOTE_Eb3, NOTE_Bb1, NOTE_Eb3, NOTE_Bb1, NOTE_F3, NOTE_C3, NOTE_F3, NOTE_C3,
		NOTE_Bb2, NOTE_F2, NOTE_Bb2, NOTE_F2, NOTE_G3, NOTE_D3, NOTE_Eb3, NOTE_Bb1,
		NOTE_F3, NOTE_C3, NOTE_Bb2, NOTE_F2, NOTE_Bb2, NOTE_Bb2, NOTE_Bb1, NOTE_Bb1,
	]

	var sixteenth_dur = beat_duration / 4.0
	var quarter_dur = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_dur) % 128
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur
		var t_in_quarter = fmod(t, quarter_dur) / quarter_dur

		var sample = 0.0

		# Melody - brass-like: square + pulse layered for rich harmonic content
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_sixteenth, 0.5)
			# Bright square for brass attack
			sample += _square_wave(t * melody_freq) * 0.12 * melody_env
			# Pulse wave for nasal brass body
			sample += _pulse_wave(t * melody_freq, 0.35) * 0.08 * melody_env
			# Octave-below for fullness (organ-like)
			sample += _triangle_wave(t * melody_freq * 0.5) * 0.04 * melody_env

		# Bass - deep, stately, oom-pah march feel
		var bass_freq = bass[quarter_idx] * 0.5
		var bass_env = pow(1.0 - t_in_quarter * 0.5, 0.8)
		sample += _square_wave(t * bass_freq) * 0.14 * bass_env
		# Pipe organ sub-bass
		sample += sin(t * bass_freq * TAU) * 0.1

		# Clock tick percussion - the signature steampunk element
		var beat_pos = fmod(t, quarter_dur)
		var beat_in_bar = int(t / quarter_dur) % 4

		# Clock tick on every beat (high metallic click)
		if beat_pos < 0.005:
			var tick_env = pow(1.0 - beat_pos / 0.005, 4.0)
			sample += sin(beat_pos * 4000 * TAU) * tick_env * 0.06
			sample += sin(beat_pos * 6000 * TAU) * tick_env * 0.03

		# Tock (lower) on offbeats
		var half_beat = fmod(t + quarter_dur * 0.5, quarter_dur)
		if half_beat < 0.005:
			var tock_env = pow(1.0 - half_beat / 0.005, 4.0)
			sample += sin(half_beat * 2000 * TAU) * tock_env * 0.04

		# March snare on 2 and 4
		if beat_in_bar in [1, 3] and beat_pos < 0.025:
			var snare_env = pow(1.0 - beat_pos / 0.025, 2.0)
			sample += randf_range(-0.1, 0.1) * snare_env
			sample += sin(beat_pos * 500 * TAU) * snare_env * 0.04

		# Bass drum on 1 and 3
		if beat_in_bar in [0, 2] and beat_pos < 0.03:
			var kick_env = pow(1.0 - beat_pos / 0.03, 2.0)
			sample += sin(beat_pos * 50 * TAU) * kick_env * 0.12

		# Subtle gear/mechanism ambience - very quiet ticking pattern
		var gear_rate = 8.0  # Ticks per second
		var gear_pos = fmod(t * gear_rate, 1.0)
		if gear_pos < 0.01:
			var gear_env = pow(1.0 - gear_pos / 0.01, 3.0)
			sample += sin(gear_pos * 3000 * TAU) * gear_env * 0.015

		# Gentle steam whistle every 4 bars (atmospheric)
		var four_bar = fmod(t, quarter_dur * 16)
		var whistle_start = quarter_dur * 15.5
		if four_bar >= whistle_start and four_bar < whistle_start + 0.15:
			var whistle_t = four_bar - whistle_start
			var whistle_env = sin(whistle_t / 0.15 * PI) * 0.03
			sample += sin(whistle_t * 1200 * TAU) * whistle_env

		# Stereo spread: main melody left, whistle/ticks slightly right
		var s = tanh(sample * 1.08) * 0.86
		buffer.append(Vector2(s * 0.92, s))

	# Medium reverb for Victorian hall feel
	return _apply_reverb(buffer, 0.32, 0.16)


func _start_urban_battle_music() -> void:
	"""Generate aggressive steampunk/urban battle theme - steam-powered urgency"""
	_music_playing = true
	if _try_play_from_manifest("battle_steampunk"):
		return
	print("[MUSIC] Playing urban battle theme")

	var sample_rate = 22050
	var bpm = 135.0  # Driving, steam-powered urgency
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_urban_battle_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _generate_urban_battle_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate aggressive steampunk battle theme - D minor, brass fanfares and clanking metal.
	   Features: driving brass riffs, pounding machinery drums, steam hiss accents,
	   metallic percussion. Steam-powered urgency, like a fight in a clockwork arena."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# D minor - dark, aggressive, with brass-like harmonics
	const NOTE_D2 = 73.42
	const NOTE_A2 = 110.0
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

	# Melody - aggressive brass riffs, fanfare-like battle calls
	# 128 sixteenth notes = 8 bars of 4/4
	var melody = [
		# Bar 1 - Battle fanfare opening
		NOTE_D4, 0, NOTE_D4, 0, NOTE_F4, 0, NOTE_A4, 0, NOTE_D5, 0, 0, 0, NOTE_C5, 0, NOTE_Bb4, 0,
		# Bar 2 - Descending brass run
		NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, 0, 0, 0, 0, NOTE_F4, 0,
		# Bar 3 - Syncopated brass stabs
		NOTE_A4, 0, 0, NOTE_A4, 0, 0, NOTE_Bb4, 0, 0, NOTE_A4, 0, 0, NOTE_G4, 0, NOTE_F4, 0,
		# Bar 4 - Clanking rhythm
		NOTE_D4, NOTE_D4, 0, NOTE_F4, NOTE_F4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_D4, 0, 0, 0,
		# Bar 5 - Rising tension
		NOTE_Bb4, 0, NOTE_A4, 0, NOTE_Bb4, 0, NOTE_C5, 0, NOTE_D5, 0, 0, 0, NOTE_C5, 0, 0, 0,
		# Bar 6 - Machine-gun brass
		NOTE_A4, NOTE_A4, NOTE_A4, 0, NOTE_G4, NOTE_G4, NOTE_G4, 0, NOTE_F4, NOTE_F4, NOTE_F4, 0, NOTE_E4, 0, 0, 0,
		# Bar 7 - Climactic phrase
		NOTE_D5, 0, NOTE_C5, 0, NOTE_Bb4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0,
		# Bar 8 - Resolving power chords
		NOTE_D4, 0, NOTE_F4, 0, NOTE_A4, 0, NOTE_D4, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	]

	# Bass - heavy, piston-like pumping
	# 32 quarter notes = 8 bars
	var bass = [
		NOTE_D2, NOTE_D2, NOTE_D2, NOTE_A2, NOTE_D2, NOTE_D2, NOTE_F3, NOTE_A2,
		NOTE_D3, NOTE_D3, NOTE_G3, NOTE_G3, NOTE_A3, NOTE_A3, NOTE_A2, NOTE_A2,
		NOTE_Bb3, NOTE_Bb3, NOTE_A3, NOTE_A3, NOTE_G3, NOTE_G3, NOTE_F3, NOTE_F3,
		NOTE_D2, NOTE_A2, NOTE_D3, NOTE_A2, NOTE_D2, NOTE_D2, NOTE_D2, NOTE_D2,
	]

	var sixteenth_dur = beat_duration / 4.0
	var quarter_dur = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_dur) % 128
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur
		var t_in_quarter = fmod(t, quarter_dur) / quarter_dur

		var sample = 0.0

		# Melody - layered square waves for aggressive brass tone
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_sixteenth, 0.3)
			# Primary brass voice: bright square
			sample += _square_wave(t * melody_freq) * 0.14 * melody_env
			# Secondary: pulse for nasal brass edge
			sample += _pulse_wave(t * melody_freq, 0.3) * 0.08 * melody_env
			# Octave doubling for power
			sample += _square_wave(t * melody_freq * 0.5) * 0.05 * melody_env

		# Bass - heavy, grinding, piston-like
		var bass_freq = bass[quarter_idx] * 0.5
		var bass_env = pow(1.0 - t_in_quarter * 0.4, 0.8)
		sample += _square_wave(t * bass_freq) * 0.16 * bass_env
		# Deep sub for rumble
		sample += sin(t * bass_freq * 0.5 * TAU) * 0.12

		# Percussion - heavy machinery battle drums
		var beat_pos = fmod(t, quarter_dur)
		var beat_in_bar = int(t / quarter_dur) % 4

		# Pounding kick on every beat (relentless piston)
		if beat_pos < 0.05:
			var kick_env = pow(1.0 - beat_pos / 0.05, 2.5)
			sample += sin(beat_pos * 55 * TAU) * kick_env * 0.25
			sample += sin(beat_pos * 28 * TAU) * kick_env * 0.15  # Sub thump

		# Metal clang snare on 2 and 4
		if beat_in_bar in [1, 3] and beat_pos < 0.04:
			var snare_env = pow(1.0 - beat_pos / 0.04, 1.8)
			sample += randf_range(-0.25, 0.25) * snare_env
			sample += sin(beat_pos * 900 * TAU) * snare_env * 0.1  # Metallic ring
			sample += sin(beat_pos * 1300 * TAU) * snare_env * 0.05

		# Clanking 16th-note hi-hats (gear teeth)
		var sixteenth_pos = fmod(t, sixteenth_dur)
		if sixteenth_pos < 0.012:
			var clank_env = pow(1.0 - sixteenth_pos / 0.012, 3.5)
			sample += randf_range(-0.06, 0.06) * clank_env
			sample += sin(sixteenth_pos * 3500 * TAU) * clank_env * 0.04

		# Steam hiss accent every 2 beats (pressure release)
		var two_beat = fmod(t, quarter_dur * 2)
		var hiss_start = quarter_dur * 1.75
		if two_beat >= hiss_start and two_beat < hiss_start + 0.06:
			var hiss_t = two_beat - hiss_start
			var hiss_env = pow(1.0 - hiss_t / 0.06, 1.2)
			sample += randf_range(-0.08, 0.08) * hiss_env

		# Tom fill on last beat of every 4th bar (hammering metal descent)
		var bar_ub = int(t / (quarter_dur * 4)) % 8
		if beat_in_bar == 3 and bar_ub % 4 == 3:
			var sub_idx_ub = int(beat_pos / sixteenth_dur) % 4  # which 16th within beat
			var tom_pitches_ub = [180.0, 140.0, 100.0, 70.0]
			if sixteenth_pos < 0.12:
				var tom_ub = _snes_tom(sixteenth_pos, tom_pitches_ub[sub_idx_ub], 0.10) * 0.60
				sample += tom_ub

		# Crash on bar 1 of loop
		var abs_bar_ub = int(t / (quarter_dur * 4)) % 16
		if abs_bar_ub == 0 and beat_in_bar == 0 and beat_pos < 0.18:
			var crash_ub = _snes_crash(beat_pos, 0.16) * 0.50
			sample += crash_ub * 0.85

		# Grinding industrial noise floor (slight stereo spread)
		sample += randf_range(-0.012, 0.012)

		var s = tanh(sample * 1.12) * 0.88
		buffer.append(Vector2(s * 0.90, s))

	return _apply_reverb(buffer, 0.28, 0.14)


func _start_industrial_music() -> void:
	"""Generate heavy industrial factory theme - D minor, rhythmic machinery"""
	_music_playing = true
	if _try_play_from_manifest("overworld_industrial"):
		return
	print("[MUSIC] Playing industrial theme")
	if _play_area_wav_cached("industrial"):
		return

	var sample_rate = 22050
	var bpm = 110.0  # Steady, relentless machine tempo
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_industrial_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "industrial")


func _generate_industrial_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate heavy industrial theme - D minor, mechanical rhythm, oppressive
	   Features: pounding bass, metallic percussion, minor key melody, machine-like repetition"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# D minor / Dm pentatonic - dark, oppressive
	const NOTE_D2 = 73.42
	const NOTE_A2 = 110.0
	const NOTE_D3 = 146.83
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

	# Melody - sparse, mechanical, repetitive (like an alarm or machine signal)
	# 128 sixteenth notes = 8 bars of 4/4
	var melody = [
		NOTE_D4, 0, 0, 0, NOTE_F4, 0, 0, 0, NOTE_D4, 0, NOTE_E4, 0, NOTE_D4, 0, 0, 0,
		NOTE_A3, 0, 0, 0, NOTE_Bb3, 0, NOTE_A3, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		NOTE_D4, 0, 0, 0, NOTE_F4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, 0, 0,
		NOTE_A3, 0, 0, 0, NOTE_C4, 0, NOTE_Bb3, 0, NOTE_A3, 0, 0, 0, 0, 0, 0, 0,
		NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, 0, 0, NOTE_E4, 0, NOTE_D4, 0, 0, 0, 0, 0,
		NOTE_Bb4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0, NOTE_E4, 0, NOTE_D4, 0, 0, 0, 0, 0,
		NOTE_D4, 0, NOTE_D4, 0, NOTE_F4, 0, NOTE_D4, 0, NOTE_A3, 0, 0, 0, NOTE_D4, 0, 0, 0,
		0, 0, 0, 0, NOTE_A3, 0, NOTE_D4, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	]

	# Bass - heavy, pounding, machine-like repetition
	# 32 quarter notes = 8 bars
	var bass = [
		NOTE_D2, NOTE_D2, NOTE_D2, NOTE_A2, NOTE_D2, NOTE_D2, NOTE_D3, NOTE_A2,
		NOTE_D2, NOTE_D2, NOTE_D2, NOTE_A2, NOTE_D2, NOTE_D2, NOTE_D3, NOTE_A2,
		NOTE_F3, NOTE_F3, NOTE_D2, NOTE_D2, NOTE_G3, NOTE_G3, NOTE_A2, NOTE_A2,
		NOTE_D2, NOTE_D2, NOTE_D2, NOTE_A2, NOTE_D2, NOTE_D2, NOTE_D2, NOTE_D2,
	]

	var sixteenth_dur = beat_duration / 4.0
	var quarter_dur = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_dur) % 128
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur
		var t_in_quarter = fmod(t, quarter_dur) / quarter_dur

		var sample = 0.0

		# Melody - harsh pulse wave for industrial/metallic tone
		var melody_freq = melody[sixteenth_idx]
		if melody_freq > 0:
			var melody_env = pow(1.0 - t_in_sixteenth, 0.35)
			# Pulse wave with narrow duty cycle for harsh, nasal sound
			sample += _pulse_wave(t * melody_freq, 0.3) * 0.15 * melody_env
			# Slight detune for gritty texture
			sample += _pulse_wave(t * melody_freq * 1.005, 0.25) * 0.07 * melody_env

		# Bass - heavy square wave, almost subsonic rumble
		var bass_freq = bass[quarter_idx] * 0.5
		var bass_env = pow(1.0 - t_in_quarter * 0.6, 0.8)
		sample += _square_wave(t * bass_freq) * 0.18 * bass_env
		# Sub bass rumble
		sample += sin(t * bass_freq * 0.5 * TAU) * 0.12

		# Machine percussion - pounding kick on every beat
		var beat_pos = fmod(t, quarter_dur)
		if beat_pos < 0.04:
			var kick_env = pow(1.0 - beat_pos / 0.04, 2.5)
			sample += sin(beat_pos * 45 * TAU) * kick_env * 0.22

		# Anvil/clang on offbeats (metallic percussion)
		var half_beat = fmod(t + quarter_dur * 0.5, quarter_dur)
		if half_beat < 0.02:
			var clang_env = pow(1.0 - half_beat / 0.02, 3.0)
			sample += sin(half_beat * 3200 * TAU) * clang_env * 0.08
			sample += sin(half_beat * 4700 * TAU) * clang_env * 0.04

		# Hissing steam noise on beat 3 of each bar
		var bar_pos = fmod(t, quarter_dur * 4)
		var beat3_start = quarter_dur * 2
		var steam_pos = bar_pos - beat3_start
		if steam_pos > 0 and steam_pos < 0.08:
			var steam_env = pow(1.0 - steam_pos / 0.08, 1.5)
			sample += randf_range(-0.06, 0.06) * steam_env

		# Subtle grinding noise floor (factory ambience)
		sample += randf_range(-0.015, 0.015)

		var s = tanh(sample * 1.05) * 0.84
		buffer.append(Vector2(s, s * 0.95))

	# Large reverb for big factory space
	return _apply_reverb(buffer, 0.40, 0.18)


func _start_futuristic_music() -> void:
	"""Generate cold digital ambient theme - B minor/diminished, synth pads, arpeggiated sequences"""
	_music_playing = true
	if _try_play_from_manifest("overworld_digital"):
		return
	print("[MUSIC] Playing futuristic digital theme")
	if _play_area_wav_cached("futuristic"):
		return

	var sample_rate = 22050
	var bpm = 85.0  # Measured, clinical tempo
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_futuristic_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "futuristic")


func _generate_futuristic_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate cold digital ambient theme - B minor/diminished, clinical
	   Features: detuned synth pads, arpeggiated sequences, cold tonality, digital artifacts"""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# B minor / B diminished - cold, clinical, digital
	const NOTE_B1 = 61.74
	const NOTE_Fs2 = 92.50
	const NOTE_B2 = 123.47
	const NOTE_D3 = 146.83
	const NOTE_E3 = 164.81
	const NOTE_Fs3 = 185.0
	const NOTE_A3 = 220.0
	const NOTE_B3 = 246.94
	const NOTE_Cs4 = 277.18
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_Fs4 = 369.99
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88
	const NOTE_Cs5 = 554.37
	const NOTE_D5 = 587.33

	# Arpeggio pattern - cold, precise, sequencer-like
	# 64 sixteenth notes = 4 bars, repeated twice = 8 bars
	var arpeggio = [
		NOTE_B3, NOTE_D4, NOTE_Fs4, NOTE_B4, NOTE_Fs4, NOTE_D4, NOTE_B3, 0,
		NOTE_E4, NOTE_A4, NOTE_Cs5, NOTE_A4, NOTE_E4, 0, NOTE_D4, 0,
		NOTE_B3, NOTE_D4, NOTE_Fs4, NOTE_B4, NOTE_D5, NOTE_B4, NOTE_Fs4, 0,
		NOTE_Cs4, NOTE_E4, NOTE_A4, NOTE_E4, NOTE_Cs4, 0, NOTE_B3, 0,
		NOTE_B3, NOTE_Fs4, NOTE_D4, NOTE_B4, NOTE_Fs4, NOTE_D4, NOTE_B3, 0,
		NOTE_E4, NOTE_Cs5, NOTE_A4, NOTE_E4, 0, NOTE_D4, NOTE_E4, 0,
		NOTE_Fs4, NOTE_B4, NOTE_D5, NOTE_B4, NOTE_Fs4, NOTE_D4, NOTE_B3, 0,
		NOTE_A4, NOTE_E4, NOTE_Cs4, NOTE_E4, 0, 0, 0, 0,
	]

	# Pad chords - long, sustained, detuned for digital shimmer
	var pad_chords = [
		[NOTE_B2, NOTE_D3, NOTE_Fs3],      # Bm
		[NOTE_E3, NOTE_A3, NOTE_Cs4],       # A/E
		[NOTE_D3, NOTE_Fs3, NOTE_A3],       # D
		[NOTE_Fs3, NOTE_B3, NOTE_D4],       # Bm/F#
	]

	# Bass drone - sub-bass pulse
	var bass = [
		NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1, NOTE_Fs2, NOTE_Fs2,
		NOTE_E3, NOTE_E3, NOTE_E3, NOTE_E3, NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1,
		NOTE_D3, NOTE_D3, NOTE_D3, NOTE_D3, NOTE_Fs2, NOTE_Fs2, NOTE_Fs2, NOTE_Fs2,
		NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1, NOTE_B1,
	]

	var sixteenth_dur = beat_duration / 4.0
	var quarter_dur = beat_duration
	var half_bar_dur = quarter_dur * 2

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_dur) % 64
		var quarter_idx = int(t / quarter_dur) % 32
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur
		var chord_idx = int(t / (half_bar_dur * 4)) % 4

		var sample = 0.0

		# Arpeggiated sequence (triangle wave - cold, precise)
		var arp_freq = arpeggio[sixteenth_idx]
		if arp_freq > 0:
			var arp_env = pow(1.0 - t_in_sixteenth, 0.5)
			sample += _triangle_wave(t * arp_freq) * 0.14 * arp_env
			sample += sin(t * arp_freq * 2.0 * TAU) * 0.04 * arp_env * arp_env

		# Synth pad (detuned oscillators for shimmer)
		var chord = pad_chords[chord_idx]
		for note_freq in chord:
			var detune_amount = 0.003
			var pad_freq1 = note_freq * (1.0 + detune_amount)
			var pad_freq2 = note_freq * (1.0 - detune_amount)
			sample += _triangle_wave(t * pad_freq1) * 0.04
			sample += _triangle_wave(t * pad_freq2) * 0.04
			sample += sin(t * note_freq * TAU) * 0.03

		# Sub-bass drone (sine wave)
		var bass_freq = bass[quarter_idx] * 0.5
		var bass_env = 0.8 + sin(t * 0.3) * 0.2
		sample += sin(t * bass_freq * TAU) * 0.10 * bass_env

		# Digital percussion (minimal cold clicks)
		var beat_pos = fmod(t, quarter_dur)
		if beat_pos < 0.008:
			var click_env = pow(1.0 - beat_pos / 0.008, 4.0)
			sample += sin(beat_pos * 6000 * TAU) * click_env * 0.06

		# Hi-hat style digital noise on offbeats
		var half_beat = fmod(t + quarter_dur * 0.5, quarter_dur)
		if half_beat < 0.012:
			var hat_env = pow(1.0 - half_beat / 0.012, 3.0)
			var noise_phase = sin(t * 12345.6789) * cos(t * 9876.5432)
			sample += noise_phase * hat_env * 0.04

		# Digital artifacts (occasional glitch blips every 4th bar)
		var bar_time = fmod(t, quarter_dur * 16)
		if bar_time > quarter_dur * 12 and bar_time < quarter_dur * 12 + 0.03:
			var glitch_t = bar_time - quarter_dur * 12
			var glitch_env = pow(1.0 - glitch_t / 0.03, 2.0)
			sample += sin(glitch_t * 8000 * TAU) * glitch_env * 0.05

		# Ambient hum (subtle high-frequency carrier for "digital air")
		sample += sin(t * 4000 * TAU) * 0.005 * (0.5 + sin(t * 0.7) * 0.5)

		# Slight stereo - arpeggios lean left, pads lean right
		var s = tanh(sample * 1.05) * 0.85
		buffer.append(Vector2(s * 0.95, s))

	# Spacious reverb for cold digital void
	return _apply_reverb(buffer, 0.38, 0.20)


## ============================================================================
## AUTOGRIND AMBIENT MUSIC
## ============================================================================
## Plays when autogrind is active: lo-fi, analytical, calm but with urgency.
## "System monitoring music" — the player is watching automation, not fighting.
## Style: slow ambient electronic pulse, sparse arpeggios, subtle noise floor.
## Key: D Dorian (modal — analytical but not bleak). BPM: 72 (slow, measured).

func _start_autogrind_music() -> void:
	"""Generate and play the autogrind ambient monitoring loop."""
	_music_playing = true
	if _try_play_from_manifest("autogrind"):
		return
	print("[MUSIC] Playing autogrind ambient theme")
	if _play_area_wav_cached("autogrind"):
		return

	var sample_rate = 22050
	var bpm = 72.0
	var bars = 16
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_autogrind_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "autogrind")


func _generate_autogrind_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Autogrind ambient loop — D Dorian, 72 BPM, 16 bars.
	   Layers: slow pad chord, sparse arpeggio, soft kick pulse, subtle noise floor.
	   Analytical and calm, with enough motion to feel like a system is running."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_dur = 60.0 / bpm
	var sixteenth_dur = beat_dur / 4.0
	var bar_dur = beat_dur * 4.0

	# D Dorian frequencies — analytical, not gloomy
	const NOTE_D2 = 73.42
	const NOTE_A2 = 110.0
	const NOTE_D3 = 146.83
	const NOTE_E3 = 164.81
	const NOTE_F3 = 174.61
	const NOTE_A3 = 220.0
	const NOTE_B3 = 246.94
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88

	# Sparse arpeggio — 8 bars of 32 sixteenth notes, mostly rests
	# Pattern plays notes only every 2-4 steps — analytical breathing room
	var arp_pattern = [
		NOTE_D3, 0, 0, NOTE_A3,   0, NOTE_F3, 0, 0,   NOTE_E3, 0, 0, NOTE_B3,  0, 0, NOTE_A3, 0,
		NOTE_D3, 0, NOTE_F3, 0,   NOTE_A3, 0, 0, NOTE_C4,  0, NOTE_D4, 0, 0,  NOTE_A3, 0, NOTE_E3, 0,
		NOTE_D3, 0, 0, NOTE_G4,   0, NOTE_F4, 0, 0,   NOTE_E4, 0, NOTE_B3, 0,  0, 0, NOTE_A3, 0,
		NOTE_D3, 0, NOTE_A3, 0,   0, NOTE_E4, 0, NOTE_D4,  NOTE_A3, 0, 0, NOTE_F3,  0, NOTE_E3, 0, 0,
	]
	var arp_len = arp_pattern.size()  # 64 steps = 4 bars, repeats

	# Pad chords — slow harmonic movement, 4 bars each
	var pad_chords = [
		[NOTE_D3, NOTE_F3, NOTE_A3],     # Dm
		[NOTE_A2, NOTE_E3, NOTE_A3],     # Am
		[NOTE_F3, NOTE_A3, NOTE_C4],     # F
		[NOTE_E3, NOTE_G4 * 0.5, NOTE_B3],  # Em (G dropped octave)
	]

	# Slow bass drone — quarter notes, D pedal with occasional movement
	var bass_pattern = [
		NOTE_D2, NOTE_D2, NOTE_D2, NOTE_D2,  # Bar 1
		NOTE_A2, NOTE_A2, NOTE_D2, NOTE_D2,  # Bar 2
		NOTE_D2, NOTE_F3 * 0.5, NOTE_D2, NOTE_D2,  # Bar 3
		NOTE_E3 * 0.5, NOTE_E3 * 0.5, NOTE_D2, NOTE_D2,  # Bar 4
	]

	for i in range(samples):
		var t = float(i) / rate
		var sample_l = 0.0
		var sample_r = 0.0

		# --- SLOW SYNTH PAD ---
		# Four-bar chord cycle, very slow attack (0.5 beat) for ambient float
		var chord_idx = int(t / (bar_dur * 4)) % 4
		var chord = pad_chords[chord_idx]
		var bar_t = fmod(t, bar_dur * 4)
		var pad_env = min(bar_t / (beat_dur * 2.0), 1.0)  # 2-beat fade-in per cycle
		for note_freq in chord:
			# Three detuned oscillators for shimmer
			var d = 0.0025
			var v1 = _triangle_wave(t * note_freq * (1.0 + d)) * 0.30
			var v2 = _triangle_wave(t * note_freq * (1.0 - d)) * 0.28
			var v3 = sin(t * note_freq * TAU) * 0.18
			var pad_mix = (v1 + v2 + v3) * pad_env * 0.045
			sample_l += pad_mix * 0.85
			sample_r += pad_mix * 1.0

		# --- SPARSE ARPEGGIO ---
		# Triangle wave — analytical, cold, precise
		var arp_idx = int(t / sixteenth_dur) % arp_len
		var t_in_sixteenth = fmod(t, sixteenth_dur) / sixteenth_dur
		var arp_freq = arp_pattern[arp_idx]
		if arp_freq > 0:
			var arp_env = pow(1.0 - t_in_sixteenth, 0.6)
			var arp_tone = _triangle_wave(t * arp_freq) * 0.55
			# Detuned echo voice for width
			arp_tone += _triangle_wave(t * arp_freq * 1.004) * 0.20
			var av = arp_tone * arp_env * 0.12
			# Arpeggios lean slightly left
			sample_l += av * 1.0
			sample_r += av * 0.70

		# --- BASS DRONE ---
		# Quarter-note pulse, triangle + sub sine, soft envelope
		var bass_quarter_idx = int(t / beat_dur) % bass_pattern.size()
		var t_in_quarter = fmod(t, beat_dur) / beat_dur
		var bass_freq = bass_pattern[bass_quarter_idx]
		var bass_env = _adsr(t_in_quarter * beat_dur, 0.02, 0.1, 0.65, beat_dur * 0.7, beat_dur)
		var bass_tri = _triangle_wave(t * bass_freq) * 0.55
		var bass_sub = sin(t * bass_freq * TAU) * 0.35
		var bv = (bass_tri + bass_sub) * bass_env * 0.14
		sample_l += bv
		sample_r += bv

		# --- SOFT KICK PULSE ---
		# Every full beat — just a gentle thump, not a battle drum
		var beat_pos = fmod(t, beat_dur)
		if beat_pos < 0.06:
			var kick_env = pow(1.0 - beat_pos / 0.06, 2.5)
			var kick_freq = 60.0 * pow(0.3, beat_pos * 15)
			var kick = sin(beat_pos * kick_freq * TAU) * kick_env * 0.28
			sample_l += kick
			sample_r += kick

		# --- SUBTLE HI-HAT TICK (every 2 beats) ---
		# Gives a sense of measured time passing — data center clock ticks
		var two_beat_pos = fmod(t, beat_dur * 2.0)
		if two_beat_pos < 0.008:
			var tick_env = pow(1.0 - two_beat_pos / 0.008, 4.0)
			var tick = randf_range(-0.3, 0.3) * tick_env * 0.10
			sample_l += tick * 0.6
			sample_r += tick * 1.0

		# --- AMBIENT NOISE FLOOR ---
		# Very quiet hiss — "system is running" texture
		var noise_floor = randf_range(-0.012, 0.012)
		sample_l += noise_floor
		sample_r += noise_floor

		# Soft tanh limiter
		var out_l = tanh(sample_l * 1.1) * 0.80
		var out_r = tanh(sample_r * 1.1) * 0.80
		buffer.append(Vector2(out_l, out_r))

	# Light reverb — ambient space without washing out the analytical clarity
	return _apply_reverb(buffer, 0.28, 0.12)


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


## ============================================================================
## TERRAIN-SPECIFIC BATTLE MUSIC
## ============================================================================
## Each terrain area has its own battle theme with unique instrumentation
## and mood to match the world's aesthetic.

func _start_industrial_battle_music() -> void:
	"""Generate heavy mechanical industrial battle music.
	   Clanking metal, steam hisses, driving machinery tempo."""
	_music_playing = true
	if _try_play_from_manifest("battle_industrial"):
		return
	print("[MUSIC] Playing industrial battle theme")

	var sample_rate = 22050
	var bpm = 150.0  # Driving, relentless machine tempo
	var bars = 12
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_industrial_battle_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _generate_industrial_battle_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate heavy industrial battle theme - clanking metal, driving rhythm.
	   Key: D minor (dark, oppressive). Distorted bass, metallic percussion,
	   steam hiss accents. Think factory floor during a fight."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# D minor / Phrygian scale for dark industrial feel
	const NOTE_D3 = 146.83
	const NOTE_Eb3 = 155.56
	const NOTE_F3 = 174.61
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_Bb3 = 233.08
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_Eb4 = 311.13
	const NOTE_F4 = 349.23
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_Bb4 = 466.16
	const NOTE_D5 = 587.33

	# Aggressive riff pattern - 16th notes, lots of repetition like hammering
	# Section A: Pounding riff (bars 1-4)
	var melody_a = [
		NOTE_D4, NOTE_D4, 0, NOTE_D4, NOTE_F4, 0, NOTE_D4, 0,  # Bar 1 - hammering D
		NOTE_Eb4, 0, NOTE_D4, 0, NOTE_D4, NOTE_D4, 0, 0,
		NOTE_D4, NOTE_D4, 0, NOTE_D4, NOTE_G4, 0, NOTE_F4, 0,  # Bar 2
		NOTE_Eb4, NOTE_D4, 0, 0, NOTE_D4, 0, NOTE_A3, 0,
		NOTE_D4, NOTE_D4, 0, NOTE_F4, NOTE_D4, 0, NOTE_D4, NOTE_D4,  # Bar 3
		0, NOTE_Eb4, NOTE_D4, 0, NOTE_Bb3, 0, NOTE_A3, 0,
		NOTE_D4, 0, NOTE_F4, NOTE_G4, NOTE_F4, NOTE_Eb4, NOTE_D4, 0,  # Bar 4
		NOTE_D4, NOTE_D4, NOTE_D4, 0, NOTE_A3, 0, NOTE_D4, 0,
	]

	# Section B: Rising tension, piston-like (bars 5-8)
	var melody_b = [
		NOTE_A3, 0, NOTE_A3, NOTE_D4, 0, NOTE_A3, NOTE_D4, 0,  # Bar 5 - pistons
		NOTE_F4, 0, NOTE_Eb4, 0, NOTE_D4, 0, NOTE_A3, 0,
		NOTE_Bb3, 0, NOTE_Bb3, NOTE_Eb4, 0, NOTE_Bb3, NOTE_Eb4, 0,  # Bar 6
		NOTE_F4, 0, NOTE_Eb4, 0, NOTE_D4, 0, NOTE_Bb3, 0,
		NOTE_G4, 0, NOTE_F4, 0, NOTE_Eb4, 0, NOTE_D4, 0,  # Bar 7 - descending
		NOTE_G4, NOTE_F4, NOTE_Eb4, NOTE_D4, NOTE_Eb4, NOTE_F4, NOTE_G4, 0,
		NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, NOTE_Eb4, NOTE_D4, 0,  # Bar 8
		NOTE_D4, NOTE_D4, NOTE_D4, NOTE_D4, 0, 0, 0, 0,
	]

	# Section C: Mechanical climax (bars 9-12)
	var melody_c = [
		NOTE_D5, 0, NOTE_D4, 0, NOTE_D5, 0, NOTE_D4, 0,  # Bar 9 - octave jumps
		NOTE_Bb4, 0, NOTE_A4, 0, NOTE_G4, 0, NOTE_F4, 0,
		NOTE_D5, NOTE_D5, 0, NOTE_Bb4, NOTE_A4, 0, NOTE_G4, 0,  # Bar 10
		NOTE_F4, NOTE_Eb4, NOTE_D4, 0, NOTE_D4, NOTE_F4, NOTE_A4, 0,
		NOTE_D4, NOTE_F4, NOTE_D4, NOTE_F4, NOTE_G4, NOTE_F4, NOTE_G4, NOTE_A4,  # Bar 11
		NOTE_Bb4, NOTE_A4, NOTE_G4, NOTE_F4, NOTE_Eb4, NOTE_D4, NOTE_Eb4, NOTE_F4,
		NOTE_D4, 0, NOTE_D4, 0, NOTE_F4, NOTE_D4, 0, NOTE_D4,  # Bar 12
		0, NOTE_D4, 0, NOTE_D4, NOTE_D4, NOTE_D4, NOTE_D4, 0,
	]

	var melody_pattern = melody_a + melody_b + melody_c

	# Heavy distorted bass - power chord roots
	var bass_pattern = [
		NOTE_D3, NOTE_D3, NOTE_D3, NOTE_D3,  # Bars 1-4
		NOTE_F3, NOTE_F3, NOTE_Eb3, NOTE_Eb3,
		NOTE_D3, NOTE_D3, NOTE_D3, NOTE_D3,
		NOTE_D3, NOTE_F3, NOTE_G3, NOTE_D3,
		NOTE_A3, NOTE_A3, NOTE_Bb3, NOTE_Bb3,  # Bars 5-8
		NOTE_G3, NOTE_G3, NOTE_F3, NOTE_F3,
		NOTE_D3, NOTE_D3, NOTE_Eb3, NOTE_Eb3,
		NOTE_D3, NOTE_D3, NOTE_D3, NOTE_D3,
		NOTE_D3, NOTE_D3, NOTE_F3, NOTE_F3,  # Bars 9-12
		NOTE_G3, NOTE_G3, NOTE_Bb3, NOTE_A3,
		NOTE_D3, NOTE_D3, NOTE_Eb3, NOTE_Eb3,
		NOTE_D3, NOTE_D3, NOTE_D3, NOTE_D3,
	]

	var sixteenth_duration = beat_duration / 4.0
	var quarter_duration = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_duration) % 192
		var quarter_idx = int(t / quarter_duration) % 48
		var t_in_sixteenth = fmod(t, sixteenth_duration) / sixteenth_duration
		var t_in_quarter = fmod(t, quarter_duration) / quarter_duration

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: Harsh distorted industrial lead, panned left ---
		var melody_freq = melody_pattern[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_duration
			var melody_env = _adsr(note_t, 0.002, 0.025, 0.75, sixteenth_duration * 0.85, sixteenth_duration)
			# Hard distortion: clipped square + detuned for thickness
			var raw = _square_wave(t * melody_freq) * 0.55
			raw += _square_wave(t * melody_freq * 1.010) * 0.35
			raw += _pulse_wave(t * melody_freq, 0.30) * 0.20
			var distorted = clamp(raw * 2.2, -1.0, 1.0)
			distorted *= melody_env * 0.18
			sample_l += distorted * 0.90
			sample_r += distorted * 0.70

		# --- BASS: Heavily ground bass, center-right ---
		var bass_freq = bass_pattern[quarter_idx] * 0.5
		var bass_raw = _triangle_wave(t * bass_freq) * 0.6 + _square_wave(t * bass_freq * 0.998) * 0.4
		var bass_distorted = clamp(bass_raw * 1.9, -1.0, 1.0)
		var bass_env = _adsr(t_in_quarter * quarter_duration, 0.002, 0.05, 0.82, quarter_duration * 0.88, quarter_duration)
		var bv = bass_distorted * 0.22 * bass_env
		sample_l += bv
		sample_r += bv * 1.05

		# --- DRUMS: Industrial relentless machine drums ---
		var beat_pos = fmod(t, beat_duration)
		var beat_in_bar = int(t / beat_duration) % 4

		# Heavy kick every beat (piston)
		if beat_pos < 0.10:
			var kick = _snes_kick(beat_pos, 0.095) * 0.75
			# Extra sub thump for industrial weight
			kick += sin(beat_pos * 35.0 * TAU) * pow(max(0.0, 1.0 - beat_pos * 12.0), 2) * 0.30
			sample_l += kick
			sample_r += kick

		# Metallic snare on 2 and 4 (noisy + ring)
		if beat_in_bar in [1, 3] and beat_pos < 0.11:
			var snare = _snes_snare(beat_pos, 0.105) * 0.85
			# Metal ring overlay
			var ring = sin(beat_pos * 820.0 * TAU) * pow(max(0.0, 1.0 - beat_pos * 10.0), 1.8) * 0.12
			sample_l += (snare + ring) * 0.88
			sample_r += (snare + ring) * 0.95

		# Clanking 16th-note metallic hi-hats
		var sixteenth_pos = fmod(t, sixteenth_duration)
		if sixteenth_pos < 0.022:
			var clank_env = pow(1.0 - sixteenth_pos / 0.022, 4)
			var clank = randf_range(-0.12, 0.12) * clank_env
			clank += sin(sixteenth_pos * 2500.0 * TAU) * clank_env * 0.06
			sample_l += clank * 0.75
			sample_r += clank

		# Steam hiss accent every 2 bars
		var bar_num = int(t / (beat_duration * 4)) % 12
		var bar_pos = fmod(t, beat_duration * 4)
		var hiss_start = beat_duration * 3.5
		if bar_num % 2 == 1 and bar_pos >= hiss_start and bar_pos < hiss_start + 0.12:
			var hiss_t = bar_pos - hiss_start
			var hiss_env = pow(1.0 - hiss_t / 0.12, 0.8)
			var hiss = randf_range(-0.15, 0.15) * hiss_env
			# Steam panned left (like a release valve)
			sample_l += hiss * 1.2
			sample_r += hiss * 0.5

		# Tom fill on last beat of every 4th bar (industrial hammering)
		if beat_in_bar == 3 and bar_num % 4 == 3:
			var sub_idx_ib = int(beat_pos / sixteenth_duration) % 4  # which 16th within beat
			var tom_pitches_ib = [175.0, 130.0, 95.0, 65.0]
			if sixteenth_pos < 0.14:
				var tom_ib = _snes_tom(sixteenth_pos, tom_pitches_ib[sub_idx_ib], 0.11) * 0.65
				sample_l += tom_ib * 0.85
				sample_r += tom_ib * 0.95

		# Crash on bar 1 of loop
		if bar_num == 0 and beat_in_bar == 0 and beat_pos < 0.22:
			var crash_ib = _snes_crash(beat_pos, 0.20) * 0.55
			sample_l += crash_ib * 0.80
			sample_r += crash_ib

		# Hard industrial clip
		sample_l = clamp(tanh(sample_l * 1.25) * 0.88, -0.92, 0.92)
		sample_r = clamp(tanh(sample_r * 1.25) * 0.88, -0.92, 0.92)
		buffer.append(Vector2(sample_l, sample_r))

	# Small reverb - industrial spaces have short metallic echo
	return _apply_reverb(buffer, 0.20, 0.10)


func _start_digital_battle_music() -> void:
	"""Generate electronic/glitchy digital battle music.
	   Fast arpeggios, digital distortion, Tron/Matrix vibes."""
	_music_playing = true
	if _try_play_from_manifest("battle_digital"):
		return
	print("[MUSIC] Playing digital battle theme")

	var sample_rate = 22050
	var bpm = 160.0  # Fast electronic tempo
	var bars = 12
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_digital_battle_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _generate_digital_battle_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate electronic/digital battle theme - fast arpeggios, glitchy textures.
	   Key: E minor with chromatic accents. Pulse wave arpeggios, bitcrushed bass,
	   chip-tune leads. Fighting inside a computer - Tron/Matrix vibes."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# E minor / chromatic for digital, cyber feel
	const NOTE_E3 = 164.81
	const NOTE_F3 = 174.61
	const NOTE_G3 = 196.0
	const NOTE_A3 = 220.0
	const NOTE_B3 = 246.94
	const NOTE_C4 = 261.63
	const NOTE_D4 = 293.66
	const NOTE_E4 = 329.63
	const NOTE_Fs4 = 369.99  # F#4 - digital sharpness
	const NOTE_G4 = 392.0
	const NOTE_A4 = 440.0
	const NOTE_B4 = 493.88
	const NOTE_C5 = 523.25
	const NOTE_D5 = 587.33
	const NOTE_E5 = 659.25
	const NOTE_G5 = 783.99
	const NOTE_B5 = 987.77

	# Section A: Rapid arpeggios (bars 1-4) - quintessential digital
	var melody_a = [
		NOTE_E4, NOTE_G4, NOTE_B4, NOTE_E5, NOTE_B4, NOTE_G4, NOTE_E4, NOTE_G4,  # Bar 1 - Em arp
		NOTE_B4, NOTE_E5, NOTE_G5, NOTE_E5, NOTE_B4, NOTE_G4, NOTE_E4, 0,
		NOTE_C4, NOTE_E4, NOTE_G4, NOTE_C5, NOTE_G4, NOTE_E4, NOTE_C4, NOTE_E4,  # Bar 2 - C arp
		NOTE_G4, NOTE_C5, NOTE_E5, NOTE_C5, NOTE_G4, NOTE_E4, NOTE_C4, 0,
		NOTE_D4, NOTE_Fs4, NOTE_A4, NOTE_D5, NOTE_A4, NOTE_Fs4, NOTE_D4, NOTE_Fs4,  # Bar 3 - D arp
		NOTE_A4, NOTE_D5, NOTE_Fs4, NOTE_D5, NOTE_A4, NOTE_Fs4, NOTE_D4, 0,
		NOTE_E4, NOTE_B4, NOTE_E5, NOTE_B5, NOTE_E5, NOTE_B4, NOTE_E4, 0,  # Bar 4 - Em octave sweep
		NOTE_E5, NOTE_B4, NOTE_E4, NOTE_B3, NOTE_E4, NOTE_B4, NOTE_E5, 0,
	]

	# Section B: Glitch stutter (bars 5-8) - broken signal effect
	var melody_b = [
		NOTE_E5, NOTE_E5, 0, 0, NOTE_E5, 0, NOTE_D5, 0,  # Bar 5 - stutter
		0, NOTE_E5, 0, NOTE_D5, 0, 0, NOTE_B4, 0,
		NOTE_G4, NOTE_G4, 0, 0, NOTE_A4, 0, NOTE_B4, 0,  # Bar 6
		0, NOTE_C5, 0, 0, NOTE_B4, NOTE_A4, 0, 0,
		NOTE_E4, 0, NOTE_E4, 0, NOTE_G4, 0, NOTE_G4, 0,  # Bar 7 - bit pattern
		NOTE_B4, 0, NOTE_B4, 0, NOTE_E5, 0, NOTE_E5, 0,
		NOTE_D5, 0, NOTE_C5, 0, NOTE_B4, 0, NOTE_A4, 0,  # Bar 8 - descending
		NOTE_G4, 0, NOTE_Fs4, 0, NOTE_E4, 0, 0, 0,
	]

	# Section C: Full digital assault (bars 9-12)
	var melody_c = [
		NOTE_E5, NOTE_G5, NOTE_E5, NOTE_B4, NOTE_E5, NOTE_G5, NOTE_E5, NOTE_B4,  # Bar 9
		NOTE_E5, NOTE_D5, NOTE_B4, NOTE_G4, NOTE_E4, NOTE_G4, NOTE_B4, NOTE_D5,
		NOTE_C5, NOTE_E5, NOTE_C5, NOTE_G4, NOTE_C5, NOTE_E5, NOTE_C5, NOTE_G4,  # Bar 10
		NOTE_B4, NOTE_D5, NOTE_B4, NOTE_G4, NOTE_A4, NOTE_B4, NOTE_D5, NOTE_E5,
		NOTE_E5, NOTE_B5, NOTE_E5, NOTE_B5, NOTE_G5, NOTE_E5, NOTE_G5, NOTE_B5,  # Bar 11
		NOTE_E5, NOTE_B4, NOTE_E5, NOTE_B4, NOTE_G4, NOTE_E4, NOTE_G4, NOTE_B4,
		NOTE_E5, 0, NOTE_E5, 0, NOTE_E5, NOTE_E5, NOTE_E5, NOTE_E5,  # Bar 12 - data burst
		NOTE_G5, NOTE_E5, NOTE_B4, NOTE_E5, NOTE_G5, 0, NOTE_E5, 0,
	]

	var melody_pattern = melody_a + melody_b + melody_c

	# Bass - heavy bitcrushed low synth
	var bass_pattern = [
		NOTE_E3, NOTE_E3, NOTE_C4, NOTE_C4,  # Bars 1-4
		NOTE_D4, NOTE_D4, NOTE_E3, NOTE_E3,
		NOTE_E3, NOTE_E3, NOTE_C4, NOTE_C4,
		NOTE_B3, NOTE_B3, NOTE_E3, NOTE_E3,
		NOTE_E3, NOTE_E3, NOTE_G3, NOTE_G3,  # Bars 5-8
		NOTE_A3, NOTE_A3, NOTE_B3, NOTE_B3,
		NOTE_E3, NOTE_E3, NOTE_E3, NOTE_E3,
		NOTE_G3, NOTE_A3, NOTE_B3, NOTE_E3,
		NOTE_E3, NOTE_E3, NOTE_C4, NOTE_C4,  # Bars 9-12
		NOTE_D4, NOTE_D4, NOTE_B3, NOTE_B3,
		NOTE_E3, NOTE_E3, NOTE_G3, NOTE_G3,
		NOTE_E3, NOTE_E3, NOTE_E3, NOTE_E3,
	]

	var sixteenth_duration = beat_duration / 4.0
	var quarter_duration = beat_duration

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_duration) % 192
		var quarter_idx = int(t / quarter_duration) % 48
		var t_in_sixteenth = fmod(t, sixteenth_duration) / sixteenth_duration
		var t_in_quarter = fmod(t, quarter_duration) / quarter_duration

		var sample_l = 0.0
		var sample_r = 0.0

		# --- MELODY: PWM arpeggio lead with stereo width ---
		var melody_freq = melody_pattern[sixteenth_idx]
		if melody_freq > 0:
			var note_t = t_in_sixteenth * sixteenth_duration
			var melody_env = _adsr(note_t, 0.003, 0.030, 0.65, sixteenth_duration * 0.80, sixteenth_duration)
			# Pulse wave with slowly shifting duty cycle (digital shimmer)
			var duty = 0.25 + sin(t * 2.7) * 0.10
			var mel = _pulse_wave(t * melody_freq, duty) * 0.52
			# Opposite phase detune for stereo shimmer
			mel += _pulse_wave(t * melody_freq * 1.005, 0.5 - duty) * 0.28
			mel += _triangle_wave(t * melody_freq * 2.0) * 0.12  # Octave shimmer
			mel *= melody_env * 0.20
			# Hard left/right spread for digital arpeggios
			sample_l += mel * 0.95
			sample_r += mel * 0.70

		# --- BASS: Bitcrushed digital bass ---
		var bass_freq = bass_pattern[quarter_idx] * 0.5
		var bass_raw = _square_wave(t * bass_freq) * 0.25
		# Bitcrush quantization for digital grit
		bass_raw = round(bass_raw * 8.0) / 8.0
		var bass_env = _adsr(t_in_quarter * quarter_duration, 0.002, 0.04, 0.78, quarter_duration * 0.85, quarter_duration)
		var bv = bass_raw * bass_env * 0.92
		# Sub doubling for body
		bv += sin(t * bass_freq * 0.5 * TAU) * bass_env * 0.18
		sample_l += bv
		sample_r += bv

		# --- DRUMS: Electronic SNES-style ---
		var beat_pos = fmod(t, beat_duration)
		var beat_in_bar = int(t / beat_duration) % 4

		# Punchy electronic kick (proper pitch sweep)
		if beat_pos < 0.085:
			var kick = _snes_kick(beat_pos, 0.080) * 0.65
			sample_l += kick
			sample_r += kick

		# Electronic clap/snare on 2 and 4
		if beat_in_bar in [1, 3] and beat_pos < 0.070:
			var snare = _snes_snare(beat_pos, 0.065) * 0.65
			# Add electronic ping for digital flavor
			var ping = sin(beat_pos * 1200.0 * TAU) * pow(max(0.0, 1.0 - beat_pos * 18.0), 2.0) * 0.08
			sample_l += (snare + ping) * 0.80
			sample_r += (snare + ping) * 1.0

		# Fast 16th hi-hats
		var sixteenth_pos = fmod(t, sixteenth_duration)
		if sixteenth_pos < 0.015:
			var hat = _snes_hihat(sixteenth_pos, 0.012, false) * 0.55
			sample_l += hat * 0.65
			sample_r += hat

		# Digital glitch accents at section transitions
		var bar_num = int(t / (beat_duration * 4)) % 12
		if bar_num in [3, 7, 11]:
			var bar_pos = fmod(t, beat_duration * 4)
			var glitch_beat = beat_duration * 3.0
			if bar_pos >= glitch_beat and bar_pos < glitch_beat + beat_duration:
				var glitch_t = bar_pos - glitch_beat
				var glitch_freq = 800.0 + sin(glitch_t * 50.0) * 400.0
				var glitch_env = pow(1.0 - glitch_t / beat_duration, 0.5)
				var glitch = _square_wave(t * glitch_freq) * glitch_env * 0.07
				# Glitch hard panned alternating
				sample_l += glitch * (1.5 if bar_num == 3 else 0.4)
				sample_r += glitch * (0.4 if bar_num == 3 else 1.5)

		# Tom fill (digital pitch sweep) on last beat of every 4th bar
		var beat_in_bar_db = int(t / beat_duration) % 4
		if beat_in_bar_db == 3 and bar_num % 4 == 3:
			var sub_idx_db = int(beat_pos / sixteenth_duration) % 4  # which 16th within beat
			var tom_pitches_db = [200.0, 155.0, 115.0, 80.0]
			if sixteenth_pos < 0.12:
				var tom_db = _snes_tom(sixteenth_pos, tom_pitches_db[sub_idx_db], 0.09) * 0.55
				sample_l += tom_db * 0.75
				sample_r += tom_db * 0.95

		# Crash on bar 1 of loop
		if bar_num == 0 and beat_in_bar_db == 0 and beat_pos < 0.20:
			var crash_db = _snes_crash(beat_pos, 0.18) * 0.50
			sample_l += crash_db * 0.75
			sample_r += crash_db

		sample_l = tanh(sample_l * 1.15) * 0.86
		sample_r = tanh(sample_r * 1.15) * 0.86
		buffer.append(Vector2(sample_l, sample_r))

	# Digital space: short reverb with metallic character
	return _apply_reverb(buffer, 0.18, 0.12)


func _start_void_battle_music() -> void:
	"""Generate minimal, unsettling void battle music.
	   Sparse hits, deep reverb, silence between notes.
	   The quietest, most uncomfortable battle music."""
	_music_playing = true
	if _try_play_from_manifest("battle_abstract"):
		return
	print("[MUSIC] Playing void battle theme")

	var sample_rate = 22050
	var bpm = 80.0  # Slow, deliberate, uncomfortable
	var bars = 16  # Longer loop for more variation in sparse arrangement
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_void_battle_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate)


func _generate_void_battle_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate minimal void battle theme - sparse, unsettling, uncomfortable.
	   Key: Atonal / chromatic clusters. Mostly silence with isolated hits,
	   dissonant intervals, deep sub-bass drones. Like fighting in a vacuum.
	   The quietest battle music - the absence of sound IS the music."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm

	# Sparse, dissonant note choices - tritones and minor 2nds
	const NOTE_E2 = 82.41   # Sub bass drone
	const NOTE_F2 = 87.31
	const NOTE_B2 = 123.47  # Tritone from F
	const NOTE_C3 = 130.81
	const NOTE_E3 = 164.81
	const NOTE_F3 = 174.61
	const NOTE_B3 = 246.94  # Tritone
	const NOTE_C4 = 261.63
	const NOTE_E4 = 329.63
	const NOTE_F4 = 349.23
	const NOTE_Gb4 = 369.99  # Minor 2nd above F
	const NOTE_B4 = 493.88
	const NOTE_C5 = 523.25
	const NOTE_E5 = 659.25
	const NOTE_F5 = 698.46

	# Melody is EXTREMELY sparse - mostly silence (0), occasional isolated notes
	# Each beat gets a 16th note slot; 0 = silence
	# 16 bars * 16 sixteenths = 256 slots
	var melody_pattern = [
		# Bar 1: silence... then a single note
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NOTE_B4, 0, 0, 0, 0, 0,
		# Bar 2: silence
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		# Bar 3: two dissonant notes far apart
		0, 0, 0, 0, NOTE_F4, 0, 0, 0, 0, 0, 0, 0, 0, NOTE_E4, 0, 0,
		# Bar 4: silence
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		# Bar 5: high isolated ping
		0, 0, 0, 0, 0, 0, 0, 0, NOTE_E5, 0, 0, 0, 0, 0, 0, 0,
		# Bar 6: chromatic cluster (unsettling)
		0, 0, 0, NOTE_F4, 0, NOTE_Gb4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		# Bar 7: silence with low thud
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NOTE_C4, 0, 0, 0,
		# Bar 8: tritone
		0, 0, 0, 0, 0, NOTE_F4, 0, 0, 0, 0, 0, NOTE_B4, 0, 0, 0, 0,
		# Bar 9: single high note, very exposed
		0, 0, 0, 0, 0, 0, NOTE_C5, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		# Bar 10: silence
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		# Bar 11: descending tritones
		0, 0, NOTE_B4, 0, 0, 0, NOTE_F4, 0, 0, 0, NOTE_B3, 0, 0, 0, NOTE_F3, 0,
		# Bar 12: silence
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		# Bar 13: sudden cluster
		0, 0, 0, 0, 0, 0, 0, 0, 0, NOTE_E4, NOTE_F4, 0, 0, 0, 0, 0,
		# Bar 14: isolated high
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NOTE_F5, 0, 0, 0,
		# Bar 15: building tension
		0, 0, 0, NOTE_E4, 0, 0, 0, NOTE_F4, 0, 0, 0, NOTE_B4, 0, 0, NOTE_C5, 0,
		# Bar 16: fade to nothing
		NOTE_E5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	]

	# Sub-bass drone pattern (per bar, very quiet background)
	# Some bars have drone, some don't - the absence is part of the composition
	var drone_bars = [
		NOTE_E2,  # Bar 1
		0,        # Bar 2 - no drone (pure silence)
		NOTE_F2,  # Bar 3
		0,        # Bar 4
		NOTE_E2,  # Bar 5
		NOTE_F2,  # Bar 6
		0,        # Bar 7
		NOTE_B2,  # Bar 8 - tritone bass
		0,        # Bar 9
		0,        # Bar 10 - extended silence
		NOTE_E2,  # Bar 11
		0,        # Bar 12
		NOTE_F2,  # Bar 13
		0,        # Bar 14
		NOTE_E2,  # Bar 15
		0,        # Bar 16 - ends in void
	]

	var sixteenth_duration = beat_duration / 4.0
	var bar_duration = beat_duration * 4.0

	for i in range(samples):
		var t = float(i) / rate
		var sixteenth_idx = int(t / sixteenth_duration) % 256  # 16 bars * 16
		var bar_idx = int(t / bar_duration) % 16
		var t_in_sixteenth = fmod(t, sixteenth_duration) / sixteenth_duration

		var sample = 0.0

		# Melody notes - sine wave with long reverb tail (exposed, pure)
		var melody_freq = melody_pattern[sixteenth_idx]
		if melody_freq > 0:
			# Sharp attack, very long natural decay (like striking glass in silence)
			var note_time = fmod(t, sixteenth_duration)
			var attack = min(note_time * 200.0, 1.0)  # Instant attack
			var decay = pow(0.3, note_time * 2.0)  # Long resonant decay
			var env = attack * decay
			# Pure sine with slight detuned 2nd for ghostly quality
			var tone = sin(t * melody_freq * TAU) * 0.7
			tone += sin(t * melody_freq * 1.002 * TAU) * 0.3  # Slight beating
			sample += tone * env * 0.18

		# Sub-bass drone (barely audible, felt more than heard)
		var drone_freq = drone_bars[bar_idx]
		if drone_freq > 0:
			# Slow amplitude modulation for unease
			var mod = 0.5 + sin(t * 0.3 * TAU) * 0.3  # Very slow wobble
			var drone = sin(t * drone_freq * TAU) * mod * 0.08
			sample += drone

		# Sparse percussion - irregular, unsettling
		var beat_pos = fmod(t, beat_duration)
		var beat_in_bar = int(t / beat_duration) % 4
		var absolute_beat = int(t / beat_duration) % 64

		# Occasional deep thud (not on every beat - random-feeling pattern)
		# Only on specific beats for rhythmic unease
		if absolute_beat in [2, 11, 19, 28, 37, 45, 53, 61]:
			if beat_pos < 0.08:
				var thud_env = pow(1.0 - beat_pos / 0.08, 3)
				# Very low frequency thud
				var thud = sin(beat_pos * 40 * TAU) * thud_env * 0.3
				sample += thud

		# Occasional metallic ping (wind chime in the void)
		if absolute_beat in [7, 23, 41, 55]:
			if beat_pos < 0.15:
				var ping_env = pow(1.0 - beat_pos / 0.15, 1.0)
				var ping = sin(beat_pos * 3200 * TAU) * ping_env * 0.04
				ping += sin(beat_pos * 4100 * TAU) * ping_env * 0.02  # Inharmonic
				sample += ping

		# Breath-like noise swell (every 8 bars)
		if bar_idx in [3, 11]:
			var bar_pos = fmod(t, bar_duration) / bar_duration
			if bar_pos > 0.5:
				var breath_vol = sin((bar_pos - 0.5) * 2.0 * PI) * 0.03
				sample += randf_range(-breath_vol, breath_vol)

		# Very subtle - do NOT hard clip, let it be quiet
		sample = clamp(sample, -0.5, 0.5)
		buffer.append(Vector2(sample, sample))

	return buffer


func _start_abstract_music() -> void:
	"""Generate minimal abstract void theme - the most sparse music in the game.
	   Long sustained tones, occasional single piano notes, vast silence between.
	   Almost like the music itself has been optimized down to nearly nothing.
	   Haunting and beautiful."""
	_music_playing = true
	if _try_play_from_manifest("overworld_abstract"):
		return
	print("[MUSIC] Playing abstract void theme")
	if _play_area_wav_cached("abstract"):
		return

	var sample_rate = 22050
	var bpm = 40.0  # Extremely slow - glacial, contemplative
	var bars = 32  # Longer loop for more variation in the silence
	var beat_duration = 60.0 / bpm
	var total_duration = beat_duration * 4 * bars

	_music_buffer = _generate_abstract_music(sample_rate, total_duration, bpm)
	_create_and_play_looping_wav(_music_buffer, sample_rate, "abstract")


func _generate_abstract_music(rate: int, duration: float, bpm: float) -> PackedVector2Array:
	"""Generate minimal abstract void music - the sound of optimized nothing.
	   Features: long sustained sine tones, single piano-like notes with vast gaps,
	   subharmonic drones, the occasional high harmonic like a glass singing bowl.
	   Most of the music is silence. The silence IS the music."""
	var buffer = PackedVector2Array()
	var samples = int(rate * duration)
	var beat_duration = 60.0 / bpm
	var bar_duration = beat_duration * 4

	# Notes chosen for their overtone purity and emotional weight
	# Mostly perfect fifths, octaves, and the occasional suspended note
	const NOTE_C2 = 65.41    # Deep foundation
	const NOTE_G2 = 98.00    # Perfect fifth
	const NOTE_C3 = 130.81   # Octave
	const NOTE_G3 = 196.0    # Perfect fifth
	const NOTE_C4 = 261.63   # Middle C - the "piano" note
	const NOTE_E4 = 329.63   # Sweetness
	const NOTE_G4 = 392.0    # Clarity
	const NOTE_C5 = 523.25   # High octave
	const NOTE_E5 = 659.25   # High sweetness

	# Sparse piano melody - most beats are silence (0)
	# Only ~12 notes across 32 bars. Each one precious.
	var piano_events: Array = [
		# [bar, beat_in_bar, note_freq, velocity(0-1)]
		[1, 0.0, NOTE_C4, 0.35],      # First note after long silence
		[3, 2.5, NOTE_E4, 0.25],      # Gentle answer
		[6, 1.0, NOTE_G4, 0.30],      # Rising
		[8, 0.0, NOTE_C5, 0.20],      # Peak - barely there
		[10, 3.0, NOTE_E4, 0.28],     # Falling back
		[13, 1.5, NOTE_C4, 0.32],     # Return
		[16, 0.0, NOTE_G3, 0.22],     # Deeper
		[19, 2.0, NOTE_E5, 0.15],     # Highest - like a star
		[22, 1.0, NOTE_C4, 0.30],     # Home again
		[25, 3.5, NOTE_E4, 0.20],     # Low warmth
		[28, 0.0, NOTE_G4, 0.25],     # Gentle rise
		[30, 2.0, NOTE_C4, 0.18],     # Final whisper before loop
	]

	# Drone events - long sustained tones that swell and fade
	# [start_bar, end_bar, frequency, max_volume]
	var drone_events: Array = [
		[0, 8, NOTE_C2, 0.12],        # Opening drone
		[4, 14, NOTE_G2, 0.08],       # Fifth enters
		[12, 22, NOTE_C3, 0.10],      # Octave up
		[18, 28, NOTE_G2, 0.07],      # Fifth returns
		[24, 32, NOTE_C2, 0.11],      # Closing drone
	]

	# Harmonic events - glass singing bowl tones, very high, very quiet
	# [bar, beat, frequency, duration_beats]
	var harmonic_events: Array = [
		[2, 0.0, NOTE_C5 * 2.0, 4.0],   # 2 octaves above middle C
		[9, 2.0, NOTE_G4 * 2.0, 3.0],
		[17, 1.0, NOTE_E5 * 2.0, 5.0],
		[26, 3.0, NOTE_C5 * 2.0, 4.0],
	]

	for i in range(samples):
		var t = float(i) / rate
		var bar_float = t / bar_duration
		var bar_idx = int(bar_float) % 32
		var beat_in_bar = fmod(t, bar_duration) / beat_duration

		var sample = 0.0

		# === Drone layer - long, sustained, pure sine tones ===
		# These are the breath of the void. Slow swells.
		for drone in drone_events:
			var d_start: float = float(drone[0])
			var d_end: float = float(drone[1])
			var d_freq: float = float(drone[2])
			var d_vol: float = float(drone[3])

			if bar_float >= d_start and bar_float < d_end:
				var drone_progress = (bar_float - d_start) / (d_end - d_start)
				# Slow swell: fade in over first quarter, sustain, fade out over last quarter
				var drone_env: float
				if drone_progress < 0.25:
					drone_env = drone_progress / 0.25
				elif drone_progress > 0.75:
					drone_env = (1.0 - drone_progress) / 0.25
				else:
					drone_env = 1.0
				drone_env = drone_env * drone_env  # Smooth curve

				# Pure sine with very slight vibrato (like a bowed string)
				var vibrato = sin(t * 0.3) * 0.002
				var drone_wave = sin(t * d_freq * (1.0 + vibrato) * TAU)
				# Add a very quiet octave harmonic
				drone_wave += sin(t * d_freq * 2.0 * TAU) * 0.15
				sample += drone_wave * d_vol * drone_env

		# === Piano layer - single notes with natural decay ===
		for event in piano_events:
			var e_bar: float = float(event[0])
			var e_beat: float = float(event[1])
			var e_freq: float = float(event[2])
			var e_vel: float = float(event[3])

			var note_time = e_bar * bar_duration + e_beat * beat_duration
			var time_since_note = t - note_time

			# Piano notes ring for about 4 seconds with natural decay
			if time_since_note >= 0 and time_since_note < 4.0:
				# Piano envelope: sharp attack, exponential decay
				var attack = min(time_since_note * 80.0, 1.0)
				var decay = pow(0.35, time_since_note)  # Slower decay = longer ring
				var env = attack * decay

				# Piano timbre: fundamental + harmonics with different decay rates
				var piano = sin(t * e_freq * TAU) * 1.0
				piano += sin(t * e_freq * 2.0 * TAU) * 0.5 * pow(0.5, time_since_note)
				piano += sin(t * e_freq * 3.0 * TAU) * 0.25 * pow(0.7, time_since_note)
				piano += sin(t * e_freq * 4.0 * TAU) * 0.12 * pow(0.9, time_since_note)
				# Slight detuning for warmth
				piano += sin(t * e_freq * 1.002 * TAU) * 0.3 * decay

				sample += piano * e_vel * env

		# === Harmonic layer - glass singing bowls ===
		for harm in harmonic_events:
			var h_bar: float = float(harm[0])
			var h_beat: float = float(harm[1])
			var h_freq: float = float(harm[2])
			var h_dur_beats: float = float(harm[3])

			var harm_time = h_bar * bar_duration + h_beat * beat_duration
			var harm_duration = h_dur_beats * beat_duration
			var time_since_harm = t - harm_time

			if time_since_harm >= 0 and time_since_harm < harm_duration:
				var h_progress = time_since_harm / harm_duration
				# Very gentle swell and fade
				var h_env = sin(h_progress * PI)
				h_env = h_env * h_env  # Smoother
				# Pure high sine - like striking a crystal
				var harm_wave = sin(t * h_freq * TAU)
				harm_wave += sin(t * h_freq * 1.5 * TAU) * 0.3  # Inharmonic partial
				sample += harm_wave * 0.025 * h_env

		# === Silence texture - the faintest possible noise floor ===
		# Even in silence, the void has a sound - like blood in your ears
		sample += randf_range(-0.003, 0.003)

		# === Very occasional sub-bass pulse - felt more than heard ===
		# Like a heartbeat in the void, very rare
		var absolute_beat = int(t / beat_duration)
		if absolute_beat in [0, 32, 64, 96]:
			var beat_pos = fmod(t, beat_duration * 8) / (beat_duration * 8)
			if beat_pos < 0.02:
				var pulse = sin(beat_pos * 30 * TAU) * pow(1.0 - beat_pos / 0.02, 3)
				sample += pulse * 0.08

		# Gentle limiting - this music should be QUIET
		sample = clamp(sample, -0.6, 0.6)
		buffer.append(Vector2(sample, sample))

	return buffer
