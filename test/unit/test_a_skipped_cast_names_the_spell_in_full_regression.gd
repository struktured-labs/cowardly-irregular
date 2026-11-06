extends GutTest

## Since .772 a skipped Member Casts names its ability by the menu's name, which is longer than the id it replaced, so the Summary's
## 36-character cut showed "Member Casts: Mira does not know Sa…": the one word the player needed was the one cut. A long reason
## now drops its generic action prefix before cutting, so the caster and the spell survive.

const Summary := preload("res://src/ui/autogrind/AutogrindSummary.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


## The real reason the system writes, through the real skip path, for an ability the caster does not know.
func _real_reason(aid: String) -> String:
	var mira := Combatant.new()
	add_child_autofree(mira)
	mira.initialize({"name": "Mira", "max_hp": 100, "max_mp": 50})
	return "Member Casts: %s" % str(AutogrindSystem._member_ability_apply(mira, aid, "").get("reason", ""))


func test_a_long_skip_reason_keeps_the_spell_name() -> void:
	var checked := 0
	for aid in ["cure", "raise", "protect", "fire", "blizzard", "esuna"]:
		if JobSystem.get_ability(aid).is_empty():
			continue
		var reason := _real_reason(aid)
		if reason.length() <= Summary.RULE_NOOP_REASON_CHARS:
			continue
		checked += 1
		var label: String = Summary.noop_reason_label(reason)
		assert_string_contains(label, AbilityIcons.name_of(aid), "'%s' must keep the spell's name, got '%s'" % [reason, label])
		assert_lte(label.length(), Summary.RULE_NOOP_REASON_CHARS, "and still fit the row")
	assert_gt(checked, 0, "CONTROL: at least one real skip reason is longer than the row, or this arm proves nothing")


func test_a_short_reason_is_untouched() -> void:
	assert_eq(Summary.noop_reason_label("Restore MP: out of ethers"), "Restore MP: out of ethers", "a reason that fits keeps its action prefix")


func test_a_reason_too_long_even_without_its_prefix_is_still_cut() -> void:
	var long := "Member Casts: " + "x".repeat(60)
	var label: String = Summary.noop_reason_label(long)
	assert_true(label.ends_with("…"), "an overlong reason is still cut, so it can't run into the count")
	assert_eq(label.length(), Summary.RULE_NOOP_REASON_CHARS, "at the row's width")


func test_the_summary_rows_use_it() -> void:
	var sm: Node = Summary.new()
	add_child_autofree(sm)
	sm._stats = {"rule_noops": {_real_reason("cure"): 3}}
	var rows: Array = sm._rule_noop_rows()
	assert_eq(rows.size(), 1, "CONTROL: one skipped rule, one row")
	assert_string_contains(str(rows[0]["label"]), AbilityIcons.name_of("cure"), "the Summary row shows the spell the rule tried to cast")
