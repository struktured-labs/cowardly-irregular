# Live Voice Client (Piece 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings gets a working **Test Voice**, which speaks a line in a cast speaker's voice through a local speech server. No dialogue call site changes.

**Architecture:** A swappable `TTSBackend` (HTTP, Null, test Replay) is owned by a new `VoiceService` autoload. The service also holds `data/voice_cast.json` and a bounded on-disk `VoiceCache`. `VoiceAudio` turns WAV bytes into an `AudioStreamWAV`, refuses incomplete files, and counts clipped runs. `SoundManager.play_voice_stream` plays a stream on the existing voice player. `LiveVoicePanel` is the settings UI, modelled on `BYOKConfigPanel`.

**Tech Stack:** Godot 4.4.1, GDScript, GUT 9.4 via `tools/run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-09-24-local-tts-voice-design.md`, Piece 1 (§1.1–1.8) and Contracts 2–5.

## Global Constraints

- Every godot command sets `XDG_DATA_HOME=$PWD/tmp/xdg`. Tests run as `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh <name>`: EC `0` pass, `1` fail, `3` nothing ran (import needed or parse error), `4` a test asserted nothing.
- After adding any file with a `class_name`, run `XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import --quit` before running tests.
- `.gd` comments are one line max.
- Wire protocol (contract 2): `POST /v1/audio/speech` with exactly `{"model","input","voice","response_format":"wav"}`, which returns WAV bytes. `GET /v1/audio/voices` returns `{"status":"ok","voices":[<filename>,…]}` (verified in devnen `server.py` @ `915ae28`, lines 1382–1386).
- Contract 4: the client **never** sends exaggeration, cfg, temperature or seed.
- Defaults: `tts_live_enabled=false`, `tts_server_url="http://127.0.0.1:8004"`, `tts_model="chatterbox"`.
- Web: no backend contacts a server URL, the `tts_*` settings don't persist, and the panel refuses to open.
- Boot writes nothing to `user://`. The cache directory is created on the first write.
- Cache: `user://voice_cache/<key>.wav`, where key = first 32 hex characters of `sha256("v1|"+voice+"|"+str(rev)+"|"+text)`. Cap: 200 MB, least recently used evicted first.
- Clipping: **≥ 2 runs** of samples at the int16 rail (|s| ≥ 32767) means clipped. Detection never modifies audio.
- Lanes don't run the full suite. Run your own files plus the files that reach what you changed, then hand off to cowir-main.

## File Structure

| File | Responsibility |
|---|---|
| `src/llm/VoiceAudio.gd` (new) | WAV bytes → `AudioStreamWAV`; completeness check; clipped-run count |
| `src/llm/TTSBackend.gd` (new) | Backend contract (signal + virtuals) |
| `src/llm/NullTTSBackend.gd` (new) | Never ready, contacts nothing |
| `src/llm/HTTPTTSBackend.gd` (new) | OpenAI-compatible client, probe, voice list |
| `tools/replay_tts_backend.gd` (new) | Test-only canned-bytes backend |
| `src/llm/VoiceCache.gd` (new) | Bounded least-recently-used WAV cache on disk |
| `src/llm/VoiceService.gd` (new autoload) | Backend selection, cast, cache, `synthesize`, `status` |
| `src/audio/SoundManager.gd` | + `play_voice_stream` |
| `src/meta/GameState.gd`, `src/save/SaveSystem.gd` | + `tts_*` settings, persisted on desktop only |
| `src/ui/LiveVoicePanel.gd` (new) | Configure Live Voice panel |
| `src/ui/SettingsMenu.gd` | + "Configure Live Voice" row, desktop only |
| `test/unit/helpers/wav_fixture.gd` (new) | Builds PCM16 WAV bytes for tests |

---

### Task 1: Live voice settings, persisted on desktop only

**Files:**
- Modify: `src/meta/GameState.gd` (after `llm_custom_api_key`, ~line 96)
- Modify: `src/save/SaveSystem.gd` (inside both existing `if not OS.has_feature("web"):` BYOK blocks, ~lines 1078 and 1250)
- Test: `test/unit/test_live_voice_settings_persist_on_desktop_only.gd`

**Interfaces:**
- Produces: `GameState.tts_live_enabled: bool`, `GameState.tts_server_url: String`, `GameState.tts_model: String`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## Live voice settings round-trip through settings.json on desktop, and are skipped on web exactly like BYOK.

const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"
const SETTINGS := "user://settings.json"
const FIELDS := ["tts_live_enabled", "tts_server_url", "tts_model"]

var _prior_existed: bool = false
var _prior_text: String = ""
var _saved: Dictionary = {}


func before_each() -> void:
	_prior_existed = FileAccess.file_exists(SETTINGS)
	_prior_text = FileAccess.get_file_as_string(SETTINGS) if _prior_existed else ""
	for f in FIELDS:
		_saved[f] = GameState.get(f)


func after_each() -> void:
	for f in FIELDS:
		GameState.set(f, _saved[f])
	if _prior_existed:
		var w := FileAccess.open(SETTINGS, FileAccess.WRITE)
		w.store_string(_prior_text)
		w.close()
	elif FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)


func test_the_defaults_point_at_the_supported_local_server() -> void:
	var gs = load("res://src/meta/GameState.gd").new()
	assert_eq(gs.tts_live_enabled, false, "live voice is opt-in")
	assert_eq(gs.tts_server_url, "http://127.0.0.1:8004")
	assert_eq(gs.tts_model, "chatterbox", "chatterbox, not turbo: the engine struktured approved by ear")
	gs.free()


func test_the_settings_survive_a_save_and_load() -> void:
	GameState.tts_live_enabled = true
	GameState.tts_server_url = "http://127.0.0.1:9999"
	GameState.tts_model = "chatterbox-test"
	SaveSystem.save_settings()
	GameState.tts_live_enabled = false
	GameState.tts_server_url = "changed"
	GameState.tts_model = "changed"
	SaveSystem.load_settings()
	assert_eq(GameState.tts_live_enabled, true)
	assert_eq(GameState.tts_server_url, "http://127.0.0.1:9999")
	assert_eq(GameState.tts_model, "chatterbox-test")


func test_both_directions_sit_inside_the_web_gate() -> void:
	var src: String = FileAccess.get_file_as_string(SAVE_SYSTEM)
	for fn in ["func save_settings", "func load_settings"]:
		var at: int = src.find(fn)
		assert_gt(at, -1, "%s must exist" % fn)
		var end: int = src.find("\nfunc ", at + 1)
		var body: String = src.substr(at, (end if end != -1 else src.length()) - at)
		var gate: int = body.find("if not OS.has_feature(\"web\"):")
		assert_gt(gate, -1, "%s must gate on web" % fn)
		for f in FIELDS:
			var use: int = body.find(f)
			assert_gt(use, gate, "%s: %s must be written/read only after the web gate" % [fn, f])
```

- [ ] **Step 2: Run it and watch it fail**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh live_voice_settings_persist_on_desktop_only`
Expected: EC=1. The default arm fails with `Invalid get index 'tts_live_enabled'` or equivalent, and the gate arm fails with `-1 expected to be > …`.

- [ ] **Step 3: Implement**

In `src/meta/GameState.gd`, after the `llm_custom_api_key` line:

```gdscript
## Live voice (local TTS server): desktop only, SaveSystem skips these on web like llm_custom_*.
var tts_live_enabled: bool = false
var tts_server_url: String = "http://127.0.0.1:8004"
var tts_model: String = "chatterbox"
```

In `SaveSystem.save_settings`, inside the existing `if not OS.has_feature("web"):` block, after the `llm_custom_api_key` write:

```gdscript
			for f in ["tts_live_enabled", "tts_server_url", "tts_model"]:
				if f in GameState:
					settings[f] = GameState.get(f)
```

In `SaveSystem.load_settings`, inside the existing `if not OS.has_feature("web"):` block, after the `llm_custom_api_key` read:

```gdscript
			if settings.has("tts_live_enabled") and "tts_live_enabled" in GameState:
				GameState.tts_live_enabled = bool(settings["tts_live_enabled"])
			if settings.has("tts_server_url") and "tts_server_url" in GameState and str(settings["tts_server_url"]).strip_edges() != "":
				GameState.tts_server_url = str(settings["tts_server_url"]).strip_edges()
			if settings.has("tts_model") and "tts_model" in GameState and str(settings["tts_model"]).strip_edges() != "":
				GameState.tts_model = str(settings["tts_model"]).strip_edges()
```

- [ ] **Step 4: Run and pass.** Same command. Expected: EC=0, `Passing 3`.

- [ ] **Step 5: Mutation check (load-bearing: web gating).** Temporarily move the `tts_*` write loop in `save_settings` to just *before* its `if not OS.has_feature("web"):` line, run the test, and confirm `test_both_directions_sit_inside_the_web_gate` fails. Revert, then confirm the source matches `git diff` from Step 3.

- [ ] **Step 6: Commit**

```bash
git add src/meta/GameState.gd src/save/SaveSystem.gd test/unit/test_live_voice_settings_persist_on_desktop_only.gd
git commit -m "feat(voice): live voice settings, persisted on desktop and skipped on web"
```

---

### Task 2: `VoiceAudio`: decode only a complete WAV, and count clipped runs

**Files:**
- Create: `src/llm/VoiceAudio.gd`
- Create: `test/unit/helpers/wav_fixture.gd`
- Test: `test/unit/test_a_voice_line_decodes_only_when_whole.gd`

**Interfaces:**
- Produces: `VoiceAudio.decode(bytes: PackedByteArray) -> AudioStreamWAV` (null unless complete), `VoiceAudio.is_complete_wav(bytes) -> bool`, `VoiceAudio.pinned_runs(stream: AudioStreamWAV) -> int`, `VoiceAudio.is_clipped(stream) -> bool`, `const VoiceAudio.CLIPPED_RUNS := 2`
- Produces (test helper): `WavFixture.pcm16(samples: PackedInt32Array, rate := 24000) -> PackedByteArray`, `WavFixture.tone(seconds: float, peak: int, rate := 24000) -> PackedByteArray`

Measured before planning (Godot 4.4.1): `AudioStreamWAV.load_from_buffer` returns null on garbage or a truncated header, **but accepts audio truncated mid-data and returns a shorter stream** (1000 of 240044 bytes → 0.02 s). It also prints engine errors on bad input. Hence the completeness check runs before decoding. A clipping scan of 120k samples takes 6.5 ms.

- [ ] **Step 1: Write the fixture helper**

`test/unit/helpers/wav_fixture.gd`:

```gdscript
class_name WavFixture
extends RefCounted

## Mono 16-bit PCM WAV bytes for tests; no server or GPU needed.

static func pcm16(samples: PackedInt32Array, rate: int = 24000) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(samples[i], -32768, 32767))
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.append_array(_u32(36 + data.size()))
	out.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, 1)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * 2)
	fmt.encode_u16(16, 2)
	fmt.encode_u16(18, 16)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	out.append_array(_u32(data.size()))
	out.append_array(data)
	return out


## A sine at this peak amplitude; peak 29196 is the supported server's -1 dBFS ceiling.
static func tone(seconds: float, peak: int, rate: int = 24000) -> PackedByteArray:
	var s := PackedInt32Array()
	s.resize(int(seconds * rate))
	for i in s.size():
		s[i] = int(round(sin(i * 0.05) * peak))
	return pcm16(s, rate)


static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b
```

- [ ] **Step 2: Write the failing test**

`test/unit/test_a_voice_line_decodes_only_when_whole.gd`:

```gdscript
extends GutTest

## A server that dies mid-line returns a WAV that load_from_buffer plays SHORT; only a whole file may reach the player.

func _clip_runs(runs: int) -> PackedByteArray:
	var s := PackedInt32Array()
	s.resize(24000)
	for i in s.size():
		s[i] = int(sin(i * 0.05) * 20000)
	for r in runs:
		for k in 5:
			s[1000 + r * 3000 + k] = 32767
	return WavFixture.pcm16(s)


func test_a_whole_wav_decodes_at_its_own_rate_and_length() -> void:
	var w := VoiceAudio.decode(WavFixture.tone(0.5, 20000))
	assert_not_null(w)
	assert_eq(w.mix_rate, 24000, "24 kHz plays at 24 kHz, no resampling")
	assert_eq(w.stereo, false)
	assert_almost_eq(w.get_length(), 0.5, 0.001)


func test_a_truncated_wav_is_refused_not_played_short() -> void:
	var whole := WavFixture.tone(0.5, 20000)
	assert_null(VoiceAudio.decode(whole.slice(0, 1000)), "cut mid-data: the engine would play 0.02s of it")
	assert_null(VoiceAudio.decode(whole.slice(0, 30)), "cut mid-header")


func test_garbage_and_empty_are_refused() -> void:
	var junk := PackedByteArray()
	junk.resize(500)
	junk.fill(7)
	assert_null(VoiceAudio.decode(junk))
	assert_null(VoiceAudio.decode(PackedByteArray()))


func test_two_pinned_runs_are_clipping_and_one_is_a_peak() -> void:
	assert_eq(VoiceAudio.pinned_runs(VoiceAudio.decode(_clip_runs(2))), 2)
	assert_true(VoiceAudio.is_clipped(VoiceAudio.decode(_clip_runs(2))), "2 runs at the rail: clipped")
	assert_false(VoiceAudio.is_clipped(VoiceAudio.decode(_clip_runs(1))), "1 pinned run can be a clean peak")


func test_the_supported_servers_minus_1_dbfs_output_is_not_clipping() -> void:
	var w := VoiceAudio.decode(WavFixture.tone(1.0, 29196))
	assert_eq(VoiceAudio.pinned_runs(w), 0, "peak-normalised to -1 dBFS never reaches the rail")
```

- [ ] **Step 3: Import, run, fail.** Run the import command, then `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh a_voice_line_decodes_only_when_whole`. Expected: EC=3, `Identifier "VoiceAudio" not declared` (the class doesn't exist yet).

- [ ] **Step 4: Implement `src/llm/VoiceAudio.gd`**

```gdscript
class_name VoiceAudio
extends RefCounted

## WAV bytes from a speech server → a playable stream, plus the clipping count the status line reports.

## A sample at or past this magnitude is pinned at the int16 rail.
const RAIL := 32767
## Pinned runs that mark a line clipped; a single one can be a clean peak.
const CLIPPED_RUNS := 2


## Null unless the bytes are a whole RIFF/WAVE: the engine would play a truncated file short.
static func decode(bytes: PackedByteArray) -> AudioStreamWAV:
	if not is_complete_wav(bytes):
		return null
	return AudioStreamWAV.load_from_buffer(bytes)


static func is_complete_wav(bytes: PackedByteArray) -> bool:
	if bytes.size() < 44:
		return false
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return false
	var pos := 12
	while pos + 8 <= bytes.size():
		var size: int = bytes.decode_u32(pos + 4)
		if bytes.slice(pos, pos + 4).get_string_from_ascii() == "data":
			return size > 0 and pos + 8 + size <= bytes.size()
		pos += 8 + size + (size & 1)
	return false


## Runs of consecutive samples at the rail; 16-bit mono PCM, anything else reports 0.
static func pinned_runs(stream: AudioStreamWAV) -> int:
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS:
		return 0
	var d: PackedByteArray = stream.data
	var runs := 0
	var in_run := false
	for i in range(0, d.size() - 1, 2):
		var v: int = d.decode_s16(i)
		var pinned: bool = v >= RAIL or v <= -RAIL
		if pinned and not in_run:
			runs += 1
		in_run = pinned
	return runs


static func is_clipped(stream: AudioStreamWAV) -> bool:
	return pinned_runs(stream) >= CLIPPED_RUNS
```

- [ ] **Step 5: Import, run, pass.** Expected: EC=0, `Passing 5`.

- [ ] **Step 6: Mutation checks (load-bearing: decode, clipping).** One at a time, reverting each: (a) make `decode` skip `is_complete_wav`, and the truncation arm must fail; (b) change `CLIPPED_RUNS` to 1, and the one-run arm must fail; (c) change `RAIL` to 29000, and the −1 dBFS arm must fail. Confirm each by its failure message.

- [ ] **Step 7: Commit**

```bash
git add src/llm/VoiceAudio.gd test/unit/helpers/wav_fixture.gd test/unit/test_a_voice_line_decodes_only_when_whole.gd
git commit -m "feat(voice): VoiceAudio decodes only a whole WAV and counts clipped runs"
```

---

### Task 3: Speech backends: the contract, Null, HTTP and Replay

**Files:**
- Create: `src/llm/TTSBackend.gd`, `src/llm/NullTTSBackend.gd`, `src/llm/HTTPTTSBackend.gd`, `tools/replay_tts_backend.gd`
- Test: `test/unit/test_the_speech_client_sends_only_the_wire_contract.gd`

**Interfaces:**
- Produces: `TTSBackend` with `signal synthesis_finished(id: String, ok: bool, wav: PackedByteArray, error: String)`, `backend_id() -> String`, `is_ready() -> bool`, `contacts_url() -> String` ("" = contacts no server), `server_voices() -> Array[String]` ([] = unknown), `status() -> Dictionary`, `synthesize(id, text, voice) -> void`, `cancel(id)`, `cancel_all()`
- Produces: `HTTPTTSBackend.base_url`, `.model`, `build_body(text, voice) -> String`, `static parse_voices(body: String) -> Array[String]`
- Produces (tests): `tools/replay_tts_backend.gd` with `next_wav`, `voices`, `silent`, `fail_error`, `requests: Array`, `cancelled: Array[String]`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## The client sends exactly the wire contract: delivery (exaggeration/cfg/temperature/seed) is the server's, per voice.

const REFUSED_URL := "http://127.0.0.1:1"


func test_the_request_body_is_exactly_the_four_contract_keys() -> void:
	var b := HTTPTTSBackend.new()
	b.model = "chatterbox"
	var body: Dictionary = JSON.parse_string(b.build_body("Hello there.", "bard.wav"))
	var keys: Array = body.keys()
	keys.sort()
	assert_eq(keys, ["input", "model", "response_format", "voice"], "contract 4: no delivery parameters leave the client")
	assert_eq(body["response_format"], "wav")
	assert_eq(body["voice"], "bard.wav")
	assert_eq(body["input"], "Hello there.")
	b.free()


func test_the_voice_list_parses_the_real_servers_shape() -> void:
	## devnen server.py @ 915ae28 lines 1382-1386.
	assert_eq(HTTPTTSBackend.parse_voices('{"status": "ok", "voices": ["bard.wav", "fighter.wav"]}'),
		["bard.wav", "fighter.wav"] as Array[String])
	assert_eq(HTTPTTSBackend.parse_voices('[{"filename": "mage.wav", "display_name": "Mage"}]'),
		["mage.wav"] as Array[String], "the /get_predefined_voices shape too")
	assert_eq(HTTPTTSBackend.parse_voices("not json"), [] as Array[String])


func test_a_refused_connection_answers_once_and_not_ok() -> void:
	var b := HTTPTTSBackend.new()
	b.base_url = REFUSED_URL
	add_child_autofree(b)
	var got: Array = []
	b.synthesis_finished.connect(func(id, ok, wav, err): got.append([id, ok, wav.size(), err]))
	b.synthesize("t1", "Hello.", "bard.wav")
	var t0 := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got.size(), 1, "exactly one answer per id, or a caller waits forever")
	assert_eq(got[0][0], "t1")
	assert_false(got[0][1])
	assert_ne(got[0][3], "", "a failure says why")


func test_contacts_url_names_where_requests_go() -> void:
	var h := HTTPTTSBackend.new()
	h.base_url = "http://127.0.0.1:8004/v1/"
	assert_eq(h.contacts_url(), "http://127.0.0.1:8004", "trailing /v1 and slash are ours to add")
	h.free()
	var n := NullTTSBackend.new()
	assert_eq(n.contacts_url(), "", "the null backend contacts nothing")
	assert_false(n.is_ready())
	n.free()
```

- [ ] **Step 2: Import, run, fail.** Expected: EC=3, `HTTPTTSBackend` not declared.

- [ ] **Step 3: Implement `src/llm/TTSBackend.gd`**

```gdscript
class_name TTSBackend
extends Node

## Speech backend contract; VoiceService talks only to this, so piece 5's browser backend slots in. synthesize MUST answer each id exactly once.

signal synthesis_finished(id: String, ok: bool, wav: PackedByteArray, error: String)


func backend_id() -> String:
	return "base"


func is_ready() -> bool:
	return false


## Where requests go, or "" for a backend that contacts no server (the web gating property).
func contacts_url() -> String:
	return ""


## Voice names the server reports; [] means not known yet, never "none installed".
func server_voices() -> Array[String]:
	return []


func status() -> Dictionary:
	return {"backend": backend_id(), "ready": is_ready(), "url": contacts_url()}


func synthesize(id: String, _text: String, _voice: String) -> void:
	synthesis_finished.emit(id, false, PackedByteArray(), "synthesize() not implemented")


func cancel(_id: String) -> void:
	pass


func cancel_all() -> void:
	pass
```

- [ ] **Step 4: Implement `src/llm/NullTTSBackend.gd`**

```gdscript
class_name NullTTSBackend
extends TTSBackend

## Never ready and contacts nothing: live voice off, and web until piece 5.

func backend_id() -> String:
	return "null"


func synthesize(id: String, _text: String, _voice: String) -> void:
	synthesis_finished.emit(id, false, PackedByteArray(), "live voice is off")
```

- [ ] **Step 5: Implement `src/llm/HTTPTTSBackend.gd`**

```gdscript
class_name HTTPTTSBackend
extends TTSBackend

## OpenAI-compatible speech client: POST /v1/audio/speech returns WAV bytes; GET /v1/audio/voices is the readiness probe.

signal availability_changed(available: bool)

@export var base_url: String = "http://127.0.0.1:8004"
@export var model: String = "chatterbox"

const PROBE_TIMEOUT_SEC: float = 1.5
const PROBE_INTERVAL_SEC: float = 30.0
const REQUEST_TIMEOUT_SEC: float = 8.0

var _inflight: Dictionary = {}
var _ready_flag: bool = false
var _probe_request: HTTPRequest = null
var _last_probe_msec: int = 0
var _first_probe_done: bool = false
var _voices: Array[String] = []


func _ready() -> void:
	_start_probe()


func backend_id() -> String:
	return "http"


func is_ready() -> bool:
	_maybe_refresh_probe()
	return _ready_flag


func contacts_url() -> String:
	var b: String = base_url.strip_edges().rstrip("/")
	if b.ends_with("/v1"):
		b = b.substr(0, b.length() - 3)
	return b.rstrip("/")


func server_voices() -> Array[String]:
	return _voices.duplicate()


func status() -> Dictionary:
	return {"backend": backend_id(), "ready": _ready_flag, "url": contacts_url(), "probed": _first_probe_done}


func build_body(text: String, voice: String) -> String:
	return JSON.stringify({"model": model, "input": text, "voice": voice, "response_format": "wav"})


func synthesize(id: String, text: String, voice: String) -> void:
	if _inflight.has(id):
		push_warning("[HTTPTTSBackend] duplicate request id '%s' ignored" % id)
		return
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SEC
	add_child(http)
	_inflight[id] = http
	var err: int = http.request(contacts_url() + "/v1/audio/speech", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, build_body(text, voice))
	if err != OK:
		_cleanup(id)
		synthesis_finished.emit(id, false, PackedByteArray(), "request could not start (error %d)" % err)
		return
	var _id := id
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void: _on_completed(_id, result, code, body))


func cancel(id: String) -> void:
	if not _inflight.has(id):
		return
	(_inflight[id] as HTTPRequest).cancel_request()
	_cleanup(id)
	synthesis_finished.emit(id, false, PackedByteArray(), "cancelled")


func cancel_all() -> void:
	for id in _inflight.keys().duplicate():
		cancel(id)


## Voice names from {"status":"ok","voices":[...]} (devnen 915ae28) or a list of {"filename":...}.
static func parse_voices(body: String) -> Array[String]:
	var out: Array[String] = []
	var parsed: Variant = JSON.parse_string(body)
	var list: Variant = (parsed as Dictionary).get("voices", []) if parsed is Dictionary else parsed
	if not (list is Array):
		return out
	for v in list:
		if v is String:
			out.append(v)
		elif v is Dictionary and (v as Dictionary).has("filename"):
			out.append(str(v["filename"]))
	return out


func _on_completed(id: String, result: int, code: int, body: PackedByteArray) -> void:
	if not _inflight.has(id):
		return
	_cleanup(id)
	if result != HTTPRequest.RESULT_SUCCESS:
		synthesis_finished.emit(id, false, PackedByteArray(), "request failed (HTTPRequest result %d)" % result)
		return
	if code < 200 or code >= 300:
		synthesis_finished.emit(id, false, PackedByteArray(), "HTTP %d: %s" % [code, body.get_string_from_utf8().left(200)])
		return
	synthesis_finished.emit(id, true, body, "")


func _cleanup(id: String) -> void:
	var http: Variant = _inflight.get(id)
	_inflight.erase(id)
	if http != null and is_instance_valid(http):
		(http as HTTPRequest).queue_free()


func _start_probe() -> void:
	if _probe_request != null and is_instance_valid(_probe_request):
		return
	_probe_request = HTTPRequest.new()
	_probe_request.timeout = PROBE_TIMEOUT_SEC
	add_child(_probe_request)
	_probe_request.request_completed.connect(_on_probe_completed)
	if _probe_request.request(contacts_url() + "/v1/audio/voices") != OK:
		_first_probe_done = true
		_last_probe_msec = Time.get_ticks_msec()
		_cleanup_probe()


func _maybe_refresh_probe() -> void:
	if not _first_probe_done or (_probe_request != null and is_instance_valid(_probe_request)):
		return
	if Time.get_ticks_msec() - _last_probe_msec >= int(PROBE_INTERVAL_SEC * 1000.0):
		_start_probe()


func _on_probe_completed(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var now_ready: bool = result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if now_ready:
		_voices = parse_voices(body.get_string_from_utf8())
	var changed: bool = now_ready != _ready_flag or not _first_probe_done
	_ready_flag = now_ready
	_first_probe_done = true
	_last_probe_msec = Time.get_ticks_msec()
	_cleanup_probe()
	if changed:
		availability_changed.emit(now_ready)


func _cleanup_probe() -> void:
	if _probe_request != null and is_instance_valid(_probe_request):
		if _probe_request.request_completed.is_connected(_on_probe_completed):
			_probe_request.request_completed.disconnect(_on_probe_completed)
		_probe_request.queue_free()
	_probe_request = null
```

- [ ] **Step 6: Implement `tools/replay_tts_backend.gd`**

```gdscript
extends TTSBackend

## Test-only: answers with canned WAV bytes, so no test needs a server or GPU.

var next_wav: PackedByteArray = PackedByteArray()
var voices: Array[String] = []
var silent: bool = false
var fail_error: String = ""
var requests: Array = []
var cancelled: Array[String] = []


func backend_id() -> String:
	return "replay"


func is_ready() -> bool:
	return true


func server_voices() -> Array[String]:
	return voices.duplicate()


func synthesize(id: String, text: String, voice: String) -> void:
	requests.append({"id": id, "text": text, "voice": voice})
	if not silent:
		_emit.call_deferred(id)


func _emit(id: String) -> void:
	if id in cancelled:
		return
	if fail_error != "":
		synthesis_finished.emit(id, false, PackedByteArray(), fail_error)
	else:
		synthesis_finished.emit(id, true, next_wav, "")


func cancel(id: String) -> void:
	cancelled.append(id)
```

- [ ] **Step 7: Import, run, pass.** Expected: EC=0, `Passing 4`. If the refused-connection arm times out rather than failing fast, read the recorded error before changing anything. Port 1 refusing instantly is the assumption under test.

- [ ] **Step 8: Mutation check (load-bearing: the wire contract).** Add `"exaggeration": 0.8` to `build_body`'s dictionary. The four-keys arm must fail. Revert.

- [ ] **Step 9: Commit**

```bash
git add src/llm/TTSBackend.gd src/llm/NullTTSBackend.gd src/llm/HTTPTTSBackend.gd tools/replay_tts_backend.gd test/unit/test_the_speech_client_sends_only_the_wire_contract.gd
git commit -m "feat(voice): speech backends — the HTTP client sends only the wire contract"
```

---

### Task 4: `VoiceCache`: bounded, least recently used out first, keyed by voice + rev + text

**Files:**
- Create: `src/llm/VoiceCache.gd`
- Test: `test/unit/test_the_voice_cache_is_bounded_and_keyed_by_rev.gd`

**Interfaces:**
- Produces: `VoiceCache.new(dir: String = "user://voice_cache", cap: int = 200*1024*1024)`, `static key_for(voice: String, rev: int, text: String) -> String`, `has(key) -> bool`, `read(key) -> PackedByteArray` (empty = miss; a hit counts as a use), `write(key, bytes) -> bool`, `remove(key)`, `total_bytes() -> int`

Least-recently-used order is tracked in memory and seeded from file modification times at startup. Godot has no API to touch a file's mtime, and rewriting the file on every hit would cost a disk write per line spoken. Across sessions, "last used" therefore means "last written". Task 8 updates the spec's §1.4 to say so.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## An unbounded cache is the LLMService._cache defect of 2026-09-20; a recast (rev bump) must never replay stale audio.

const DIR := "user://test_voice_cache"


func before_each() -> void:
	_wipe()


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


func _blob(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	b.fill(1)
	return b


func test_the_key_changes_with_voice_rev_and_text() -> void:
	var k := VoiceCache.key_for("bard.wav", 3, "Hello.")
	assert_eq(k.length(), 32)
	assert_eq(k, ("v1|bard.wav|3|Hello.").sha256_text().left(32), "the spec's key, exactly")
	assert_ne(k, VoiceCache.key_for("bard.wav", 4, "Hello."), "bumping rev must miss")
	assert_ne(k, VoiceCache.key_for("mage.wav", 3, "Hello."))
	assert_ne(k, VoiceCache.key_for("bard.wav", 3, "Hello!"))


func test_a_write_reads_back_and_survives_a_new_instance() -> void:
	var c := VoiceCache.new(DIR, 10_000)
	assert_true(c.write("k1", _blob(100)))
	assert_eq(c.read("k1").size(), 100)
	var again := VoiceCache.new(DIR, 10_000)
	assert_true(again.has("k1"), "the index is rebuilt from disk")
	assert_eq(again.total_bytes(), 100)


func test_the_directory_stays_under_the_cap_and_a_read_protects_a_line() -> void:
	var c := VoiceCache.new(DIR, 1000)
	c.write("old", _blob(400))
	c.write("mid", _blob(400))
	c.read("old")
	c.write("new", _blob(400))
	assert_true(c.total_bytes() <= 1000, "over the cap: %d" % c.total_bytes())
	assert_true(c.has("old"), "read most recently before the write, so it stays")
	assert_false(c.has("mid"), "least recently used goes first")
	assert_true(c.has("new"))
	assert_false(FileAccess.file_exists(DIR + "/mid.wav"), "evicted from disk, not just the index")


func test_constructing_a_cache_writes_nothing() -> void:
	VoiceCache.new(DIR, 1000)
	assert_false(DirAccess.dir_exists_absolute(DIR), "boot must not write user://; the dir appears on first write")
```

- [ ] **Step 2: Import, run, fail.** Expected: EC=3, `VoiceCache` not declared.

- [ ] **Step 3: Implement `src/llm/VoiceCache.gd`**

```gdscript
class_name VoiceCache
extends RefCounted

## Synthesized WAV bytes on disk, bounded: past the cap the least-recently-used line goes first.

const DEFAULT_DIR := "user://voice_cache"
const DEFAULT_CAP_BYTES := 200 * 1024 * 1024

var dir: String
var cap_bytes: int
var _sizes: Dictionary = {}
var _used: Dictionary = {}
var _total: int = 0
var _last_stamp: float = 0.0


func _init(cache_dir: String = DEFAULT_DIR, cap: int = DEFAULT_CAP_BYTES) -> void:
	dir = cache_dir
	cap_bytes = cap
	_scan()


static func key_for(voice: String, rev: int, text: String) -> String:
	return ("v1|%s|%d|%s" % [voice, rev, text]).sha256_text().left(32)


func path_for(key: String) -> String:
	return "%s/%s.wav" % [dir, key]


func has(key: String) -> bool:
	return _sizes.has(key)


func total_bytes() -> int:
	return _total


## The cached bytes, or empty on a miss; a hit counts as a use.
func read(key: String) -> PackedByteArray:
	if not _sizes.has(key):
		return PackedByteArray()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path_for(key))
	if bytes.is_empty():
		_forget(key)
		return bytes
	_used[key] = _stamp()
	return bytes


func write(key: String, bytes: PackedByteArray) -> bool:
	if bytes.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path_for(key), FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	_total += bytes.size() - int(_sizes.get(key, 0))
	_sizes[key] = bytes.size()
	_used[key] = _stamp()
	_evict()
	return true


func remove(key: String) -> void:
	if _sizes.has(key):
		DirAccess.remove_absolute(path_for(key))
		_forget(key)


func _forget(key: String) -> void:
	_total -= int(_sizes.get(key, 0))
	_sizes.erase(key)
	_used.erase(key)


func _evict() -> void:
	if _total <= cap_bytes:
		return
	var keys: Array = _sizes.keys()
	keys.sort_custom(func(a, b): return float(_used[a]) < float(_used[b]))
	for k in keys:
		if _total <= cap_bytes:
			break
		remove(k)


func _stamp() -> float:
	_last_stamp = maxf(Time.get_unix_time_from_system(), _last_stamp + 0.001)
	return _last_stamp


func _scan() -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for name in d.get_files():
		if not name.ends_with(".wav"):
			continue
		var key: String = name.get_basename()
		var f := FileAccess.open(path_for(key), FileAccess.READ)
		if f == null:
			continue
		_sizes[key] = f.get_length()
		f.close()
		_total += int(_sizes[key])
		_used[key] = float(FileAccess.get_modified_time(path_for(key)))
		_last_stamp = maxf(_last_stamp, float(_used[key]))
```

- [ ] **Step 4: Import, run, pass.** Expected: EC=0, `Passing 4`.

- [ ] **Step 5: Mutation checks (load-bearing: cache key, bound).** (a) Drop `rev` from `key_for`'s format, and the rev arm must fail. (b) Make `read` not update `_used`, and the read-protects arm must fail. (c) Make `_evict` return immediately, and the under-cap arm must fail. Revert each.

- [ ] **Step 6: Commit**

```bash
git add src/llm/VoiceCache.gd test/unit/test_the_voice_cache_is_bounded_and_keyed_by_rev.gd
git commit -m "feat(voice): VoiceCache — bounded, least-recently-used out first, keyed by voice, rev and text"
```

---

### Task 5: `VoiceService` autoload: selection, cast, synthesize, status

**Files:**
- Create: `src/llm/VoiceService.gd`
- Modify: `project.godot` `[autoload]`: add `VoiceService="*res://src/llm/VoiceService.gd"` after `PartyPersonas`
- Test: `test/unit/test_voice_service_degrades_to_null_and_never_blocks.gd`

**Interfaces:**
- Consumes: `VoiceAudio.decode/is_clipped`, `VoiceCache`, `TTSBackend`, `NullTTSBackend`, `HTTPTTSBackend`, `GameState.tts_*`
- Produces: `VoiceService.is_live_ready() -> bool`, `status() -> Dictionary` with keys `enabled, ready, backend, url, last_latency_ms, last_error, clipping_detected, missing_voices`, `voice_for(speaker_id) -> Dictionary` ({} when uncast), `cast_speakers() -> Array[String]`, `get_cached(speaker_id, text) -> AudioStream`, `synthesize(speaker_id, text, timeout_sec) -> AudioStream` (await; null on any failure), `apply_config()`, `install_backend(b: TTSBackend)`, `is_web: bool`, `test_backend: TTSBackend` (tests only), `cache: VoiceCache`, `_cast: Dictionary`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## Every failure path returns null in bounded time; the web gate is a PROPERTY (no server URL), so piece 5's browser backend keeps it.

const Replay := preload("res://tools/replay_tts_backend.gd")
const DIR := "user://test_voice_service_cache"

var _saved_cast: Dictionary
var _saved_cache
var _saved_web: bool
var _saved_gs: Dictionary = {}
var _replay


func before_each() -> void:
	_saved_cast = VoiceService._cast.duplicate(true)
	_saved_cache = VoiceService.cache
	_saved_web = VoiceService.is_web
	for f in ["tts_live_enabled", "tts_server_url", "tts_model"]:
		_saved_gs[f] = GameState.get(f)
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {"bard": {"voice": "bard.wav", "rev": 3}}
	_replay = Replay.new()
	_replay.next_wav = WavFixture.tone(0.25, 20000)
	VoiceService.install_backend(_replay)


func after_each() -> void:
	VoiceService.test_backend = null
	VoiceService.is_web = _saved_web
	for f in _saved_gs:
		GameState.set(f, _saved_gs[f])
	VoiceService._cast = _saved_cast
	VoiceService.apply_config()
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(DIR + "/" + f)
		DirAccess.remove_absolute(DIR)
	VoiceService.cache = _saved_cache


func test_an_uncast_speaker_never_asks_the_server() -> void:
	assert_null(await VoiceService.synthesize("goblin", "Hi.", 2.0))
	assert_eq(_replay.requests.size(), 0)


func test_a_fresh_line_is_synthesized_cached_and_then_served_from_cache() -> void:
	var s: AudioStream = await VoiceService.synthesize("bard", "A song.", 2.0)
	assert_not_null(s)
	assert_eq(_replay.requests.size(), 1)
	assert_eq(_replay.requests[0]["voice"], "bard.wav", "the cast's server voice name is what is sent")
	assert_not_null(VoiceService.get_cached("bard", "A song."), "synchronously available for the bubble")
	await VoiceService.synthesize("bard", "A song.", 2.0)
	assert_eq(_replay.requests.size(), 1, "a cached line never reaches the server again")


func test_a_recast_misses_the_old_audio() -> void:
	await VoiceService.synthesize("bard", "A song.", 2.0)
	VoiceService._cast["bard"]["rev"] = 4
	assert_null(VoiceService.get_cached("bard", "A song."), "rev is in the key")


func test_a_cached_blob_that_fails_to_decode_is_deleted_not_served() -> void:
	var key := VoiceCache.key_for("bard.wav", 3, "Rotten.")
	VoiceService.cache.write(key, "not a wav".to_utf8_buffer())
	assert_null(VoiceService.get_cached("bard", "Rotten."))
	assert_false(VoiceService.cache.has(key), "spec 1.4: a blob that fails to decode is deleted, never served")


func test_a_reply_that_is_not_a_whole_wav_is_null_and_not_cached() -> void:
	_replay.next_wav = WavFixture.tone(0.25, 20000).slice(0, 500)
	assert_null(await VoiceService.synthesize("bard", "Cut off.", 2.0))
	assert_null(VoiceService.get_cached("bard", "Cut off."))
	assert_ne(VoiceService.status()["last_error"], "")


func test_a_silent_server_times_out_within_budget_and_is_cancelled() -> void:
	_replay.silent = true
	var t0 := Time.get_ticks_msec()
	assert_null(await VoiceService.synthesize("bard", "Anyone?", 0.3))
	var took := Time.get_ticks_msec() - t0
	assert_true(took < 1000, "took %d ms against a 300 ms budget" % took)
	assert_eq(_replay.cancelled.size(), 1, "the abandoned request is cancelled")
	assert_string_contains(VoiceService.status()["last_error"], "timed out")


func test_clipping_is_flagged_in_status() -> void:
	var s := PackedInt32Array()
	s.resize(12000)
	for i in s.size():
		s[i] = 32767 if (i % 1000) < 5 else 1000
	_replay.next_wav = WavFixture.pcm16(s)
	await VoiceService.synthesize("bard", "Loud.", 2.0)
	assert_true(VoiceService.status()["clipping_detected"])


func test_status_has_the_spec_shape_and_names_missing_voices() -> void:
	VoiceService._cast["mage"] = {"voice": "mage.wav", "rev": 1}
	_replay.voices = ["bard.wav"] as Array[String]
	var st: Dictionary = VoiceService.status()
	for k in ["enabled", "ready", "backend", "url", "last_latency_ms", "last_error", "clipping_detected", "missing_voices"]:
		assert_true(st.has(k), "status needs %s" % k)
	assert_eq(st["missing_voices"], ["mage.wav"] as Array[String])
	_replay.voices = [] as Array[String]
	assert_eq(VoiceService.status()["missing_voices"], [] as Array[String], "an unknown server list flags nothing")


func test_on_web_no_backend_contacts_a_server_url() -> void:
	GameState.tts_live_enabled = true
	GameState.tts_server_url = "http://127.0.0.1:8004"
	VoiceService.is_web = true
	VoiceService.apply_config()
	assert_eq(VoiceService.status()["url"], "", "on web nothing may point at a server")
	assert_null(await VoiceService.synthesize("bard", "Anything.", 0.5))
	assert_eq(VoiceService.find_children("*", "HTTPRequest", true, false).size(), 0, "no HTTPRequest was ever made")


func test_control_on_desktop_the_same_config_does_point_at_the_server() -> void:
	GameState.tts_live_enabled = true
	GameState.tts_server_url = "http://127.0.0.1:1"
	VoiceService.is_web = false
	VoiceService.apply_config()
	assert_eq(VoiceService.status()["url"], "http://127.0.0.1:1", "CONTROL: without the web gate this is where requests go")


func test_live_off_selects_a_backend_that_contacts_nothing() -> void:
	GameState.tts_live_enabled = false
	VoiceService.is_web = false
	VoiceService.apply_config()
	assert_eq(VoiceService.status()["url"], "")
	assert_false(VoiceService.is_live_ready())
```

- [ ] **Step 2: Implement `src/llm/VoiceService.gd`** (import after adding the autoload line)

```gdscript
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
		if _backend.get_parent() == self:
			remove_child(_backend)
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
	if s == null:
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
```

Add `VoiceService="*res://src/llm/VoiceService.gd"` to `project.godot` directly after the `PartyPersonas=` autoload line.

- [ ] **Step 3: Import, run, pass.** `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh voice_service_degrades_to_null_and_never_blocks`. Expected: EC=0, `Passing 11`. (There is no separate red step for a new file whose subject doesn't exist yet. The mutation step below is what shows the guards fire.)

- [ ] **Step 4: Mutation checks (load-bearing: web gating, timeout).** (a) Remove `is_web or` from `_make_backend`. The web arm must fail, and its control must still pass. (b) Remove the `and Time.get_ticks_msec() - t0 < …` clause, which gives an unbounded wait. Wrap this run in the harness's normal bound. The timeout arm must fail or the run must be killed as wedged (EC=124); either shows the bound is load-bearing. Revert each and re-run green.

- [ ] **Step 5: Run the autoload guard.** `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh autoloads_actually_register`. Expected: EC=0.

- [ ] **Step 6: Commit**

```bash
git add src/llm/VoiceService.gd project.godot test/unit/test_voice_service_degrades_to_null_and_never_blocks.gd
git commit -m "feat(voice): VoiceService — backend selection, cast, cache and status; every failure is null"
```

---

### Task 6: `SoundManager.play_voice_stream`

**Files:**
- Modify: `src/audio/SoundManager.gd` (after `play_voice`, ~line 983)
- Test: `test/unit/test_a_synthesized_line_plays_like_a_recorded_one.gd`

**Interfaces:**
- Produces: `SoundManager.play_voice_stream(stream: AudioStream) -> float` (length in seconds; 0.0 on null)

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## A live line must use play_voice's player, level and unity pitch, and return its length: the bubble's hold is set from it.

func test_it_plays_on_the_voice_player_at_unity_pitch_and_returns_its_length() -> void:
	var s := VoiceAudio.decode(WavFixture.tone(0.5, 20000))
	SoundManager._voice_player.pitch_scale = 0.9
	SoundManager._voice_player.volume_db = -30.0
	var got: float = SoundManager.play_voice_stream(s)
	assert_almost_eq(got, 0.5, 0.001, "the bubble holds for exactly this long")
	assert_eq(SoundManager._voice_player.stream, s)
	assert_eq(SoundManager._voice_player.pitch_scale, 1.0, "a stale pitch would detune the voice and lie about its length")
	assert_eq(SoundManager._voice_player.volume_db, SoundManager.VOICE_PLAYER_BASE_DB)
	SoundManager.stop_voice()


func test_null_plays_nothing_and_holds_for_nothing() -> void:
	assert_eq(SoundManager.play_voice_stream(null), 0.0)
```

- [ ] **Step 2: Run, fail.** Expected: EC=1 (`Invalid call. Nonexistent function 'play_voice_stream'`).

- [ ] **Step 3: Implement**, directly after `play_voice`:

```gdscript
## A synthesized line on play_voice's player, level and unity pitch; returns its length so the bubble's hold holds.
func play_voice_stream(stream: AudioStream) -> float:
	if _voice_player == null or stream == null:
		return 0.0
	_voice_player.stream = stream
	_voice_player.volume_db = VOICE_PLAYER_BASE_DB
	_voice_player.pitch_scale = 1.0
	_voice_player.play()
	return stream.get_length()
```

- [ ] **Step 4: Run, pass.** Expected: EC=0, `Passing 2`. Then run the existing voice-player files that reach `_voice_player`, so the change is checked against the recorded-voice path: `for n in $(command grep -a -rl "_voice_player\|play_voice" test/unit | xargs -n1 basename | sed 's/^test_//; s/\.gd$//'); do XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh $n > tmp/pv_$n.log 2>&1; echo "$n EC=$?"; done`. Expected: every file EC=0.

- [ ] **Step 5: Commit**

```bash
git add src/audio/SoundManager.gd test/unit/test_a_synthesized_line_plays_like_a_recorded_one.gd
git commit -m "feat(voice): play_voice_stream — a live line plays like a recorded one"
```

---

### Task 7: The Configure Live Voice panel and its Settings row

**Files:**
- Create: `src/ui/LiveVoicePanel.gd`
- Modify: `src/ui/SettingsMenu.gd`. Add the action row after "Configure BYOK" (~line 671), the dispatch arm after `byok_config` (~line 1706), `_open_live_voice_config` / `_on_live_voice_config_closed` after `_on_byok_config_closed` (~line 1789), the `_live_voice_config_open` flag at ~line 112, and the flag in every guard that lists `_byok_config_open` (~lines 1142, 1159, 2009) plus the `_has_live_submenu_child` path list
- Test: `test/unit/test_the_live_voice_panel_speaks_and_refuses_web.gd`

**Interfaces:**
- Consumes: `VoiceService.apply_config/status/cast_speakers/synthesize/is_live_ready`, `SoundManager.play_voice_stream`, `SaveSystem.save_settings`, `PartyPersonas.get_trigger_voice(job, "turn_start")`
- Produces: `LiveVoicePanel` (`signal closed()`), `static LiveVoicePanel.status_text(st: Dictionary) -> String`, `_on_test_pressed()` (async), `_on_save_pressed()`, `_on_cancel_pressed()`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## Test Voice must speak through the live path with the TYPED settings; the panel and its row never exist on web.

const Replay := preload("res://tools/replay_tts_backend.gd")
const MENU := "res://src/ui/SettingsMenu.gd"
const PANEL := "res://src/ui/LiveVoicePanel.gd"

var _saved_gs: Dictionary = {}
var _saved_cast: Dictionary
var _replay


func before_each() -> void:
	for f in ["tts_live_enabled", "tts_server_url", "tts_model"]:
		_saved_gs[f] = GameState.get(f)
	_saved_cast = VoiceService._cast.duplicate(true)
	VoiceService._cast = {"bard": {"voice": "bard.wav", "rev": 1}}
	_replay = Replay.new()
	_replay.next_wav = WavFixture.tone(0.3, 20000)
	VoiceService.test_backend = _replay


func after_each() -> void:
	VoiceService.test_backend = null
	for f in _saved_gs:
		GameState.set(f, _saved_gs[f])
	VoiceService._cast = _saved_cast
	VoiceService.apply_config()
	SoundManager.stop_voice()


func test_test_voice_speaks_a_cast_line_through_play_voice_stream() -> void:
	GameState.tts_live_enabled = false
	var p := LiveVoicePanel.new()
	add_child_autofree(p)
	p._enabled_toggle.button_pressed = true
	await p._on_test_pressed()
	assert_eq(_replay.requests.size(), 1, "the TYPED enable is what the test uses: %s" % p._status_label.text)
	assert_eq(_replay.requests[0]["voice"], "bard.wav")
	assert_not_null(SoundManager._voice_player.stream, "the synthesized line reached the voice player")
	assert_string_contains(p._status_label.text, "ms")


func test_cancel_restores_the_settings_the_panel_opened_with() -> void:
	GameState.tts_live_enabled = false
	GameState.tts_server_url = "http://127.0.0.1:8004"
	var p := LiveVoicePanel.new()
	add_child(p)
	p._enabled_toggle.button_pressed = true
	p._url_field.text = "http://127.0.0.1:1"
	await p._on_test_pressed()
	p._on_cancel_pressed()
	assert_eq(GameState.tts_live_enabled, false, "Test applied the typed values; Cancel must put them back")
	assert_eq(GameState.tts_server_url, "http://127.0.0.1:8004")


func test_status_text_names_missing_voices_and_the_supported_server() -> void:
	var t := LiveVoicePanel.status_text({"enabled": true, "ready": true, "url": "http://127.0.0.1:8004",
		"last_latency_ms": 812, "last_error": "", "clipping_detected": true, "missing_voices": ["mage.wav"]})
	assert_string_contains(t, "mage.wav")
	assert_string_contains(t, "915ae28", "the clipping warning names the supported server")
	assert_string_contains(LiveVoicePanel.status_text({"enabled": false}), "off")


func test_the_row_and_the_open_helper_are_desktop_only() -> void:
	var src: String = FileAccess.get_file_as_string(MENU)
	var row: int = src.find("\"Configure Live Voice\"")
	assert_gt(row, -1, "the Settings row exists")
	var gate: int = src.rfind("if not OS.has_feature(\"web\"):", row)
	assert_gt(gate, -1)
	assert_eq(src.substr(gate, row - gate).count("\n"), 2, "the gate is the line immediately above the add_action call")
	var at: int = src.find("func _open_live_voice_config")
	assert_gt(at, -1)
	assert_true(src.substr(at, 120).contains("if OS.has_feature(\"web\"):"), "belt and braces, like _open_byok_config")
	assert_true(FileAccess.get_file_as_string(PANEL).contains("if OS.has_feature(\"web\"):"), "the panel refuses to build on web")


## A guard site enumerates several panel flags; _open_byok_config's own lines name only BYOK's and are not one.
const OTHER_FLAGS := ["_rebalance_review_open", "_jukebox_submenu_open", "_rebalance_history_open"]


func test_every_guard_that_knows_the_byok_panel_knows_this_one() -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string(MENU).split("\n")
	var sites := 0
	var missing: Array[String] = []
	for i in lines.size():
		if not lines[i].contains("_byok_config_open") or lines[i].strip_edges().begins_with("var "):
			continue
		var window: String = "\n".join(lines.slice(maxi(0, i - 2), i + 3))
		if not OTHER_FLAGS.any(func(f): return window.contains(f)):
			continue
		sites += 1
		if not window.contains("_live_voice_config_open"):
			missing.append("%d: %s" % [i + 1, lines[i].strip_edges()])
	assert_true(sites >= 3, "VOID: found only %d guard sites (expected _process, _input and the failsafe reset)" % sites)
	var src: String = FileAccess.get_file_as_string(MENU)
	assert_true(src.contains("path.ends_with(\"LiveVoicePanel.gd\")"), "the stuck-flag failsafe must recognise the panel")
	assert_eq(missing, [] as Array[String], "a guard that forgets this panel strands input: %s" % [missing])
```

- [ ] **Step 2: Import, run, fail.** Expected: EC=3, `LiveVoicePanel` not declared.

- [ ] **Step 3: Implement `src/ui/LiveVoicePanel.gd`**

```gdscript
extends Control
class_name LiveVoicePanel

## Configure Live Voice: server URL, enable, and a Test Voice that speaks a cast line; never built on web.

signal closed()

const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const PANEL_COLOR := Color(0.12, 0.12, 0.18)
const BORDER_LIGHT := Color(0.6, 0.6, 0.7)
const HEADER_COLOR := Color(0.85, 0.75, 0.40)
const DIM_COLOR := Color(0.65, 0.65, 0.70)
const OK_COLOR := Color(0.45, 0.85, 0.50)
const FAIL_COLOR := Color(0.95, 0.45, 0.40)
const BUSY_COLOR := Color(0.85, 0.75, 0.40)
const CONNECT_WAIT_SEC := 3.0
const TEST_TIMEOUT_SEC := 12.0
const SAMPLE_FALLBACK := "This is how I sound when the game speaks for me."
const SUPPORTED_SERVER := "devnen Chatterbox-TTS-Server 915ae28 + the cowir-sfx patch"

var _enabled_toggle: CheckButton
var _url_field: LineEdit
var _speaker_picker: OptionButton
var _status_label: Label
var _test_btn: Button
var _save_btn: Button
var _cancel_btn: Button
var _testing: bool = false
var _opened_with: Dictionary = {}


func _ready() -> void:
	if OS.has_feature("web"):
		closed.emit()
		queue_free()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for f in ["tts_live_enabled", "tts_server_url", "tts_model"]:
		_opened_with[f] = GameState.get(f)
	_build_ui()
	_enabled_toggle.button_pressed = bool(GameState.tts_live_enabled)
	_url_field.text = str(GameState.tts_server_url)
	_show_status()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	var w: float = min(680.0, vp.x - 80)
	var h: float = min(360.0, vp.y - 80)
	var x: float = (vp.x - w) / 2.0
	var y: float = (vp.y - h) / 2.0
	var rim := ColorRect.new()
	rim.color = BORDER_LIGHT
	rim.position = Vector2(x - 3, y - 3)
	rim.size = Vector2(w + 6, h + 6)
	add_child(rim)
	var panel := ColorRect.new()
	panel.color = PANEL_COLOR
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, h)
	add_child(panel)
	_label("LIVE VOICE", x + 20, y + 16, w - 40, 18, HEADER_COLOR)
	_label("A local speech server voices lines the game writes. Off: you hear the shipped recordings.", x + 20, y + 44, w - 40, 11, DIM_COLOR)
	var lx: float = x + 24
	var cx: float = x + 170
	var cw: float = w - 194
	_label("Enabled", lx, y + 86, 140, 13, Color.WHITE)
	_enabled_toggle = CheckButton.new()
	_enabled_toggle.position = Vector2(cx, y + 82)
	add_child(_enabled_toggle)
	_label("Server URL", lx, y + 126, 140, 13, Color.WHITE)
	_url_field = LineEdit.new()
	_url_field.placeholder_text = "http://127.0.0.1:8004"
	_url_field.position = Vector2(cx, y + 122)
	_url_field.size = Vector2(cw, 30)
	add_child(_url_field)
	_label("Speaker", lx, y + 166, 140, 13, Color.WHITE)
	_speaker_picker = OptionButton.new()
	_speaker_picker.position = Vector2(cx, y + 162)
	_speaker_picker.size = Vector2(cw, 30)
	var speakers: Array[String] = VoiceService.cast_speakers() if VoiceService != null else ([] as Array[String])
	for s in speakers:
		_speaker_picker.add_item(s)
	if speakers.is_empty():
		_speaker_picker.add_item("(no voices cast yet)")
		_speaker_picker.disabled = true
	add_child(_speaker_picker)
	_status_label = _label("", lx, y + 206, w - 48, 12, DIM_COLOR)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size.y = 72
	_test_btn = _button("Test Voice", x + 24, y + h - 56, _on_test_pressed)
	_save_btn = _button("Save", x + w - 360, y + h - 56, _on_save_pressed)
	_cancel_btn = _button("Cancel", x + w - 184, y + h - 56, _on_cancel_pressed)
	var spine: Array = [_enabled_toggle, _url_field, _speaker_picker, _test_btn]
	for i in spine.size():
		spine[i].focus_neighbor_top = spine[i].get_path_to(spine[i - 1] if i > 0 else _save_btn)
		spine[i].focus_neighbor_bottom = spine[i].get_path_to(spine[i + 1] if i + 1 < spine.size() else _save_btn)
	for row in [[_test_btn, _cancel_btn, _save_btn], [_save_btn, _test_btn, _cancel_btn], [_cancel_btn, _save_btn, _test_btn]]:
		row[0].focus_neighbor_left = row[0].get_path_to(row[1])
		row[0].focus_neighbor_right = row[0].get_path_to(row[2])
	_save_btn.focus_neighbor_top = _save_btn.get_path_to(_speaker_picker)
	_cancel_btn.focus_neighbor_top = _cancel_btn.get_path_to(_speaker_picker)
	_save_btn.focus_neighbor_bottom = _save_btn.get_path_to(_enabled_toggle)
	_cancel_btn.focus_neighbor_bottom = _cancel_btn.get_path_to(_enabled_toggle)
	_enabled_toggle.grab_focus.call_deferred()


func _label(text: String, x: float, y: float, w: float, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.position = Vector2(x, y)
	l.size = Vector2(w, size + 10)
	add_child(l)
	return l


func _button(text: String, x: float, y: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size = Vector2(160, 36)
	b.position = Vector2(x, y)
	b.pressed.connect(cb)
	add_child(b)
	return b


## The one line the player reads: readiness, latency, missing voices, and a clipping warning naming the supported server.
static func status_text(st: Dictionary) -> String:
	if not bool(st.get("enabled", false)):
		return "Live voice is off. Turn it on to test."
	var parts: Array[String] = []
	if bool(st.get("ready", false)):
		parts.append("Connected to %s" % str(st.get("url", "")))
	else:
		parts.append("Can't reach the voice server at %s" % str(st.get("url", "")))
	if int(st.get("last_latency_ms", -1)) >= 0:
		parts.append("last line in %d ms" % int(st["last_latency_ms"]))
	if str(st.get("last_error", "")) != "":
		parts.append("error: %s" % str(st["last_error"]))
	var missing: Array = st.get("missing_voices", [])
	if not missing.is_empty():
		parts.append("missing voices: %s" % ", ".join(PackedStringArray(missing)))
	if bool(st.get("clipping_detected", false)):
		parts.append("CLIPPING: this server distorts loud lines; use %s" % SUPPORTED_SERVER)
	return ". ".join(PackedStringArray(parts)) + "."


func _show_status() -> void:
	if VoiceService != null:
		_set_status(status_text(VoiceService.status()), DIM_COLOR)


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _apply_typed() -> void:
	GameState.tts_live_enabled = _enabled_toggle.button_pressed
	var url: String = _url_field.text.strip_edges()
	GameState.tts_server_url = url if url != "" else "http://127.0.0.1:8004"
	VoiceService.apply_config()


func _on_test_pressed() -> void:
	if _testing:
		return
	_testing = true
	_apply_typed()
	if not GameState.tts_live_enabled:
		_set_status(status_text(VoiceService.status()), DIM_COLOR)
		_testing = false
		return
	_set_status("Connecting…", BUSY_COLOR)
	var t0 := Time.get_ticks_msec()
	while not VoiceService.is_live_ready() and Time.get_ticks_msec() - t0 < int(CONNECT_WAIT_SEC * 1000.0):
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var speaker: String = "" if _speaker_picker.disabled else _speaker_picker.get_item_text(_speaker_picker.selected)
	if speaker == "":
		_set_status("No voices are cast yet (data/voice_cast.json).", FAIL_COLOR)
		_testing = false
		return
	_set_status("Speaking…", BUSY_COLOR)
	var stream: AudioStream = await VoiceService.synthesize(speaker, _sample_line(speaker), TEST_TIMEOUT_SEC)
	if not is_inside_tree():
		return
	if stream != null:
		SoundManager.play_voice_stream(stream)
		_set_status(status_text(VoiceService.status()), OK_COLOR)
	else:
		_set_status(status_text(VoiceService.status()), FAIL_COLOR)
	_testing = false


func _sample_line(speaker: String) -> String:
	var pp := get_node_or_null("/root/PartyPersonas")
	var line: String = str(pp.get_trigger_voice(speaker, "turn_start")) if pp != null and pp.has_method("get_trigger_voice") else ""
	return line if line != "" else SAMPLE_FALLBACK


func _on_save_pressed() -> void:
	_apply_typed()
	if SaveSystem and SaveSystem.has_method("save_settings"):
		SaveSystem.save_settings()
	if SoundManager:
		SoundManager.play_ui("menu_select")
	closed.emit()
	queue_free()


func _on_cancel_pressed() -> void:
	for f in _opened_with:
		GameState.set(f, _opened_with[f])
	VoiceService.apply_config()
	if SoundManager:
		SoundManager.play_ui("menu_cancel")
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if not (get_viewport().gui_get_focus_owner() is LineEdit):
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
```

- [ ] **Step 4: Wire `SettingsMenu.gd`**, six edits:
  1. By `var _byok_config_open`: `var _live_voice_config_open: bool = false`.
  2. After the "Configure BYOK" `add_action.call(...)` block:
     ```gdscript
     	if not OS.has_feature("web"):
     		add_action.call(
     			"Configure Live Voice",
     			"A local speech server voices lines the game writes (desktop)",
     			"live_voice_config")
     ```
  3. After the `byok_config` dispatch arm: `elif item["id"] == "live_voice_config":` then `_open_live_voice_config()`.
  4. After `_on_byok_config_closed`:
     ```gdscript
     func _open_live_voice_config() -> void:
     	if OS.has_feature("web"):
     		return
     	_live_voice_config_open = true
     	var PanelScript = load("res://src/ui/LiveVoicePanel.gd")
     	if not PanelScript:
     		_live_voice_config_open = false
     		return
     	var panel = PanelScript.new()
     	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
     	panel.closed.connect(_on_live_voice_config_closed)
     	add_child(panel)
     	if SoundManager:
     		SoundManager.play_ui("menu_select")


     func _on_live_voice_config_closed() -> void:
     	_live_voice_config_open = false
     ```
  5. Append `or _live_voice_config_open` beside `_byok_config_open` in `_process`'s guard and `_input`'s guard, and add `_live_voice_config_open = false` beside `_byok_config_open = false` in the failsafe reset.
  6. In `_has_live_submenu_child`, add `or path.ends_with("LiveVoicePanel.gd") \` to the path list.

- [ ] **Step 5: Import, run, pass.** Expected: EC=0, `Passing 5`. If `test_every_guard…` names a line, add the flag there.

- [ ] **Step 6: Run the BYOK and settings files that share these sites.** Loop the `run_tests.sh` form from Task 6 over `byok_config_panel byok_settings_ui_regression settings_menu_from_title_exit_regression settings_menu_controls_subtitle settings_menu_debug_button_subtitles`. Expected: every file EC=0.

- [ ] **Step 7: Mutation check (load-bearing: the guard-site sweep).** Remove `or _live_voice_config_open` from `_input`'s guard. `test_every_guard…` must fail and name that line. Revert.

- [ ] **Step 8: Commit**

```bash
git add src/ui/LiveVoicePanel.gd src/ui/SettingsMenu.gd test/unit/test_the_live_voice_panel_speaks_and_refuses_web.gd
git commit -m "feat(voice): Configure Live Voice panel — Test Voice speaks a cast line, desktop only"
```

---

### Task 8: Spec correction, real-server smoke, hand-offs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-24-local-tts-voice-design.md` §1.4 and §1.5

- [ ] **Step 1: Correct §1.4.** Replace "Read touches the file's modification time (LRU)." with: "A read counts as a use for least-recently-used eviction. Order is kept in memory and seeded from file modification times at startup, because Godot has no API to touch a file's mtime, and rewriting the file on every hit would cost a disk write per line spoken. Across sessions, 'last used' therefore means 'last written'."

- [ ] **Step 2: Add a §1.5 caveat under `missing_voices`:** "`/v1/audio/voices` lists **predefined** voices only (devnen `server.py` @ `915ae28`, `utils.get_predefined_voices()`), while `/v1/audio/speech` also accepts reference-audio files. A cast voice must therefore live in the predefined voices directory, or it is reported missing while still working."

- [ ] **Step 3: Real-server smoke, only if one is running.** `curl -s -m 2 http://127.0.0.1:8004/v1/audio/voices`. If no server answers, skip this step and say so in the hand-off; don't claim a live test. If one answers, write `tmp/smoke_live_voice.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var vs = root.get_node("VoiceService")
	var gs = root.get_node("GameState")
	gs.tts_live_enabled = true
	gs.tts_server_url = "http://127.0.0.1:8004"
	vs.cache = VoiceCache.new("user://smoke_voice_cache", 50_000_000)
	vs.apply_config()
	var t0 := Time.get_ticks_msec()
	while not vs.is_live_ready() and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	var voices: Array = vs._backend.server_voices()
	print("SMOKE ready=%s voices=%s" % [vs.is_live_ready(), voices])
	if voices.is_empty():
		quit(1)
		return
	vs._cast = {"smoke": {"voice": str(voices[0]), "rev": 0}}
	var s: AudioStream = await vs.synthesize("smoke", "Steel speaks plain.", 15.0)
	print("SMOKE stream=%s length=%.2f status=%s" % [s, s.get_length() if s else -1.0, vs.status()])
	quit(0 if s != null else 1)
```

Run: `bash -c 'timeout 60 env XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy -s $PWD/tmp/smoke_live_voice.gd > tmp/smoke_live_voice.out 2>&1'; echo EC=$?; command grep -a SMOKE tmp/smoke_live_voice.out`. Record the latency, `clipping_detected`, and the decoded length for the hand-off. Stock devnen should report `clipping_detected: true` on theatrical lines, and the patched server should report false.

- [ ] **Step 4: Commit the spec, push, and hand off.**

```bash
git add docs/superpowers/specs/2026-09-24-local-tts-voice-design.md docs/superpowers/plans/2026-09-25-live-voice-client.md
git commit -m "docs(voice): piece 1 plan; cache recency and voice-list caveats measured against the code"
git push -u origin llm/tts-client
```

Send three messages:
- **cowir-main:** READY TO FOLD, with the SHA, the list of test files and their counts, the mutations run, and the fact that the branch depends on `llm/voice-choice-variety` (the spec lives there).
- **cowir-sfx:** (1) please add `data/voice_cast.json` in the contract-3 shape, because Test Voice lists only cast speakers; (2) put cast voices in the **predefined** voices directory; (3) the clipping threshold still needs their negative control (patched output) and positive control (stock devnen), per §1.5.
- **cowir-story:** nothing is needed yet.
