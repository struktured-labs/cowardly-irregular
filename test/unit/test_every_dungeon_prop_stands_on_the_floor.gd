extends GutTest

## The sign and save-crystal fixes found the same mistake twice: a dungeon object placed at a fixed pixel offset or a
## cell CORNER rather than on a checked floor cell. This walks every floor of every dungeon and checks every chest,
## save crystal and quest examine point: centred on a cell, and that cell is not a wall.

const DUNGEONS := [
	"res://src/maps/dungeons/WhisperingCave.gd",
	"res://src/maps/dungeons/FireDragonCave.gd",
	"res://src/maps/dungeons/IceDragonCave.gd",
	"res://src/maps/dungeons/LightningDragonCave.gd",
	"res://src/maps/dungeons/ShadowDragonCave.gd",
	"res://src/maps/dungeons/CastleHarmonia.gd",
	"res://src/maps/dungeons/SuburbanUnderground.gd",
	"res://src/maps/dungeons/SteampunkMechanism.gd",
	"res://src/maps/dungeons/AssemblyCore.gd",
	"res://src/maps/dungeons/RootProcess.gd",
	"res://src/maps/dungeons/NullChamber.gd",
	"res://src/maps/dungeons/ContrarianDepths.gd",
]
## Layout chars that draw as wall until a puzzle opens them (DragonCave._char_to_tile_type).
const WALL_CHARS := ["M", "G", "Z", "O", "W"]

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)


func test_every_prop_is_centred_on_a_floor_cell() -> void:
	var checked := 0
	for path in DUNGEONS:
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		add_child_autofree(vp)
		var cave = load(path).new()
		vp.add_child(cave)
		await get_tree().process_frame
		var tile: int = cave.TILE_SIZE
		for f in range(1, int(cave.total_floors) + 1):
			cave._generate_map_for_floor(f)
			cave._setup_transitions_for_floor(f)
			var rows: Array = cave.floor_layouts.get(f, cave.floor_layouts.get(1, []))
			for c in cave.transitions.get_children():
				if c.is_queued_for_deletion() or not (c is SavePoint or c is TreasureChest or c is QuestExaminePoint):
					continue
				checked += 1
				var cell := Vector2i(c.position / tile)
				var ch := "?"
				if cell.y >= 0 and cell.y < rows.size() and cell.x >= 0 and cell.x < str(rows[cell.y]).length():
					ch = str(rows[cell.y])[cell.x]
				var label := "%s floor %d %s at %s" % [path.get_file(), f, c.get_class() if c.get_script() == null else c.get_script().get_global_name(), str(c.position)]
				assert_false(ch in WALL_CHARS or ch == "?", "%s stands on a wall cell '%s'" % [label, ch])
				assert_eq(c.position, (Vector2(cell) + Vector2(0.5, 0.5)) * tile, "%s sits at a cell centre" % label)
	assert_gt(checked, 30, "CONTROL: the walk reached real props (%d)" % checked)
