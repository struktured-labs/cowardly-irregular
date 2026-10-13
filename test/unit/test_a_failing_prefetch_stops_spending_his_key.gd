extends GutTest

## The idle voice-pool filler retried a failing fill every 5 seconds, forever, on the player's own
## API key.
##
## `_fill` makes an UNCACHED completion — `{"cache": false}`, so no retry is ever served from the
## cache — and has four failure returns: an unusable line, a line naming a party member
## (`discarded`), a line repeating the pool (`repeated`), and a null synthesis. `fill_slot` answered
## every one of them with a flat `_retry_after_msec = now + FAIL_COOLDOWN_MSEC`, and
## `next_empty_slot()` keeps handing back the same still-empty slot. So:
##
##     a model that cannot produce a usable line  ->  12 uncached round trips a minute, forever
##
## 📌 AND THE COUNTERS THAT WOULD HAVE BEEN THE NATURAL BACK-OFF SIGNAL ARE NOT CONSULTED BY ANY
## CONSUMER. `discarded` and `repeated` are incremented in `_fill`, and no `src/` file reads them —
## measured, and the 11 other `src/` hits for those words are the ENGLISH words in prose comments,
## read rather than counted. ⚠️ They are NOT "read nowhere", which is what this docstring said
## first: `test_the_voice_pool_fills_one_true_line_at_a_time` asserts on both. So they are
## OBSERVABLE but not ACTIONABLE — weaker than the inert-field shape, and corrected here because
## the stronger version was the claim I nearly shipped.
##
## REACH: a small local model is the normal case for this feature, not an edge — Ollama users run 3B
## models, and those are exactly the ones that keep naming party members or repeating themselves. On
## Ollama the cost is GPU; on a paid BYOK endpoint it is money, silently, with nothing on screen.
##
## 🔑 THE ARM THAT MATTERS MOST IS THE OVER-REACH ONE, NAMED BEFORE THE FIX WAS WRITTEN:
## `test_a_success_clears_the_debt`. Backoff that never resets would leave prefetch permanently slow
## after a single transient blip — a worse defect than the one being fixed, and invisible because
## everything still works, just later.

const BED_SPEAKER := "bard"
const TRIGGER := "turn_start"
const DIR := "user://test_pool_backoff_cache"

const Replay := preload("res://tools/replay_tts_backend.gd")


## A model whose reply the pool must reject, so every fill fails for a REAL reason rather than by
## stubbing fill_slot out. `line: ""` takes `_fill`'s first failure return.
class UnusableModel extends LLMBackend:
	var reply: String = "{\"line\": \"\", \"mood\": \"neutral\"}"
	var submitted: int = 0
	func backend_id() -> String: return "unusable_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		var r := reply
		(func(): request_finished.emit(id, true, r, "")).call_deferred()


var _model: UnusableModel
var _replay
var _saved := {}


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func before_each() -> void:
	_wipe()
	_saved = {
		"cast": VoiceService._cast.duplicate(true), "cache": VoiceService.cache,
		"web": VoiceService.is_web, "store": VoicePool.store,
		"tts": GameState.tts_live_enabled, "pld": GameState.party_llm_dialogue_enabled,
		"party": GameState.player_party.duplicate(true),
		"backends": LLMService._backends.duplicate(), "active": LLMService._active_backend,
		"llm_on": LLMService.llm_enabled,
	}
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {BED_SPEAKER: {"voice": "bard.wav", "rev": 1}}
	VoiceService.is_web = false
	_replay = Replay.new()
	_replay.next_wav = WavFixture.tone(0.3, 8000)
	VoiceService.install_backend(_replay)
	VoicePool.store = VoicePoolStore.new(DIR + "/pool.json")
	VoicePool._retry_after_msec = 0
	VoicePool.consecutive_failures = 0
	VoicePool._recent = {}
	VoicePool.discarded = 0
	VoicePool.repeated = 0
	## No idle filling from _process: every arm drives fill_slot itself so the count is the arm's.
	VoicePool.set_process(false)
	GameState.tts_live_enabled = true
	GameState.party_llm_dialogue_enabled = true
	GameState.player_party.assign([{"name": "Lyra", "job_id": BED_SPEAKER}])
	_model = UnusableModel.new()
	LLMService.add_child(_model)
	LLMService._backends.clear()
	LLMService._backends.append(_model)
	_model.request_finished.connect(LLMService._on_backend_finished)
	LLMService._active_backend = _model
	LLMService.llm_enabled = true


func after_each() -> void:
	LLMService.cancel_all("prefetch backoff test teardown")
	_model.request_finished.disconnect(LLMService._on_backend_finished)
	LLMService.remove_child(_model)
	_model.free()
	LLMService._backends.assign(_saved["backends"])
	LLMService._active_backend = _saved["active"]
	LLMService.llm_enabled = bool(_saved["llm_on"])
	VoiceService._cast = _saved["cast"]
	VoiceService.cache = _saved["cache"]
	VoiceService.is_web = bool(_saved["web"])
	VoiceService.apply_config()
	VoicePool.store = _saved["store"]
	VoicePool._retry_after_msec = 0
	VoicePool.consecutive_failures = 0
	VoicePool.discarded = 0
	VoicePool.repeated = 0
	VoicePool.set_process(true)
	GameState.tts_live_enabled = bool(_saved["tts"])
	GameState.party_llm_dialogue_enabled = bool(_saved["pld"])
	GameState.player_party.assign(_saved["party"])
	_wipe()


## One real fill attempt, and the cooldown it set, measured from the clock rather than assumed.
func _attempt() -> int:
	var before: int = Time.get_ticks_msec()
	var ok: bool = await VoicePool.fill_slot(BED_SPEAKER, TRIGGER)
	assert_false(ok, "PREMISE: the fixture's model must make every fill FAIL, or this file tests nothing")
	return VoicePool._retry_after_msec - before


# ── the premise: the fixture creates the hazard ──────────────────────────────────────────────────

func test_the_fixture_really_spends_a_round_trip_per_attempt() -> void:
	## Without this the arms below could pass because nothing ever called the model — the same
	## green as a correct backoff.
	assert_eq(_model.submitted, 0, "PREMISE: no calls before the first attempt")
	await _attempt()
	assert_eq(_model.submitted, 1, "one failed fill must cost exactly one completion")
	await _attempt()
	assert_eq(_model.submitted, 2, "and the next attempt costs another — this is the spend being bounded")


# ── the defect ───────────────────────────────────────────────────────────────────────────────────

func test_repeated_failures_wait_longer_each_time() -> void:
	var first: int = await _attempt()
	var second: int = await _attempt()
	var third: int = await _attempt()
	assert_almost_eq(first, VoicePool.FAIL_COOLDOWN_MSEC, 150,
		"the FIRST failure must still retry promptly — the common case is transient")
	assert_gt(second, first + 100,
		"the second consecutive failure waited the same 5s: a model that cannot produce a line spends 12 uncached completions a minute, forever, on the player's own key")
	assert_gt(third, second + 100, "and the third must wait longer than the second")


func test_the_wait_is_capped_so_prefetch_never_dies_completely() -> void:
	VoicePool.consecutive_failures = 400
	assert_eq(VoicePool.fail_cooldown_msec(), VoicePool.FAIL_BACKOFF_CAP_MSEC,
		"the backoff must saturate, not overflow into a wait no session outlives")
	VoicePool.consecutive_failures = 0
	assert_eq(VoicePool.fail_cooldown_msec(), VoicePool.FAIL_COOLDOWN_MSEC,
		"and with no failures recorded it must read as the base cooldown")


# ── the over-reach arm, named before the fix was written ─────────────────────────────────────────

func test_a_success_clears_the_debt() -> void:
	## ⛔ THE ARM THAT KEEPS THIS A FIX RATHER THAN A NEW DEFECT. Backoff that never resets leaves
	## prefetch permanently slow after one transient blip — and it is invisible, because every line
	## still arrives, just later and later.
	await _attempt()
	await _attempt()
	await _attempt()
	assert_gt(VoicePool.consecutive_failures, 2, "PREMISE: a debt must have accumulated")
	_model.reply = "{\"line\": \"Hold for applause. No? Tough room.\", \"mood\": \"wry\"}"
	var ok: bool = await VoicePool.fill_slot(BED_SPEAKER, TRIGGER)
	assert_true(ok, "PREMISE: a usable line must now succeed, or this arm proves nothing")
	assert_eq(VoicePool.consecutive_failures, 0, "a success must clear the accumulated debt")
	VoicePool.store.take(BED_SPEAKER, TRIGGER)
	_model.reply = "{\"line\": \"\", \"mood\": \"neutral\"}"
	var after: int = await _attempt()
	assert_almost_eq(after, VoicePool.FAIL_COOLDOWN_MSEC, 150,
		"the next failure after a success must be back to the BASE cooldown, not the escalated one")


func test_a_success_sets_no_cooldown_at_all() -> void:
	## CONTROL: without this, "always set a cooldown" would satisfy the arms above.
	_model.reply = "{\"line\": \"Verse two, with feeling!\", \"mood\": \"bright\"}"
	VoicePool._retry_after_msec = 0
	assert_true(await VoicePool.fill_slot(BED_SPEAKER, TRIGGER), "PREMISE: this line must be usable")
	assert_eq(VoicePool._retry_after_msec, 0, "a successful fill must not gate the next one")


# ── floor ────────────────────────────────────────────────────────────────────────────────────────

func test_the_symbols_this_guard_drives_exist() -> void:
	for m in ["fill_slot", "fail_cooldown_msec", "can_fill", "next_empty_slot"]:
		assert_true(VoicePool.has_method(m), "VoicePool.%s" % m)
	assert_true("consecutive_failures" in VoicePool, "VoicePool.consecutive_failures")
	assert_gt(VoicePool.FAIL_BACKOFF_CAP_MSEC, VoicePool.FAIL_COOLDOWN_MSEC,
		"the cap must be above the base cooldown or the backoff is inverted")
