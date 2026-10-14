extends GutTest

## Text Size, 2026-10-14: every text node in RuleComposerOverlay.tscn is themed with no font_size
## override, so the Rule Composer ignored the Text Size setting entirely. Scaling the fonts is only
## half of it -- the preview box was a fixed 200px and the panel a fixed 70% of the screen, so grown
## text pushes the button row out of the panel. Measured on the built node at every preset.

const OverlayScene := preload("res://src/ui/autobattle/RuleComposerOverlay.tscn")
## DERIVED, not copied. @cowir-controller's census found this file among 17 carrying an UNCHECKED
## copy of the ladder — @cowir-adhoc's test is the right one: "has a copy" is not the defect, "has a
## copy and nothing checks it" is. Reached through the class_name, so a rename is a PARSE error
## (EC=3, nothing ran) rather than an abort, and with NO fallback default: a fallback would pass
## every arm below against a ladder no player can select.
const PRESETS: Array = SettingsMenu.TEXT_SIZE_PRESETS

## The paths the overlay scales. PreviewLabel is built on demand, so it only exists in a populated overlay.
const TEXT_PATHS: Array = [
	"Panel/VBox/Title",
	"Panel/VBox/PromptField",
	"Panel/VBox/StatusLabel",
	"Panel/VBox/ButtonsHBox/ComposeButton",
	"Panel/VBox/ButtonsHBox/RegenButton",
	"Panel/VBox/ButtonsHBox/ConfirmButton",
	"Panel/VBox/ButtonsHBox/CancelButton",
	"Panel/VBox/ReplaceToggle",
	"Panel/VBox/PreviewPanel/PreviewLabel",
]

const ROWS: Array = [
	"Panel/VBox/Title",
	"Panel/VBox/PromptField",
	"Panel/VBox/StatusLabel",
	"Panel/VBox/PreviewPanel",
	"Panel/VBox/ButtonsHBox",
	"Panel/VBox/ReplaceToggle",
]

## A real composition: the description the composer writes, three rules, and the notes it adds when it
## had to edit them. The notes are the long half and the reason the preview box overflows.
const COMPOSITION: Dictionary = {
	"name": "Cautious Healer",
	"description": "Heals whoever is lowest, cures status before it stacks, and attacks only when the party is safe.",
	"rules": [{"conditions": []}, {"conditions": []}, {"conditions": []}],
	"notes": [
		"added an MP guard to rule 1 so Cure cannot fizzle at 0 MP",
		"moved the attack rule below the heal rules, or it would always win first",
		"dropped a target the grid cannot express (nearest wounded ally)",
	],
}

var _orig_scale: float = 1.0
var _llm_was_enabled: bool = true


func before_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		_orig_scale = float(gs.text_size_scale)
	_llm_was_enabled = LLMService.llm_enabled


func after_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = _orig_scale
	LLMService.llm_enabled = _llm_was_enabled


func _set_scale(scale: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale


func _settle() -> void:
	for _i in 4:
		await get_tree().process_frame


## Builds a fresh overlay AT the live scale and populates its preview. Every derived value reads
## TextScale at call time, so an overlay built at another scale answers for that one, not this.
func _open_populated(scale: float):
	_set_scale(scale)
	var o = OverlayScene.instantiate()
	add_child_autofree(o)
	await _settle()
	o.open("autobattle", "fighter", [])
	o._show_preview(COMPOSITION)
	await _settle()
	return o


## The same overlay freshly opened with no backend: the long no-LLM notice is the status line's worst case.
func _open_with_notice(scale: float):
	LLMService.llm_enabled = false
	_set_scale(scale)
	var o = OverlayScene.instantiate()
	add_child_autofree(o)
	await _settle()
	o.open("autobattle", "fighter", [])
	await _settle()
	return o


func _font_px(o, path: String) -> int:
	var n := o.get_node_or_null(path) as Control
	if n == null:
		return 0
	return n.get_theme_font_size("font_size")


# ---------------------------------------------------------------- the control


func test_the_fixture_really_fills_the_overlay() -> void:
	var o = await _open_populated(1.0)
	var status: Label = o.get_node("Panel/VBox/StatusLabel")
	var preview: Label = o.get_node_or_null("Panel/VBox/PreviewPanel/PreviewLabel")
	assert_not_null(preview, "CONTROL: the preview label was never built, so every preview arm below measures nothing")
	assert_string_contains(status.text, "rule(s)", "CONTROL: the status line must carry the composed count")
	assert_gt(preview.get_line_count(), 4, "CONTROL: the preview must hold the description plus the notes (%d lines)" % preview.get_line_count())
	assert_true((o.get_node("Panel/VBox/PreviewPanel") as Control).visible, "CONTROL: the preview panel is hidden, so its geometry is not what a player sees")
	for p in ["Panel/VBox/ButtonsHBox/ComposeButton", "Panel/VBox/ButtonsHBox/RegenButton",
			"Panel/VBox/ButtonsHBox/ConfirmButton", "Panel/VBox/ButtonsHBox/CancelButton"]:
		assert_ne(str((o.get_node(p) as Button).text), "", "CONTROL: %s has no caption to fit" % p)

	var notice_o = await _open_with_notice(1.0)
	var notice: Label = notice_o.get_node("Panel/VBox/StatusLabel")
	assert_string_contains(notice.text, "No LLM backend reachable", "CONTROL: the no-backend notice is the status line's worst case and it is absent")


# ---------------------------------------------------------------- the font grew


func test_every_text_node_grows_with_the_text_size() -> void:
	var seen: Dictionary = {}
	for scale in PRESETS:
		var o = await _open_populated(scale)
		var row: Dictionary = {}
		for p in TEXT_PATHS:
			row[p] = _font_px(o, p)
		seen[scale] = row
		gut.p("scale %.2f  %s" % [scale, str(row)])
	for p in TEXT_PATHS:
		assert_gt(int(seen[1.0][p]), 0, "%s was never found, so its font is not measured" % p)
		assert_gt(int(seen[2.0][p]), int(seen[1.0][p]),
			"%s does not grow with Text Size (200%% gives %d, 100%% gives %d)" % [p, int(seen[2.0][p]), int(seen[1.0][p])])
		assert_lt(int(seen[0.8][p]), int(seen[1.0][p]),
			"%s does not shrink with Text Size (80%% gives %d, 100%% gives %d)" % [p, int(seen[0.8][p]), int(seen[1.0][p])])
		var prev: int = 0
		for scale in PRESETS:
			var px: int = int(seen[scale][p])
			assert_gte(px, prev, "%s went backwards up the ladder at %.2f (%d after %d)" % [p, scale, px, prev])
			prev = px


## The frame is exactly the shipped one at 100% and below, and only ever GROWS above it. I dropped the
## widening once, on a measurement that read the preview BOX (which fits trivially) instead of the
## text inside it -- the box is not the node that overflows, so the arm had no teeth and the fix lost
## its load-bearing half. One-directional in both halves: 100% is pinned, larger may only gain room.
func test_the_modal_grows_only_above_the_shipped_frame() -> void:
	# DERIVED sub-unity set, not a hand-written one. @cowir-music's finding: a file can derive its
	# full sweep and still hold a literal partial ladder for its "unchanged at 100%" arm -- and that
	# literal carries no [0.8, 1.0, 1.25] triple, so a census keyed on the full ladder cannot see it.
	# It is the arm that decides whether a NEW sub-unity preset is ever checked at all.
	var at_or_below: Array = PRESETS.filter(func(p): return float(p) <= 1.0)
	assert_false(at_or_below.is_empty(), "no preset at or below 100% — this arm would assert nothing")
	for scale in at_or_below:
		var small = await _open_populated(scale)
		var sp := small.get_node("Panel") as Control
		for pair in [["anchor_left", 0.15], ["anchor_top", 0.15], ["anchor_right", 0.85], ["anchor_bottom", 0.85]]:
			assert_almost_eq(float(sp.get(str(pair[0]))), float(pair[1]), 0.001,
				"at %.2fx the modal's %s moved to %.3f; at and below 100%% the frame is the shipped one" % [scale, str(pair[0]), float(sp.get(str(pair[0])))])
	var prev_h: float = 0.0
	for scale in PRESETS:
		var o = await _open_populated(scale)
		var panel := o.get_node("Panel") as Control
		assert_lte(panel.anchor_left, 0.1501, "at %.2fx the modal is narrower than the shipped frame" % scale)
		assert_gte(panel.anchor_right, 0.8499, "at %.2fx the modal is narrower than the shipped frame" % scale)
		assert_gte(panel.get_global_rect().size.y, prev_h - 0.5,
			"at %.2fx the modal got SHORTER (%.0f after %.0f) while its text got bigger" % [scale, panel.get_global_rect().size.y, prev_h])
		prev_h = panel.get_global_rect().size.y


func test_the_shipped_look_is_unchanged_at_100_percent() -> void:
	var o = await _open_populated(1.0)
	for p in TEXT_PATHS:
		var n := o.get_node_or_null(p) as Control
		assert_not_null(n, "%s is missing" % p)
		assert_eq(_font_px(o, p), n.get_theme_default_font_size(),
			"%s draws at %d at 100%%, where the theme default it shipped with is %d" % [p, _font_px(o, p), n.get_theme_default_font_size()])


# ---------------------------------------------------------------- the text fits


## Containment is checked against the SCREEN as well as the panel: a PanelContainer grows past its
## own anchors when its child's minimum outgrows them, and then "inside the panel" is satisfied by a
## panel that grew with the rows. The compounding mutation reaches 3049px wide and reds here.
func test_every_row_fits_the_panel_and_the_screen() -> void:
	var screen: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for scale in PRESETS:
		var o = await _open_populated(scale)
		var panel_rect: Rect2 = (o.get_node("Panel") as Control).get_global_rect()
		gut.p("scale %.2f  panel %s  screen %s" % [scale, str(panel_rect), str(screen.size)])
		assert_lte(panel_rect.end.x, screen.end.x + 0.5,
			"at %.2fx the modal itself is %.0fpx wide and the screen is %.0f" % [scale, panel_rect.size.x, screen.size.x])
		assert_lte(panel_rect.end.y, screen.end.y + 0.5,
			"at %.2fx the modal itself is %.0fpx tall and the screen is %.0f" % [scale, panel_rect.size.y, screen.size.y])
		var prev_bottom: float = -1.0
		for p in ROWS:
			var n := o.get_node(p) as Control
			if not n.visible:
				continue
			var r: Rect2 = n.get_global_rect()
			gut.p("    %-28s %s" % [p.get_file(), str(r)])
			assert_lte(r.end.y, panel_rect.end.y + 0.5,
				"at %.2fx %s ends at y=%.0f, past the panel's own bottom at %.0f" % [scale, p.get_file(), r.end.y, panel_rect.end.y])
			assert_lte(r.end.x, panel_rect.end.x + 0.5,
				"at %.2fx %s ends at x=%.0f, past the panel's own right edge at %.0f" % [scale, p.get_file(), r.end.x, panel_rect.end.x])
			assert_gte(r.position.y, prev_bottom - 0.5,
				"at %.2fx %s starts at y=%.0f, on top of the row above which ends at %.0f" % [scale, p.get_file(), r.position.y, prev_bottom])
			assert_lte(r.end.y, screen.end.y + 0.5,
				"at %.2fx %s ends at y=%.0f, off the bottom of a %.0fpx screen" % [scale, p.get_file(), r.end.y, screen.size.y])
			prev_bottom = r.end.y


func test_the_wrapping_lines_are_never_cut_off() -> void:
	for scale in PRESETS:
		var notice_o = await _open_with_notice(scale)
		var notice: Label = notice_o.get_node("Panel/VBox/StatusLabel")
		assert_gte(notice.get_visible_line_count(), notice.get_line_count(),
			"at %.2fx the no-LLM notice shows %d of its %d lines" % [scale, notice.get_visible_line_count(), notice.get_line_count()])
		var o = await _open_populated(scale)
		var status: Label = o.get_node("Panel/VBox/StatusLabel")
		assert_gte(status.get_visible_line_count(), status.get_line_count(),
			"at %.2fx the composed status shows %d of its %d lines" % [scale, status.get_visible_line_count(), status.get_line_count()])


func test_the_preview_never_draws_over_the_buttons() -> void:
	for scale in PRESETS:
		var o = await _open_populated(scale)
		var box := o.get_node("Panel/VBox/PreviewPanel") as Control
		var buttons := o.get_node("Panel/VBox/ButtonsHBox") as Control
		assert_true(box.clip_contents,
			"at %.2fx the preview box does not clip, so a long composition draws over the buttons" % scale)
		assert_lte(box.get_global_rect().end.y, buttons.get_global_rect().position.y + 0.5,
			"at %.2fx the preview box ends at y=%.0f and the buttons start at y=%.0f" % [scale, box.get_global_rect().end.y, buttons.get_global_rect().position.y])
		var preview: Label = o.get_node("Panel/VBox/PreviewPanel/PreviewLabel")
		gut.p("    %.2fx  box %.0f  label %.0f  lines %d" % [scale, box.size.y, preview.size.y, preview.get_line_count()])
		# The teeth, and the node that matters is the LABEL. A Label cannot shrink below its own
		# wrapped content, so the shipped 200px box left a 378px label hanging out of its parent at
		# 200% -- the box reported 200 and fitted, and the text was what drew over the buttons.
		assert_lte(preview.get_global_rect().end.y, box.get_global_rect().end.y + 0.5,
			"at %.2fx the composition's text is %.0fpx tall in a %.0fpx preview box" % [scale, preview.size.y, box.size.y])
		assert_gte(preview.get_visible_line_count(), preview.get_line_count(),
			"at %.2fx the preview shows %d of the composition's %d lines" % [scale, preview.get_visible_line_count(), preview.get_line_count()])


func test_each_button_caption_fits_its_own_box() -> void:
	for scale in PRESETS:
		var o = await _open_populated(scale)
		for p in ["Panel/VBox/ButtonsHBox/ComposeButton", "Panel/VBox/ButtonsHBox/RegenButton",
				"Panel/VBox/ButtonsHBox/ConfirmButton", "Panel/VBox/ButtonsHBox/CancelButton"]:
			var b := o.get_node(p) as Button
			var px: int = b.get_theme_font_size("font_size")
			var ink: float = ThemeDB.fallback_font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			assert_lte(ink, b.size.x,
				"at %.2fx '%s' needs %.0fpx of a %.0fpx button" % [scale, b.text, ink, b.size.x])
		var toggle := o.get_node("Panel/VBox/ReplaceToggle") as CheckBox
		var t_px: int = toggle.get_theme_font_size("font_size")
		var t_ink: float = ThemeDB.fallback_font.get_string_size(toggle.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t_px).x
		assert_lte(t_ink, toggle.size.x,
			"at %.2fx '%s' needs %.0fpx of a %.0fpx row" % [scale, toggle.text, t_ink, toggle.size.x])


# ---------------------------------------------------------------- the floor


## Every overlay member this file reaches, named here so a rename reds with the symbol instead of
## aborting an arm into a vacuous pass. _apply_text_scale and _text_scale have no other consumer.
func test_the_overlay_still_has_what_this_file_drives() -> void:
	var o = OverlayScene.instantiate()
	add_child_autofree(o)
	for m in ["open", "_show_preview", "_populate_preview", "_apply_text_scale", "_text_scale", "_apply_preview_room"]:
		assert_true(o.has_method(m), "RuleComposerOverlay has no %s(), so the arms that drive it pass without running" % m)
	for f in ["_status_label", "_preview_panel", "_compose_button"]:
		assert_true(f in o, "RuleComposerOverlay has no %s, so this file's fixture is stale" % f)
	# A const is not a property, so `in` cannot see it -- read the script's own constant map.
	var consts: Dictionary = o.get_script().get_script_constant_map()
	assert_true(consts.has("TEXT_NODE_PATHS"), "the overlay no longer declares which nodes it scales")
	var declared: Array = consts.get("TEXT_NODE_PATHS", [])
	assert_eq(declared.size(), TEXT_PATHS.size(),
		"the overlay scales %d nodes and this file measures %d" % [declared.size(), TEXT_PATHS.size()])
	for p in TEXT_PATHS:
		assert_true(declared.has(p), "the overlay does not scale %s, which this file measures" % p)

## The derivation's own floor: an EMPTY ladder makes every preset loop above iterate zero times and
## pass. Named rather than counted, and ASCENDING because the growth arms walk the ladder asserting
## each value is >= the one before — an unsorted ladder would change what they assert, not break it.
func test_the_preset_ladder_is_the_players_own() -> void:
	assert_false(PRESETS.is_empty(), "the ladder derived empty — every preset loop in this file would pass vacuously")
	assert_true(PRESETS.has(1.0), "the shipped default must be a rung the player can select: %s" % str(PRESETS))
	var prev: float = -1.0
	for scale in PRESETS:
		assert_gt(float(scale), prev, "the ladder is not ascending at %s: %s" % [str(scale), str(PRESETS)])
		prev = float(scale)
