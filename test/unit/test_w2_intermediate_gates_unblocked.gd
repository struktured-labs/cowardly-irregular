extends GutTest

## tick 101 regression: the W2 chapter chain depended on two never-set
## defeat flags (cutscene_flag_arbiter_suburban_defeated +
## cutscene_flag_curator_suburban_defeated). Both flags were set only
## by JSON cutscenes (world2_arbiter_defeat.json + world2_curator_defeat.json)
## that NO code path triggered.
##
## Net effect pre-fix: W2 chapter5 (community center / Coordinator
## reveal) and chapter7_infrastructure (feral shopping cart) were
## both unreachable. After tick 100 unblocked W2→W3, the chain was
## STILL broken inside W2 because the arbiter and curator gates never
## fired.
##
## Tick 101's fix auto-set both flags after the matching narrative beat, making the battles
## "off-screen narrative beats" because nothing could trigger them.
##
## SUPERSEDED: both are real fights now, placed by MapleHeightsVillage._place_masterites, and the
## auto-sets are gone. The arms below keep this file's actual subject — every gate in the W2 chain
## has a writer, so no intermediate chapter is unreachable — and add the half tick 101 could not
## assert: that the writer is a victory rather than a grant.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _pending_cutscene_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _get_pending_story_cutscene")
	assert_gt(idx, -1, "_get_pending_story_cutscene must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


## The flags each gate reads, and the village that must contain the fight writing them.
const W2_GATED := {
	"cutscene_flag_arbiter_suburban_defeated": "return \"world2_chapter5\"",
	"cutscene_flag_curator_suburban_defeated": "return \"world2_chapter7_infrastructure\"",
}
const VILLAGE_DIR := "res://src/maps/villages"


func _village_sources() -> String:
	var all := ""
	var d := DirAccess.open(VILLAGE_DIR)
	assert_not_null(d, "FLOOR: %s must be listable — both arms below read it" % VILLAGE_DIR)
	if d == null:
		return all
	for f in d.get_files():
		if f.ends_with(".gd"):
			all += FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f)
	return all


func test_each_w2_gate_still_reads_its_defeat_flag() -> void:
	## Reachability is this file's subject. The gates must still be there to be reached.
	var body := _pending_cutscene_body()
	for flag in W2_GATED:
		assert_true(body.contains(flag),
			"the W2 chain must still gate on %s" % flag)
		assert_true(body.contains(str(W2_GATED[flag])),
			"%s must still have its return path" % str(W2_GATED[flag]))


func test_each_w2_defeat_flag_is_written_by_a_fight() -> void:
	## WAS: "W2 must auto-set arbiter_suburban_defeated ... otherwise chapter5 unreachable".
	## Tick 101 granted both defeats the instant the preceding beat ended, because the battles
	## had no trigger — its own comment called them "off-screen narrative beats". They are fought
	## now (MapleHeightsVillage._place_masterites), so the writer is a victory, not a gate.
	## The requirement is unchanged in substance: every gating flag must have a writer.
	var villages := _village_sources()
	for flag in W2_GATED:
		assert_true(villages.contains('defeat_flag_name = "%s"' % flag),
			"%s must be written by a placed MasteriteEncounter — a gate with no writer strands the chain" % flag)


func test_no_w2_defeat_is_granted_without_the_fight() -> void:
	## The other half: re-adding an auto-set would hand back the unfought victory AND make the
	## placed encounter dead content, with the chain still traversable so nothing else would notice.
	var body := _pending_cutscene_body()
	for flag in W2_GATED:
		assert_false(body.contains('_set_cutscene_flag_and_mirror("%s")' % flag),
			"%s must not be auto-set: that grants a defeat the player never fought" % flag)


func test_full_w2_chain_now_traversable_in_source() -> void:
	# Sanity: every W2 chapter cutscene from prologue through
	# chapter11 has a return path AND any gating flag has a setter
	# somewhere in source (cutscene completion handler, or auto-set
	# block from tick 100/101).
	var src := _read(GAME_LOOP)
	for w2_chapter in ["world2_prologue", "world2_chapter1", "world2_chapter2",
	                   "world2_chapter3", "world2_chapter4_garage", "world2_chapter4",
	                   "world2_chapter5", "world2_chapter7_infrastructure",
	                   "world2_chapter8_memos", "world2_chapter11"]:
		assert_true(src.contains("return \"" + w2_chapter + "\""),
			"%s must have a return path in _get_pending_story_cutscene" % w2_chapter)


func test_w2_arbiter_intro_completion_flag_unchanged() -> void:
	# Sanity: the world2_chapter4 → arbiter_suburban_intro_complete
	# mapping in _CUTSCENE_COMPLETION_FLAGS must still exist —
	# tick 101's auto-set depends on that flag being settable.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("\"world2_chapter4\":                  \"cutscene_flag_arbiter_suburban_intro_complete\""),
		"_CUTSCENE_COMPLETION_FLAGS must still map world2_chapter4 → arbiter_suburban_intro_complete — tick 101 depends on it")
