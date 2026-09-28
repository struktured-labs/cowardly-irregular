extends GutTest

## Regression: walking near a W1 boss cave swapped in `danger_medieval` ("party about to be wiped out") — the near-death bed — even for caves already cleared.
## struktured 2026-09-28: "danger music is sometimes played on overworld (like I'm half dead ... seems located next to regions of map)".

const OVERWORLD := "res://src/exploration/OverworldScene.gd"
const CAVE := Vector2(400, 400)

var _gs_story: Dictionary
var _gs_consts: Dictionary
var _holder: Node
var _player: Node2D
var _zone: DangerZone


func before_each() -> void:
	_gs_story = GameState.story_flags.duplicate(true)
	_gs_consts = GameState.game_constants.duplicate(true)
	GameState.story_flags.erase("rat_king_defeated")
	GameState.game_constants.erase("cutscene_flag_rat_king_defeated")
	GameState.game_constants.erase("rat_king_defeated")
	var df: Variant = GameState.game_constants.get("dungeon_flags", {})
	if df is Dictionary:
		(df as Dictionary).erase("rat_king_defeated")
	_holder = Node.new()
	add_child_autofree(_holder)
	_player = Node2D.new()
	_holder.add_child(_player)
	_zone = DangerZone.new()
	_holder.add_child(_zone)
	var pts: Array[Vector2] = [CAVE]
	var flags: Array[String] = ["rat_king_defeated"]
	_zone.setup(_holder, _player, pts, flags)


func after_each() -> void:
	GameState.story_flags = _gs_story
	GameState.game_constants = _gs_consts
	SoundManager.stop_music()
	SoundManager._current_area = ""


func _walk_to_cave_and_linger(frames: int = 40) -> void:
	_player.global_position = CAVE + Vector2(32, 0)
	for i in frames:
		_zone.process(0.05)


func _alpha() -> float:
	return _zone._vignette.color.a + _zone._current_intensity


func test_control_an_undefeated_cave_still_warns() -> void:
	_walk_to_cave_and_linger()
	assert_false(_zone.is_point_cleared(0), "CONTROL: rat king is not defeated in this fixture")
	assert_gt(_zone._current_intensity, 0.5,
		"CONTROL FAILED: standing next to an undefeated boss cave produced no warning — the probe below would be vacuous")


func test_a_cleared_cave_does_not_warn() -> void:
	GameState.story_flags["rat_king_defeated"] = true
	_walk_to_cave_and_linger()
	assert_true(_zone.is_point_cleared(0), "the Rat King's flag must clear the Whispering Cave point")
	assert_eq(_zone.nearest_live_distance(_player.global_position), INF, "a cleared cave must drop out of the proximity search")
	assert_almost_eq(_alpha(), 0.0, 0.001, "the vignette pulsed beside a cave whose boss is already dead")


func test_a_cave_cleared_mid_walk_goes_quiet_without_a_rebuild() -> void:
	_walk_to_cave_and_linger()
	assert_gt(_zone._current_intensity, 0.5, "CONTROL: warning is up before the flag flips")
	GameState.game_constants["dungeon_flags"] = {"rat_king_defeated": true}
	_walk_to_cave_and_linger(80)
	assert_lt(_zone._current_intensity, 0.01, "the zone read its flags once at setup — a cave cleared while the overworld is cached keeps warning")


func test_the_warning_never_swaps_in_the_near_death_bed() -> void:
	SoundManager.play_area_music("overworld")
	await get_tree().process_frame
	await get_tree().process_frame
	_walk_to_cave_and_linger()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(_zone._current_intensity, 0.5, "CONTROL: the warning must be at full strength for this arm to mean anything")
	assert_ne(SoundManager._current_area, "danger", "proximity to a cave switched the field to the `danger` area bed")
	var p: AudioStreamPlayer = SoundManager._music_player
	var path: String = p.stream.resource_path if p != null and p.stream != null else ""
	assert_false(path.contains("danger"), "the overworld is playing %s — the near-death bed, which tells the player they are dying" % path)


func test_every_cave_flag_has_a_writer() -> void:
	## A typo'd flag is never set, so that cave would warn forever — the exact symptom, arrived at from the other side.
	var flags: Dictionary = load(OVERWORLD).DANGER_CAVE_BOSS_FLAGS
	assert_eq(flags.size(), 6, "SCOPE: the W1 boss caves are Whispering + four dragons + the Warren")
	var src := ""
	for f in ["WhisperingCave", "FireDragonCave", "IceDragonCave", "LightningDragonCave", "ShadowDragonCave", "ContrarianDepths"]:
		src += FileAccess.get_file_as_string("res://src/maps/dungeons/%s.gd" % f)
	assert_gt(src.length(), 1000, "SCOPE: dungeon sources read back empty")
	for key in flags:
		assert_true(src.contains("\"%s\"" % flags[key]), "%s's clear flag %s is written by no W1 boss cave" % [key, flags[key]])
