extends GutTest

## A grind share code pasted in the console wrote AutogrindSystem and never this screen's own copy of the rules. The grid
## kept showing the old set, and closing the console (or starting a grind) wrote that old set back over the paste: it said
## "applied" and was undone silently. Found beside cowir-controller's paste-undo for the autobattle editor (27434).
## The console now adopts what it applied, and the set it replaced is one undo away, like a delete.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

const MINE := [{"enabled": true, "conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}], "actions": [{"type": "heal_party"}]}]
const PASTED := [
	{"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 40}], "actions": [{"type": "stop_grinding"}]},
	{"enabled": true, "conditions": [{"type": "party_mp_avg", "op": "<", "value": 20}], "actions": [{"type": "restore_mp"}]},
]

var _ag: Dictionary
var _ui: Node
var _code := ""


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	assert_true(AutogrindSystem.set_autogrind_rules(PASTED.duplicate(true)), "CONTROL: the code's rules are a valid set")
	_code = ScriptShareManager.encode_autogrind_share_code()
	assert_true(AutogrindSystem.set_autogrind_rules(MINE.duplicate(true)), "CONTROL: the player's rules are a valid set")
	_ui = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	await get_tree().process_frame
	_ui._load_rules()


func after_each() -> void:
	AutogrindState.restore(_ag)


func _types(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		out.append(str(((r as Dictionary).get("conditions", [{}]) as Array)[0].get("type", "")))
	return out


func test_the_grid_shows_what_was_pasted() -> void:
	assert_ne(_code, "", "CONTROL: a share code was made")
	assert_eq(_types(_ui.rules), ["party_hp_avg"], "CONTROL: the console starts on the player's own rules")
	_ui._apply_rules_share_code(_code)
	assert_eq(_types(AutogrindSystem.get_autogrind_rules()), ["battles_done", "party_mp_avg"], "CONTROL: the paste reached the system")
	assert_eq(_types(_ui.rules), ["battles_done", "party_mp_avg"], "the console's grid still showed the rules the paste replaced")


func test_closing_keeps_the_paste() -> void:
	_ui._apply_rules_share_code(_code)
	_ui._persist_rules_on_close()
	assert_eq(_types(AutogrindSystem.get_autogrind_rules()), ["battles_done", "party_mp_avg"],
		"closing the console wrote the old rules back over the paste")


func test_the_replaced_rules_are_one_undo_away() -> void:
	_ui._apply_rules_share_code(_code)
	assert_true(_ui._undo_is_live(), "a paste leaves its undo live")
	_ui._undo_delete()
	assert_eq(_types(_ui.rules), ["party_hp_avg"], "undo brings back the rules the paste replaced")
	_ui._persist_rules_on_close()
	assert_eq(_types(AutogrindSystem.get_autogrind_rules()), ["party_hp_avg"], "and closing keeps the undone state")
	assert_false(_ui._undo_is_live(), "the undo is one level and is spent")


func test_a_refused_code_changes_nothing_and_arms_no_undo() -> void:
	_ui._apply_rules_share_code("COWIR1:not-a-code")
	assert_eq(_types(_ui.rules), ["party_hp_avg"], "a refused paste leaves the grid alone")
	assert_false(_ui._undo_is_live(), "and has nothing to undo")


## The file import replaces the set the same way, so it goes through the same adoption.
func test_the_file_import_adopts_the_same_way() -> void:
	var src: String = load("res://src/ui/autogrind/AutogrindUI.gd").source_code
	var at := src.find("func _import_scripts(")
	assert_gt(at, -1, "CONTROL: the import route still exists")
	var end := src.find("\nfunc ", at + 10)
	assert_true(src.substr(at, end - at).contains("_adopt_applied_rules("), "the file import does not adopt what it applied")


## The success line now ends in the undo hint, so at Text Size 2.0 with a long file name it outgrows one line; the console_log wraps it.
func test_the_long_success_line_wraps_inside_the_log_at_text_size_two() -> void:
	var was: float = float(GameState.text_size_scale)
	GameState.text_size_scale = 2.0
	var ui: Node = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(ui)
	await get_tree().process_frame
	var console_log: RichTextLabel = ui._battle_log
	GameState.text_size_scale = was
	assert_not_null(console_log, "CONTROL: the console built its console_log")
	if console_log == null:
		return
	var line := "Imported autogrind rules from autogrind_rules_my_very_long_export_name_2026.json — %s to undo." % ui._undo_hint(" on an empty slot")
	var px: int = console_log.get_theme_font_size("normal_font_size")
	var one_line: float = console_log.get_theme_font("normal_font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_gt(one_line, console_log.size.x, "CONTROL: at 2.0 the line is wider than the console_log, or this arm proves nothing")
	assert_ne(console_log.autowrap_mode, TextServer.AUTOWRAP_OFF, "the console's console_log does not wrap")
	var before: int = console_log.get_line_count()
	ui._log_message(line)
	await get_tree().process_frame
	assert_gt(console_log.get_line_count() - before, 1, "the long success line ran past the console_log's edge instead of wrapping")
