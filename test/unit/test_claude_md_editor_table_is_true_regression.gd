extends GutTest

## CLAUDE.md's "Autobattle Editor Controls" table is the reference every lane and struktured reads,
## and it had DRIFTED: it said **Delete cell — Start / Y | Escape** when delete had been rehomed
## months ago. Measured against the live editor:
##
##     Escape -> ui_cancel -> save_and_close()        not delete
##     Start  -> ui_menu   -> _save_script + close    not delete
##     actual delete: Delete/Backspace, or Y off a condition cell
##
## Two of the three bindings the table named for delete now SAVE AND CLOSE — the most destructive
## possible mis-documentation for an editor, because a player following the doc to remove one rule
## exits the screen instead, and the doc reads as authoritative.
##
## ⚠️ SCOPE: this pins the DELETE row, the one that drifted, plus the two actions that stole its
## keys, plus the OPEN EDITOR row (below). It does not verify the whole table. A row-by-row ratchet
## over prose is a different, larger instrument and I am not claiming to have built it.
##
## ⛔ THIS HEADER USED TO SAY "the other six rows were measured correct by hand (2026-09-11) and are
## not asserted here." ONE OF THOSE SIX WAS FALSE. The table said `Open editor | L+R together`, and
## the ONLY simultaneous L+R handler in src/ is GameLoop:901 — inside the autogrind console block,
## cycling the AUTOGRIND TIER. Four citations, zero handlers; @cowir-overworld found it because an
## NPC repeats the claim to the player. My hand-pass cleared it, and I then EDITED THIS TABLE an hour
## later to add a device-name note without re-reading the rows I had blessed.
##
## 🔑 A "measured by hand" note is a claim with no instrument behind it, and it reads in the file
## exactly like a verified one. The repair is not a better hand-pass: the row that was wrong is now
## ASSERTED, and this header no longer vouches for anything it does not test.

const CLAUDE_MD := "res://CLAUDE.md"
const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"


func _editor_source() -> String:
	var src := FileAccess.get_file_as_string(EDITOR)
	assert_gt(src.length(), 1000, "PRECONDITION: the editor source must be readable")
	return src


func _table_row(label: String) -> String:
	var doc := FileAccess.get_file_as_string(CLAUDE_MD)
	assert_gt(doc.length(), 1000, "PRECONDITION: CLAUDE.md must be readable")
	var at := doc.find("### Autobattle Editor Controls")
	assert_gt(at, -1, "the editor controls table must exist in CLAUDE.md")
	var stop := doc.find("\n###", at + 1)
	var table := doc.substr(at, (stop - at) if stop > at else -1)
	var row_at := table.find("| %s |" % label)
	assert_gt(row_at, -1, "the table must have a '%s' row" % label)
	var row_end := table.find("\n", row_at)
	return table.substr(row_at, (row_end - row_at) if row_end > row_at else -1)


## THE DRIFT. The keyboard column must name the keys the editor actually deletes on.
func test_the_delete_row_names_the_real_keys() -> void:
	var row := _table_row("Delete cell")
	var src := _editor_source()
	assert_true(src.contains("KEY_DELETE, KEY_BACKSPACE"),
		"PRECONDITION: the editor deletes on Delete/Backspace — if this moved, fix the row too")
	assert_true(row.contains("Delete") and row.contains("Backspace"),
		"the Delete row must name Delete/Backspace, the keys that actually delete: %s" % row)
	assert_false(row.contains("Escape"),
		"Escape must NOT be listed as delete — it is ui_cancel and SAVES AND CLOSES the editor, " +
		"so a player following this doc loses the screen instead of a rule: %s" % row)
	assert_false(row.contains("Start"),
		"Start must NOT be listed as delete — it is ui_menu and also saves and closes: %s" % row)


## The two actions that took those keys must still do what makes the exclusion above correct.
## If either ever stops closing the editor, the Delete row's wording needs revisiting rather than
## this test quietly staying green on a stale reason.
## ⚠️ Scans EVERY occurrence, not the first. This editor has FOUR ui_cancel branches at different
## nesting levels — portrait focus, grid level, option picker, share picker — because Escape backs
## out one level at a time, which is correct. A bare find() takes the portrait one and reports a
## defect on healthy code. It did.
func _any_branch_reaching(action: String, effect: String, window: int) -> bool:
	var src := _editor_source()
	var needle := "is_action_pressed(\"%s\")" % action
	var from := 0
	while true:
		var at := src.find(needle, from)
		if at < 0:
			return false
		if src.substr(at, window).contains(effect):
			return true
		from = at + 1
	return false


func test_escape_and_start_still_close_rather_than_delete() -> void:
	assert_true(_any_branch_reaching("ui_cancel", "save_and_close", 160),
		"some ui_cancel branch (Escape/X/B) must save and close — that is why Escape is not a " +
		"delete key, and it is the claim the corrected table rests on")
	assert_true(_any_branch_reaching("ui_menu", "closed.emit", 200),
		"some ui_menu branch (Start) must close — that is why Start is not a delete key")
	assert_false(_any_branch_reaching("ui_cancel", "_delete_current_cell", 160),
		"no ui_cancel branch may DELETE — that was the old binding the table still described")


## CONTROL: the table reader must be able to report a row ABSENT, or every arm above could be
## passing on an empty string.
func test_the_table_reader_discriminates() -> void:
	var row := _table_row("Close editor")
	assert_true(row.contains("B"), "CONTROL present: the Close row names B")
	assert_true(row.length() > 10, "CONTROL: a real row was returned, not an empty slice")
	var delete_row := _table_row("Delete cell")
	assert_ne(delete_row, row, "CONTROL: two different labels must return two different rows")


## THE OPEN-EDITOR ROW. It claimed L+R for months; the row is now asserted rather than hand-blessed.
## Pins the RELATIONSHIP — the doc's gamepad claim must name an opener the code actually has — not
## the spelling, so rewording the row is free and rebinding it is not.
func test_the_open_editor_row_names_a_real_opener() -> void:
	var row := _table_row("Open editor")
	var loop := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(loop.length(), 1000, "PRECONDITION: GameLoop must be readable")

	# The gamepad opener is ui_menu reaching _toggle_autobattle_editor. Prove that arm exists.
	var menu_at := loop.find("is_action_pressed(\"ui_menu\")")
	assert_gt(menu_at, -1, "PRECONDITION: the ui_menu arm must exist, or this test pins nothing")
	assert_gt(loop.find("_toggle_autobattle_editor()", menu_at), -1,
		"ui_menu must still reach _toggle_autobattle_editor — the row names Start as the opener")

	# NEGATIVE: no simultaneous L+R handler may open the editor. The only one in src/ cycles the
	# autogrind tier, so a row claiming L+R sends a pad player to a button that does nothing.
	assert_false(row.contains("L+R"),
		"the Open editor row claims L+R, which opens nothing: the sole simultaneous L+R handler " +
		"(GameLoop, autogrind console) calls cycle_tier(). Row: %s" % row)
	assert_true(row.contains("Start"), "the row must name Start, the real gamepad opener: %s" % row)
	assert_true(row.contains("F5"), "the row must keep the keyboard opener: %s" % row)


## CONTROL for the negative arm above. My first version of this asserted
## `"| Open editor | L+R together | F5 |".contains("L+R")` — a literal against itself, which proves
## the predicate compiles and NOTHING about the reader. The way `assert_false(row.contains("L+R"))`
## actually goes vacuous is `_table_row` returning a slice that stops before the gamepad column, so
## that is what this pins: the row must carry all three cells.
##
## The real negative control is the MUTATION, recorded here because it cannot live in the file:
## restoring `| Open editor | L+R together | F5 |` to CLAUDE.md -> Failing 1, naming the row.
func test_the_row_reader_surfaces_the_gamepad_column() -> void:
	var row := _table_row("Open editor")
	assert_eq(row.count("|"), 4,
		"a full table row has 4 pipes (label, gamepad, keyboard); a shorter slice would make the " +
		"L+R check pass by reading past nothing: %s" % row)
	var cells := row.split("|", false)
	assert_eq(cells.size(), 3, "CONTROL: label, gamepad and keyboard cells must all be present: %s" % row)
	assert_gt(cells[1].strip_edges().length(), 0, "CONTROL: the gamepad cell must be non-empty")


## @cowir-overworld 2026-09-11: my first repair of this row was CORRECT AND INCOMPLETE. It named
## Start (battle-only) and F5, and omitted what a pad player does in EXPLORATION — where Start opens
## SETTINGS, not the editor. They shipped "Start on a pad" into NPC dialogue on the strength of the
## row I had just fixed, and a pad player following it landed in Settings. A row can be true of the
## state it describes and wrong for the state the reader is in.
func test_the_open_editor_row_covers_exploration_too() -> void:
	var row := _table_row("Open editor")
	var loop := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var exp_at := loop.find("elif current_state == LoopState.EXPLORATION:")
	assert_gt(exp_at, -1, "PRECONDITION: the exploration arm of the ui_menu block must exist")
	# In exploration, ui_menu opens SETTINGS. If that ever becomes the editor, this row must change.
	assert_gt(loop.find("_open_settings_menu()", exp_at), -1,
		"ui_menu in EXPLORATION must still reach _open_settings_menu — the row warns readers it " +
		"does NOT open the editor there, and that warning is only true while this holds")
	assert_true(row.contains("exploration") or row.contains("Exploration"),
		"the row must say what a PAD player does outside battle, or it is true only in battle: %s" % row)
	assert_true(row.contains("Settings"),
		"the row must warn that Start opens Settings in exploration — the trap that put an NPC " +
		"line wrong: %s" % row)
