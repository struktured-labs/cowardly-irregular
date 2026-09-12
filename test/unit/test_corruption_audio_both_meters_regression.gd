extends GutTest

## The corruption audio degradation existed but only the AUTOGRIND meter reached it, and only from
## inside the grind loop — so a save rotting during ordinary play was silent. Two meters now share
## one surface via stored state + max(), NOT two callers of one setter: that would be
## last-writer-wins and the audio would snap back to grind-only after each grind battle.

var _grind_before: float = 0.0
var _save_before: float = 0.0


func before_each() -> void:
	_grind_before = SoundManager._grind_corruption
	_save_before = SoundManager._save_corruption


func after_each() -> void:
	SoundManager._grind_corruption = _grind_before
	SoundManager._save_corruption = _save_before
	## ⛔ THE INPUTS ARE NOT THE STATE. These two are the meters; the RENDERED level lives in
	## _corruption_intensity and is written by the tween, so restoring the meters left a detune of
	## up to 0.95 on the autoload for every later file. It cost gate 188 a red in
	## test_victory_music_not_pitched_by_danger_regression once reset_danger began restoring a
	## settled detune — visible only in the full suite, never in this file's own run. cowir-main
	## patched the victim's fixture in-fold; this is the source.
	SoundManager.reset_corruption()


## The fixture's own contract, because the leak was invisible to every arm below: they assert what
## the RENDERER computed and none of them looks at what is left behind. A file that raises a global
## meter owes the next file a clean one.
func test_the_fixture_leaves_no_detune_behind() -> void:
	SoundManager.set_corruption_intensity(0.9)
	for i in range(30):
		await get_tree().process_frame
		if SoundManager._corruption_intensity > 0.1:
			break
	assert_gt(SoundManager._corruption_intensity, 0.1,
		"CONTROL: the meter really did render before cleanup — it is at %.3f" % SoundManager._corruption_intensity)

	after_each()

	assert_almost_eq(SoundManager._corruption_intensity, 0.0, 0.001,
		"after_each left a rendered detune of %.3f on the autoload; every later music test inherits it" % SoundManager._corruption_intensity)
	## ⚠️ NOT MUTATION-DISTINGUISHED, and stated rather than assumed: a teardown that only zeroes the
	## field passes this too. Catching that needs the envelope caught MID-FLIGHT, and it cannot be
	## held there — measured 2026-09-12, the tween completes inside ONE frame whenever the frame
	## delta spans its 1.5 s, so a control asserting is_running() red on correct code. The LEVEL
	## assertion above is the load-bearing one; this is a cheap second look, not a proof.
	assert_true(SoundManager._corruption_tween == null or not SoundManager._corruption_tween.is_running(),
		"after_each left the corruption tween RUNNING — it keeps writing pitch into whatever the next file plays")


## The envelope half, which the arm above cannot distinguish: a teardown that only zeroed
## _corruption_intensity passed it. You cannot HOLD a tween mid-flight — measured, a 1.5 s envelope
## completes inside one frame whenever the frame delta spans it — but you do not need to
## (@cowir-autogrind, 2026-09-12): a tween created THIS frame has not advanced, so assert before the
## first await. And ask is_running(), never is_valid(): kill() does not flip valid in the calling
## frame, so a control built on it reds on correct code.
func test_the_fixture_kills_the_envelope_not_just_the_number() -> void:
	SoundManager.set_corruption_intensity(0.9)
	var envelope: Tween = SoundManager._corruption_tween
	assert_true(envelope != null and envelope.is_running(),
		"CONTROL: a fresh envelope runs before any frame — without this the assertion below cannot fail")

	after_each()

	assert_false(envelope.is_running(),
		"the teardown zeroed the number and left the envelope alive; it keeps writing _corruption_intensity for up to 1.5 s of WALL time, into whatever file runs next")


func _rendered() -> float:
	# What the PRODUCTION code computed, not a max() the test recomputes. The first version of this
	# helper derived the expectation from the same two vars, so both mutation arms (drop either
	# meter from the render) scored GREEN — the test could not observe the formula it was pinning.
	return SoundManager._corruption_target


func test_the_autogrind_meter_reaches_the_audio() -> void:
	SoundManager.set_save_corruption(0.0)
	SoundManager.set_corruption_intensity(0.8)
	assert_almost_eq(SoundManager._grind_corruption, 0.8, 0.001, "the grind setter must still store the grind meter")
	assert_almost_eq(_rendered(), 0.8, 0.001, "autogrind corruption must still drive the audio — it is a closed ruling that grind risk stays visible")


func test_the_save_meter_reaches_the_audio() -> void:
	SoundManager.set_corruption_intensity(0.0)
	SoundManager.set_save_corruption(0.7)
	assert_almost_eq(SoundManager._save_corruption, 0.7, 0.001, "the save setter must store the save meter")
	assert_almost_eq(_rendered(), 0.7, 0.001, "GameState.corruption_level must drive the audio with NO autogrind activity — this is the whole point")


func test_neither_meter_masks_the_other() -> void:
	SoundManager.set_corruption_intensity(0.9)
	SoundManager.set_save_corruption(0.2)
	assert_almost_eq(_rendered(), 0.9, 0.001, "grind higher -> grind wins")
	SoundManager.set_save_corruption(0.95)
	assert_almost_eq(_rendered(), 0.95, 0.001, "save higher -> save wins")
	SoundManager.set_corruption_intensity(0.1)
	assert_almost_eq(_rendered(), 0.95, 0.001, "a grind battle ending must NOT drop the audio back to grind-only while the save is still rotten")


func test_gamestate_emits_on_every_corruption_write_not_only_raises() -> void:
	# Load and New Game move corruption_level too. An audio surface that only hears raises leaves a
	# loaded corrupt save clean and a fresh save dirty.
	assert_true(GameState.has_signal("corruption_changed"), "GameState must expose corruption_changed for the audio to subscribe to")
	var src := FileAccess.get_file_as_string("res://src/meta/GameState.gd")
	assert_ne(src, "", "GameState.gd unreadable — the count below would be vacuous")
	var emits := src.count("corruption_changed.emit")
	assert_eq(emits, 3, "expected an emit at all THREE corruption_level writes (load, add_corruption, reset); found %d" % emits)


func test_the_audio_actually_subscribes_to_that_signal() -> void:
	# A signal nobody connects is the same silence with more code.
	assert_true(SoundManager.has_method("set_save_corruption"), "the save-side entry point must exist")
	assert_true(GameState.corruption_changed.is_connected(SoundManager.set_save_corruption),
		"SoundManager is NOT connected to GameState.corruption_changed — player corruption would stay silent and nothing would error")


func test_every_corruption_cue_resolves() -> void:
	var raw := FileAccess.get_file_as_string("res://data/sfx_manifest.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has("menu_select"), "manifest lacks a known-present key — this check is not reading the file")
	var missing: Array = []
	for k in ["corruption_gain_visual_glitch", "corruption_gain_stat_drain", "corruption_gain_encounter_surge",
			"corruption_gain_bp_instability", "corruption_gain_ability_corruption",
			"corruption_misfire", "corruption_ap_flicker"]:
		if not sfx.has(k):
			missing.append(k)
	if not missing.is_empty():
		fail_test("corruption cues wired in src but absent from the manifest — they play silence: %s" % [missing])
