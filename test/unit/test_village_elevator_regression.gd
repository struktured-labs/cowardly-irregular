extends GutTest

## Component regression for VillageElevator (2026-09-06, struktured's live scope add:
## "elevator would be cool too in the villages"). Verifies interact() rides the player to the
## FAR endpoint, InputLockManager is pushed then popped around the ride, and — using the three
## authored villages as a walkability oracle — every real elevator's endpoints are walkable and
## sit on different tiers.

const VillageElevatorScript := preload("res://src/exploration/VillageElevator.gd")
const HeightGridScript := preload("res://src/exploration/HeightGrid.gd")
const BRASSTON := "res://src/maps/villages/BrasstonVillage.gd"
const RIVET_ROW := "res://src/maps/villages/RivetRowVillage.gd"
const NODE_PRIME := "res://src/maps/villages/NodePrimeVillage.gd"
const TILE := 32

class MockRider extends Node2D:
	var teleported_to: Vector2 = Vector2(-9999, -9999)
	func teleport(pos: Vector2) -> void:
		teleported_to = pos
		global_position = pos


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


func test_interact_from_the_bottom_rides_up_to_the_top() -> void:
	var e := VillageElevatorScript.create(VillageElevatorScript.Style.BRASS, Vector2(100, 200), Vector2(100, 40), "steam_hiss")
	add_child_autofree(e)
	await get_tree().process_frame
	var rider := MockRider.new()
	add_child_autofree(rider)
	rider.global_position = Vector2(100, 200)
	e.interact(rider)
	await get_tree().create_timer(VillageElevatorScript.RIDE_TIME + 0.2).timeout
	assert_eq(rider.teleported_to, Vector2(100, 40), "rider standing at the bottom must land on the top endpoint")


func test_interact_from_the_top_rides_down_to_the_bottom() -> void:
	var e := VillageElevatorScript.create(VillageElevatorScript.Style.HAZARD, Vector2(100, 200), Vector2(100, 40), "armor_clank")
	add_child_autofree(e)
	await get_tree().process_frame
	var rider := MockRider.new()
	add_child_autofree(rider)
	rider.global_position = Vector2(100, 40)
	e.interact(rider)
	await get_tree().create_timer(VillageElevatorScript.RIDE_TIME + 0.2).timeout
	assert_eq(rider.teleported_to, Vector2(100, 200), "rider standing at the top must land on the bottom endpoint")


func test_lock_is_pushed_during_the_ride_and_popped_after() -> void:
	var e := VillageElevatorScript.create(VillageElevatorScript.Style.NEON, Vector2(0, 0), Vector2(0, -100), "portal_activate")
	add_child_autofree(e)
	await get_tree().process_frame
	var rider := MockRider.new()
	add_child_autofree(rider)
	rider.global_position = Vector2(0, 0)
	assert_false(InputLockManager.has_lock(VillageElevatorScript.LOCK_ID), "no lock before the ride")
	e.interact(rider)
	await get_tree().process_frame
	assert_true(InputLockManager.has_lock(VillageElevatorScript.LOCK_ID), "lock held mid-ride")
	await get_tree().create_timer(VillageElevatorScript.RIDE_TIME + 0.2).timeout
	assert_false(InputLockManager.has_lock(VillageElevatorScript.LOCK_ID), "lock released once the ride finishes")


func test_reentrant_interact_is_a_no_op_while_busy() -> void:
	var e := VillageElevatorScript.create(VillageElevatorScript.Style.BRASS, Vector2(0, 0), Vector2(0, -100), "steam_hiss")
	add_child_autofree(e)
	await get_tree().process_frame
	var rider := MockRider.new()
	add_child_autofree(rider)
	rider.global_position = Vector2(0, 0)
	e.interact(rider)
	assert_true(e._busy, "elevator marks itself busy mid-ride")
	e.interact(rider)
	await get_tree().create_timer(VillageElevatorScript.RIDE_TIME + 0.2).timeout
	assert_false(InputLockManager.has_lock(VillageElevatorScript.LOCK_ID), "lock still released exactly once, not double-pushed")


func test_authored_elevators_have_walkable_endpoints_on_different_tiers() -> void:
	var checked := 0
	for path in [BRASSTON, RIVET_ROW, NODE_PRIME]:
		var v = load(path).new()
		add_child_autofree(v)
		await get_tree().process_frame
		await get_tree().process_frame
		for b in v.buildings.get_children():
			if not ("bottom_position" in b and "top_position" in b):
				continue
			checked += 1
			var bc := _cell(b.bottom_position)
			var tc := _cell(b.top_position)
			assert_true(v._is_cell_walkable(bc), "%s bottom endpoint %s must be walkable" % [b.name, bc])
			assert_true(v._is_cell_walkable(tc), "%s top endpoint %s must be walkable" % [b.name, tc])
			assert_ne(HeightGridScript.height_at(v._height_grid, bc), HeightGridScript.height_at(v._height_grid, tc),
				"%s endpoints %s/%s must sit on different tiers" % [b.name, bc, tc])
	assert_eq(checked, 3, "control: all three new villages must carry exactly one elevator each")
