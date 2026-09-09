extends GutTest

## Shift+R (Rename profile) was UNREACHABLE in both grid editors, and one of them advertised it.
##
## MEASURED: `battle_advance` binds KEY_R, and Godot matches an action even when EXTRA MODIFIERS
## are held — probed, not assumed: an InputEventKey with keycode R and shift_pressed=true returns
## true from is_action_pressed("battle_advance"). So in an elif chain the battle_advance branch
## consumed Shift+R before the rename branch below it could see it.
##
##   AutogrindGridEditor    _open_rename_profile had exactly ONE caller — the dead branch.
##                          The whole feature was unreachable. No legend claimed it.
##   AutobattleGridEditor   the earlier branch excludes echo, so rename fired only on a key
##                          REPEAT — and the legend promises "Sh+R:Rename".
##
## 🔑 A source-text guard cannot see this: KEY_R IS compared, the handler IS present, the legend's
## claim DOES resolve. Only branch ORDER decides it. My own legend ratchet passed this file.

const EDITORS := {
	"res://src/ui/autogrind/AutogrindGridEditor.gd": "battle_advance",
	"res://src/ui/autobattle/AutobattleGridEditor.gd": "battle_advance",
}


## The premise, measured rather than reasoned. If Godot ever stops matching actions under extra
## modifiers this whole file is about a bug that no longer exists, and it should say so loudly.
func test_an_action_still_matches_with_a_modifier_held() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_R
	e.pressed = true
	e.shift_pressed = true
	assert_true(e.is_action_pressed("battle_advance"),
		"PREMISE: Shift+R must still match battle_advance — the shadowing this file guards depends on it")
	var plain := InputEventKey.new()
	plain.keycode = KEY_R
	plain.pressed = true
	assert_true(plain.is_action_pressed("battle_advance"), "CONTROL: plain R matches too")
	var other := InputEventKey.new()
	other.keycode = KEY_J
	other.pressed = true
	assert_false(other.is_action_pressed("battle_advance"),
		"CONTROL: an unrelated key must NOT match, or the premise arm proves nothing")


## THE RATCHET: the specific branch must sit above the general one that would eat its key.
func test_shift_r_precedes_the_action_that_claims_r() -> void:
	for path in EDITORS:
		var src := FileAccess.get_file_as_string(path)
		var rename_at := src.find("event.keycode == KEY_R and event.shift_pressed")
		var action_at := src.find('is_action_pressed("%s")' % EDITORS[path])
		assert_gt(rename_at, -1, "%s must still bind Shift+R" % path)
		assert_gt(action_at, -1, "CONTROL: %s must still bind the action that claims R" % path)
		assert_lt(rename_at, action_at,
			"%s: Shift+R must be handled BEFORE %s, which claims R and matches with modifiers held" % [path, EDITORS[path]])


## Rename must be reachable at all. In the autogrind editor the dead branch was its ONLY caller,
## so the feature existed and could not be run.
func test_rename_has_a_live_route_in_every_editor() -> void:
	for path in EDITORS:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains("func _open_rename_profile"), "%s must define rename" % path)
		var re := RegEx.new()
		re.compile("_open_rename_profile\\(\\)")
		assert_gt(re.search_all(src).size(), 0,
			"%s must CALL rename from somewhere, not merely define it" % path)


## The advertised claim must be honest: the editor that prints Sh+R must be the one where it works.
func test_the_legend_promise_is_now_true() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")
	assert_true(src.contains("Sh+R:Rename"), "this editor advertises Sh+R")
	var rename_at := src.find("event.keycode == KEY_R and event.shift_pressed")
	var action_at := src.find('is_action_pressed("battle_advance")')
	assert_lt(rename_at, action_at,
		"and a legend claim that only fires on a key REPEAT is not a working control")
