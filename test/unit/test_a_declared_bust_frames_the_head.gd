extends GutTest

## A monster's cutscene bust is cut by bust_region(), which squares the WHOLE figure. For a wide boss that square is the
## whole body: the storm dragon's 211px figure fit in a 72px cell left its head lost among the lightning bolts
## (cowir-cutscenes' render 2026-11-05, .774). A sheet may now declare `bust_rect` [x, y, w, h] in monster_sheets, and
## bust_region returns it. Everything that declares nothing keeps the measured crop, so job busts are untouched.

const RATIO := 0.55
## Frame-0 landmarks of lightning_dragon.png, read off a gridded 3x render. Re-measure if the art is redrawn.
const STORM_EYE := Vector2i(172, 108)
const STORM_SNOUT := Vector2i(192, 125)


func _sheets() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return manifest["monster_sheets"]


func _declared(id: String) -> Rect2i:
	var r: Array = (_sheets()[id] as Dictionary).get("bust_rect", [])
	return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])) if r.size() == 4 else Rect2i()


func test_a_declared_bust_is_the_box_the_cutscene_crops() -> void:
	var entry: Dictionary = _sheets()["lightning_dragon"]
	var want := _declared("lightning_dragon")
	assert_gt(want.size.x, 0, "CONTROL: lightning_dragon declares a bust_rect")
	var got := HybridSpriteLoader.bust_region(str(entry["path"]), int(entry["frame_height"]), RATIO)
	assert_eq(got, want, "bust_region must return the sheet's declared bust_rect, not the whole-figure square")
	assert_true(got.has_point(STORM_EYE) and got.has_point(STORM_SNOUT),
		"the declared storm-dragon bust holds its eye and snout: %s" % got)


func test_a_sheet_that_declares_nothing_keeps_the_measured_crop() -> void:
	## CONTROL: fire_dragon declares no bust, so its crop is still the figure square (side = figure width).
	var entry: Dictionary = _sheets()["fire_dragon"]
	assert_false(entry.has("bust_rect"), "CONTROL: fire_dragon declares no bust_rect")
	var path := str(entry["path"])
	var fig := HybridSpriteLoader.figure_rect(path)
	var got := HybridSpriteLoader.bust_region(path, int(entry["frame_height"]), RATIO)
	assert_gt(fig.size.x, 0, "CONTROL: the fire dragon's figure measures")
	assert_eq(got.size.x, maxi(fig.size.x, int(round(fig.size.y * RATIO))), "an undeclared sheet keeps the measured square")


func test_every_declared_bust_is_a_square_inside_its_frame() -> void:
	var bad: Array = []
	var declared := 0
	for id in _sheets():
		var e: Dictionary = _sheets()[id]
		if not e.has("bust_rect"):
			continue
		declared += 1
		var r := _declared(str(id))
		var frame: int = int(e.get("frame_height", 0))
		if r.size.x <= 0 or r.size.x != r.size.y or r.position.x < 0 or r.position.y < 0 \
				or r.end.x > frame or r.end.y > frame:
			bad.append("%s %s in a %dpx frame" % [id, r, frame])
	assert_gt(declared, 0, "ANTI-VACUITY: no sheet declares a bust_rect")
	assert_eq(bad, [], "a bust_rect must be a non-empty square inside frame 0: %s" % [bad])
