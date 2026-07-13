extends GutTest

## Playtest 2026-07-13: "when hp is low, the color of the font should change
## in the RHS panel on the battle screen. I also think all that stuff is a
## little too hard to read, maybe increased font size a bit"
##
## Fix: party HP label recolors per HP tier via AccessibilityPalette (mirrors
## the enemy panel pattern at BattleUIManager:761). Font sizes bumped across
## the party status box for readability.


func test_party_hp_label_tinted_per_hp_tier() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	# Locate the UPDATE site (not the creation site) — the color logic lives
	# under the alive branch of `_update_member_status`, which is downstream
	# of the KO branch, so key off the KO-branch anchor.
	var i := src.find("hp_label.text = \"-- KO --\"")
	assert_gt(i, -1, "KO-branch anchor must exist to locate the update site")
	var body := src.substr(i, 900)
	assert_true("AccessibilityPalette.hp_low()" in body,
		"low-HP tier must recolor via AccessibilityPalette.hp_low() so colorblind mode still reads")
	assert_true("AccessibilityPalette.hp_mid()" in body,
		"mid-HP tier must recolor via AccessibilityPalette.hp_mid()")
	assert_true("AccessibilityPalette.hp_high()" in body,
		"default tier must fall back to AccessibilityPalette.hp_high() for parity with the enemy panel")
	assert_true("add_theme_color_override(\"font_color\"" in body,
		"party HP label must apply font_color override — the whole point of the fix")


func test_party_panel_font_sizes_bumped_for_readability() -> void:
	# Bump the RHS party status box past the 10-13 defaults the artist called
	# "hard to read". Values pin the intent so a stealth revert would fail.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_true("name_label.add_theme_font_size_override(\"font_size\", TextScale.scaled(15))" in src,
		"party name font must be TextScale.scaled(15) (was 13)")
	assert_true("hp_label.add_theme_font_size_override(\"font_size\", TextScale.scaled(15))" in src,
		"party HP font must be TextScale.scaled(15) (was 12) — the readability complaint")
	assert_true("mp_label.add_theme_font_size_override(\"font_size\", TextScale.scaled(13))" in src,
		"party MP font must be TextScale.scaled(13) (was 11)")
	assert_true("ap_label.add_theme_font_size_override(\"normal_font_size\", TextScale.scaled(15))" in src,
		"AP normal font must be TextScale.scaled(15) (was 13)")
	assert_true("stat_label.add_theme_font_size_override(\"normal_font_size\", TextScale.scaled(12))" in src,
		"stat font must be TextScale.scaled(12) (was 10)")
