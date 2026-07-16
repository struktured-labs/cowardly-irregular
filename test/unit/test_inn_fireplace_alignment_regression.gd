extends GutTest

## Task #26 (struktured cap 2026-07-15 15:11): "fireplace fire is not
## aligned" + the player was standing INSIDE the hearth opening.
##
## Geometry facts: the mantle surround sprite (3×2 tiles) is centered at
## (4.5, 4.5) tiles, so its black arch opening is centered on x=4.5 —
## but the flame sprite was placed at x=5.5 (one full tile right) and the
## hearth had no collision at all.

const INN := "res://src/maps/interiors/InnInterior.gd"


func test_flame_and_light_centered_on_the_arch() -> void:
	var src := FileAccess.get_file_as_string(INN)
	var i := src.find("func _setup_fireplace_anim")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1200)
	assert_true("_fire_sprite.position = Vector2(4.5 * TILE_SIZE" in body,
		"flame must center on x=4.5 tiles — the surround (and its arch) is centered there; 5.5 hung the fire one tile right of the opening")
	assert_true("_fire_light.position = Vector2(4.5 * TILE_SIZE" in body,
		"fire light must track the flame, not the old offset position")


func test_hearth_has_solid_collision() -> void:
	var src := FileAccess.get_file_as_string(INN)
	var i := src.find("func _create_fireplace_surround")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 3000)
	assert_true("HearthCollision" in body,
		"fireplace surround must carry a StaticBody2D — the player could walk into the arch and stand in the fire")
	assert_true("hearth_body.collision_layer = 1" in body,
		"hearth collider must be on the world layer the player collides with")
	assert_true("hearth_body.position = Vector2(4.5 * TILE_SIZE, 4.5 * TILE_SIZE)" in body,
		"collider must cover the surround footprint (same center as the sprite)")
