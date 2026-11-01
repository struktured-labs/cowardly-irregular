extends GutTest

## The Harmonia pilot (cowir-overworld 21137, framed shots): the bigger inn's thatch rose 39px over its 4-row block and
## the remedies' roof 46px, but each stands ONE row below a higher tier, so the roofs climbed over the stone ledge and
## onto the walkable row above. A roof may cover the cliff-face row it backs onto, never the higher tier's ground: its
## rise over the block must stay 8px under that clearance, so the top of the wall still shows.

const SLACK := 8
## Every village whose map carries tiers and whose buildings are drawn (BUILDING_ART).
const VILLAGES := [
	"res://src/maps/villages/HarmoniaVillage.gd",
	"res://src/maps/villages/FrostholdVillage.gd",
	"res://src/maps/villages/GrimhollowVillage.gd",
	"res://src/maps/villages/IronhavenVillage.gd",
	"res://src/maps/villages/EldertreeVillage.gd",
	"res://src/maps/villages/SandriftVillage.gd",
	"res://src/maps/villages/MapleHeightsVillage.gd",
	"res://src/maps/villages/BrasstonVillage.gd",
	"res://src/maps/villages/NodePrimeVillage.gd",
	"res://src/maps/villages/VertexVillage.gd",
]


func _built(path: String) -> Node:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v = load(path).new()
	vp.add_child(v)
	await get_tree().process_frame
	await get_tree().process_frame
	return v


func _art_heights() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var out := {}
	for key in (parsed as Dictionary).get("building_art", {}):
		var e = parsed["building_art"][key]
		if e is Dictionary and e.has("path"):
			out[key] = (load(str(e["path"])) as Texture2D).get_height()
	return out


## The block the art stands on: the run of its glyph from the art's anchor cell, as [top, bottom, left, right].
func _block(rows: Array, at: Vector2i) -> Array:
	var g := str(rows[at.y])[at.x]
	var top := at.y
	while top > 0 and str(rows[top - 1])[at.x] == g:
		top -= 1
	var bot := at.y
	while bot + 1 < rows.size() and str(rows[bot + 1])[at.x] == g:
		bot += 1
	var left := at.x
	while left > 0 and str(rows[at.y])[left - 1] == g:
		left -= 1
	var right := at.x
	while right + 1 < str(rows[at.y]).length() and str(rows[at.y])[right + 1] == g:
		right += 1
	return [top, bot, left, right]


## Rows of the block's own tier between its top and the nearest HIGHER tier above it (min over its columns); -1 = none.
func _clearance(grid: Array, b: Array) -> int:
	var best := -1
	for x in range(int(b[2]), int(b[3]) + 1):
		var tier := int(grid[b[0]][x])
		for y in range(int(b[0]) - 1, -1, -1):
			if int(grid[y][x]) > tier:
				var c := int(b[0]) - y - 1
				best = c if best < 0 else mini(best, c)
				break
	return best


func test_no_roof_climbs_onto_the_tier_above() -> void:
	var heights := _art_heights()
	var judged := 0
	var over: Array = []
	for path in VILLAGES:
		var consts: Dictionary = (load(path) as Script).get_script_constant_map()
		var art: Dictionary = consts.get("BUILDING_ART", {})
		if art.is_empty():
			continue
		var v = await _built(path)
		var rows: Array = v.get("_map_rows")
		var grid: Array = v.get("_height_grid")
		if rows.is_empty() or grid.is_empty():
			continue
		for at in art:
			var key := str(art[at])
			if not heights.has(key):
				continue
			var b := _block(rows, at)
			var rise: int = int(heights[key]) - (int(b[1]) - int(b[0]) + 1) * 32
			var c := _clearance(grid, b)
			if c < 1:
				continue  # flush against the tier (no lower row to cover) or nothing higher above
			judged += 1
			if rise > c * 32 - SLACK:
				over.append("%s %s: rises %dpx, %d clear row(s) allow %dpx" % [path.get_file(), key, rise, c, c * 32 - SLACK])
	## FLOOR: Harmonia's inn and remedies sit one row under the castle approach; they must be judged.
	assert_gte(judged, 2, "FLOOR: at least the inn and remedies stand under a higher tier (%d judged)" % judged)
	assert_eq(over, [], "these roofs climb over the ledge onto the tier above: %s" % [over])
