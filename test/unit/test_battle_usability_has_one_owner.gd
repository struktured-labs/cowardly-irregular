extends GutTest

## "META items cannot be used in a battle" had TWO copies: BattleCommandMenu filtered the
## player's Use Item list on it, and RuleComposer._battle_item_ids re-derived the same rule
## for the model — spelling `ItemSystem.ItemCategory.META` as a literal `4` while the enum
## was reachable from the file next to it.
##
## No live defect: the copies agreed. This is the class that DID cost something today —
## AutogrindUI's between-battle predicate was private, the LLM prompt re-derived it, and 40
## of 53 delivered actions were silent no-ops. A correct copy the next consumer cannot
## reach is invisible to every check that asks whether the value is correct, which is why
## the arm below asks a different question: does anyone spell the rule twice.

const RC := preload("res://src/llm/RuleComposer.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


# ── the owner answers ─────────────────────────────────────────────────────────

func test_a_meta_item_is_not_usable_in_a_battle() -> void:
	var meta: Array = []
	for iid in ItemSystem.items.keys():
		if int((ItemSystem.items[iid] as Dictionary).get("category", -1)) == ItemSystem.ItemCategory.META:
			meta.append(str(iid))
	assert_gt(meta.size(), 0, "CONTROL: items.json must actually contain META items")
	for iid in meta.slice(0, 5):
		assert_false(ItemSystem.is_usable_in_battle(str(iid)), "%s is META" % iid)


func test_a_consumable_and_a_curative_are_usable() -> void:
	for iid in ["potion", "echo_herbs"]:
		assert_true(ItemSystem.is_usable_in_battle(iid), "%s must be offerable" % iid)


func test_an_item_that_does_not_exist_is_not_usable() -> void:
	## The composer feeds it ids from a model. An unknown id must be a refusal, not a
	## default-true that hands the deep check something to reject later.
	assert_false(ItemSystem.is_usable_in_battle("captain_nobodys_hat"), "unknown is not usable")
	assert_false(ItemSystem.is_usable_in_battle(""), "and neither is nothing")


# ── both consumers ASK it rather than re-deriving ─────────────────────────────

func test_the_composers_offer_is_exactly_what_the_owner_accepts() -> void:
	## Derived from the store on both sides, so this cannot go stale against a new item.
	var offered: Array = _rc()._battle_item_ids()
	assert_gt(offered.size(), 10, "CONTROL: the battle categories must resolve")
	var expected: Array = []
	for iid in ItemSystem.items.keys():
		if ItemSystem.is_usable_in_battle(str(iid)):
			expected.append(str(iid))
	expected.sort()
	assert_eq(offered, expected, "the prompt offers exactly what the engine calls usable")


func test_neither_consumer_spells_the_rule_a_second_time() -> void:
	## THE RATCHET, and the only arm here that could have prevented today's 40-of-53: a
	## re-derivation is invisible to every check that asks whether the VALUE is right,
	## because both copies are right until one of them moves.
	##
	## Comments stripped: this file's own prose names ItemCategory.META, and so does the
	## owner's docstring.
	for path in ["res://src/llm/RuleComposer.gd", "res://src/battle/BattleCommandMenu.gd"]:
		var code: String = GdSource.code_of(path)
		assert_false(code.is_empty(), "CONTROL: %s must be readable" % path)
		assert_true(code.find("ItemCategory.META") == -1,
			"%s decides battle usability itself instead of asking ItemSystem" % path)
		assert_true(code.find("is_usable_in_battle") != -1,
			"%s must ask the owner" % path)
