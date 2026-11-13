extends RefCounted
class_name InteriorArt

## struktured 2026-11-01: "the inside of village houses and shops need a major sprite rework". The seam the art lands on, one
## manifest section with the villages (prop_art): "<kind>_<room>_<village>" -> "<kind>_<room>" -> "<kind>_<world>" -> "<kind>".
## No entry, or no file, and the room's own painter runs exactly as before, so nothing goes blank mid-rework.

const TILE := 32
## Tile kinds a room asks for by name; anything else a room passes is furniture.
const TILE_KINDS := ["floor", "wall", "counter", "shelf", "hearth", "carpet"]
## Furniture kinds wired to the seam so far (each one names its own place_or_paint call).
const FURNITURE_KINDS := ["shelf_goods", "back_wall", "armchair", "table_things", "table", "desk", "coat_rack", "rug", "bench", "barrel", "crate", "round_table", "stool", "door_mat", "gear_pile", "barrels", "sacks", "crate_produce", "mat", "anvil", "weapon_crates", "bellows", "quench_barrel", "coal_bin", "forge"]
const WORLDS := ["medieval", "suburban", "steampunk", "industrial", "futuristic", "abstract"]
const INTERIORS_DIR := "res://src/maps/interiors"
## Shared rooms, keyed by what they ARE; a village-specific variant adds "_<village>" (e.g. counter_shop_item_harmonia).
const SHOP_ROOMS := ["shop_item", "shop_black_magic", "shop_white_magic", "shop_blacksmith"]


## The art path for a kind in a room, most specific first; "" when nothing on disk answers.
static func path(kind: String, room: String, village: String = "", world: String = "") -> String:
	var sec := VillageProp._prop_art_section()
	var keys: Array = []
	if room != "" and village != "":
		keys.append("%s_%s_%s" % [kind, room, village])
	if room != "":
		keys.append("%s_%s" % [kind, room])
	if world != "":
		keys.append("%s_%s" % [kind, world])
	keys.append(kind)
	for k in keys:
		var e: Variant = sec.get(k, null)
		if e is Dictionary and ResourceLoader.exists(str((e as Dictionary).get("path", ""))):
			return str((e as Dictionary)["path"])
	return ""


## A village id as rooms see it: "harmonia_village" -> "harmonia".
static func village_key(origin_id: String) -> String:
	return origin_id.trim_suffix("_village")


## A tile image: the drawn one when it exists, trimmed to whole 32px cells, so a 128x128 entry is a 4x4 PATTERN the room
## samples by (x mod 4, y mod 4) and a 32x32 entry is the 1x1 case; else the room's painter fills one fresh 32px cell.
static func tile(kind: String, room: String, painter: Callable, village: String = "", world: String = "") -> Image:
	var p := path(kind, room, village, world)
	if p != "":
		var src := (load(p) as Texture2D).get_image()
		var cells := Vector2i(src.get_width() / TILE, src.get_height() / TILE)
		if cells.x >= 1 and cells.y >= 1:
			return src.get_region(Rect2i(Vector2i.ZERO, cells * TILE))
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	painter.call(img)
	return img


## An atlas source holding every 32px cell of a tile image (one cell for a painted tile, cols x rows for a pattern).
static func source(img: Image) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	for y in range(img.get_height() / TILE):
		for x in range(img.get_width() / TILE):
			src.create_tile(Vector2i(x, y))
	return src


## The atlas cell a map cell uses: a pattern repeats every cols x rows, a single cell is always (0, 0).
static func cell(src: TileSetAtlasSource, at: Vector2i) -> Vector2i:
	var grid := src.get_atlas_grid_size()
	return Vector2i(posmod(at.x, maxi(grid.x, 1)), posmod(at.y, maxi(grid.y, 1)))


## A room-wide strip standing on the top wall row's base (it may rise above the map's top edge); no art = nothing extra.
static func back_wall(parent: Node, room: String, map_width_tiles: int, village: String = "", world: String = "") -> Node:
	var none := func() -> Node:
		return null
	return place_or_paint(parent, "back_wall", room, Vector2(map_width_tiles * TILE / 2.0, TILE), none, village, world)


## The atlas cell for map cell `at` in a tilemap's source `source_id` (patterns repeat; a single cell stays (0, 0)).
static func cell_in(tm: TileMapLayer, source_id: int, at: Vector2i) -> Vector2i:
	if tm == null or tm.tile_set == null or not tm.tile_set.has_source(source_id):
		return Vector2i.ZERO
	var src := tm.tile_set.get_source(source_id) as TileSetAtlasSource
	return cell(src, at) if src != null else Vector2i.ZERO


## A piece of furniture: the drawn one stands base-centred on `base` (its feet on that point); else the painter builds it.
static func place_or_paint(parent: Node, kind: String, room: String, base: Vector2, painter: Callable, village: String = "", world: String = "") -> Node:
	var p := path(kind, room, village, world)
	if p == "":
		return painter.call()
	var spr := Sprite2D.new()
	spr.name = "Art_" + kind
	spr.centered = false
	spr.texture = load(p)
	spr.position = base - Vector2(spr.texture.get_width() / 2.0, spr.texture.get_height())
	## Readable names: repeated pieces under one parent stay Art_<kind>, Art_<kind>2..., not @Sprite2D@N.
	parent.add_child(spr, true)
	return spr


## Every room key art may name: the shared rooms plus each BaseInterior room's own area id (derived from its source).
static func room_ids() -> Array:
	var out: Array = SHOP_ROOMS.duplicate()
	out.append_array(["inn", "tavern"])
	var rx := RegEx.create_from_string('func _get_area_id\\(\\)[^\\n]*\\n\\s*return "([a-z_0-9]+)"')
	for f in DirAccess.get_files_at(INTERIORS_DIR):
		if f.ends_with(".gd"):
			var m := rx.search(FileAccess.get_file_as_string(INTERIORS_DIR + "/" + f))
			if m != null and not (m.get_string(1) in out):
				out.append(m.get_string(1))
	return out


## True when a prop_art key is an interior key some room can ask for: <kind>, <kind>_<world>, <kind>_<room>[_<village>].
static func accepts_key(key: String) -> bool:
	var rooms := room_ids()
	for kind in TILE_KINDS + FURNITURE_KINDS:
		if key == kind:
			return true
		if not key.begins_with(kind + "_"):
			continue
		var rest := key.trim_prefix(kind + "_")
		if rest in WORLDS:
			return true
		for room in rooms:
			if rest == room or rest.begins_with(room + "_"):
				return true
	return false


## The layout cells a room's furniture occupies: every cell holding one of `glyphs`, skipping the outer wall rows
## (an inn's bottom-row "D" is its door, its top-row "D" block the desk). For NPC-placement guards.
static func furniture_cells(layout: Array, glyphs: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(1, layout.size() - 1):
		var row: String = layout[y]
		for x in range(row.length()):
			if glyphs.contains(row[x]):
				out.append(Vector2i(x, y))
	return out


## Every drawn piece standing in a room (the Art_* sprites place_or_paint adds), as its rect in the room's own space.
static func drawn_piece_rects(room: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for n in room.find_children("Art_*", "Sprite2D", true, false):
		var spr := n as Sprite2D
		if spr.texture == null:
			continue
		var r := spr.get_rect()
		r.position += spr.position
		var p := spr.get_parent()
		while p != null and p != room and p is Node2D:
			r.position += (p as Node2D).position
			p = p.get_parent()
		out.append(r)
	return out
