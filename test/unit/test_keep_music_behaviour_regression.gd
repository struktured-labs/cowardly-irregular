extends GutTest

## `keep_music` was guarded by a SOURCE-TEXT pin, and that pin does not cover
## the behaviour it claims to.
##
## The existing assertion (test_mordaine_escalation_wiring_regression) reads:
##
##     assert_gt(src.find('data.get("keep_music"'), -1,
##         "the director must honor keep_music, or the field is authored-but-inert")
##
## VERIFIED BY MUTATION 2026-07-29: replace the guard with a refactor that
## still READS the field and stops acting on it —
##
##     if SoundManager and SoundManager._music_playing:
##         var _keep := bool(data.get("keep_music", false))
##
## — and the whole wiring file reports 13 passing / 0 failing while the
## ambient road beat is back to fading the overworld into dead air. The
## string survives; the behaviour is gone.
##
## That is @cowir-ai's class (msg-3319): a source-text pin is a claim about
## the code's SPELLING, written where we meant its BEHAVIOUR. Their tell —
## "a pinned string containing a word that carries a condition nothing ever
## varies" — fits exactly: the condition is `not`, and nothing varied it.
##
## Found by copying their habit, not by a red build. Every guard defect the
## fleet found tonight came from one lane publishing a near-miss and another
## lane re-checking its own work; none came from a failing test.
##
## The fix is theirs too: make the decision a named predicate so a test can
## DRIVE it. The source pin stays where it is — it catches a different class
## (the field being removed outright) and costs nothing.

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"

var _saved_playing: bool = false


func before_each() -> void:
	if SoundManager:
		_saved_playing = SoundManager._music_playing


func after_each() -> void:
	if SoundManager:
		SoundManager._music_playing = _saved_playing


func _director():
	var d = load(DIRECTOR).new()
	add_child_autofree(d)
	return d


func test_keep_music_scene_does_not_fade() -> void:
	# THE regression. This is what the source pin could not see.
	SoundManager._music_playing = true
	assert_false(_director()._should_fade_music_for({"keep_music": true}),
		"a scene opting out must NOT fade the map music — that is the whole point of the ambient beat")


func test_ordinary_scene_still_fades() -> void:
	# Positive control. Without this, a predicate that returned false
	# unconditionally would satisfy the test above and silently disable the
	# fade for all 190+ scenes.
	SoundManager._music_playing = true
	assert_true(_director()._should_fade_music_for({}),
		"a scene that does NOT opt out must still fade — the fade is corpus-wide behaviour struktured has already heard")
	assert_true(_director()._should_fade_music_for({"keep_music": false}),
		"an explicit false must behave like an absent key")


func test_no_fade_when_nothing_is_playing() -> void:
	SoundManager._music_playing = false
	assert_false(_director()._should_fade_music_for({}),
		"nothing playing = nothing to fade, regardless of the flag")


func test_the_decision_is_a_named_predicate_not_an_inline_condition() -> void:
	# Guards the testability itself. Inlining this back into play_cutscene
	# would leave the behaviour undrivable and put the class straight back —
	# the tests above would still pass while covering a function nobody calls.
	var src := FileAccess.get_file_as_string(DIRECTOR)
	assert_gt(src.find("func _should_fade_music_for("), -1,
		"the fade decision must stay a named predicate so it can be driven by a test")
	var call_site := src.find("if _should_fade_music_for(data):")
	assert_gt(call_site, -1,
		"play_cutscene must USE the predicate — a tested function nobody calls is the same defect wearing a rosette")
