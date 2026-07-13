extends GutTest

## Playtest 2026-07-12 (user furious, recurring): W1 village object detection.
## 1. A treasure chest opened from ~5 player-lengths away, offset right+down.
##    Root: TreasureChest._setup_collision hard-coded a Mode-7-sized 128px x
##    ~214px billboard grab ellipse, used UNCHANGED in flat villages. Now
##    gated on Mode7Overlay.is_active (small 40px zone when flat).
## 2. The library door wouldn't trigger even standing on its arrow. Root:
##    _add_interior_door centered a 64x32 box on the door origin, which sits
##    in the impassable wall row; the walkable approach is one row below, so
##    body_entered never fired. Now the box shifts DOWN onto the walkable tile.

const ChestScript = preload("res://src/exploration/TreasureChest.gd")


func _first_circle_radius(node: Node) -> float:
	for c in node.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is CircleShape2D:
			return ((c as CollisionShape2D).shape as CircleShape2D).radius
	return -1.0


func test_chest_grab_zone_is_small_in_flat_village() -> void:
	var prev: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = false
	var chest = ChestScript.new()
	chest._setup_collision()
	var r := _first_circle_radius(chest)
	assert_eq(r, 40.0,
		"flat-village chest must use a ~1.25-tile grab zone, NOT the 128px Mode 7 billboard (opened from 5 tiles away)")
	chest.free()
	Mode7Overlay.is_active = prev


func test_chest_grab_zone_stays_large_on_mode7_overworld() -> void:
	var prev: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = true
	var chest = ChestScript.new()
	chest._setup_collision()
	var r := _first_circle_radius(chest)
	assert_eq(r, 128.0,
		"Mode 7 overworld keeps the tall billboard grab zone so perspective-distant chests stay reachable")
	chest.free()
	Mode7Overlay.is_active = prev


func test_interior_door_trigger_shifted_onto_walkable_row() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/BaseVillage.gd")
	var i := src.find("func _add_interior_door")
	assert_gt(i, -1, "_add_interior_door must exist")
	var body := src.substr(i, 1500)
	assert_true("collision.position = Vector2(0, TILE_SIZE * 0.75)" in body,
		"door trigger must shift DOWN out of the wall row onto the walkable approach, or body_entered never fires")
	assert_true("TILE_SIZE * 1.5" in body,
		"door trigger box must be tall enough that the walkable tile + arrow overlap it")
