extends GutTest

## set_music_volume's docstring drifted 4 dB from the constant it describes
## (2026-08-05).
##
## It listed slider 1.00 → -6 dB / 0.50 → -12 dB / 0.10 → -26 dB. Those are
## correct for a -6 dB ceiling; MUSIC_VOLUME_CEILING_DB is -10.0, so the real
## values are -10 / -16 / -30. Someone moved the ceiling and left the prose.
##
## This is the "authored text vs data" class, in its type-(a) form: the two are
## meant to AGREE, so the guard asserts agreement rather than modelling
## precedence. The documented numbers are not independent facts — they are
## MUSIC_VOLUME_CEILING_DB + linear_to_db(slider) — so this derives them and
## fails if the prose stops matching.
##
## Why it earns a test rather than just a correction: nothing about a stale
## docstring is visible at runtime, the suite was green throughout, and the
## drift was found only because a neighbouring lane happened to quote the
## constant. It could equally have sat wrong for another year — and I built a
## wrong recommendation on the same function while it was wrong.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _doc_body() -> String:
	var src: String = FileAccess.get_file_as_string(SOUND_MANAGER)
	assert_ne(src, "", "SoundManager must be readable")
	var i := src.find("func set_music_volume")
	assert_true(i > -1, "set_music_volume must exist")
	return src.substr(i, 900)


func test_documented_slider_values_match_the_ceiling_constant() -> void:
	var sm := _sm()
	if sm == null:
		assert_not_null(sm, "SoundManager unavailable — a skip here reports GREEN having tested nothing")
		return
	var ceiling: float = float(sm.MUSIC_VOLUME_CEILING_DB)
	var body := _doc_body()
	## Same expression the function uses, so the expectation cannot drift
	## independently of the implementation.
	for slider in [1.0, 0.5, 0.1]:
		var expected: int = int(round(ceiling + linear_to_db(slider)))
		var needle: String = "%d dB" % expected
		assert_true(body.find(needle) > -1,
			"the docstring must state \"%s\" for slider %.2f (ceiling %.1f + %.1f attenuation) — it currently does not, so the prose describes a ceiling the code no longer has" % [needle, slider, ceiling, linear_to_db(slider)])


func test_the_stale_values_are_gone() -> void:
	## Negative half. Without it, a docstring listing BOTH the old and new
	## numbers would satisfy the check above while still misinforming a reader.
	var body := _doc_body()
	var sm := _sm()
	if sm == null:
		assert_not_null(sm, "SoundManager unavailable — a skip here reports GREEN having tested nothing")
		return
	var ceiling: float = float(sm.MUSIC_VOLUME_CEILING_DB)
	## Only flag an old value if the ceiling has genuinely moved away from it,
	## so this cannot fire on a deliberate return to -6.
	if not is_equal_approx(ceiling, -6.0):
		var i := body.find("slider 1.00")
		assert_true(i > -1, "the slider table must still exist")
		var line: String = body.substr(i, 60)
		assert_false(line.contains("-6 dB"),
			"the slider-1.00 line still claims -6 dB while the ceiling is %.1f — this is the exact drift the file was corrected for" % ceiling)


func test_positive_control_the_constant_resolves() -> void:
	## If MUSIC_VOLUME_CEILING_DB were renamed, `float(null)` would read 0.0 and
	## the derivation above would silently expect the wrong numbers.
	var sm := _sm()
	if sm == null:
		assert_not_null(sm, "SoundManager unavailable — a skip here reports GREEN having tested nothing")
		return
	assert_lt(float(sm.MUSIC_VOLUME_CEILING_DB), 0.0,
		"MUSIC_VOLUME_CEILING_DB must resolve to a real attenuation — 0.0 means it was renamed and every derivation here is vacuous")
	assert_gt(float(sm.MUSIC_VOLUME_CEILING_DB), -40.0,
		"a ceiling below -40 dB would mean music is effectively muted; the constant is probably not what this test thinks it is")
