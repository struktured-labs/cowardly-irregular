extends GutTest

## `volume_db` is CHANNEL state, not a per-play argument: every SFX player is built at a
## design-intent base and `set_sfx_volume` re-asserts those "in case a caller mutated them".
## `_play_sound` was that caller — it defaulted to 0.0 and overwrote the base.

const UI_ONLY_CUE := "grind_stop_hp"  # procedural-only: no manifest entry, so the synth path is LIVE
const FILE_CUE := "attack_hit"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _const(sm: Node, name: String) -> float:
	return float(sm.get_script().get_script_constant_map().get(name, NAN))


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._ui_player.volume_db = _const(sm, "SFX_UI_BASE_DB")
	sm._battle_player.volume_db = _const(sm, "SFX_BATTLE_BASE_DB")


func test_a_procedural_only_cue_plays_at_its_channel_level() -> void:
	## The player-facing half. These six grind cues have no manifest entry, so they ALWAYS take
	## the synth path — at 0.0 they sat 16 dB above every other menu sound.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var ui_base: float = _const(sm, "SFX_UI_BASE_DB")
	assert_false(sm._sfx_manifest.has(UI_ONLY_CUE),
		"CONTROL: %s must have NO manifest entry, or this arm never reaches the synth path" % UI_ONLY_CUE)
	assert_true(sm.SOUNDS.has(UI_ONLY_CUE), "CONTROL: %s must be in SOUNDS" % UI_ONLY_CUE)
	sm.play_ui(UI_ONLY_CUE)
	assert_eq(sm._ui_player.volume_db, ui_base,
		"a procedural-only UI cue played at %.2f dB on a channel designed for %.2f — %.1f dB above every menu blip" % [sm._ui_player.volume_db, ui_base, sm._ui_player.volume_db - ui_base])


func test_a_synth_cue_does_not_move_the_channel_base() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	var base: float = _const(sm, "SFX_BATTLE_BASE_DB")
	assert_eq(sm._battle_player.volume_db, base, "CONTROL: start at the channel base")
	sm._play_sound(sm._battle_player, {"freq": 440.0, "duration": 0.05, "type": "blip"})
	assert_eq(sm._battle_player.volume_db, base,
		"a synth cue moved the battle channel to %.2f dB — volume_db persists on a SHARED player" % sm._battle_player.volume_db)


func test_a_preserving_file_cue_still_gets_the_base_after_a_synth_cue() -> void:
	## The leak: play_attack_hit passes NAN, documented as "preserves the player's channel base
	## volume". It preserved whatever the last synth cue left instead.
	var sm: Node = _sm()
	if sm == null:
		return
	var base: float = _const(sm, "SFX_BATTLE_BASE_DB")
	sm._play_sound(sm._battle_player, {"freq": 440.0, "duration": 0.05, "type": "blip"})
	sm._sfx_cooldowns.clear()
	var played: bool = sm._try_play_sfx_from_manifest(sm._battle_player, FILE_CUE, NAN, 1.0)
	assert_true(played, "CONTROL: %s must sound, or nothing read the level" % FILE_CUE)
	assert_eq(sm._battle_player.volume_db, base,
		"a NAN-override file cue inherited %.2f dB from the preceding synth cue instead of the %.2f dB base" % [sm._battle_player.volume_db, base])


func test_an_explicit_level_is_still_honoured() -> void:
	## Anti-overcorrection: defaulting to the channel must not swallow a level a caller DID pass.
	## play_crit's sub-thud and play_battle_scaled both rely on this.
	var sm: Node = _sm()
	if sm == null:
		return
	sm._play_sound(sm._battle_player, {"freq": 440.0, "duration": 0.05, "type": "blip", "volume_db": -30.0})
	assert_eq(sm._battle_player.volume_db, -30.0,
		"an explicit volume_db in params was ignored — the default swallowed a real argument")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## Rung-3 floor: a renamed member aborts the arm AFTER its first assert and scores PASSING.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT
	## a live derivation. Add a new sm. reach to this file and it is NOT covered until you add it
	## here. The sibling floors in this lane carry the same disclaimer, for the same reason.
	for method_name in ["_play_sound", "_try_play_sfx_from_manifest", "play_ui"]:
		assert_true(sm.has_method(method_name),
			"SoundManager has no method %s — this file CALLS it" % method_name)
	for member_name in ["_ui_player", "_battle_player", "_sfx_cooldowns", "_sfx_manifest"]:
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly" % member_name)
	var consts: Dictionary = sm.get_script().get_script_constant_map()
	## SOUNDS added 2026-09-17: `sm.SOUNDS.has(...)` at :38 sits AFTER two asserts in its arm, so a
	## rename aborted it at rung 3 — measured EC=0 · Passing 5 with a SCRIPT ERROR on stderr only.
	for c in ["SFX_UI_BASE_DB", "SFX_BATTLE_BASE_DB", "SOUNDS"]:
		assert_true(consts.has(c),
			"%s is gone — this file's arms read it directly, so its absence makes them vacuous" % c)
