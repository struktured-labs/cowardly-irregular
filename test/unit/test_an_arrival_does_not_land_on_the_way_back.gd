extends GutTest

## 🐛 YOU ARRIVE IN A NEW WORLD STANDING INSIDE THE TRIGGER THAT SENDS YOU BACK — 2 of 4 world
## transitions, at the shipped default. The triggers carry `MODE7_TRIGGER_Y_OFFSET` (-140.6 px) and
## the PLAYER does not: `spawn_player_at` is a bare `player.teleport(spawn_points[name])`. So an
## arrival authored near its own return portal lands inside a 192 px box shifted 140.6 px north of
## its anchor.
##
##     W2 -> W3 Steampunk   arrival (2608, 112)   box 64x192  y   67.4 ..  259.4   INSIDE
##     W4 -> W5 Futuristic  arrival (2608, 3856)  box 64x192  y 3811.4 .. 4003.4   INSIDE
##     W3 -> W4 Industrial  arrival (2896, 3472)  box 64x192  y 3715.4 .. 3907.4   clear
##     W5 -> W6 Abstract    arrival (1232, 2064)  box 64x32   y 2112.0 .. 2144.0   clear
##
## `require_interaction` is true on every one, so it is not an instant bounce. It is worse-shaped:
## `AreaTransition:231` shows the indicator from `body_entered`, so the "Return to ..." prompt is
## already up as the world fades in, and the first interact press — the button a player uses
## reflexively on signs and dialogue — leaves the world they just reached.
##
## ⛔ THIS FILE READS EACH PORTAL'S OWN BOX, AND THAT IS NOT STYLE: MY HAND MEASUREMENT GOT IT WRONG
## BY ASSUMING THE CONSTANT. I used `ENTRANCE_BOX_MODE7` for all four and published "3 of 4".
## `AbstractOverworld` passes `Vector2(TILE_SIZE * 2, TILE_SIZE)` — 64x32, a sixth the height — and
## applies no Mode 7 offset, so W5->W6 clears by 48 px. One box read once and generalised past the
## population it was measured on. **The box comes off the built CollisionShape2D here, never off
## `InteractGeometry`.**
##
## 🔑 TWO CONTROLS, CLEAR FOR DIFFERENT REASONS, which is worth more than two clears:
##     W3 -> W4   clear by DISTANCE   a different column (29 vs 30) and five rows out
##     W5 -> W6   clear by BOX SIZE   64x32, and no offset applied
## A guard that hardcoded the 192 box would red W5->W6. One control cannot tell you the box is being
## read; two that are clear for different reasons can.

const DIR := "res://src/exploration/"
## The arrival KEY is a property of the SOURCE world's forward portal, so it is parsed from there
## rather than written down — a retarget then reaches this guard instead of going quiet.
const FORWARD_MAP := 'forward_portal\\.target_map = "([a-z_]+)"'
const FORWARD_SPAWN := 'forward_portal\\.target_spawn = "([a-z_]+)"'
## suburban's forward portal is the W2->W3 edge; its own arrival comes from W1, which is not a
## per-world script, so W1->W2 is deliberately out of scope and the count below says so.
const SOURCES := ["SuburbanOverworld", "SteampunkOverworld", "IndustrialOverworld", "FuturisticOverworld"]
const MAP_TO_SCRIPT := {
	"suburban_overworld": "SuburbanOverworld",
	"steampunk_overworld": "SteampunkOverworld",
	"industrial_overworld": "IndustrialOverworld",
	"futuristic_overworld": "FuturisticOverworld",
	"abstract_overworld": "AbstractOverworld",
}


## (source world, target world, the spawn key the forward portal names) — derived, not listed.
func _transitions() -> Array:
	var out: Array = []
	for src in SOURCES:
		var raw := FileAccess.get_file_as_string(DIR + src + ".gd")
		if raw == "":
			continue
		var m := RegEx.create_from_string(FORWARD_MAP).search(raw)
		var s := RegEx.create_from_string(FORWARD_SPAWN).search(raw)
		if m == null or s == null:
			continue
		var target: String = str(MAP_TO_SCRIPT.get(m.get_string(1), ""))
		if target == "":
			continue
		out.append({"from": src, "to": target, "key": s.get_string(1)})
	return out


## The live BackPortal of an instantiated world: its position and the size of its REAL shape.
func _back_portal(world: Node) -> Dictionary:
	var found: Node = null
	for child in world.get_children():
		for n in child.get_children():
			if str(n.name) == "BackPortal":
				found = n
				break
		if found != null:
			break
	if found == null:
		return {}
	for c in found.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			return {"pos": (found as Node2D).global_position,
				"box": ((c as CollisionShape2D).shape as RectangleShape2D).size,
				"require_interaction": bool(found.require_interaction) if "require_interaction" in found else false}
	return {}


func test_the_transition_corpus_is_derived_and_real() -> void:
	var t := _transitions()
	assert_eq(t.size(), 4,
		"CONTROL: 4 forward transitions must parse from the per-world scripts (found %d). W1->W2 is out of scope — W1 is OverworldScene, not a per-world variant — and this count is what says so out loud" % t.size())
	var keys: Array = []
	for row in t:
		keys.append("%s->%s via %s" % [row["from"], row["to"], row["key"]])
	keys.sort()
	gut.p("  derived transitions: %s" % ", ".join(keys))


## ⛔ THE ARM THAT MATTERS: no world's arrival spawn may sit inside its own return trigger.
func test_no_arrival_lands_inside_its_return_trigger() -> void:
	var inside: Array = []
	var skipped: Array = []
	var measured := 0
	var boxes: Array = []
	for row in _transitions():
		var scr = load(DIR + str(row["to"]) + ".gd")
		if scr == null or not (scr is GDScript) or not scr.can_instantiate():
			skipped.append("%s: script will not instantiate" % row["to"])
			continue
		var world = scr.new()
		add_child_autofree(world)
		await get_tree().process_frame
		var bp := _back_portal(world)
		if bp.is_empty():
			skipped.append("%s: no BackPortal with a RectangleShape2D" % row["to"])
			continue
		if not ("spawn_points" in world) or not (world.spawn_points as Dictionary).has(row["key"]):
			skipped.append("%s: no spawn_points[%s]" % [row["to"], row["key"]])
			continue
		var arrival: Vector2 = world.spawn_points[row["key"]]
		var pos: Vector2 = bp["pos"]
		var box: Vector2 = bp["box"]
		boxes.append("%s %.0fx%.0f" % [row["to"], box.x, box.y])
		measured += 1
		var dx: float = absf(arrival.x - pos.x)
		var dy: float = absf(arrival.y - pos.y)
		if dx <= box.x * 0.5 and dy <= box.y * 0.5:
			inside.append("%s arriving at %s is INSIDE its BackPortal box (centre %s, %.0fx%.0f) — the return prompt is up as the world fades in and the first interact press leaves it" % [
				row["to"], str(arrival), str(pos), box.x, box.y])
	## ⛔ EVERY SKIP IS NAMED AND ASSERTED EMPTY. A silent `continue` here would let the arm report
	## "measured" while judging nothing — the hollow-arm shape @cowir-adhoc and @cowir-sfx each found
	## in a guard of their own today, where a coverage floor stayed green over a 55% skip.
	skipped.sort()
	assert_eq(skipped, [],
		"%d world(s) could not be measured, so this arm is silent about them: %s" % [skipped.size(), "; ".join(skipped)])
	assert_eq(measured, 4,
		"CONTROL: all 4 transitions must be measured, got %d — a derived denominator, not a round floor" % measured)
	boxes.sort()
	gut.p("  boxes read from the BUILT shapes: %s" % ", ".join(boxes))
	inside.sort()
	assert_eq(inside, [],
		"%d arrival(s) land on the way back: %s" % [inside.size(), "; ".join(inside)])


## ⛔ AND THE BOXES MUST NOT ALL BE THE SAME, or reading them off the node proves nothing. This is
## the control my hand measurement failed: with one constant for all four, W5->W6 reads as a defect.
func test_the_portals_do_not_all_share_one_box() -> void:
	var seen: Dictionary = {}
	var measured := 0
	for row in _transitions():
		var scr = load(DIR + str(row["to"]) + ".gd")
		if scr == null or not (scr is GDScript) or not scr.can_instantiate():
			continue
		var world = scr.new()
		add_child_autofree(world)
		await get_tree().process_frame
		var bp := _back_portal(world)
		if bp.is_empty():
			continue
		measured += 1
		seen["%.0fx%.0f" % [(bp["box"] as Vector2).x, (bp["box"] as Vector2).y]] = true
	assert_gt(measured, 3, "CONTROL: %d portals read; the walk did not run" % measured)
	assert_gt(seen.size(), 1,
		"every BackPortal reports the same box (%s), so reading it off the node is indistinguishable from using the constant — and the constant is what produced a false positive on W5->W6" % str(seen.keys()))
	gut.p("  %d distinct portal box sizes across %d worlds: %s" % [seen.size(), measured, str(seen.keys())])


## ⛔ THE DERIVATION, driven directly: the clearance comes from the box and the DIRECTION from which
## half of the map the trigger sits in, so no world carries a direction constant that could disagree
## with its own geometry.
func test_the_arrival_is_derived_from_the_box_it_must_clear() -> void:
	var box := Vector2(64.0, 192.0)
	var map_h := 4800.0
	## A trigger in the TOP half pushes the arrival south, away from the edge behind it.
	var top: Vector2 = InteractGeometry.arrival_clear_of(Vector2(2608.0, 163.4), box, map_h)
	assert_gt(top.y, 163.4, "a trigger in the map's top half must push the arrival SOUTH, into the map")
	assert_gte(absf(top.y - 163.4), box.y * 0.5,
		"the arrival must clear at least half the box (%.1f of %.1f)" % [absf(top.y - 163.4), box.y * 0.5])
	## And one in the BOTTOM half pushes north — the mirror, which a hardcoded direction fails.
	var bottom: Vector2 = InteractGeometry.arrival_clear_of(Vector2(2608.0, 3907.4), box, map_h)
	assert_lt(bottom.y, 3907.4, "a trigger in the map's bottom half must push the arrival NORTH, into the map")
	assert_eq(top.x, 2608.0, "the derivation is vertical only; x must not move")
	## ⛔ AND IT MUST SCALE WITH THE BOX, not with a constant. A 32 px box needs far less clearance
	## than a 192 px one, and that is exactly the difference my hand measurement flattened.
	var small: Vector2 = InteractGeometry.arrival_clear_of(Vector2(1232.0, 2128.0), Vector2(64.0, 32.0), 2240.0)
	assert_lt(absf(small.y - 2128.0), absf(bottom.y - 3907.4),
		"a smaller box must need less clearance (%.1f vs %.1f); if these are equal the box is not an input" % [
			absf(small.y - 2128.0), absf(bottom.y - 3907.4)])
	gut.p("  derived: 192px box clears %.1f, 32px box clears %.1f, direction follows the map half" % [
		absf(bottom.y - 3907.4), absf(small.y - 2128.0)])
