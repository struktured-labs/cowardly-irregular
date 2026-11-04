extends GutTest

## struktured 2026-11-01 (via cowir-main 21319): "The doors need an opening animation I think." Each drawn building's door
## opens from ITS OWN pixels (tools/gen_door_strips.py): the strip's first frame is the painted door, the last is open.
## The rect is the leaf in the art's own pixels, the contract cowir-overworld's door wiring reads (21329).

const MIN_DOORS := 20


func _doors() -> Dictionary:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var out := {}
	for k in (m as Dictionary).get("building_art", {}):
		var e: Dictionary = m["building_art"][k]
		if e.has("door"):
			out[k] = e
	return out


func test_enough_buildings_have_a_drawn_door() -> void:
	assert_gte(_doors().size(), MIN_DOORS, "FLOOR: only %d drawn buildings declare a door" % _doors().size())


func test_each_door_strip_fits_its_rect_and_its_art() -> void:
	for k in _doors():
		var e: Dictionary = _doors()[k]
		var d: Dictionary = e["door"]
		var r: Array = d["rect"]
		var art: Image = (load(str(e["path"])) as Texture2D).get_image()
		var strip: Image = (load(str(d["open"])) as Texture2D).get_image()
		assert_true(int(r[0]) >= 0 and int(r[1]) >= 0 and int(r[0]) + int(r[2]) <= art.get_width() and int(r[1]) + int(r[3]) <= art.get_height(), "%s: the door rect %s leaves its art" % [k, r])
		assert_eq(strip.get_size(), Vector2i(int(r[2]) * int(d["frames"]), int(r[3])), "%s: the strip is not %d cells of its rect" % [k, int(d["frames"])])
		assert_true(str(d.get("style", "")) in ["house", "shop"], "%s: door style '%s' names no cue" % [k, d.get("style", "")])


func _changed(a: Image, ax: int, ay: int, b: Image, bx: int, by: int, w: int, h: int) -> float:
	var n := 0
	var diff := 0
	for y in range(h):
		for x in range(w):
			var cb := b.get_pixel(bx + x, by + y)
			if cb.a < 0.5:
				continue
			n += 1
			var ca := a.get_pixel(ax + x, ay + y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				diff += 1
	return float(diff) / maxf(n, 1.0)


func test_the_closed_frame_is_the_painted_door_and_the_last_is_open() -> void:
	for k in _doors():
		var e: Dictionary = _doors()[k]
		var d: Dictionary = e["door"]
		var r: Array = d["rect"]
		var art: Image = (load(str(e["path"])) as Texture2D).get_image()
		var strip: Image = (load(str(d["open"])) as Texture2D).get_image()
		var w := int(r[2])
		var h := int(r[3])
		var last := (int(d["frames"]) - 1) * w
		assert_lt(_changed(art, int(r[0]), int(r[1]), strip, 0, 0, w, h), 0.02, "%s: the closed frame is not the painted door" % k)
		assert_gt(_changed(art, int(r[0]), int(r[1]), strip, last, 0, w, h), 0.3, "%s: the last frame does not open the door" % k)
