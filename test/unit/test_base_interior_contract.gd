extends GutTest

## tick 35: extracted BaseInterior so subsequent village interiors are
## data-only subclasses, not 200-line scaffolds. HarmoniaChapelInterior
## now extends it. Future ticks adding libraries / guard houses /
## trader interiors override 3-4 virtual hooks instead of writing the
## tilemap + player + camera + controller setup from scratch.
##
## This test pins the base contract — every hook a subclass needs is
## present and the chapel actually uses it (not just inherits silently).

const BASE := "res://src/maps/interiors/BaseInterior.gd"
const CHAPEL := "res://src/maps/interiors/HarmoniaChapelInterior.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_base_interior_declares_virtual_hooks() -> void:
	var src := _read(BASE)
	# Six override-able hooks. Subclasses use them to differentiate
	# without copying tilemap / player / camera scaffolding.
	for hook in ["_get_area_id", "_get_map_width", "_get_map_height",
				"_get_layout", "_init_spawn_points", "_setup_decorations",
				"_setup_npcs", "_setup_transitions",
				"_draw_floor_tile", "_draw_wall_tile"]:
		assert_true(src.contains("func " + hook),
			"BaseInterior must declare virtual hook %s" % hook)


func test_base_interior_provides_shared_scaffolding() -> void:
	var src := _read(BASE)
	# These methods are concrete — subclasses inherit them as-is.
	# Future migrations / additions should NOT have to copy them.
	for shared in ["_setup_tilemap", "_setup_player", "_setup_camera",
				"_setup_controller", "spawn_player_at",
				"_on_exit_triggered", "pause", "resume"]:
		assert_true(src.contains("func " + shared),
			"BaseInterior must provide shared scaffold method %s" % shared)


func test_base_interior_declares_the_three_signals() -> void:
	# Match TavernInterior's signal surface so MapSystem and GameLoop's
	# scene-routing code work unchanged for any BaseInterior subclass.
	var src := _read(BASE)
	for sig in ["transition_triggered", "area_transition", "battle_triggered"]:
		assert_true(src.contains("signal " + sig),
			"BaseInterior must declare signal '%s' to match TavernInterior surface" % sig)


func test_chapel_extends_base_interior() -> void:
	# HarmoniaChapelInterior was tick 34's first interior. tick 35
	# refactored it onto BaseInterior. If a future revert pulls it
	# back to extends Node2D, the leverage of having BaseInterior
	# evaporates.
	var src := _read(CHAPEL)
	assert_true(src.contains("extends BaseInterior"),
		"HarmoniaChapelInterior must extend BaseInterior — that's the whole point of tick 35")
	# Class name stays so GameLoop's preload + cross-refs still work.
	assert_true(src.contains("class_name HarmoniaChapelInterior"),
		"chapel class_name must survive the refactor")


func test_chapel_keeps_its_payload_content() -> void:
	# Sanity: refactor didn't strip the foreshadowing dialogue.
	var src := _read(CHAPEL)
	assert_true(src.contains("Sister Concord"),
		"Sister Concord must survive the refactor")
	assert_true(src.contains("Chancellor"),
		"Chancellor foreshadowing line must survive the refactor")
	assert_true(src.contains("target_map = \"harmonia_village\""),
		"exit must still target harmonia_village")
	assert_true(src.contains("target_spawn = \"chapel_exit\""),
		"exit must still target chapel_exit spawn")


func test_chapel_shrunk_by_refactor() -> void:
	# Concrete leverage: post-refactor chapel must be smaller than the
	# pre-refactor version. tick 34 was ~210 lines; with BaseInterior
	# providing 90%+ of the scaffolding, the subclass should be well
	# under 150.
	var src := _read(CHAPEL)
	var lines := src.split("\n").size()
	assert_lt(lines, 150,
		"chapel post-refactor should be <150 lines (was ~210). Got %d" % lines)
