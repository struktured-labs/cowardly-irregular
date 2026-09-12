extends GutTest

const SCENES := {
	"DragonCave(FireDragonCave)": "res://src/maps/dungeons/FireDragonCave.gd",
	"WhisperingCave": "res://src/maps/dungeons/WhisperingCave.gd",
	"CastleHarmonia": "res://src/maps/dungeons/CastleHarmonia.gd",
	"SteampunkMechanism": "res://src/maps/dungeons/SteampunkMechanism.gd",
	"AssemblyCore": "res://src/maps/dungeons/AssemblyCore.gd",
	"CONTROL HarmoniaVillage": "res://src/maps/villages/HarmoniaVillage.gd",
	"CONTROL InnInterior": "res://src/maps/interiors/InnInterior.gd",
}

func test_probe() -> void:
	for label in SCENES:
		var path: String = SCENES[label]
		if not ResourceLoader.exists(path):
			gut.p("  %-30s MISSING" % label)
			continue
		# Simulate arriving straight from the Mode 7 overworld with the statics still hot.
		Mode7Overlay.is_active = true
		Mode7Overlay.camera_angle = 0.7
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var m = load(path).new()
		vp.add_child(m)
		await get_tree().process_frame
		await get_tree().process_frame
		gut.p("  %-30s after _ready: is_active=%-5s camera_angle=%.2f   is_mode7()=%s" % [
			label, str(Mode7Overlay.is_active), Mode7Overlay.camera_angle, str(InteractGeometry.is_mode7())])
		m.queue_free()
		await get_tree().process_frame
	Mode7Overlay.is_active = false
	Mode7Overlay.camera_angle = 0.0
	assert_true(true)
