extends GutTest

const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")

## Measured 2026-11-20 (cowir-main 26735): Vertex's map is 576 px wide and the village camera shows 640, so no camera limit could keep
## the view on the map and a 64 px band of nothing stood down the screen's left edge from every spot a player could stand.

const VILLAGE_DIR := "res://src/maps/villages"
const VERTEX := "res://src/maps/villages/VertexVillage.gd"
const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"

var _vps: Array = []


func after_each() -> void:
	for vp in _vps:
		if is_instance_valid(vp):
			vp.free()
	_vps.clear()


func _build(path: String) -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child(vp)
	_vps.append(vp)
	var v: Node = load(path).new()
	vp.add_child(v)
	return v


## What the project's own screen shows of a village at its camera's zoom.
func _view(v: Node) -> Vector2:
	return Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")), float(ProjectSettings.get_setting("display/window/size/viewport_height"))) / v.camera.zoom


func _limits(v: Node) -> Rect2i:
	return Rect2i(v.camera.limit_left, v.camera.limit_top, v.camera.limit_right - v.camera.limit_left, v.camera.limit_bottom - v.camera.limit_top)


## Cells inside `rect` (pixels) that carry no tile.
func _bare_cells(v: Node, rect: Rect2i) -> Array:
	var bare: Array = []
	var t: int = v.TILE_SIZE
	for y in range(floori(float(rect.position.y) / t), ceili(float(rect.end.y) / t)):
		for x in range(floori(float(rect.position.x) / t), ceili(float(rect.end.x) / t)):
			if v.tile_map.get_cell_source_id(Vector2i(x, y)) == -1:
				bare.append(Vector2i(x, y))
	return bare


func test_everything_a_village_camera_may_show_is_painted() -> void:
	var judged: int = 0
	for path in MapScripts.maps_in(VILLAGE_DIR):
		var v := _build(path)
		await get_tree().process_frame
		if not ("camera" in v) or v.camera == null:
			continue
		var may_show := _limits(v)
		var view := _view(v)
		var file: String = path.get_file()
		assert_true(may_show.size.x >= view.x and may_show.size.y >= view.y, "%s: the camera may show %s but the screen shows %s, so some of the view is past its limits" % [file, str(may_show.size), str(view)])
		var bare := _bare_cells(v, may_show)
		assert_eq(bare.size(), 0, "%s: %d cell(s) the camera may show carry no tile, first %s" % [file, bare.size(), str(bare.slice(0, 3))])
		judged += 1
	assert_gt(judged, 10, "CONTROL: village cameras were judged (%d)" % judged)


func test_vertex_is_narrower_than_the_screen_and_shows_its_own_border() -> void:
	var v := _build(VERTEX)
	await get_tree().process_frame
	var map := Vector2(v._get_map_pixel_size())
	var view := _view(v)
	assert_lt(map.x, view.x, "CONTROL: Vertex's map (%.0f) is narrower than the screen's view (%.0f)" % [map.x, view.x])
	var spill: Vector2i = v.camera_spill(map, v.camera.zoom)
	assert_eq(spill, Vector2i(ceili((view.x - map.x) / 2.0), 0), "the spill is half the shortfall on each side, and none where the map is tall enough")
	assert_eq(v.camera.limit_left, -spill.x, "the camera may look that far left of the map")
	assert_eq(v.camera.limit_right, int(map.x) + spill.x, "and that far right of it: the village sits centred")
	var cols: int = int(map.x) / v.TILE_SIZE
	for y in [0, 3, int(map.y) / v.TILE_SIZE - 1]:
		assert_eq(v.tile_map.get_cell_atlas_coords(Vector2i(-1, y)), v.tile_map.get_cell_atlas_coords(Vector2i(0, y)), "row %d: the cell left of the map repeats the map's own edge" % y)
		assert_eq(v.tile_map.get_cell_atlas_coords(Vector2i(cols, y)), v.tile_map.get_cell_atlas_coords(Vector2i(cols - 1, y)), "row %d: the cell right of the map repeats the map's own edge" % y)
		assert_ne(v.tile_map.get_cell_source_id(Vector2i(-1, y)), -1, "row %d: that cell is painted at all" % y)


func test_a_village_that_fills_the_screen_is_left_alone() -> void:
	var v := _build(HARMONIA)
	await get_tree().process_frame
	var map := Vector2i(v._get_map_pixel_size())
	assert_gt(float(map.x), _view(v).x, "CONTROL: Harmonia is wider than the screen")
	assert_eq(_limits(v), Rect2i(Vector2i.ZERO, map), "its camera stops at the map's own edge, as before")
	assert_eq(v.tile_map.get_cell_source_id(Vector2i(-1, 3)), -1, "and nothing is painted past it")


func test_the_spill_is_half_the_shortfall_and_never_negative() -> void:
	var zoom := Vector2(2.0, 2.0)
	var view := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")), float(ProjectSettings.get_setting("display/window/size/viewport_height"))) / zoom
	assert_eq(BaseVillage.camera_spill(view, zoom), Vector2i.ZERO, "a map exactly the screen's size spills nothing")
	assert_eq(BaseVillage.camera_spill(view * 3.0, zoom), Vector2i.ZERO, "a larger one spills nothing")
	assert_eq(BaseVillage.camera_spill(view - Vector2(100, 61), zoom), Vector2i(50, 31), "a smaller one spills half its shortfall per side, rounded up")
