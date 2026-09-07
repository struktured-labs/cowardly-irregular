extends GutTest

## struktured 2026-09-07: "if some ability gains MP it should be differently colored (purple)
## than HP (green) and AP should be another color (red)". Before: every MP restore (Pray /
## Channel / Riff / ethers / drain_mp) rode healing_done and popped GREEN, indistinguishable
## from a cure; ability AP grants popped nothing at all.

const BM_SRC := "res://src/battle/BattleManager.gd"
const IS_SRC := "res://src/items/ItemSystem.gd"


func _popup(kind: String) -> DamageNumber:
	var n := DamageNumber.new()
	n.setup(25, true, false, kind)
	add_child_autofree(n)
	return n


func test_three_resources_three_colors() -> void:
	var hp := _popup("hp")
	var mp := _popup("mp")
	var ap := _popup("ap")
	var c_hp: Color = hp._label.get_theme_color("font_color")
	var c_mp: Color = mp._label.get_theme_color("font_color")
	var c_ap: Color = ap._label.get_theme_color("font_color")
	assert_eq(c_hp, AccessibilityPalette.heal(), "HP heals keep the heal palette (green by default)")
	assert_eq(c_mp, AccessibilityPalette.mp(), "MP gains use the MP palette")
	assert_eq(c_ap, AccessibilityPalette.ap(), "AP grants use the AP palette")
	assert_ne(c_hp, c_mp, "green vs purple must differ")
	assert_ne(c_mp, c_ap, "purple vs red must differ")
	assert_ne(c_hp, c_ap, "green vs red must differ")


func test_default_palette_is_green_purple_red() -> void:
	# His words, pinned as hue relationships rather than exact literals (the exact tint is his to move).
	var mp := AccessibilityPalette.mp()
	var ap := AccessibilityPalette.ap()
	if AccessibilityPalette.is_on():
		pass_test("accessibility mode on — hue check skipped, distinctness covered above")
		return
	assert_true(mp.b > mp.g and mp.r > mp.g, "purple = red+blue over green: %s" % str(mp))
	assert_true(ap.r > ap.g and ap.r > ap.b, "red dominant: %s" % str(ap))


func test_mp_and_ap_popups_say_which_resource() -> void:
	assert_true(_popup("mp")._label.text.contains("MP"), "an MP popup names MP so purple isn't a guess")
	assert_true(_popup("ap")._label.text.contains("AP"), "an AP popup names AP")
	assert_false(_popup("hp")._label.text.contains("HP"), "CONTROL: HP heals keep the bare number")


func test_the_default_kind_is_hp_so_every_existing_caller_is_unchanged() -> void:
	var n := DamageNumber.new()
	n.setup(10, true, false)
	add_child_autofree(n)
	assert_eq(n.kind, "hp")
	assert_eq(n._label.get_theme_color("font_color"), AccessibilityPalette.heal())


func test_no_mp_restore_site_still_pops_green() -> void:
	# Every restore_mp that feeds a popup must emit mp_restored, not healing_done.
	var bm := FileAccess.get_file_as_string(BM_SRC)
	var it := FileAccess.get_file_as_string(IS_SRC)
	var offenders: Array[String] = []
	for src_pair in [["BattleManager", bm], ["ItemSystem", it]]:
		var lines: PackedStringArray = (src_pair[1] as String).split("\n")
		for i in lines.size():
			if not lines[i].contains("healing_done.emit("):
				continue
			var window := ""
			for j in range(maxi(0, i - 6), i):
				window += lines[j] + "\n"
			if window.contains("restore_mp(") or window.contains("actual_mp"):
				offenders.append("%s:%d" % [src_pair[0], i + 1])
	assert_eq(offenders, [] as Array[String], "MP restores emitting the GREEN heal signal: %s" % str(offenders))
	assert_gt(bm.count("mp_restored.emit("), 2, "CONTROL: the MP sites actually moved to mp_restored")
	assert_gt(bm.count("ap_granted.emit("), 2, "CONTROL: ability AP grants emit ap_granted")
