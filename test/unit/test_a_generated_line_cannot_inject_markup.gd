extends GutTest

## ⛔ MODEL TEXT REACHES A BBCODE PARSER, AND THE PARSER EATS IT. `CutsceneDialogue._text_label`
## (`:735`) and `BattleDialogue._text_label` (`:292`) set `bbcode_enabled = true` and assign the
## string RAW. An LLM line containing `[s]`, `[b]` or `[color=red]` loses those characters silently.
##
## 🔑 FOUND BY INVERTING MY OWN GUARD. `test_a_bracketed_narration_survives_its_bbcode_label` derives
## its corpus from `data/cutscenes` + `data/boss_dialogue.json` — the AUTHORED set. @cowir-sfx's 18051
## showed the shape: enumerating what can reach a surface is unbounded, and model output is exactly
## the member no data-derived corpus can list. This guard is therefore SINK-SIDE: it plants markup
## and asserts the characters survive, which covers generated text without enumerating it.
##
## ⚠️ SCOPE, STATED: this covers the NPC-dialogue path (`DynamicConversation._show_npc_line`, the one
## caller of `say()` on the generated side, reached from :303/:348/:399/:430). The BOSS TAUNT path
## (`BossDialogue:339` lifts `taunt_line` from the LLM detail) is NOT covered here and is declared
## in the arm below rather than left implicit.

const LLMServiceScript = preload("res://src/llm/LLMService.gd")

## The three tags most likely in prose: emphasis, a redaction, and a colour.
const PLANTS: Array = ["[s]struck[/s]", "[b]bold[/b]", "[color=red]alarm[/color]"]


func _bbcode_label() -> RichTextLabel:
	## The SHIPPED configuration of both renderers, for the one property that decides parsing.
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	add_child_autofree(rtl)
	return rtl


## ⛔ THE CONTROL FIRST: without this, every green below could mean "the parser never ate anything".
func test_an_unescaped_tag_really_is_eaten() -> void:
	var rtl := _bbcode_label()
	var survived: Array = []
	for plant in PLANTS:
		rtl.text = str(plant)
		var got: String = rtl.get_parsed_text()
		gut.p("  RAW  %-26s %2d chars -> %2d parsed  kept=%s" % [
			str(plant), str(plant).length(), got.length(), got])
		if got.length() >= str(plant).length():
			survived.append("%s was NOT eaten (%d -> %d)" % [str(plant), str(plant).length(), got.length()])
	assert_eq(survived, [],
		"CONTROL: the parser must demonstrably consume a tag, or every 'escaped text survives' verdict here is vacuous: %s" % [survived])


func test_an_escaped_generated_line_keeps_every_character() -> void:
	var rtl := _bbcode_label()
	var lost: Array = []
	for plant in PLANTS:
		var escaped: String = LLMServiceScript.escape_markup(str(plant))
		rtl.text = escaped
		var got: String = rtl.get_parsed_text()
		gut.p("  ESC  %-26s -> %-32s parsed %2d of %2d  kept=%s" % [
			str(plant), escaped, got.length(), str(plant).length(), got])
		if got != str(plant):
			lost.append("%s rendered as %s" % [str(plant), got])
	assert_eq(lost, [],
		"an escaped generated line must reach the screen character for character: %s" % [lost])


## cowir-main's ruling: "authored text is unchanged". The escape must be a NO-OP on prose with no
## brackets, and must not be reachable from the authored path at all.
func test_prose_without_brackets_is_untouched() -> void:
	for line in [
		"The cave is to the northwest.",
		"Filing the encounter under 'unscheduled'.",
		"Nothing here but the hum of a machine that forgot its job.",
	]:
		assert_eq(LLMServiceScript.escape_markup(line), line,
			"the escape must not alter prose that carries no bracket: %s" % line)


## ⛔ THE SCOPE ARM, so the uncovered path is a measured declaration rather than a silence. It asserts
## what IS wired, and NAMES what is not; if someone wires the boss path later this arm tells them to
## update it instead of leaving a stale comment.
func test_the_wired_path_escapes_and_the_unwired_one_is_declared() -> void:
	var dc: String = FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd")
	assert_ne(dc, "", "CONTROL: the conversation source must be readable")
	assert_true(dc.contains("LLMService.escape_markup(line)"),
		"the NPC generated path must escape at _show_npc_line, the one caller of say() on that side")
	## The boss taunt path, named by its line rather than described: still unescaped today.
	var bd: String = FileAccess.get_file_as_string("res://src/llm/BossDialogue.gd")
	assert_ne(bd, "", "CONTROL: the boss dialogue source must be readable")
	var boss_escaped: bool = bd.contains("escape_markup")
	gut.p("  boss taunt path escaped: %s  (declared uncovered as of this commit)" % str(boss_escaped))
	assert_false(boss_escaped,
		"boss taunts now escape too — good, but this arm's declaration is stale: cover it above and update this")
