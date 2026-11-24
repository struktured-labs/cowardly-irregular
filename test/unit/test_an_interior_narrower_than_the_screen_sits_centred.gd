extends GutTest

## Measured 2026-11-23: 21 of 31 interiors are narrower than the interior camera's 512 px view (18 by 64 px, 3 by 128),
## so each room sat pinned to the screen's left edge with a flat grey band of nothing down its right side.

const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")
const INTERIOR_DIR := "res://src/maps/interiors"
const FILLS_THE_SCREEN := "res://src/maps/interiors/HarmoniaLibraryInterior.gd"

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
	var room: Node = load(path).new()
	vp.add_child(room)
	return room


func _camera(room: Node) -> Camera2D:
	if "camera" in room and room.camera is Camera2D:
		return room.camera
	var found := room.find_children("*", "Camera2D", true, false)
	return found[0] if not found.is_empty() else null


func _view(cam: Camera2D) -> Vector2:
	return Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")), float(ProjectSettings.get_setting("display/window/size/viewport_height"))) / cam.zoom


func _limits(cam: Camera2D) -> Rect2i:
	return Rect2i(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top)


## Cells inside `rect` (pixels) that no tile layer of the room paints.
func _bare_cells(room: Node, rect: Rect2i) -> Array:
	var layers := room.find_children("*", "TileMapLayer", true, false)
	var t: int = 32
	var bare: Array = []
	for y in range(floori(float(rect.position.y) / t), ceili(float(rect.end.y) / t)):
		for x in range(floori(float(rect.position.x) / t), ceili(float(rect.end.x) / t)):
			var painted := false
			for l in layers:
				if (l as TileMapLayer).get_cell_source_id(Vector2i(x, y)) != -1:
					painted = true
					break
			if not painted:
				bare.append(Vector2i(x, y))
	return bare


## The first interior whose room is narrower than the view, read off the room's own size.
func _a_narrow_room() -> String:
	for path in MapScripts.maps_in(INTERIOR_DIR):
		var s: Script = load(path)
		var probe: Node = s.new()
		var narrow: bool = probe.has_method("_get_map_width") and probe._get_map_width() * 32 < 512
		probe.free()
		if narrow:
			return path
	return ""


func test_everything_an_interior_camera_may_show_is_painted() -> void:
	var judged := 0
	var spilled := 0
	for path in MapScripts.maps_in(INTERIOR_DIR):
		var room := _build(path)
		await get_tree().process_frame
		var cam := _camera(room)
		if cam == null:
			continue
		var file: String = path.get_file()
		var may_show := _limits(cam)
		var view := _view(cam)
		assert_true(may_show.size.x >= view.x and may_show.size.y >= view.y, "%s: the camera may show %s but the screen shows %s, so part of the view is past its limits" % [file, str(may_show.size), str(view)])
		var bare := _bare_cells(room, may_show)
		assert_eq(bare.size(), 0, "%s: %d cell(s) the camera may show carry no tile, first %s" % [file, bare.size(), str(bare.slice(0, 3))])
		if may_show.position.x < 0 or may_show.position.y < 0:
			spilled += 1
		judged += 1
	assert_gt(judged, 25, "CONTROL: interior cameras were judged (%d)" % judged)
	assert_gt(spilled, 0, "CONTROL: some interior is narrower than the screen, so this arm judged a spill (%d)" % spilled)


func test_a_narrow_room_sits_centred_inside_its_own_wall() -> void:
	var path := _a_narrow_room()
	assert_ne(path, "", "CONTROL: some interior is narrower than the 512 px view")
	if path == "":
		return
	var room := _build(path)
	await get_tree().process_frame
	var cam := _camera(room)
	var room_w: int = room._get_map_width() * 32
	var left_spill: int = -cam.limit_left
	var right_spill: int = cam.limit_right - room_w
	assert_gt(left_spill, 0, "%s: the camera may look left of the room" % path.get_file())
	assert_eq(left_spill, right_spill, "%s: as far left as right, so the room sits centred" % path.get_file())
	var tm: TileMapLayer = room.tilemap
	for y in [0, room._get_map_height() / 2, room._get_map_height() - 1]:
		assert_eq(tm.get_cell_source_id(Vector2i(-1, y)), 1, "row %d: left of the room is the room's wall" % y)
		assert_eq(tm.get_cell_source_id(Vector2i(room._get_map_width(), y)), 1, "row %d: right of the room is the room's wall" % y)


func test_a_room_that_fills_the_screen_is_left_alone() -> void:
	var room := _build(FILLS_THE_SCREEN)
	await get_tree().process_frame
	var cam := _camera(room)
	var size := Vector2i(room._get_map_width() * 32, room._get_map_height() * 32)
	assert_gt(float(size.x), _view(cam).x, "CONTROL: the library is wider than the view")
	assert_eq(_limits(cam), Rect2i(Vector2i.ZERO, size), "its camera stops at the room's own edge, as before")
	assert_eq(room.tilemap.get_cell_source_id(Vector2i(-1, 3)), -1, "and nothing is painted past it")
