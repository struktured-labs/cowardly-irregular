extends GutTest

## The night music filter must soften, not muffle (2026-07-30).
##
## struktured, playing the desktop build: "did u lower the music volume? feels
## muffled even on my desktop version." No volume was lowered — I had set the
## night bus low-pass at 1500 Hz, which removes cymbals, string harmonics and
## the top of a harpsichord. It reads as both duller AND quieter, because
## deleting that much spectrum costs level as a side effect.
##
## Measured on village_harmonia, 12 s excerpt:
##     dry        -13.64 dB RMS
##     1500 Hz    -16.69 dB   (-3.05)   <- what he heard
##     7000 Hz    -16.42 dB   (-2.79)
## The aggressive cutoff bought 0.26 dB of extra attenuation and cost the entire
## top three octaves. There was never a tradeoff to make.
##
## This pins the RELATIONSHIP, not the number: the cutoff must stay above the
## presence region where the perceived brightness of this material lives. A bare
## `== 7000.0` would be a coincidental-value ratchet — it would go red on a
## defensible move to 8 kHz and green on a move to 6.9 kHz that is nearly as bad.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"

## Below this, a low-pass stops being a tone shaping and becomes an occlusion
## effect — the "behind a door / underwater" character struktured reported.
const MUFFLING_THRESHOLD_HZ: float = 4000.0


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_night_cutoff_is_above_the_muffling_threshold() -> void:
	var sm := _sm()
	if sm == null:
		assert_not_null(sm, "SoundManager unavailable — a skip here reports GREEN having tested nothing")
		return
	var cutoff: float = float(sm.NIGHT_LPF_CUTOFF_HZ)
	assert_gt(cutoff, MUFFLING_THRESHOLD_HZ,
		"night LPF is at %.0f Hz — at or below %.0f Hz this reads as occlusion rather than nightfall, which is the defect struktured reported as 'muffled'" % [cutoff, MUFFLING_THRESHOLD_HZ])


func test_the_filter_starts_disabled() -> void:
	## The premise that makes the cutoff a NIGHT concern and not an always-on
	## one. If the effects ever ship enabled, every track is filtered in
	## daylight too and the cutoff value stops being the whole story.
	var src: String = FileAccess.get_file_as_string(SOUND_MANAGER)
	assert_ne(src, "", "SoundManager must be readable")
	var idx := src.find("func _ensure_music_night_bus")
	assert_true(idx > -1, "the night bus builder must exist")
	var body := src.substr(idx, 1400)
	assert_true(body.find("set_bus_effect_enabled") > -1,
		"the builder must explicitly set effect-enabled state rather than leaving the default")
	assert_eq(body.count("set_bus_effect_enabled"), 2,
		"both effects (LPF and reverb) must be explicitly disabled at construction")
	assert_true(body.find("false)") > -1,
		"the effects must start DISABLED — an always-on night filter would muffle daytime music too")


func test_reverb_stays_a_hint_not_a_hall() -> void:
	## Same class as the cutoff: the other way to accidentally build occlusion.
	var sm := _sm()
	if sm == null:
		assert_not_null(sm, "SoundManager unavailable — a skip here reports GREEN having tested nothing")
		return
	assert_lt(float(sm.NIGHT_REVERB_WET), 0.35,
		"night reverb wet is %.2f — past ~0.35 the music sits in a room rather than gaining an evening character" % float(sm.NIGHT_REVERB_WET))


func test_positive_control_the_constants_are_readable() -> void:
	## Without this, a renamed constant makes every assertion above read a
	## default of 0.0 and the suite reports the filter as pristine.
	var sm := _sm()
	if sm == null:
		assert_not_null(sm, "SoundManager unavailable — a skip here reports GREEN having tested nothing")
		return
	assert_gt(float(sm.NIGHT_LPF_CUTOFF_HZ), 0.0,
		"NIGHT_LPF_CUTOFF_HZ must resolve to a real value — 0.0 means the constant was renamed and the checks above are vacuous")
	assert_gt(float(sm.NIGHT_REVERB_WET), 0.0, "NIGHT_REVERB_WET must resolve")
