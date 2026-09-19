extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## play_strike_element / play_weakness_flash fall back to _battle_player when their dedicated voice
## is absent. That call passed NO level, and _try_play_sfx_from_manifest leaves volume_db UNTOUCHED
## on NAN — so the fallback played at whatever trim the previous battle cue left behind.

const TRIMMED_CUE := "corruption_ap_flicker"  # -6.0 in _BATTLE_VOLUME_TRIM_DB
const STRIKE_ELEMENT := "fire"                # strike_fire is in the manifest

var _saved_strike: AudioStreamPlayer = null
var _saved_flash: AudioStreamPlayer = null


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _base(sm: Node) -> float:
	return float(sm.get_script().get_script_constant_map()["SFX_BATTLE_BASE_DB"])


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	## Stash BEFORE nulling: these are autoload singletons the rest of the suite shares.
	_saved_strike = sm._strike_player
	_saved_flash = sm._flash_player
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = _base(sm)


## Restore FIRST — a GDScript error below would abort this function and strand the nulls.
func after_each() -> void:
	var sm: Node = _sm()
	if sm != null:
		sm._strike_player = _saved_strike
		sm._flash_player = _saved_flash
		sm._battle_player.volume_db = _base(sm)
		sm._sfx_cooldowns.clear()
	SfxState.release_streams()


## FLOOR: every symbol this file reaches, so a rename reds here instead of passing vacuously.
func test_the_symbols_this_file_drives_all_exist() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	for m in ["play_battle", "play_strike_element", "play_weakness_flash"]:
		assert_true(sm.has_method(m), "SoundManager.%s is gone — this guard drives it" % m)
	for f in ["_strike_player", "_flash_player", "_battle_player", "_sfx_cooldowns"]:
		assert_true(f in sm, "SoundManager.%s is gone — this guard drives it" % f)
	assert_true(sm.get_script().get_script_constant_map().has("SFX_BATTLE_BASE_DB"),
		"SFX_BATTLE_BASE_DB is gone — every assert below reads it")


func test_a_strike_on_the_fallback_voice_plays_at_the_channel_level() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var base: float = _base(sm)
	sm.play_battle(TRIMMED_CUE)
	## CONTROL: without a non-base level here the assert below passes for the wrong reason.
	assert_ne(sm._battle_player.volume_db, base,
		"CONTROL: %s must leave a trim on _battle_player, or this arm measures nothing" % TRIMMED_CUE)
	sm._sfx_cooldowns.clear()
	sm._strike_player = null  # force the documented fallback
	sm.play_strike_element(STRIKE_ELEMENT)
	assert_eq(sm._battle_player.volume_db, base,
		"the strike fallback inherited %s's trim instead of the channel level" % TRIMMED_CUE)


func test_a_weakness_flash_on_the_fallback_voice_plays_at_the_channel_level() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var base: float = _base(sm)
	sm.play_battle(TRIMMED_CUE)
	assert_ne(sm._battle_player.volume_db, base,
		"CONTROL: %s must leave a trim on _battle_player, or this arm measures nothing" % TRIMMED_CUE)
	sm._sfx_cooldowns.clear()
	sm._flash_player = null  # force the documented fallback
	sm.play_weakness_flash()
	assert_eq(sm._battle_player.volume_db, base,
		"the weakness-flash fallback inherited %s's trim instead of the channel level" % TRIMMED_CUE)
