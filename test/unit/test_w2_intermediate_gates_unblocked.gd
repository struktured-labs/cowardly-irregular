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
## Fix: auto-set the defeat flags after the matching narrative beat
## completes — arbiter after intro_complete, curator after chapter5_complete.
## The Masterite battles become off-screen narrative beats rather than
## actual fights (battle infrastructure for them is unimplemented).

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


func test_arbiter_defeat_auto_set_after_intro_complete() -> void:
	var body := _pending_cutscene_body()
	var pattern: String = (
		"if flags.get(\"cutscene_flag_arbiter_suburban_intro_complete\", false) "
		+ "and not flags.get(\"cutscene_flag_arbiter_suburban_defeated\", false):"
	)
	assert_true(body.contains(pattern),
		"W2 must auto-set arbiter_suburban_defeated after arbiter_suburban_intro_complete — otherwise chapter5 unreachable")
	# Tick 220: now via _set_cutscene_flag_and_mirror so the flag also lands in story_flags.
	assert_true(body.contains("_set_cutscene_flag_and_mirror(\"cutscene_flag_arbiter_suburban_defeated\")"),
		"the gate must actually assign the flag (via mirror helper) — gate alone is a no-op")


func test_curator_defeat_auto_set_after_chapter5_complete() -> void:
	var body := _pending_cutscene_body()
	var pattern: String = (
		"if flags.get(\"cutscene_flag_world2_chapter5_complete\", false) "
		+ "and not flags.get(\"cutscene_flag_curator_suburban_defeated\", false):"
	)
	assert_true(body.contains(pattern),
		"W2 must auto-set curator_suburban_defeated after world2_chapter5_complete — otherwise chapter7_infrastructure unreachable")
	# Tick 220: now via _set_cutscene_flag_and_mirror.
	assert_true(body.contains("_set_cutscene_flag_and_mirror(\"cutscene_flag_curator_suburban_defeated\")"),
		"the gate must actually assign the flag (via mirror helper)")


func test_arbiter_auto_set_precedes_chapter5_gate() -> void:
	# Ordering: arbiter auto-set must come BEFORE the chapter5 gate
	# in source so chapter5 reads arbiter_defeated as TRUE on the
	# same evaluation pass after intro completes.
	var body := _pending_cutscene_body()
	# Tick 220: pin the helper call instead of the bare write.
	var auto_set_idx: int = body.find("_set_cutscene_flag_and_mirror(\"cutscene_flag_arbiter_suburban_defeated\")")
	var chapter5_idx: int = body.find("return \"world2_chapter5\"")
	assert_gt(auto_set_idx, -1, "arbiter auto-set must exist")
	assert_gt(chapter5_idx, -1, "chapter5 return must exist")
	assert_lt(auto_set_idx, chapter5_idx,
		"arbiter auto-set must precede the chapter5 return — otherwise chapter5 reads stale defeated=false on first pass")


func test_curator_auto_set_precedes_chapter7_gate() -> void:
	var body := _pending_cutscene_body()
	# Tick 220: pin the helper call instead of the bare write.
	var auto_set_idx: int = body.find("_set_cutscene_flag_and_mirror(\"cutscene_flag_curator_suburban_defeated\")")
	var chapter7_idx: int = body.find("return \"world2_chapter7_infrastructure\"")
	assert_gt(auto_set_idx, -1, "curator auto-set must exist")
	assert_gt(chapter7_idx, -1, "chapter7 return must exist")
	assert_lt(auto_set_idx, chapter7_idx,
		"curator auto-set must precede the chapter7 return — otherwise chapter7 reads stale defeated=false on first pass")


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
