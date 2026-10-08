extends GutTest

## Every dungeon's lore sign was placed at `pos * TILE_SIZE` — a cell's top-left CORNER — so it straddled four cells and
## drew half in a wall or over the stairs (the W2 storm drain's two "→" signs flanking its ▼); the orientation signs used
## fixed offsets that landed inside maze walls. All of them now stand centred on a free plain-floor cell. Walks every
## floor of every dungeon that places signs and checks each live Signpost.

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

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)


func _signs(cave: Node) -> Array:
	var out: Array = []
	for c in cave.transitions.get_children():
		if c is Signpost and not c.is_queued_for_deletion():
			out.append(c)
	return out


func test_every_dungeon_sign_stands_centred_on_free_floor() -> void:
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
			var spawn_cells := {}
			for k in cave.spawn_points:
				if cave.spawn_points[k] is Vector2:
					spawn_cells[Vector2i(cave.spawn_points[k] / tile)] = k
			var used := {}
			for s in _signs(cave):
				var p: Vector2 = s.position
				var cell := Vector2i(p / tile)
				var label := "%s floor %d sign '%s'" % [path.get_file(), f, str(s.sign_text).substr(0, 24)]
				checked += 1
				assert_eq(p, (Vector2(cell) + Vector2(0.5, 0.5)) * tile, "%s sits at a cell centre, not a corner" % label)
				var ch := "?"
				if cell.y >= 0 and cell.y < rows.size() and cell.x >= 0 and cell.x < str(rows[cell.y]).length():
					ch = str(rows[cell.y])[cell.x]
				assert_true(ch in Signpost.SIGN_GROUND, "%s stands on plain floor, got '%s'" % [label, ch])
				assert_false(spawn_cells.has(cell), "%s is not on a spawn cell (%s)" % [label, str(spawn_cells.get(cell, ""))])
				assert_false(used.has(cell), "%s does not share a cell with another sign" % label)
				used[cell] = true
	assert_gt(checked, 60, "CONTROL: the walk reached real signs (%d)" % checked)
