extends GutTest

## Phase-4 dungeon visuals (2026-10-06): every later-world dungeon used to render with the
## same CAVE_WALL/CAVE_FLOOR tiles as the W1 medieval caves -- a steampunk mechanism and a
## null-chamber void looked like the same rock room. This pins that each later-world dungeon
## now resolves its own wall/floor TileType, and that every dungeon carries a light that
## follows the player (not just landmark torches) so the room stays readable.

const TG := preload("res://src/exploration/TileGenerator.gd")
const DUNGEONS := {
	"steampunk_mechanism": "res://src/maps/dungeons/SteampunkMechanism.gd",
	"assembly_core": "res://src/maps/dungeons/AssemblyCore.gd",
	"root_process": "res://src/maps/dungeons/RootProcess.gd",
	"null_chamber": "res://src/maps/dungeons/NullChamber.gd",
	"suburban_underground": "res://src/maps/dungeons/SuburbanUnderground.gd",
	"vertex_apex": "res://src/maps/dungeons/VertexApex.gd",
}


func _cave(path: String) -> Node:
	var scr = load(path)
	assert_not_null(scr, "%s must load" % path)
	var c: Node = scr.new()
	add_child_autofree(c)
	await get_tree().process_frame
	await get_tree().process_frame
	return c


## null_chamber and vertex_apex are BOTH W6 abstract (VertexApex's own doc: "stays single-room
## BY DESIGN") -- they are deliberately the one pair expected to share a wall tile.
const EXPECTED_SHARED_WALL_GROUPS := [["null_chamber", "vertex_apex"]]


func test_each_later_world_dungeon_resolves_its_own_wall_tile() -> void:
	# CONTROL: a plain DragonCave (W1 medieval) must resolve wall char "M" to CAVE_WALL,
	# else the comparison below proves nothing.
	var medieval_wall: int = TG.TileType.CAVE_WALL
	var by_type: Dictionary = {}
	for name in DUNGEONS:
		var c: Node = await _cave(DUNGEONS[name])
		var wall_type: int = c._char_to_tile_type("M")
		assert_ne(wall_type, medieval_wall,
			"%s still renders the medieval CAVE_WALL tile -- phase-4 tileset not wired" % name)
		if not by_type.has(wall_type):
			by_type[wall_type] = []
		(by_type[wall_type] as Array).append(name)
	var allowed: Array = EXPECTED_SHARED_WALL_GROUPS.duplicate(true)
	var unexpected: Array = []
	for wall_type in by_type:
		var names: Array = by_type[wall_type]
		if names.size() <= 1:
			continue
		names.sort()
		var ok := false
		for group in allowed:
			var sorted_group: Array = (group as Array).duplicate()
			sorted_group.sort()
			if sorted_group == names:
				ok = true
				break
		if not ok:
			unexpected.append(names)
	assert_eq(unexpected, [], "dungeons sharing a wall tile outside the known abstract pair: %s" % str(unexpected))


func test_wall_and_floor_tile_ids_resolve_to_distinct_atlas_cells() -> void:
	for name in DUNGEONS:
		var c: Node = await _cave(DUNGEONS[name])
		var wall_id: int = TG.get_tile_id(c._char_to_tile_type("M"))
		var floor_id: int = TG.get_tile_id(c._char_to_tile_type("."))
		assert_ne(wall_id, floor_id, "%s: wall and floor resolved to the same atlas cell" % name)
		assert_gt(wall_id, 0, "%s: wall tile id fell back to the atlas's id-0 default" % name)


func test_every_dungeon_carries_a_light_that_follows_the_player() -> void:
	for name in DUNGEONS:
		var c: Node = await _cave(DUNGEONS[name])
		assert_not_null(c.lighting, "%s built no lighting rig" % name)
		assert_not_null(c.lighting._player_light, "%s has no player-following light" % name)
		assert_eq(c.lighting._player_light.get_parent(), c.lighting,
			"%s: player light escaped the CanvasModulate and would be swallowed by the dark" % name)
		await get_tree().process_frame
		var dist: float = c.lighting._player_light.position.distance_to(c.player.position)
		assert_lt(dist, 4.0, "%s: player light drifted away from the player it is meant to follow" % name)


func test_new_wall_types_are_impassable() -> void:
	var blocked: Array = TG.new()._get_impassable_types()
	for t in [TG.TileType.STEAMPUNK_WALL, TG.TileType.INDUSTRIAL_WALL, TG.TileType.DIGITAL_WALL,
			TG.TileType.ABSTRACT_WALL, TG.TileType.SUBURBAN_WALL]:
		assert_true(t in blocked, "%s must block movement like every other dungeon wall" % TG.TileType.keys()[t])
