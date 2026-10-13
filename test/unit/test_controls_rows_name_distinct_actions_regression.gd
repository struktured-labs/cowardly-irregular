extends GutTest

## Settings → Controls is the one screen whose entire job is telling the player which button does
## what. It drew TWO rows both titled "Menu": `ui_field_menu` on the north face / S (the overworld
## menu — party, items, quests, save) and `ui_menu` on Start / Enter (Settings in the field, the
## autobattle editor in battle). Nothing on either row said which was which, so the screen could
## not answer the only question it is there to answer.
##
## The title is not decoration — three surfaces read the same table and print it to the player:
##   the row list · the Conflicts line ("Plus: Menu & Menu") · Test Buttons ("Mapped to: Menu / Menu")
## and a rebind onto a shared button is exactly when a player goes looking.
##
## ⚠️ THE SAME AMBIGUITY HAS ALREADY SHIPPED ONCE, in prose: TutorialHints' quest-log hint used
## {menu} — which is `ui_menu` and opens SETTINGS — and sent a lost player to a menu with no Quest
## Log. That one was found by a person reading it. This file is the version that goes red.
##
## 🛑 WHY THE ROWS ARE READ FROM THE SCENE AND NOT FROM ACTION_LABELS: a table arm proves the table
## is distinct, not that the player sees distinct rows. The row builder picks its own title source
## (it could read a different table, or the raw action id through `.get(action, action)`), so the
## claim is only worth making about the Label that actually draws. The table arm is kept as well,
## below, because it covers the two surfaces that have no rows at all.

const ControlsMenuScript = preload("res://src/ui/ControlsMenu.gd")

## The row title for ui_accept. A CONTROL value: if the reader below grabbed the dot leader or the
## binding column instead of the title it comes back "...." or "Ⓐ", and every arm here would be
## comparing the wrong labels while staying green.
const KNOWN_FIRST_TITLE := "Confirm"

## The dot leader runs from the end of the title to x=312 and the binding column starts at x=320
## (ControlsMenu._add_row). A title wider than that draws over both.
const BINDING_COLUMN_LIMIT := 312.0


func _make_menu() -> ControlsMenu:
	var menu = ControlsMenuScript.new()
	menu.size = Vector2(1280, 720)
	add_child_autofree(menu)
	return menu


## The Label a player reads on `action`'s row — the first child of the row, which is the title
## `_add_row` adds before the dots and the value. Null if the row or that child is not a Label.
func _row_title(menu: ControlsMenu, action: String) -> Label:
	if not menu._action_labels.has(action):
		return null
	var row: Node = menu._action_labels[action].get_parent()
	if row == null or row.get_child_count() == 0:
		return null
	var first: Node = row.get_child(0)
	return first as Label


## Values appearing more than once, each named once, in first-seen order.
func _duplicates(values: Array) -> Array[String]:
	var seen := {}
	var dupes: Array[String] = []
	for v in values:
		var s := str(v)
		if seen.has(s):
			if not (s in dupes):
				dupes.append(s)
		else:
			seen[s] = true
	return dupes


## CONTROL for the detector itself: it must be able to say BOTH words. Without this the arms below
## are green on any detector that returns an empty array unconditionally.
func test_the_duplicate_detector_can_report_and_can_clear() -> void:
	assert_eq(_duplicates(["Menu", "Confirm", "Menu"]), ["Menu"] as Array[String],
		"CONTROL: the detector must NAME a repeated title")
	assert_eq(_duplicates(["Menu", "Confirm"]), [] as Array[String],
		"CONTROL: and must clear a list that has none")
	assert_eq(_duplicates(["A", "A", "A"]), ["A"] as Array[String],
		"CONTROL: a title repeated three times is one offender, not two")


## THE REGRESSION, as the player meets it: two rows with the same words on them.
func test_no_two_controls_rows_share_a_title() -> void:
	var menu := _make_menu()
	var titles: Array[String] = []
	var missing: Array[String] = []
	for action in InputProfileManager.REMAPPABLE_ACTIONS:
		var l := _row_title(menu, action)
		if l == null:
			missing.append(action)
			continue
		titles.append(str(l.text))
	assert_eq(missing, [] as Array[String],
		"PRECONDITION: every remappable action draws a row with a title Label: %s"
		% [", ".join(missing)])
	assert_eq(titles.size(), InputProfileManager.REMAPPABLE_ACTIONS.size(),
		"PRECONDITION: one title per remappable action, got %d of %d"
		% [titles.size(), InputProfileManager.REMAPPABLE_ACTIONS.size()])
	## By NAME, not by index: an arm that indexes `titles[0]` reads whichever action survived the
	## loop once one is missing, and crashes outright on an empty list — and a runtime error partway
	## through a GUT test body scores as a pass.
	var accept := _row_title(menu, "ui_accept")
	assert_not_null(accept, "CONTROL: ui_accept must have a row to read")
	if accept != null:
		assert_eq(str(accept.text), KNOWN_FIRST_TITLE,
			"CONTROL: ui_accept's row must read '%s' — any other value means this file is reading "
			% KNOWN_FIRST_TITLE + "the dot leader or the binding column, not the title")
	assert_eq(_duplicates(titles), [] as Array[String],
		"two rows on Settings → Controls read the same words, so the screen cannot say which "
		+ "button does what — that is how ui_field_menu and ui_menu both said 'Menu': %s"
		% [", ".join(_duplicates(titles))])


## No title may be blank either — an empty row title is distinct from every other title, so the
## arm above passes on one and the player gets a nameless binding.
func test_no_controls_row_title_is_blank() -> void:
	var menu := _make_menu()
	var blank: Array[String] = []
	for action in InputProfileManager.REMAPPABLE_ACTIONS:
		var l := _row_title(menu, action)
		if l == null or str(l.text).strip_edges() == "":
			blank.append(action)
	assert_eq(blank, [] as Array[String],
		"a Controls row has no title: %s" % [", ".join(blank)])


## A longer title is only an improvement if it still FITS. The title has no `clip_text`, so it draws
## straight over the dot leader and into the binding column; the column starts at x=320 and the
## leader is sized from the measured title width, so a title past x=312 collapses the leader to
## nothing and then overlaps the button name it is supposed to label.
func test_every_row_title_stops_before_the_binding_column() -> void:
	var menu := _make_menu()
	var over: Array[String] = []
	var widest := 0.0
	for action in InputProfileManager.REMAPPABLE_ACTIONS:
		var l := _row_title(menu, action)
		if l == null:
			continue
		var font: Font = l.get_theme_font("font")
		if font == null:
			continue
		## -1, not a wrap width: the title does not autowrap, and a width-limited query would
		## report a WRAPPED size for a Label that draws one line — i.e. it would agree with the fix
		## whether or not the fix is there.
		var w: float = font.get_string_size(str(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var right: float = l.position.x + w
		widest = maxf(widest, right)
		if right > BINDING_COLUMN_LIMIT:
			over.append("%s '%s' ends at %.0fpx" % [action, str(l.text), right])
	assert_gt(widest, 0.0,
		"CONTROL: the font must report a real width, or this arm passes on zeroes")
	assert_eq(over, [] as Array[String],
		"a Controls row title runs into the binding column (limit %.0fpx): %s"
		% [BINDING_COLUMN_LIMIT, ", ".join(over)])


## The two surfaces with no rows of their own — the Conflicts line and the Test Buttons overlay —
## join ACTION_LABELS values with " & " / " / ", so a duplicate there reads "Menu & Menu" with no
## row to disambiguate it. They read the table directly, so the table is asserted directly.
func test_no_two_actions_share_a_display_name() -> void:
	var labels: Array[String] = []
	for action in InputProfileManager.ACTION_LABELS:
		labels.append(str(InputProfileManager.ACTION_LABELS[action]))
	assert_gt(labels.size(), 5,
		"PRECONDITION: ACTION_LABELS must be populated, got %d entries" % labels.size())
	assert_eq(_duplicates(labels), [] as Array[String],
		"two actions share a display name, so the Conflicts line and Test Buttons print it twice "
		+ "with nothing to tell them apart: %s" % [", ".join(_duplicates(labels))])
