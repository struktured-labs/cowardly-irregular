extends GutTest

## Party-panel AP at the +4 cap used the same lime as +1/+2/+3, so a full
## bank did not read as a full bank. Gold is the existing full-bank language
## (AdvanceAura rim + the ★ on a discounted Advance). Helper: BattleUIManager._ap_bbcode.

const UIM := preload("res://src/battle/BattleUIManager.gd")


func _ui():
	var ui = UIM.new(null)
	autofree(ui)
	return ui


func test_ap_color_helper_exists() -> void:
	var ui = _ui()
	assert_true(ui.has_method("_ap_bbcode"),
		"AP color must live on one helper — party and enemy panels cannot keep their own lime/red ternary")


func test_maxed_ap_is_not_ordinary_positive() -> void:
	var ui = _ui()
	assert_true(ui.has_method("_ap_bbcode"), "floor: helper must exist or the next line aborts")
	var maxed: String = str(ui._ap_bbcode(BattleManager.FULL_BANK_AP))
	var ordinary: String = str(ui._ap_bbcode(1))
	assert_ne(maxed, ordinary,
		"+%d AP must not share the +1 color — that is the whole tell" % BattleManager.FULL_BANK_AP)
	assert_eq(str(ui._ap_bbcode(BattleManager.FULL_BANK_AP - 1)), ordinary,
		"+%d is still ordinary positive, not the cap color" % (BattleManager.FULL_BANK_AP - 1))


func test_maxed_ap_is_gold_not_a_named_lane() -> void:
	var ui = _ui()
	assert_true(ui.has_method("_ap_bbcode"), "floor: helper must exist or the next line aborts")
	var maxed: String = str(ui._ap_bbcode(BattleManager.FULL_BANK_AP))
	assert_false(maxed in ["lime", "red", "white", "cyan", "magenta"],
		"cap color must not collide with the +/0/− lanes (or their colorblind swaps)")
	assert_ne(maxed, AccessibilityPalette.bonus_bbcode(),
		"cap color must stay distinct from bonus (lime/cyan) so colorblind mode still shows the tell")


func test_zero_and_debt_keep_their_lanes() -> void:
	var ui = _ui()
	assert_true(ui.has_method("_ap_bbcode"), "floor: helper must exist or the next line aborts")
	assert_eq(str(ui._ap_bbcode(0)), "white")
	assert_eq(str(ui._ap_bbcode(-1)), "red")
	assert_eq(str(ui._ap_bbcode(1)), "lime")


func test_both_panels_use_the_helper() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_gt(src.length(), 1000, "CONTROL: read BattleUIManager")
	assert_true(src.contains("var ap_color = _ap_bbcode("),
		"both AP blocks must ask the helper, not keep a private ternary")
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("var ap_color = _ap_bbcode(", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	assert_eq(count, 2,
		"party panel AND enemy panel must both go through _ap_bbcode (got %d)" % count)
