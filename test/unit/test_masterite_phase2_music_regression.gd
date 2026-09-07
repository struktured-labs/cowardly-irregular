extends GutTest

## Regression: boss_phase2_<role> tracks (warden/arbiter/tempo/curator) sat
## in the manifest but BattleScene never swapped to them when a Masterite
## escalated to phase 2. This pins the wiring at source level — instantiating
## BattleScene headless explodes on its autoload-driven _ready, so we check
## the hook is present and references the right meta keys + track family.

const BATTLE_SCENE_PATH: String = "res://src/battle/BattleScene.gd"
const MUSIC_MANIFEST_PATH: String = "res://data/music_manifest.json"

const EXPECTED_ROLES: Array[String] = ["warden", "arbiter", "tempo", "curator"]


func _load_source() -> String:
	var f: FileAccess = FileAccess.open(BATTLE_SCENE_PATH, FileAccess.READ)
	assert_not_null(f, "could not open BattleScene source")
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


func test_phase2_swap_hook_is_wired_into_action_executed() -> void:
	var src: String = _load_source()
	assert_true(src.contains("_check_masterite_phase2_music_swap"),
		"BattleScene must define the phase-2 swap helper")
	# The helper must be called from _on_action_executed (signal hook) so the
	# swap fires reliably each turn the boss acts.
	var idx: int = src.find("func _on_action_executed")
	assert_gt(idx, -1, "_on_action_executed must exist")
	var slice: String = src.substr(idx, 800)
	assert_true(slice.contains("_check_masterite_phase2_music_swap"),
		"_on_action_executed must invoke the phase-2 swap check")


func test_phase2_swap_helper_reads_correct_meta_and_emits_correct_track() -> void:
	var src: String = _load_source()
	var idx: int = src.find("func _check_masterite_phase2_music_swap")
	assert_gt(idx, -1, "phase-2 swap helper must be defined")
	var slice: String = src.substr(idx, 800)
	assert_true(slice.contains("masterite_battle_phase"),
		"helper must read the masterite_battle_phase meta written by BattleManager")
	assert_true(slice.contains("masterite_type"),
		"helper must read masterite_type so we know which role's track to swap to")
	assert_true(slice.contains("boss_phase2_%s"),
		"helper must construct the boss_phase2_<role> track id (per-role manifest entries)")
	assert_true(slice.contains("_masterite_phase2_swapped"),
		"helper must latch a one-shot flag so we do not re-swap every action")


func test_phase2_latch_is_declared_and_reset_at_battle_start() -> void:
	var src: String = _load_source()
	assert_true(src.contains("var _masterite_phase2_swapped"),
		"BattleScene must declare the _masterite_phase2_swapped state var")
	# Reset at battle music setup, alongside _is_danger_music.
	assert_true(src.contains("_masterite_phase2_swapped = false"),
		"latch must be cleared between battles or summons would inherit stale state")


func test_each_expected_phase2_track_exists_in_the_music_manifest() -> void:
	# Belt-and-suspenders: pin that the manifest entries the swap targets are
	# present. Catches the silent fall-through to dungeon_medieval if a track
	# id is renamed without updating the swap helper.
	var f: FileAccess = FileAccess.open(MUSIC_MANIFEST_PATH, FileAccess.READ)
	assert_not_null(f, "could not open music_manifest.json")
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "music_manifest root must be Dictionary")
	if not (parsed is Dictionary):
		return
	var root: Dictionary = parsed
	var tracks: Dictionary = root.get("tracks", {})
	for role in EXPECTED_ROLES:
		var key: String = "boss_phase2_%s" % role
		assert_true(tracks.has(key),
			"music_manifest.json must define %s for the phase-2 swap to land" % key)
