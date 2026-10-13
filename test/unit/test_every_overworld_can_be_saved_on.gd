extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## 🐛 W1 WAS THE ONLY WORLD OF SIX WITH NO OVERWORLD SAVE POINT. Every other world places one at a
## crossroads or plaza — SuburbanOverworld:230, SteampunkOverworld:223, IndustrialOverworld:221,
## FuturisticOverworld:226, AbstractOverworld:250 — and `OverworldScene.gd` held zero references to
## SavePoint. So the first world every player crosses, on the largest map in the game (200x140
## against the others' smaller grids), was the one where you could not save between a village and a
## dragon cave. Villages and dungeons have their own crystals; the ROAD had none.
##
## ⛔ THE GUARD DERIVES THE WORLD SET AND ASSERTS A RELATIONSHIP, NOT A COORDINATE. Naming W1 would
## pass the moment W1 was fixed and say nothing about a seventh world; pinning the cell would be the
## coincidental value this repo warns about, red on a correct relocation and green on a bad one. So:
## EVERY overworld scene places exactly one save point, it is standable, it is approachable from
## every neighbouring cell, and it does not contest any other interactable's press.
##
## ⚠️ THE "DOES NOT CONTEST" ARM IS THE ONE THAT EARNS ITS PLACE, and it is why the W1 cell came out
## of a physics sweep rather than off the painted map. A SavePoint grabs at SAVE_RADIUS (48 px,
## Y-stretched under Mode 7), so a crystal parked beside a door or a chest takes the faced press
## under nearest-wins arbitration and a player who meant to enter the cave saves instead — exactly
## the defect `test_a_chest_in_the_doorway_answers_instead_of_the_door` exists for, one class over.

## Each world's overworld scene. Derived names would be guesswork — these five are the shipped set,
## and the arm below reds if a sixth script appears without a row here.
const WORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
	"abstract": "res://src/exploration/AbstractOverworld.gd",
}

const DIR := "res://src/exploration/"

var _vp: SubViewport = null


func _build(path: String) -> Node2D:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null:
		gs.set_story_flag("world1_mordaine_defeated", true)
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var scr = load(path)
	assert_true(scr is GDScript and scr.can_instantiate(), "CONTROL: %s must instantiate" % path)
	if not (scr is GDScript) or not scr.can_instantiate():
		return null
	var w = scr.new()
	_vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return w


func _fits(at: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


func _collect(w: Node2D) -> Dictionary:
	var saves: Array = []
	var others: Array = []
	var stack: Array = [w]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node2D):
			continue
		if n is SavePoint:
			saves.append(n)
		elif n.has_method("interact") or n.is_in_group("interactables"):
			others.append(n)
	return {"saves": saves, "others": others}


## ⛔ THE CORPUS ARM. A `*Overworld.gd` that appears without a row above would otherwise be judged by
## nothing, and this guard's whole claim is "every world" — so the set has to be derived from disk
## and compared, not trusted.
func test_the_world_set_is_the_whole_world_set() -> void:
	var d := DirAccess.open(DIR)
	assert_not_null(d, "CONTROL: the exploration directory must be readable")
	if d == null:
		return
	var on_disk: Array = []
	for f in d.get_files():
		if f.ends_with("Overworld.gd") or f == "OverworldScene.gd":
			on_disk.append(DIR + f)
	on_disk.sort()
	var listed: Array = WORLDS.values().duplicate()
	listed.sort()
	assert_gt(on_disk.size(), 5, "CONTROL: found %d overworld scripts" % on_disk.size())
	assert_eq(on_disk, listed,
		"an overworld scene is not judged by this guard — add it to WORLDS or this file's 'every world' claim is false")


func test_every_overworld_places_exactly_one_save_point() -> void:
	var missing: Array = []
	for world in WORLDS.keys():
		var w = await _build(str(WORLDS[world]))
		if w == null:
			continue
		var found: Array = (_collect(w)["saves"] as Array)
		if found.size() != 1:
			missing.append("%s: %d save points — a player crossing this world cannot save on the road" % [
				world, found.size()])
		w.queue_free()
		await get_tree().process_frame
		_vp.queue_free()
		await get_tree().process_frame
	missing.sort()
	assert_eq(missing, [], "an overworld has no save crystal: %s" % ", ".join(missing))


func test_every_save_point_is_standable_and_approachable() -> void:
	var bad: Array = []
	var checked := 0
	for world in WORLDS.keys():
		var w = await _build(str(WORLDS[world]))
		if w == null:
			continue
		var step := float(int(w.MAP_SCALE) * int(w.TILE_SIZE))
		for sp in (_collect(w)["saves"] as Array):
			checked += 1
			var at: Vector2 = (sp as Node2D).global_position
			var reach := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					if _fits(at + Vector2(dx * step, dy * step)):
						reach += 1
			## Sealed, or reachable from one cell only, is a crystal the player cannot use — the
			## other half of the chest lesson: moving something until it stops robbing a door is
			## satisfiable by moving it somewhere useless.
			if reach < 3:
				bad.append("%s: its save crystal has %d standable neighbours — unusable" % [world, reach])
		w.queue_free()
		await get_tree().process_frame
		_vp.queue_free()
		await get_tree().process_frame
	assert_gt(checked, 5, "CONTROL: only %d crystals examined" % checked)
	bad.sort()
	assert_eq(bad, [], "a save crystal cannot be reached: %s" % ", ".join(bad))


## ✅ ALL SIX WORLDS NOW. This arm shipped covering four, because when it was written two worlds
## FAILED it on pre-existing placements and the remedy was not mine to choose:
##
##     industrial  standing (1,1) at an NPC and facing it SAVED instead of talking   (113 px apart)
##     steampunk   standing (-1,-1) at the crystal and facing it TALKED instead      (plaza NPC)
##
## cowir-main's route: move the CRYSTAL, never the authored NPC and never the pinned
## NPC_TALK_RADIUS_MODE7. Both cells came from the same sweep W1's did — fits a body, all eight
## neighbours standable, >= 220 px from every other interactable — and then every surviving candidate
## was PRESS-TESTED in both directions, which is the only acceptance criterion. Steampunk cleared one
## cell south (smallest of 55 candidates, stays in the plaza); industrial needed four (smallest of
## 64; one cell FLIPPED the clash direction instead of clearing it, which is why the probe decides
## and not the distance). So the scope constant is gone and the claim is the whole set again.
##
## ⚠️ AND IT SIMULATES THE PRESS RATHER THAN MEASURING A DISTANCE. My first version used a floor of SAVE_RADIUS + PROBE_REACH and flagged
## W4's crystal at 113 px from an NPC, and the proxy turned out to be RIGHT — which is luck, not
## method: the press probe confirmed harm at one of that NPC's eight approach cells. That floor is a
## PROXY: whether two interactables actually
## contest depends on a standable cell, a facing, and nearest-by-anchor arbitration, not on centre
## distance. A proxy that reds on a harmless pair is a guard somebody deletes, and one that passes a
## harmful pair is worse — so this reproduces OverworldController's probe, the way
## `test_a_chest_in_the_doorway_answers_instead_of_the_door` does for doors.
func _press_lands_on(feet: Vector2, facing: Vector2) -> Node:
	var space := _vp.world_2d.direct_space_state
	for point in [feet + facing * InteractGeometry.PROBE_REACH_MODE7, feet]:
		var q := PhysicsPointQueryParameters2D.new()
		q.position = point
		q.collide_with_areas = true
		q.collide_with_bodies = false
		q.collision_mask = InteractGeometry.LAYER_INTERACTABLE
		var best: Node = null
		var best_d := INF
		for hit in space.intersect_point(q):
			var c = hit.get("collider")
			if c == null or not is_instance_valid(c) or not (c is Node2D):
				continue
			if not (c is SavePoint or c.has_method("interact") or c.is_in_group("interactables")):
				continue
			var d: float = InteractGeometry.anchor(c).distance_squared_to(feet)
			if d < best_d:
				best_d = d
				best = c
		if best != null:
			return best
	return null


## Who wins each standable cell touching `n` when the player stands there and faces `n`.
func _winners(n: Node2D, step: float) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var feet: Vector2 = n.global_position + Vector2(dx * step, dy * step)
			if not _fits(feet):
				continue
			var facing := Vector2(-dx, 0) if absi(dx) >= absi(dy) else Vector2(0, -dy)
			out.append({"cell": "(%d,%d)" % [dx, dy], "won": _press_lands_on(feet, facing)})
	return out


func _base_of(n: Node) -> String:
	if n.get_script() == null:
		return "?"
	return str(n.get_script().resource_path).get_file().get_basename()


func test_no_save_crystal_steals_or_loses_a_faced_press() -> void:
	var robbed: Array = []
	var checked := 0
	var cells := 0
	for world in WORLDS.keys():
		var w = await _build(str(WORLDS[world]))
		if w == null:
			continue
		var step := float(int(w.MAP_SCALE) * int(w.TILE_SIZE))
		var got: Dictionary = _collect(w)
		for sp in (got["saves"] as Array):
			checked += 1
			## Direction 1: the crystal must answer its own faced presses.
			for row in _winners(sp as Node2D, step):
				cells += 1
				var won = row["won"]
				if won == null or won == sp:
					continue
				robbed.append("%s: standing %s at the save crystal and facing it opens %s instead — the player cannot save there" % [
					world, str(row["cell"]), _base_of(won)])
			## Direction 2: and it must not answer anybody else's. Only neighbours close enough to
			## be plausible contenders are walked, so this stays a press test on the pairs that can
			## actually collide rather than a sweep of every interactable in the world.
			var at: Vector2 = (sp as Node2D).global_position
			for o in (got["others"] as Array):
				if (o as Node2D).global_position.distance_to(at) > 4.0 * step:
					continue
				for row in _winners(o as Node2D, step):
					cells += 1
					if row["won"] == sp:
						robbed.append("%s: standing %s at %s/%s and facing it SAVES instead — the crystal took its press" % [
							world, str(row["cell"]), _base_of(o), str((o as Node2D).name)])
		w.queue_free()
		await get_tree().process_frame
		_vp.queue_free()
		await get_tree().process_frame
	assert_eq(checked, WORLDS.size(),
		"CONTROL: %d crystals press-checked for %d worlds" % [checked, WORLDS.size()])
	assert_gt(cells, 20, "CONTROL: only %d approach cells probed; the arm would clear vacuously" % cells)
	robbed.sort()
	for r in robbed:
		gut.p("CLASH %s" % str(r))
	assert_eq(robbed, [], "a faced press goes to the wrong thing: %s" % ", ".join(robbed))
	gut.p("  %d crystals, %d approach cells probed, no contested press" % [checked, cells])


## Every world's scene calls play_area_music in _ready, so building six of them writes
## SoundManager's area/world/playing state without naming any of it.
func after_all() -> void:
	SoundState.restore()
