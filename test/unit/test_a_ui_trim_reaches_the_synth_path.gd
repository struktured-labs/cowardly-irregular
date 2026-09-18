extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## play_ui computes SFX_UI_BASE_DB + trim and passed it only to the MANIFEST call. Wherever the
## synth path runs — a cue whose file fails to load, or a trim authored for a procedural-only cue —
## the level fell back to the bare base and the authored trim was silently dropped.
## Same both-paths asymmetry as play_battle_scaled and play_ability, third instance in this file.

const TRIMMED := "menu_select"          # -2.5 in _UI_VOLUME_TRIM_DB, and in BOTH manifest and SOUNDS
const UNTRIMMED := "grind_stop_hp"      # procedural-only, no trim — the anti-overcorrection arm
const BROKEN_FILE := "assets/audio/sfx/zz_this_file_does_not_exist.ogg"

var _saved: Dictionary = {}


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _c(sm: Node, name: String) -> Variant:
	return sm.get_script().get_script_constant_map()[name]


## Deltas, never absolutes: asserting `base + trim` would agree with the product only while the
## constants hold their current values, and a retune of either is an ordinary mix change.
func _ui_base(sm: Node) -> float:
	return float(_c(sm, "SFX_UI_BASE_DB"))


func _trim(sm: Node, key: String) -> float:
	return float((_c(sm, "_UI_VOLUME_TRIM_DB") as Dictionary).get(key, 0.0))


## Force the synth path for a cue that normally loads: break its manifest entry, no fallback_to.
func _break(sm: Node, key: String) -> void:
	_saved = (sm._sfx_manifest[key] as Dictionary).duplicate(true)
	sm._sfx_manifest[key] = {"file": BROKEN_FILE}
	sm._sfx_stream_cache.erase(key)
	sm._sfx_cooldowns.clear()


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._ui_player.volume_db = _ui_base(sm)


func after_each() -> void:
	## FIRST, not last: a GDScript error in the restores below aborts after_each, and a release that
	## sits at the bottom is then skipped. Self-contained, so it needs nothing above it.
	SfxState.release_streams()
	var sm: Node = _sm()
	if sm == null:
		return
	if not _saved.is_empty():
		sm._sfx_manifest[TRIMMED] = _saved
		_saved = {}
	sm._sfx_stream_cache.erase(TRIMMED)
	sm._sfx_cooldowns.clear()
	sm._ui_player.volume_db = _ui_base(sm)
	sm._ui_player.pitch_scale = 1.0


func test_this_files_premise_still_holds() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_ne(_trim(sm, TRIMMED), 0.0,
		"CONTROL: %s is no longer trimmed, so every arm below would measure a trim of zero" % TRIMMED)
	assert_true((_c(sm, "SOUNDS") as Dictionary).has(TRIMMED),
		"CONTROL: %s left SOUNDS, so the synth path this file drives no longer exists for it" % TRIMMED)


func test_a_trimmed_cue_keeps_its_trim_on_the_synth_path() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	_break(sm, TRIMMED)
	sm.play_ui(TRIMMED)
	assert_eq(sm._ui_player.volume_db - _ui_base(sm), _trim(sm, TRIMMED),
		"a trimmed UI cue falling to the synth path sits %+.2f dB from the channel base instead of its authored %+.2f — the trim was computed and then dropped" % [
			sm._ui_player.volume_db - _ui_base(sm), _trim(sm, TRIMMED)])


func test_an_untrimmed_cue_still_sits_on_the_bare_base() -> void:
	## Anti-overcorrection: a fix that applied some level unconditionally would pass the arm above
	## and quietly move every untrimmed procedural UI cue.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_false(sm._sfx_manifest.has(UNTRIMMED),
		"CONTROL: %s is authored now, so this arm no longer reaches the synth path" % UNTRIMMED)
	sm.play_ui(UNTRIMMED)
	assert_eq(sm._ui_player.volume_db - _ui_base(sm), 0.0,
		"an untrimmed procedural UI cue sits %+.2f dB off the base" % [sm._ui_player.volume_db - _ui_base(sm)])


func test_the_manifest_path_is_unchanged() -> void:
	## The half that already worked. A fix that moved the trim to the synth path only would pass
	## the arms above and break every UI cue that loads.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_ui(TRIMMED)
	assert_eq(sm._ui_player.volume_db - _ui_base(sm), _trim(sm, TRIMMED),
		"the manifest path lost the trim it has always applied (%+.2f off base, expected %+.2f)" % [
			sm._ui_player.volume_db - _ui_base(sm), _trim(sm, TRIMMED)])


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT
	## a live derivation. Add a new sm. reach to this file and it is NOT covered until you add it here.
	assert_true(sm.has_method("play_ui"), "SoundManager has no method play_ui — this file is about it")
	for member_name in ["_ui_player", "_sfx_cooldowns", "_sfx_manifest", "_sfx_stream_cache"]:
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly" % member_name)
	for c in ["SFX_UI_BASE_DB", "_UI_VOLUME_TRIM_DB", "SOUNDS"]:
		assert_true((sm.get_script().get_script_constant_map() as Dictionary).has(c),
			"%s is gone — this file's arms read it directly" % c)
