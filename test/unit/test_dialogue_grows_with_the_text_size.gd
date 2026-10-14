extends GutTest

## ⛔ THE PANEL DID NOT GROW WITH ITS OWN FONTS. CutsceneDialogue has scaled speaker/body/hint
## through TextScale since tick 222, but `BOX_HEIGHT` is a const and `_text_label` is
## `clip_contents = true` — so the box held 150px at every Text Size while the line height doubled.
## Measured on the real panel at 1248px wide, against the 535 authored dialogue/narration steps:
##
##   scale  font  line_h  holds   CLIPPED
##   1.00    16    23.0   4        0 of 535     <- why nobody saw it
##   1.25    20    28.0   3       19
##   1.50    24    34.0   3       52
##   2.00    32    45.0   2      344            <- 64% of the game's dialogue
##
## 🔑 `BattleDialogue._dialogue_metrics` already carried the repair, and ITS comment cites this file
## as the model: "Text Size uses the same TextScale helper as cutscene dialogue. The panel grows
## with it so the line stays inside the box." The sibling was fixed; the surface it copied was not.
##
## This file judges the METRICS, not the spelling of a const, and its corpus is the authored pack —
## so new dialogue joins the population without editing the test.

const CUTSCENES := "res://data/cutscenes"
## ⛔ THE SWEEP IS THE PLAYER'S OWN LADDER, DERIVED — NOT A COPY OF IT. This file carried
## `const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]`, a duplicate of
## `SettingsMenu.TEXT_SIZE_PRESETS` with nothing checking the two still agreed. A copy goes stale
## the day a preset is added, and the arm written to catch "it broke at 125%" then never visits the
## new rung — silently, because a loop over a short list still passes.
##
## ⚠️ NO FALLBACK DEFAULT, deliberately: a RENAME must red rather than pass against a ladder
## nobody can select. If the const is gone, `s.TEXT_SIZE_PRESETS` raises and this file fails by
## name; if it is emptied, `_presets()` asserts below.
const SETTINGS_PATH := "res://src/ui/SettingsMenu.gd"

var _ladder: Array = []


## ⛔ THE FLOOR LIVES HERE, IN THE HELPER EVERY SWEEPING ARM CALLS, not only as a separate arm.
## A file-level floor arm makes the FILE red on an empty ladder but leaves each looping arm
## individually vacuous — it iterates zero times and passes green, so a reorder or a single-arm
## run reports success. Asserting on every call means every arm that sweeps reds by its own name.
func _presets() -> Array:
	if _ladder.is_empty():
		var s = load(SETTINGS_PATH)
		_ladder = (s.TEXT_SIZE_PRESETS as Array) if s != null else []
	assert_gt(_ladder.size(), 1, "the shipped Text Size ladder must have at least two rungs — an "
		+ "empty or stubbed ladder makes every preset loop iterate ZERO times and pass")
	return _ladder


## The sub-unity rungs. A SECOND literal lived in these files as `for scale in [0.8, 1.0]`, and it
## is invisible to any census keyed on the full ladder because it carries no 1.25 — yet it is the
## arm deciding whether a new sub-unity preset is ever checked at all. (@cowir-music, 2026-10-14.)
func _sub_unity() -> Array:
	var out: Array = []
	for p in _presets():
		if float(p) <= 1.0:
			out.append(p)
	return out


## The ladder's SHAPE, which several arms below silently depend on: ascending (a "100% is the
## baseline, larger must not shrink" arm reads differently under an unsorted ladder) and containing
## 1.0 (the default-unchanged arms have nothing to assert without it).
func test_the_sweep_is_the_players_own_ladder() -> void:
	var p: Array = _presets()
	assert_gt(p.size(), 1, "FLOOR: the derived ladder must be real")
	assert_true(1.0 in p, "the ladder must contain 1.0 — the default-unchanged arms sweep "
		+ "_sub_unity() and would examine nobody without it")
	var ascending := true
	for i in range(1, p.size()):
		if float(p[i]) <= float(p[i - 1]):
			ascending = false
	assert_true(ascending, "the ladder must be ASCENDING: arms here judge every larger size "
		+ "against 1.0 and an unsorted ladder changes what they assert rather than breaking them: %s" % [p])
	assert_gt(_sub_unity().size(), 0, "FLOOR: the sub-unity set must be non-empty, else the "
		+ "default-unchanged arm iterates zero times and passes")
	gut.p("  ladder %s · sub-unity %s (derived from SettingsMenu.TEXT_SIZE_PRESETS)" % [p, _sub_unity()])



var _saved: float = 1.0


func before_each() -> void:
	if GameState and "text_size_scale" in GameState:
		_saved = float(GameState.text_size_scale)


func after_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _saved


## Every authored dialogue/narration body, from the pack on disk.
func _lines() -> Array:
	var out: Array = []
	var d := DirAccess.open(CUTSCENES)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENES, f]))
		if not (parsed is Dictionary):
			continue
		for s in (parsed as Dictionary).get("steps", []):
			if s is Dictionary and str(s.get("type", "")) in ["dialogue", "narration"]:
				var t: String = str(s.get("text", "")).strip_edges()
				if t != "":
					out.append({"text": t, "file": str(f)})
	return out


## The live panel at one Text Size: its own box, text rect and hint, read after a layout pass.
func _panel(scale: float) -> Dictionary:
	GameState.text_size_scale = scale
	var dlg = load("res://src/cutscene/CutsceneDialogue.gd").new()
	add_child_autofree(dlg)
	for _i in 3:
		await get_tree().process_frame
	var box: Control = dlg.get("_dialogue_box")
	var lbl: RichTextLabel = dlg.get("_text_label")
	var hint = dlg.get("_advance_hint")
	return {"box": box, "lbl": lbl, "hint": hint}


func test_the_corpus_is_real() -> void:
	var rows: Array = _lines()
	assert_gt(rows.size(), 400, "CONTROL: only %d authored dialogue steps read — the arms below judge nothing without the pack" % rows.size())
	gut.p("  authored dialogue/narration steps: %d" % rows.size())


## THE ARM THE DEFECT FAILED: at every Text Size the player can pick, every authored line must fit
## the text rect the panel actually gives it.
func test_every_authored_line_fits_at_every_text_size() -> void:
	var rows: Array = _lines()
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "CONTROL: a theme font is needed to measure wrapping")
	for scale in _presets():
		var p: Dictionary = await _panel(scale)
		var lbl: RichTextLabel = p["lbl"]
		assert_not_null(lbl, "CONTROL: the panel must build a text label at scale %.2f" % scale)
		var px: int = TextScale.scaled(16)
		var line_h: float = maxf(1.0, float(font.get_height(px)))
		var holds: int = int(floor(lbl.size.y / line_h))
		var clipped: Array = []
		for r in rows:
			var need: int = int(ceil(font.get_multiline_string_size(
				str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, lbl.size.x, px).y / line_h))
			if need > holds:
				clipped.append("%s (needs %d, holds %d)" % [r["file"], need, holds])
		gut.p("  scale %.2f: font %d, line %.1f, rect %.0fx%.0f, holds %d — clipped %d of %d" % [
			scale, px, line_h, lbl.size.x, lbl.size.y, holds, clipped.size(), rows.size()])
		assert_eq(clipped.size(), 0,
			"at Text Size %.0f%% these authored lines are cut off by a panel that did not grow with its own fonts: %s" % [
				scale * 100.0, ", ".join(clipped.slice(0, 4))])


## The default must not move: 100% and 80% keep the authored 150px panel exactly.
func test_the_default_panel_is_unchanged() -> void:
	for scale in _sub_unity():
		var p: Dictionary = await _panel(scale)
		var box: Control = p["box"]
		assert_not_null(box, "CONTROL: the panel must build at scale %.2f" % scale)
		assert_almost_eq(box.size.y, 150.0, 0.5,
			"at %.0f%% the panel must stay the authored 150px — this fix must not move the default layout" % [scale * 100.0])


## And the hint stays inside the panel at every size, or the player loses the advance prompt.
func test_the_advance_hint_stays_inside_the_panel() -> void:
	var outside: Array = []
	for scale in _presets():
		var p: Dictionary = await _panel(scale)
		var box: Control = p["box"]
		var hint = p["hint"]
		if box == null or hint == null:
			continue
		if hint.position.y >= box.size.y:
			outside.append("%.0f%% (hint y %.0f, box %.0f)" % [scale * 100.0, hint.position.y, box.size.y])
	assert_eq(outside, [], "the advance hint fell outside the panel: %s" % [outside])
