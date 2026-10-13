extends GutTest

## `VoicePool.take_line` spent the pool slot BEFORE it resolved the audio:
##
##     var slot := store.take(speaker, trigger)     # gone from the pool, and saved to disk
##     store.save()
##     var stream := vs.get_cached(speaker, slot["line"])
##     if stream == null:
##         return {}                                 # ...and the line is destroyed
##
## A line costs an LLM completion plus a TTS synthesis. On any cache miss the player got the live
## LLM path instead — a line, but UNVOICED and after a fresh round trip — and the prefetched voiced
## line was gone for good.
##
## ⛔ THE CASE THAT MAKES IT A DEFECT RATHER THAN A TIDY-UP IS ONE THE CACHE ITSELF GUARDS AGAINST.
## `VoiceService.get_cached` ends with: *"A wedged mix refuses the lock and returns null. That blob
## is still whole, so the key stays."* Someone thought about a wedged mixer, deliberately KEPT the
## cached bytes — and the caller threw the line away regardless. The audio was preserved and the
## line it belonged to was not.
##
## MEASURED on this box, headless/Dummy, control in the same run (2026-10-13):
##   stall watch active                                     true
##   baseline            wav_commit_refused()               false
##   _audio_mixer_wedged = true -> wav_commit_refused()      true   (the flag survives the
##                                                                  note_mixer_progress() call)
##   decode_voice_wav(good tone) while wedged               NULL
##   CONTROL same tone, not wedged                          STREAM
## So one flag reproduces the production condition through the real path.
##
## ⚠️ THE FIX NEEDS BOTH DIRECTIONS, and naming them before writing the mutants is the only reason
## the second one exists: keeping the slot on EVERY miss would wedge it forever when the blob is
## genuinely gone. `has_cached` is the discriminator, and it answers about the BLOB where
## `get_cached` answers about the STREAM.
##
## Three ways a blob goes for good, read off VoiceCache rather than assumed: LRU eviction past the
## 200 MB cap (`_evict` sorts ascending on `_used`, and `write`/`read` are the only things that
## stamp — so an unread prefetched line's stamp NEVER advances and it sinks toward the front of
## the queue while it waits; not "evicted first by definition", which overstates it, but aged
## relatively by every later write or hit), a file that reads back empty (`read` forgets the key),
## and a voice change under the slot, which makes every key unreachable.

const DIR := "user://test_pool_spend_cache"
const LINE := "Hold for applause. No? Tough room."
const SPEAKER := "bard"
const TRIGGER := "turn_start"

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
		"wedged": SoundManager._audio_mixer_wedged,
	}
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {SPEAKER: {"voice": "bard.wav", "rev": 1}}
	VoiceService.is_web = false
	VoicePool.store = VoicePoolStore.new(DIR + "/pool.json")
	VoicePool.set_process(false)
	GameState.tts_live_enabled = true
	GameState.party_llm_dialogue_enabled = true
	SoundManager._audio_mixer_wedged = false


func after_each() -> void:
	SoundManager._audio_mixer_wedged = bool(_saved["wedged"])
	VoiceService._cast = _saved["cast"]
	VoiceService.cache = _saved["cache"]
	VoiceService.is_web = bool(_saved["web"])
	VoicePool.store = _saved["store"]
	GameState.tts_live_enabled = bool(_saved["tts"])
	GameState.party_llm_dialogue_enabled = bool(_saved["pld"])
	VoicePool.set_process(true)
	_wipe()


## A slot whose audio IS cached — the state the prefetcher leaves behind.
func _arm_ready_slot() -> void:
	var key := VoiceService.cache_key_for(SPEAKER, LINE)
	assert_ne(key, "", "PREMISE: the speaker's voice must resolve or nothing below is about caching")
	assert_true(VoiceService.cache.write(key, WavFixture.tone(0.3, 8000)),
		"PREMISE: the fixture must actually cache the audio")
	VoicePool.store.put(SPEAKER, TRIGGER, LINE, "bard.wav", 1)
	VoicePool.store.save()
	assert_true(VoicePool.store.has_line(SPEAKER, TRIGGER), "PREMISE: the slot must be armed")


func _slot_on_disk() -> bool:
	var fresh := VoicePoolStore.new(DIR + "/pool.json")
	fresh.load_from_disk()
	return fresh.has_line(SPEAKER, TRIGGER)


# ── the discriminator the fix rests on ───────────────────────────────────────────────────────────

func test_has_cached_separates_a_wedged_mixer_from_a_missing_blob() -> void:
	_arm_ready_slot()
	SoundManager._audio_mixer_wedged = true
	assert_null(VoiceService.get_cached(SPEAKER, LINE),
		"PREMISE: a wedged mixer must refuse the decode, or this file tests nothing")
	assert_true(VoiceService.has_cached(SPEAKER, LINE),
		"the blob must still be there while the mixer is wedged — get_cached keeps the key on purpose")
	SoundManager._audio_mixer_wedged = false
	VoiceService.cache.remove(VoiceService.cache_key_for(SPEAKER, LINE))
	assert_false(VoiceService.has_cached(SPEAKER, LINE), "a removed blob must read absent")


func test_both_readers_derive_the_key_from_one_place() -> void:
	## Pins the single derivation: a second spelling would make has_cached answer about a key
	## get_cached never reads, and the fix's whole discriminator would be about nothing.
	var key := VoiceService.cache_key_for(SPEAKER, LINE)
	assert_eq(key, VoiceCache.key_for("bard.wav", 1, LINE),
		"cache_key_for must agree with VoiceCache.key_for on the resolved voice and rev")
	assert_false(VoiceService.has_cached(SPEAKER, LINE), "PREMISE: nothing cached yet")
	VoiceService.cache.write(key, WavFixture.tone(0.2, 8000))
	assert_true(VoiceService.has_cached(SPEAKER, LINE),
		"has_cached must answer about the SAME key cache_key_for returns")


# ── the defect ───────────────────────────────────────────────────────────────────────────────────

func test_a_wedged_mixer_does_not_spend_the_pooled_line() -> void:
	_arm_ready_slot()
	SoundManager._audio_mixer_wedged = true
	var got: Dictionary = VoicePool.take_line(SPEAKER, TRIGGER)
	assert_true(got.is_empty(), "PREMISE: a refused decode must still yield no line this turn")
	assert_true(VoicePool.store.has_line(SPEAKER, TRIGGER),
		"the pooled line was destroyed by a TRANSIENT refusal — it cost an LLM call and a synthesis")
	assert_true(_slot_on_disk(),
		"the loss was persisted: pool.json no longer holds the slot, so a restart cannot recover it")


func test_the_line_still_speaks_once_the_mixer_recovers() -> void:
	## The consequence that makes the arm above worth having: the player gets the voiced line back.
	_arm_ready_slot()
	SoundManager._audio_mixer_wedged = true
	assert_true(VoicePool.take_line(SPEAKER, TRIGGER).is_empty(), "PREMISE: refused while wedged")
	SoundManager._audio_mixer_wedged = false
	var got: Dictionary = VoicePool.take_line(SPEAKER, TRIGGER)
	assert_false(got.is_empty(), "the kept slot must speak once the mixer recovers")
	assert_eq(str(got.get("line", "")), LINE, "and it must be the line that was prefetched")
	assert_not_null(VoicePool.claim_stream(str(got.get("token", ""))),
		"its synthesized audio must still be claimable")


func test_a_transient_miss_leaves_the_pool_file_alone() -> void:
	## The old code saved on the failure path too, writing a smaller pool for nothing.
	_arm_ready_slot()
	var before: String = FileAccess.get_file_as_string(DIR + "/pool.json")
	assert_ne(before, "", "PREMISE: the pool file must exist to compare")
	SoundManager._audio_mixer_wedged = true
	VoicePool.take_line(SPEAKER, TRIGGER)
	assert_eq(FileAccess.get_file_as_string(DIR + "/pool.json"), before,
		"a transient miss rewrote pool.json")


# ── the other direction: a slot that can never play must not wedge forever ───────────────────────

func test_a_blob_that_is_gone_spends_the_slot_so_the_filler_can_replace_it() -> void:
	## THE OVER-REACH ARM. Keeping the slot on EVERY miss would strand it: next_empty_slot only
	## refills an EMPTY slot, so an unplayable one would block its trigger for the rest of the run.
	_arm_ready_slot()
	VoiceService.cache.remove(VoiceService.cache_key_for(SPEAKER, LINE))
	assert_false(VoiceService.has_cached(SPEAKER, LINE), "PREMISE: the blob must really be gone")
	var got: Dictionary = VoicePool.take_line(SPEAKER, TRIGGER)
	assert_true(got.is_empty(), "an unplayable slot must not pretend to speak")
	assert_false(VoicePool.store.has_line(SPEAKER, TRIGGER),
		"an unplayable slot was kept, so its trigger can never refill — a line that is gone is not transient")
	assert_false(_slot_on_disk(), "and the drop must be persisted, or a restart restores the stuck slot")


func test_a_voice_change_under_a_slot_spends_it() -> void:
	## The same direction by a different route, and the one a player can actually cause: changing
	## the speaker's voice makes every cached key unreachable, so the slot can never play.
	_arm_ready_slot()
	VoiceService._cast = {SPEAKER: {"voice": "other.wav", "rev": 2}}
	assert_false(VoiceService.has_cached(SPEAKER, LINE), "PREMISE: the new voice must miss the cache")
	assert_true(VoicePool.take_line(SPEAKER, TRIGGER).is_empty(), "it cannot speak in the old voice")
	assert_false(VoicePool.store.has_line(SPEAKER, TRIGGER),
		"a slot synthesized in a retired voice must be spent so the filler replaces it")


# ── the happy path, unchanged ────────────────────────────────────────────────────────────────────

func test_a_ready_slot_with_a_healthy_mixer_still_spends_and_speaks() -> void:
	## CONTROL for every arm above: without it, "never spend" and "always keep" both pass.
	_arm_ready_slot()
	var got: Dictionary = VoicePool.take_line(SPEAKER, TRIGGER)
	assert_false(got.is_empty(), "a ready slot must speak")
	assert_eq(str(got.get("line", "")), LINE, "with its own line")
	assert_false(VoicePool.store.has_line(SPEAKER, TRIGGER), "and the slot must be spent")
	assert_false(_slot_on_disk(), "persisted, so a restart does not replay it")
	assert_not_null(VoicePool.claim_stream(str(got.get("token", ""))), "its audio is claimable once")
	assert_null(VoicePool.claim_stream(str(got.get("token", ""))), "and only once")


func test_a_disabled_pool_touches_nothing() -> void:
	## CONTROL on the early return: an opted-out player's pool must not be spent either.
	_arm_ready_slot()
	GameState.tts_live_enabled = false
	assert_true(VoicePool.take_line(SPEAKER, TRIGGER).is_empty(), "a disabled pool yields nothing")
	assert_true(VoicePool.store.has_line(SPEAKER, TRIGGER), "and spends nothing")


# ── floor ────────────────────────────────────────────────────────────────────────────────────────

func test_the_symbols_this_guard_drives_exist() -> void:
	for m in ["cache_key_for", "has_cached", "get_cached", "voice_for"]:
		assert_true(VoiceService.has_method(m), "VoiceService.%s" % m)
	for m in ["take_line", "claim_stream"]:
		assert_true(VoicePool.has_method(m), "VoicePool.%s" % m)
	for m in ["peek", "take", "has_line", "save", "load_from_disk"]:
		assert_true(VoicePool.store.has_method(m), "VoicePoolStore.%s" % m)
	assert_true(SoundManager.has_method("wav_commit_refused"), "SoundManager.wav_commit_refused")
	assert_true(SoundManager.has_method("mixer_is_wedged"), "SoundManager.mixer_is_wedged")
