class_name EnvironmentTileSets
extends RefCounted
## Builds the Cliff and Overlay TileSets villages paint derived elevation onto; single-row atlases, ids fixed here.

const TILE := 32
const FACE_ID := 16
const STAIR_ID := 16
const RAMP_ID := 17
const SHADOW_ID := 18
const CLIFF_COUNT := 17
const OVERLAY_COUNT := 19
const EDGE_THICKNESS := 4.0

const DEFAULT_PALETTE := {
	"face_dark": Color(0.30, 0.26, 0.24),
	"face_mid": Color(0.46, 0.40, 0.36),
	"face_light": Color(0.60, 0.54, 0.48),
	"lip": Color(0.82, 0.78, 0.66),
	"lip_shadow": Color(0.22, 0.19, 0.17, 0.85),
	"grass": Color(0.38, 0.62, 0.28),
	"grass_light": Color(0.50, 0.74, 0.34),
	"stair_tread": Color(0.72, 0.68, 0.60),
	"stair_riser": Color(0.40, 0.36, 0.32),
}


static func atlas_coords(id: int) -> Vector2i:
	return Vector2i(id, 0)


## Artist piece from the world's sheet, or the procedural image — colliders are set by id, never by art
static func _art_or(sheet_key: String, section: String, name: String, procedural: Image) -> Image:
	var art: Image = TileSheetManifest.region(sheet_key, section, name) if sheet_key != "" else null
	return art if art != null else procedural


static func _pal(palette: Dictionary, key: String) -> Color:
	return palette.get(key, DEFAULT_PALETTE[key])


static func _make_atlas(images: Array) -> TileSetAtlasSource:
	var sheet := Image.create(TILE * images.size(), TILE, false, Image.FORMAT_RGBA8)
	for i in range(images.size()):
		sheet.blit_rect(images[i], Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(sheet)
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in range(images.size()):
		src.create_tile(atlas_coords(i))
	return src


static func _edge_strip(bit: int, half: float) -> PackedVector2Array:
	var t := EDGE_THICKNESS
	match bit:
		1: return PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, -half + t), Vector2(-half, -half + t)])
		2: return PackedVector2Array([Vector2(half - t, -half), Vector2(half, -half), Vector2(half, half), Vector2(half - t, half)])
		4: return PackedVector2Array([Vector2(-half, half - t), Vector2(half, half - t), Vector2(half, half), Vector2(-half, half)])
		_: return PackedVector2Array([Vector2(-half, -half), Vector2(-half + t, -half), Vector2(-half + t, half), Vector2(-half, half)])


static func build_cliff_tileset(palette: Dictionary = {}, sheet_key: String = "") -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)
	var images: Array = []
	for mask in range(16):
		images.append(_art_or(sheet_key, "cliff", "edge_%d" % mask, _draw_edge_tile(mask, palette)))
	images.append(_art_or(sheet_key, "cliff", "face", _draw_face_tile(palette)))
	var src := _make_atlas(images)
	ts.add_source(src)
	var half := TILE / 2.0
	for mask in range(1, 16):
		var td := src.get_tile_data(atlas_coords(mask), 0)
		for bit in [1, 2, 4, 8]:
			if mask & bit:
				var idx := td.get_collision_polygons_count(0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, idx, _edge_strip(bit, half))
	var face := src.get_tile_data(atlas_coords(FACE_ID), 0)
	face.add_collision_polygon(0)
	face.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]))
	return ts


static func build_overlay_tileset(palette: Dictionary = {}, sheet_key: String = "") -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)
	var images: Array = []
	for mask in range(16):
		images.append(_art_or(sheet_key, "overlay", "fringe_%d" % mask, _draw_fringe_tile(mask, palette)))
	images.append(_art_or(sheet_key, "overlay", "stair", _draw_stair_tile(palette)))
	images.append(_art_or(sheet_key, "overlay", "ramp", _draw_ramp_tile(palette)))
	images.append(_art_or(sheet_key, "overlay", "shadow", _draw_shadow_tile()))
	ts.add_source(_make_atlas(images))
	return ts


static func _draw_edge_tile(mask: int, palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var lip := _pal(palette, "lip")
	var shadow := _pal(palette, "lip_shadow")
	if mask & 1:
		img.fill_rect(Rect2i(0, 0, TILE, 2), lip)
		img.fill_rect(Rect2i(0, 2, TILE, 1), shadow)
	if mask & 4:
		img.fill_rect(Rect2i(0, TILE - 2, TILE, 2), lip)
		img.fill_rect(Rect2i(0, TILE - 3, TILE, 1), shadow)
	if mask & 8:
		img.fill_rect(Rect2i(0, 0, 2, TILE), lip)
		img.fill_rect(Rect2i(2, 0, 1, TILE), shadow)
	if mask & 2:
		img.fill_rect(Rect2i(TILE - 2, 0, 2, TILE), lip)
		img.fill_rect(Rect2i(TILE - 3, 0, 1, TILE), shadow)
	return img


## A ledge reads as a ledge only with a LIT top edge, a darkening body and a black foot — flat mid-grey reads as path.
static func _draw_face_tile(palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var dark := _pal(palette, "face_dark")
	var mid := _pal(palette, "face_mid")
	var light := _pal(palette, "face_light")
	for y in range(TILE):
		var t := float(y) / float(TILE - 1)
		img.fill_rect(Rect2i(0, y, TILE, 1), light.lerp(mid, clampf(t * 1.6, 0.0, 1.0)).lerp(dark, clampf((t - 0.55) * 2.2, 0.0, 1.0)))
	img.fill_rect(Rect2i(0, 0, TILE, 2), _pal(palette, "lip"))
	img.fill_rect(Rect2i(0, 2, TILE, 1), light)
	for y in range(7, TILE - 4, 7):
		var jitter := int(sin(y * 1.7) * 4.0)
		img.fill_rect(Rect2i(0, y, TILE, 1), dark.darkened(0.25))
		img.fill_rect(Rect2i(3 + jitter, y + 3, 9, 1), light)
		img.fill_rect(Rect2i(19 - jitter, y + 4, 7, 1), light)
		img.fill_rect(Rect2i(13 + jitter, y, 1, 7), dark.darkened(0.25))
	img.fill_rect(Rect2i(0, TILE - 3, TILE, 3), dark.darkened(0.45))
	return img


## Cast shadow the ledge throws onto the ground beneath it (painted on the cell SOUTH of a face)
static func _draw_shadow_tile() -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in range(12):
		var a := 0.55 * (1.0 - float(y) / 12.0)
		img.fill_rect(Rect2i(0, y, TILE, 1), Color(0.05, 0.04, 0.08, a * a + 0.08 * (1.0 - float(y) / 12.0)))
	return img


static func _draw_fringe_tile(mask: int, palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var g := _pal(palette, "grass")
	var gl := _pal(palette, "grass_light")
	for i in range(0, TILE, 3):
		var h := 2 + int(abs(sin(i * 2.3 + mask))) * 2
		if mask & 1:
			img.fill_rect(Rect2i(i, 0, 2, h), g if i % 2 == 0 else gl)
		if mask & 4:
			img.fill_rect(Rect2i(i, TILE - h, 2, h), g if i % 2 == 0 else gl)
		if mask & 8:
			img.fill_rect(Rect2i(0, i, h, 2), g if i % 2 == 0 else gl)
		if mask & 2:
			img.fill_rect(Rect2i(TILE - h, i, h, 2), g if i % 2 == 0 else gl)
	return img


static func _draw_stair_tile(palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var tread := _pal(palette, "stair_tread")
	var riser := _pal(palette, "stair_riser")
	for step in range(4):
		var y := step * 8
		img.fill_rect(Rect2i(2, y, TILE - 4, 5), tread)
		img.fill_rect(Rect2i(2, y + 5, TILE - 4, 3), riser)
	img.fill_rect(Rect2i(0, 0, 2, TILE), riser)
	img.fill_rect(Rect2i(TILE - 2, 0, 2, TILE), riser)
	return img


static func _draw_ramp_tile(palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var tread := _pal(palette, "stair_tread")
	var riser := _pal(palette, "stair_riser")
	img.fill(tread)
	for d in range(0, TILE * 2, 6):
		for x in range(TILE):
			var y := d - x
			if y >= 0 and y < TILE:
				img.set_pixel(x, y, riser)
	return img
