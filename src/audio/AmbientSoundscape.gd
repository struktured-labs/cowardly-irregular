class_name AmbientSoundscape
extends Node

## A place's living soundscape: one unpitched bed plus scheduled one-shots drawn from a data recipe.
## Owned by SoundManager. Never plays back identically, because every interval, level, pan and pitch is rolled.

const RECIPES_PATH := "res://data/ambient_recipes.json"
const VOICE_COUNT := 4
const VOICE_BUS_PREFIX := "AmbientEvent"
## While dialogue holds the duck, an event that comes due is pushed back by this much instead of playing.
const DIALOGUE_HOLD_S := 3.0

static var _recipes: Dictionary = {}
static var _recipes_loaded: bool = false

var _rng := RandomNumberGenerator.new()
var _place: String = ""
var _band: String = ""
var _layer: Dictionary = {}
## The weather bed nightfall took the layer from, handed back at dawn; "" when night displaced our own bed.
var _displaced: String = ""
var _due_in: Array = []
var _voices: Array = []
var _next_voice: int = 0
## Each fired event as {key, volume_db, pan, pitch}; tests read this, nothing in play does.
var fired: Array = []
## Tests turn this off to drive the schedule without creating buses or voices.
var audible: bool = true


static func load_recipes() -> Dictionary:
	if _recipes_loaded:
		return _recipes
	_recipes_loaded = true
	_recipes = {}
	var f := FileAccess.open(RECIPES_PATH, FileAccess.READ)
	if f == null:
		push_warning("[SOUNDSCAPE] %s could not be opened — no place has a soundscape" % RECIPES_PATH)
		return _recipes
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not (parsed.get("places", null) is Dictionary):
		push_warning("[SOUNDSCAPE] %s has no `places` table — no place has a soundscape" % RECIPES_PATH)
		return _recipes
	_recipes = parsed["places"]
	return _recipes


static func has_place(place_id: String) -> bool:
	return load_recipes().has(place_id)


## dawn sounds like the day starting and dusk like the night coming, unless a recipe names the band itself.
static func phase_for_band(band: String) -> String:
	return "night" if band == "dusk" or band == "night" else "day"


static func layer_for(recipe: Dictionary, band: String) -> Dictionary:
	var phases: Dictionary = recipe.get("phases", {})
	if phases.has(band):
		return phases[band]
	return phases.get(phase_for_band(band), {})


func seed_rng(value: int) -> void:
	_rng.seed = value


func place() -> String:
	return _place


func band() -> String:
	return _band


func bed_key() -> String:
	return str(_layer.get("bed", ""))


func start(place_id: String, band_name: String) -> bool:
	var recipes := load_recipes()
	if not recipes.has(place_id):
		return false
	_place = place_id
	_apply_band(band_name, true)
	return true


func stop() -> void:
	_place = ""
	_band = ""
	_layer = {}
	_displaced = ""
	_due_in = []
	for v in _voices:
		(v as AudioStreamPlayer).stop()


## Day turning to night swaps the layer; the bed restarts only when the new layer names a different one.
func set_band(band_name: String) -> void:
	if _place == "" or band_name == _band:
		return
	_apply_band(band_name, false)


func _apply_band(band_name: String, starting: bool) -> void:
	var old_bed := bed_key()
	_band = band_name
	_layer = layer_for(load_recipes()[_place], band_name)
	_due_in = []
	for ev in _events():
		## Staggered across the whole first interval, so a fresh entry does not fire everything at once.
		_due_in.append(_rng.randf_range(0.0, _range_of(ev, "every", [10.0, 20.0])[1]))
	if starting:
		restore_bed()
		return
	var now := _ambient_key_now()
	if now == old_bed or now == "":
		## Our bed held the layer. Dawn hands back the weather that nightfall displaced, else plays the new bed.
		if phase_for_band(band_name) == "day" and _displaced != "":
			_play_bed(_displaced)
			_displaced = ""
		elif bed_key() != old_bed or now == "":
			_play_bed(bed_key())
	elif phase_for_band(band_name) == "night":
		## Weather holds the layer: night outranks it, as SoundManager.set_night_ambience did before, and remembers it for dawn.
		_displaced = now
		_play_bed(bed_key())


func _play_bed(key: String) -> void:
	var sm = get_parent()
	if sm == null:
		return
	if key != "" and sm.has_method("play_ambient"):
		sm.play_ambient(key)
	elif sm.has_method("stop_ambient"):
		sm.stop_ambient()


func _ambient_key_now() -> String:
	var sm = get_parent()
	return str(sm._current_ambient_key) if sm != null and "_current_ambient_key" in sm else ""


## Re-asserts this place's bed, e.g. after weather handed the ambient player back; nothing is displaced any more.
func restore_bed() -> void:
	_displaced = ""
	_play_bed(bed_key())


func _events() -> Array:
	return _layer.get("events", [])


func _process(delta: float) -> void:
	advance(delta)


## Time moves the schedule; separated from _process so a test can drive it without frames.
func advance(delta: float) -> void:
	if _place == "":
		return
	var events := _events()
	for i in events.size():
		_due_in[i] -= delta
		if _due_in[i] > 0.0:
			continue
		if _dialogue_holds():
			_due_in[i] = DIALOGUE_HOLD_S
			continue
		_fire(events[i])
		var every: Array = _range_of(events[i], "every", [10.0, 20.0])
		_due_in[i] = _rng.randf_range(every[0], every[1])


func _dialogue_holds() -> bool:
	var sm = get_parent()
	return sm != null and sm.has_method("is_music_ducked_for_dialogue") and sm.is_music_ducked_for_dialogue()


func _fire(ev: Dictionary) -> void:
	var keys: Array = ev.get("keys", [])
	if keys.is_empty():
		return
	var key: String = str(keys[_rng.randi_range(0, keys.size() - 1)])
	var vol: Array = _range_of(ev, "vol_db", [-12.0, -6.0])
	var pan: Array = _range_of(ev, "pan", [-0.6, 0.6])
	var pitch: Array = _range_of(ev, "pitch", [0.96, 1.04])
	var shot := {
		"key": key,
		"volume_db": _rng.randf_range(vol[0], vol[1]),
		"pan": _rng.randf_range(pan[0], pan[1]),
		"pitch": _rng.randf_range(pitch[0], pitch[1]),
	}
	fired.append(shot)
	if audible:
		_play(shot)


func _range_of(ev: Dictionary, field: String, fallback: Array) -> Array:
	var r: Variant = ev.get(field, fallback)
	if r is Array and (r as Array).size() == 2:
		return [float(r[0]), float(r[1])]
	return fallback


func _play(shot: Dictionary) -> void:
	var stream := _stream_for(str(shot["key"]))
	if stream == null:
		push_warning("[SOUNDSCAPE] '%s' (%s) resolved no stream — that event stays silent" % [shot["key"], _place])
		return
	_ensure_voices()
	var i := _next_voice
	_next_voice = (_next_voice + 1) % VOICE_COUNT
	var player: AudioStreamPlayer = _voices[i]
	var bus_idx := AudioServer.get_bus_index(player.bus)
	if bus_idx != -1 and AudioServer.get_bus_effect_count(bus_idx) > 0:
		(AudioServer.get_bus_effect(bus_idx, 0) as AudioEffectPanner).pan = float(shot["pan"])
	player.stream = stream
	player.set_meta("offset_db", float(shot["volume_db"]))
	player.volume_db = base_db() + float(shot["volume_db"])
	player.pitch_scale = float(shot["pitch"])
	player.play()


## The music slider re-applies each voice's rolled offset, so a sound already playing follows it like the bed does.
func refresh_levels() -> void:
	for v in _voices:
		var p: AudioStreamPlayer = v
		p.volume_db = base_db() + float(p.get_meta("offset_db", 0.0))


func voices() -> Array:
	return _voices


## Events sit relative to the bed, which tracks the music slider; read at play time so the slider is live.
func base_db() -> float:
	var sm = get_parent()
	if sm == null or not ("_music_base_db" in sm):
		return -28.0
	return float(sm._music_base_db) + float(sm.AMBIENT_OFFSET_DB)


func _stream_for(key: String) -> AudioStream:
	var sm = get_parent()
	if sm == null or not ("_sfx_manifest" in sm):
		return null
	if sm.has_method("_load_sfx_manifest"):
		sm._load_sfx_manifest()
	var entry: Dictionary = sm._sfx_manifest.get(key, {})
	var path: String = str(entry.get("file", ""))
	if path == "":
		return null
	if not path.begins_with("res://"):
		path = "res://" + path
	return load(path) as AudioStream


func ensure_voices() -> void:
	_ensure_voices()


func _ensure_voices() -> void:
	if not _voices.is_empty():
		return
	var send := "MusicDuck" if AudioServer.get_bus_index("MusicDuck") != -1 else "Master"
	for i in VOICE_COUNT:
		var bus_name := "%s%d" % [VOICE_BUS_PREFIX, i]
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, send)
			AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
		var p := AudioStreamPlayer.new()
		p.name = "AmbientEventVoice%d" % i
		p.bus = bus_name
		add_child(p)
		_voices.append(p)
