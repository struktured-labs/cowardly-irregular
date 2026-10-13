extends GutTest

## The background voice prefetch held the LLM channel back to back, so the player's own NPC
## dialogue queued behind it.
##
##     VoicePool._process            every frame: if can_fill() -> fill_slot()
##     LLMService._submit_and_wait   _inflight_id != "" -> _queue.append(...)
##     LLMService._process_queue     front of the queue only — no priority, no jump
##
## The pool is polite about STARTING (`can_fill()` checks `llm.is_idle()`) and that is the whole of
## its politeness: once a fill is in flight the player's request is appended behind it and waits a
## full prefetch round trip before its own begins. `_process` re-grabbed the channel the instant it
## freed, so with slots empty — 25 at session start — it was busy essentially continuously.
##
## ⛔ NOT CLAIMED, because I checked: `QUEUE_CAP = 16` with drop-oldest means the player's request
## being EVICTED needs sixteen queued requests. Not a realistic reach. The floor pins QUEUE_CAP == 16
## so that reason cannot go stale silently.
##
## ⚠️ MY FIRST VERSION OF THIS FILE WAS VACUOUS AND THE MUTATION TABLE CAUGHT IT. Its arms set
## `_next_fill_msec` by hand and asserted `can_fill()` was false — but the fixture never enabled the
## pool, so `can_fill()` was false through `is_enabled()` regardless and every negative passed for
## the wrong reason. Three mutants that break the fix (gap never set · can_fill ignores it · gap
## replaces the backoff instead of composing) all SURVIVED. This version uses the sibling guard's
## real fixture, drives `fill_slot` for real, and asserts the premise that `can_fill()` was TRUE
## first — which is the arm the first version was missing.
##
## THE OVER-REACH ARM, NAMED BEFORE THE FIX: `test_the_gap_expires_so_the_pool_fills_again`. A gap
## that latched would leave the pool permanently empty — every line unvoiced, and invisible, because
## the scripted fallback still speaks.

const BED_SPEAKER := "bard"
const TRIGGER := "turn_start"
const DIR := "user://test_pool_gap_cache"

const Replay := preload("res://tools/replay_tts_backend.gd")


## A model whose reply the pool ACCEPTS, so a fill really succeeds and really sets the gap.
class UsableModel extends LLMBackend:
	var reply: String = "{\"line\": \"Hold for applause. No? Tough room.\", \"mood\": \"wry\"}"
	var submitted: int = 0
	func backend_id() -> String: return "usable_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		var r := reply
		(func(): request_finished.emit(id, true, r, "")).call_deferred()


var _model: UsableModel
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
	_model = UsableModel.new()
	LLMService.add_child(_model)
	LLMService._backends.clear()
	LLMService._backends.append(_model)
	_model.request_finished.connect(LLMService._on_backend_finished)
	LLMService._active_backend = _model
	LLMService.llm_enabled = true
	## The gap is AUTOLOAD state: a file that filled before this one leaves 15s on the clock, and this file's premise is that can_fill() is TRUE.
	VoicePool._next_fill_msec = 0


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


	VoicePool._next_fill_msec = 0


# ── the premise this file's negatives rest on ────────────────────────────────────────────────────

func test_the_pool_can_actually_fill_in_this_fixture() -> void:
	## Without this every assert_false(can_fill()) below could pass through is_enabled() — which is
	## exactly how the first version of this file managed to be green against three live mutants.
	assert_true(VoicePool.can_fill(),
		"PREMISE: can_fill() must be TRUE here, or this file's negatives prove nothing")


# ── the defect ───────────────────────────────────────────────────────────────────────────────────

func test_a_real_fill_leaves_the_channel_alone_afterwards() -> void:
	assert_true(VoicePool.can_fill(), "PREMISE: free before the fill")
	assert_true(await VoicePool.fill_slot(BED_SPEAKER, TRIGGER), "PREMISE: the fill must succeed")
	assert_false(VoicePool.can_fill(),
		"the pool re-grabbed the LLM channel immediately after a fill, so a player talking to an NPC queued behind a whole prefetch round trip")
	assert_gt(VoicePool._next_fill_msec, Time.get_ticks_msec(),
		"and the gap must be in the future, not merely set")
	## THE SIZE, not just the direction: a latching gap (set arbitrarily far out) would leave the
	## pool permanently empty, and the over-reach arm below cannot see it because that arm sets
	## _next_fill_msec itself. Measured: without this assert, that mutant survived 7/7.
	assert_lt(VoicePool._next_fill_msec, Time.get_ticks_msec() + VoicePool.MIN_FILL_GAP_MSEC + 2000,
		"the gap is far larger than MIN_FILL_GAP_MSEC — a latched gap never lets the pool fill again")


func test_a_FAILED_fill_is_spaced_too() -> void:
	## A failed attempt occupied the channel just as long as a successful one.
	_model.reply = "{\"line\": \"\", \"mood\": \"neutral\"}"
	assert_true(VoicePool.can_fill(), "PREMISE: free before the attempt")
	assert_false(await VoicePool.fill_slot(BED_SPEAKER, TRIGGER), "PREMISE: this fill must fail")
	assert_false(VoicePool.can_fill(), "a failed attempt must be spaced like a successful one")


func test_the_gap_and_the_failure_backoff_compose_rather_than_replace() -> void:
	var now: int = Time.get_ticks_msec()
	VoicePool._next_fill_msec = now + 60000
	VoicePool._retry_after_msec = now - 1
	assert_false(VoicePool.can_fill(), "an elapsed backoff must not release a live politeness gap")
	VoicePool._next_fill_msec = now - 1
	VoicePool._retry_after_msec = now + 60000
	assert_false(VoicePool.can_fill(), "an elapsed gap must not release a live failure backoff")
	VoicePool._retry_after_msec = 0
	VoicePool._next_fill_msec = 0
	assert_true(VoicePool.can_fill(), "CONTROL: with both clear it must fill again")


# ── the over-reach arm, named before the fix ──────────────────────────────────────────────────────

func test_the_gap_expires_so_the_pool_fills_again() -> void:
	## ⛔ A gap that latched would leave the pool permanently empty — invisible, because the
	## scripted fallback still speaks.
	assert_true(await VoicePool.fill_slot(BED_SPEAKER, TRIGGER), "PREMISE: one real fill")
	assert_false(VoicePool.can_fill(), "PREMISE: spaced immediately after")
	VoicePool._next_fill_msec = Time.get_ticks_msec() - 1
	assert_true(VoicePool.can_fill(), "once the gap elapses the pool must fill again")


func test_the_gap_is_long_enough_to_matter_and_below_the_backoff_ceiling() -> void:
	assert_gt(VoicePool.MIN_FILL_GAP_MSEC, 1000, "a sub-second gap leaves the channel monopolised")
	assert_lt(VoicePool.MIN_FILL_GAP_MSEC, VoicePool.FAIL_BACKOFF_CAP_MSEC,
		"the politeness gap must not exceed the failure backoff's own ceiling")


# ── floor ────────────────────────────────────────────────────────────────────────────────────────

func test_the_symbols_this_guard_drives_exist() -> void:
	assert_true("_next_fill_msec" in VoicePool, "VoicePool._next_fill_msec")
	assert_true("MIN_FILL_GAP_MSEC" in VoicePool, "VoicePool.MIN_FILL_GAP_MSEC")
	for m in ["can_fill", "fill_slot", "next_empty_slot"]:
		assert_true(VoicePool.has_method(m), "VoicePool.%s" % m)
	assert_eq(LLMService.QUEUE_CAP, 16,
		"QUEUE_CAP moved: the docstring's reason for NOT claiming the drop-oldest half is keyed to 16")
