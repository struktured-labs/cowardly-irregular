extends GutTest

## A signpost is read by standing next to it, and both places it is read were broken.
##
## FOUND 2026-09-10 by parking the real body on W1's "← Harmonia Village" sign and rendering:
##   1. MODE 7 — the Label is world-space, so the shader warps and fogs it exactly like ground.
##      At font size 10 the result is not hard to read, it is not text: a 25x50 smudge of dark
##      marks in the grass. Thirteen navigation signs in W1 alone, plus W2-W5.
##   2. EVERY MAP — z_index 0, z_as_relative true, against a player at z_index 0. The sprite that
##      walked up to read the sign is drawn over the words. Same defect the exit prompt had.
##
## Both now go through Mode7Prompt, shared with AreaTransition, so the two surfaces cannot drift.
## Signposts take the upper screen row: directions are information, an entrance prompt is an action,
## and a sign standing on a village gate would otherwise print both lines on top of each other.

const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")
const DUNGEON_DIR := "res://src/maps/dungeons"
const OVERWORLD := "res://src/exploration/OverworldScene.gd"


func after_each() -> void:
	## Leaking a true rotates village movement and re-scales every interact zone in the suite.
	Mode7Overlay.is_active = false


## Map set derived by SHAPE, not by a skip list — see the helper. This file read
## `NOT_MAPS := ["DragonCave.gd"]`, which was true and incomplete: BossTrigger.gd is an Area2D
## component in the same directory and was being built as a map and counted by the CONTROL below.
func _dungeon_scripts() -> Array:
	return MapScripts.maps_in(DUNGEON_DIR)


func _signposts(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c is Signpost:
			acc.append(c)
		_signposts(c, acc)


func test_the_two_prompt_surfaces_share_one_contract() -> void:
	assert_gt(Mode7Prompt.LAYER, 2,
		"the prompt layer must clear Mode7Overlay's ground (1) and player (2)")
	assert_gt(Mode7Prompt.ROW_INFO, Mode7Prompt.ROW_ACTION,
		"a signpost and an entrance prompt on the same cell would print on top of each other")
	assert_gt(Mode7Prompt.WORLD_Z, 0, "a world-space prompt at z 0 ties with the player")


func test_no_signpost_in_a_flat_map_reads_from_under_the_player() -> void:
	var buried: Array = []
	var scenes_built := 0
	var signs_seen := 0

	for path in _dungeon_scripts():
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var scene = load(path).new()
		vp.add_child(scene)
		await get_tree().physics_frame
		scenes_built += 1

		var player_z := 0
		var p = scene.get("player")
		if p != null and p is CanvasItem:
			player_z = (p as CanvasItem).z_index

		var found: Array = []
		_signposts(scene, found)
		for post in found:
			signs_seen += 1
			var lbl: Label = post._label
			if lbl == null or lbl.z_index <= player_z or lbl.z_as_relative:
				buried.append("%s/%s" % [path.get_file().get_basename(), str(post.sign_text)])
	buried.sort()

	assert_gt(scenes_built, 10, "CONTROL: only %d dungeons built" % scenes_built)
	assert_gt(signs_seen, 10, "CONTROL: only %d signposts found — the scan is broken and the zero below is free" % signs_seen)
	assert_eq(buried, [], "a signpost draws under the player who walked up to read it: %s" % str(buried))


func test_a_mode7_signpost_lifts_its_text_off_the_ground_plane() -> void:
	Mode7Overlay.is_active = true
	var post := Signpost.new()
	post.sign_text = "← Harmonia Village"
	add_child_autofree(post)
	await get_tree().process_frame
	await get_tree().process_frame

	var lbl: Label = post._label
	assert_not_null(lbl, "CONTROL: the signpost must build a label at all")
	if lbl == null:
		return
	var host = lbl.get_parent()
	assert_true(host is CanvasLayer,
		"sign text is still in world space, where the Mode 7 shader turns it into a smudge: %s" % [host])
	if host is CanvasLayer:
		assert_gt((host as CanvasLayer).layer, 2, "sign text draws under Mode7Overlay's own layers")

	Mode7Overlay.is_active = false
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(lbl.get_parent(), post, "the sign text never came back from its screen layer")
	assert_eq(lbl.position, Signpost.FLAT_OFFSET, "the sign text came back to the wrong offset")
