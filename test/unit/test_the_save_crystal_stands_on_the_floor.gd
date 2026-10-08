extends GutTest

## DragonCave put each dungeon's save crystal (floor 1 and the floor before the boss) at a FIXED two tiles left of the
## up-stairs, which in the new mazes lands inside a wall or the map border -- the rest stop before the boss could be
## unreachable. It now stands on the nearest free plain-floor cell to that mark, like the signs. Every DragonCave floor
## that carries a crystal is checked.

const DUNGEONS := [
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

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)


func test_every_save_crystal_stands_on_plain_floor() -> void:
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
				if not (c is SavePoint) or c.is_queued_for_deletion():
					continue
				checked += 1
				var cell := Vector2i(c.position / tile)
				var ch := "?"
				if cell.y >= 0 and cell.y < rows.size() and cell.x >= 0 and cell.x < str(rows[cell.y]).length():
					ch = str(rows[cell.y])[cell.x]
				var label := "%s floor %d save crystal at %s" % [path.get_file(), f, str(cell)]
				assert_true(ch in Signpost.SIGN_GROUND, "%s stands on plain floor, got '%s'" % [label, ch])
				assert_eq(c.position, (Vector2(cell) + Vector2(0.5, 0.5)) * tile, "%s sits at a cell centre" % label)
	assert_gt(checked, 15, "CONTROL: the walk reached real save crystals (%d)" % checked)
