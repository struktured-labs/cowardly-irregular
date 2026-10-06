# Voiced Party Lines With Prefetch (Piece 2b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With live voice and LLM party dialogue both on, party members speak fresh LLM-written lines in their own synthesized voice, prefetched so a battle never waits.

**Architecture:** A `VoicePool` autoload keeps one ready line per (speaker, trigger): text in `user://voice_cache/pool.json`, audio in the existing `VoiceCache`. It fills one empty slot at a time, only when neither the LLM nor the TTS server is busy, in order of how often the trigger fires. The party-line picker plays a pooled line after any moment line and before the LLM chooses among authored lines. The line travels to the bubble as a one-shot `pool:<n>` token that BattleScene redeems for the AudioStream.

**Tech Stack:** Godot 4.4.1 GDScript, GUT 9.4 via `tools/run_tests.sh`, the piece-1 voice stack (`VoiceService`, `VoiceCache`, `VoiceAudio`, `tools/replay_tts_backend.gd`, `test/unit/helpers/wav_fixture.gd`).

**Spec:** `docs/superpowers/specs/2026-09-24-local-tts-voice-design.md`, Piece 2b (2b.1, 2b.2). 2b.3 (bosses) is deferred; see Scope.

## Global Constraints

- Fallback ladder, everywhere: live synthesized line → shipped prerendered clip → text only. No rung may block gameplay; "A battle never waits on synthesis."
- The client never sends exaggeration, cfg, temperature or seed (delivery stays server-side).
- Web is unchanged: no pool, no fill, no live audio on web.
- "A pooled line must be true in any battle it might be used in": code discards any generated line containing a party job id, party member name, or enemy name, **before synthesis**.
- Idle fill: one slot at a time, only when no LLM or TTS request is in flight; **never a burst at battle start**; empty slots fill in order of how often their trigger fires (`turn_start` before `victory`).
- The pool persists to `user://voice_cache/pool.json`, so a new session starts warm.
- Empty slot at trigger time → the shipped path (2a.1 steps 4–5).
- Picker order (2a.1): a MOMENT line that holds wins; then a ready pooled line; then LLM choose; then random.
- `.gd` comments: one line max. Every godot run sets `XDG_DATA_HOME=$PWD/tmp/xdg`. Run only your own files' tests; cowir-main runs the full suite at the fold.

## Scope

**In:** 2b.1 (bubble plays a synthesized stream) and 2b.2 (the ready pool) for the party.

**Deferred, 2b.3 (bosses), for two measured reasons.** (1) `data/voice_cast.json` casts no boss, so a boss pool could never produce audio and its tests would only exercise fakes. (2) Boss taunts are bound to the intent they announce (`_update_boss_dialogue_phase` emits the taunt of the picked intent), so a generic pooled taunt would contradict the posture the boss just declared. Which boss pools can take a pooled line is a cowir-story question. The gloat half of 2b.3 ("the voice is chosen once") already holds: since `.533` a gloat emits exactly once (`GLOAT_WAIT_SEC`), and gloats render in the battle log, not a bubble. The pool below is keyed by speaker id, not job, so bosses become a data addition once cast.

## File Structure

| File | Responsibility |
|---|---|
| `src/battle/BattleSpeechBubble.gd` (modify) | `spawn` takes an optional `voice_stream`; `_play_voice` prefers it over `audio_key`. |
| `src/battle/BattleScene.gd` (modify) | `_spawn_quip_bubble` forwards `voice_stream`; `_on_party_combat_line` redeems `pool:` tokens. |
| `src/llm/VoicePoolStore.gd` (create) | Pure data: slots, take/put, staleness against the cast, JSON persistence, the name-discard predicate. |
| `src/llm/VoicePool.gd` (create, autoload `VoicePool`) | When to fill and what to fill; generation (prompt → validate → discard → synthesize); token stash. |
| `src/llm/DialoguePrompts.gd` (modify) | `build_pooled_party_line`: a line for persona + trigger that names no one. |
| `src/llm/LLMService.gd`, `src/llm/VoiceService.gd`, `src/llm/PartyPersonas.gd` (modify) | Small predicates: `is_idle()`, `is_busy()`, `has_moment_line()`. |
| `src/battle/BattleManager.gd` (modify) | Picker step 3 in `_run_party_line_async`. |
| `project.godot` (modify) | Register `VoicePool` after `VoiceService`. |

---

### Task 1: The bubble plays a synthesized line (2b.1)

**Files:**
- Modify: `src/battle/BattleSpeechBubble.gd` (`spawn`, `_play_voice`)
- Modify: `src/battle/BattleScene.gd` (`_spawn_quip_bubble`)
- Test: `test/unit/test_a_bubble_speaks_a_synthesized_line.gd`

**Interfaces:**
- Produces: `BattleSpeechBubble.spawn(..., keep_out: Callable = Callable(), voice_stream: AudioStream = null)` (new LAST parameter); `BattleScene._spawn_quip_bubble(sprite, speaker_name, line, border_color, hold_time, audio_key, voice_stream: AudioStream = null)`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## 2b.1: a pooled line carries its own audio. The bubble must play it, and hold for it, exactly as it does a shipped clip.

func _bubble(stream: AudioStream, key: String = ""):
	var parent := Node2D.new()
	add_child_autofree(parent)
	return BattleSpeechBubble.spawn(parent, Vector2(400, 300), "Bard", "A line.", Color.WHITE, 1.5, key,
		true, 0.0, BattleSpeechBubble.TOP_MARGIN, Callable(), stream)


func test_a_stream_plays_and_sets_the_hold() -> void:
	var stream := VoiceAudio.decode(WavFixture.tone(0.6, 8000))
	if stream == null:
		fail_test(WavFixture.refusal_note(WavFixture.decode_refusal_reason(stream)))
		return
	var b = _bubble(stream)
	assert_not_null(b, "CONTROL: the bubble spawned")
	if SoundManager.wav_commit_refused():
		pending("mixer latched: play_voice_stream refuses by design")
		return
	assert_eq(SoundManager._voice_player.stream, stream, "the synthesized stream is not the one on the voice player")
	assert_gte(b._hold_time, stream.get_length() + BattleSpeechBubble.VOICE_TAIL_S - 0.01,
		"the bubble fades before its line is spoken")


func test_a_stream_wins_over_a_clip_key() -> void:
	var stream := VoiceAudio.decode(WavFixture.tone(0.4, 8000))
	if stream == null or SoundManager.wav_commit_refused():
		pending("decode refused or mixer latched")
		return
	_bubble(stream, "voice_bard_turn_start")
	assert_eq(SoundManager._voice_player.stream, stream, "a shipped clip played over the synthesized line it was given")


func test_control_no_stream_keeps_todays_behaviour() -> void:
	var b = _bubble(null, "")
	assert_eq(b._hold_time, 1.5, "CONTROL: with neither a stream nor a key, the hold is the caller's")
	assert_false(b._voiced, "CONTROL: nothing was voiced")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh test_a_bubble_speaks_a_synthesized_line`
Expected: FAIL, a parse error (spawn takes no 12th argument) → EC 3.

- [ ] **Step 3: Implement**

In `BattleSpeechBubble.spawn`, append the parameter and forward it:

```gdscript
		ceiling_y: float = TOP_MARGIN, keep_out: Callable = Callable(), voice_stream: AudioStream = null) -> BattleSpeechBubble:
	...
	b._play_voice(audio_key, voice_stream)
```

Replace `_play_voice`:

```gdscript
## Plays the line's audio (a synthesized stream wins over a shipped clip) and holds the bubble for as long as it lasts.
func _play_voice(audio_key: String, voice_stream: AudioStream = null) -> void:
	if audio_key == "" and voice_stream == null:
		return
	var sm := get_node_or_null("/root/SoundManager")
	if sm == null:
		return
	var clip_len: float = 0.0
	if voice_stream != null and sm.has_method("play_voice_stream"):
		clip_len = sm.play_voice_stream(voice_stream)
	elif audio_key != "" and sm.has_method("play_voice"):
		clip_len = sm.play_voice(audio_key)
	if clip_len <= 0.0:
		return
	_hold_time = maxf(_hold_time, clip_len + VOICE_TAIL_S)
	_voiced = true
```

Keep the existing two explanatory comments above `_hold_time = ...`. In `BattleScene._spawn_quip_bubble`, add `voice_stream: AudioStream = null` as the last parameter and append it to the spawn call:

```gdscript
	BattleSpeechBubble.spawn(self, anchor, speaker_name, line, border_color, hold_time, audio_key, prefer_right, half_w, ceiling, _bubble_keep_out_rects, voice_stream)
```

- [ ] **Step 4: Run the test and its neighbours**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh test_a_bubble_speaks_a_synthesized_line` → 3/3.
Mutation: make `_play_voice` ignore `voice_stream` → arms 1–2 red. Restore.
Neighbours: every test file that names `BattleSpeechBubble` or `_spawn_quip_bubble` (`command grep -rlE "BattleSpeechBubble|_spawn_quip_bubble" test/unit`) → all green.

- [ ] **Step 5: Commit**

```bash
git add src/battle/BattleSpeechBubble.gd src/battle/BattleScene.gd test/unit/test_a_bubble_speaks_a_synthesized_line.gd
git commit -m "feat(voice): a speech bubble can speak a synthesized line (piece 2b.1)"
```

---

### Task 2: The pool's data (VoicePoolStore)

**Files:**
- Create: `src/llm/VoicePoolStore.gd`
- Test: `test/unit/test_the_voice_pool_store_keeps_true_lines.gd`

**Interfaces:**
- Produces: `class_name VoicePoolStore extends RefCounted` with `path: String`, `slots: Dictionary`, `static func slot_key(speaker: String, trigger: String) -> String`, `func has_line(speaker, trigger) -> bool`, `func peek(speaker, trigger) -> Dictionary`, `func put(speaker, trigger, line: String, voice: String, rev: int) -> void`, `func take(speaker, trigger) -> Dictionary`, `func drop_stale(cast: Dictionary) -> int`, `func save() -> bool`, `func load_from_disk() -> void`, `static func names_anyone(line: String, names: Array) -> bool`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## The ready pool's data: one line per speaker + trigger, persisted, dropped when its voice is recast, and never one that names anybody.

const PATH := "user://test_voice_pool_store/pool.json"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_put_take_empties_the_slot() -> void:
	var s := VoicePoolStore.new(PATH)
	s.put("bard", "turn_start", "Tempo up.", "bard.wav", 1)
	assert_true(s.has_line("bard", "turn_start"))
	assert_eq(s.take("bard", "turn_start")["line"], "Tempo up.")
	assert_false(s.has_line("bard", "turn_start"), "a taken line stayed in its slot, so it would play twice")
	assert_eq(s.take("bard", "turn_start"), {}, "an empty slot must answer {}")


func test_the_pool_survives_a_restart() -> void:
	var s := VoicePoolStore.new(PATH)
	s.put("mage", "victory", "As calculated.", "mage.wav", 2)
	assert_true(s.save(), "CONTROL: the pool saved")
	var again := VoicePoolStore.new(PATH)
	again.load_from_disk()
	assert_eq(again.peek("mage", "victory").get("line", ""), "As calculated.", "a new session started cold")


func test_a_recast_voice_drops_its_lines() -> void:
	var s := VoicePoolStore.new(PATH)
	s.put("bard", "turn_start", "Tempo up.", "bard.wav", 1)
	s.put("mage", "turn_start", "Hm.", "mage.wav", 1)
	var dropped := s.drop_stale({"bard": {"voice": "bard.wav", "rev": 2}, "mage": {"voice": "mage.wav", "rev": 1}})
	assert_eq(dropped, 1)
	assert_false(s.has_line("bard", "turn_start"), "a line rendered in the old bard voice survived the recast")
	assert_true(s.has_line("mage", "turn_start"), "CONTROL: an unchanged voice keeps its line")


func test_a_line_naming_anyone_is_caught() -> void:
	var names := ["cleric", "Mira", "Goblin King"]
	assert_true(VoicePoolStore.names_anyone("Cleric, heal me!", names))
	assert_true(VoicePoolStore.names_anyone("Mira's got this.", names))
	assert_true(VoicePoolStore.names_anyone("Not the goblin king again.", names))
	assert_false(VoicePoolStore.names_anyone("Every image lies.", ["mage"]), "a name inside another word is not a name")
	assert_false(VoicePoolStore.names_anyone("Steady now.", names), "CONTROL: a line naming no one passes")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh test_the_voice_pool_store_keeps_true_lines`
Expected: EC 3 (`VoicePoolStore` not found). Then `XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import --quit` after creating the file (new `class_name`).

- [ ] **Step 3: Implement `src/llm/VoicePoolStore.gd`**

```gdscript
class_name VoicePoolStore
extends RefCounted

## One ready line per speaker + trigger. Text and voice here; audio lives in VoiceCache under the same voice/rev/text key.

const VERSION := 1
const DEFAULT_PATH := "user://voice_cache/pool.json"

var path: String
var slots: Dictionary = {}


func _init(p: String = DEFAULT_PATH) -> void:
	path = p


static func slot_key(speaker: String, trigger: String) -> String:
	return "%s|%s" % [speaker, trigger]


func has_line(speaker: String, trigger: String) -> bool:
	return slots.has(slot_key(speaker, trigger))


func peek(speaker: String, trigger: String) -> Dictionary:
	return (slots.get(slot_key(speaker, trigger), {}) as Dictionary).duplicate()


func put(speaker: String, trigger: String, line: String, voice: String, rev: int) -> void:
	slots[slot_key(speaker, trigger)] = {"line": line, "voice": voice, "rev": rev}


func take(speaker: String, trigger: String) -> Dictionary:
	var k := slot_key(speaker, trigger)
	var slot: Dictionary = (slots.get(k, {}) as Dictionary).duplicate()
	slots.erase(k)
	return slot


## A slot whose voice was recast or uncast holds audio in a voice the speaker no longer has.
func drop_stale(cast: Dictionary) -> int:
	var dropped := 0
	for k in slots.keys():
		var speaker := str(k).split("|")[0]
		var v: Dictionary = cast.get(speaker, {})
		var slot: Dictionary = slots[k]
		if v.is_empty() or str(v.get("voice", "")) != str(slot.get("voice", "")) or int(v.get("rev", -1)) != int(slot.get("rev", -2)):
			slots.erase(k)
			dropped += 1
	return dropped


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": VERSION, "slots": slots}))
	f.close()
	return true


func load_from_disk() -> void:
	slots = {}
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary and int(d.get("version", 0)) == VERSION and d.get("slots") is Dictionary:
		for k in d["slots"]:
			var slot = d["slots"][k]
			if slot is Dictionary and str(slot.get("line", "")) != "":
				slots[str(k)] = {"line": str(slot["line"]), "voice": str(slot.get("voice", "")), "rev": int(slot.get("rev", 0))}


## Whole-word, case-insensitive. A pooled line was written before its battle, so it may name no one in it.
static func names_anyone(line: String, names: Array) -> bool:
	var hay := " %s " % line.to_lower()
	for n in names:
		var name := str(n).strip_edges().to_lower()
		if name == "":
			continue
		var re := RegEx.new()
		re.compile("(^|[^a-z0-9])" + _escape(name) + "($|[^a-z0-9])")
		if re.search(hay) != null:
			return true
	return false


static func _escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if ".^$*+?()[]{}|\\".contains(c) else c
	return out
```

- [ ] **Step 4: Run it**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh test_the_voice_pool_store_keeps_true_lines` → 4/4.
Mutations: `take` without `slots.erase` → arm 1 red; `drop_stale` comparing voice only → arm 3 red; `names_anyone` with plain `contains` → the "image" arm red. Restore each.

- [ ] **Step 5: Commit**

```bash
git add src/llm/VoicePoolStore.gd test/unit/test_the_voice_pool_store_keeps_true_lines.gd
git commit -m "feat(voice): the ready pool's data — one true line per speaker and trigger"
```

---

### Task 3: Idle signals, the moment check, the pooled-line prompt

**Files:**
- Modify: `src/llm/LLMService.gd`, `src/llm/VoiceService.gd`, `src/llm/PartyPersonas.gd`, `src/llm/DialoguePrompts.gd`
- Test: `test/unit/test_the_pool_reads_idle_and_moments.gd`

**Interfaces:**
- Produces: `LLMService.is_idle() -> bool`; `VoiceService.is_busy() -> bool`; `PartyPersonas.has_moment_line(job_id: String, event_kind: String, ctx: PartyCombatLineContext) -> bool`; `DialoguePrompts.build_pooled_party_line(persona: String, signature_phrases: Array, speaker_job: String, trigger: String, avoid: Array = []) -> String`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## The pool fills only when nothing else is talking to the GPU, and yields to a line written for this exact moment.

func test_llm_idle_reads_the_queue() -> void:
	var saved_id: String = LLMService._inflight_id
	LLMService._inflight_id = ""
	var idle := LLMService.is_idle() == LLMService._queue.is_empty()
	LLMService._inflight_id = "busy"
	var busy := not LLMService.is_idle()
	LLMService._inflight_id = saved_id
	assert_true(idle, "with nothing in flight the LLM reads idle exactly when its queue is empty")
	assert_true(busy, "an in-flight request read as idle")


func test_voice_busy_reads_pending_synthesis() -> void:
	var saved: Dictionary = VoiceService._pending.duplicate()
	VoiceService._pending = {}
	assert_false(VoiceService.is_busy())
	VoiceService._pending = {"tts_1": {}}
	assert_true(VoiceService.is_busy(), "a synthesis in flight read as idle")
	VoiceService._pending = saved


func test_the_pooled_prompt_forbids_names_and_states() -> void:
	var p := DialoguePrompts.build_pooled_party_line("A wry bard.", ["Encore!"], "bard", "turn_start", ["Tempo up."])
	for must in ["turn_start", "Do NOT name", "Tempo up."]:
		assert_string_contains(p, must)
```

Add a moment arm modelled on the existing 2a tests (`command grep -rl "eligible_trigger_entries" test/unit`): with a PartyPersonas entry whose list holds one `{"line": ..., "when": "ally_down"}` and a context where an ally is down, `has_moment_line` is true; with nobody down it is false.

- [ ] **Step 2: Run it to verify it fails** → missing methods, EC 3.

- [ ] **Step 3: Implement**

`LLMService.gd`:

```gdscript
## True when nothing is in flight or queued: the voice pool's cue that the GPU is free.
func is_idle() -> bool:
	return _inflight_id == "" and _queue.is_empty()
```

`VoiceService.gd`:

```gdscript
func is_busy() -> bool:
	return not _pending.is_empty()
```

`PartyPersonas.gd`, beside `eligible_trigger_entries`:

```gdscript
## A line written for a MOMENT that holds now; it outranks the pool (spec 2a.1 step 2).
func has_moment_line(job_id: String, event_kind: String, ctx: PartyCombatLineContext) -> bool:
	if ctx == null:
		return false
	return get_trigger_entries(job_id, event_kind).any(func(e): return VoiceLineTags.is_eligible(e["tags"], ctx) \
		and (e["tags"] as Array).any(func(t): return VoiceLineTags.is_moment_tag(str(t))))
```

`DialoguePrompts.gd`, after `build_party_line`:

```gdscript
## A line for the pool: written before its battle, so it must be true in any battle it plays in.
static func build_pooled_party_line(persona: String, signature_phrases: Array, speaker_job: String, trigger: String, avoid: Array = []) -> String:
	var p := "You voice the party's %s in the meta-aware JRPG 'Cowardly Irregular'.\n" % speaker_job
	p += "Persona: %s\n" % persona
	if not signature_phrases.is_empty():
		p += "Signature phrases (flavour, do not repeat verbatim): %s\n" % ", ".join(signature_phrases.map(func(x): return str(x)))
	p += "Write ONE short spoken line (under 90 characters) for the moment: %s.\n" % trigger
	p += "Do NOT name anyone: no party member, no job, no enemy, no monster. Do NOT state who is alive, down, hurt or winning.\n"
	p += "It must stay true in any battle, so react with attitude, not facts.\n"
	if not avoid.is_empty():
		p += "Do not repeat these: %s\n" % " | ".join(avoid.map(func(x): return str(x)))
	p += "Reply as JSON: {\"line\": \"...\", \"mood\": \"neutral\"}"
	return p
```

- [ ] **Step 4: Run it** → all arms green. Mutation: `is_idle` returning `_queue.is_empty()` alone → the busy arm red.

- [ ] **Step 5: Commit**

```bash
git add src/llm/LLMService.gd src/llm/VoiceService.gd src/llm/PartyPersonas.gd src/llm/DialoguePrompts.gd test/unit/test_the_pool_reads_idle_and_moments.gd
git commit -m "feat(voice): the pool's idle signals, moment check and pooled-line prompt"
```

---

### Task 4: The VoicePool autoload — fill one slot at a time

**Files:**
- Create: `src/llm/VoicePool.gd`
- Modify: `project.godot` (autoload `VoicePool="*res://src/llm/VoicePool.gd"`, after `VoiceService`)
- Test: `test/unit/test_the_voice_pool_fills_one_true_line_at_a_time.gd`

**Interfaces:**
- Consumes: Task 2 (`VoicePoolStore`), Task 3 (`is_idle`, `is_busy`, `build_pooled_party_line`), piece 1 (`VoiceService.synthesize/get_cached/voice_for/is_live_ready`, `LLMService.complete_json/is_available`, `DialoguePrompts.SCHEMA_PARTY_LINE/FALLBACK_PARTY_LINE/validate_party_line`).
- Produces: `VoicePool.TRIGGER_ORDER: Array`, `VoicePool.store: VoicePoolStore`, `VoicePool.discarded: int`, `func is_enabled() -> bool`, `func can_fill() -> bool`, `func next_empty_slot() -> Array` (`[speaker, trigger]` or `[]`), `func fill_slot(speaker: String, trigger: String) -> bool` (async), `func take_line(speaker: String, trigger: String) -> Dictionary` (`{"line", "token"}` or `{}`), `func claim_stream(token: String) -> AudioStream`, `func forbidden_names() -> Array[String]`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## The ready pool writes, checks, synthesizes and stores one line at a time, only when the GPU is free, and never one that names anybody.

const Replay := preload("res://tools/replay_tts_backend.gd")
const DIR := "user://test_voice_pool_cache"

class JsonModel extends LLMBackend:
	var reply: String = "{\"line\": \"Steady hands, loud heart.\", \"mood\": \"neutral\"}"
	var submitted: int = 0
	func backend_id() -> String: return "json_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		var r := reply
		(func(): request_finished.emit(id, true, r, "")).call_deferred()

var _model: JsonModel
var _replay
var _saved := {}


func before_each() -> void:
	_saved = {
		"cast": VoiceService._cast.duplicate(true), "cache": VoiceService.cache, "web": VoiceService.is_web,
		"store": VoicePool.store, "tts": GameState.tts_live_enabled, "pld": GameState.party_llm_dialogue_enabled,
		"party": GameState.player_party.duplicate(true), "backends": LLMService._backends.duplicate(),
		"active": LLMService._active_backend, "llm_on": LLMService.llm_enabled,
	}
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {"bard": {"voice": "bard.wav", "rev": 1}}
	_replay = Replay.new()
	_replay.next_wav = WavFixture.tone(0.3, 8000)
	VoiceService.install_backend(_replay)
	VoicePool.store = VoicePoolStore.new(DIR + "/pool.json")
	VoicePool.discarded = 0
	GameState.tts_live_enabled = true
	GameState.party_llm_dialogue_enabled = true
	GameState.player_party.assign([{"name": "Lyra", "job_id": "bard"}, {"name": "Brom", "job_id": "fighter"}])
	_model = JsonModel.new()
	LLMService.add_child(_model)
	LLMService._backends.clear()
	LLMService._backends.append(_model)
	_model.request_finished.connect(LLMService._on_backend_finished)
	LLMService._active_backend = _model
	LLMService.llm_enabled = true


func after_each() -> void:
	LLMService.cancel_all("voice pool test teardown")
	_model.request_finished.disconnect(LLMService._on_backend_finished)
	LLMService.remove_child(_model)
	_model.free()
	LLMService._backends.assign(_saved["backends"])
	LLMService._active_backend = _saved["active"]
	LLMService.llm_enabled = _saved["llm_on"]
	VoiceService._cast = _saved["cast"]
	VoiceService.cache = _saved["cache"]
	VoiceService.is_web = _saved["web"]
	VoiceService.apply_config()
	VoicePool.store = _saved["store"]
	GameState.tts_live_enabled = _saved["tts"]
	GameState.party_llm_dialogue_enabled = _saved["pld"]
	GameState.player_party.assign(_saved["party"])


func test_the_most_frequent_trigger_fills_first_for_a_cast_party_member() -> void:
	assert_eq(VoicePool.next_empty_slot(), ["bard", "turn_start"],
		"the pool must fill the bard's turn_start first: the fighter is not cast and victory fires once a battle")


func test_a_slot_fills_and_is_redeemed_once() -> void:
	assert_true(await VoicePool.fill_slot("bard", "turn_start"), "CONTROL: the fill succeeded")
	assert_true(VoicePool.store.has_line("bard", "turn_start"), "the filled line was not stored")
	var got := VoicePool.take_line("bard", "turn_start")
	assert_eq(got.get("line", ""), "Steady hands, loud heart.")
	var stream := VoicePool.claim_stream(str(got.get("token", "")))
	assert_not_null(stream, "the token did not redeem the synthesized audio")
	assert_null(VoicePool.claim_stream(str(got.get("token", ""))), "a token redeemed twice")
	assert_false(VoicePool.store.has_line("bard", "turn_start"), "a used line stayed ready, so it would play again")


func test_a_line_naming_a_party_member_is_never_synthesized() -> void:
	_model.reply = "{\"line\": \"Brom, hold the line!\", \"mood\": \"neutral\"}"
	assert_false(await VoicePool.fill_slot("bard", "turn_start"), "a line naming an ally was pooled")
	assert_eq(VoicePool.discarded, 1)
	assert_eq(_replay.requests.size(), 0, "the discarded line was sent to the TTS server anyway")


func test_nothing_fills_while_the_llm_is_busy() -> void:
	LLMService._inflight_id = "someone_else"
	var can := VoicePool.can_fill()
	LLMService._inflight_id = ""
	assert_false(can, "the pool would fill while the LLM is busy, a burst on a shared GPU")


func test_the_pool_is_off_on_web_and_when_either_toggle_is_off() -> void:
	GameState.party_llm_dialogue_enabled = false
	assert_false(VoicePool.is_enabled(), "LLM party dialogue off, yet the pool would play LLM-written lines")
	GameState.party_llm_dialogue_enabled = true
	VoiceService.is_web = true
	assert_false(VoicePool.is_enabled(), "the web build would use the pool")
```

- [ ] **Step 2: Run it to verify it fails** → EC 3 (no `VoicePool` autoload).

- [ ] **Step 3: Implement `src/llm/VoicePool.gd` and register it**

```gdscript
extends Node

## The ready pool (spec 2b.2): one LLM-written, synthesized line per speaker + trigger, filled one at a time while nothing else uses the GPU.

const TRIGGER_ORDER := ["turn_start", "big_hit_taken", "low_hp", "used_signature_ability", "victory"]
const SYNTH_TIMEOUT_SEC := 20.0
const FAIL_COOLDOWN_MSEC := 5000
const STASH_CAP := 8

var store: VoicePoolStore
var discarded: int = 0
var _filling := false
var _retry_after_msec := 0
var _stash: Dictionary = {}
var _stash_order: Array[String] = []
var _next_token := 0
var _recent: Dictionary = {}


func _ready() -> void:
	store = VoicePoolStore.new()
	store.load_from_disk()
	var vs := get_node_or_null("/root/VoiceService")
	if vs != null:
		store.drop_stale(vs._cast)


func _process(_delta: float) -> void:
	if can_fill():
		var slot := next_empty_slot()
		if not slot.is_empty():
			fill_slot(slot[0], slot[1])


## The player opted into both LLM party lines and live voice, on desktop.
func is_enabled() -> bool:
	var vs := get_node_or_null("/root/VoiceService")
	var gs := get_node_or_null("/root/GameState")
	if vs == null or gs == null or vs.is_web:
		return false
	return bool(gs.get("tts_live_enabled")) and bool(gs.get("party_llm_dialogue_enabled"))


func can_fill() -> bool:
	if _filling or Time.get_ticks_msec() < _retry_after_msec or not is_enabled():
		return false
	var vs := get_node_or_null("/root/VoiceService")
	var llm := get_node_or_null("/root/LLMService")
	if llm == null or not llm.is_available() or not llm.is_idle():
		return false
	return vs.is_live_ready() and not vs.is_busy()


func _speakers() -> Array[String]:
	var vs := get_node_or_null("/root/VoiceService")
	var gs := get_node_or_null("/root/GameState")
	var out: Array[String] = []
	if vs == null or gs == null:
		return out
	for m in gs.player_party:
		var job := str((m as Dictionary).get("job_id", ""))
		if job != "" and not vs.voice_for(job).is_empty() and not out.has(job):
			out.append(job)
	return out


func next_empty_slot() -> Array:
	for trigger in TRIGGER_ORDER:
		for speaker in _speakers():
			if not store.has_line(speaker, trigger):
				return [speaker, trigger]
	return []


func forbidden_names() -> Array[String]:
	var out: Array[String] = []
	var js := get_node_or_null("/root/JobSystem")
	if js != null and "jobs" in js:
		for j in js.jobs.keys():
			out.append(str(j).replace("_", " "))
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		for m in gs.player_party:
			out.append(str((m as Dictionary).get("name", "")))
	var es := get_node_or_null("/root/EncounterSystem")
	if es != null and "monster_database" in es:
		for id in es.monster_database:
			out.append(str(id).replace("_", " "))
			out.append(str((es.monster_database[id] as Dictionary).get("name", "")))
	return out


func fill_slot(speaker: String, trigger: String) -> bool:
	_filling = true
	var ok := await _fill(speaker, trigger)
	_filling = false
	if not ok:
		_retry_after_msec = Time.get_ticks_msec() + FAIL_COOLDOWN_MSEC
	return ok


func _fill(speaker: String, trigger: String) -> bool:
	var pp := get_node_or_null("/root/PartyPersonas")
	var llm := get_node_or_null("/root/LLMService")
	var vs := get_node_or_null("/root/VoiceService")
	if pp == null or llm == null or vs == null:
		return false
	var key := VoicePoolStore.slot_key(speaker, trigger)
	var prompt := DialoguePrompts.build_pooled_party_line(str(pp.get_persona(speaker)), pp.get_signature_phrases(speaker), speaker, trigger, _recent.get(key, []))
	var raw: Variant = await llm.complete_json(prompt, DialoguePrompts.SCHEMA_PARTY_LINE, DialoguePrompts.FALLBACK_PARTY_LINE, {"cache": false})
	var line := str(DialoguePrompts.validate_party_line(raw).get("line", ""))
	if line == "":
		return false
	if VoicePoolStore.names_anyone(line, forbidden_names()):
		discarded += 1
		return false
	var stream: AudioStream = await vs.synthesize(speaker, line, SYNTH_TIMEOUT_SEC)
	if stream == null:
		return false
	var v: Dictionary = vs.voice_for(speaker)
	store.put(speaker, trigger, line, str(v.get("voice", "")), int(v.get("rev", 0)))
	store.save()
	var recent: Array = _recent.get(key, [])
	recent.append(line)
	_recent[key] = recent.slice(-5)
	return true


## A ready line and a one-shot token for its audio. {} when the pool has nothing playable.
func take_line(speaker: String, trigger: String) -> Dictionary:
	if not is_enabled() or not store.has_line(speaker, trigger):
		return {}
	var slot := store.take(speaker, trigger)
	store.save()
	var vs := get_node_or_null("/root/VoiceService")
	var stream: AudioStream = vs.get_cached(speaker, str(slot["line"])) if vs != null else null
	if stream == null:
		return {}
	_next_token += 1
	var token := "pool:%d" % _next_token
	_stash[token] = stream
	_stash_order.append(token)
	while _stash_order.size() > STASH_CAP:
		_stash.erase(_stash_order.pop_front())
	return {"line": str(slot["line"]), "token": token}


func claim_stream(token: String) -> AudioStream:
	var s: AudioStream = _stash.get(token, null)
	_stash.erase(token)
	_stash_order.erase(token)
	return s
```

`project.godot` `[autoload]`: add `VoicePool="*res://src/llm/VoicePool.gd"` on the line after `VoiceService=`. Then import.

- [ ] **Step 4: Run it**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh test_the_voice_pool_fills_one_true_line_at_a_time` → 5/5.
Mutations, each must red its arm: drop the `names_anyone` check (discard arm); `next_empty_slot` iterating speakers before triggers is fine but dropping the `voice_for` filter reds the order arm; `can_fill` without `is_idle()` reds the busy arm; `take_line` without `store.take` reds the redeem arm.

- [ ] **Step 5: Commit**

```bash
git add src/llm/VoicePool.gd project.godot test/unit/test_the_voice_pool_fills_one_true_line_at_a_time.gd
git commit -m "feat(voice): the ready pool fills one true, synthesized line at a time (piece 2b.2)"
```

---

### Task 5: Party lines play pooled lines with their own voice (picker step 3)

**Files:**
- Modify: `src/battle/BattleManager.gd` (`_run_party_line_async`)
- Modify: `src/battle/BattleScene.gd` (`_on_party_combat_line`)
- Test: `test/unit/test_a_party_line_speaks_from_the_ready_pool.gd`

**Interfaces:**
- Consumes: Task 1 (`_spawn_quip_bubble(..., voice_stream)`), Task 3 (`has_moment_line`), Task 4 (`VoicePool.take_line`, `VoicePool.claim_stream`).
- Produces: `party_combat_line(combatant, line, voice_trigger)` where a pooled line's `voice_trigger` is a `pool:<n>` token.

- [ ] **Step 1: Write the failing test**

Reuse the fixture shapes of `test_a_line_asked_for_in_battle_never_lands_after_it.gd` (a `Combatant` with `job = {"id": "bard"}` in `BattleManager.player_party`, `current_state = PLAYER_SELECTING`, `party_combat_line` captured) and Task 4's pool fixture (cast `bard`, replay backend, isolated cache and store). Plant a ready line with `VoicePool.store.put("bard", "turn_start", "From the pool.", "bard.wav", 1)` plus `VoiceService.cache.write(VoiceCache.key_for("bard.wav", 1, "From the pool."), WavFixture.tone(0.3, 8000))`.

```gdscript
func test_a_ready_pooled_line_is_spoken_with_its_token() -> void:
	await _ask("turn_start")
	assert_eq(_heard, ["From the pool."], "the ready pooled line was not the one spoken")
	assert_true(_keys[0].begins_with("pool:"), "the pooled line lost its audio token on the way to the bubble")
	assert_false(VoicePool.store.has_line("bard", "turn_start"), "the spoken line stayed in the pool")


func test_a_moment_line_outranks_the_pool() -> void:
	_plant_moment_line("bard", "turn_start", "ally_down", "Get UP!")
	_down_an_ally()
	await _ask("turn_start")
	assert_eq(_heard, ["Get UP!"], "the pool spoke over a line written for this moment")
	assert_true(VoicePool.store.has_line("bard", "turn_start"), "CONTROL: the pooled line was left for later")


func test_with_party_llm_dialogue_off_the_pool_is_silent() -> void:
	GameState.party_llm_dialogue_enabled = false
	await _ask("turn_start")
	assert_ne(_heard, ["From the pool."], "an LLM-written pooled line played with LLM party dialogue off")


func test_the_scene_hands_the_bubble_the_pooled_audio() -> void:
	var got := VoicePool.take_line("bard", "turn_start")
	var scene = ProbeScene.new()
	scene._bubble_sprite_for_test = AnimatedSprite2D.new()
	scene._on_party_combat_line(_rogue_as("bard"), str(got["line"]), str(got["token"]))
	assert_not_null(scene.voice_stream, "the bubble got no stream for a pooled line")
	assert_eq(scene.audio_key, "", "a pooled line also asked for a shipped clip key that does not exist")
	scene.free()
```

`ProbeScene` extends `res://src/battle/BattleScene.gd`, overrides `_spawn_quip_bubble(sprite: Node2D, speaker_name: String, line: String, border_color: Color = Color(1.0, 0.85, 0.2), hold_time: float = 1.5, audio_key: String = "", voice_stream: AudioStream = null) -> void` to record `audio_key` / `voice_stream`, and overrides `_get_combatant_sprite` to return `_bubble_sprite_for_test` (match the parent signatures exactly; read them with `command grep -n "^func _get_combatant_sprite" src/battle/BattleScene.gd`). Write `_plant_moment_line` / `_down_an_ally` against `PartyPersonas._data` and `BattleManager.player_party`, restoring both in `after_each`.

- [ ] **Step 2: Run it to verify it fails** → the pooled-line arm reds (the shipped line plays), the scene arm reds (no stream).

- [ ] **Step 3: Implement**

`BattleManager._run_party_line_async`, immediately after the `if not _party_line_wants_llm(llm_dialogue_on, voice_test):` block returns:

```gdscript
	## Spec 2a.1 step 3: a moment line outranks the pool; otherwise a ready pooled line speaks with its own synthesized audio.
	var vp = get_node_or_null("/root/VoicePool")
	if vp != null and not (pp != null and pp.has_method("has_moment_line") and pp.has_moment_line(job_id, event_kind, ctx)):
		var pooled: Dictionary = vp.take_line(job_id, event_kind)
		if not pooled.is_empty():
			_emit_party_line(combatant, str(pooled["line"]), str(pooled["token"]))
			return
```

`BattleScene._on_party_combat_line`:

```gdscript
		var audio_key: String = ""
		var voice_stream: AudioStream = null
		if voice_trigger.begins_with("pool:"):
			var vp = get_node_or_null("/root/VoicePool")
			if vp != null:
				voice_stream = vp.claim_stream(voice_trigger)
		elif voice_trigger != "" and combatant.job is Dictionary:
			var job_id: String = str(combatant.job.get("id", ""))
			if job_id != "":
				audio_key = "voice_%s_%s" % [job_id, voice_trigger]
		_spawn_quip_bubble(sprite, combatant.combatant_name, line, _get_job_quip_color(combatant), 2.0, audio_key, voice_stream)
```

- [ ] **Step 4: Run it and the neighbours**

Run the new file → 4/4. Mutations: drop the `has_moment_line` guard (moment arm red); emit the pooled line with `event_kind` instead of the token (token arm red); BattleScene building `audio_key` for a pool token (scene arm red).
Neighbours: `command grep -rlE "party_combat_line|_run_party_line_async|_on_party_combat_line|VoicePool|pick_trigger_voice" test/unit` plus the directory-scoped guards (`test_autogrind_headless_drops`, `test_freed_guard_ordering_regression`) → all green.

- [ ] **Step 5: Commit**

```bash
git add src/battle/BattleManager.gd src/battle/BattleScene.gd test/unit/test_a_party_line_speaks_from_the_ready_pool.gd
git commit -m "feat(voice): party lines speak from the ready pool, after any moment line (piece 2b)"
```

---

### Task 6: Spec status and hand-off

**Files:**
- Modify: `docs/superpowers/specs/2026-09-24-local-tts-voice-design.md` (Piece 2b: implemented for the party; 2b.3 deferred with the two reasons from Scope)

- [ ] **Step 1:** Edit the spec's Piece 2b heading to record what shipped and what is deferred, citing this plan.
- [ ] **Step 2:** Run every test file this plan created or touched together; all green.
- [ ] **Step 3:** Commit, push the branch, and DM cowir-main "READY: llm/voiced-lines-with-prefetch @ <sha>" with one line on what the player hears, and a note to cowir-sfx and cowir-story that bosses wait on a boss cast and a ruling on which boss pools may take a pooled line.

```bash
git add docs/superpowers/specs/2026-09-24-local-tts-voice-design.md
git commit -m "docs(voice): piece 2b shipped for the party; bosses wait on a cast"
git push -u origin llm/voiced-lines-with-prefetch
```
