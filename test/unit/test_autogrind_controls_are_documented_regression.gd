extends GutTest

## While an autogrind runs, the player has four controls — and the F1 reference, the one screen
## struktured asked for so it would be "really easy to know all the buttons", had NO AUTOGRIND
## SECTION AT ALL. Zero mentions of autogrind, turbo or tier. That was the original defect.
##
## ⛔ THE SECTION THAT FIXED IT WAS THEN WRONG FOR MONTHS AND THIS FILE SCORED GREEN ON IT.
## Every row was checked against AutogrindInputHelper.classify_event — and that dispatch table is
## NOT the surface a grind runs on. AutogrindUI sets `visible = false` when the grind starts and
## `_show_monitor()` has exactly one caller (the mid-grind editor's close callback, reachable only
## from a monitor that was already visible), so classify_event never sees the events. GameLoop's
## `LoopState.AUTOGRIND` branch is the live handler, and it binds only ui_cancel, JOY_BUTTON_Y,
## KEY_Y, KEY_T, KEY_P and the two shoulders. The reference advertised "Back (Minus): Pause" —
## no pad binding exists — and "Start (Plus): Adjust rules", bound on neither device.
##
## The old arms could not see any of it because each half was true on its own: the reference said
## "Pause" and the HELPER said JOY_BUTTON_BACK, and nothing joined them to a live handler. One arm
## went further and PINNED "Back (Minus)" as required, so the guard forbade the fix it protected.
## Every arm below joins the rendered row to the branch that answers it.

const HELPER_SRC := "res://src/ui/autogrind/AutogrindInputHelper.gd"
const BRANCH_HEAD := "if current_state == LoopState.AUTOGRIND:"
## Vocabulary no pad this game supports has printed on it, or that names the wrong face.
## ⛔ This list twice named the wrong thing. It first banned "Start " / "Back " WITH A TRAILING SPACE,
## so a cell of exactly `Start` slipped through (a mutation predicted two reds and produced one).
## Removing the space then banned "Back" outright -- which is what an Xbox pad genuinely PRINTS on
## index 4, and "Minus" is the Switch name for it, so the ban would have forbidden the correct
## derived cell. The defect was never the family name: it was the parenthetical MASH that carries
## two families at once ("Back (Minus)", "Start (Plus)") and the face descriptions ("west face").
## No derived cell needs a bracket or the word "face", so those are the shapes to ban.
const FROZEN_PAD_WORDS := ["Select", "(", ")", "face"]


## The live handler's window, located by its own text — a line number goes stale on the first edit
## anywhere above it, and this branch sits 900 lines into GameLoop.
func _branch_window() -> String:
	## Stripped: the window is extracted by INDENTATION, so a docstring authored inside the AUTOGRIND
	## branch lands in it — and `_branch_keys` regexes `KEY_([A-Z])` over the result. A docstring
	## naming KEY_R would satisfy the advertised-is-bound arm; one naming a phantom key would red the
	## other. Demonstrated in this lane: the .338 guard passed 4/4 with a real connect deleted and a
	## docstring claiming it.
	var lines: PackedStringArray = _code_only(FileAccess.get_file_as_string("res://src/GameLoop.gd"), "func _on_grind_complete(").split("\n")
	var start := -1
	var base := 0
	for i in lines.size():
		if lines[i].contains(BRANCH_HEAD):
			start = i
			base = lines[i].length() - lines[i].lstrip("\t").length()
			break
	assert_gt(start, -1, "PRECONDITION: GameLoop must still have a `%s` branch" % BRANCH_HEAD)
	if start < 0:
		return ""
	var out: PackedStringArray = []
	for j in range(start + 1, lines.size()):
		if lines[j].strip_edges() == "":
			continue
		if lines[j].length() - lines[j].lstrip("\t").length() <= base:
			break
		out.append(lines[j])
	return "\n".join(out)


## Single-letter keycodes the live branch binds: {"P": true, ...}
func _branch_keys(window: String) -> Dictionary:
	var found := {}
	for m in RegEx.create_from_string("KEY_([A-Z])\\b").search_all(window):
		found[m.get_string(1)] = true
	return found


## The rendered rows of the autogrind block, as [pad_cell, keyboard_cell, description].
func _rows() -> Array:
	var text: String = HowToPlayOverlay.build_text()
	var at := text.find("WHILE AUTOGRINDING")
	assert_gt(at, -1, "the reference must document the mode the game is built around")
	if at < 0:
		return []
	var rest := text.substr(at)
	var stop := rest.find("[b][color=yellow]", 1)
	var body := rest.substr(0, stop) if stop > 0 else rest
	var rows: Array = []
	for line in body.split("\n"):
		if line.strip_edges() == "" or line.contains("WHILE AUTOGRINDING") or line.begins_with("[color=gray]"):
			continue
		rows.append([line.substr(0, 18).strip_edges(), line.substr(18, 18).strip_edges(),
			line.substr(36)])
	return rows


## Single-letter keys a rendered keyboard cell offers. "X / Esc" yields X; "Esc" is not a keycode
## this guard can resolve and is covered by the ui_cancel arm instead.
func _cell_letters(cell: String) -> Array:
	var out: Array = []
	for tok in cell.split("/"):
		var t := tok.strip_edges()
		if t.length() == 1 and t == t.to_upper():
			out.append(t)
	return out


func test_the_reference_documents_the_autogrind_mode() -> void:
	var rows := _rows()
	assert_gt(rows.size(), 2,
		"CONTROL: only %d autogrind rows parsed — with none in range every arm below is vacuous" % rows.size())


## → direction: nothing advertised may be unbound. This is the half that was satisfied by a word in
## one file and a constant in another.
func test_every_key_the_reference_advertises_is_really_bound() -> void:
	var window := _branch_window()
	var bound := _branch_keys(window)
	assert_gt(bound.size(), 1,
		"CONTROL: %d single-letter bindings found in the branch — the cross-check needs a real set" % bound.size())
	var unbound: Array = []
	for row in _rows():
		for letter in _cell_letters(row[1]):
			# The stop row's X comes from ACTION_KEYS["exit"] and is bound as the ui_cancel ACTION,
			# not as a raw keycode, so it is answered by its own arm below.
			if letter == str(AutogrindInputHelper.ACTION_KEYS["exit"]):
				continue
			if not bound.has(letter):
				unbound.append("%s (%s)" % [letter, row[2].strip_edges()])
	assert_eq(unbound, [],
		("the reference advertises a key the AUTOGRIND branch does not bind — a player presses it " +
		"and nothing happens, which is how 'Start (Plus) / R: Adjust rules' survived: %s") % [unbound])
	assert_true(window.contains("is_action_pressed(\"ui_cancel\")"),
		"stop-grinding must still be the ui_cancel ACTION, so a Controls rebind moves it")


## ← direction: nothing bound may go unadvertised. This is the arm that would have caught the
## original defect (Y/T/P bound globally with no section at all), and it catches the next one.
func test_every_key_the_branch_binds_is_advertised() -> void:
	var bound := _branch_keys(_branch_window())
	var advertised := {}
	for row in _rows():
		for letter in _cell_letters(row[1]):
			advertised[letter] = true
	var silent: Array = []
	for k in bound:
		if not advertised.has(k):
			silent.append(k)
	assert_eq(silent, [],
		("the AUTOGRIND branch binds a key the reference never names — that is exactly how turbo, " +
		"tier and pause became an undocumented mode: %s") % [silent])


## The pad column must be DERIVED. Frozen family vocabulary is the defect, and the previous version
## of this file required one instance of it.
func test_the_pad_column_names_no_frozen_family() -> void:
	var offenders: Array = []
	for row in _rows():
		for word in FROZEN_PAD_WORDS:
			if str(row[0]).contains(word):
				offenders.append("%s in %s" % [word, row[0]])
	assert_eq(offenders, [],
		("a pad cell names one family's plastic. Select belongs to the SNES, Plus/Minus to Nintendo, " +
		"and 'west face' was on JOY_BUTTON_Y, which is the NORTH face: %s") % [offenders])
	var helper := FileAccess.get_file_as_string(HELPER_SRC)
	## Open paren, no close: pinning the full call froze the SIGNATURE, and adding the device_name
	## test hook reddened it. The claim is the INDEX, not the argument list.
	assert_true(helper.contains("button_name_for_index(JOY_BUTTON_Y"),
		"turbo's token must come from the index GameLoop actually binds")
	## ⛔ This arm first read the WHOLE OVERLAY SOURCE for "Y (west face)     Y " — which is ALSO the
	## battle "Repeat last turn's actions" row, a row this change does not touch. It failed on a
	## neighbour, not on its subject. The section-scoped sweep above is the correct instrument.


## No pad attached is the headless case and every player's first minutes. Naming a button then is a
## guess; @cowir-controller's rule is that the helpers must decline instead.
func test_no_pad_means_no_pad_cell() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"PRECONDITION: this arm measures the no-pad rendering, so the runner must have no pad")
	var dashes := 0
	for row in _rows():
		assert_eq(str(row[0]), AutogrindInputHelper.REFERENCE_PAD_NONE,
			"with no pad attached the pad cell must decline, not guess a family: %s" % row[2].strip_edges())
		dashes += 1
	assert_gt(dashes, 2, "CONTROL: %d cells checked" % dashes)


## Pause must work on EVERY tier. The Tier-1 dashboard bound index 4 through the dispatch table
## while GameLoop's branch bound only KEY_P, so a pad player could pause on one tier and not the
## next — and the reference advertised the pad button regardless. Both halves are now bound.
func test_pause_is_bound_on_both_grind_surfaces() -> void:
	var window := _branch_window()
	## ⛔ The first version of this binding was raw `JOY_BUTTON_BACK` and the neighbour sweep redded
	## test_remap_reaches_every_handler: index 4 carries the REMAPPABLE `battle_toggle_auto`, so a
	## raw handler stays on the old button after a rebind. Both the handler and the printed cell
	## resolve through the action now.
	assert_true(window.contains("is_action_pressed(\"battle_toggle_auto\")"),
		("the AUTOGRIND branch must bind a pad button for pause — the dashboard surface already does, " +
		"and a control that works on one tier only is worse than one that works nowhere"))
	assert_true(window.contains("KEY_P"), "and the keyboard key it has always had")
	var helper := FileAccess.get_file_as_string(HELPER_SRC)
	assert_true(helper.contains("hint_for_action(\"battle_toggle_auto\""),
		"the pause row's pad cell must follow the same action, or it prints the pre-rebind button")
	var pause_rows := 0
	for row in _rows():
		if str(row[2]).contains("Pause"):
			pause_rows += 1
			assert_eq(str(row[1]), str(AutogrindInputHelper.ACTION_KEYS["pause"]),
				"the pause row's key must come from the dispatch table's own constant")
	assert_eq(pause_rows, 1, "exactly one row documents pause")


## Adjust-rules is REACHABLE as of the branch that connected adjust_rules_requested, so the reference
## must advertise it again. ⛔ THIS ARM USED TO ASSERT THE OPPOSITE, and shipping the two halves in
## separate branches is what caught me: the "nothing binds it" version landed in .328 and the branch
## that adds the connection landed in .329, so my own guard redded the fold — correctly, with the
## message "restore the reference row for it". Both directions are pinned now so neither can drift
## alone: the row exists, the key is bound in the live branch, and the signal has a listener.
func test_adjust_rules_is_advertised_because_it_is_reachable_now() -> void:
	## ⛔ This counted `adjust_rules_requested` anywhere in GameLoop, and MY OWN comment on the handler
	## contains that word — so deleting the connect scored GREEN. Prose satisfying a source-presence
	## assert, in a guard written twenty minutes earlier. Comments stripped, and the claim is the
	## CONNECT rather than the mention, because "something listens" is the reachability question.
	var gl := _code_only(FileAccess.get_file_as_string("res://src/GameLoop.gd"), "func _on_grind_complete(")
	assert_gt(gl.count("adjust_rules_requested.connect("), 0,
		("nothing connects adjust_rules_requested, so the feature is unreachable again — remove its " +
		"row from AutogrindInputHelper.grind_reference_rows rather than advertising a dead control"))
	assert_true(_branch_window().contains("KEY_R"),
		("the AUTOGRIND branch must bind KEY_R: the dashboard surface reaches adjust-rules through " +
		"AutogrindInputHelper, and without this the control works on one tier and not the next"))
	var rows := 0
	for row in _rows():
		if str(row[2]).contains("Adjust rules"):
			rows += 1
			assert_eq(str(row[1]), str(AutogrindInputHelper.ACTION_KEYS["adjust_rules"]),
				"the adjust-rules row's key must come from the dispatch table's own constant")
			assert_eq(str(row[0]), AutogrindInputHelper.REFERENCE_PAD_NONE,
				("no pad button reaches adjust-rules at tier 0, so the cell must decline. If the " +
				"AUTOGRIND branch gains a pad binding for it, derive the cell here instead of a dash"))
	assert_eq(rows, 1, "exactly one row documents adjust-rules")


## The dashboard's legend must stay derived. ⚠️ It describes classify_event, which is a DIFFERENT
## surface from the one the F1 rows describe — kept because a frozen word there is wrong on at
## most one family either way.
func test_the_dashboard_legend_is_derived() -> void:
	var dash := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	assert_true(dash.contains("AutogrindInputHelper.hint_for(\"pause\")"),
		"the dashboard's pause legend must be DERIVED from the dispatch table, not typed")
	assert_false(dash.contains("KEY_ZZQ"), "CONTROL: the source read can report absence")


## The pad column must CHANGE with the pad. A cell that is right on one family and frozen for the
## rest is the whole defect, and a no-pad run cannot see it: every cell is a dash there. The
## device_name hook makes the three families renderable with no hardware attached.
func test_the_pad_cells_differ_by_family() -> void:
	var families := {"xbox": "Xbox 360 Controller", "ps": "Sony DualSense Wireless Controller",
		"switch": "Nintendo Switch Pro Controller"}
	var seen := {}
	for key in families:
		var rows := _rows_of(AutogrindInputHelper.grind_reference_rows(families[key]))
		assert_gt(rows.size(), 2, "CONTROL: %s rendered %d rows" % [key, rows.size()])
		var cells: Array = []
		for row in rows:
			cells.append(row[0])
		gut.p("  %-7s pad cells: %s" % [key, cells])
		seen[key] = "|".join(PackedStringArray(cells))
		for word in FROZEN_PAD_WORDS:
			assert_false(seen[key].contains(word),
				"%s cell names foreign vocabulary: %s" % [key, seen[key]])
	assert_ne(seen["xbox"], seen["ps"],
		"Xbox and PlayStation render the SAME pad cells — the column is frozen, not derived")
	assert_ne(seen["xbox"], seen["switch"],
		"Xbox and Switch render the SAME pad cells — the column is frozen, not derived")


## The two inversions BattleScene._grind_console_controls already documents, stated as claims rather
## than as a copy of the table: stop is the SOUTH face, so it is never "B" on Xbox; turbo is
## JOY_BUTTON_Y, the NORTH face, which a Nintendo pad prints X, not Y.
func test_the_two_documented_inversions_do_not_come_back() -> void:
	var xbox := _rows_of(AutogrindInputHelper.grind_reference_rows("Xbox 360 Controller"))
	var switch := _rows_of(AutogrindInputHelper.grind_reference_rows("Nintendo Switch Pro Controller"))
	assert_gt(xbox.size(), 2, "CONTROL: the xbox rendering must have rows")
	for row in xbox:
		if str(row[2]).contains("Stop grinding"):
			assert_ne(str(row[0]), "B",
				"stop is ui_cancel, the SOUTH face — Xbox prints A there. 'B' is the Nintendo letter")
	for row in switch:
		if str(row[2]).contains("Turbo"):
			assert_ne(str(row[0]), "Y",
				"turbo is JOY_BUTTON_Y, the NORTH face — a Nintendo pad prints X there, not Y")


## Parse a rendered block the same way _rows() parses the live screen, so both arms measure the
## same thing. Kept separate because this one takes text rather than reading the overlay.
func _rows_of(block: String) -> Array:
	var rows: Array = []
	for line in block.split("\n"):
		if line.strip_edges() == "":
			continue
		rows.append([line.substr(0, 18).strip_edges(), line.substr(18, 18).strip_edges(),
			line.substr(36)])
	return rows


## Comment lines dropped, so a source-presence assert cannot be satisfied by an explanation of the
## very defect it guards. `#` covers `##` docstring comments too.
func _code_only(src: String, must_survive: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	var parts := "\n".join(out).split("\"\"\"")
	var kept: PackedStringArray = []
	for i2 in parts.size():
		if i2 % 2 == 0:
			kept.append(parts[i2])
	var stripped := "".join(kept)
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed a known CODE site (%s) — every assert below measures nothing" % must_survive)
	return stripped

