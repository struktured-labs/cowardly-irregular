extends GutTest

## cowir-cutscenes 2026-11-28: the title cards grew taller with Text Size but nothing judged WIDTH, so a 27-char boss name ran off both edges at 200%.

const TEXT_SIZE_PRESETS := [0.8, 1.0, 1.25, 1.5, 2.0]
const DIR := "res://data/cutscenes"


class CardDirector extends CutsceneDirector:
	var held: Array = []
	func _sleep(_duration: float, _on_tick: Callable = Callable()) -> void:
		var labels: Array = []
		for c in get_children():
			if c is Label and not c.is_queued_for_deletion():
				labels.append({"text": c.text, "y": c.position.y, "h": maxf(c.size.y, c.get_combined_minimum_size().y), "w": c.get_combined_minimum_size().x})
		for c in get_children():
			if c is Control and not (c is Label):
				for g in c.get_children():
					if g is Label:
						labels.append({"text": g.text, "y": g.position.y, "h": maxf(g.size.y, g.get_combined_minimum_size().y), "w": g.get_combined_minimum_size().x})
		if not labels.is_empty():
			held.append(labels)
	func _await_tween_hold(_tween: Tween) -> void:
		pass


var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _walk(node, kind: String, out: Array) -> void:
	if node is Dictionary:
		if str(node.get("type", "")) == kind:
			out.append(node)
		for v in node.values():
			_walk(v, kind, out)
	elif node is Array:
		for v in node:
			_walk(v, kind, out)


func _steps(kind: String) -> Array:
	var out: Array = []
	var seen := {}
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			var found: Array = []
			_walk(JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [DIR, f])), kind, found)
			for s in found:
				var key := JSON.stringify(s)
				if not seen.has(key):
					seen[key] = true
					out.append(s)
	return out


## Builds one card per step at one Text Size and returns each card's labels as they stand at the hold.
func _held_cards(kind: String, steps: Array, scale: float) -> Array:
	GameState.text_size_scale = scale
	var d := CardDirector.new()
	add_child_autofree(d)
	var cards: Array = []
	for s in steps:
		d.held.clear()
		var before: Array = d.get_children()
		if kind == "boss_intro":
			await d._step_boss_intro(s)
		else:
			await d._step_chapter_title(s)
		cards.append(d.held.back() if not d.held.is_empty() else [])
		for c in d.get_children():
			if not before.has(c):
				c.free()
	return cards


func _judge(kind: String) -> void:
	var steps := _steps(kind)
	assert_gt(steps.size(), 20, "CONTROL: the corpus holds the authored %s steps, got %d" % [kind, steps.size()])
	var vw: float = get_viewport().get_visible_rect().size.x
	assert_gt(vw, 1000.0, "CONTROL: a real viewport width, got %.0f" % vw)
	var safe: float = vw - 2.0 * CutsceneDirector.CARD_SIDE_MARGIN
	var bad: Array = []
	var widest := {"w": 0.0, "text": ""}
	for scale in TEXT_SIZE_PRESETS:
		var cards: Array = await _held_cards(kind, steps, scale)
		for i in cards.size():
			var labels: Array = cards[i]
			if labels.is_empty():
				bad.append("%s %d at %.0f%%: no card reached its hold" % [kind, i, scale * 100.0])
				continue
			for l in labels:
				if float(l["w"]) > widest["w"]:
					widest = {"w": float(l["w"]), "text": "%s @ %.0f%%" % [str(l["text"]).replace("\n", " / "), scale * 100.0]}
				if float(l["w"]) > safe:
					bad.append("%.0f%%: '%s' is %.0f px on a %.0f px screen" % [scale * 100.0, str(l["text"]).replace("\n", " / "), float(l["w"]), vw])
			for k in range(1, labels.size()):
				var top: Dictionary = labels[k - 1]
				if float(top["y"]) + float(top["h"]) > float(labels[k]["y"]) + 0.5:
					bad.append("%.0f%%: '%s' reaches into '%s' below it" % [scale * 100.0, str(top["text"]).replace("\n", " / "), labels[k]["text"]])
	gut.p("[CARD] %s widest line: %.0f px, %s" % [kind, widest["w"], widest["text"]])
	assert_eq(bad, [], "every %s line fits the screen and clears the line below it, at every Text Size" % kind)


func test_every_boss_card_fits_the_screen() -> void:
	await _judge("boss_intro")


func test_every_chapter_card_fits_the_screen() -> void:
	await _judge("chapter_title")


func test_some_boss_name_needs_the_break_at_200() -> void:
	## Without this the boss arm could be green because no name is long enough, which is no evidence about the break.
	var font: Font = UiFont.display()
	assert_not_null(font, "CONTROL: the display face is installed")
	GameState.text_size_scale = 2.0
	var px := TextScale.scaled(36)
	var safe: float = get_viewport().get_visible_rect().size.x - 2.0 * CutsceneDirector.CARD_SIDE_MARGIN
	var over: Array = []
	for s in _steps("boss_intro"):
		if font.get_string_size(str(s.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > safe:
			over.append(str(s.get("name", "")))
	assert_gt(over.size(), 0, "at least one authored boss name is wider than the screen at 200%, so the card's break is exercised")
	gut.p("[CARD] names that need the break at 200%%: %s" % str(over))


func test_at_100_no_name_is_broken() -> void:
	GameState.text_size_scale = 1.0
	var safe: float = 1280.0 - 2.0 * CutsceneDirector.CARD_SIDE_MARGIN
	var broken: Array = []
	for s in _steps("boss_intro"):
		var n := str(s.get("name", ""))
		if CutsceneDirector.card_lines(n, TextScale.scaled(36), safe) != n:
			broken.append(n)
	assert_eq(broken, [], "at 100% every authored boss name stays on one line, as it always has")
