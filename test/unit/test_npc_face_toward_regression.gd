extends GutTest

## NPC turn-to-face-player on interact (struktured playtest, msg 2764 item 1:
## "when you talk to the innkeeper, it's completely in the wrong direction
## compared to where your character is").
##
## The general fix: OverworldNPC.face_toward(target_pos) picks the dominant
## axis (left/right/up/down) and updates facing_direction + reslices the
## archetype sheet region. _start_dialogue calls it before the dialogue
## lands so the sprite reads "talking TO you." Innkeeper is the named
## repro but every dialogue-enabled NPC benefits.
##
## Lane split with cowir-main (msg 2766): NPC-side turn-to-face is my
## lane (this file). Player-side interact detection (search radius, ordering)
## is theirs.

const OverworldNPCScript := preload("res://src/exploration/OverworldNPC.gd")


func _make_npc() -> Node:
	var n = OverworldNPCScript.new()
	n.npc_name = "TestNPC"
	n.npc_type = "villager"
	# Skip archetype loading so we don't need a sheet asset in the fixture;
	# face_toward exits early on null _archetype_sheet, but the direction
	# calc is what we're pinning here.
	return n


func test_face_toward_picks_right_for_east_target() -> void:
	var npc: Node = _make_npc()
	add_child_autofree(npc)
	await get_tree().process_frame
	npc.facing_direction = 0  # start facing down
	npc.global_position = Vector2(100, 100)
	npc.face_toward(Vector2(200, 105))  # dominantly east
	assert_eq(npc.facing_direction, 3, "east target → facing_direction=3 (right)")


func test_face_toward_picks_left_for_west_target() -> void:
	var npc: Node = _make_npc()
	add_child_autofree(npc)
	await get_tree().process_frame
	npc.facing_direction = 0
	npc.global_position = Vector2(100, 100)
	npc.face_toward(Vector2(20, 108))  # dominantly west
	assert_eq(npc.facing_direction, 2, "west target → facing_direction=2 (left)")


func test_face_toward_picks_up_for_north_target() -> void:
	var npc: Node = _make_npc()
	add_child_autofree(npc)
	await get_tree().process_frame
	npc.facing_direction = 0
	npc.global_position = Vector2(100, 100)
	npc.face_toward(Vector2(105, 20))  # dominantly north
	assert_eq(npc.facing_direction, 1, "north target → facing_direction=1 (up)")


func test_face_toward_picks_down_for_south_target() -> void:
	var npc: Node = _make_npc()
	add_child_autofree(npc)
	await get_tree().process_frame
	npc.facing_direction = 1  # start facing up
	npc.global_position = Vector2(100, 100)
	npc.face_toward(Vector2(105, 200))  # dominantly south
	assert_eq(npc.facing_direction, 0, "south target → facing_direction=0 (down)")


func test_face_toward_prefers_horizontal_when_tied() -> void:
	# A perfectly diagonal target reads better as "sideways" than
	# "up/down" at overworld scale — the sprite's silhouette is more
	# recognizable in profile. `abs(dx) >= abs(dy)` gives horizontal
	# preference at equality.
	var npc: Node = _make_npc()
	add_child_autofree(npc)
	await get_tree().process_frame
	npc.facing_direction = 0
	npc.global_position = Vector2(100, 100)
	npc.face_toward(Vector2(150, 150))  # equal delta, prefer right
	assert_eq(npc.facing_direction, 3, "equal delta prefers horizontal (right)")


## Source pin: _start_dialogue must call face_toward before setting
## _is_talking = true. Otherwise a slow archetype re-slice could see the
## post-dialogue state and skip the turn — the innkeeper repro exactly.
func test_start_dialogue_faces_player_before_locking_talking() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/OverworldNPC.gd")
	var fn_idx := src.find("func _start_dialogue")
	assert_gt(fn_idx, 0, "_start_dialogue defined")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var face_pos := body.find("face_toward")
	var lock_pos := body.find("_is_talking = true")
	assert_gt(face_pos, 0, "_start_dialogue calls face_toward")
	assert_gt(lock_pos, 0, "_start_dialogue sets _is_talking = true")
	assert_lt(face_pos, lock_pos,
		"face_toward must run BEFORE the _is_talking lock so a re-entry can't skip the turn")


func test_apply_facing_is_null_safe_when_no_sheet() -> void:
	# _apply_facing must degrade cleanly for NPCs that don't have a
	# cached archetype sheet (procedural pipeline or missing asset) —
	# the direction still updates, no error.
	var npc: Node = _make_npc()
	add_child_autofree(npc)
	await get_tree().process_frame
	npc._archetype_sheet = null  # force the no-sheet path
	npc.global_position = Vector2(100, 100)
	npc.face_toward(Vector2(200, 100))  # should not error
	assert_eq(npc.facing_direction, 3, "direction still updates without a sheet")
