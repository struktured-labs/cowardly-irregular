extends GutTest

## Regression: the tavern's flame hung ONE FULL TILE right of its own fireplace surround —
## the identical defect fixed in the inn as task #26, in the sibling scene, never guarded.
## Found by reading smoke/tavern_interior.png: the flames sat at the top-right of the arch
## and spilled past its right edge.
##
##   mantle  11.5 tiles -> x 368, sprite 3x3 tiles -> spans 320..416
##   flame   12.5 tiles -> x 400, sprite 2x2 tiles -> spans 368..432   (16px outside)
##
## Mirrors test_inn_fireplace_alignment_regression: derive the surround's anchor from the
## source and assert everything else agrees with it, rather than pinning a literal. A
## coincidental value goes red on a legitimate relocation and green on a wrong one; the
## relationship survives any move and still catches an off-centre flame.
##
## Only X is asserted. The tavern's flame sits ABOVE the surround's centre by design — its
## 64px sprite is centred at y=352 so its base meets the ash bed at y=384, and flames rise
## from there. The inn's geometry differs, which is why that file's Y assertion is not copied.

const TAVERN := "res://src/maps/interiors/TavernInterior.gd"


func _fn_body(src: String, fn_name: String, fallback_len: int) -> String:
	var i := src.find("func " + fn_name)
	assert_gt(i, -1, "%s present" % fn_name)
	if i < 0:
		return ""
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else fallback_len)


func _anchor_of(body: String, ident: String) -> Vector2:
	var re := RegEx.create_from_string(
		ident.replace(".", "\\.") + "\\.position = Vector2\\(\\s*([0-9.]+) \\* TILE_SIZE,\\s*([0-9.]+) \\* TILE_SIZE\\s*\\)")
	var m := re.search(body)
	if m == null:
		return Vector2.INF
	return Vector2(float(m.get_string(1)), float(m.get_string(2)))


func test_flame_and_light_share_the_mantles_x() -> void:
	var src := FileAccess.get_file_as_string(TAVERN)
	var body := _fn_body(src, "_create_fireplace", 4000)
	var mantle := _anchor_of(body, "mantle")
	var flame := _anchor_of(body, "_fire_sprite")
	var light := _anchor_of(body, "_fireplace_light")

	assert_ne(mantle, Vector2.INF, "mantle anchor is readable — if this fails the test below is vacuous")
	assert_ne(flame, Vector2.INF, "flame anchor is readable")
	assert_ne(light, Vector2.INF, "fireplace light anchor is readable")

	assert_almost_eq(flame.x, mantle.x, 0.01,
		"flame must share the mantle's X — the arch opening is centred there; the defect was a one-tile offset that pushed the flame outside the surround")
	assert_almost_eq(light.x, mantle.x, 0.01,
		"fire light must share the mantle's X so the glow sits in the opening, not beside it")


func test_flame_sprite_stays_inside_the_surround() -> void:
	# The consequence, stated in pixels: a 2x2-tile flame centred on a 3x3-tile mantle must
	# fit within it. This is what the screenshot showed failing.
	var src := FileAccess.get_file_as_string(TAVERN)
	var body := _fn_body(src, "_create_fireplace", 4000)
	var mantle := _anchor_of(body, "mantle")
	var flame := _anchor_of(body, "_fire_sprite")
	assert_ne(mantle, Vector2.INF, "mantle anchor is readable")
	assert_ne(flame, Vector2.INF, "flame anchor is readable")

	var mantle_half := 1.5  # 3x3 tiles, centred
	var flame_half := 1.0   # 2x2 tiles, centred
	assert_true(flame.x - flame_half >= mantle.x - mantle_half - 0.01,
		"flame's left edge (%.1f) must not sit left of the surround (%.1f)" % [flame.x - flame_half, mantle.x - mantle_half])
	assert_true(flame.x + flame_half <= mantle.x + mantle_half + 0.01,
		"flame's right edge (%.1f) must not spill past the surround (%.1f) — it did, by half a tile" % [flame.x + flame_half, mantle.x + mantle_half])


func test_control_the_anchor_parser_reads_real_values() -> void:
	# CONTROL: every assertion above compares parsed anchors. If the regex silently missed,
	# both would be Vector2.INF and the almost_eq comparisons could pass on equal garbage.
	var src := FileAccess.get_file_as_string(TAVERN)
	var body := _fn_body(src, "_create_fireplace", 4000)
	assert_gt(body.length(), 200, "CONTROL: _create_fireplace body must be non-trivial")
	var mantle := _anchor_of(body, "mantle")
	assert_almost_eq(mantle.y, 11.5, 0.01, "CONTROL: mantle Y parses to its authored 11.5 tiles")
	assert_eq(_anchor_of(body, "definitely_not_a_real_node"), Vector2.INF,
		"CONTROL: a missing identifier must return INF, not a coincidental match")
