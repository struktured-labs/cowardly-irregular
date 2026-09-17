extends GutTest

## play_voice returns a DURATION, and BattleSpeechBubble._play_voice holds the bubble for it. It is
## the only consumer that reads a VALUE off the player rather than a bool, so a HANDLED-not-HEARD
## return times the bubble off whichever line played last. Siblings: the hit ramp and the status cue.

const REAL_KEY := "voice_bard_turn_start"
const PROBE_KEY := "voice_zz_probe_missing_file"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._voice_player.stream = null


func after_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_manifest.erase(PROBE_KEY)
	sm._sfx_stream_cache.erase(PROBE_KEY)
	sm._sfx_cooldowns.clear()


## The probe names a file that is not there, so the load fails and the fallback_to is taken — which
## is the ONLY way into the recursion, and therefore the only way a cooled key can answer for it.
func _install_probe(sm: Node) -> void:
	sm._sfx_manifest[PROBE_KEY] = {
		"file": "assets/audio/sfx/zz_this_file_does_not_exist.ogg",
		"fallback_to": REAL_KEY,
	}


func test_an_authored_line_reports_its_own_length() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(REAL_KEY), "CONTROL: %s must be authored or this file measures nothing" % REAL_KEY)
	var secs: float = sm.play_voice(REAL_KEY)
	assert_gt(secs, 0.0, "an authored voice line reported no duration — the bubble would drop to voiceless pacing")


func test_a_suppressed_line_reports_zero_not_the_previous_lines_length() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	## Arrange the exact hazard: a real line has played, so the player HOLDS its stream.
	var first: float = sm.play_voice(REAL_KEY)
	assert_gt(first, 0.0, "CONTROL: the first line must sound, or there is no stale stream to mistime against")
	_install_probe(sm)
	## Cool the FALLBACK, not the probe — play_voice erases the outer key by design.
	sm._sfx_cooldowns[REAL_KEY] = Time.get_ticks_msec()
	var suppressed: float = sm.play_voice(PROBE_KEY)
	## The control that makes the assert below mean something: 0.0 must come from the flag, not from
	## an empty player. If this is null, the next assert passes for the wrong reason.
	assert_not_null(sm._voice_player.stream,
		"CONTROL: the player must still hold the previous line's stream — otherwise the zero below proves nothing")
	assert_eq(suppressed, 0.0,
		"a suppressed voice line reported %.2fs — that is the PREVIOUS line's length, and the bubble would hold for it" % suppressed)


func test_the_suppression_was_real_and_not_a_missing_entry() -> void:
	## Distinguishes the two ways play_voice returns 0.0. Without this, deleting the manifest entry
	## would satisfy the arm above while the defect it guards went untested.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_voice(REAL_KEY)
	_install_probe(sm)
	sm._sfx_cooldowns[REAL_KEY] = Time.get_ticks_msec()
	sm.play_voice(PROBE_KEY)
	assert_true(sm._sfx_suppressed_by_cooldown,
		"the cooldown gate never fired — this file's scenario is not the one it claims to drive")
	assert_true(sm._sfx_manifest.has(PROBE_KEY), "CONTROL: the probe must be installed, or the call above returned early on a missing key")


func test_a_cold_fallback_still_reports_the_fallbacks_length() -> void:
	## Anti-overcorrection: the fix must return 0.0 for SUPPRESSED, not for every fallback.
	var sm: Node = _sm()
	if sm == null:
		return
	_install_probe(sm)
	var secs: float = sm.play_voice(PROBE_KEY)
	assert_gt(secs, 0.0,
		"a fallback that actually sounded reported no duration — the bubble lost its timing on a line the player heard")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## Rung-3 floor: a renamed member aborts an arm AFTER its first assert and scores PASSING.
	## get()/has_method ANSWER instead of raising, so the rename names itself here first.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	for method_name in ["play_voice"]:
		assert_true(sm.has_method(method_name), "SoundManager has no method %s — this file CALLS it" % method_name)
	## ⛔ TWO MECHANISMS, BECAUSE NEITHER COVERS THIS SET ALONE — measured 2026-09-17, not reasoned.
	## get_property_list() omits `static var`, and _sfx_manifest/_sfx_stream_cache ARE static, so a
	## property-list floor reports them missing on correct code. get() resolves statics fine but
	## cannot tell absent from legitimately-false, which is the bool below.
	for member_name in ["_voice_player", "_sfx_cooldowns", "_sfx_manifest", "_sfx_stream_cache"]:
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly, and a rename would abort these arms silently" % member_name)
	var declared: Array = []
	for p in sm.get_property_list():
		declared.append(str(p.get("name", "")))
	assert_true(declared.has("_sfx_suppressed_by_cooldown"),
		"SoundManager has no _sfx_suppressed_by_cooldown — the flag this whole file is about")
