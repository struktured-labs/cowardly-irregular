extends GutTest

## SFX players are SHARED. `_try_play_sfx_from_manifest` writes `pitch_scale` on every file cue —
## the combo bias times a ±5% jitter — and `_play_sound` never reset it, so a procedural cue played
## at whatever the previous file cue left. Measured 1.1013 after one biased hit.

const BIASED := 1.12  # COMBO_PITCH_CAP's ceiling, what play_attack_hit passes at a full ramp
const FILE_CUE := "attack_hit"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._battle_player.pitch_scale = 1.0


func test_a_synth_cue_plays_at_its_own_pitch() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## Arrange the hazard: a file cue leaves a biased pitch on the shared player.
	var played: bool = sm._try_play_sfx_from_manifest(sm._battle_player, FILE_CUE, NAN, BIASED)
	assert_true(played, "CONTROL: %s must sound, or nothing set a pitch to inherit" % FILE_CUE)
	## The control that makes the assert below mean something: without a NON-1.0 pitch here,
	## a passing result proves nothing — 1.0 would be the untouched default.
	assert_gt(sm._battle_player.pitch_scale, 1.0,
		"CONTROL: the file cue must leave a biased pitch, or this file measures nothing")
	sm._sfx_cooldowns.clear()
	sm._play_sound(sm._battle_player, {"freq": 440.0, "duration": 0.05, "type": "blip"})
	assert_eq(sm._battle_player.pitch_scale, 1.0,
		"a synth cue inherited the previous FILE cue's pitch (%.4f) — the procedural path biases by FREQUENCY, so this applies the bias twice" % sm._battle_player.pitch_scale)


func test_a_file_cue_still_gets_its_own_pitch() -> void:
	## Anti-overcorrection: the reset belongs to the procedural path only. A file cue must still
	## carry its combo bias, or the ramp this lane shipped in .393 goes silent in the other sense.
	var sm: Node = _sm()
	if sm == null:
		return
	sm._play_sound(sm._battle_player, {"freq": 440.0, "duration": 0.05, "type": "blip"})
	assert_eq(sm._battle_player.pitch_scale, 1.0, "CONTROL: the synth cue must leave 1.0 to start from")
	sm._sfx_cooldowns.clear()
	var played: bool = sm._try_play_sfx_from_manifest(sm._battle_player, FILE_CUE, NAN, BIASED)
	assert_true(played, "CONTROL: %s must sound" % FILE_CUE)
	assert_gt(sm._battle_player.pitch_scale, 1.0,
		"a file cue lost its combo bias — the reset was applied to the wrong path")


func test_the_reset_is_per_play_not_once() -> void:
	## A reset that only fires on the first synth cue would pass the arm above and still detune
	## every later one. Drives the alternation twice.
	var sm: Node = _sm()
	if sm == null:
		return
	for i in 2:
		sm._sfx_cooldowns.clear()
		assert_true(sm._try_play_sfx_from_manifest(sm._battle_player, FILE_CUE, NAN, BIASED),
			"CONTROL: %s must sound on pass %d" % [FILE_CUE, i])
		sm._sfx_cooldowns.clear()
		sm._play_sound(sm._battle_player, {"freq": 440.0, "duration": 0.05, "type": "blip"})
		assert_eq(sm._battle_player.pitch_scale, 1.0,
			"pass %d: the synth cue kept a biased pitch — the reset does not fire on every play" % i)


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## Rung-3 floor: a renamed member raises at runtime and ABORTS the arm, which scores PASSING if
	## anything asserted first. get()/has_method ANSWER instead of raising.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT
	## a live derivation. Add a new sm. reach to this file and it is NOT covered until you add it
	## here. The sibling floors in this lane carry the same disclaimer, for the same reason.
	for method_name in ["_try_play_sfx_from_manifest", "_play_sound"]:
		assert_true(sm.has_method(method_name),
			"SoundManager has no method %s — this file CALLS it, and a rename would abort its arms silently" % method_name)
	## get(), not the property list: _sfx_cooldowns is an instance var and never null after _ready,
	## while get_property_list() omits `static var` entirely (measured 2026-09-17).
	for member_name in ["_battle_player", "_sfx_cooldowns"]:
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly" % member_name)
	var consts: Dictionary = sm.get_script().get_script_constant_map()
	assert_true(consts.has("COMBO_PITCH_CAP"),
		"COMBO_PITCH_CAP is gone — BIASED in this file was derived from it and now describes nothing")
