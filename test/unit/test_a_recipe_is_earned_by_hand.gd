extends GutTest

## Recipe catalog + ledger (struktured 2026-11-23: rules earned by playing manually, ~10 uses).
## Unwired: these arms pin the catalog's data and the ledger's counting, persistence and reset.

const STORY_IDS := [
	"heal_ally_under_50", "cure_status", "hit_known_weakness", "finish_under_25",
	"defer_at_low_ap", "advance_full_bank", "bard_riff_unblinded", "steal_first", "revive_ko",
]
const R := "defer_at_low_ap"
const OTHER := "finish_under_25"


func before_each() -> void:
	RecipeCatalog._reset_cache_for_test()


func _ledger() -> RecipeLedger:
	return RecipeLedger.new()


func _press(l: RecipeLedger, actor: String, ids: Array, times: int, manual: bool = true) -> Array:
	var earned_now: Array = []
	for i in times:
		earned_now.append_array(l.record(actor, ids, manual))
	return earned_now


func test_the_catalog_carries_every_starter_recipe_with_a_valid_rule() -> void:
	var ids := RecipeCatalog.ids()
	assert_eq(ids.size(), STORY_IDS.size(), "CONTROL: catalog read %d recipes, expected %d" % [ids.size(), STORY_IDS.size()])
	for id in STORY_IDS:
		assert_true(ids.has(id), "catalog is missing the starter recipe '%s'" % id)
	for r in RecipeCatalog.catalog():
		var errs: Array = AutobattleSystem.validate_rule(r["rule"])
		assert_eq(errs.size(), 0, "recipe '%s' carries a rule the evaluator refuses: %s" % [r["id"], errs])
		for k in ["name", "line", "flavour"]:
			assert_ne(str(r.get(k, "")), "", "recipe '%s' has no %s for the reveal" % [r["id"], k])
		assert_true(str(r["line"]).contains(str(int(r["threshold"]))),
			"recipe '%s' says \"%s\" but its threshold is %d — the reveal would lie" % [r["id"], r["line"], int(r["threshold"])])


func test_ten_manual_choices_earn_the_card_exactly_once() -> void:
	var l := _ledger()
	var need := RecipeCatalog.threshold(R)
	assert_gt(need, 1, "CONTROL: the recipe needs more than one use, or 'earned too early' cannot be seen")
	assert_eq(_press(l, "p1", [R], need - 1), [], "the card was earned before its %d-th use" % need)
	assert_false(l.is_earned("p1", R), "earned at %d of %d" % [l.count("p1", R), need])
	watch_signals(l)
	assert_eq(l.record("p1", [R], true), [R] as Array[String], "the %d-th manual use did not earn '%s'" % [need, R])
	assert_signal_emit_count(l, "recipe_earned", 1)
	assert_eq(_press(l, "p1", [R], 5), [], "an earned card was earned again")
	assert_eq(l.count("p1", R), need, "a count ran past its threshold to %d" % l.count("p1", R))


func test_an_autobattle_turn_teaches_nothing() -> void:
	var l := _ledger()
	_press(l, "p1", [R], RecipeCatalog.threshold(R) * 3, false)
	assert_eq(l.count("p1", R), 0, "autobattle turns counted toward a recipe — the script would teach itself")
	assert_eq(l.earned("p1"), [] as Array[String], "an autobattle-only character earned a card")


func test_counts_belong_to_one_character_and_one_recipe() -> void:
	var l := _ledger()
	_press(l, "p1", [R, R, "no_such_recipe"], 3)
	assert_eq(l.count("p1", R), 3, "a choice listing a recipe twice counted it twice (or not at all)")
	assert_eq(l.count("p2", R), 0, "p1's choices leaked into p2's progress")
	assert_eq(l.count("p1", OTHER), 0, "one recipe's choices counted toward another")
	assert_eq(l.count("p1", "no_such_recipe"), 0, "an id the catalog does not have was counted")


func test_progress_survives_a_json_save_and_a_new_game_clears_it() -> void:
	var l := _ledger()
	var need := RecipeCatalog.threshold(R)
	_press(l, "p1", [R], need)
	_press(l, "p1", [OTHER], 4)
	var loaded := _ledger()
	loaded.from_dict(JSON.parse_string(JSON.stringify(l.to_dict())))
	assert_true(loaded.is_earned("p1", R), "an earned card was lost through a JSON save")
	assert_eq(loaded.count("p1", OTHER), 4, "progress 4 came back as %d through a JSON save" % loaded.count("p1", OTHER))
	assert_eq(loaded.earned("p1"), [R] as Array[String], "earned list changed through a JSON save")
	loaded.reset()
	assert_eq(loaded.count("p1", OTHER), 0, "New Game kept last run's progress")
	assert_false(loaded.is_earned("p1", R), "New Game kept last run's card")


func test_a_save_from_another_catalog_loads_without_ghosts() -> void:
	var l := _ledger()
	var need := RecipeCatalog.threshold(OTHER)
	l.from_dict({"counts": {"p1": {OTHER: float(need + 7), "retired_recipe": 3.0}}, "earned": {"p1": ["retired_recipe"]}})
	assert_eq(l.count("p1", OTHER), need, "a saved count above the threshold was not clamped")
	assert_true(l.is_earned("p1", OTHER), "a saved count at or past a lowered threshold did not earn on load")
	assert_false(l.earned("p1").has("retired_recipe"), "a recipe the catalog dropped came back as an earned card")


func test_the_reveal_dict_has_every_key_the_popup_reads() -> void:
	var l := _ledger()
	_press(l, "p1", [R], 6)
	var d := l.reveal_dict("p1", R)
	for k in ["name", "line", "flavour", "rarity", "icon_key", "progress", "threshold"]:
		assert_true(d.has(k), "reveal dict lacks '%s'" % k)
	assert_eq(d.get("name"), "Strategic Cowardice", "the reveal shows the wrong recipe's name")
	assert_eq(d.get("progress"), 6, "the reveal shows %s of %s, the ledger counted 6" % [d.get("progress"), d.get("threshold")])
	assert_eq(l.reveal_dict("p1", "no_such_recipe"), {}, "an unknown recipe produced a reveal")
