extends GutTest

## Regression test for the 2026-07-25 playtest report:
## "got stuck in castle harmonia btw, you cant go up or down any labeled place
##  in the dungeon/village modes. seems busted tbh."
##
## Stairs are plain Area2D sensors fired by body_entered. For that to work FOUR
## things must all hold, and each fails silently on its own:
##   1. the floor layout carries the U / D markers
##   2. the marker chars parse to a WALKABLE tile (a wall = unreachable trigger)
##   3. an Area2D actually gets built at the marker position
##   4. its collision_mask includes the player's collision_layer (2)
##
## Verified 2026-07-25: CastleHarmonia's layouts do carry U/D on every floor and
## _char_to_tile_type maps both to CAVE_FLOOR, so 1 and 2 hold. This pins all
## four so the next regression names which link broke instead of presenting as
## "the dungeon is busted".

const CASTLE := "res://src/maps/dungeons/CastleHarmonia.gd"
const CAVE := "res://src/maps/dungeons/DragonCave.gd"
## OverworldPlayer sets collision_layer = 2; a stairs sensor must mask that bit.
const PLAYER_LAYER_BIT := 2


func _layouts(path: String) -> Dictionary:
	var src := FileAccess.get_file_as_string(path)
	var out := {}
	for floor_num in range(1, 7):
		var re := RegEx.new()
		re.compile("\\n\\t*%d:\\s*\\[(?<body>[\\s\\S]*?)\\n\\t*\\]," % floor_num)
		var m := re.search(src)
		if m == null:
			continue
		var rows: Array = []
		var rre := RegEx.new()
		rre.compile('"([^"]*)"')
		for rm in rre.search_all(m.get_string("body")):
			rows.append(rm.get_string(1))
		if rows.size() > 0:
			out[floor_num] = rows
	return out


func test_castle_floors_all_carry_stair_markers() -> void:
	var layouts := _layouts(CASTLE)
	assert_gt(layouts.size(), 0, "CastleHarmonia must define floor layouts")
	for floor_num in layouts:
		var joined := "".join(layouts[floor_num])
		# Every floor needs a way DOWN; only the top floor may omit UP.
		assert_true(
			joined.contains("D"),
			"castle floor %d has no 'D' marker — nothing to walk onto to descend, which is "
			% floor_num + "how a player gets stranded"
		)


func test_stair_marker_chars_parse_to_walkable_floor() -> void:
	# A stairs trigger sitting under a wall tile can never fire: the player is
	# blocked before body_entered. This is exactly the inn's "Upstairs" defect,
	# where U was documented as a BLOCKER.
	var src := FileAccess.get_file_as_string(CAVE)
	var start := src.find("func _char_to_tile_type")
	assert_gt(start, 0, "_char_to_tile_type must exist")
	var body := src.substr(start, 420)
	# Check the WALL branch specifically: the line that returns CAVE_WALL must not list U or D.
	var wall_markers: Array = []
	for line in body.split("\n"):
		if line.contains("CAVE_WALL"):
			wall_markers.append(line)
	assert_gt(wall_markers.size(), 0, "there must be a CAVE_WALL branch to check against")
	for marker in ["U", "D"]:
		for line in wall_markers:
			assert_false(
				line.contains('"%s"' % marker),
				"'%s' must not map to CAVE_WALL — a walled stairs tile is an unreachable trigger" % marker
			)
	assert_true(body.contains('"U"') and body.contains('"D"'),
		"both stair markers must be handled explicitly, not fall through the default")


func test_stairs_sensor_masks_the_player_collision_layer() -> void:
	# The single most silent failure: geometry, tiles and handler all correct,
	# but the sensor never sees the player because the mask bit is wrong.
	var src := FileAccess.get_file_as_string(CAVE)
	var start := src.find("func _setup_transition_collision")
	assert_gt(start, 0, "_setup_transition_collision must exist")
	var body := src.substr(start, 300)
	assert_true(
		body.contains("collision_mask = %d" % PLAYER_LAYER_BIT),
		"stairs sensors must mask layer %d — OverworldPlayer is on collision_layer 2, and a "
		% PLAYER_LAYER_BIT + "mismatched mask makes every staircase in every dungeon inert"
	)
	assert_true(body.contains("monitoring = true"), "a non-monitoring Area2D never emits body_entered")


func test_both_stair_handlers_are_connected_to_body_entered() -> void:
	var src := FileAccess.get_file_as_string(CAVE)
	assert_true(src.contains("up_trans.body_entered.connect(_on_stairs_up_entered)"),
		"StairsUp must be wired to body_entered")
	assert_true(src.contains("down_trans.body_entered.connect(_on_stairs_down_entered)"),
		"StairsDown must be wired to body_entered")


func test_transitioning_latch_is_always_released() -> void:
	# _transitioning gates BOTH handlers. If any path sets it true without
	# clearing it, every staircase in that dungeon goes dead for the rest of the
	# session — which presents exactly as "you can't go up or down anywhere".
	var src := FileAccess.get_file_as_string(CAVE)
	var sets := src.count("_transitioning = true")
	var clears := src.count("_transitioning = false")
	assert_gt(clears, 0, "_transitioning must be released somewhere")
	assert_true(
		clears >= sets,
		"every path that sets _transitioning must clear it (%d set / %d cleared) — an unreleased "
		% [sets, clears] + "latch kills every staircase in the dungeon"
	)


func test_floor_one_descent_targets_the_overworld_exit() -> void:
	# Floor 1's D is the way OUT. If it doesn't resolve to a real exit map the
	# player is sealed in the dungeon with no recourse but a reload.
	var src := FileAccess.get_file_as_string(CAVE)
	assert_true(
		src.contains("exit_trans.target_map = overworld_exit_map"),
		"floor 1 stairs-down must route to overworld_exit_map — this is the only way out"
	)
	assert_true(
		src.contains("exit_trans.require_interaction = false"),
		"the exit must be a walk-on sensor; a press-gate that nobody prompts for reads as a locked door"
	)
