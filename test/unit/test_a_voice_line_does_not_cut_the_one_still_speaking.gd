extends GutTest

## A second party voice line replaces the stream on the SHARED `_voice_player` mid-word.
##
##     func play_voice_stream(stream: AudioStream) -> float:
##         _voice_player.stream = stream
##         _voice_player.play()
##         return stream.get_length()
##
## One AudioStreamPlayer, so the later line truncates the earlier one — and the earlier BUBBLE
## stays on screen for the rest of its `clip_len + VOICE_TAIL_S` hold, silent, because the hold was
## computed from a clip that got cut off.
##
## ⛔ THE COMMON CASE IS EVERY BATTLE VICTORY, not an edge. The party-line gate is keyed PER
## CHARACTER and measured in rounds, and victory bypasses it outright:
##     PARTY_LINE_COOLDOWN_ROUNDS = 8, keyed on combatant_name
##     `event_kind != "victory"` in the cooldown condition  -> victory is exempt for everyone
## So up to five PCs emit a line in the same moment, four get cut, and `MAX_CONCURRENT = 2` frees
## the older bubbles besides.
##
## 🔑 THE CODEBASE HAS FIXED THIS CLASS TWICE ALREADY, in the same file, and both comments survive:
##     _voice_player   "party lines are SECONDS long and every menu blip on _ui_player cut
##                      them (2026-09-11)"
##     play_pickup     "on the shared UI player they landed on a cue still playing: a gold
##                      chest's lid (1.48s) was replaced by its coins (1.00s) in the same
##                      frame, on all 15 of them"
## Both were repaired by giving the cue its OWN player. That remedy is wrong here: a second voice
## player would let two party members talk over each other, which is worse than losing one line's
## audio. So this refuses instead — and the refusal has to be VISIBLE IN THE RETURN VALUE, because
## BattleSpeechBubble._play_voice builds its hold from it and would otherwise hold for audio that
## never played.

const A_SEC := 1.0
const B_SEC := 0.4

var _saved_wedged: bool = false


func before_each() -> void:
	_saved_wedged = SoundManager._audio_mixer_wedged
	SoundManager._audio_mixer_wedged = false
	SoundManager.stop_voice()


func after_each() -> void:
	SoundManager.stop_voice()
	SoundManager._audio_mixer_wedged = _saved_wedged


func _tone(sec: float) -> AudioStream:
	var s := AudioStreamWAV.load_from_buffer(WavFixture.tone(sec, 8000))
	assert_not_null(s, "PREMISE: the fixture tone must decode")
	return s


# ── the premise this whole file rests on ─────────────────────────────────────────────────────────

func test_a_played_voice_reports_itself_as_playing() -> void:
	## Without this the arms below could pass because NOTHING ever plays in a Dummy-driver run,
	## which is the same green as a correct refusal.
	var a := _tone(A_SEC)
	assert_gt(SoundManager.play_voice_stream(a), 0.0, "a fresh line must report its length")
	assert_true(SoundManager._voice_player.playing,
		"the voice player must report playing, or 'still speaking' is not a state this run can reach")
	assert_eq(SoundManager._voice_player.stream, a, "and it must hold the stream it was given")


# ── the defect ───────────────────────────────────────────────────────────────────────────────────

func test_a_second_line_does_not_replace_the_one_still_speaking() -> void:
	var a := _tone(A_SEC)
	var b := _tone(B_SEC)
	SoundManager.play_voice_stream(a)
	assert_true(SoundManager._voice_player.playing, "PREMISE: the first line must still be speaking")
	SoundManager.play_voice_stream(b)
	assert_eq(SoundManager._voice_player.stream, a,
		"the second line replaced the first mid-word — at victory, four of five lines are fragments")


func test_a_refused_line_says_so_in_its_RETURN_VALUE() -> void:
	## The half that matters to the bubble: BattleSpeechBubble._play_voice does
	## `_hold_time = maxf(_hold_time, clip_len + VOICE_TAIL_S)` on this return. A refusal that
	## reported the clip's length would hold a silent bubble for audio that never played.
	var a := _tone(A_SEC)
	var b := _tone(B_SEC)
	SoundManager.play_voice_stream(a)
	assert_eq(SoundManager.play_voice_stream(b), 0.0,
		"a refused line must report NO audio, or its bubble holds for a clip it never got")


func test_a_refused_line_leaves_the_player_untouched() -> void:
	## The current code sets volume_db and pitch_scale BEFORE play(), so a refusal that returns
	## early after those assignments would re-tune the line that IS speaking.
	var a := _tone(A_SEC)
	var b := _tone(B_SEC)
	SoundManager.play_voice_stream(a)
	var vol: float = SoundManager._voice_player.volume_db
	var pitch: float = SoundManager._voice_player.pitch_scale
	SoundManager.play_voice_stream(b)
	assert_almost_eq(SoundManager._voice_player.volume_db, vol, 0.001,
		"a refused line re-tuned the volume of the line still speaking")
	assert_almost_eq(SoundManager._voice_player.pitch_scale, pitch, 0.001,
		"a refused line re-tuned the pitch of the line still speaking")


# ── controls: the refusal must not become "never play anything" ──────────────────────────────────

func test_a_line_plays_when_nothing_is_speaking() -> void:
	## CONTROL for every arm above. Without it, a blanket refusal passes them all.
	var b := _tone(B_SEC)
	assert_gt(SoundManager.play_voice_stream(b), 0.0, "a line must play when the channel is free")
	assert_eq(SoundManager._voice_player.stream, b, "and the player must hold it")


func test_a_line_plays_again_once_the_channel_is_released() -> void:
	## CONTROL for the refusal's SCOPE: it must last only as long as the line it protects.
	var a := _tone(A_SEC)
	var b := _tone(B_SEC)
	SoundManager.play_voice_stream(a)
	assert_eq(SoundManager.play_voice_stream(b), 0.0, "PREMISE: refused while a is speaking")
	SoundManager.stop_voice()
	assert_gt(SoundManager.play_voice_stream(b), 0.0, "once released, the next line must play")
	assert_eq(SoundManager._voice_player.stream, b, "and take the player")


func test_a_line_plays_again_once_the_previous_one_ENDS_BY_ITSELF() -> void:
	## ⛔ THE ARM THAT DECIDES WHETHER THE FIX IS SAFE AT ALL. Refusing while `playing` is true
	## introduces a new failure mode the defect never had: if `playing` never clears, every voice
	## line for the rest of the session is refused. The sibling control releases the channel with an
	## explicit stop_voice(); this one waits for NATURAL completion, which is what a real battle
	## does. If a Dummy-driver run does not advance playback, this arm reds and the fix is wrong.
	var short := _tone(0.15)
	assert_gt(SoundManager.play_voice_stream(short), 0.0, "PREMISE: the short line must play")
	var waited: float = 0.0
	while SoundManager._voice_player.playing and waited < 3.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	assert_false(SoundManager._voice_player.playing,
		"playback never finished on its own after %.2fs — a busy-refusal would then silence every later line" % waited)
	var b := _tone(B_SEC)
	assert_gt(SoundManager.play_voice_stream(b), 0.0,
		"the channel did not free itself, so the next line could never play")
	assert_eq(SoundManager._voice_player.stream, b, "and the new line must hold the player")


func test_a_wedged_mixer_refuses_whether_the_channel_is_free_or_busy() -> void:
	## ⛔ THIS ARM USED TO CLAIM THE WEDGE CHECK "KEEPS PRECEDENCE OVER THE BUSY CHECK", and the
	## mutation that swaps the two SURVIVED 10/10 — so the arm could not see the order and the
	## rationale was wrong anyway: with the busy check first, a wedged-and-busy player returns
	## before the wedge check and still never reaches set_data. Neither order can produce the
	## call that issue #224 hangs on. What IS worth pinning is that the two refusals COMPOSE —
	## a wedged mixer refuses on a free channel AND on a busy one — which is what this now drives.
	var a := _tone(A_SEC)
	SoundManager._audio_mixer_wedged = true
	assert_eq(SoundManager.play_voice_stream(a), 0.0, "a wedged mixer must refuse on a FREE channel")
	assert_false(SoundManager._voice_player.playing, "and must not have started anything")
	SoundManager._audio_mixer_wedged = false
	assert_gt(SoundManager.play_voice_stream(a), 0.0, "PREMISE: it plays once the wedge clears")
	SoundManager._audio_mixer_wedged = true
	assert_eq(SoundManager.play_voice_stream(_tone(B_SEC)), 0.0,
		"a wedged mixer must refuse on a BUSY channel too")
	assert_eq(SoundManager._voice_player.stream, a, "and must not disturb the line already speaking")


# ── the player-visible end of it: a refused line degrades to an unvoiced bubble ──────────────────

func test_a_bubble_whose_voice_was_refused_behaves_like_an_unvoiced_one() -> void:
	## The loop closed, from SoundManager to the screen. BattleSpeechBubble._play_voice already
	## early-returns on `clip_len <= 0.0`, so the refusal needs NO change there — but that is the
	## arm proving it, because the alternative (holding a silent bubble for a clip it never got)
	## is the defect wearing different clothes.
	var parent := Node2D.new()
	add_child_autofree(parent)
	var before: float = Engine.time_scale
	Engine.time_scale = 0.25
	SoundManager.play_voice_stream(_tone(A_SEC))
	assert_true(SoundManager._voice_player.playing, "PREMISE: the channel must be busy")
	var b = BattleSpeechBubble.spawn(parent, Vector2(320, 240), "Lyra", "a refused line",
		Color.WHITE, 2.0, "", true, 0.0, 8.0, Callable(), _tone(B_SEC))
	Engine.time_scale = before
	assert_not_null(b, "PREMISE: the bubble must spawn at this speed")
	assert_false(b._voiced,
		"the bubble marked itself voiced on a refused line, so it holds on the real clock for audio that never played")
	assert_almost_eq(b._hold_time, 2.0, 0.001,
		"a refused line must leave the requested hold alone — a voiced hold would stretch it to the clip")
	b.queue_free()
	await get_tree().process_frame


# ── floor ────────────────────────────────────────────────────────────────────────────────────────

func test_the_symbols_this_guard_drives_exist() -> void:
	for m in ["play_voice_stream", "stop_voice", "wav_commit_refused", "mixer_is_wedged"]:
		assert_true(SoundManager.has_method(m), "SoundManager.%s" % m)
	assert_not_null(SoundManager._voice_player, "SoundManager._voice_player")
	assert_true(SoundManager._voice_player is AudioStreamPlayer, "it must be an AudioStreamPlayer")
