extends GutTest

## tick 64: tenth interior, first in W4 (industrial). RivetRow gets
## Steward Vetch's Local 8743 Union Hall — foreshadows the Assembly
## Core dungeon AND the warden_industrial boss with a class-conscious
## frame nobody else has used yet.

const HALL := "res://src/maps/interiors/RivetRowUnionHallInterior.gd"
const RIVET_ROW := "res://src/maps/villages/RivetRowVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_hall_extends_base_interior() -> void:
	var src := _read(HALL)
	assert_true(src.contains("extends BaseInterior"),
		"hall must extend BaseInterior — tenth interior, abstraction must keep holding")
	assert_true(src.contains("class_name RivetRowUnionHallInterior"),
		"class_name must exist for GameLoop preload")


func test_hall_payload_foreshadows_assembly_core_and_warden() -> void:
	# Vetch must name the Core AND the Warden — both are concrete
	# W4 hooks (AssemblyCore dungeon + warden_industrial boss).
	var src := _read(HALL)
	assert_true(src.contains("Steward Vetch"),
		"hall must spawn Steward Vetch — the room's payload NPC")
	assert_true(src.contains("Core"),
		"Vetch must reference 'the Core' — hooks into the AssemblyCore dungeon")
	assert_true(src.contains("Warden") or src.contains("warden"),
		"Vetch must reference 'the Warden' — hooks into the warden_industrial boss")


func test_hall_uses_class_conscious_frame() -> void:
	# The unique narrative angle of this interior — none of the prior
	# nine interiors used a worker / labor / management frame.
	var src := _read(HALL)
	assert_true(src.contains("second shift") or src.contains("strike") or src.contains("union") or src.contains("ledger"),
		"Vetch's lines must use union/strike/ledger framing — distinguishes this room narratively from the prior nine")
	# Concrete advice with class-conscious framing: 'don't take their offer'.
	assert_true(src.contains("don't take their offer") or src.contains("always make an offer"),
		"Vetch must give the 'don't take their offer' advice — the room's signature warning")


func test_hall_exit_returns_to_rivet_row() -> void:
	var src := _read(HALL)
	assert_true(src.contains("target_map = \"rivet_row_village\""),
		"hall exit must target rivet_row_village")
	assert_true(src.contains("target_spawn = \"union_hall_exit\""),
		"hall exit must spawn at union_hall_exit")


func test_game_loop_routes_rivet_row_union_hall() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("RivetRowUnionHallInteriorScript = preload"),
		"GameLoop must preload the hall script")
	assert_true(src.contains("\"rivet_row_union_hall\":"),
		"GameLoop scene routing must include rivet_row_union_hall")
	assert_true(src.contains("\"rivet_row_union_hall\":\n\t\t\treturn \"industrial\""),
		"rivet_row_union_hall must map to 'industrial' terrain — W4's battle backdrop")


func test_rivet_row_has_door_via_helper() -> void:
	var src := _read(RIVET_ROW)
	assert_true(src.contains("spawn_points[\"union_hall_exit\"]"),
		"RivetRowVillage must define union_hall_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"UnionHallDoor\", \"rivet_row_union_hall\""),
		"hall door must use the shared _add_interior_door helper from BaseVillage")


func test_teleport_menu_lists_hall() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("rivet_row_union_hall"),
		"TeleportMenu must list rivet_row_union_hall")
