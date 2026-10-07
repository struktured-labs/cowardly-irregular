extends GutTest

## Descending into a dungeon floor must not seal you in.
##
## Found 2026-08-08 reproducing struktured's "got stuck after teleporting" report.
## `NullChamber` floor 2 and `SuburbanUnderground` floor 2 authored the up-stairs inside a
## walled room with no door:
##
##     M......MMMMMM......M
##     M......M....M......M
##     M......M..U.M......M     <- U = stairs_up, 8 walkable cells, no exit
##     M......MMMMMM......M
##
## `DragonCave._transition_to_floor` spawns you at `stairs_up` when you descend to any floor
## above the first, so descending from floor 3 dropped the player into an 8-cell box whose
## only exit was the staircase back up. Deterministic — the layouts are authored ASCII and
## the only `rand` in these files picks flavour text — so every player hit it every time.
##
## THE PREDICATE IS ARRIVAL-REACHES-EXIT, NOT PERCENTAGE-OF-FLOOR. My first version asserted
## a stair must reach 90% of its floor's walkable cells. That is wrong in both directions:
## it flagged Whispering Cave floors 4 and 5, whose concentric spiral leaves a deliberately
## walled inner chamber and outer ring (the stairs there reach each other fine), and it
## would have passed a sealed room that happened to be large. What actually strands a player
## is arriving somewhere the exit cannot be reached from.
##
## SCOPE COMES FROM THE CODE, NOT A SKIP LIST. `_transition_to_floor` uses `entrance` when
## descending to floor 1 and `stairs_up` otherwise, so floor 1's `U` is never an arrival
## point. Two of the four sealed rooms found live on floor 1 and are unreachable dead
## geometry — left alone deliberately, flagged rather than silently re-cut.
##
## Whispering Cave also holds three treasures no staircase reaches (floor 4 at (4,15) and
## (18,15), floor 5 at (11,10)). Those are inside the spiral's sealed chambers. Reported,
## not fixed: recutting authored maze geometry is a design act, not a wiring one.

const DUNGEON_DIR := "res://src/maps/dungeons"
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const WALL := "M"
## Floor 1 is entered via `entrance`; only floors above it spawn you on `stairs_up`.
const FIRST_ARRIVAL_FLOOR := 2
## struktured 2026-10-07 ruling ("Required, Zelda-style"): every W1 dragon cave floor from 2 up
## to the boss floor now gates its exit stairs behind a REQUIRED puzzle (key/door, lever/flip,
## pushable block + pylon, timed plate/gate, mirror lever, or an ice-slide crossing). This plain
## ASCII sweep has no notion of locks/switches/mechanics state -- it treats a 'G'/'Z'/'O'/'W' char
## as open (not "M", so not WALL) but a lever/mirror gate is a literal 'M' until its switch fires,
## which this sweep can never see opening. Both shapes would read as "stranding" here for a
## floor that is actually fully solvable. These four files are certified instead by the
## mechanics-aware solver in test_w1_dungeon_depth_solver.gd (which models every required
## mechanic, including a mutation control proving each gate actually blocks). W2-W6 dungeons are
## UNCHANGED and still owned by this plain sweep -- see test_later_world_dungeon_depth_solver.gd's
## own header for why they stay simpler.
const W1_REQUIRED_GATE_FILES := ["FireDragonCave.gd", "IceDragonCave.gd", "LightningDragonCave.gd", "ShadowDragonCave.gd"]


func _dungeon_sources() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(DUNGEON_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out[f] = FileAccess.get_file_as_string(DUNGEON_DIR + "/" + f)
	return out


func _floors(src: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("(?s)(\\d+):\\s*\\[(.*?)\\]")
	var row_re := RegEx.create_from_string("\"([^\"]*)\"")
	for m in re.search_all(src):
		var rows: Array = []
		for r in row_re.search_all(m.get_string(2)):
			rows.append(r.get_string(1))
		if not rows.is_empty():
			out.append({"floor": int(m.get_string(1)), "rows": rows})
	return out


func _reachable_from(rows: Array, start: Vector2i) -> Dictionary:
	var walk := {}
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if row[x] != WALL:
				walk[Vector2i(x, y)] = true
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var cur = stack.pop_back()
		for d in DIRS:
			var n = cur + d
			if walk.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen


func _find(rows: Array, ch: String) -> Vector2i:
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if row[x] == ch:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Scope control, as its own test: a parse yielding nothing would satisfy the absence
## assertion below for free, which is the shape this suite keeps producing.
func test_the_layout_parse_finds_arrival_floors() -> void:
	var srcs := _dungeon_sources()
	assert_gt(srcs.size(), 5, "found dungeon scripts — a small count means the directory scan broke")
	# named member: the file an earlier hand-listed sweep of six omitted entirely
	assert_true(srcs.has("WhisperingCave.gd"), "Whispering Cave is in the corpus — a hand-list missed it once")
	assert_false(srcs.has("ZzzNotADungeon.gd"), "a fabricated name is absent, so membership means something")
	var arrival := 0
	for f in srcs:
		for b in _floors(srcs[f]):
			if int(b["floor"]) >= FIRST_ARRIVAL_FLOOR and _find(b["rows"], "U").x >= 0:
				arrival += 1
	assert_gt(arrival, 10, "parsed %d arrival floors carrying a 'U' — too few; the layout or marker changed" % arrival)


func test_descending_never_strands_the_player() -> void:
	var srcs := _dungeon_sources()
	var checked := 0
	var offenders: Array = []
	for f in srcs:
		if W1_REQUIRED_GATE_FILES.has(f):
			continue  # certified by test_w1_dungeon_depth_solver.gd instead -- see this file's const doc
		for b in _floors(srcs[f]):
			if int(b["floor"]) < FIRST_ARRIVAL_FLOOR:
				continue
			var rows: Array = b["rows"]
			var arrival := _find(rows, "U")
			var exit_stair := _find(rows, "D")
			if arrival.x < 0 or exit_stair.x < 0:
				continue
			checked += 1
			var reach := _reachable_from(rows, arrival)
			if not reach.has(exit_stair):
				offenders.append("%s floor %d: descending spawns at %s, which cannot reach the exit stair at %s (%d cells reachable)" % [
					f, int(b["floor"]), str(arrival), str(exit_stair), reach.size()])
	assert_gt(checked, 10, "checked %d arrival floors — too few to be a sweep" % checked)
	assert_true(offenders.is_empty(),
		"%d dungeon floor(s) strand the player on arrival:\n  %s" % [offenders.size(), "\n  ".join(offenders)])


## The exemption above is earned, not convenient: every excluded file really does carry a
## required gate this plain sweep cannot see past (a lever/mirror gate is a literal 'M' until a
## switch/lever fires, invisible to this file's WALL-only model) -- if a future edit removed the
## gate without removing the exemption, THIS test would catch the resulting false pass.
func test_the_w1_exemption_is_earned_by_a_real_gate_this_sweep_cannot_see() -> void:
	var srcs := _dungeon_sources()
	assert_eq(W1_REQUIRED_GATE_FILES.size(), 4, "sanity: exactly the four W1 dragon caves are exempt")
	var proven := 0
	for f in W1_REQUIRED_GATE_FILES:
		assert_true(srcs.has(f), "%s: must exist in the dungeon corpus for the exemption to mean anything" % f)
		var src: String = srcs[f]
		var gated_floor_found := false
		for b in _floors(src):
			if int(b["floor"]) < FIRST_ARRIVAL_FLOOR:
				continue
			var rows: Array = b["rows"]
			var arrival := _find(rows, "U")
			var exit_stair := _find(rows, "D")
			if arrival.x < 0 or exit_stair.x < 0:
				continue
			# Naive reach treats every non-'M' char (including this engine's own G/Z/O/W lock
			# glyphs) as open -- so if THIS still fails to connect them, a real wall ('M', only
			# opened by a lever/mirror switch this sweep never evaluates) is in the way.
			if not _reachable_from(rows, arrival).has(exit_stair):
				gated_floor_found = true
				proven += 1
		assert_true(gated_floor_found, "%s: expected at least one floor where the naive (mechanics-blind) sweep is actually blocked" % f)
	assert_gte(proven, 4, "CONTROL: expected at least one proven gate per exempt file, found %d" % proven)
