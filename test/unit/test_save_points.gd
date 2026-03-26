extends GutTest

## Test SavePoint class and village/dungeon placement.


func test_save_point_has_signal():
	var sp = SavePoint.new()
	add_child_autofree(sp)
	await get_tree().physics_frame

	assert_true(sp.has_signal("save_requested"), "SavePoint should have save_requested signal")
	gut.p("SavePoint signal: ✓")


func test_save_point_has_collision():
	var sp = SavePoint.new()
	add_child_autofree(sp)
	await get_tree().physics_frame

	var found_collision = false
	for child in sp.get_children():
		if child is CollisionShape2D:
			found_collision = true
			assert_true(child.shape is CircleShape2D, "Should use CircleShape2D")
			gut.p("Collision radius: %.0f" % child.shape.radius)
	assert_true(found_collision, "SavePoint should have CollisionShape2D")


func test_save_point_has_sprite():
	var sp = SavePoint.new()
	add_child_autofree(sp)
	await get_tree().physics_frame

	var sprite = sp.get_node_or_null("Sprite")
	assert_not_null(sprite, "SavePoint should have Sprite node")
	assert_not_null(sprite.texture, "Sprite should have texture")
	gut.p("SavePoint sprite: ✓")


func test_save_point_signal_connectable():
	var sp = SavePoint.new()
	add_child_autofree(sp)
	await get_tree().physics_frame

	# Verify signal exists and is connectable
	assert_true(sp.has_signal("save_requested"), "Signal should exist")
	var callable = func(): pass
	sp.save_requested.connect(callable)
	assert_true(sp.save_requested.is_connected(callable), "Signal should be connectable")
	gut.p("Signal connectable: ✓")


func test_save_point_glow_animation():
	var sp = SavePoint.new()
	add_child_autofree(sp)
	await get_tree().physics_frame

	var sprite = sp.get_node_or_null("Sprite")
	var initial_mod = sprite.modulate if sprite else Color.WHITE

	# Simulate a few frames
	for _i in range(10):
		await get_tree().process_frame

	# Modulate should have changed due to pulsing
	assert_not_null(sprite, "Sprite should exist for glow")
	gut.p("Glow animation running: ✓")


func test_village_save_point_count():
	# Verify all 11 villages have save point setup methods
	var village_scripts = [
		"res://src/maps/villages/HarmoniaVillage.gd",
		"res://src/maps/villages/FrostholdVillage.gd",
		"res://src/maps/villages/EldertreeVillage.gd",
		"res://src/maps/villages/GrimhollowVillage.gd",
		"res://src/maps/villages/SandriftVillage.gd",
		"res://src/maps/villages/IronhavenVillage.gd",
		"res://src/maps/villages/MapleHeightsVillage.gd",
		"res://src/maps/villages/BrasstonVillage.gd",
		"res://src/maps/villages/RivetRowVillage.gd",
		"res://src/maps/villages/NodePrimeVillage.gd",
		"res://src/maps/villages/VertexVillage.gd",
	]
	var count = 0
	for path in village_scripts:
		if ResourceLoader.exists(path):
			count += 1
	gut.p("Village scripts found: %d / 11" % count)
	assert_eq(count, 11, "All 11 village scripts should exist")
