extends GutTest

## Task #26 (struktured cap 2026-07-15 15:11): "fireplace fire is not
## aligned" + the player was standing INSIDE the hearth opening.
##
## The bug: the mantle surround sprite (3×2 tiles) has its black arch
## opening centered on the surround's own X, but the flame sprite was
## placed one full tile to the right, and the hearth had no collision.
##
## 2026-07-25 — REWRITTEN to pin the RELATIONSHIPS instead of the literals.
## The original asserted the flame sat at x=4.5 tiles, which was true but
## incidental: it was where the fireplace happened to be. When struktured
## asked for the hearth moved off the innkeeper's counter (msg 2764 item 2)
## this test failed for a legitimate relocation, even though flame, light
## and collider had all moved correctly together.
##
## That is the same trap the Mode 7 displacement work hit today — a check
## that pins a coincidental VALUE goes red on a correct change and green on
## a wrong one, whereas a check that pins the RELATIONSHIP survives every
## legitimate move and still catches the actual defect. So: derive the
## surround's anchor from the source, then assert everything else agrees
## with it. The fireplace can now be moved anywhere without touching this
## file; hanging the fire off-center still fails.

const INN := "res://src/maps/interiors/InnInterior.gd"


func _fn_body(src: String, fn_name: String, fallback_len: int) -> String:
	var i := src.find("func " + fn_name)
	assert_gt(i, -1, "%s present" % fn_name)
	if i < 0:
		return ""
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else fallback_len)


## Pull the (x, y) tile anchor out of a `<name>.position = Vector2(X *
## TILE_SIZE, Y * TILE_SIZE)` assignment. Returns Vector2.INF when absent
## so callers can assert a clean failure rather than silently comparing
## zeroes.
func _anchor_of(body: String, ident: String) -> Vector2:
	var re := RegEx.create_from_string(
		ident.replace(".", "\\.") + "\\.position = Vector2\\(\\s*([0-9.]+) \\* TILE_SIZE,\\s*([0-9.]+) \\* TILE_SIZE\\s*\\)")
	var m := re.search(body)
	if m == null:
		return Vector2.INF
	return Vector2(float(m.get_string(1)), float(m.get_string(2)))


func test_flame_and_light_centered_on_the_arch() -> void:
	var src := FileAccess.get_file_as_string(INN)
	var surround := _anchor_of(_fn_body(src, "_create_fireplace_surround", 3000), "surround")
	var anim := _fn_body(src, "_setup_fireplace_anim", 1200)
	var flame := _anchor_of(anim, "_fire_sprite")
	var light := _anchor_of(anim, "_fire_light")

	assert_ne(surround, Vector2.INF, "surround anchor is readable")
	assert_ne(flame, Vector2.INF, "flame anchor is readable")
	assert_ne(light, Vector2.INF, "fire-light anchor is readable")

	# THE bug from task #26: flame hung one tile right of the arch.
	assert_almost_eq(flame.x, surround.x, 0.01,
		"flame must share the surround's X — the arch opening is centered there; the original defect was a one-tile offset")
	assert_almost_eq(light.x, surround.x, 0.01,
		"fire light must share the surround's X so the glow sits in the opening, not beside it")

	# The flame sits IN the hearth mouth, i.e. below the surround's centre,
	# and the light sits at or below the flame. Relative, so a relocation
	# preserves it automatically.
	assert_gt(flame.y, surround.y,
		"flame belongs in the hearth mouth, below the surround centre")
	assert_gte(light.y, flame.y,
		"fire light sits at or below the flame, casting up out of the opening")


func test_hearth_has_solid_collision() -> void:
	var src := FileAccess.get_file_as_string(INN)
	var body := _fn_body(src, "_create_fireplace_surround", 3000)
	assert_true("HearthCollision" in body,
		"fireplace surround must carry a StaticBody2D — the player could walk into the arch and stand in the fire")
	assert_true("hearth_body.collision_layer = 1" in body,
		"hearth collider must be on the world layer the player collides with")

	var surround := _anchor_of(body, "surround")
	var collider := _anchor_of(body, "hearth_body")
	assert_ne(collider, Vector2.INF, "hearth collider anchor is readable")
	assert_eq(collider, surround,
		"collider must sit exactly on the surround footprint — a collider left behind at the old spot blocks open floor while the new hearth is walk-through")
