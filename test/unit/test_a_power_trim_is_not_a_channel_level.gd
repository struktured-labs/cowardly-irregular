extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## EffectSystem scales an impact by power with `lerp(-3.0, 3.0, ...)` — a TRIM, per its own comment
## ("more powerful = slightly louder"). play_battle_scaled forwarded it as volume_db_override, which
## _try_play_sfx_from_manifest writes as the player's ABSOLUTE level. Measured 2026-09-17: the
## weakest spell landed +3 dB over the -6 dB battle channel and the strongest +9, and it persisted.

const FILE_CUE := "strike_fire"          # manifest path
const PROCEDURAL_CUE := "grind_stop_hp"  # in SOUNDS, not in the manifest — the fallback path
const MAX_POWER_TRIM := 3.0              # lerp(-3, 3) at power == POWER_MAX
const MIN_POWER_TRIM := -3.0             # ... at power == POWER_MIN
const SENTINEL := -50.0                  # a level no cue sets, so "never sounded" cannot read as a pass


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _base(sm: Node) -> float:
	return float(sm.get_script().get_script_constant_map()["SFX_BATTLE_BASE_DB"])


## The channel level for THIS cue, from the product's own owner. Asserting against the bare base
## would be a coincidence: it equals the level only while the cue carries no _BATTLE_VOLUME_TRIM_DB
## entry, so an authored trim — a legitimate mix change — would red these arms on correct code.
## What the fix actually claims is a RELATIONSHIP: the power value is ADDED to whatever the channel
## level is. Asserting the delta says that and survives any retune of the base or the trim.
func _level(sm: Node, cue: String) -> float:
	return float(sm._battle_level(cue))


## Park the player somewhere no cue would leave it: if the cue never sounds, the asserts below read
## SENTINEL and say so, instead of finding the base already there and passing for the wrong reason.
func _arm(sm: Node) -> void:
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = SENTINEL


func after_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = _base(sm)
	## Shared players keep their stream after a cue ends; sound_state.gd owns the music surface, not this one.
	SfxState.release_streams()


func test_a_max_power_spell_plays_a_trim_above_the_channel_not_an_absolute_level() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var base: float = _base(sm)
	_arm(sm)
	sm.play_battle_scaled(FILE_CUE, MAX_POWER_TRIM, 1.0)
	assert_ne(sm._battle_player.volume_db, SENTINEL,
		"CONTROL: %s never sounded, so this arm measured nothing" % FILE_CUE)
	assert_eq(sm._battle_player.volume_db - _level(sm, FILE_CUE), MAX_POWER_TRIM,
		"the strongest spell sits %.2f dB from its channel level; the power value is a TRIM so it must be exactly %+.2f (a raw override lands at %.2f absolute, ignoring the level entirely)" % [
			sm._battle_player.volume_db - _level(sm, FILE_CUE), MAX_POWER_TRIM, sm._battle_player.volume_db])


func test_a_min_power_spell_lands_below_the_channel_level() -> void:
	## The other direction. A fix that only subtracted the overshoot at the top would pass the arm
	## above and still leave the weakest spell 3 dB louder than an ordinary hit.
	var sm: Node = _sm()
	if sm == null:
		return
	var base: float = _base(sm)
	_arm(sm)
	sm.play_battle_scaled(FILE_CUE, MIN_POWER_TRIM, 1.0)
	assert_ne(sm._battle_player.volume_db, SENTINEL, "CONTROL: %s never sounded" % FILE_CUE)
	assert_lt(sm._battle_player.volume_db, base,
		"the weakest spell played at %.2f dB, at or above the %.2f dB channel level — a negative trim must go DOWN from the channel, not up from zero" % [
			sm._battle_player.volume_db, base])
	assert_eq(sm._battle_player.volume_db - _level(sm, FILE_CUE), MIN_POWER_TRIM,
		"the weakest spell sits %.2f dB from its channel level, not %+.2f" % [sm._battle_player.volume_db - _level(sm, FILE_CUE), MIN_POWER_TRIM])


func test_the_default_volume_means_no_trim() -> void:
	## The signature's `volume_db: float = 0.0` only reads as a sane default once it is a TRIM —
	## as an absolute level 0.0 is 6 dB over a channel whose base is -6.
	var sm: Node = _sm()
	if sm == null:
		return
	_arm(sm)
	sm.play_battle_scaled(FILE_CUE)
	assert_ne(sm._battle_player.volume_db, SENTINEL, "CONTROL: %s never sounded" % FILE_CUE)
	assert_eq(sm._battle_player.volume_db - _level(sm, FILE_CUE), 0.0,
		"an untrimmed scaled cue sits %.2f dB from its channel level instead of ON it" % [sm._battle_player.volume_db - _level(sm, FILE_CUE)])


func test_the_procedural_fallback_takes_the_same_level() -> void:
	## play_battle_scaled has TWO paths and the bug was on both. A fix to the manifest branch alone
	## passes every arm above while a synth cue keeps the old absolute level.
	var sm: Node = _sm()
	if sm == null:
		return
	var base: float = _base(sm)
	assert_false(sm._sfx_manifest.has(PROCEDURAL_CUE),
		"CONTROL: %s is authored now, so this arm no longer reaches the procedural branch" % PROCEDURAL_CUE)
	_arm(sm)
	sm.play_battle_scaled(PROCEDURAL_CUE, MAX_POWER_TRIM, 1.0)
	assert_ne(sm._battle_player.volume_db, SENTINEL, "CONTROL: %s never sounded" % PROCEDURAL_CUE)
	assert_eq(sm._battle_player.volume_db - _level(sm, PROCEDURAL_CUE), MAX_POWER_TRIM,
		"the procedural branch sits %.2f dB from its channel level, not %+.2f — only the manifest branch was fixed" % [
			sm._battle_player.volume_db - _level(sm, PROCEDURAL_CUE), MAX_POWER_TRIM])


func test_the_caller_still_passes_a_relative_trim() -> void:
	## This file's whole premise. If EffectSystem is ever changed to pass an absolute level, the
	## addition here would double-apply — and every arm above would still pass, because they drive
	## play_battle_scaled directly. The premise has to be pinned where it is authored.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/battle/EffectSystem.gd")
	assert_ne(code, "", "CONTROL: EffectSystem code must survive the comment strip")
	## Leading `= ` / `.` bracket each symbol: a prefix cannot supply them, because whatever the
	## prefix is sits between the anchor and the name (cowir-autogrind, measured 2026-09-17).
	assert_true(code.contains("= lerp(-3.0, 3.0,"),
		"EffectSystem no longer derives its volume as a symmetric trim around zero — play_battle_scaled adds it to the channel level and would now be wrong")
	assert_true(code.contains(".play_battle_scaled(sound_key, volume_db, pitch)"),
		"EffectSystem no longer feeds that value to play_battle_scaled — this file guards a path nothing takes")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## Rung-3 floor: a renamed member aborts an arm AFTER its first assert and scores PASSING.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT
	## a live derivation. Add a new sm. reach to this file and it is NOT covered until you add it
	## here. The sibling floors in this lane carry the same disclaimer, for the same reason.
	for method_name in ["play_battle_scaled", "_battle_level"]:
		assert_true(sm.has_method(method_name), "SoundManager has no method %s — this file CALLS it" % method_name)
	for member_name in ["_battle_player", "_sfx_cooldowns", "_sfx_manifest"]:
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly" % member_name)
	var consts: Dictionary = sm.get_script().get_script_constant_map()
	assert_true(consts.has("SFX_BATTLE_BASE_DB"),
		"SFX_BATTLE_BASE_DB is gone — every level in this file derives from it")
	assert_true(consts.has("SOUNDS") and (consts["SOUNDS"] as Dictionary).has(PROCEDURAL_CUE),
		"%s left SOUNDS — the procedural arm would reach no branch at all" % PROCEDURAL_CUE)
