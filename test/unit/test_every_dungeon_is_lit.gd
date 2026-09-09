extends GutTest

## Every dungeon carries the lighting rig, including the one that does not inherit it.
##
## FOUND 2026-09-09. Twelve of thirteen dungeons extend DragonCave and get its rig for free:
## a DungeonLighting CanvasModulate holding a cave ambient, plus a torch at every landmark.
## WhisperingCave extends Node2D directly, so it inherited none of it and built neither -- and
## it is the FIRST cave in the game, where the Rat King is. The tutorial dungeon was the one
## flat-lit room in a game where every later cave has atmosphere. Nothing errored; a scene with
## no CanvasModulate simply renders at full brightness, which looks like a decision.
##
## WHY THE AMBIENT IS CHECKED AND NOT JUST THE NODE. DungeonLighting._ready() sets color to
## WHITE and _process() replaces it with the real ambient. A probe that awaits only PHYSICS
## frames therefore reads white on every dungeon and reports the whole feature inert -- which
## is exactly what my first measurement of this said before I noticed it needed a PROCESS
## frame. Asserting the applied colour, after a process frame, is what makes this a test of the
## lighting rather than of its constructor.

const DUNGEON_DIR := "res://src/maps/dungeons"
const NOT_DUNGEONS := ["BossTrigger.gd", "DragonCave.gd"]


func _dungeon_scripts() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd") and not (f in NOT_DUNGEONS):
			out.append(f)
		f = dir.get_next()
	out.sort()
	return out


func test_every_dungeon_lights_itself() -> void:
	var scripts := _dungeon_scripts()
	assert_gt(scripts.size(), 8, "only %d dungeon scripts found -- the scan is looking in the wrong place" % scripts.size())

	var unlit: Array = []
	var torchless: Array = []
	var built := 0

	for name in scripts:
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		add_child_autofree(vp)
		var d = load("%s/%s" % [DUNGEON_DIR, name]).new()
		vp.add_child(d)
		await get_tree().physics_frame
		# _process applies the ambient; without this the colour is still _ready()'s white
		await get_tree().process_frame
		await get_tree().process_frame
		built += 1

		var lighting = d.get_node_or_null("Lighting")
		if lighting == null or not (lighting is CanvasModulate):
			unlit.append(name)
			continue
		# A cave must actually be darker than the room it is drawn in.
		var c: Color = (lighting as CanvasModulate).color
		if c.r >= 0.95 and c.g >= 0.95 and c.b >= 0.95:
			unlit.append("%s (ambient still white -- the rig exists but never dimmed)" % name)
		var lamps := 0
		for ch in lighting.get_children():
			if ch is PointLight2D:
				lamps += 1
		if lamps == 0:
			torchless.append(name)

	assert_eq(built, scripts.size(), "built %d of %d dungeons" % [built, scripts.size()])
	assert_eq(unlit, [], "a dungeon with no ambient renders at full brightness, which reads as a design choice rather than a bug: %s" % str(unlit))
	assert_eq(torchless, [], "a dungeon with an ambient and no torches is uniformly dark with nothing to walk toward: %s" % str(torchless))
