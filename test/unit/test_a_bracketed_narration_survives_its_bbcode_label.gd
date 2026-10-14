extends GutTest

## PROBE, not yet a claim. `CutsceneDialogue._text_label` is a RichTextLabel with
## `bbcode_enabled = true` (`:735`), the authored text is assigned RAW (`_current_text = text` at
## `:1144`, no escaping anywhere in the file), and the typewriter assigns PREFIXES —
## `_text_label.text = _current_text.substr(0, _displayed_chars)` at `:1183`.
##
## Exactly ONE authored player-facing string carries a bracket token: `world6_orrery.json`'s
## narration, 110 chars wrapped ENTIRELY in `[ ... ]`. A prefix of that is an UNTERMINATED tag, so
## the interesting question is not the finished line but the reveal.
##
## Derived from the pack at run time, not pinned: new authored brackets must move this fixture.

const CUTSCENES := "res://data/cutscenes"
## ⛔ THE SECOND RENDERER, found by applying @cowir-sfx's own sibling-site error to this guard. I
## audited `CutsceneDialogue._text_label` and stopped — but `src/ui/BattleDialogue.gd:292` is a
## SECOND RichTextLabel with `bbcode_enabled = true`, fed authored prose by
## `show_boss_intro(speaker, intro_lines, ...)` from `data/boss_dialogue.json`, and it carries the
## SAME typewriter-prefix pattern at `:543`. 111 authored strings reach it; 0 carry a bracket today,
## so this half of the corpus is empty-but-watched rather than a finding.
const BOSS_DIALOGUE := "res://data/boss_dialogue.json"


## ⛔ THE CORPUS TOOK FOUR TRIES AND THE FIRST THREE WERE A GUESSED FIELD NAME. A dialogue or
## narration step carries its prose in THREE shapes, and reading only one of them answered "1
## bracketed string" when the real answer is ten:
##
##   {"type": "narration", "text": "..."}                         557 steps
##   {"type": "narration", "lines": ["...", "..."]}                145 steps   plain strings
##   {"type": "dialogue",  "lines": [{"speaker": .., "text": ..}]}             SPEAKER DICTS
##
## Every W4 machine-voice token — `[QUERY: ...]`, `[RESULT: ...]`, `[MEMORY_OVERFLOW]`,
## `[CALCULATING]`, `[OVERFLOW]` — lives in the THIRD shape, at `$.steps[N].lines[M].text`. A corpus
## keyed to `text` on the step itself sees none of them and reports a clean sweep.
func _bracketed_lines() -> Array:
	var out: Array = []
	var d := DirAccess.open(CUTSCENES)
	if d == null:
		return out
	for fname in d.get_files():
		if not fname.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENES, fname]))
		var stack: Array = [parsed]
		while not stack.is_empty():
			var node = stack.pop_back()
			if node is Dictionary:
				var dict: Dictionary = node
				if str(dict.get("type", "")) in ["dialogue", "narration", "say"]:
					for s in _prose_of(dict):
						if s.contains("[") and s.contains("]"):
							out.append([fname, s])
				for v in dict.values():
					stack.append(v)
			elif node is Array:
				for v in (node as Array):
					stack.append(v)
	out.append_array(_bracketed_boss_lines())
	return out


## The second renderer's corpus. `_`-prefixed keys are schema notes, not prose — two of them carry
## brackets describing the format, and counting those would make this arm pass on documentation.
func _bracketed_boss_lines() -> Array:
	var out: Array = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BOSS_DIALOGUE))
	if not (parsed is Dictionary):
		return out
	for boss_id in (parsed as Dictionary):
		if str(boss_id).begins_with("_"):
			continue
		var entry = (parsed as Dictionary)[boss_id]
		if not (entry is Dictionary):
			continue
		for key in (entry as Dictionary):
			if str(key).begins_with("_"):
				continue
			var val = (entry as Dictionary)[key]
			var vals: Array = val if val is Array else [val]
			for line in vals:
				if line is String and str(line).contains("[") and str(line).contains("]"):
					out.append(["boss_dialogue.json/%s/%s" % [str(boss_id), str(key)], str(line)])
	return out


## All three authored shapes of one step's prose.
func _prose_of(step: Dictionary) -> Array:
	var out: Array = []
	if step.get("text") is String:
		out.append(str(step["text"]))
	var lines = step.get("lines")
	if lines is Array:
		for row in (lines as Array):
			if row is String:
				out.append(str(row))
			elif row is Dictionary and (row as Dictionary).get("text") is String:
				out.append(str((row as Dictionary)["text"]))
	return out


func _shipped_label() -> RichTextLabel:
	## The SHIPPED configuration of CutsceneDialogue._text_label, for the two properties that
	## decide parsing. Nothing about the box affects whether a tag is swallowed.
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	add_child_autofree(rtl)
	return rtl


func test_the_corpus_is_real() -> void:
	var lines: Array = _bracketed_lines()
	gut.p("  authored player-facing strings with [tokens]: %d" % lines.size())
	for row in lines:
		gut.p("    %s: %d chars" % [str(row[0]), str(row[1]).length()])
	assert_gt(lines.size(), 0,
		"CONTROL: the probe found no bracketed authored line, so every verdict below is vacuous")
	## The boss half is legitimately EMPTY today, so it gets a reachability floor instead of a
	## content floor: the file must parse and carry prose, or an unreadable path would read as clean.
	var boss = JSON.parse_string(FileAccess.get_file_as_string(BOSS_DIALOGUE))
	assert_true(boss is Dictionary, "CONTROL: %s must parse or its renderer is unwatched" % BOSS_DIALOGUE)
	var boss_strings := 0
	if boss is Dictionary:
		for bid in (boss as Dictionary):
			var e = (boss as Dictionary)[bid]
			if str(bid).begins_with("_") or not (e is Dictionary):
				continue
			for k in (e as Dictionary):
				if str(k).begins_with("_"):
					continue
				var v = (e as Dictionary)[k]
				for ln in (v if v is Array else [v]):
					if ln is String:
						boss_strings += 1
	gut.p("  boss_dialogue.json: %d authored strings reach BattleDialogue, %d bracketed" % [
		boss_strings, _bracketed_boss_lines().size()])
	assert_gt(boss_strings, 50,
		"CONTROL: the second renderer's corpus must be populated, saw %d" % boss_strings)


func test_a_finished_bracketed_line_keeps_all_its_characters() -> void:
	var rtl := _shipped_label()
	var lost: Array = []
	for row in _bracketed_lines():
		rtl.text = str(row[1])
		var parsed: String = rtl.get_parsed_text()
		gut.p("  %s: authored %d -> parsed %d" % [str(row[0]), str(row[1]).length(), parsed.length()])
		if parsed.length() < str(row[1]).length():
			lost.append("%s: %d of %d chars reach the screen | parsed=%s" % [
				str(row[0]), parsed.length(), str(row[1]).length(), parsed])
	assert_eq(lost, [], "a bbcode label ate authored prose: %s" % [lost])


## THE REVEAL, which is the shape the finished line cannot show: the typewriter assigns prefixes,
## and a prefix of `[ ... ]` has an opening bracket with no closing one.
func test_the_typewriter_reveal_never_blanks_the_line() -> void:
	var rtl := _shipped_label()
	var worst: Array = []
	for row in _bracketed_lines():
		var s: String = str(row[1])
		var blanked := 0
		var first_blank := -1
		var deficit_max := 0
		for n in range(1, s.length() + 1):
			rtl.text = s.substr(0, n)
			var got: int = rtl.get_parsed_text().length()
			if got < n:
				blanked += 1
				deficit_max = maxi(deficit_max, n - got)
				if first_blank < 0:
					first_blank = n
		gut.p("  %s: %d of %d reveal steps lose characters (first at %d, worst deficit %d)" % [
			str(row[0]), blanked, s.length(), first_blank, deficit_max])
		if blanked > 0:
			worst.append("%s: %d reveal steps show fewer chars than revealed, worst %d missing" % [
				str(row[0]), blanked, deficit_max])
	assert_eq(worst, [],
		"the typewriter reveals characters the bbcode parser then hides: %s" % [worst])


## ⛔ WITHOUT THIS ARM EVERY GREEN ABOVE IS VACUOUS. "0 characters lost" is the same reading whether
## the parser preserved the prose or `get_parsed_text()` is simply not an instrument that can show a
## loss. This points the detector at the UNHEALTHY state and requires it to fire — the rule this repo
## learned from a label that fired on health.
##
## 🔑 It also states the live risk precisely. Today none of the ten authored tokens collides with a
## Godot tag name (`[QUERY: ...]`, `[RESULT: ...]`, `[MEMORY_OVERFLOW]`, `[CALCULATING]`,
## `[OVERFLOW]`), so the arms above pass on content, not on luck. The moment a writer reaches for
## `[b]`, `[i]`, `[s]`, `[color=...]`, `[wave]` or `[shake]` in that same machine-voice register —
## and `[s]` for a redaction is the one I would bet on — the prose is silently eaten and these arms
## are what notices.
func test_the_detector_can_see_a_real_tag_being_eaten() -> void:
	var rtl := _shipped_label()
	var cases: Array = [
		["[b]redacted[/b]", "bold"],
		["[s]struck[/s]", "strikethrough"],
		["[color=red]alarm[/color]", "color"],
	]
	var blind: Array = []
	for row in cases:
		var authored: String = str(row[0])
		rtl.text = authored
		var parsed: String = rtl.get_parsed_text()
		gut.p("  %-14s authored %2d -> parsed %2d  kept=%s" % [
			str(row[1]), authored.length(), parsed.length(), parsed])
		if parsed.length() >= authored.length():
			blind.append("%s: %d -> %d, the tag was NOT consumed" % [
				str(row[1]), authored.length(), parsed.length()])
	assert_eq(blind, [],
		"get_parsed_text() cannot see a real BBCode tag being consumed, so every 'nothing lost' verdict in this file is vacuous: %s" % [blind])
