extends GutTest

## ⛔ THE BACKLOG HEADER HAD A FIXED 28px BOX AND A SCALED FONT. At Text Size 150% and 200% the
## title's glyphs are 34px and 45px tall, and a Label does not clip by default — so "Already said"
## drew DOWN into the scroll container that starts at y=48 and printed through the newest backlog
## line. Nothing was hidden; the two simply overlapped.
##
## 🔑 The pairing is the reason it is worth fixing: the backlog exists to re-read a line you missed,
## and a player on 200% text is the one most likely to have missed it. Same family as the dialogue
## panel itself, one surface over — `_box_metrics` fixed that one in .685.
##
## The close prompt had the same shape: a fixed 24px box at a fixed offset put its bottom edge
## EXACTLY on the panel edge at 200%, with no margin for a font whose metrics differ by a pixel.

const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved: float = 1.0


func before_each() -> void:
	if GameState and "text_size_scale" in GameState:
		_saved = float(GameState.text_size_scale)


func after_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _saved


## The live panel at one Text Size: the title, the scroll container and the close hint.
func _parts(scale: float) -> Dictionary:
	GameState.text_size_scale = scale
	var dlg = load("res://src/cutscene/CutsceneDialogue.gd").new()
	add_child_autofree(dlg)
	for _i in 2:
		await get_tree().process_frame
	## Two lines so the backlog has rows to overlap.
	dlg._record_in_backlog("Theron", "The crystal is not a lock. It is a question nobody finished asking.")
	dlg._record_in_backlog("", "The well is deeper than it looks.")
	dlg.open_backlog()
	for _i in 2:
		await get_tree().process_frame
	var title: Label = null
	var hint: Label = null
	var scroll: ScrollContainer = dlg.get("_backlog_scroll")
	for n in _walk(dlg):
		if n is Label:
			if str((n as Label).text) == "Already said":
				title = n
			elif str((n as Label).text).contains("Close"):
				hint = n
	return {"title": title, "hint": hint, "scroll": scroll}


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for kid in n.get_children():
		out.append_array(_walk(kid))
	return out


func test_the_header_box_holds_its_own_glyphs() -> void:
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "CONTROL: a theme font is needed to measure the header")
	var short: Array = []
	for s in PRESETS:
		var p: Dictionary = await _parts(s)
		var title: Label = p["title"]
		assert_not_null(title, "CONTROL: the backlog must build its header at %.0f%%" % [s * 100.0])
		var need: float = float(font.get_height(TextScale.scaled(18)))
		if title.size.y + 0.5 < need:
			short.append("%.0f%% (box %.0f, glyphs %.0f)" % [s * 100.0, title.size.y, need])
	assert_eq(short, [], "the backlog header's box is shorter than its own text, so it prints into the rows below: %s" % [short])


func test_the_rows_start_below_the_header() -> void:
	var overlap: Array = []
	for s in PRESETS:
		var p: Dictionary = await _parts(s)
		var title: Label = p["title"]
		var scroll: ScrollContainer = p["scroll"]
		if title == null or scroll == null:
			continue
		if scroll.position.y + 0.5 < title.position.y + title.size.y:
			overlap.append("%.0f%% (rows at %.0f, header ends %.0f)" % [
				s * 100.0, scroll.position.y, title.position.y + title.size.y])
	assert_eq(overlap, [], "the backlog rows start inside the header: %s" % [overlap])


func test_the_close_prompt_stays_inside_the_panel() -> void:
	var out: Array = []
	for s in PRESETS:
		var p: Dictionary = await _parts(s)
		var hint: Label = p["hint"]
		if hint == null:
			continue
		var bottom: float = hint.position.y + hint.size.y
		if bottom > 460.0 - 2.0:
			out.append("%.0f%% (bottom %.0f of 460)" % [s * 100.0, bottom])
	assert_eq(out, [], "the close prompt reaches the panel edge, so the player can lose it: %s" % [out])


## The default must not move.
func test_the_default_geometry_is_unchanged() -> void:
	var p: Dictionary = await _parts(1.0)
	var title: Label = p["title"]
	var scroll: ScrollContainer = p["scroll"]
	assert_not_null(title, "CONTROL: the header must exist at 100%")
	assert_almost_eq(title.size.y, 28.0, 0.5, "at 100% the header keeps its authored 28px box")
	assert_almost_eq(scroll.position.y, 48.0, 0.5, "at 100% the rows keep their authored y=48")
