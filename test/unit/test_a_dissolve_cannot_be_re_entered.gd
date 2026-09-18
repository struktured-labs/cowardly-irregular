extends GutTest

## The six `_on_transition_triggered` copies hold `world_transition` across a 1.2s await and emit
## `area_transition` below it, with NO re-entrancy guard — 0 of 6. `AreaTransition._triggered` is
## per-instance, so it cannot see a second instance firing, and `InputLockManager._locks` is a
## DICTIONARY keyed by name: push twice and the FIRST pop releases, leaving the player free to move
## while the second dissolve still runs. `_trigger_transition`'s own comment states the other half —
## "GameLoop's loader is not idempotent under that condition (it could chain into two scene loads)".
##
## ⛔ SO WHY NO LATCH: THE SHAPE IS UNREACHABLE, AND NOT BECAUSE THE HANDLER HANDLES IT. Measured
## 2026-09-18 — two independent facts, in two different files, neither of them in the handler:
##   21 AreaTransition constructions across the six mode7 scenes, ALL require_interaction = true
##      -> the auto `body_entered` path cannot reach the dissolve branch at all
##   OverworldController._on_interaction_requested picks _pick_nearest_interactable and RETURNS
##      -> one press dispatches exactly one interactable, even with overlapping AABBs (the
##         2026-07-13 fix, made for Castle Harmonia sitting 2 tiles from CaveEntrance)
##
## 🔑 THAT IS "COVERED BY A DIFFERENT MECHANISM", NOT "THE CODE HANDLES THE CASE" — the two survive
## an edit only if something reds when they change. A latch here would be dead code; these arms are
## the deliverable instead. If either goes false, restore the guard rather than deleting an arm.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## The scenes whose `_on_transition_triggered` awaits a dissolve while holding the lock.
const MODE7_SCENES := [
	"res://src/exploration/OverworldScene.gd",
	"res://src/exploration/AbstractOverworld.gd",
	"res://src/exploration/SteampunkOverworld.gd",
	"res://src/exploration/FuturisticOverworld.gd",
	"res://src/exploration/SuburbanOverworld.gd",
	"res://src/exploration/IndustrialOverworld.gd",
]
const CONTROLLER := "res://src/exploration/OverworldController.gd"


func _code(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 0, "could not read %s" % path)
	return str(GdSource.split(raw)["code"])


## One function's lines, from the code half. Boundary detection on the RAW source would let a
## `"""` region's column-0 `func` line open a phantom function (cowir-controller's plant).
func _body(code: String, fn: String) -> String:
	var out: Array = []
	var inside := false
	for line in code.split("\n"):
		if line.begins_with("func ") or line.begins_with("static func "):
			inside = line.begins_with("func " + fn + "(")
		if inside:
			out.append(line)
	return "\n".join(out)


func test_every_overworld_portal_still_needs_a_button_press() -> void:
	## The auto path is the only one that can fire two transitions in one frame: the player is
	## input-locked the moment the first dissolve starts, so they cannot WALK into a second zone —
	## but two `body_entered` signals in a single physics frame are dispatched back to back, and
	## the first handler returns at its `await` before the second arrives.
	var total := 0
	for path in MODE7_SCENES:
		var code := _code(path)
		var ctors: Array = []
		var auto: Array = []
		var lines := code.split("\n")
		for i in lines.size():
			var t: String = str(lines[i]).strip_edges()
			if not t.contains("AreaTransitionScript.new()"):
				continue
			if not t.begins_with("var "):
				continue
			var name_part: String = t.substr(4).split("=")[0].strip_edges()
			ctors.append(name_part)
			if not code.contains(name_part + ".require_interaction = true"):
				auto.append(name_part)
		assert_gt(ctors.size(), 0,
			"CONTROL: no AreaTransition construction found in %s — the derivation stopped matching, so this arm is asserting over nothing" % path)
		assert_eq(auto, [],
			"%s builds a transition that auto-triggers on body_entered: %s — two overlapping auto zones fire in ONE frame, and _on_transition_triggered has no re-entrancy guard, so the second push_lock is a no-op and the FIRST pop unlocks the player mid-dissolve. Add the guard, or keep the press." % [path, str(auto)])
		total += ctors.size()
	assert_gt(total, 15,
		"CONTROL: only %d constructions found across six scenes — the corpus shrank and a green here would be about the wrong tree" % total)


func test_one_press_still_dispatches_exactly_one_interactable() -> void:
	## The other half, and it lives in a file none of the six handlers mention. First-hit-wins was
	## replaced by nearest-wins on 2026-07-13 because overworld portals have overlapping AABBs; if
	## it ever dispatches to every hit instead, one press emits two transitions.
	var body := _body(_code(CONTROLLER), "_on_interaction_requested")
	assert_gt(body.length(), 0,
		"CONTROL: _on_interaction_requested not found in OverworldController.gd — renamed or moved, and this arm proves nothing")

	var calls := 0
	var unreturned: Array = []
	var lines := body.split("\n")
	for i in lines.size():
		var t: String = str(lines[i]).strip_edges()
		if not t.ends_with(".interact(player)"):
			continue
		calls += 1
		var nxt: String = str(lines[i + 1]).strip_edges() if i + 1 < lines.size() else ""
		if nxt != "return":
			unreturned.append(t)
	assert_gt(calls, 0,
		"CONTROL: no `.interact(player)` call found — the dispatch changed shape and this arm stopped measuring it")
	assert_eq(unreturned, [],
		"a dispatch in _on_interaction_requested is not followed by `return`: %s — one press would reach every overlapping interactable, and two overworld portals then emit two transitions into a handler with no re-entrancy guard" % str(unreturned))
	## 📌 NOT A DUPLICATE OF `test_overworld_reachability_framework`, WHICH RATCHETS THE SAME SYMBOL:
	## that one pins the DEFINITION (it exists, and its body does distance math); this pins that the
	## DISPATCHER still uses it, which is the half my re-entrancy argument rests on. Its two pins read
	## raw source and false-greened on a comment — measured and fixed separately.
	assert_true(body.contains("_pick_nearest_interactable"),
		"nearest-wins selection is gone from _on_interaction_requested — first-hit-wins was the 2026-07-13 defect (Castle Harmonia stole CaveEntrance's press), and it is also what keeps one press to one transition")


func test_the_lock_is_a_set_so_a_second_push_is_not_counted() -> void:
	## The reason a re-entrancy guard would be needed at all, pinned so the premise above cannot
	## quietly become false. If `_locks` ever becomes a counter, a double push/pop is harmless and
	## the two arms above are defending less than they claim.
	var code := _code("res://src/input/InputLockManager.gd")
	assert_true(code.contains("_locks[lock_id] = Time.get_ticks_msec()"),
		"push_lock no longer stamps the dict by name — if it counts instead, re-entry is no longer a release-early hazard and the reasoning in this file's header needs rewriting, not deleting")
	assert_false(code.contains("_locks[lock_id] += 1"),
		"push_lock looks like a counter now; re-check whether the two arms above are still the thing keeping the dissolve safe")
