extends GutTest

## CrossCode phase 4, second half: caves were flat-lit — walking into a dragon cave at noon
## lit it like a meadow, because nothing underground had a rig at all.
##
## DungeonLighting reuses the village lamp machinery but pins the ambient per-dungeon. The
## defect this pins is the one a subclass invites: inheriting VillageLighting and forgetting
## to sever the clock, which looks correct all day and only breaks at dusk.
##
## Torch positions are DERIVED from spawn_points (the landmarks the layout already marks),
## never authored, so a re-authored cave map relights itself instead of stranding lamps
## where a staircase used to be. Asserted as that relationship, not as coordinates.

const DL := preload("res://src/exploration/DungeonLighting.gd")
const VL := preload("res://src/exploration/VillageLighting.gd")
const CAVES := {
	"Fire": "res://src/maps/dungeons/FireDragonCave.gd",
	"Ice": "res://src/maps/dungeons/IceDragonCave.gd",
	"Lightning": "res://src/maps/dungeons/LightningDragonCave.gd",
	"Shadow": "res://src/maps/dungeons/ShadowDragonCave.gd",
}


func _cave(path: String) -> Node:
	var scr = load(path)
	assert_not_null(scr, "%s must load" % path)
	var c: Node = scr.new()
	add_child_autofree(c)
	await get_tree().process_frame
	await get_tree().process_frame
	return c


func test_a_cave_ambient_ignores_the_day_clock() -> void:
	# The whole reason the subclass exists.
	var rig := DL.new()
	add_child_autofree(rig)
	rig.ambient = Color(0.3, 0.29, 0.42)
	var readings: Array = []
	for phase in [0.0, 0.25, 0.5, 0.75]:
		rig.phase_override = phase
		readings.append(rig.tint_now())
	for r in readings:
		assert_eq(r, rig.ambient, "cave tint moved with the clock — the sky got underground")

	# CONTROL: the village rig MUST vary across those same phases, or this test would pass
	# just as well against a rig that returns a constant for every reason.
	var village := VL.new()
	add_child_autofree(village)
	var seen: Dictionary = {}
	for phase in [0.0, 0.25, 0.5, 0.75]:
		village.phase_override = phase
		seen[village.tint_now()] = true
	assert_gt(seen.size(), 1, "CONTROL: VillageLighting must track the clock, else the comparison is empty")


func test_every_dragon_cave_builds_a_rig_and_tints_its_own_dark() -> void:
	var ambients: Dictionary = {}
	for name in CAVES:
		var c: Node = await _cave(CAVES[name])
		assert_not_null(c.lighting, "%s cave built no lighting rig" % name)
		assert_true(c.lighting is DungeonLighting, "%s must use the dungeon rig, not the village one" % name)
		ambients[c.lighting.ambient] = name
		assert_lt(c.lighting.ambient.get_luminance(), 0.5, "%s ambient is not dark — it is a cave" % name)
	assert_eq(ambients.size(), CAVES.size(),
		"each elemental cave needs its OWN dark; got %d distinct ambients for %d caves" % [ambients.size(), CAVES.size()])


func test_torches_are_derived_from_the_maps_landmarks() -> void:
	# Not "there are N lamps" — that would pin a coincidence. The invariant is that every
	# landmark the layout marked got a light, at that landmark's own position.
	var c: Node = await _cave(CAVES["Fire"])
	assert_gt(c.spawn_points.size(), 1, "CONTROL: the cave layout marked some landmarks")
	var lit: Dictionary = {}
	for l in c.lighting._lamps:
		if is_instance_valid(l):
			lit[l.position] = true
	var unlit: Array = []
	for key in c.spawn_points:
		if not lit.has(c.spawn_points[key]):
			unlit.append(str(key))
	assert_eq(unlit.size(), 0, "landmarks with no torch: %s" % str(unlit))


func test_lamps_hang_under_the_modulate_so_they_pierce_the_dark() -> void:
	# A PointLight2D parented outside the CanvasModulate gets multiplied into the ambient
	# instead of cutting through it — the cave would go dark WITH the torches still "on".
	var c: Node = await _cave(CAVES["Shadow"])
	assert_gt(c.lighting._lamps.size(), 0, "CONTROL: the shadow cave placed torches")
	for l in c.lighting._lamps:
		if is_instance_valid(l):
			assert_eq(l.get_parent(), c.lighting, "a torch escaped the modulate and will be swallowed by it")


func test_relighting_a_floor_does_not_accumulate_torches() -> void:
	# _place_torches runs per floor. Without the clear, floor 3 of a 3-floor cave carries
	# every torch from floors 1 and 2, at coordinates that mean nothing on this map.
	var c: Node = await _cave(CAVES["Ice"])
	var first: int = c.lighting._lamps.size()
	assert_gt(first, 0, "CONTROL: the first floor lit something")
	c._place_torches()
	c._place_torches()
	assert_eq(c.lighting._lamps.size(), first, "torches accumulated across relights")
