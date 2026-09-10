extends GutTest

## You arrive standing IN the exit zone, so the prompt is drawn under your own sprite.
##
## AreaTransition's indicator Label was a plain child of the trigger with no z_index, and the player
## is added after the transitions, so "Enter Village" rendered BEHIND the character in every interior
## in the game — measured on a rendered frame 2026-09-10, the sprite covered the middle of the word.
## Nothing errors; the prompt is there, you just cannot read all of it while standing where the
## prompt appears, which is the only place it appears.
##
## The prompt is an affordance, not scenery. It is pinned above sprites here rather than nudged out
## of the way, because moving it just relocates the collision — the player can approach a door from
## any side.

const DIRS := ["res://src/maps/interiors", "res://src/maps/villages"]
const NOT_MAPS := ["BaseInterior.gd", "BaseVillage.gd", "InteriorPlacementSweep.gd"]


func _scripts() -> Array:
	var out: Array = []
	for d in DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd") and not (f in NOT_MAPS):
				out.append(d + "/" + f)
	out.sort()
	return out


func _indicators(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c is Label and str(c.name) == "Indicator":
			acc.append(c)
		_indicators(c, acc)


func test_no_exit_prompt_renders_below_the_player() -> void:
	var buried: Array = []
	var scenes_built := 0
	var prompts_seen := 0

	for path in _scripts():
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var scene = load(path).new()
		vp.add_child(scene)
		await get_tree().physics_frame
		scenes_built += 1

		var player_z := 0
		var p = scene.get("player")
		if p != null and p is CanvasItem:
			player_z = (p as CanvasItem).z_index

		var found: Array = []
		_indicators(scene, found)
		for lbl in found:
			prompts_seen += 1
			# z_as_relative would make the value relative to the trigger's own layer, which is 0 here
			# but need not stay 0 -- an absolute index is what keeps this true if a map moves its doors.
			if lbl.z_index <= player_z or lbl.z_as_relative:
				buried.append("%s/%s" % [path.get_file().get_basename(), str(lbl.text)])
	buried.sort()

	assert_gt(scenes_built, 30, "CONTROL: only %d maps built" % scenes_built)
	assert_gt(prompts_seen, 20, "CONTROL: only %d exit prompts found across every interior and village -- the scan is broken and the zero below is free" % prompts_seen)
	assert_eq(buried, [],
		"an exit prompt draws under the player who is standing on it, which is the only place it shows: %s" % str(buried))
