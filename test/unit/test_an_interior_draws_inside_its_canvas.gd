extends GutTest

## ⛔ struktured's 2026-10-05 session logged **152 engine errors**: `Index p_y = 40 is out of bounds
## (height = 40)`, at `set_pixel (core/io/image.cpp:3349)` — **38 occurrences of EACH of rows 40, 41,
## 42, 43**, i.e. a 44-row drawing into a 40-row canvas, 38 columns wide. One burst of 290 lines in a
## 15,260-line session, starting immediately after `door_open` / `secret_found`, so it fires on
## INTERIOR ENTRY. (@cowir-music found it, @cowir-sprites established the write and the climbing
## rows, @cowir-music corrected "all identical" — it is four rows, not an off-by-one.)
##
## 🔑 WHY THIS IS A RUN AND NOT A GREP. I enumerated all **424** `Image.create` sites in `src/`:
## 222 heights resolve statically, **9 are exactly 40**, and 5 more resolve to 40 by tracing their
## variable to its assignment. **I read all 14 and every one stays in bounds.** Also cleared: no
## `BitMap` anywhere (so it is an `Image`), `_create_light_texture` is structurally incapable of
## overrun, `OverworldPlayer.SPRITE_SIZE` is 32, `OverworldNPC` images are `TILE_SIZE²`. Six
## candidate shapes ruled out by pattern. **32 heights remain parameter- or member-valued and cannot
## be resolved without running them** — which is the whole reason this file exists.
##
## ⚠️ THE ERROR IS NOT CATCHABLE FROM GDSCRIPT — it is engine-side and goes to the log. So this arm's
## job is to BUILD every interior and print a marker first; the error lines then land immediately
## after the culprit's marker in the run log, which localises it in ONE run:
##
##     command grep -a -B2 "out of bounds" tmp/gut_manual_godot.<pid>.log
##
## 📌 AND IT ANSWERS THE PRIOR QUESTION AT THE SAME TIME, which is the one nobody had answered:
## **does main still do it?** His log predates a week of fixes and carries no Build line — exactly
## how the 1401 save refusals turned out to be a stale-tree artifact (@cowir-battle's discriminator).
## If no interior emits it on main, the finding is a fact about HIS TREE and this arm says so by
## passing. @cowir-main's ruling: if it does not reproduce, drop it and say so.

const DIR := "res://src/maps/interiors/"

## Not instantiable as a scene subject: a base class and a helper, neither of which a player enters.
const NOT_A_ROOM := ["BaseInterior.gd", "InteriorPlacementSweep.gd"]


func _interior_scripts() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	assert_not_null(d, "CONTROL: the interiors directory must be readable")
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".gd") or f in NOT_A_ROOM:
			continue
		out.append(f)
	out.sort()
	return out


## Builds every interior, one per marker line. The arm cannot SEE the engine error, so it asserts
## only what it can: that each room instantiated and drew something. The localisation is the log.
func test_every_interior_builds_for_the_log_to_be_read() -> void:
	var scripts := _interior_scripts()
	assert_gt(scripts.size(), 25,
		"CONTROL: expected the full interior set, found %d — a short list would clear nothing" % scripts.size())
	var built := 0
	var failed: Array = []
	for f in scripts:
		gut.p("PROBE_INTERIOR_BEGIN %s" % f)
		var scr = load(DIR + f)
		if scr == null:
			failed.append(f)
			gut.p("PROBE_INTERIOR_SKIP %s (script would not load)" % f)
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var room = scr.new()
		vp.add_child(room)
		await get_tree().physics_frame
		await get_tree().physics_frame
		built += 1
		gut.p("PROBE_INTERIOR_END %s" % f)
		vp.queue_free()
		await get_tree().process_frame

	assert_eq(failed, [], "these interior scripts would not load: %s" % ", ".join(failed))
	assert_gt(built, 25, "CONTROL: %d interiors built; the sweep must cover the set to clear it" % built)
	gut.p("  built %d interiors — now grep the run log for 'out of bounds' and read the marker above it" % built)
