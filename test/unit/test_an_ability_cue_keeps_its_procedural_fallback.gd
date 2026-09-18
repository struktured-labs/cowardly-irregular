extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## play_ability was the ONE world-prefix caller without the `world_key != sound_key` guard. In W1
## the prefix is "", so it called the manifest helper TWICE with the same key. The helper stamps the
## cooldown BEFORE loading, so a first attempt that stamps and then fails leaves the second answering
## `true` — HANDLED, not HEARD — and play_ability returned before its procedural fallback.
## Measured 2026-09-17: the same broken entry went silent here and fell back correctly via play_battle.

const KEY := "ability_heal"            # authored AND in SOUNDS — the fallback only exists for these
const PROBE_ABILITY := "zz_probe_ability_cue"
const BROKEN_FILE := "assets/audio/sfx/zz_this_file_does_not_exist.ogg"

var _saved_entry: Dictionary = {}
## ⛔ The world suffix lives on the AUTOLOAD and persists for the whole GUT run. This file drove it
## as a PRECONDITION and a prior file in the .412 batch left "abstract" there — the control refused,
## correctly, and red the gate. A file must ESTABLISH the state its premise needs, not assert that
## someone else left it. Measured: entering at w6_, pre-fix is Failing 3, this is Passing 6.
var _saved_area: String = ""
## "medieval", not "" — this is the field's LIVE default, and after_each writes it back
## unconditionally. A wrong default here is only unreachable because the snapshot sits directly
## under the null guard; a reorder makes it a restore that CORRUPTS rather than one that skips.
var _saved_suffix: String = "medieval"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


## A manifest entry that resolves, stamps the cooldown, then fails to load — the shape a web/PCK
## export produces. NO fallback_to, so the manifest path is genuinely exhausted rather than rerouted.
func _break_entry(sm: Node) -> void:
	_saved_entry = (sm._sfx_manifest[KEY] as Dictionary).duplicate(true)
	sm._sfx_manifest[KEY] = {"file": BROKEN_FILE}
	sm._sfx_stream_cache.erase(KEY)
	sm._sfx_cooldowns.clear()


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	_saved_area = str(sm._current_area)
	_saved_suffix = str(sm._current_world_suffix)
	## W1 defaults, which are exactly what make _get_world_sfx_prefix() return "" — the premise.
	sm._current_area = ""
	sm._current_world_suffix = "medieval"
	sm._sfx_cooldowns.clear()
	sm._sfx_stream_cache.erase(KEY)
	sm._ability_sounds[PROBE_ABILITY] = KEY
	sm._ability_player.stream = null


func after_each() -> void:
	## FIRST, not last: a GDScript error in the restores below aborts after_each, and a release that
	## sits at the bottom is then skipped. Self-contained, so it needs nothing above it.
	SfxState.release_streams()
	var sm: Node = _sm()
	if sm == null:
		return
	if not _saved_entry.is_empty():
		sm._sfx_manifest[KEY] = _saved_entry
		_saved_entry = {}
	sm._sfx_stream_cache.erase(KEY)
	sm._ability_sounds.erase(PROBE_ABILITY)
	sm._sfx_cooldowns.clear()
	sm._current_area = _saved_area
	sm._current_world_suffix = _saved_suffix
	## pitch_scale PERSISTS on the shared player — the defect 39fe0bded fixed. The ±5% jitter in
	## _try_play_sfx_from_manifest leaves it randomized, so a file that plays anything must put it back.
	sm._ability_player.pitch_scale = 1.0
	sm._battle_player.pitch_scale = 1.0


func test_this_files_scenario_is_the_one_it_claims_to_drive() -> void:
	## Every arm below depends on all three. If the lane moves to a prefixed world, or KEY loses its
	## procedural twin, the arms would pass while measuring a path that no longer exists.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_eq(sm._get_world_sfx_prefix(), "",
		"CONTROL: before_each did not establish the W1 world state — the prefix is not empty, so world_key != sound_key and this file drives nothing")
	assert_true(sm._sfx_manifest.has(KEY), "CONTROL: %s must be authored" % KEY)
	var sounds: Dictionary = sm.get_script().get_script_constant_map()["SOUNDS"]
	assert_true(sounds.has(KEY),
		"CONTROL: %s has no SOUNDS entry, so there is no procedural fallback to lose" % KEY)


func test_a_broken_ability_entry_still_reaches_the_procedural_fallback() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	_break_entry(sm)
	sm.play_ability(PROBE_ABILITY)
	assert_not_null(sm._ability_player.stream,
		"an ability whose file failed to load played NOTHING — the second manifest attempt answered off the cooldown stamp the first one wrote, and the procedural fallback was skipped")
	assert_true(sm._ability_player.stream is AudioStreamGenerator,
		"the ability player holds a %s, not the generated fallback stream" % [sm._ability_player.stream])


func test_a_guarded_sibling_recovers_from_the_same_broken_entry() -> void:
	## The comparison that makes the arm above a DEFECT rather than a design choice: play_battle has
	## carried this guard all along, and on the identical entry it reaches the synth.
	var sm: Node = _sm()
	if sm == null:
		return
	_break_entry(sm)
	sm._battle_player.stream = null
	sm.play_battle(KEY)
	assert_true(sm._battle_player.stream is AudioStreamGenerator,
		"play_battle no longer recovers either — the fallback this file compares against is gone, so the arm above proves nothing")


func test_a_healthy_ability_entry_still_plays_its_file() -> void:
	## Anti-overcorrection: a fix that routed every ability to the synth would pass both arms above
	## and silently discard 346 authored cues.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_ability(PROBE_ABILITY)
	assert_not_null(sm._ability_player.stream, "CONTROL: %s never sounded at all" % KEY)
	assert_false(sm._ability_player.stream is AudioStreamGenerator,
		"a healthy authored ability cue played the PROCEDURAL stream — the manifest path is being skipped")


func test_every_world_prefix_caller_carries_the_guard() -> void:
	## Derived, not hand-listed: play_ability was the odd one out for months precisely because the
	## three that were right looked like the whole set.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/audio/SoundManager.gd")
	assert_ne(code, "", "CONTROL: SoundManager code must survive the comment strip")
	var sites: int = code.count("_get_world_sfx_prefix() + sound_key")
	var guards: int = code.count("world_key != sound_key and _try_play_sfx_from_manifest")
	assert_gt(sites, 0, "CONTROL: no world-prefix call site found — the pattern was renamed")
	assert_eq(guards, sites,
		"%d of %d world-prefix callers guard world_key != sound_key; an unguarded one stamps the cooldown and then answers its own stamp" % [guards, sites])


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT
	## a live derivation. Add a new sm. reach to this file and it is NOT covered until you add it
	## here. The sibling floors in this lane carry the same disclaimer, for the same reason.
	for method_name in ["play_ability", "play_battle", "_get_world_sfx_prefix"]:
		assert_true(sm.has_method(method_name), "SoundManager has no method %s — this file CALLS it" % method_name)
	for member_name in ["_ability_player", "_battle_player", "_ability_sounds", "_sfx_cooldowns", "_sfx_manifest", "_sfx_stream_cache"]:
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly" % member_name)
	## The fixture WRITES these two; a rename would silently stop the file establishing its premise.
	for world_member in ["_current_area", "_current_world_suffix"]:
		assert_true(sm.get(world_member) != null,
			"SoundManager has no %s — before_each writes it to establish this file's premise" % world_member)
	assert_true(sm.get_script().get_script_constant_map().has("SOUNDS"),
		"SOUNDS is gone — the procedural fallback this whole file is about")
