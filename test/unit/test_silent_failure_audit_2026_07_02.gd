extends GutTest

## Silent-failure audit (2026-07-02, silent-failure-hunter agent) —
## pins for the six verified findings. This project's core principle:
## "silent failures are worse than crashes."


func test_missing_duelist_returns_unavailable_not_defeat() -> void:
	# Finding 1 (CRITICAL): a job-swapped-away duelist made
	# start_solo_battle return "defeat" — the cutscene retry loop
	# retried FOREVER (softlock that survived reload). Sentinel +
	# skip-step handling.
	var gl: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var idx: int = gl.find("no party member with job")
	assert_gt(idx, -1)
	assert_true(gl.substr(idx, 300).contains("return \"unavailable\""),
		"missing PC must return the 'unavailable' sentinel, not 'defeat'")
	var cd: String = FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var bidx: int = cd.find("start_solo_battle(str(combatants[0])")
	assert_gt(bidx, -1)
	assert_true(cd.substr(bidx, 500).contains("result != \"defeat\""),
		"the retry loop must skip (not retry) non-defeat sentinels")


func test_zero_forced_spawns_never_reach_battle() -> void:
	# Finding 2 (HIGH): all-unknown forced enemy ids spawned ZERO
	# enemies → first victory check saw "all enemies dead" → instant
	# reported WIN, defeat flags set for a fight that never happened.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleEnemySpawner.gd")
	var fn: int = src.find("func spawn_forced_enemies")
	var next_fn: int = src.find("\nfunc ", fn + 1)
	var body: String = src.substr(fn, next_fn - fn)
	assert_true(body.contains("test_enemies.is_empty()"),
		"forced spawn must empty-check after the loop")
	assert_true(body.contains("push_error"),
		"zero spawns must be LOUD — it means a typo'd cross-file id")


func test_out_of_range_objective_index_clamps_and_warns() -> void:
	# Finding 3 (HIGH): a saved objective_index beyond the (shrunk)
	# objectives array bricked the quest forever with zero feedback.
	var saved: Dictionary = GameState.quests.duplicate(true)
	GameState.quests["world1_fools_spread"] = {"state": "active", "objective_index": 99}
	var idx: int = QuestSystem.get_objective_index("world1_fools_spread")
	var total: int = (QuestSystem.get_quest("world1_fools_spread")["objectives"] as Array).size()
	assert_eq(idx, total - 1, "out-of-range index must clamp to the final objective")
	assert_eq(int(GameState.quests["world1_fools_spread"]["objective_index"]), total - 1,
		"the clamp must persist so the quest is completable")
	GameState.quests = saved


func test_loader_rejects_objectiveless_quests() -> void:
	# Finding 3b: an objective-less quest accepts into a permanently
	# uncompletable active state — loader must reject at load.
	var src: String = FileAccess.get_file_as_string("res://src/quests/QuestSystem.gd")
	assert_true(src.contains("has no objectives — skipped"),
		"loader must reject quests without objectives")
	assert_true(src.contains("read EMPTY — skipped"),
		"empty quest files must warn as loudly as parse failures")


func test_shop_refuses_spell_sale_without_live_mirror() -> void:
	# Finding 4 (MEDIUM): spend-then-teach could take gold while the
	# spell landed only in the clobbered snapshot ("paid, confirmed,
	# revoked"). Live mirror is now verified BEFORE spend_gold.
	var src: String = FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")
	var live_idx: int = src.find("var live_ok: bool")
	var spend_idx: int = src.find("if game_state.spend_gold(cost):", live_idx)
	assert_gt(live_idx, -1, "live-mirror check must exist")
	assert_gt(spend_idx, live_idx,
		"the live-mirror check must run BEFORE gold is spent")


func test_advance_subaction_has_default_arm() -> void:
	# Finding 6 (LOW): unknown Advance sub-action types were silently
	# eaten — imported autobattle scripts are player-editable JSON.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("unknown Advance sub-action type"),
		"advance sub-action match needs a loud default arm")
