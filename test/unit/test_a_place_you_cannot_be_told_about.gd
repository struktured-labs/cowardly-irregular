extends GutTest

## Two World 1 destinations had a working transition and **no signpost anywhere**: Scriptura Plaza
## and the Backwards Warren. Neither is hidden by design — Scriptura is the capital, and it holds the
## Guild scholar that `world1_thirty_seven`'s step 2 sends you to talk to. A player who never walks
## into that corner of the map cannot be told the place exists.
##
## ⚠️ SCOPED TO W1 DELIBERATELY, and the numbers are why rather than an omission. Measured at runtime
## across all six overworlds, matching a destination's map id against every signpost's text:
##
##     medieval   signs 16  transitions 12  unnamed []
##     suburban   signs  8  transitions  3  unnamed []
##     steampunk  signs  8  transitions  3  unnamed [suburban_overworld]
##     industrial signs  8  transitions  3  unnamed [steampunk_overworld]
##     futuristic signs  7  transitions  3  unnamed [industrial_overworld]
##     abstract   signs  8  transitions  3  unnamed [futuristic_overworld]
##
## Those four are NOT gaps — each world signs its BACKWARD portal poetically ("↓ Return ◉ Source
## Layer (W5)") rather than by map id, so an id-token predicate over-reports on every one of them.
## Encoding that convention would be an allowlist wearing a rule's clothes. W1 names its destinations
## literally, which is what makes the property checkable there at all.

const W1 := "res://src/exploration/OverworldScene.gd"
## ⚠️ A DESTINATION MAY BE DELIBERATELY UNSIGNED, and without this the guard forbids a real design
## choice while claiming a defect (@cowir-music's shape: the fix right, the reason wrong). W1 already
## hides things on purpose — the Sunken Ring and the Frozen Alcove are behind disguised walls — so a
## future hidden entrance must be able to stay unsigned. You cannot silence this green, only explain
## it green: the reason is required and must be long enough to disagree with.
const DELIBERATELY_UNSIGNED := {}

## Ids whose own words are too generic to carry a match; each is signed by a PROPER name instead.
const PROPER_NAMES := {
	"backwards_warren": "warren",
	"scriptura_plaza": "scriptura",
	"suburban_overworld": "portal",
	"castle_harmonia": "harmonia",
}


## ⛔ THE GATED HALF, and this guard was VACUOUS about it for one revision. Castle Harmonia and
## Scriptura are built only when `_castle_is_earned` is true, so a fresh-state instantiation yields
## 12 transitions and silently omits the two that matter most — including the one this file was
## written for. Deleting the Scriptura sign left it GREEN. The flag is armed and restored here, the
## same way the village-chest sweep had to arm ScripturaPlaza's quest gate.
func _arm_spine(gs: Node) -> Dictionary:
	var prior: Dictionary = {"flags": gs.story_flags.duplicate(true)}
	gs.set_story_flag("world1_mordaine_defeated", true)
	return prior


func test_every_w1_destination_is_named_on_a_signpost() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "PRECONDITION: GameState — without it the gated destinations never build")
	if gs == null:
		return
	var prior: Dictionary = _arm_spine(gs)

	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var w = load(W1).new()
	vp.add_child(w)
	await get_tree().physics_frame
	gs.story_flags = prior["flags"]

	var signs: Array = []
	var dests: Array = []
	var stack: Array = [w]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get_script() == null:
			continue
		var base: String = str(n.get_script().resource_path).get_file().get_basename()
		if base == "Signpost" and "sign_text" in n:
			signs.append(str(n.sign_text).to_lower())
		elif base == "AreaTransition" and "target_map" in n:
			dests.append(str(n.target_map))

	var blob: String = " ".join(signs)
	assert_gt(signs.size(), 10, "CONTROL: only %d signposts collected — the scan is broken and the [] below is free" % signs.size())
	assert_gte(dests.size(), 14,
		"CONTROL: %d transitions collected, expected 14 — the SPINE GATE is not armed, so " % dests.size() +
		"castle_harmonia and scriptura_plaza are absent and this file is vacuous about both")

	var unnamed: Array = []
	for d in dests:
		var hit := false
		if PROPER_NAMES.has(d) and blob.contains(str(PROPER_NAMES[d])):
			hit = true
		for tok in str(d).split("_"):
			if str(tok).length() > 3 and blob.contains(str(tok)):
				hit = true
		if DELIBERATELY_UNSIGNED.has(d):
			continue
		if not hit and not unnamed.has(d):
			# The BUILDER is the whole message: GUT prints `at line -1` for these asserts, so a bare
			# id leaves the reader with nothing to act on (@cowir-story / @cowir-adhoc, 2026-09-12).
			var toks: Array = []
			for tok in str(d).split("_"):
				if str(tok).length() > 3:
					toks.append(str(tok))
			unnamed.append("%s — no signpost mentions %s; add a row to _place_signposts, or add the proper name it IS signed by to PROPER_NAMES, or record it in DELIBERATELY_UNSIGNED with a reason" % [d, ", ".join(toks)])
	unnamed.sort()

	assert_eq(unnamed, [],
		"a W1 destination has a working transition and no signpost naming it — the player can walk " +
		"into it and can never be TOLD it is there: %s" % str(unnamed))


## CONTROL: the scan must be able to report a destination as unnamed, or the [] above is decoration.
func test_the_scan_can_see_an_unnamed_destination() -> void:
	var signs: Array = ["← harmonia village", "↑ whispering cave"]
	var blob: String = " ".join(signs)
	var unnamed: Array = []
	for d in ["harmonia_village", "scriptura_plaza"]:
		var hit := false
		if PROPER_NAMES.has(d) and blob.contains(str(PROPER_NAMES[d])):
			hit = true
		for tok in str(d).split("_"):
			if str(tok).length() > 3 and blob.contains(str(tok)):
				hit = true
		if not hit:
			unnamed.append(d)
	assert_eq(unnamed, ["scriptura_plaza"],
		"the predicate must name the destination no sign mentions, and only that one")


## The exemption's teeth: a reason a reader can disagree with, not a checkbox (@cowir-autogrind).
func test_an_unsigned_destination_must_be_explained_not_silenced() -> void:
	assert_true(DELIBERATELY_UNSIGNED is Dictionary, "the exemption is a reason map, not a list")
	for d in DELIBERATELY_UNSIGNED:
		var why: String = str(DELIBERATELY_UNSIGNED[d])
		assert_gt(why.length(), 40,
			"%s is exempt with the reason %s — an exemption needs a reason a reader can disagree " % [d, why] +
			"with, naming what makes this destination one a player should DISCOVER rather than be told about")


## ⛔ A REASON REQUIREMENT CATCHES A LAZY ENTRY, NOT A STALE ONE (@cowir-autogrind). An exemption
## goes inert two ways — the destination gets signed later, or it stops existing — and then it reads
## as coverage that is no longer there. Same shape as this repo's "GOOD NEWS, STALE LIST" arm in
## test_no_job_is_unlockable_by_nothing_regression: a list shrinking is news, and silence is not.
func test_an_exemption_that_stopped_being_true_must_be_deleted() -> void:
	if DELIBERATELY_UNSIGNED.is_empty():
		# Vacuous BY CONSTRUCTION today and that is honest: the dict ships empty. The arm below is
		# proven to fire by planting an occupant, so an entry cannot rot silently once one exists.
		assert_true(true, "no exemptions authored — nothing to go stale")
		return
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	var prior: Dictionary = _arm_spine(gs)
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var w = load(W1).new()
	vp.add_child(w)
	await get_tree().physics_frame
	gs.story_flags = prior["flags"]

	var signs: Array = []
	var dests: Array = []
	var stack: Array = [w]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get_script() == null:
			continue
		var base: String = str(n.get_script().resource_path).get_file().get_basename()
		if base == "Signpost" and "sign_text" in n:
			signs.append(str(n.sign_text).to_lower())
		elif base == "AreaTransition" and "target_map" in n:
			dests.append(str(n.target_map))
	var blob: String = " ".join(signs)

	var stale: Array = []
	for d in DELIBERATELY_UNSIGNED:
		if not dests.has(str(d)):
			stale.append("%s — exempt, but no W1 transition targets it any more; delete the DELIBERATELY_UNSIGNED entry" % d)
			continue
		var named := false
		for tok in str(d).split("_"):
			if str(tok).length() > 3 and blob.contains(str(tok)):
				named = true
		if PROPER_NAMES.has(d) and blob.contains(str(PROPER_NAMES[d])):
			named = true
		if named:
			stale.append("%s — exempt as deliberately unsigned, but a signpost NAMES it now; delete the DELIBERATELY_UNSIGNED entry, the exemption is claiming cover it no longer needs" % d)
	stale.sort()
	assert_eq(stale, [],
		"an exemption stopped being true — it reads as coverage this guard no longer has: %s" % str(stale))
