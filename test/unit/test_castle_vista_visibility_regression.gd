extends GutTest

## Regression: the after_cave "look east" pan showed nothing (struktured,
## 2026-07-25 playtest — "the look what u see line moves camera to nothing
## seeable. just two blue triangles and red flag or somehting on a stone wall").
##
## CastleVista stood at tile row 3 — INSIDE the map — with z_index -2, i.e.
## behind the TileMapLayer at z 0. Rows 0-2 are opaque ('W' wall, and '.'
## falls through to VILLAGE_GRASS in _char_to_tile_type), so the tilemap
## painted over the whole silhouette. The only part that survived was the 8px
## rising above the map's top edge: the two tower roof apexes (ROOF is blue)
## and the banner tip (BANNER is red). His description was pixel-accurate.
##
## Why no existing test caught it: test_staged_scene_live_geometry_smoke
## asserted camera targets were INSIDE THE MAP RECT — which this one was, and
## which is precisely the condition that guaranteed occlusion. Bounds were
## the wrong invariant. What matters is whether anything is VISIBLE there.
##
## So these assert the RELATIONSHIP (silhouette clears the tilemap; the pan
## frames the silhouette), never the literal coordinates — a correct future
## reposition should stay green, and only a re-occlusion should go red.

const HARMONIA_TSCN := "res://src/maps/villages/HarmoniaVillage.tscn"
const CASTLE_VISTA := "res://src/exploration/CastleVista.gd"
const AFTER_CAVE := "res://data/cutscenes/world1_harmonia_after_cave.json"

var _village: Node = null


func before_each() -> void:
	var packed: PackedScene = load(HARMONIA_TSCN)
	assert_not_null(packed, "HarmoniaVillage.tscn must load")
	_village = packed.instantiate()
	add_child_autofree(_village)
	await get_tree().process_frame
	await get_tree().process_frame


func _vista() -> Node2D:
	return _village.find_child("CastleVista", true, false)


func _vista_script() -> GDScript:
	return load(CASTLE_VISTA)


## Top of the castle silhouette in global coords (roof apex of the towers).
func _castle_top_y() -> float:
	var s := _vista_script()
	return _vista().global_position.y + s.CASTLE_BASE - (104.0 * s.CASTLE_SCALE)


func _castle_base_y() -> float:
	return _vista().global_position.y + _vista_script().CASTLE_BASE


func test_vista_exists_in_the_live_village() -> void:
	assert_not_null(_vista(), "HarmoniaVillage must build a CastleVista — the after_cave pan aims at it")


func test_castle_silhouette_clears_the_tilemap_entirely() -> void:
	# THE regression. Any part of the silhouette at or below the tilemap's
	# first row is painted over by opaque tiles, because the vista renders
	# behind the tilemap. "Above the top row" is the visibility invariant.
	var tm: TileMapLayer = _village.tile_map
	assert_not_null(tm, "village must have a tile_map")
	var used: Rect2i = tm.get_used_rect()
	var first_tile_y: float = float(used.position.y * _village.TILE_SIZE)
	assert_true(_castle_base_y() <= first_tile_y,
		"the castle's BASELINE (%.1f) must sit at or above the tilemap's first row (%.1f) — below it, opaque tiles paint over the silhouette and only the roof tips show" % [
			_castle_base_y(), first_tile_y])
	assert_true(_castle_top_y() < _castle_base_y(),
		"sanity: the silhouette must rise upward from its baseline")


func test_vista_renders_behind_the_tilemap_by_design() -> void:
	# Position, not z-order, is what guarantees visibility. Pinning z_index
	# here documents that the vista is DELIBERATELY behind the tilemap, so the
	# only thing keeping it visible is standing clear of the map — which is
	# what the test above enforces. Flipping z to draw over the village would
	# be a different (and wrong) fix: it would cover the perimeter wall.
	assert_eq(_vista().z_index, -2,
		"vista stays behind the tilemap; it is kept visible by POSITION, not by z-order")


func test_the_look_east_pan_actually_frames_the_castle() -> void:
	# A camera target that merely sits in-bounds proved nothing — the old one
	# was in-bounds and showed a wall. Require the target to land within the
	# silhouette's vertical span, so the pan is aimed at the castle itself.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(AFTER_CAVE))
	assert_true(parsed is Dictionary, "after_cave scene must parse")
	var targets: Array = []
	for step in parsed.get("steps", []):
		if step is Dictionary and step.get("type") == "camera_focus" and step.get("target") is Array:
			var t = step["target"]
			targets.append(Vector2(float(t[0]), float(t[1])))
	var top := _castle_top_y()
	var base := _castle_base_y()
	var framing := targets.filter(func(p): return p.y >= top and p.y <= base)
	assert_gt(framing.size(), 0,
		"no camera_focus in the scene lands inside the castle's span (%.1f..%.1f) — Theron says 'tell me what you see' and the pan must put the castle on screen. targets: %s" % [
			top, base, str(targets)])


func test_vista_spans_the_visible_width_at_that_pan() -> void:
	# The sky/treeline backdrop has to cover the whole viewport at the pan, or
	# the frame shows engine-grey void beside the castle (which is what the
	# pre-fix shot did above the wall).
	var s := _vista_script()
	var view_w: float = 1280.0 / 2.0   # viewport width / camera zoom
	assert_true(s.SPAN_X >= view_w,
		"vista backdrop (%.0fpx) must be at least as wide as the visible region (%.0fpx) or grey void shows at the edges" % [s.SPAN_X, view_w])
	var view_h: float = 720.0 / 2.0
	assert_true(s.SKY_HEIGHT >= view_h,
		"sky (%.0fpx) must cover the visible height (%.0fpx) above the horizon" % [s.SKY_HEIGHT, view_h])


func test_night_palette_is_distinct_from_day() -> void:
	# The vista polls GameState.is_night and redraws; both palettes ship, so
	# pin that they actually differ (a copy-paste would render day at night).
	var s := _vista_script()
	assert_ne(s.SKY_TOP_NIGHT, s.SKY_TOP_DAY, "night sky must differ from day")
	assert_ne(s.TREE_NIGHT, s.TREE_DAY, "night treeline must differ from day")
	assert_ne(s.WINDOW_NIGHT, s.WINDOW_DAY, "lit windows are the night read")
