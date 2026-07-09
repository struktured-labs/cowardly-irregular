extends GutTest

## Accessibility fix (2026-07-09): the Settings text-size scale reached menus,
## dialogue, and the results screen — but the battle HUD (HP/MP/AP labels,
## Win98 command menu) hardcoded every font size, so the setting silently
## half-worked exactly where small text hurts most. All 16 sites now route
## through TextScale.scaled(); this ratchet keeps new ones honest.

## Round 2 (same tick family): the five highest-traffic menus joined the sweep.
const FILES := ["res://src/battle/BattleUIManager.gd", "res://src/ui/Win98Menu.gd",
	"res://src/ui/OverworldMenu.gd", "res://src/ui/ItemsMenu.gd",
	"res://src/ui/SettingsMenu.gd", "res://src/ui/FormationsMenu.gd",
	"res://src/exploration/ShopScene.gd",
	"res://src/ui/RecordsMenu.gd"]


func test_no_bare_int_font_overrides_in_battle_hud() -> void:
	var rx := RegEx.new()
	rx.compile("add_theme_font_size_override\\(\"[a-z_]+\",\\s*\\d+\\)")
	for path in FILES:
		var src := FileAccess.get_file_as_string(path)
		var hits := rx.search_all(src)
		assert_eq(hits.size(), 0,
			"%s has %d bare-int font override(s) — route them through TextScale.scaled() so the accessibility setting reaches the battle HUD" % [path, hits.size()])
		assert_gt(src.count("TextScale.scaled("), 0, "%s actually uses TextScale" % path)


func test_text_scale_actually_scales() -> void:
	var prev: float = GameState.text_size_scale if "text_size_scale" in GameState else 1.0
	GameState.text_size_scale = 1.5
	assert_eq(TextScale.scaled(12), 18, "1.5x scale: 12 -> 18")
	GameState.text_size_scale = 1.0
	assert_eq(TextScale.scaled(12), 12, "1.0x is identity")
	GameState.text_size_scale = prev
