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
## keys. It does not verify the whole table — the other six rows were measured correct by hand
## (2026-09-11) and are not asserted here. A row-by-row ratchet over prose is a different, larger
## instrument and I am not claiming to have built it.

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
