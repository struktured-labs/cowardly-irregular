extends GutTest

## struktured asked for "animations in the dungeons". DungeonAmbience's floor branch only knew "shadow"; every other
## theme -- including the "steam" SteampunkMechanism already declared -- fell through to cave crystals, and the storm
## drain, the factory and the castle never declared a theme at all. Floors now dress by theme: steam vents, drain
## puddle glints, castle dust; the caves keep their crystals.

const W := 20
const H := 16


func _kinds(theme: String) -> Dictionary:
	var rows: Array = []
	for y in H:
		rows.append(".".repeat(W))
	var amb := DungeonAmbience.new()
	add_child_autofree(amb)
	amb.rebuild_for_floor(rows, W, H, theme, 7)
	var kinds := {}
	for e in amb._effects:
		kinds[e["kind"]] = int(kinds.get(e["kind"], 0)) + 1
	return kinds


func test_the_cave_still_grows_crystals() -> void:
	assert_true(_kinds("cave").has("crystal"), "CONTROL: an open cave floor grows crystals")


func test_each_themed_floor_dresses_in_its_own_kind_and_no_crystal() -> void:
	for pair in [["steam", "vent"], ["drain", "puddle"], ["castle", "mote"]]:
		var k := _kinds(pair[0])
		assert_true(k.has(pair[1]), "a %s floor shows %s: %s" % [pair[0], pair[1], str(k)])
		assert_false(k.has("crystal"), "a %s floor grows no cave crystals: %s" % [pair[0], str(k)])


func test_each_dungeon_names_its_theme() -> void:
	var want := {
		"res://src/maps/dungeons/SuburbanUnderground.gd": "drain",
		"res://src/maps/dungeons/SteampunkMechanism.gd": "steam",
		"res://src/maps/dungeons/AssemblyCore.gd": "steam",
		"res://src/maps/dungeons/CastleHarmonia.gd": "castle",
	}
	for path in want:
		var cave = load(path).new()
		autofree(cave)
		assert_eq(cave._get_ambient_fx_theme(), want[path], "%s's ambience theme" % path.get_file())
