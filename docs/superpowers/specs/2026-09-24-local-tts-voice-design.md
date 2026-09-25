# Local TTS voice acting — design

**Date:** 2026-09-24 · **Lane:** cowir-ai (runtime) · **Status:** design, awaiting review

## Goal

Dynamic voice acting for every speaker — party, bosses, NPCs — using a **free, local**
text-to-speech engine. Lines the LLM writes at runtime are voiced live; lines authored in
advance ship prerendered. The game stays fully playable, and behaves exactly as today, when
live voice is off, unavailable, or on web.

## Decisions already made (struktured, 2026-09-24)

| Decision | Ruling |
|---|---|
| Engine | Free local TTS. Chatterbox (MIT) chosen by ear over Kokoro after a listening test. |
| Scope | Everyone: party, bosses, NPCs. Party first. |
| Prerendered lines | Rendered with the **same free engine** at ship time, so a character's shipped and live lines are one voice. |
| How players get live voice | **Opt-in local server, like Ollama.** Everyone else hears shipped prerenders. |
| Web | Desktop gets live voice. Web is unchanged until piece 5. |
| Steam | A first-run setup wizard installs and configures the local AI and voice. |
| ElevenLabs | Existing ElevenLabs voice work is kept, and is **never** used as a cloning reference (their Prohibited Use Policy bars Output as input to ML models). |

## Lane separation

Split by *what is said*, *how it sounds*, and *when and which*.

| Lane | Owns |
|---|---|
| **cowir-story** — what is said | Corpus line text, boss line pools, NPC persona voice, situational tags, tone review of LLM-written lines. |
| **cowir-sfx** — how it sounds | The TTS server (`devnen/Chatterbox-TTS-Server` @ `915ae28` + patch), voice-model tuning (exaggeration/cfg/temperature/seed), rights-clean reference voices, `voice_cast.json` content, ship-time prerender, the launcher the wizard calls. |
| **cowir-ai** — when and which (this spec) | The runtime: TTS client, cache, the voiced-line picker, prefetch, playback wiring, settings, setup wizard, web tier. **Never tunes model parameters.** |

### Contracts between lanes

1. **Line text → clip (story → sfx → ai).** A trigger's `trigger_voices` value is a list
   (supported since `637e5d6b7`). List index `n` is clip `voice_<speaker>_<trigger>_<n>`;
   index 0 keeps the historical key `voice_<speaker>_<trigger>`. **Append-only**: reordering
   shifts every later clip. An element is either a string or `{"line": str, "when": tag|[tags]}`.
   Tags never affect indexing. `test_party_voice_pack_regression` joins text to clip per
   variant and reds on `source_sha` drift, so an edited line cannot play a stale clip.
   **`source_sha` hashes the `line` text, not the JSON element**, so converting a rendered
   string to an object at the same index (adding a tag) does not stale its clip and costs no
   re-render. Every reader of these lists, including the signature guard that today does
   `PackedStringArray(entry)`, accepts both element shapes before cowir-story writes objects.
   **The voice-pack guard violates this today:** its `_variants` does `str(lines[n])`, which
   hashes the whole element, so a string→object conversion would stale every tagged clip
   (found by cowir-sfx). `_variants` extracts `"line"` from a Dictionary **in the same commit
   that introduces the object format** (piece 2a), never after.
2. **Wire protocol (ai → sfx).** OpenAI-compatible `POST /v1/audio/speech` with
   `{"model", "input", "voice", "response_format": "wav"}`; response is WAV bytes.
   `GET /v1/audio/voices` lists server voices. Default server: `http://127.0.0.1:8004`.
3. **Voice cast (sfx → ai).** `data/voice_cast.json`:
   ```json
   {"version": 1, "voices": {"bard": {"voice": "bard.wav", "rev": 3}}}
   ```
   `voice` is the server's voice name. `rev` is bumped by sfx whenever the reference or
   tuning changes; it is part of the cache key, so a recast can never replay stale audio.
4. **Delivery parameters stay server-side.** The client never sends exaggeration, cfg,
   temperature, or seed. Stock devnen applies these as *global* defaults on
   `/v1/audio/speech` (verified in its `server.py`), so every voice would share one delivery.
   **Decided by cowir-sfx (2026-09-24): their patch makes `/v1/audio/speech` look these up
   per voice**, from a per-voice config keyed by voice name. The endpoint stays standard and
   the client is unchanged.
5. **The supported server is the patched one, not stock devnen.** Stock devnen is wrong for
   us on three counts, each verified by cowir-sfx: it hard-clips (`np.clip` before int16),
   it defaults to **chatterbox-turbo**, a different engine from the one struktured approved
   by ear, and it binds `0.0.0.0`. Supported = devnen `915ae28` + the cowir-sfx patch, with
   `repo_id: chatterbox` and `host: 127.0.0.1`. Verified end to end: five theatrical lines
   all peak at exactly −1.00 dBFS (29,195/32,767), none at the rail, 24 kHz.

## Architecture

```
            ┌──────────── cowir-ai (Godot) ─────────────┐        ┌── cowir-sfx ──┐
 LLM line ─▶│ VoiceLinePicker ─▶ VoiceService ─▶ cache ─┼─HTTP──▶│ TTS server    │
 authored ─▶│   (choose / pool)    │   ▲         user://│        │ /v1/audio/... │
            │                      ▼   │ WAV bytes     │        └───────────────┘
            │   BattleSpeechBubble / NPCDialogue        │
            │        └─▶ SoundManager.play_voice_stream │
            └───────────────────────────────────────────┘
```

**Fallback ladder, everywhere:** live synthesized line → shipped prerendered clip → text only.
Every rung is reached by the rung above failing, timing out, or being disabled. No rung may
block gameplay.

---

## Piece 1 — TTS backend, cache, playback, settings

The foundation. After piece 1, Settings has a working **Test Voice** that speaks a sample
line in a chosen speaker's voice through the local server. No dialogue call site changes yet.

### 1.1 `TTSBackend` (`src/llm/TTSBackend.gd`, `class_name TTSBackend extends Node`)

Base class, mirroring `LLMBackend`, so backends are swappable (the web backend in piece 5
slots in here).

```gdscript
signal synthesis_finished(id: String, ok: bool, wav: PackedByteArray, error: String)
func backend_id() -> String
func is_ready() -> bool
func status() -> Dictionary      # see 1.5
func synthesize(id: String, text: String, voice: String) -> void
func cancel(id: String) -> void
func cancel_all() -> void
```

Backends return **WAV bytes**, not a stream, so `VoiceService` caches exactly what it
decodes, once.

Implementations:
- **`HTTPTTSBackend`** — the OpenAI-compatible client. Readiness probe is
  `GET /v1/audio/voices` (timeout 1.5 s, re-probe every 30 s after a failure, same cadence
  as `HTTPBackend`). The probe response also yields the server's voice list, used for 1.5.
  Synthesis request timeout: 8 s client-side.
- **`NullTTSBackend`** — never ready. Used whenever live voice is off, and on web until
  piece 5 replaces the web case with `WebTTSBackend`.
- **`tools/replay_tts_backend.gd`** — returns canned WAV bytes. Test-only, mirroring
  `tools/replay_backend.gd`, so no test needs a server or GPU.

### 1.2 `VoiceService` (new autoload, `src/llm/VoiceService.gd`)

Owns backend selection, `voice_cast.json`, and the cache. Public API:

```gdscript
func is_live_ready() -> bool
func status() -> Dictionary
func voice_for(speaker_id: String) -> Dictionary          # {} when uncast
func get_cached(speaker_id: String, text: String) -> AudioStream   # sync; null if absent
func synthesize(speaker_id: String, text: String, timeout_sec: float) -> AudioStream  # await; null on any failure
```

`get_cached` is synchronous on purpose: `BattleSpeechBubble` must have the audio **before**
it builds its fade tween (the clip length sets the hold), so a battle bubble can only ever
use audio that is already in hand. `synthesize` checks the cache first.

Selection: `HTTPTTSBackend` when `GameState.tts_live_enabled` and not web; otherwise
`NullTTSBackend`. Uncast speakers (no `voice_cast.json` entry) never synthesize.

### 1.3 Decoding

WAV bytes → `AudioStreamWAV.load_from_buffer(bytes)`. Verified in Godot 4.4.1: a 24 kHz
PCM16 mono buffer decodes to `mix_rate=24000, stereo=false, format=16-bit, length=0.5 s`
exactly. No hand-written RIFF parser. Chatterbox outputs 24 kHz; the live path plays it at
that rate with no resampling.

### 1.4 Cache

- Path: `user://voice_cache/<key>.wav`, key = first 32 hex chars of
  `sha256("v1|" + voice + "|" + str(rev) + "|" + text)`.
- Read touches the file's modification time (LRU). Write evicts oldest-first when the
  directory exceeds **200 MB**. The bound is part of the design: an unbounded cache is the
  defect found in `LLMService._cache` on 2026-09-20.
- A bytes blob that fails to decode is deleted, never served.

### 1.5 Status and clipping detection

`VoiceService.status()` returns:

```
{enabled, ready, backend, url, last_latency_ms, last_error,
 clipping_detected: bool, missing_voices: Array[String]}
```

- `missing_voices`: cast voice names absent from the server's `/v1/audio/voices`.
- `clipping_detected`: set when a returned line has **≥ 2 runs of samples pinned at
  ±32767**. The supported server peak-normalises to −1 dBFS (max 29,196), so correct output
  never reaches the ceiling; a single pinned sample on another server may be a clean peak,
  hence 2 runs. In the spike, stock output produced 7–14 runs per theatrical line and 1–4
  per neutral line. The threshold is confirmed against cowir-sfx's patched output (negative
  control) and stock devnen (positive control) before it ships. Detection **does not modify
  audio**; normalising is the server's job, and a second copy client-side could drift.

The wizard (piece 4) and the settings panel both read this one dictionary.

### 1.6 `SoundManager.play_voice_stream(stream: AudioStream) -> float`

Sibling of `play_voice(key)`: the same dedicated `_voice_player`, the same unity pitch (no
jitter, per the 2026-09-18 measurement), the same base dB, and it **returns the length in
seconds**, so the bubble's hold contract is unchanged.

### 1.7 Settings

`GameState` gains, persisted by `SaveSystem.save_settings` and **gated off on web** exactly
like `llm_custom_*`:

| Field | Default |
|---|---|
| `tts_live_enabled` | `false` |
| `tts_server_url` | `"http://127.0.0.1:8004"` |
| `tts_model` | `"chatterbox"` |

A **Configure Live Voice** panel, modelled on `BYOKConfigPanel` (controller-first focus
chain, never instantiable on web): enable toggle, server URL, a speaker picker, **Test
Voice** (synthesizes and plays a sample line), and a status line showing readiness, latency,
missing voices, and a clipping warning that names the supported server. No API key: the
server is local.

### 1.8 Piece 1 tests (all against `ReplayTTSBackend`)

- Decode: valid WAV → correct rate/length; corrupt bytes → null and the cache entry deleted.
- Cache: key includes `rev` (bumping it misses); LRU eviction keeps the directory under the cap.
- Clipping: a synthetic line with 2+ pinned runs → flagged; a −1 dBFS line → not flagged.
- `play_voice_stream` returns the stream's length and uses the voice player.
- Web gating: on web, **no backend ever contacts a server URL**, the URL setting doesn't
  persist, and the panel refuses. Written as that property rather than "the backend is
  `NullTTSBackend`", so piece 5's in-browser backend (which contacts no server) doesn't have
  to break it.
- Settings round-trip through `save_settings` / load.
- Status shape, including `missing_voices` against a replayed voice list.
- Timeout: a backend that never answers → `synthesize` returns null within its timeout.

Load-bearing guards (decode, cache key, clipping, web gating) are mutation-tested.

---

## Piece 2a — Situational eligibility (fixes a shipped defect; no TTS)

**Measured defect (cowir-story, 2026-09-24).** `_maybe_fire_party_line` has no solo or duel
check, and the victory line goes to the freshest alive PC. So a line that names an ally plays
in a **spotlight duel, where the speaker is alone**, or while that ally is KO'd. Example, the
Fighter's solo duel, `low_hp`: *"Cleric. When you're ready. No rush."* In the batch-1 corpus,
**14 lines name an ally (4 of them shipped variant-0 lines)** and **3 claim a party state**
("Nobody fell."). The duels are where a player first meets each character. This happens today
with LLM and voice both off, so 2a ships first and depends on nothing else in this spec.

### 2a.1 The picker (`VoiceLinePicker`)

For a speaker + trigger + `PartyCombatLineContext`:

1. **Eligible lines** = untagged lines + tagged lines whose `when` condition holds now.
   Conditions are evaluated **by code**, never by the LLM, so the LLM can only ever choose
   among lines that are true.
2. **A tagged line is eligible** → it wins over generic lines: written for this moment, it is
   more apt than anything generic, including a live pooled line (2b). Choose among the
   eligible tagged lines by step 4 or 5.
3. **Live voice ready and the pool has a line** (2b) → play the pooled line. It carries its
   own synthesized audio and has no list index.
4. **LLM on** → `LLMService.choose(prompt, eligible_texts, fallback)` (its first production
   caller). `choose` already guarantees the result is one of the options.
5. **LLM off** → random among eligible, no immediate repeat.
6. For steps 4–5 the chosen index `n` maps to clip `voice_<speaker>_<trigger>_<n>`.

**Corpus size (struktured, 2026-09-24): weighted, 145 lines per job, 725 in total**:
`turn_start` 50 · `low_hp` 25 · `big_hit_taken` 25 · `used_signature_ability` 20 ·
`victory` 25, plus situational lines. The largest list (50) is sent to `choose()` whole; at
~38–74 characters per line that is 2–4K characters, within budget without pre-filtering.
Past ~50 options per trigger, eligible lines would be pre-filtered before the LLM sees them.

### 2a.2 Tags

Every tag is a pure predicate over `PartyCombatLineContext`:

| Tag | True when |
|---|---|
| `ally_alive:<job>` | a party member with that `job_id` is present **and** alive (parameterised) |
| `none_down` | no party member has `is_alive == false` |
| `ally_down` | another party member is KO'd |
| `ally_low` | another party member is below 30% HP |
| `last_standing` | the speaker is the only party member alive |
| `enemy_last` | exactly one enemy remains |
| `enemy_nearly_dead` | an enemy is below 20% HP |
| `many_enemies` | three or more enemies |
| `self_status` | the speaker has any status effect |

`ally_alive:<job>` and `none_down` are what cowir-story's 17 waiting lines need (e.g. *"The
singed sleeve first, then the new limp"* → `["ally_alive:mage", "ally_alive:rogue"]`;
*"Nobody fell."* → `none_down`). `boss` and streak tags (`third_hit`) need one new context
field each and are added when first used. `"when"` may be a list (all must hold). An unknown
tag makes its line ineligible **and reds a guard**, so a typo can't silently mute a line.

### 2a.3 Tests

A table test per tag (holds / doesn't); the duel case (a line tagged `ally_alive:cleric` is
never picked in a solo duel); tagged lines win when eligible; an object entry and a string
entry at the same index hash to the same `source_sha`; every list reader accepts both element
shapes; unknown tags red.

---

## Piece 2b — Voiced party and boss lines, with prefetch

### 2b.1 Bubble integration

`BattleSpeechBubble.spawn` gains an optional `voice_stream: AudioStream`. When present,
`_play_voice` calls `play_voice_stream` instead of `play_voice(key)`, **before** `_present`,
preserving today's ordering (the clip length sets the hold, and the fade tween is built from
it). Absent a stream, behaviour is exactly today's.

### 2b.2 Prefetch: the ready pool

Because the bubble needs audio at spawn, live party/boss lines are **written and synthesized
ahead of their moment**:

- Each (speaker, trigger) keeps **one ready line** (text + cached audio).
- On use, a replacement is generated in the background: the LLM writes a line from persona +
  trigger, then `VoiceService.synthesize`.
- **A pooled line must be true in any battle it might be used in.** It was written before the
  battle it plays in, so it may name no enemy, no ally, and no party state. The prompt asks
  for that, and **code enforces it**: a generated line containing any party job id, party
  member name, or enemy name is discarded before synthesis. This is 2a's duel defect again,
  one level over, and the prompt alone isn't trusted to prevent it.
- Idle fill: when no LLM or TTS request is in flight, fill one empty slot. **Never a burst at
  battle start**; the GPU is shared with the local LLM. Empty slots are filled in order of
  how often their trigger fires, so `turn_start` (every party turn) refills before `victory`
  (once per battle).
- The pool persists to `user://voice_cache/pool.json`, so a new session starts warm.
- Empty slot at trigger time → steps 4–5 of 2a.1 (shipped clip). A battle never waits on
  synthesis.

Trade-off, accepted: a pooled line reacts to the trigger and persona, not to the exact hit,
because it was written before that hit. Situational tagged lines (2a) cover the moments
where specificity matters, and they outrank the pool.

### 2b.3 Bosses

Boss line pools (`BossDialogue`: phase transitions, automation lines, steal, taunts,
victory/defeat) follow the same list and tag contract, keyed `voice_<boss_id>_<pool>_<n>`,
and the same picker and pool. Two render surfaces, both verified in code:

- **Barks and taunts** → `BattleManager._emit_boss_bark` → `BattleSpeechBubble.spawn`
  (`BattleScene.gd:5731`). Same bubble as the party, so 2b.1 applies unchanged.
- **Victory/defeat gloats** → the `boss_gloat_line(text, is_victory)` signal. These are
  **non-blocking by design**: the shipped line emits at once, and an LLM re-narration
  replaces it if it arrives. **A late re-narration replaces the text only, never the voice**;
  otherwise the boss speaks twice. The voice is chosen once, at the first emit.

---

## Piece 3 — Live NPC voice

NPC replies answer the player's choice, so they can't be pre-rendered; this is where live
voice is always on the critical path.

- In `DynamicConversation`, `_fetch_npc_opening`, `_fetch_npc_reply` and
  `_fetch_npc_sign_off` already show the "thinking" dots. After the text arrives and
  **before** `_show_npc_line`, if live voice is ready: `await VoiceService.synthesize(npc_id,
  line, 5.0)` while the dots stay up, then show the text and play the audio together.
- Timeout or failure → the text shows alone, exactly as today.
- Scripted NPC lines (persona `fallbacks[]`) follow the list contract and play shipped clips.
- Advancing the dialogue stops the voice line.
- **Voice mode per speaker:** `VoiceService.voice_mode(speaker_id) -> "live" | "shipped" | "off"`.
  Default: `live` if ready and cast, else `shipped`. `voice_cast.json` may override per
  speaker. This is the hook for "NPCs go fully dynamic after some point in the game"; the
  progression rule itself is struktured's call and is not built here.

---

## Piece 4 — First-run setup wizard (Steam)

Guides a player from nothing to working local AI and voice, and can be re-opened from Settings.

1. **Detect:** GPU and VRAM via the launcher's `--check` (Godot cannot read VRAM).
2. **Recommend a tier:**

   | Tier | Needs | Gets |
   |---|---|---|
   | Full local | NVIDIA GPU | LLM dialogue + Chatterbox voice |
   | Light local | CPU | LLM dialogue + Kokoro (stock voices) |
   | Cloud key | nothing | the BYOK presets |
   | Off | nothing | shipped lines; fully playable |

3. **Install and launch** through cowir-sfx's launcher (non-interactive, meaningful exit
   codes, `--check` returning JSON). The launcher installs the **supported** server
   (contract 5): the patch, `repo_id: chatterbox`, `host: 127.0.0.1`. "Install devnen" alone
   gets none of the three right. Ollama is detected by its readiness probe; if absent, the
   wizard links to its installer rather than silently installing system software.
4. **Test** via `VoiceService.status()` and the LLM backend's readiness, then hand back.

Shown once on first run (a `GameState` flag). All four tiers leave the game playable.

### 4.1 Security: the local server must not be reachable from the player's browser

devnen's admin endpoints (`/save_settings`, `/restart_server`, `/upload_reference`,
`/upload_predefined_voice`) are **unauthenticated**. Binding `127.0.0.1` keeps the LAN out
but **not a web page open in the player's browser**, which can send requests to `localhost`
(and, via DNS rebinding, can even defeat a naive host check). A malicious site could
reconfigure the server, upload files, or spend the player's GPU. The server the wizard
installs must therefore:

- **Expose only the two endpoints the game uses**, `POST /v1/audio/speech` and
  `GET /v1/audio/voices`; everything else is disabled.
- **Reject any request carrying an `Origin` header.** Browsers attach one to cross-origin
  requests; Godot's `HTTPRequest` does not, so the game is unaffected. Ollama does the same
  by default (its `OLLAMA_ORIGINS` allowlist).
- **Reject any `Host` header other than `127.0.0.1:<port>` or `localhost:<port>`**, which
  defeats DNS rebinding.

This is a requirement on the installed server (cowir-sfx's patch and launcher); piece 4's
tests verify it against the running server. The web tier (piece 5) never talks to a local
server, so the `Origin` rule costs it nothing.

---

## Piece 5 — Web tier (kokoro-js in the browser)

- `WebTTSBackend` calls **kokoro-js** (Kokoro-82M, ~86 MB quantized, WASM/WebGPU) through
  Godot's `JavaScriptBridge`. PCM from the browser is packed into WAV bytes and goes through
  the same decode and cache path.
- The model is **fetched at runtime, not packed into the `.pck`**, so it neither counts
  toward itch's 200 MB file limit nor inflates the uncached `.pck`; the browser caches it.
- **First step of the piece-5 plan: verify cross-origin isolation.** If our web export runs
  threaded (COOP/COEP), a cross-origin model fetch needs CORP headers; if Hugging Face
  doesn't send them, the model is self-hosted on the same origin as a separate file (86 MB is
  under itch's per-file limit).
- Kokoro cannot clone, so web characters use **stock voices** cast by cowir-sfx
  (`voice_cast.json` gains a `web_voice` field per speaker).
- Opt-in: the first enable downloads the model. No keys, so "web never holds keys" holds.

---

## Dependencies on other lanes

| Piece | Needs | From |
|---|---|---|
| 2a | Nothing. cowir-story tags its 17 waiting lines once 2a lands | — |
| 1 | Nothing to build; a live Test Voice needs the patched server | cowir-sfx |
| 2b | Corpus lists (batch 1: lists of 10); voice cast + clips | cowir-story, cowir-sfx |
| 3 | NPC voices cast | cowir-sfx |
| 4 | Launcher with `--check` / install / start | cowir-sfx |
| 5 | Web voice casting | cowir-sfx |

## Out of scope

Voice-model tuning, reference sourcing and prerendering (cowir-sfx); writing line text
(cowir-story); speech-to-text; cloud TTS keys (ElevenLabs/OpenAI TTS); the progression rule
for when NPCs go fully dynamic (hook only).

## Build order

**2a → 1 → 2b → 3 → 4 → 5.** 2a goes first because it repairs a defect in shipped lines
today and depends on nothing else here. Each piece gets its own implementation plan and
lands on its own branch.
