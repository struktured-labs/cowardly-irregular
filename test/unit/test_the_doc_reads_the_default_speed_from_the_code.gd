extends GutTest

## CLAUDE.md said "engine 0.25 = "1x" = the default" for a week after struktured made 1.5x the default
## (47b98083f, 2026-10-30), and on 2026-11-05 a lane sized a reaction-window table from that line: every
## default-speed figure in it was wrong. The line now names the const instead of a rung.
##
## ⛔ PINS THE DERIVATION, NOT THE RUNG. Asserting "1.5x" here would red on a correct change to the default
## and pass a doc that names the wrong const; asserting that the line points at the const and claims no
## literal default is what stays true.

const CLAUDE_MD := "res://CLAUDE.md"


func _speed_line() -> String:
	var doc := FileAccess.get_file_as_string(CLAUDE_MD)
	assert_gt(doc.length(), 1000, "PRECONDITION: CLAUDE.md must be readable")
	for line in doc.split("\n"):
		if line.contains("**Battle speed scale"):
			return line
	return ""


func test_the_speed_line_names_the_default_const() -> void:
	var line := _speed_line()
	assert_ne(line, "", "the Project Status battle-speed line must exist")
	assert_string_contains(line, "DEFAULT_BATTLE_SPEED_INDEX", "the default must be read from the const it names")
	var bs: Script = load("res://src/battle/BattleScene.gd")
	assert_true(bs.get_script_constant_map().has("DEFAULT_BATTLE_SPEED_INDEX"),
		"CONTROL: the const the doc names must exist in BattleScene")


func test_the_speed_line_claims_no_literal_default() -> void:
	var line := _speed_line()
	for claim in ['"1x" = the default', '"1.5x" = the default', "= the default ("]:
		assert_false(line.contains(claim), "the line must not state a rung as THE default: found %s" % claim)
