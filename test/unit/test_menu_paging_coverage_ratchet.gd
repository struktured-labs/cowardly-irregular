extends GutTest

var GdSource = load("res://test/unit/helpers/gd_source.gd")

## struktured 2026-07-26: "how to scroll quickly or page thru long menus?"
##
## He asked because paging existed in only 2 of the menus that need it — and the
## two longest lists in the game (Jukebox at 153 tracks, Abilities) were among
## the ones without it. A feature that exists in some menus and not others is
## worse than one that exists nowhere: the player learns it works, then it
## silently doesn't, and they conclude the menu is broken rather than unpaged.
##
## Ratchets that every menu driving a long list through selected_index also
## offers a page jump. Deliberately NOT "every menu" — short fixed menus don't
## need it and requiring them would be the allowlist-on-day-one shape.

## ⛔ A FLOOR, NOT THE POPULATION — and it read as the population until 2026-09-17. Six hand-picked
## paths in a file called "coverage ratchet": a seventh long menu was caught by nothing. The derived
## arm at the bottom is what actually ratchets; this list only pins six that must never regress.
const LONG_LIST_MENUS := [
	"res://src/ui/SettingsMenu.gd",
	"res://src/ui/BossSelectorMenu.gd",
	"res://src/ui/JukeboxMenu.gd",
	"res://src/ui/AbilitiesMenu.gd",
	"res://src/ui/TeleportMenu.gd",
	"res://src/ui/FastTravelMenu.gd",
]

## Godot ships these with a KEYBOARD default and no joypad binding, and project.godot declares
## none of them — so a menu paging through them pages on keyboard only. TeleportMenu did exactly
## that (2026-09-16): PageUp/PageDown moved 8 rows, and a pad had no fast scroll at all.
const KEYBOARD_ONLY_PAGE_ACTIONS := ["ui_page_up", "ui_page_down"]

## Jump-to-first/last is a keyboard CONVENIENCE, not a control a pad is missing: a page jump
## reaches either end. So these are allowed — but only in a menu that also offers the pad-reachable
## page jump, which is the property the arm below checks. Found by the page arm reporting them.
const KEYBOARD_ONLY_EXTRA_ACTIONS := ["ui_home", "ui_end"]


func test_every_long_list_menu_offers_a_page_jump() -> void:
	var missing: Array = []
	for path in LONG_LIST_MENUS:
		var src := FileAccess.get_file_as_string(path)
		assert_ne(src, "", "%s must be readable" % path)
		if not src.contains("MenuPaging.page_delta("):
			missing.append(path.get_file())
	assert_eq(missing, [],
		"these menus scroll long lists but offer no page jump, so paging works in some "
		+ "menus and not others: %s" % [missing])


func test_paging_helper_covers_both_keyboard_and_gamepad() -> void:
	# If it were keyboard-only, a controller-first player would never find it —
	# and this project is controller-first by design.
	var src := FileAccess.get_file_as_string("res://src/ui/MenuPaging.gd")
	assert_true(src.contains("KEY_PAGEUP") and src.contains("KEY_PAGEDOWN"),
		"keyboard paging must stay bound to PageUp/PageDown")
	assert_true(src.contains("battle_defer") and src.contains("battle_advance"),
		"gamepad paging must stay on L1/R1 — controller-first is a project rule")


func test_page_jump_is_a_meaningful_stride() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/MenuPaging.gd")
	var re := RegEx.new()
	re.compile("PAGE_ROWS\\s*:=\\s*(?<n>\\d+)")
	var m := re.search(src)
	assert_not_null(m, "PAGE_ROWS must be declared")
	if m != null:
		assert_gt(int(m.get_string("n")), 3,
			"a page jump smaller than a few rows is indistinguishable from holding the d-pad")


## The arm that would have caught TeleportMenu. Derived from the source rather than a list of
## menus someone remembers to update: any UI file reaching for a keyboard-only nav action is
## shipping a control a controller cannot press, in a project whose first rule is the opposite.
func test_no_menu_pages_through_a_keyboard_only_action() -> void:
	var declared := FileAccess.get_file_as_string("res://project.godot")
	var offenders: Array = []
	var scanned := 0
	for action in KEYBOARD_ONLY_PAGE_ACTIONS + KEYBOARD_ONLY_EXTRA_ACTIONS:
		assert_false(declared.contains("\n%s={" % action),
			"%s is now declared in project.godot — if it was given a pad binding, drop it from this list" % action)
	for path in _ui_scripts("res://src/ui"):
		# Comment-stripped: the fix for this very defect explains itself in a comment naming both
		# actions, and a raw scan would red on the sentence describing why they were removed.
		var src: String = GdSource.code_of(path)
		if src == "":
			continue
		scanned += 1
		for action in KEYBOARD_ONLY_PAGE_ACTIONS:
			if src.contains('is_action_pressed("%s")' % action):
				offenders.append("%s -> %s" % [path.get_file(), action])
		for action in KEYBOARD_ONLY_EXTRA_ACTIONS:
			if src.contains('is_action_pressed("%s")' % action) and not src.contains("MenuPaging.page_delta("):
				offenders.append("%s -> %s with no pad-reachable page jump beside it" % [path.get_file(), action])
	assert_gt(scanned, 20, "the scan must actually read the UI corpus; a short corpus passes vacuously")
	assert_eq(offenders, [],
		"these menus navigate with an action that has no gamepad binding, so the control is "
		+ "invisible to a controller-first player: %s" % [offenders])


func _ui_scripts(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_ui_scripts(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## ⛔ THE DERIVED POPULATION. A list that needs a SCROLL WINDOW is, by its own code's admission,
## longer than the panel showing it — `MenuScroll.window_offset` exists for exactly that. So the
## population is derivable from the tree instead of hand-picked, and a new windowed menu is covered
## without editing this file.
##
## Found by deriving it: JobMenu had a windowed list, BOTH shoulders free, and no page jump — up to
## 14 jobs plus "(None)" as unlocks land, walked one row per press. The hand-list above never named
## it, and `test_every_long_list_menu_offers_a_page_jump` passed throughout.
##
## 🔑 EXEMPTIONS CARRY A REASON THIS ARM VERIFIES IN THE SOURCE, never a boolean. CLAUDE.md's rule:
## you cannot silence it green, only explain it green, and the explanation has to still be true.
##
## ⚠️ TWO DERIVATIONS HERE, TWO TRIGGERS — and this note described only the one I had last mutated.
##   POPULATION (_is_windowed over src/ui): a tree-wide rename of both tokens collapses it to 0 and
##     the scope control reds NAMED — measured, not assumed.
##   EXEMPTION (_reason_holds over the subject's source): catches the token disappearing, and NOT a
##     handler that keeps its text and becomes unreachable behind a new guard.
## @cowir-sfx's split: a floor asking the LIVE OBJECT catches a rename; one deriving from the TEST
## file's own source moves both sides together and stays silent; one deriving from the SUBJECT's
## source plus a non-empty scope control reds by collapse. Same word "verify", three triggers.
const WINDOWED_WITHOUT_PAGING := [
	{"path": "res://src/ui/EquipmentMenu.gd", "because": "shoulders_taken"},
	{"path": "res://src/ui/autobattle/AutobattleGridEditor.gd", "because": "shoulders_taken"},
	{"path": "res://src/ui/Win98Menu.gd", "because": "shoulders_are_battle_mechanics"},
]


## A list the menu has to WINDOW is longer than its panel — through the shared helper, or rolled by
## hand. ⛔ The first version required the helper, and that CALL-SHAPE bound hid two menus that roll
## their own (@cowir-sfx's axis: a location bound and a shape bound are different sentences).
func _is_windowed(code: String) -> bool:
	return code.contains("MenuScroll.window_offset(") or code.contains("max_visible")


## Is the declared reason still true of the file? Each verb is checked against the source.
func _reason_holds(because: String, code: String) -> bool:
	match because:
		"shoulders_are_battle_mechanics":
			# The one menu live DURING battle, where these actions ARE Defer and Advance — the case
			# MenuPaging's own header carves out. Paging here would spend a turn, not scroll a list.
			return code.contains("event.is_action_pressed(\"battle_defer\")") \
				and code.contains("event.is_action_pressed(\"battle_advance\")") \
				and code.contains("_handle_defer_input") and code.contains("_handle_advance_input")
		"shoulders_taken":
			# ⛔ `event.`, NOT bare — the bare spelling is ALSO satisfied by the _process self-heal's
			# `Input.is_action_pressed("battle_advance")`, so the first version of this check stayed
			# green with the shoulder HANDLER gutted. Caught by mutation, never by reading.
			return code.contains("event.is_action_pressed(\"battle_defer\")") \
				and code.contains("event.is_action_pressed(\"battle_advance\")")
	return false


func _declared(path: String) -> Dictionary:
	for e in WINDOWED_WITHOUT_PAGING:
		if str(e["path"]) == path:
			return e
	return {}


func test_every_windowed_list_pages_or_explains_why() -> void:
	var windowed: Array = []
	var unreadable: Array = []
	var offenders: Array = []
	for path in _ui_scripts("res://src/ui"):
		# An unreadable file is a corpus DROP, not a pass — it used to `continue` silently.
		if FileAccess.get_file_as_string(path) == "":
			unreadable.append(path.get_file())
			continue
		var code: String = GdSource.code_of(path)
		if not _is_windowed(code):
			continue
		windowed.append(path)
		if code.contains("MenuPaging.page_delta("):
			continue
		var e := _declared(path)
		if e.is_empty():
			offenders.append("%s: windowed list, no page jump, no declared reason" % path.get_file())
		elif not _reason_holds(str(e["because"]), code):
			offenders.append("%s: declares '%s' but the source no longer shows it" % [path.get_file(), str(e["because"])])
	assert_eq(unreadable, [],
		"these src/ui files could not be read, so the sweep never saw them: %s" % [unreadable])
	assert_gt(windowed.size(), 1,
		"the derivation found %d windowed menus — a short corpus passes vacuously" % windowed.size())
	assert_eq(offenders, [],
		"a windowed list is longer than its panel by construction, so one row per press is the "
		+ "longest walk in that menu. Page it, or add it to WINDOWED_WITHOUT_PAGING with a reason "
		+ "this file can verify: %s" % [offenders])


## The ledger must not outlive its fact: an entry that now pages is a declaration describing nothing.
func test_the_paging_exemptions_are_still_exempt() -> void:
	var stale: Array = []
	for e in WINDOWED_WITHOUT_PAGING:
		var code: String = GdSource.code_of(str(e["path"]))
		if code == "":
			continue
		if code.contains("MenuPaging.page_delta("):
			stale.append("%s now pages — delete its exemption" % str(e["path"]).get_file())
		elif not _is_windowed(code):
			stale.append("%s no longer windows its list — the exemption is about nothing" % str(e["path"]).get_file())
	assert_eq(stale, [], "%s" % [stale])
