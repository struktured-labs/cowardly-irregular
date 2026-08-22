extends GutTest

## CrossCode phase 4 (struktured 2026-08-22: "continue with next cross code phase"): W2-W6
## villages painted themselves with the MEDIEVAL tile generator, so suburbia rendered in
## castle-town grass. Routing a village to its world's generator is not a one-line override —
## every generator has a DISJOINT TileType enum and its own atlas size, so the village's legend
## must be re-authored at the same time or every cell indexes the wrong art.
##
## The failure this pins is silent: _atlas_for() returns Vector2i.ZERO for a type its generator
## does not know, so a mis-routed village paints ONE tile everywhere and still runs. Nothing
## errors, nothing crashes, and a screenshot is the only way a human notices.
##
## BOUND, measured by mutation 2026-08-22: TileType values are plain small ints, so
## resolvability is DIRECTIONAL. A medieval legend (ids up to 23) inside a 16-entry world
## atlas is caught; the reverse — a world legend (ids 0-15) inside medieval's 40-entry order
## — resolves by coincidence and this check stays green. That direction is covered instead by
## test_each_village_uses_its_own_worlds_generator, which is why both tests must exist.
##
## Chars are swept across printable ASCII rather than read from the legend source — the default
## `_` arm is part of the contract too, and a source-parsed char list would go quietly empty.

const MEDIEVAL := "res://src/exploration/TileGenerator.gd"
const SUBURBAN := "res://src/exploration/SuburbanTileGenerator.gd"
const STEAMPUNK := "res://src/exploration/SteampunkTileGenerator.gd"
const INDUSTRIAL := "res://src/exploration/IndustrialTileGenerator.gd"
const FUTURISTIC := "res://src/exploration/FuturisticTileGenerator.gd"
const ABSTRACT := "res://src/exploration/AbstractTileGenerator.gd"

## Every village outside W1, with the generator its world is supposed to paint with.
const W2 := {
	"res://src/maps/villages/MapleHeightsVillage.gd": SUBURBAN,
	"res://src/maps/villages/MapleStripMall.gd": SUBURBAN,
	"res://src/maps/villages/BrasstonVillage.gd": STEAMPUNK,
	"res://src/maps/villages/ScripturaPlaza.gd": STEAMPUNK,
	"res://src/maps/villages/RivetRowVillage.gd": INDUSTRIAL,
	"res://src/maps/villages/NodePrimeVillage.gd": FUTURISTIC,
	"res://src/maps/villages/VertexVillage.gd": ABSTRACT,
}
## W1 stays medieval — without this the suite cannot tell "routed correctly" from "routed all
## villages to one generator", which passes every other assert here.
const W1_CONTROL := "res://src/maps/villages/HarmoniaVillage.gd"


func _village(path: String) -> Node:
	# Villages are scripts, not scenes — only Harmonia has a .tscn. Loading one as a PackedScene
	# yields null, and the abort scores every test [Risky] rather than failing.
	var scr = load(path)
	assert_not_null(scr, "%s must load" % path)
	var v: Node = scr.new()
	add_child_autofree(v)
	await get_tree().process_frame
	await get_tree().process_frame
	return v


func _chars() -> Array:
	var out: Array = []
	for code in range(33, 127):
		out.append(char(code))
	return out


func test_each_village_uses_its_own_worlds_generator() -> void:
	for path in W2:
		var v: Node = await _village(path)
		assert_not_null(v.tile_generator, "%s built no generator" % path)
		assert_eq(v.tile_generator.get_script().resource_path, W2[path],
			"%s must paint with its world's generator" % path.get_file())
	var w1: Node = await _village(W1_CONTROL)
	assert_eq(w1.tile_generator.get_script().resource_path, MEDIEVAL,
		"CONTROL: W1 still medieval — if this flipped, routing was applied indiscriminately")


func test_every_char_the_legend_can_emit_resolves_in_that_generators_atlas() -> void:
	# The whole point of the phase. An unresolved type is not an error — it is tile (0,0).
	for path in W2:
		var v: Node = await _village(path)
		var order: Array = v.tile_generator._get_tile_order()
		assert_gt(order.size(), 0, "CONTROL: %s generator declares a tile order" % path.get_file())
		var unresolved: Array = []
		for c in _chars():
			var t: int = v._char_to_tile_type(c)
			if order.find(t) < 0:
				unresolved.append("'%s'->%d" % [c, t])
		assert_eq(unresolved.size(), 0,
			"%s emits types its own generator cannot draw (they paint as tile 0,0): %s"
			% [path.get_file(), ", ".join(unresolved)])


func test_the_resolvability_check_can_actually_fail() -> void:
	# Feeds the real resolver a type from the WRONG generator — the exact mistake the phase
	# invites. Without this, the zero above is equally true of a check that never compared.
	var foreign: int = TileGenerator.TileType.VILLAGE_HEDGE
	for path in W2:
		var v: Node = await _village(path)
		assert_lt(v.tile_generator._get_tile_order().find(foreign), 0,
			"%s: a medieval type must NOT resolve in this atlas — else the vocabularies overlap and the resolvability check proves nothing" % path.get_file())


func test_routing_preserved_which_cells_block() -> void:
	# Collision is derived from the generator's impassable set, so re-authoring the legend can
	# silently open a wall or seal a street. Asserts the RELATIONSHIP (walls block, open ground
	# walks), not any particular tile id.
	for path in W2:
		var v: Node = await _village(path)
		var blocked: Array = v.tile_generator._get_impassable_types()
		assert_gt(blocked.size(), 0, "CONTROL: %s declares impassable types" % path.get_file())
		assert_true(blocked.has(v._char_to_tile_type("W")),
			"%s: 'W' is the map border — it must still block" % path.get_file())
		assert_false(blocked.has(v._char_to_tile_type(".")),
			"%s: '.' is open ground — it must still be walkable" % path.get_file())
		assert_false(blocked.has(v._char_to_tile_type("p")),
			"%s: 'p' is a walked path — it must still be walkable" % path.get_file())


func test_the_map_still_paints_more_than_one_kind_of_tile() -> void:
	# Reads back what was actually painted. A collapsed village is uniform, and uniformity is
	# the one symptom visible without opening the game.
	for path in W2:
		var v: Node = await _village(path)
		var seen: Dictionary = {}
		for cell in v.tile_map.get_used_cells():
			seen[v.tile_map.get_cell_atlas_coords(cell)] = true
		assert_gt(v.tile_map.get_used_cells().size(), 100, "CONTROL: %s painted a real map" % path.get_file())
		assert_gt(seen.size(), 2,
			"%s painted only %d distinct tiles — the mis-route symptom" % [path.get_file(), seen.size()])


func test_the_shared_legend_parser_can_see_these_villages_walls() -> void:
	# test_village_npc_connectivity flood-fills from a legend parsed by village_grid_source,
	# whose impassable list was MEDIEVAL type names. Routing W2-W6 to their own generators
	# made every one of their legends parse as zero blocking chars — the flood fill would have
	# escaped through the walls and the whole reachability suite would have gone vacuous.
	# Its own guard caught it. This pins the fix from the other side.
	var GS := preload("res://test/unit/helpers/village_grid_source.gd")
	for path in W2:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 500, "CONTROL: read a real village source for %s" % path.get_file())
		var derived: Array = GS.derived_impassable(src)
		assert_gt(derived.size(), 0,
			"%s: the shared parser derives no impassable types — every flood fill over it is vacuous" % path.get_file())
		assert_gt(GS.blocked_chars(src, []).size(), 0,
			"%s: no blocking legend chars, even with derivation" % path.get_file())


func test_derivation_agrees_with_the_medieval_hand_list_it_replaced() -> void:
	# The medieval generator's own impassable set was byte-identical to the hardcoded list
	# callers passed, which is WHY deriving was safe for W1. Asserted so a change to either
	# side surfaces here rather than as a silently different W1 flood fill.
	var GS := preload("res://test/unit/helpers/village_grid_source.gd")
	var src := FileAccess.get_file_as_string("res://src/maps/villages/HarmoniaVillage.gd")
	var derived: Array = GS.derived_impassable(src)
	derived.sort()
	var hand := ["CAVE_WALL", "LAVA", "MOUNTAIN", "VILLAGE_HEDGE", "WALL", "WATER"]
	assert_eq(derived, hand, "medieval derivation drifted from the list it replaced")
