extends GutTest

## `volume_db` PERSISTS on a shared AudioStreamPlayer, so a cue that sets an authored trim leaves it
## there. `play_battle` passes an explicit level on every call for exactly this reason — its own
## comment says so — and the other `_battle_player` callers passed NAN ("preserve"), inheriting it.

## ⚠️ LOUD_TRIM_CUE IS DRIVEN THROUGH play_battle DIRECTLY AND NO LIVE CALLER DOES THAT: advance_undo
## reaches _refuse_player via play_advance_state. It is the only POSITIVE trim authored, so it is the
## only way to cover that direction of play_battle's contract — the quiet arm is the one with live
## instances (7 of 8 trims reach _battle_player and every one of them is negative).
const LOUD_TRIM_CUE := "advance_undo"           # +6.0 in _BATTLE_VOLUME_TRIM_DB
const QUIET_TRIM_CUE := "corruption_ap_flicker" # -6.0, and play_battle("corruption_ap_flicker") is a real call site


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _base(sm: Node) -> float:
	return float(sm.get_script().get_script_constant_map()["SFX_BATTLE_BASE_DB"])


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = _base(sm)
	sm.reset_hit_chain()


## pitch_scale PERSISTS on the shared player — the defect 39fe0bded fixed. The ±5% jitter leaves it
## randomized, so this file must put it back or it hands the next file a detuned battle player.
func after_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._battle_player.pitch_scale = 1.0
	sm._battle_player.volume_db = _base(sm)
	sm._sfx_cooldowns.clear()


func test_a_hit_after_a_loud_trim_plays_at_the_channel_level() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var base: float = _base(sm)
	sm.play_battle(LOUD_TRIM_CUE)
	## The control: without a NON-base level here the assert below passes for the wrong reason.
	assert_gt(sm._battle_player.volume_db, base,
		"CONTROL: %s must raise the level, or this arm measures nothing" % LOUD_TRIM_CUE)
	sm._sfx_cooldowns.clear()
	sm.play_attack_hit("", false)
	assert_eq(sm._battle_player.volume_db, base,
		"a hit after %s played at %.2f dB instead of the %.2f dB channel level — the trim outlived its cue" % [LOUD_TRIM_CUE, sm._battle_player.volume_db, base])


func test_a_hit_after_a_quiet_trim_plays_at_the_channel_level() -> void:
	## The other direction, because a fix that clamps upward would pass the arm above and still
	## leave every hit 6 dB quiet during corruption.
	var sm: Node = _sm()
	if sm == null:
		return
	var base: float = _base(sm)
	sm.play_battle(QUIET_TRIM_CUE)
	assert_lt(sm._battle_player.volume_db, base,
		"CONTROL: %s must lower the level, or this arm measures nothing" % QUIET_TRIM_CUE)
	sm._sfx_cooldowns.clear()
	sm.play_attack_hit("", false)
	assert_eq(sm._battle_player.volume_db, base,
		"a hit after %s played at %.2f dB instead of the %.2f dB channel level" % [QUIET_TRIM_CUE, sm._battle_player.volume_db, base])


func test_a_trimmed_cue_still_gets_its_own_trim() -> void:
	## Anti-overcorrection: the trims are authored corrections and must still apply to their OWN
	## cue. A fix that made every battle cue play at the bare base would pass both arms above.
	var sm: Node = _sm()
	if sm == null:
		return
	var base: float = _base(sm)
	sm.play_battle(LOUD_TRIM_CUE)
	assert_ne(sm._battle_player.volume_db, base,
		"%s lost its authored trim — the level is now the bare base for every cue" % LOUD_TRIM_CUE)


func test_the_level_owner_is_one_function() -> void:
	## Two copies of `base + trim` is how the callers drifted apart to begin with: play_battle had
	## it and the rest passed NAN. Pins that the computation has a single owner.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/audio/SoundManager.gd")
	assert_ne(code, "", "CONTROL: SoundManager code must survive the comment strip")
	assert_true(code.contains("func _battle_level("),
		"the battle-level owner is gone — every caller is computing its own again")
	var inline: int = code.count("SFX_BATTLE_BASE_DB + float(_BATTLE_VOLUME_TRIM_DB")
	assert_eq(inline, 1,
		"base+trim is computed inline %d times outside the owner — that is how play_battle and play_attack_hit disagreed" % inline)


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT
	## a live derivation. Add a new sm. reach to this file and it is NOT covered until you add it
	## here. The sibling floors in this lane carry the same disclaimer, for the same reason.
	for method_name in ["play_battle", "play_attack_hit", "reset_hit_chain", "_battle_level"]:
		assert_true(sm.has_method(method_name),
			"SoundManager has no method %s — this file CALLS it" % method_name)
	for member_name in ["_battle_player", "_sfx_cooldowns"]:
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly" % member_name)
	var consts: Dictionary = sm.get_script().get_script_constant_map()
	assert_true(consts.has("SFX_BATTLE_BASE_DB"),
		"SFX_BATTLE_BASE_DB is gone — every level in this file derives from it")
	var trims = consts.get("_BATTLE_VOLUME_TRIM_DB", {})
	assert_true(trims is Dictionary and trims.has(LOUD_TRIM_CUE) and trims.has(QUIET_TRIM_CUE),
		"the two cues this file drives are no longer trimmed — it would pass while measuring nothing")
