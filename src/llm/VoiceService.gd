extends Node

## Live voice: picks the speech backend, owns voice_cast.json and the cache; every failure returns null, nothing blocks.

const CAST_PATH := "res://data/voice_cast.json"

var is_web: bool = OS.has_feature("web")
## Tests only: apply_config installs this in place of an HTTP backend when live voice is on.
var test_backend: TTSBackend = null
var cache: VoiceCache
var _backend: TTSBackend
var _cast: Dictionary = {}
var _pending: Dictionary = {}
var _next_id: int = 0
var _last_latency_ms: int = -1
var _last_error: String = ""
var _clipping_detected: bool = false


func _ready() -> void:
	cache = VoiceCache.new()
	_cast = load_cast(CAST_PATH)
	apply_config()


## Re-reads GameState.tts_* and swaps the backend; the settings panel calls this on Save and Test.
func apply_config() -> void:
	install_backend(_make_backend())


func install_backend(b: TTSBackend) -> void:
	if b == _backend:
		return
	if _backend != null and is_instance_valid(_backend):
		_backend.cancel_all()
		if _backend.synthesis_finished.is_connected(_on_finished):
			_backend.synthesis_finished.disconnect(_on_finished)
		_backend.queue_free()
	_backend = b
	_backend.synthesis_finished.connect(_on_finished)
	add_child(_backend)
	_clipping_detected = false
	_last_error = ""


func _make_backend() -> TTSBackend:
	var gs := get_node_or_null("/root/GameState")
	var on: bool = gs != null and "tts_live_enabled" in gs and bool(gs.tts_live_enabled)
	if is_web or not on:
		return NullTTSBackend.new()
	if test_backend != null:
		return test_backend
	var http := HTTPTTSBackend.new()
	http.base_url = str(gs.tts_server_url)
	http.model = str(gs.tts_model)
	return http


static func load_cast(path: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not ((d as Dictionary).get("voices") is Dictionary):
		push_warning("[VoiceService] %s has no \"voices\" object; nobody is cast" % path)
		return out
	var voices: Dictionary = d["voices"]
	for speaker in voices:
		var v: Variant = voices[speaker]
		if v is Dictionary and str((v as Dictionary).get("voice", "")) != "":
			out[str(speaker)] = {"voice": str(v["voice"]), "rev": int(v.get("rev", 0))}
	return out


func voice_for(speaker_id: String) -> Dictionary:
	return (_cast.get(speaker_id, {}) as Dictionary).duplicate()


func cast_speakers() -> Array[String]:
	var out: Array[String] = []
	for k in _cast.keys():
		out.append(str(k))
	out.sort()
	return out


func is_live_ready() -> bool:
	return _backend != null and _backend.is_ready()


## Synchronous: a battle bubble must have its audio before it builds its fade tween.
func get_cached(speaker_id: String, text: String) -> AudioStream:
	var v := voice_for(speaker_id)
	if v.is_empty() or cache == null:
		return null
	var key := VoiceCache.key_for(str(v["voice"]), int(v["rev"]), text)
	var bytes: PackedByteArray = cache.read(key)
	if bytes.is_empty():
		return null
	var s := VoiceAudio.decode(bytes)
	# A wedged mix refuses the lock and returns null. That blob is still whole, so the key stays.
	if s == null and (not VoiceAudio.is_complete_wav(bytes) or SoundManager == null or not SoundManager.mixer_is_wedged()):
		cache.remove(key)
	return s


func synthesize(speaker_id: String, text: String, timeout_sec: float) -> AudioStream:
	var hit := get_cached(speaker_id, text)
	if hit != null:
		return hit
	var v := voice_for(speaker_id)
	if v.is_empty() or text.strip_edges() == "" or not is_live_ready():
		return null
	_next_id += 1
	var id := "tts_%d" % _next_id
	var box := {"done": false, "ok": false, "wav": PackedByteArray(), "error": ""}
	_pending[id] = box
	var backend := _backend
	var t0 := Time.get_ticks_msec()
	backend.synthesize(id, text, str(v["voice"]))
	while not box["done"] and Time.get_ticks_msec() - t0 < int(timeout_sec * 1000.0):
		await get_tree().process_frame
	_pending.erase(id)
	if not box["done"]:
		if is_instance_valid(backend):
			backend.cancel(id)
		_last_error = "timed out after %.1fs" % timeout_sec
		return null
	if not box["ok"]:
		_last_error = str(box["error"])
		return null
	var stream := VoiceAudio.decode(box["wav"])
	if stream == null:
		if SoundManager != null and SoundManager.mixer_is_wedged():
			_last_error = "headless mixer wedged — voice WAV was not decoded"
		else:
			_last_error = "the server's reply was not a whole WAV"
		return null
	_last_latency_ms = Time.get_ticks_msec() - t0
	_last_error = ""
	if VoiceAudio.is_clipped(stream):
		_clipping_detected = true
	if cache != null:
		cache.write(VoiceCache.key_for(str(v["voice"]), int(v["rev"]), text), box["wav"])
	return stream


func status() -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	var known: Array[String] = _backend.server_voices() if _backend != null else ([] as Array[String])
	var missing: Array[String] = []
	if not known.is_empty():
		for speaker in _cast:
			var name := str(_cast[speaker]["voice"])
			if not (name in known) and not (name in missing):
				missing.append(name)
	return {
		"enabled": not is_web and gs != null and "tts_live_enabled" in gs and bool(gs.tts_live_enabled),
		"ready": is_live_ready(),
		"backend": _backend.backend_id() if _backend != null else "none",
		"url": _backend.contacts_url() if _backend != null else "",
		"last_latency_ms": _last_latency_ms,
		"last_error": _last_error,
		"clipping_detected": _clipping_detected,
		"missing_voices": missing,
	}


func _on_finished(id: String, ok: bool, wav: PackedByteArray, error: String) -> void:
	var box: Variant = _pending.get(id)
	if box == null:
		return
	box["done"] = true
	box["ok"] = ok
	box["wav"] = wav
	box["error"] = error
