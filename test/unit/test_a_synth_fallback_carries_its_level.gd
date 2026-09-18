extends GutTest

## _play_sound defaults to the PLAYER'S level, which is right only where the computed level equals
## the player's resting base. Four callers computed something else — a trim, or the death boost —
## and passed it to the manifest call only, so the synth branch silently used the wrong level.
##
## The generic status blip is the reachable one: it is the DESIGNED fallback for an unauthored
## status, and 32 ability effects reach it. Measured 2026-09-18, pre-fix: after corruption_ap_flicker
## it played at -12.00 against a -6.00 channel, inheriting whatever the previous battle cue left.

const TRIMMED_CUE := "corruption_ap_flicker"   # -6.0 in _BATTLE_VOLUME_TRIM_DB
const UNAUTHORED := "zz_no_such_status_at_all"
const DEATH_CUE := "enemy_death"               # in SOUNDS and the manifest, so it can be forced to synth
const BROKEN := "assets/audio/sfx/zz_this_file_does_not_exist.ogg"

var _saved: Dictionary = {}


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _c(sm: Node, n: String) -> float:
	return float(sm.get_script().get_script_constant_map()[n])


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = _c(sm, "SFX_BATTLE_BASE_DB")
	sm._death_player.volume_db = _c(sm, "DEATH_PLAYER_BASE_DB")


func after_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	if not _saved.is_empty():
		sm._sfx_manifest[DEATH_CUE] = _saved
		_saved = {}
	sm._sfx_stream_cache.erase(DEATH_CUE)
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = _c(sm, "SFX_BATTLE_BASE_DB")
	sm._death_player.volume_db = _c(sm, "DEATH_PLAYER_BASE_DB")
	sm._battle_player.pitch_scale = 1.0
	sm._death_player.pitch_scale = 1.0


func test_the_blip_does_not_inherit_the_previous_cues_trim() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var base: float = _c(sm, "SFX_BATTLE_BASE_DB")
	sm.play_battle(TRIMMED_CUE)
	assert_ne(sm._battle_player.volume_db, base,
		"CONTROL: %s must move the level off the base, or this arm has no stale value to inherit" % TRIMMED_CUE)
	sm._sfx_cooldowns.clear()
	sm.play_status(UNAUTHORED)
	assert_eq(sm._battle_player.volume_db - base, 0.0,
		"the generic status blip sits %+.2f dB off the channel base — it inherited the previous cue's trim instead of carrying its own level" % [
			sm._battle_player.volume_db - base])


func test_the_death_cue_keeps_its_boost_on_the_synth_path() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	var boost: float = _c(sm, "DEATH_CUE_BOOST_DB")
	assert_ne(boost, 0.0, "CONTROL: the boost is zero, so this arm cannot tell the paths apart")
	_saved = (sm._sfx_manifest[DEATH_CUE] as Dictionary).duplicate(true)
	sm._sfx_manifest[DEATH_CUE] = {"file": BROKEN}
	sm._sfx_stream_cache.erase(DEATH_CUE)
	sm._sfx_cooldowns.clear()
	sm.play_death(DEATH_CUE)
	assert_eq(sm._death_player.volume_db - _c(sm, "DEATH_PLAYER_BASE_DB"), boost,
		"the death cue fell to the synth path and sits %+.2f dB off its base instead of its authored %+.2f boost — the boost exists because the cry was being masked" % [
			sm._death_player.volume_db - _c(sm, "DEATH_PLAYER_BASE_DB"), boost])


func test_a_trimmed_cue_still_gets_its_own_trim() -> void:
	## Anti-overcorrection: a fix that forced every synth cue to the bare base would pass both arms
	## above and discard every authored trim.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_battle(TRIMMED_CUE)
	assert_ne(sm._battle_player.volume_db - _c(sm, "SFX_BATTLE_BASE_DB"), 0.0,
		"%s lost its authored trim — every battle cue now plays at the bare base" % TRIMMED_CUE)


func test_the_synth_level_has_one_owner() -> void:
	## Four callers had to remember this and one already had. Pins that they go through the helper,
	## so the next caller cannot forget it the way these did.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/audio/SoundManager.gd")
	assert_ne(code, "", "CONTROL: SoundManager code must survive the comment strip")
	assert_true(code.contains("func _synth_params("),
		"the synth-level owner is gone — every caller is folding its own level in again")
	var raw: int = code.count("_play_sound(_battle_player, SOUNDS[")
	raw += code.count("_play_sound(_death_player, SOUNDS[")
	raw += code.count("_play_sound(player, SOUNDS[")
	assert_eq(raw, 0,
		"%d synth call(s) still pass the RAW SOUNDS entry, so they take the player's resting level rather than the one their caller computed" % raw)


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen.
	for m in ["play_battle", "play_status", "play_death", "_battle_level", "_synth_params"]:
		assert_true(sm.has_method(m), "SoundManager has no method %s — this file CALLS it" % m)
	for n in ["_battle_player", "_death_player", "_sfx_cooldowns", "_sfx_manifest", "_sfx_stream_cache"]:
		assert_true(sm.get(n) != null, "SoundManager has no %s — this file reaches for it directly" % n)
	for c in ["SFX_BATTLE_BASE_DB", "DEATH_PLAYER_BASE_DB", "DEATH_CUE_BOOST_DB", "_BATTLE_VOLUME_TRIM_DB"]:
		assert_true((sm.get_script().get_script_constant_map() as Dictionary).has(c),
			"%s is gone — this file's arms read it directly" % c)
