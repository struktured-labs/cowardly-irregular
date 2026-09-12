extends GutTest

## Thirteen menu-footer strings named a pad letter and NO keyboard key — eleven of them offering a
## mouse click instead, in a game whose CLAUDE.md opens "designed for SNES-style gamepad. NO
## MOUSE/CLICKING required" and whose first design principle is "everything works on gamepad".
## "A/Click: Use" tells a keyboard player to reach for the mouse; "B" is right on Nintendo only.
##
## ⛔ AND THE WORST ONE WAS NOT A CAPTION. EquipmentMenu's "X: Unequip" meant the KEYBOARD X key —
## its only call site was `event.keycode == KEY_X` — in a footer where A and B are pad buttons. So a
## pad player read X, pressed their X face button, and nothing happened: UNEQUIP HAD NO PAD ROUTE AT
## ALL. The caption was not merely misleading, it named the one route that player did not have.
##
## The footers now derive through hint_for_action, which returns the pad glyph when a pad is
## connected and the KEY when one is not — so whoever is playing is told something they can press.

const UI_ROOT := "res://src/ui"
const EQUIPMENT := "res://src/ui/EquipmentMenu.gd"

## Keyboard vocabulary a footer may name. Deliberately small: these are the keys menus actually bind.
const KEY_WORDS := ["Enter", "Esc", "Escape", "Space", "Tab", "Z", "X", "Del", "Backspace"]

var _scanned: int = 0


func _ui_files(root: String, out: Array) -> void:
	var d := DirAccess.open(root)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := root + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_ui_files(path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = d.get_next()
	d.list_dir_end()


func _strip_comment(line: String) -> String:
	var esc := false
	var quote := ""
	for i in range(line.length()):
		var c := line[i]
		if esc:
			esc = false
			continue
		if c == "\\":
			esc = true
		elif quote != "":
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


## A footer is a string ASSIGNED to a visible label. Comments are stripped first — this file's own
## header names "A/Click: Use" and must not red itself.
func _footer_strings() -> Array:
	var files: Array = []
	_ui_files(UI_ROOT, files)
	assert_gt(files.size(), 30, "PRECONDITION: the walk must reach src/ui — a short list scans nothing")
	var out: Array = []
	_scanned = 0
	var re := RegEx.create_from_string("\"([^\"]{12,})\"")
	for path in files:
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			var code := _strip_comment(raw)
			if not (code.contains(".text") or code.contains("footer_text")):
				continue
			if not code.contains("="):
				continue
			for m in re.search_all(code):
				_scanned += 1
				out.append([path, m.get_string(1)])
	return out


## THE CLASS. A footer naming a bare face letter must also name a key, or it is addressed to
## somebody who is not holding what it describes.
func test_no_footer_names_a_pad_letter_without_a_key() -> void:
	var offenders: Array[String] = []
	for entry in _footer_strings():
		var text: String = entry[1]
		var frozen := RegEx.create_from_string("(^|[\\s\\[(])([AB])\\s*[/:]").search(text) != null
		if not frozen:
			continue
		var has_key := false
		for w in KEY_WORDS:
			if RegEx.create_from_string("(^|[\\s/\\[(])%s($|[\\s/\\]):])" % w).search(text) != null:
				has_key = true
				break
		if not has_key:
			offenders.append("%s :: %s" % [str(entry[0]).get_file(), text])
	gut.p("footer corpus: %d strings scanned from src/ui | key vocabulary: %s" % [_scanned, str(KEY_WORDS)])
	assert_eq(offenders, [] as Array[String],
		"a footer names a pad face letter and no key a keyboard player can press.\n" +
		"FIX: derive the token with InputProfileManager.hint_for_action(<the action the footer " +
		"describes>) — it returns that pad family's glyph when a pad is attached and the " +
		"keyboard key when none is, so one string serves both. Offenders: %s" %
		"\n  ".join(offenders))


## THE FUNCTIONAL DEFECT, and the reason this file exists rather than a caption ratchet:
## unequip was reachable ONLY from a keyboard.
func test_unequip_is_reachable_from_a_pad() -> void:
	var src := FileAccess.get_file_as_string(EQUIPMENT)
	assert_gt(src.length(), 1000, "PRECONDITION: EquipmentMenu must be readable")
	assert_true(src.contains("event.keycode == KEY_X"),
		"PRECONDITION: the keyboard route must still exist — this guard defends ADDING the pad one")
	assert_true(src.contains("event.button_index == JOY_BUTTON_X"),
		"unequip must have a PAD route. It had none: the only call site was KEY_X, so a pad player " +
		"could not unequip at all on a screen this game promises works on gamepad")
	var at := src.find("event.button_index == JOY_BUTTON_X")
	assert_gt(src.find("_unequip_slot()", at), -1,
		"the pad branch must actually call _unequip_slot, not merely mention the button")


## CONTROL: the scanner must be able to SEE a frozen footer, or the arm above is vacuous over
## whatever it happens to have collected. Uses the real predicate against a planted string.
func test_the_footer_scanner_can_fire() -> void:
	var re := RegEx.create_from_string("(^|[\\s\\[(])([AB])\\s*[/:]")
	assert_true(re.search("↑↓: Select  A/Click: Use  B/RClick: Back") != null,
		"CONTROL: the frozen-letter pattern must match the shape this defect took")
	assert_true(re.search("[A/Enter/Click] Play") != null,
		"CONTROL: it must match inside brackets too — that is a real footer shape here")
	assert_false(re.search("↑↓/D-pad: Select  Ⓐ/Click: Use") != null,
		"CONTROL: a DERIVED footer must NOT match, or correct work reds")
	assert_false(re.search("Backspace: Delete") != null,
		"CONTROL: a word merely starting with B must not match")


## The corpus must reach the files this defect lived in. Named, not counted — a walk that broke
## would report zero offenders over zero strings.
func test_the_corpus_reaches_the_menus_that_had_it() -> void:
	var seen := {}
	for entry in _footer_strings():
		seen[str(entry[0]).get_file()] = true
	assert_gt(_scanned, 40, "the footer corpus collapsed; it should hold dozens of strings")
	for f in ["EquipmentMenu.gd", "ItemsMenu.gd", "QuestLog.gd", "OverworldMenu.gd"]:
		assert_true(seen.has(f), "the corpus must reach %s — it carried one of the thirteen" % f)


## ⛔ THE ARM THIS FILE SHIPPED WITHOUT. "a pad player can unequip" went out in .302 verified by
## `code.contains("button_index == JOY_BUTTON_X")` — a fact about SOURCE TEXT. That survives the
## branch existing and never being reached: an `_input` that returns early, a mode that never routes
## there, a handler consumed upstream. @cowir-music's day cost the fleet this sentence — "I measured
## the REGISTER and reported it as the ARTIFACT" — and @cowir-battle turned their blind guard from a
## has_status() source assert into a miss-rate count on the same principle.
##
## So: build the event, feed it to the real handler, and assert the equipment actually came off.
func test_pressing_the_pad_button_really_unequips() -> void:
	var weapon_id: String = ""
	for id in EquipmentSystem.weapons.keys():
		weapon_id = str(id)
		break
	assert_ne(weapon_id, "", "PRECONDITION: EquipmentSystem must know at least one weapon")

	var c := Combatant.new()
	c.combatant_name = "PadTester"
	assert_true(EquipmentSystem.equip_weapon(c, weapon_id),
		"PRECONDITION: equipping must succeed, or the unequip below proves nothing")
	assert_eq(c.equipped_weapon, weapon_id, "PRECONDITION: the weapon is ON before the press")

	var menu = load("res://src/ui/EquipmentMenu.gd").new()
	add_child_autofree(menu)
	menu.character = c
	menu.selected_slot = 0
	menu.mode = menu.Mode.ITEM_SELECT   # the mode whose footer carries "Unequip"
	menu.visible = true

	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_X
	ev.pressed = true
	menu._input(ev)

	assert_eq(c.equipped_weapon, "",
		"pressing the west face in ITEM_SELECT must actually take the weapon OFF. The source " +
		"branch existing is not the same as the event reaching it")


## CONTROL: the probe must be able to observe a NON-event, or "it unequipped" is unfalsifiable.
func test_a_different_face_button_does_not_unequip() -> void:
	var weapon_id: String = ""
	for id in EquipmentSystem.weapons.keys():
		weapon_id = str(id)
		break
	var c := Combatant.new()
	c.combatant_name = "PadTester2"
	EquipmentSystem.equip_weapon(c, weapon_id)

	var menu = load("res://src/ui/EquipmentMenu.gd").new()
	add_child_autofree(menu)
	menu.character = c
	menu.selected_slot = 0
	menu.mode = menu.Mode.ITEM_SELECT
	menu.visible = true

	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_START   # not the unequip face
	ev.pressed = true
	menu._input(ev)

	assert_eq(c.equipped_weapon, weapon_id,
		"CONTROL: an unrelated pad button must NOT unequip — otherwise the arm above proves nothing")
