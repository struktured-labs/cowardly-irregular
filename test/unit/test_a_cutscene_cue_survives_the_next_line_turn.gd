extends GutTest

## A cutscene's own SFX played on _ui_player, and `CutsceneDialogue._advance_dialogue` plays
## `menu_select` on that same player on EVERY press — unconditionally, as the last statement of the
## function. So a cue authored in a cutscene died on the player's next line turn, which during a
## cutscene is immediately: advancing dialogue IS the interaction.
##
## MEASURED in struktured's 2026-10-12 session (uncapped, so its cue sequence is complete):
## portal_activate (2.00s) played 3 times and ALL 3 were followed by menu_select on the very next
## [SFX] line, same UIPlayer. The surrounding lines are `[CUTSCENE] world1_mordaine_defeat complete
## -> chaining world1_epilogue`, so the cue was a cutscene step, not the lever or the teleport pad.
## That channel carried 1,769 cues that session; menu_select alone was 612 of them.
##
## 44 distinct cues are named by data/cutscenes/*.json and 18 exceed 1.0s — up to cave_whispers at
## 3.00s — so this is the whole cutscene vocabulary, not one cue.
##
## 🔑 TENTH INSTANCE OF ONE CLASS, and the nine before it each left a dated one-line comment on the
## player they carved out: death cries (08-18), footsteps / the group flourish / party voice lines
## (09-11), pickups (09-12), the full bank / a refused Advance (09-14), the elemental strike / the
## weakness stinger (09-16), thunder (09-18).
##
## ⛔ THE FIX GOES THE OPPOSITE WAY TO 2026-09-11, AND ITS OWN COMMENT SAYS WHY. There, the victims
## were unenumerable ("the UI player carries 41 cues and enumerating the long ones would need
## extending for every future cue") so the frequent CUTTER was moved instead. Here the victims reach
## the channel through ONE call site — CutsceneDirector._step_play_sfx — so moving them needs no list
## and nothing to maintain. The blip stays on _ui_player: a blip replacing a blip is correct.

const SM_PATH := "res://src/audio/SoundManager.gd"
const CD_PATH := "res://src/cutscene/CutsceneDirector.gd"
const DLG_PATH := "res://src/cutscene/CutsceneDialogue.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## 2.00s, named by cutscene JSON, and the cue his log caught being cut 3 times out of 3.
const LONG_CUE := "portal_activate"
## What _advance_dialogue plays on every press.
const BLIP := "menu_select"


func _reset() -> void:
	## The cooldown returns ~30 lines ABOVE the stream assignment and is keyed on the cue, so a
	## replay inside the window is suppressed and the arm reads the PREVIOUS arm's stream.
	SoundManager._sfx_cooldowns.erase(LONG_CUE)
	SoundManager._sfx_cooldowns.erase(BLIP)


func _stream_of(p: AudioStreamPlayer) -> String:
	if p == null or p.stream == null:
		return ""
	return str(p.stream.resource_path)


func test_the_two_voices_are_distinct_nodes() -> void:
	assert_not_null(SoundManager._cutscene_player, "no cutscene voice exists, so every arm below is about nothing")
	assert_not_null(SoundManager._ui_player, "VOID: no UI player")
	assert_ne(SoundManager._cutscene_player, SoundManager._ui_player,
		"the cutscene voice IS the UI player, so the advance blip still replaces every cutscene cue")


func test_the_cutscene_step_does_not_use_the_shared_ui_voice() -> void:
	var code: String = GdSource.code_of(CD_PATH)
	assert_gt(code.length(), 100, "VOID: CutsceneDirector's code read empty")
	var i: int = code.find("func _step_play_sfx(")
	assert_gt(i, -1, "SCOPE: _step_play_sfx is gone, so this arm no longer describes the function it guards")
	var j: int = code.find("\nfunc ", i + 1)
	var body: String = code.substr(i, (j - i) if j > i else -1)
	assert_true(body.contains("play_cutscene_sfx("),
		"the cutscene sfx step no longer routes to the dedicated voice")
	assert_false(body.contains("play_ui("),
		"the cutscene sfx step is back on play_ui, so every cue it plays dies on the player's next advance press — and it fails SILENTLY, because the cue is audible for the few ms before the press")


func test_the_dedicated_voice_reuses_play_uis_resolution() -> void:
	## Not a style point: the world-variant lookup, the trim table and the cooldown are all in
	## play_ui. A second implementation would drift, and the w<N>_ variant work would stop reaching
	## cutscene cues with nothing saying so.
	var code: String = GdSource.code_of(SM_PATH)
	var i: int = code.find("func play_cutscene_sfx(")
	assert_gt(i, -1, "play_cutscene_sfx is gone")
	var j: int = code.find("\nfunc ", i + 1)
	var body: String = code.substr(i, (j - i) if j > i else -1)
	assert_true(body.contains("play_ui(") and body.contains("_cutscene_player"),
		"play_cutscene_sfx stopped delegating to play_ui, so the variant lookup and the trim table now have two implementations")


func test_a_cutscene_cue_survives_the_advance_blip() -> void:
	_reset()
	SoundManager.play_cutscene_sfx(LONG_CUE)
	var loaded: String = _stream_of(SoundManager._cutscene_player)
	## Without this the arm below passes on a player holding NOTHING, which is the same green.
	assert_true(loaded.contains(LONG_CUE),
		"VOID: %s never reached the cutscene voice (stream=%s), so the survival assert is about nothing" % [LONG_CUE, loaded])
	SoundManager.play_ui(BLIP)
	assert_true(_stream_of(SoundManager._cutscene_player).contains(LONG_CUE),
		"the advance blip displaced the cutscene cue: the cutscene voice now holds %s" % _stream_of(SoundManager._cutscene_player))
	_reset()


func test_the_control_shows_the_blip_really_does_displace() -> void:
	## ⛔ THE ARM ABOVE HAS NO LOUD DIRECTION OF ITS OWN. "The cue survived" and "neither cue ever
	## played" both look like a pass. This drives the OLD routing — both cues through play_ui — and
	## MUST show the displacement, or the arm above cannot be attributed to the fix.
	_reset()
	SoundManager.play_ui(LONG_CUE)
	var loaded: String = _stream_of(SoundManager._ui_player)
	assert_true(loaded.contains(LONG_CUE),
		"VOID: the control's first cue never loaded (stream=%s), so it cannot demonstrate a collision" % loaded)
	SoundManager.play_ui(BLIP)
	assert_false(_stream_of(SoundManager._ui_player).contains(LONG_CUE),
		"the control did NOT collide — two cues on one player left the first in place — so this test cannot see a displacement at all and the survival arm proves nothing")
	_reset()


func test_the_advance_blip_was_not_silenced_instead() -> void:
	## The cheap wrong fix is to stop the cutter sounding. The blip is the player's confirmation that
	## the press registered; removing it would make every dialogue advance silent.
	var code: String = GdSource.code_of(DLG_PATH)
	var i: int = code.find("func _advance_dialogue(")
	assert_gt(i, -1, "SCOPE: _advance_dialogue is gone")
	var j: int = code.find("\nfunc ", i + 1)
	var body: String = code.substr(i, (j - i) if j > i else -1)
	assert_true(body.contains("play_ui(\"%s\")" % BLIP),
		"the advance press no longer plays its blip — the collision was fixed by silencing the cutter, so a press now gives no audible confirmation")
