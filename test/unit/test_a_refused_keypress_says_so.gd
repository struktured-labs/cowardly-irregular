extends GutTest

## ⛔ THE ON-SCREEN KEYBOARD REFUSED SILENTLY. At `max_length` (16) a keypress did nothing and made
## no sound; so did backspace on an empty field. The player presses, the field does not move, and
## nothing tells them why — while every ACCEPTED press has had a cue all along.
##
## 🔑 `menu_error` is the established answer elsewhere for exactly this: ItemsMenu on an empty list,
## JobMenu on an unavailable job, AutobattleGridEditor on a cell that cannot take a target. This
## keyboard is where every PC in the game gets its name.
##
## ⚠️ THE HOLD PATH IS DELIBERATELY LEFT SILENT and this file pins that, so nobody "completes" the
## fix into a repeating beep. `_backspace_step` returns on empty by design — its own comment says
## DELETING ONLY, so that a held cancel never reaches the cancel branch. A cue there would fire
## every tick of a hold against an empty field.

const KeyboardScript := preload("res://src/ui/VirtualKeyboard.gd")

## Grid positions in LAYOUTS: row 0 col 0 is "a"; row 3 col 7 is the backspace glyph.
const LETTER := Vector2i(0, 0)
const BACKSPACE := Vector2i(3, 7)


func _keyboard(text: String) -> Node:
	var kb: Node = KeyboardScript.new()
	add_child_autofree(kb)
	kb.visible = true
	kb.set("input_text", text)
	kb.set("char_set", 0)
	return kb


func _at(kb: Node, cell: Vector2i) -> void:
	kb.set("cursor_row", cell.x)
	kb.set("cursor_col", cell.y)


## ⛔ _sfx_cooldowns IS A SHARED AUTOLOAD MAP AND A FULL-SUITE RUN SHARES ONE PROCESS. Erasing keys
## to observe a cue would leave the dedupe table altered for every later file — the same shared-state
## shape the fleet spent today on. Snapshot in, restore out, and restore the WHOLE map rather than
## the keys this file happens to name, so a cue fired mid-test cannot survive either.
var _saved_cooldowns: Dictionary = {}


func before_each() -> void:
	_saved_cooldowns = SoundManager._sfx_cooldowns.duplicate(true)


func after_each() -> void:
	SoundManager._sfx_cooldowns.clear()
	for k in _saved_cooldowns:
		SoundManager._sfx_cooldowns[k] = _saved_cooldowns[k]


func _forget(keys: Array) -> void:
	for k in keys:
		SoundManager._sfx_cooldowns.erase(k)


func _cued(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


## ⛔ THE SEAM CONTROL. Every arm below reads _sfx_cooldowns to decide whether a cue fired. If
## play_ui does not record there, a cue that never fires is indistinguishable from one correctly
## withheld — and all four arms would pass for the wrong reason.
func test_the_cue_seam_records_a_play() -> void:
	_forget(["menu_error"])
	assert_false(_cued("menu_error"), "CONTROL: the key must start clear")
	SoundManager.play_ui("menu_error")
	assert_true(_cued("menu_error"),
		"play_ui does not record in _sfx_cooldowns — this file cannot observe a cue at all")


func test_a_key_at_the_limit_is_refused_out_loud() -> void:
	var full: String = "0123456789abcdef"   # exactly max_length (16)
	var kb := _keyboard(full)
	_at(kb, LETTER)
	_forget(["menu_error", "menu_select"])
	kb._press_key()
	assert_eq(str(kb.get("input_text")), full,
		"the field grew past max_length — the refusal itself is gone")
	assert_true(_cued("menu_error"),
		"a keypress at the limit changed nothing and said nothing; the player presses and the field "
		+ "just sits there")


## ANTI-OVERCORRECTION: a fix that cued an error unconditionally would pass the arm above and make
## every ordinary keystroke sound like a failure.
func test_a_key_under_the_limit_still_types() -> void:
	var kb := _keyboard("ab")
	_at(kb, LETTER)
	_forget(["menu_error", "menu_select"])
	kb._press_key()
	assert_eq(str(kb.get("input_text")), "aba", "an ordinary keystroke must still type")
	assert_true(_cued("menu_select"), "an accepted press must keep its own cue")
	assert_false(_cued("menu_error"), "an accepted press must not sound like a refusal")


func test_backspace_on_an_empty_field_is_refused_out_loud() -> void:
	var kb := _keyboard("")
	_at(kb, BACKSPACE)
	_forget(["menu_error", "menu_cancel"])
	kb._press_key()
	assert_eq(str(kb.get("input_text")), "", "nothing to delete")
	assert_true(_cued("menu_error"), "backspace on an empty field said nothing")


## ⛔ AND THE HOLD PATH MUST STAY SILENT — pinned so the fix is not "completed" into a beep per tick.
func test_the_held_backspace_stays_silent_on_empty() -> void:
	var kb := _keyboard("")
	_forget(["menu_error", "menu_cancel"])
	kb._backspace_step()
	assert_false(_cued("menu_error"),
		"_backspace_step is the HOLD path and runs every tick — a refusal cue here fires "
		+ "continuously while a player holds cancel against an empty field")
	assert_false(_cued("menu_cancel"), "nothing was deleted, so the delete cue must not fire either")
