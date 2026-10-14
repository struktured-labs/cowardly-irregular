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

## Apply the current scale to a node's font, from a base captured ONCE on the node itself.
## Lifted out of BattleScene so every persistent surface shares one implementation.
##
## Two measured reasons the base is recorded rather than re-read, both from 2026-10-14:
##   get_theme_font_size() returns the OVERRIDE once one is set, so re-reading COMPOUNDS -- a
##   32px label reached 128px after two extra applications.
##   a Label's content minimum lands on a DEFERRED pass, so a node's own metrics read in the same
##   frame are stale (cowir-autogrind, same day).
## So this is idempotent BY CONSTRUCTION, which is what makes it safe to call from a change signal.
static func apply(c: Control, key: StringName = &"font_size") -> void:
	if c == null or not is_instance_valid(c):
		return
	var meta_key: StringName = &"text_scale_base_" + key
	if not c.has_meta(meta_key):
		c.set_meta(meta_key, c.get_theme_font_size(key))
	var base: int = int(c.get_meta(meta_key))
	if base > 0:
		c.add_theme_font_size_override(key, scaled(base))


## Re-apply to a whole kept subtree. A persistent HUD connects a change signal to this; a surface
## built per open needs nothing, because construction already reads the live scale.
## ⚠️ FONTS ONLY. Re-scaling text is not re-scaling a LAYOUT: a surface whose boxes are derived
## from a literal still has to recompute its own geometry, which this cannot do for it.
static func apply_tree(root: Node, key: StringName = &"font_size") -> int:
	if root == null or not is_instance_valid(root):
		return 0
	var n: int = 0
	if root is Control and root.has_meta(&"text_scale_base_" + key):
		apply(root as Control, key)
		n += 1
	for child in root.get_children():
		n += apply_tree(child, key)
	return n
