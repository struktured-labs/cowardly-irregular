extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## 🐛 THE PRE-BOSS SAVE CRYSTAL IN TWO DRAGON CAVES COULD ONLY BE REACHED THROUGH THE UP-STAIRS.
## Ice and Shadow floor 4 — `total_floors - 1`, the rest stop before the boss — resolved their
## crystal to (528,432) while `StairsUp` sits at (560,432) with a 48x48 box. The cell one step east
## of the crystal IS the stair centre, and a stair fires on `body_entered` with no input from the
## player. So walking to the save point from that side sent you UP TO THE BOSS FLOOR instead of
## letting you save before the fight. Fire and Lightning were clean by layout luck, not by design.
##
## 🔑 CAUSE: `Signpost.floor_spot`'s `taken` set excludes each spawn's OWN cell and not the cells
## AROUND it. When the authored two-tiles-left mark is not plain floor — which DragonCave's own
## comment says happened on seven maze floors — the ring search lands the crystal in the cell beside
## the stairs and the stair becomes an approach cell. Same shape as every placement bug this week: a
## resolver that knows about walls and is blind to what else occupies the space.
##
## ⛔ A PRESS-CONTEST PROBE FINDS NOTHING HERE, which is why the village sweep missed it. Dungeon
## stairs are not press targets — `DragonCave:555-556` wires `body_entered`, so there is no
## nearest-wins arbitration to lose. The hazard is standing there at all.
##
## ⚠️ MY FIRST CLASSIFIER REPORTED 30 RISKS OF WHICH 28 WERE LABELS DOING THEIR JOB. Flagging any
## area with `body_entered` and no `interact()` caught every Signpost and ReadableProp, which show a
## label on proximity and are supposed to. Only areas that CHANGE THE WORLD on touch count: a stair,
## an `AreaTransition` with `require_interaction == false`, a BossTrigger.
##
## ⛔ AND THE CRYSTAL IS NOT THE ONLY PRESS TARGET THIS CAN HAPPEN TO. `DragonCave._place_treasure
## _chests` falls back to `_sign_position(_cell_of(stairs_up) + Vector2i(2, 1))` on any floor with no
## `T` marker — the SAME resolver with the SAME spawn-cells-only exclusion that put the crystal
## beside the stairs. A chest or a mimic there has the identical failure: you walk up to open it and
## the floor changes instead. So the last arm asks the question of EVERY press target, and the
## crystal arms above are the special case that found it.
##
## ✅ AND THE SECOND ARM EXISTS BECAUSE THE FIRST FIX BROKE IT. Avoiding the stairs alone left
## Shadow's pre-boss crystal with ONE standable approach cell — "move it until it stops colliding"
## is satisfiable by moving it where nobody can stand, the same half-fix that bit the W1 chests.

const SUBJECTS := [
	{"path": "res://src/maps/dungeons/IceDragonCave.gd", "floors": [1, 2, 3, 4]},
	{"path": "res://src/maps/dungeons/FireDragonCave.gd", "floors": [1, 2, 3, 4]},
	{"path": "res://src/maps/dungeons/LightningDragonCave.gd", "floors": [1, 2, 3, 4]},
	{"path": "res://src/maps/dungeons/ShadowDragonCave.gd", "floors": [1, 2, 3, 4]},
	{"path": "res://src/maps/dungeons/CastleHarmonia.gd", "floors": [1, 2, 3, 4]},
	{"path": "res://src/maps/dungeons/WhisperingCave.gd", "floors": [1, 2, 3, 4, 5]},
]

## Proximity feedback, not world changes — these may share space with a crystal.
const HARMLESS := ["Signpost", "ReadableProp", "TreasureChest"]

var _vp: SubViewport = null
var _step: float = 32.0


func _build(path: String, floor_n: int) -> Node2D:
	var scr = load(path)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		return null
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var d = scr.new()
	d.current_floor = floor_n
	_vp.add_child(d)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_step = float(d.TILE_SIZE) if "TILE_SIZE" in d else 32.0
	return d


func _teardown(d: Node2D) -> void:
	d.queue_free()
	await get_tree().process_frame
	_vp.queue_free()
	await get_tree().process_frame


func _fits(at: Vector2) -> bool:
	var sh := CircleShape2D.new()
	sh.radius = 8.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = sh
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


func _areas_at(point: Vector2) -> Array:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = point
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = InteractGeometry.LAYER_INTERACTABLE
	var out: Array = []
	for hit in _vp.world_2d.direct_space_state.intersect_point(q, 32):
		var c = hit.get("collider")
		if c != null and is_instance_valid(c) and c is Node2D:
			out.append(c)
	return out


func _base(n: Node) -> String:
	if n.get_script() == null:
		return "Area2D"
	return str(n.get_script().resource_path).get_file().get_basename()


## Does standing here fire something that moves the player?
func _teleporters_at(point: Vector2, crystal: Node) -> Array:
	var out: Array = []
	for a in _areas_at(point):
		if a == crystal:
			continue
		var b := _base(a)
		if b in HARMLESS:
			continue
		var nm := str(a.name)
		var auto_transition: bool = (b == "AreaTransition" and "require_interaction" in a
			and not bool(a.get("require_interaction")))
		if auto_transition or nm.begins_with("Stairs") or nm.begins_with("Exit") or b == "BossTrigger":
			out.append("%s '%s'" % [b, nm])
	return out


func _crystals(d: Node2D) -> Array:
	var out: Array = []
	var stack: Array = [d]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is SavePoint:
			out.append(n)
	return out


## Every standable cell touching the crystal, and what it would fire.
func _approaches(sp: Node2D) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var feet: Vector2 = (sp as Node2D).global_position + Vector2(dx * _step, dy * _step)
			if not _fits(feet):
				continue
			out.append({"cell": "(%d,%d)" % [dx, dy], "fires": _teleporters_at(feet, sp)})
	return out


func test_the_dungeons_build_and_carry_crystals() -> void:
	var found := 0
	var built := 0
	for s in SUBJECTS:
		for fl in (s["floors"] as Array):
			var d = await _build(str(s["path"]), int(fl))
			if d == null:
				continue
			built += 1
			found += _crystals(d).size()
			await _teardown(d)
	assert_gt(built, 20, "CONTROL: only %d dungeon floors built" % built)
	assert_gt(found, 8,
		"CONTROL: only %d save crystals found across %d floors; the arms below would clear vacuously" % [found, built])


## ⛔ THE ARM.
func test_no_crystal_is_approached_through_something_that_fires_on_touch() -> void:
	var bad: Array = []
	var cells := 0
	for s in SUBJECTS:
		for fl in (s["floors"] as Array):
			var d = await _build(str(s["path"]), int(fl))
			if d == null:
				continue
			var nm := str(s["path"]).get_file().get_basename()
			for sp in _crystals(d):
				for row in _approaches(sp as Node2D):
					cells += 1
					for fired in (row["fires"] as Array):
						bad.append("%s floor %d: standing %s at the save crystal is INSIDE %s, which fires on touch — the player is moved instead of reaching the crystal" % [
							nm, int(fl), str(row["cell"]), str(fired)])
			await _teardown(d)
	assert_gt(cells, 15, "CONTROL: only %d approach cells probed" % cells)
	bad.sort()
	for b in bad:
		gut.p("HAZARD %s" % str(b))
	assert_eq(bad, [], "a save crystal is reached through a teleporter: %s" % "; ".join(bad))
	gut.p("  %d approach cells, none inside a touch trigger" % cells)


## 🔑 THE OTHER HALF: a crystal nobody can stand beside is not fixed, it is hidden.
func test_every_crystal_keeps_at_least_two_approaches() -> void:
	var thin: Array = []
	for s in SUBJECTS:
		for fl in (s["floors"] as Array):
			var d = await _build(str(s["path"]), int(fl))
			if d == null:
				continue
			var nm := str(s["path"]).get_file().get_basename()
			for sp in _crystals(d):
				var n: int = _approaches(sp as Node2D).size()
				if n < 2:
					thin.append("%s floor %d: its crystal has %d standable approach cell(s) — one blocked prop from unusable" % [
						nm, int(fl), n])
			await _teardown(d)
	thin.sort()
	assert_eq(thin, [], "a save crystal was moved somewhere nearly unreachable: %s" % "; ".join(thin))


## 🔑 POSITIVE CONTROL, because a clean sweep of eleven crystals is worth nothing without one. Park
## a crystal ON the up-stairs and require the detector to name it.
func test_the_detector_can_see_a_crystal_on_a_stair() -> void:
	var d = await _build("res://src/maps/dungeons/IceDragonCave.gd", 4)
	assert_not_null(d, "CONTROL: the Ice cave floor 4 must build")
	if d == null:
		return
	var sp: Node2D = null
	for c in _crystals(d):
		sp = c
	assert_not_null(sp, "CONTROL: floor 4 carries the pre-boss crystal")
	if sp == null:
		await _teardown(d)
		return
	var stair: Node2D = null
	var stack: Array = [d]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node2D and str(n.name).begins_with("Stairs"):
			stair = n
	assert_not_null(stair, "CONTROL: a stair exists to collide with")
	if stair == null:
		await _teardown(d)
		return
	var clean_before := 0
	for row in _approaches(sp):
		clean_before += (row["fires"] as Array).size()
	assert_eq(clean_before, 0, "CONTROL: this crystal is clean before the plant")

	sp.global_position = (stair as Node2D).global_position - Vector2(_step, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var seen := 0
	for row in _approaches(sp):
		seen += (row["fires"] as Array).size()
	assert_gt(seen, 0,
		"a crystal one cell from the stairs must be reported — if it is not, the clean sweep means nothing")
	await _teardown(d)


## ⛔ THE WIDENING: anything that needs a PRESS, not just the save crystal. A press target whose
## approach cells are inside a touch trigger cannot be used — the trigger fires first, every time,
## because it needs no input. Found by asking why the crystal was special and finding it is not.
func test_no_press_target_is_approached_only_through_a_trigger() -> void:
	var bad: Array = []
	var targets := 0
	var gates := 0
	for s in SUBJECTS:
		for fl in (s["floors"] as Array):
			var d = await _build(str(s["path"]), int(fl))
			if d == null:
				continue
			var nm := str(s["path"]).get_file().get_basename()
			var stack: Array = [d]
			while not stack.is_empty():
				var n = stack.pop_back()
				for c in n.get_children():
					stack.append(c)
				if not (n is Node2D) or not n.has_method("interact"):
					continue
				## A touch trigger is not itself a press target; an AreaTransition that DOES want a
				## press is, and it is judged like any other.
				var b := _base(n)
				if b == "BossTrigger" or str(n.name).begins_with("Stairs") or str(n.name).begins_with("Exit"):
					continue
				targets += 1
				var rows: Array = _approaches(n as Node2D)
				if rows.is_empty():
					continue
				## \u26d4 A PRESS TARGET ON A **GATE** TILE IS A DOOR, AND ITS APPROACHES ARE WHAT IT
				## CONNECTS. `DungeonMechanics.LockTrigger` is placed on the layout's `G`/`Z` lock
				## character, which renders as wall until the puzzle opens it \u2014 Whispering Cave floor 4
				## has one at (6,10) with the DOWN stairs at (6,9) and the UP stairs at (6,11), so both
				## its approaches being staircases is the entire design. A strict rule with that one
				## named as an exception would be a suppression list; the TILE is structural and needs
				## nothing kept current.
				## \u2705 ASKED OF THE COLLIDER, NOT OF A CHARACTER SET. My first version tested the cell's
				## layout char against `Signpost.SIGN_GROUND` \u2014 which is `[".", "i"]`, the cells a SIGN
				## may take, not "is this floor". A chest sitting on its own `T` marker tile read as
				## non-floor, and 60 of 79 targets were exempted instead of 2. The real question is
				## whether a player can stand where the target is: a gate cannot be stood on.
				if not _fits((n as Node2D).global_position):
					gates += 1
					continue
				for row in rows:
					for f in (row["fires"] as Array):
						bad.append("%s floor %d: %s '%s' can be approached from %s, which is INSIDE %s and fires on touch \u2014 the player is moved instead of reaching it" % [
							nm, int(fl), b, str(n.name), str(row["cell"]), str(f)])
			await _teardown(d)
	assert_gt(targets, 20,
		"CONTROL: only %d press targets found across the dungeon floors; the arm would clear vacuously" % targets)
	bad.sort()
	for b in bad:
		gut.p("TOUCHED %s" % str(b))
	assert_eq(bad, [], "a press target is approached through a touch trigger: %s" % "; ".join(bad))
	assert_gt(gates, 0,
		"CONTROL: %d gate-tile targets excluded — if none is found the structural exemption is not being exercised and the rule is stricter than it reads" % gates)
	gut.p("  %d floor-standing press targets clean, %d gate-tile doors exempt by their own tile" % [targets - gates, gates])


## Every dungeon floor's build calls play_area_music, so this file writes SoundManager's area/world
## state without naming any of it.
func after_all() -> void:
	SoundState.restore()
