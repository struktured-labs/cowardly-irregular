extends GutTest

## No overworld entrance may swallow another's interact cells.
##
## THIS DEFECT HAS NOW HAPPENED TWICE, and the second time is the interesting one. On
## 2026-07-13 Castle Harmonia sat 2 tiles east of the Whispering Cave, their 4x10 boxes
## overlapped, and the earlier sibling took every ui_accept in the shared cells -- a player
## walking to the castle got warped into the cave. The fix shrank the box to 2x6 and the
## comment recording it is still in _add_area_transition.
##
## It came back on 2026-09-09, in W1, because `InteractGeometry.is_mode7()` had been returning
## false in every world for ten weeks and started working. The 2x6 Mode-7 box had therefore
## NEVER been applied to a live scene. It assumes landmarks sit 6+ tiles apart; the Lightning
## Dragon Cave and Sandrift's entrance are authored 4 apart on one column, so their boxes
## overlapped by 2 tiles and the cave -- sibling index 4 against the village's 10 -- took them.
## Walking south from the dragon cave toward the village handed you the dragon cave again.
##
## The lesson is not "check for overlaps after moving a landmark". It is that a fix which
## restores a dead code path also switches on every decision downstream of it, and those
## decisions have never been observed. "The proven W1 recipe" described a value that had not
## run once.
##
## WHAT IS ASSERTED, after a wrong turn worth recording: my first fix TRIMMED the overlapping
## box so the zones no longer touched. That satisfied "no overlap" and broke the thing the zone
## exists for -- Sandrift shrank to 2x2 and a 2-tall box cannot reach a landmark 3 tiles below
## it. I had asserted a PROPERTY (>= one tile of reach) instead of the OUTCOME (a player can
## enter), which is the same substitution this file was written to document. Overlaps are now
## resolved by AreaTransition choosing the NEAREST destination, and what is pinned here is that
## no zone is ever silently shortened.

const MODE7_WORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
}


func _boxes(world) -> Array:
	var out: Array = []
	if world.transitions == null:
		return out
	for t in world.transitions.get_children():
		if not (t is Area2D):
			continue
		for c in t.get_children():
			if c is CollisionShape2D and c.shape is RectangleShape2D:
				out.append({
					"name": str(t.name),
					"pos": t.position + c.position,
					"half": (c.shape as RectangleShape2D).size / 2.0,
				})
	return out


func test_no_entrance_swallows_another() -> void:
	var problems: Array = []
	var worlds_built := 0
	var boxes_seen := 0

	for label in MODE7_WORLDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(128, 128)
		add_child_autofree(vp)
		var w = load(MODE7_WORLDS[label]).new()
		vp.add_child(w)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var boxes := _boxes(w)
		if boxes.is_empty():
			continue
		worlds_built += 1
		boxes_seen += boxes.size()



		# OVERLAPS ARE NO LONGER THE DEFECT -- AreaTransition arbitrates them by distance. What
		# must not happen is a zone being SHRUNK to dodge one: the zone sits 3 tiles above its
		# landmark to compensate for Mode 7, so a box under 6 tiles tall stops covering its own
		# doorway. That was shipped in .254 (Sandrift trimmed to 2x2) and reverted here.
		for b in boxes:
			if b["half"].y * 2.0 < float(w.TILE_SIZE) * 6.0:
				problems.append("%s: %s has a %s-tile box -- a zone shorter than 6 tiles no longer reaches the landmark it belongs to"
					% [label, b["name"], str(b["half"].y * 2.0 / float(w.TILE_SIZE))])

	assert_eq(worlds_built, MODE7_WORLDS.size(),
		"built %d of %d Mode 7 worlds" % [worlds_built, MODE7_WORLDS.size()])
	assert_gt(boxes_seen, 15,
		"only %d transition boxes measured across five worlds (24 at time of writing) -- the probe is not seeing them and any zero below is free" % boxes_seen)
	assert_eq(problems, [], "\n  ".join(problems))
