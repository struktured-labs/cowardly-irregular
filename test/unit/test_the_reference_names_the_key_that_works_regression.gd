extends GutTest

## The controls reference — the one screen that teaches a player the controls — named keys that do
## something else, for ten days, on the rows a new player reads first:
##
##   row                        said            truth
##   Confirm / Select           Z / Enter       X / Enter / Space   (emulator layout, 2026-09-29)
##   Cancel / Back              X / Escape      Z / Escape          (X CONFIRMS now)
##   Defer                      L Key           Q                   (shoulders -> Q/W, 2026-09-25)
##   Advance                    R Key           W
##   Run                        Shift           Shift / A
##   Open the menu              (no row at all) S / Escape
##
## Pressing L for Defer opened the party chat or the battle log instead. Every row was a frozen
## letter written beside a gamepad cell that WAS derived.
##
## ⛔ WHY NOTHING CAUGHT IT: test_controls_reference_lists_every_global_key sweeps project ACTIONS
## and global F-keys, and asks whether each is ADVERTISED — whether the row EXISTS, never whether
## the key it prints is the key that works. A row can name a real action and a wrong key and pass.
## The field-menu toggle is worse than wrong: it is a RAW keycode with no action at all
## (OverworldMenu.TOGGLE_KEY), so it sits outside that corpus entirely and had no row.
##
## So this guard reads the RENDERED reference and checks each row's keyboard cell against the
## InputMap — never against the helper that printed it, or it would only agree with itself.

const Overlay := preload("res://src/ui/HowToPlayOverlay.gd")

## description marker -> the action whose keys that row's keyboard cell must name.
const ROW_ACTION := {
	"Confirm / Select": "ui_accept",
	"Cancel / Back": "ui_cancel",
	"Defer (in battle)": "battle_defer",
	"Party Chat (in the field)": "party_chat",
	"Advance (queue action)": "battle_advance",
	"Run — hold": "dash",
}

## The keyboard column: 18 wide, after the 18-wide gamepad column.
const KB_COL := 18
const KB_WIDTH := 18


func _rows() -> Dictionary:
	var out := {}
	for line in Overlay.build_text().split("\n"):
		for marker in ROW_ACTION:
			if line.contains(marker):
				out[marker] = line.substr(KB_COL, KB_WIDTH).strip_edges()
	return out


func _key_event(token: String) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = OS.find_keycode_from_string(token)
	e.pressed = true
	return e


func test_every_key_the_reference_prints_does_what_the_row_says() -> void:
	var rows := _rows()
	assert_eq(rows.size(), ROW_ACTION.size(),
		"CONTROL: every row this guard checks must be IN the reference, else it proves nothing. Missing: %s"
		% [ROW_ACTION.keys().filter(func(m): return not rows.has(m))])
	var offenders := []
	var checked := 0
	for marker in rows:
		var action: String = ROW_ACTION[marker]
		var cell: String = rows[marker]
		assert_ne(cell, "", "the '%s' row prints no key at all" % marker)
		for token in cell.split(" / "):
			var t := token.strip_edges()
			if t == "" or t == "—":
				continue
			checked += 1
			var e := _key_event(t)
			if e.keycode == KEY_NONE or not InputMap.event_is_action(e, action):
				offenders.append("'%s' row names %s, which is not bound to %s" % [marker, t, action])
	assert_gt(checked, ROW_ACTION.size(), "CONTROL: the rows must name real key tokens to check")
	assert_eq(offenders, [],
		"the controls reference names keys that do something else: %s" % [offenders])


## The row that did not exist. The field menu is the first control a player needs in the field and
## its key is raw, so no action sweep can see it — it must be named, and the key must really open it.
func test_the_reference_names_the_key_that_opens_the_menu() -> void:
	var menu_rows := []
	for line in Overlay.build_text().split("\n"):
		if line.contains("Open the menu"):
			menu_rows.append(line)
	assert_eq(menu_rows.size(), 1, "the reference must name the menu key, exactly once")
	if menu_rows.is_empty():
		return
	var cell: String = menu_rows[0].substr(KB_COL, KB_WIDTH).strip_edges()
	var checked := 0
	for token in cell.split(" / "):
		var t := token.strip_edges()
		if t == "":
			continue
		checked += 1
		assert_true(OverworldMenu.is_toggle_event(_key_event(t)),
			"the menu row names %s, which does not open the overworld menu" % t)
	assert_gt(checked, 0, "CONTROL: the row must print at least one key")
	assert_string_contains(cell, OS.get_keycode_string(OverworldMenu.TOGGLE_KEY),
		"and it must name the opener's own key, so a rebind moves the row with it")


## CONTROL FOR THE DETECTOR ITSELF: the exact letters that were on those rows must now FAIL the
## check above, or a future freeze would slip through the same way.
func test_the_keys_it_used_to_name_are_rejected_now() -> void:
	for pair in [["L", "battle_defer"], ["R", "battle_advance"], ["Z", "ui_accept"], ["X", "ui_cancel"]]:
		assert_false(InputMap.event_is_action(_key_event(pair[0]), pair[1]),
			"%s must NOT be %s — that pairing is what the reference taught, and this guard must reject it"
			% [pair[0], pair[1]])
