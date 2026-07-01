extends GutTest

## tick 97 regression: the cleric spotlight cutscene must be
## triggered by _get_pending_story_cutscene, not just referenced by
## the completion-flag map. Pre-fix, spotlight cutscenes existed in
## data/cutscenes/ and were referenced by _CUTSCENE_COMPLETION_FLAGS,
## but NO code path actually played them — so non-Fighter PCs
## (Cleric, Mage, Rogue, Bard) stayed permanently
## autobattle-locked, with manual control gated behind cutscenes
## that never fired.
##
## This tick adds only the first gate (cleric @ chapter1_complete
## in harmonia_village). Other spotlights (rogue/mage @ ch3, bard
## @ ch7) follow the same pattern; pinned in later ticks.

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


func test_cleric_spotlight_cutscene_can_be_returned() -> void:
	# Pin: _get_pending_story_cutscene returns "world1_spotlight_cleric_ch1"
	# under some condition. Without this, the cleric spotlight is
	# unreachable code.
	var body := _pending_cutscene_body()
	assert_true(body.contains("return \"world1_spotlight_cleric_ch1\""),
		"_get_pending_story_cutscene must have a return path for world1_spotlight_cleric_ch1 — otherwise the cleric spotlight never fires and cleric stays autobattle-locked")


func test_cleric_gate_uses_correct_flag_pair() -> void:
	# Pin the exact gating pattern: chapter1_complete (predicate) +
	# not spotlight_unlocked_cleric (idempotence). A different flag
	# would either gate too early or never fire.
	var body := _pending_cutscene_body()
	assert_true(body.contains("flags.get(\"cutscene_flag_chapter1_complete\", false) and not flags.get(\"cutscene_flag_spotlight_unlocked_cleric\", false)"),
		"cleric spotlight gate must check chapter1_complete AND not spotlight_unlocked_cleric — without idempotence, the cutscene would loop")


func test_cleric_gate_scoped_to_harmonia_village() -> void:
	# Pin: the cutscene only fires in harmonia_village. Firing on
	# another map (e.g. mid-cave) would be tonally wrong (cleric
	# joins manual control "at the village well" per design comment).
	var body := _pending_cutscene_body()
	var idx: int = body.find("return \"world1_spotlight_cleric_ch1\"")
	assert_gt(idx, -1, "cleric spotlight return must exist")
	var window_start: int = max(0, idx - 200)
	var window: String = body.substr(window_start, idx - window_start)
	assert_true(window.contains("_current_map_id == \"harmonia_village\""),
		"cleric spotlight must be gated on _current_map_id == 'harmonia_village' — fires at the village well moment")


func test_cleric_cutscene_file_exists_and_embeds_battle() -> void:
	# Tick 471 architecture shift: spotlight_unlocked_<job> is now
	# written by GameLoop._on_battle_ended on battle_won, NOT by a
	# set_flag step in the cutscene. The cutscene must instead embed
	# a "battle" step against the cleric spotlight miniboss so the
	# engine has something to fight (and thus something to flag).
	var path := "res://data/cutscenes/world1_spotlight_cleric_ch1.json"
	assert_true(FileAccess.file_exists(path),
		"world1_spotlight_cleric_ch1.json must exist on disk")
	var raw: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary,
		"cleric spotlight cutscene must parse to a Dictionary")
	var steps: Variant = (parsed as Dictionary).get("steps", [])
	assert_true(steps is Array)
	var found_battle: bool = false
	for step in steps:
		if step is Dictionary and str((step as Dictionary).get("type", "")) == "battle":
			var combatants: Variant = (step as Dictionary).get("combatants", [])
			if combatants is Array and "cleric" in (combatants as Array):
				found_battle = true
				break
	assert_true(found_battle,
		"cleric spotlight cutscene must embed a `type:battle` step with combatants:[\"cleric\"] — GameLoop writes the unlock flag on battle_won")


func test_cleric_cutscene_in_completion_flag_map() -> void:
	# Pin: the _CUTSCENE_COMPLETION_FLAGS map must still cover this
	# cutscene id. Without the map entry, the chapter1_complete flag
	# is set (by play handler) but spotlight_unlocked_cleric is NOT,
	# leaving the cutscene to loop.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("\"world1_spotlight_cleric_ch1\":      \"cutscene_flag_spotlight_unlocked_cleric\""),
		"_CUTSCENE_COMPLETION_FLAGS map must still associate world1_spotlight_cleric_ch1 with cutscene_flag_spotlight_unlocked_cleric — otherwise cutscene loops")


func test_reconcile_spotlight_locks_handles_cleric() -> void:
	# Sanity: _reconcile_spotlight_locks reads
	# cutscene_flag_spotlight_unlocked_<job_id>. Pin the loop body
	# so a future refactor doesn't break the cleric path.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("var flag = \"cutscene_flag_spotlight_unlocked_\" + job_id"),
		"_reconcile_spotlight_locks must compute flag = 'cutscene_flag_spotlight_unlocked_' + job_id — cleric (job_id='cleric') uses this same path")
