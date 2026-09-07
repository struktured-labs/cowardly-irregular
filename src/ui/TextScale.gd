extends RefCounted
class_name TextScale

## Shared accessibility text-size helper — tick 223.
##
## Extracted from CutsceneDialogue (tick 222) so every menu can
## scale font sizes from the same source of truth (GameState
## .text_size_scale, set via SettingsMenu's Text Size option).
##
## Use anywhere a font_size literal appears:
##   label.add_theme_font_size_override("font_size", TextScale.scaled(14))
##
## Reads GameState.text_size_scale at call time so a SettingsMenu
## change applies on next menu rebuild.

# Tick 223: floor at 1 so a tiny base × 0 scale doesn't crash font rendering. Rounds to int because font sizes are integers. Autoload is looked up via the scene-tree root (Engine.has_singleton matches NATIVE singletons only — see test_no_engine_has_singleton.gd lint).
static func scaled(base: int) -> int:
	var scale: float = 1.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var gs = tree.root.get_node_or_null("GameState")
		if gs and "text_size_scale" in gs:
			scale = float(gs.text_size_scale)
	return max(1, int(round(float(base) * scale)))
