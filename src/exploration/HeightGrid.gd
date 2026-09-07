class_name HeightGrid
extends RefCounted
## Pure height-grid math for villages: digit rows in, cliff pieces + the walk-only step rule out. No scene access.

const EDGE_N := 1
const EDGE_E := 2
const EDGE_S := 4
const EDGE_W := 8
const STAIR_CHARS := ["^", "/"]
const DIRS := {EDGE_N: Vector2i(0, -1), EDGE_E: Vector2i(1, 0), EDGE_S: Vector2i(0, 1), EDGE_W: Vector2i(-1, 0)}


static func parse(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var line: Array[int] = []
		var s := str(r)
		for i in range(s.length()):
			line.append(int(s[i]))
		out.append(line)
	return out


static func height_at(grid: Array, cell: Vector2i) -> int:
	if cell.y < 0 or cell.y >= grid.size():
		return -1
	var row: Array = grid[cell.y]
	if cell.x < 0 or cell.x >= row.size():
		return -1
	return int(row[cell.x])


static func stair_cells(map_rows: Array) -> Dictionary:
	var out := {}
	for y in range(map_rows.size()):
		var row := str(map_rows[y])
		for x in range(row.length()):
			if row[x] in STAIR_CHARS:
				out[Vector2i(x, y)] = row[x]
	return out


## Same height, or a ONE-tier step where either end is a stair/ramp.
static func can_step(grid: Array, stairs: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	var a := height_at(grid, from)
	var b := height_at(grid, to)
	if a < 0 or b < 0:
		return false
	if a == b:
		return true
	return absi(a - b) == 1 and (stairs.has(from) or stairs.has(to))


## A south step paints a FACE onto the lower cell (unless it is a wall or stair); every other illegal step becomes an edge bit on the HIGHER cell.
static func derive(grid: Array, stairs: Dictionary, walls: Dictionary = {}) -> Dictionary:
	var faces := {}
	var edges := {}
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var c := Vector2i(x, y)
			var h := height_at(grid, c)
			for bit in DIRS:
				var n: Vector2i = c + DIRS[bit]
				var hn := height_at(grid, n)
				if hn < 0 or hn >= h or can_step(grid, stairs, c, n):
					continue
				if bit == EDGE_S:
					if not walls.has(n) and not stairs.has(n):
						faces[n] = true
				else:
					edges[c] = int(edges.get(c, 0)) | bit
	return {"faces": faces, "edges": edges}
