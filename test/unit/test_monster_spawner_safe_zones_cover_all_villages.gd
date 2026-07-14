extends GutTest

## tick 83 regression: MonsterSpawner.SAFE_ZONE_RECTS must protect
## every world's village entrance, not just W1 Harmonia. Pre-fix,
## the rects covered ONLY Harmonia's coords [0,21,12,10] +
## [20,22,16,10] — roaming monsters could spawn ON or adjacent to
## W2 Maple Heights, W4 Rivet Row, W5 Node Prime, W6 Vertex
## entrances in those worlds (W3 Brasston was coincidentally inside
## the W1 rect).
##
## MonsterSpawner is shared by all 6 overworld scenes (W1 OverworldScene,
## W2 SuburbanOverworld, W3 SteampunkOverworld, W4 IndustrialOverworld,
## W5 FuturisticOverworld, W6 AbstractOverworld), so the const lives
## in MonsterSpawner and must cover all of them.

const MONSTER_SPAWNER := preload("res://src/exploration/MonsterSpawner.gd")


## Every village entrance position (in tile coords) the spawner must protect.
## Pull from the spawn_points["<village>_entrance"] assignments in each
## overworld script:
##   W2 SuburbanOverworld:     maple_heights_entrance @ (38, 3)
##   W3 SteampunkOverworld:    brasston_entrance      @ (5, 26)
##   W4 IndustrialOverworld:   rivet_row_entrance     @ (55, 17)
##   W5 FuturisticOverworld:   node_prime_entrance    @ (50, 20)
##   W6 AbstractOverworld:     vertex_entrance        @ (19, 16)
const VILLAGE_ENTRANCE_TILES: Array[Array] = [
	[38, 3,  "W2 Maple Heights"],
	[5,  26, "W3 Brasston"],
	[55, 17, "W4 Rivet Row"],
	[50, 20, "W5 Node Prime"],
	[19, 16, "W6 Vertex"],
]


func _tile_in_any_rect(tx: int, ty: int, rects: Array) -> bool:
	for rect_arr in rects:
		var rx: int = int(rect_arr[0])
		var ry: int = int(rect_arr[1])
		var rw: int = int(rect_arr[2])
		var rh: int = int(rect_arr[3])
		if tx >= rx and tx < rx + rw and ty >= ry and ty < ry + rh:
			return true
	return false


func test_every_village_entrance_tile_is_inside_a_safe_zone() -> void:
	# Pin: each village entrance tile must fall inside at least one
	# SAFE_ZONE_RECTS entry. A future world or relocated entrance must
	# update the const.
	var rects: Array = MONSTER_SPAWNER.SAFE_ZONE_RECTS
	for entry in VILLAGE_ENTRANCE_TILES:
		var tx: int = int(entry[0])
		var ty: int = int(entry[1])
		var label: String = String(entry[2])
		assert_true(_tile_in_any_rect(tx, ty, rects),
			"village entrance for %s @ tile (%d, %d) must be inside a SAFE_ZONE_RECTS entry — otherwise roaming monsters can spawn on the player's entry point" % [label, tx, ty])


func test_w1_harmonia_safe_zone_still_present() -> void:
	# Don't regress the original W1 coverage while adding W2-W6.
	var rects: Array = MONSTER_SPAWNER.SAFE_ZONE_RECTS
	# W1 village area centroid ~ tile (5, 26)
	assert_true(_tile_in_any_rect(5, 26, rects),
		"W1 Harmonia village area tile (5, 26) must still be protected — was the original safe zone")


func test_safe_zone_rects_has_at_least_six_entries() -> void:
	# At minimum: 2 W1 rects + 4 new W2/W4/W5/W6 rects = 6.
	# A future refactor that condenses them is OK, but reducing
	# coverage below the 6-village count is not.
	var rects: Array = MONSTER_SPAWNER.SAFE_ZONE_RECTS
	assert_gt(rects.size(), 5,
		"SAFE_ZONE_RECTS must have at least 6 entries — 2 W1 rects + 4 new W2/W4/W5/W6 entrance rects. Coincidental W3 coverage by the W1 rect is fine but not guaranteed.")


func test_each_rect_well_formed() -> void:
	# Defensive: each rect must be [int, int, int, int] with
	# positive dimensions. _in_safe_zone reads index 0..3 as ints,
	# so a malformed entry would crash at runtime.
	var rects: Array = MONSTER_SPAWNER.SAFE_ZONE_RECTS
	for i in range(rects.size()):
		var r: Array = rects[i]
		assert_eq(r.size(), 4,
			"SAFE_ZONE_RECTS[%d] must have exactly 4 elements (tile_x, tile_y, width, height)" % i)
		var rw: int = int(r[2])
		var rh: int = int(r[3])
		assert_gt(rw, 0, "SAFE_ZONE_RECTS[%d] width must be > 0" % i)
		assert_gt(rh, 0, "SAFE_ZONE_RECTS[%d] height must be > 0" % i)
