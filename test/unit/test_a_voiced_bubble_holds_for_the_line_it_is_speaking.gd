extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## SoundManager COMPUTES the clip length and BattleSpeechBubble SHOWS it for that long. Those are two
## claims and only the first was pinned: test_a_voice_line_times_the_bubble_it_was_heard_in drives
## sm.play_voice and asserts the returned float, and NOTHING drove the consumer at
## BattleSpeechBubble:327. cowir-autogrind's shape — the manager computes a value, the UI presents
## it, and a guard at the manager is green whatever the UI does with it.

const BUBBLE_SRC := "res://src/battle/BattleSpeechBubble.gd"
const VOICED_KEY := "voice_bard_turn_start"
const SILENT_KEY := "zz_no_such_voice_line_at_all"
const BASE_HOLD := 1.5

var _parent: Node = null
var _saved_scale: float = 1.0


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func before_each() -> void:
	## ESTABLISHED, not asserted: spawn() returns null at or above SUPPRESS_TIME_SCALE, and a prior
	## file leaving 4x would make every arm here vacuously skip.
	_saved_scale = Engine.time_scale
	Engine.time_scale = 1.0
	BattleSpeechBubble._live.clear()
	_parent = Node.new()
	add_child(_parent)
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()


func after_each() -> void:
	SfxState.release_streams()
	## static, so it outlives this file — a stale entry counts against MAX_CONCURRENT for everyone.
	BattleSpeechBubble._live.clear()
	## free(), not queue_free(): the queued form defers past the end of the test, so the bubbles and
	## every Control _present builds under them survive as ORPHANS for the rest of the run. Measured
	## 2026-09-18 with a residue probe: 24 orphan nodes after this file, 0 at baseline; free() takes it
	## to 2. _live and the scene tree both read clean — orphan count is a third surface and nothing else
	## here measures it. The residual 2 is NOT same-speaker eviction inside spawn(): distinct speakers
	## in every arm still measured 2, so that hypothesis is disproven and the source is unidentified.
	if _parent and is_instance_valid(_parent):
		_parent.free()
		_parent = null
	Engine.time_scale = _saved_scale
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()


func test_a_voiced_bubble_holds_for_the_length_the_clip_reported() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(VOICED_KEY),
		"CONTROL: %s must be authored, or this arm measures the unresolved path instead" % VOICED_KEY)
	var b = BattleSpeechBubble.spawn(_parent, Vector2(320, 240), "Bard", "a line", Color.WHITE, BASE_HOLD, VOICED_KEY)
	assert_not_null(b, "CONTROL: spawn returned null — suppressed, so nothing below is measured")
	if b == null:
		return
	assert_not_null(sm._voice_player.stream,
		"CONTROL: the voice clip must have loaded, or the length under test is 0.0 by default")
	var clip: float = float(sm._voice_player.stream.get_length())
	assert_gt(clip, BASE_HOLD - BattleSpeechBubble.VOICE_TAIL_S,
		"CONTROL: this clip is shorter than the base hold, so maxf() keeps the base and the arm cannot tell the consumer read anything")
	assert_eq(b._hold_time, clip + BattleSpeechBubble.VOICE_TAIL_S,
		"the bubble held %.2fs for a %.2fs line — it did not take the length play_voice returned" % [b._hold_time, clip])
	assert_true(b._voiced, "_voiced is false, so _present builds the fade on the SCALED clock and a 5.3s line runs ~24s at 4x")


func test_an_unresolvable_key_leaves_the_bubble_on_battle_pacing() -> void:
	## Anti-overcorrection: play_voice returns 0.0 when the key does not resolve, and the consumer
	## must leave the hold alone rather than clamping every voiceless bubble to VOICE_TAIL_S.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_false(sm._sfx_manifest.has(SILENT_KEY), "CONTROL: %s must NOT be authored" % SILENT_KEY)
	var b = BattleSpeechBubble.spawn(_parent, Vector2(320, 240), "Mage", "a line", Color.WHITE, BASE_HOLD, SILENT_KEY)
	assert_not_null(b, "CONTROL: spawn returned null")
	if b == null:
		return
	assert_eq(b._hold_time, BASE_HOLD, "an unvoiced bubble's hold moved to %.2f — the 0.0 return was treated as a length" % b._hold_time)
	assert_false(b._voiced, "an unvoiced bubble claimed to be voiced, putting its fade on the real clock")


func test_the_voice_is_read_before_the_fade_tween_is_built() -> void:
	## The ordering is load-bearing and its own comment says so — "a tween created first would keep
	## the old 2.0s and fade over a line still being spoken" — but a comment cannot red. One line
	## moved below _present reintroduces a measured 24s bubble, and every behavioural arm above still
	## passes because _hold_time is correct by then; only the TWEEN read the stale value.
	var code: String = GdSource.code_of(BUBBLE_SRC)
	assert_ne(code, "", "CONTROL: BattleSpeechBubble source must survive the comment strip")
	var voice_at: int = code.find("_play_voice(audio_key)")
	var present_at: int = code.find("_present(anchor_global_pos")
	assert_gt(voice_at, -1, "the spawn path no longer calls _play_voice(audio_key) — this file's subject is gone")
	assert_gt(present_at, -1, "the spawn path no longer calls _present(anchor_global_pos ...)")
	assert_lt(voice_at, present_at,
		"_play_voice is called AFTER _present, so the fade tween is built from the pre-voice hold and a voiced bubble fades mid-line")


func test_the_voice_tail_is_a_tail_and_not_a_second_pause() -> void:
	## ⚠️ THE ARM ABOVE IS BLIND TO THIS AND I PROVED IT BEFORE WRITING THIS ONE. It asserts
	## `_hold_time == clip + VOICE_TAIL_S` while the product computes `maxf(_hold_time, clip_len +
	## VOICE_TAIL_S)` — the SAME constant on both sides, so a wrong tail moves both and the delta
	## holds. Measured 2026-09-18: 0.3 -> 2.5 leaves all three arms Passing, i.e. every voiced bubble
	## hanging 2.2s past its line with the guard green. That is the delta-ratchet cost, in the guard
	## I wrote to defend this hold — the defence and the defect share a reference.
	##
	## So this arm judges the constant from OUTSIDE the relationship: a TAIL is the beat after a line
	## ends, not a second line. The bound is relational rather than a pinned 0.3 — that would be the
	## coincidental-value ratchet and would red an honest retune.
	var sm: Node = _sm()
	if sm == null:
		return
	var tail: float = float(BattleSpeechBubble.VOICE_TAIL_S)
	assert_gt(tail, 0.0, "VOICE_TAIL_S is %.2f — a voiced bubble closes the instant the audio stops" % tail)
	var b = BattleSpeechBubble.spawn(_parent, Vector2(320, 240), "Bard", "a line", Color.WHITE, BASE_HOLD, VOICED_KEY)
	assert_not_null(b, "CONTROL: spawn returned null")
	if b == null or sm._voice_player.stream == null:
		return
	## ⛔ FIRST VERSION OF THIS BOUND WAS `clip * 0.5` AND PASSED THE 2.5 IT WAS WRITTEN TO CATCH —
	## the measured clip is 5.20s, so the bound was 2.60. An arm blind to its own motivating case.
	## Absolute, because the claim is about the CONTRACT of a tail rather than about this clip: the
	## bubble lingers a beat after the audio stops. Anything past a second is a pause the player
	## waits through on every voiced line, and 31 authored lines do not all exceed two seconds.
	assert_lt(tail, 1.0,
		"VOICE_TAIL_S is %.2fs — past a second it is a pause the player sits through on every voiced line, not a tail, and the delta arm above cannot see it" % tail)
