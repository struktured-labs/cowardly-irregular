extends GutTest

## Tavern dancer stage (struktured, msg 2780 item 2: "make a better stage
## for the dancers" — cowir-main's brief: "the Tonberry's stage is a bare
## sprite offset today; build an actual platform visual (raised planks,
## edge trim, maybe a light wash/spotlight on the dancer)").
##
## THE DEFECT BEHIND "bare sprite offset": the stage platform sprite was
## centered at x=16 tiles while the stage floor tiles (`S` in TAVERN_LAYOUT)
## sit at cols 16-23 — centre 20. The whole platform hung FOUR TILES WEST
## of its own floor, so the drawn curtain/planks and the lighter `S` tiles
## only overlapped halfway. The dancer, meanwhile, stood at x=20 — correct
## for the tiles, at the far edge of the sprite.
##
## Written relationship-first from the outset, per today's lesson (the July
## fireplace ratchet asserted a coincidental x=4.5 and went red on a
## legitimate relocation). Everything here derives the stage span from
## TAVERN_LAYOUT and asserts agreement, so the stage can be moved or
## resized freely and only genuine misalignment fails.

const TAVERN := "res://src/maps/interiors/TavernInterior.gd"


func _read() -> String:
	return FileAccess.get_file_as_string(TAVERN)


## Recover the `S` tile span straight from the authored layout — the
## single source of truth this test measures everything against.
func _stage_tile_span() -> Dictionary:
	var src := _read()
	var start := src.find("const TAVERN_LAYOUT = [")
	assert_gt(start, 0, "TAVERN_LAYOUT present")
	var body_start := src.find("[", start) + 1
	var body_end := src.find("]", body_start)
	var rows: Array = []
	for m in RegEx.create_from_string("\"([^\"]+)\"").search_all(src.substr(body_start, body_end - body_start)):
		rows.append(m.get_string(1))
	var min_c := 999
	var max_c := -1
	var min_r := 999
	var max_r := -1
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if row[x] == "S":
				min_c = mini(min_c, x)
				max_c = maxi(max_c, x)
				min_r = mini(min_r, y)
				max_r = maxi(max_r, y)
	return {"c0": min_c, "c1": max_c, "r0": min_r, "r1": max_r}


func test_stage_constants_match_the_authored_tiles() -> void:
	var span := _stage_tile_span()
	assert_gt(span["c1"], -1, "layout still has stage tiles")
	var t := load(TAVERN)
	assert_eq(t.STAGE_COL_FIRST, span["c0"],
		"STAGE_COL_FIRST must track the S tiles in TAVERN_LAYOUT")
	assert_eq(t.STAGE_COL_LAST, span["c1"],
		"STAGE_COL_LAST must track the S tiles in TAVERN_LAYOUT")
	assert_eq(t.STAGE_ROW_FIRST, span["r0"], "STAGE_ROW_FIRST tracks the tiles")
	assert_eq(t.STAGE_ROW_LAST, span["r1"], "STAGE_ROW_LAST tracks the tiles")


## THE regression: the platform must sit ON its floor tiles. This is the
## assertion that would have caught the 4-tile offset.
func test_platform_is_centred_on_its_own_floor_tiles() -> void:
	var span := _stage_tile_span()
	var t := load(TAVERN)
	var expected_x: float = (float(span["c0"]) + float(span["c1"]) + 1.0) / 2.0
	var expected_y: float = (float(span["r0"]) + float(span["r1"]) + 1.0) / 2.0
	assert_almost_eq(t.STAGE_CENTER_X, expected_x, 0.01,
		"stage centre X must equal the S-tile span centre — it was 16 against a span centred on 20, hanging the platform 4 tiles west of its own floor")
	assert_almost_eq(t.STAGE_CENTER_Y, expected_y, 0.01,
		"stage centre Y must equal the S-tile span centre")
	# And the sprite must actually USE the derived centre, not a literal
	# that happens to match today.
	var src := _read()
	assert_true(src.contains("sprite.position = Vector2(STAGE_CENTER_X * TILE_SIZE, STAGE_CENTER_Y * TILE_SIZE)"),
		"platform sprite anchors off the derived centre — a matching literal would silently stop tracking if the stage moved")
	assert_false(src.contains("sprite.position = Vector2(16 * TILE_SIZE, 3.5 * TILE_SIZE)"),
		"the old off-by-four anchor must not return")


## The dancer performs ON the stage, so she anchors to the same centre.
## A literal here is how the performer drifts off the platform later.
func test_dancer_anchors_to_the_stage_centre() -> void:
	var src := _read()
	assert_true(src.contains("dancer_sprite.position = Vector2(STAGE_CENTER_X * TILE_SIZE, STAGE_CENTER_Y * TILE_SIZE)"),
		"dancer derives her position from the stage centre rather than a matching literal")


## struktured asked for "a light wash/spotlight on the dancer" — both
## fixtures exist and are parented to the stage so they travel with it.
func test_stage_is_lit() -> void:
	var src := _read()
	assert_true(src.contains("func _add_stage_footlights"),
		"footlight strip along the stage lip — sells a raised platform edge")
	assert_true(src.contains("func _add_stage_spotlight"),
		"overhead wash on the performer, per the brief")
	assert_true(src.contains("_add_stage_footlights(stage)") and src.contains("_add_stage_spotlight(stage)"),
		"both are actually called from _create_stage")
	# Parented to `stage`, not `decorations`, so a future stage move carries
	# the lighting with it instead of stranding lamps over bare floor.
	var idx := src.find("func _add_stage_spotlight")
	var next := src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next - idx) if next > 0 else src.substr(idx)
	assert_true(body.contains("stage.add_child(spot)"),
		"spotlight is parented to the stage node so it travels with the platform")
	assert_true(body.contains("STAGE_CENTER_X"),
		"spotlight centres on the derived stage centre, i.e. on the dancer")


## Footlights sit at the stage LIP (front edge), not its middle — that's
## what reads as a raised platform rather than a lit rectangle.
func test_footlights_sit_at_the_front_lip() -> void:
	var src := _read()
	var idx := src.find("func _add_stage_footlights")
	var next := src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next - idx) if next > 0 else src.substr(idx)
	assert_true(body.contains("STAGE_ROW_LAST"),
		"lip position derives from the stage's last row, not a literal")
	assert_true(body.contains("stage.add_child(lamp)"),
		"footlights parented to the stage so they travel with it")
