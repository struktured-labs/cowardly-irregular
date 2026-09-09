extends GutTest

## `InteractGeometry.is_mode7()` RETURNED FALSE IN EVERY WORLD, EVERY FRAME.
##
## It read `SceneTree.root.get_node_or_null("Mode7Overlay")` — a DIRECT CHILD OF ROOT.
## The CanvasLayer of that name is created in Mode7Overlay.setup(scene, player) and
## parented to `scene`, the overworld itself, so the live path is
## root/GameLoop/<Overworld>/Mode7Overlay. The lookup found nothing and `return false`
## reads as "not in Mode 7" — indistinguishable from a flat world. Nothing errored.
##
## Six production consumers took their FLAT branch under Mode-7 scaled sprites:
## OverworldNPC (x2), WanderingNPC, Signpost, SavePoint.
##
## 🔑 THIS WAS THE SECOND TIME. The 2026-07-18 audit killed an ancestor-walk detector for
## being dead code — its note says "Mode 7 NPCs kept a 40px zone under a 96px sprite" —
## and `is_mode7()` was its replacement. The replacement had the same defect.
##
## AND THE GUARD THAT SHOULD HAVE CAUGHT IT WAS A SOURCE PIN.
## test_overworld_npc_collision_layer_regression asserts that the STRING
## "InteractGeometry.is_mode7()" appears in the NPC function body, and that it appears
## after `collision_layer = 4`. Both were true the whole time. A pin on the CALL SITE
## cannot see that the callee returns a constant — it verifies the wiring exists and
## says nothing about what flows through it. That test is not wrong and should stay; it
## pins ordering, which is a real thing it can see. This file pins the VALUE, which is
## the thing it cannot.
##
## These arms drive the real static through its real setter and assert the real reader
## agrees. No source text, no node paths — a detector that resolves through a tree can be
## rewired without touching a string this file reads.

const FLAT := false
const MODE7 := true


func before_each() -> void:
	Mode7Overlay.is_active = FLAT


func after_each() -> void:
	## Leaking a true here would rotate village movement — BaseVillage:82 clears it for
	## exactly that reason, and OverworldPlayer reads camera_angle unconditionally.
	Mode7Overlay.is_active = FLAT


## The load-bearing arm. Pre-fix this read FALSE with is_active true, in every world.
func test_is_mode7_is_true_when_the_overlay_is_active() -> void:
	Mode7Overlay.is_active = MODE7
	assert_true(InteractGeometry.is_mode7(),
		"Mode7Overlay.is_active is true and is_mode7() still reports flat — the signal six consumers branch on is dead, and every one of them is using flat geometry under Mode-7 sprites")


## The other half: a detector hardwired to `true` would pass the arm above and be just as
## broken. Both directions or neither.
func test_is_mode7_is_false_when_the_overlay_is_not_active() -> void:
	Mode7Overlay.is_active = FLAT
	assert_false(InteractGeometry.is_mode7(),
		"is_mode7() reports Mode 7 while the overlay is inactive — flat worlds would take Mode-7 geometry")


## The reader must TRACK the flag, not merely agree with it once. A constant passes either
## single-direction arm depending on which constant it is; only a transition catches it.
func test_is_mode7_tracks_the_flag_across_transitions() -> void:
	var seen: Array[bool] = []
	for want in [MODE7, FLAT, MODE7]:
		Mode7Overlay.is_active = want
		seen.append(InteractGeometry.is_mode7())
	assert_eq(seen, [true, false, true] as Array[bool],
		"is_mode7() did not follow is_active through active->flat->active; read %s" % str(seen))


## PREMISE / population canary. Every arm above sets one static and reads one function; if
## the static were not settable, or the class not resolvable from a test context, all three
## would compare false to false and pass having exercised nothing.
func test_premise_the_static_is_real_and_settable() -> void:
	Mode7Overlay.is_active = MODE7
	assert_true(Mode7Overlay.is_active,
		"PREMISE BROKEN: Mode7Overlay.is_active did not hold the value just written to it — the arms above are asserting against a field they cannot move")
	Mode7Overlay.is_active = FLAT
	assert_false(Mode7Overlay.is_active,
		"PREMISE BROKEN: Mode7Overlay.is_active did not clear")


## Consumers must not have kept a private copy of the dead lookup. A second detector that
## walks the tree would be dead in exactly the way this fix removes, and would go on being
## dead while the arms above pass.
func test_no_consumer_still_looks_the_overlay_up_by_node_path() -> void:
	var offenders: Array[String] = []
	var checked: int = 0
	for path in [
		"res://src/exploration/InteractGeometry.gd",
		"res://src/exploration/OverworldNPC.gd",
		"res://src/exploration/WanderingNPC.gd",
		"res://src/exploration/Signpost.gd",
		"res://src/exploration/SavePoint.gd",
	]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_ne(text, "", "could not read %s — this arm would pass vacuously" % path)
		if text == "":
			continue
		checked += 1
		# LINE-BASED AND COMMENT-AWARE. A whole-file `contains` flagged
		# InteractGeometry.gd on the docstring above, which QUOTES the dead lookup to
		# explain it — the string in prose, not in code. That is the same substring
		# mistake this file exists to document, made inside its own guard.
		for raw_line in text.split("\n"):
			var line: String = raw_line.strip_edges()
			if line.begins_with("#"):
				continue
			if line.contains('get_node_or_null("Mode7Overlay")') or line.contains('get_node("Mode7Overlay")'):
				if not offenders.has(path.get_file()):
					offenders.append(path.get_file())
	# Output-side canary with a typed literal: names how many files were actually read, so
	# an unreadable set cannot report "no offenders".
	assert_eq(checked, 5,
		"read %d of 5 consumer files — a zero offender count below is not a reading" % checked)
	assert_eq(offenders.size(), 0,
		"still resolving the overlay by node path, which is null at root: %s" % ", ".join(offenders))
