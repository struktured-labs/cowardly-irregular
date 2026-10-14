extends GutTest

## ⛔ A REMAPPABLE ACTION COULD BE BOUND ONTO A D-PAD DIRECTION, AND NOTHING SAW IT. Two guards sit
## on the remap path and the navigation buttons were in neither corpus:
##   `binding_would_trap_the_player` compares against `_refused_partners`, which was ONE pair
##     (`ui_accept`/`ui_cancel`) plus the field-menu set -- so a nav button was never a partner.
##   `detect_conflicts` iterated REMAPPABLE_ACTIONS, and the nav actions are not remappable -- so
##     the collision was STRUCTURALLY unreachable and the screen printed "Conflicts: None".
##
## 🔑 WHY CONFIRM IS A REFUSAL AND THE OTHER SEVEN ARE ONLY REPORTED, measured rather than asserted:
## `MenuNav.step` precedes the `ui_accept` check in 21 of the 34 menus that read it -- including the
## CONTROLS SCREEN (nav :1196, accept :1224), the only one that matters, since it is where the bind
## would be undone. 5 menus check accept FIRST and 8 never check it, so "every menu" was false.
## There, a direction consumes the event and the accept arm below it never runs: no pad press can
## activate a row, Reset included.
##
## ⚠️ TWO NON-PAD ESCAPES EXIST: keyboard Confirm survives (the capture replaces joypad events only)
## and a MOUSE click activates a row via `_on_row_click`. So this strands PAD-ONLY players -- which
## CLAUDE.md's "NO MOUSE/CLICKING required" makes a designed-for population rather than an edge
## case -- and the refusal is right either way, since a dead Confirm is not a thing to ship.
##
## 📌 THE WIDENED CONFLICT CORPUS COSTS NOTHING AT STOCK, which is why it is not gated: no
## remappable action sits on 11-14 and the four directions do not collide with each other, so
## `test_a_rebind_survives_the_face_convention`'s "stock is conflict-free" control stays green.

const IPM := "res://src/input/InputProfileManager.gd"
const CONFIG := "user://input/controls.json"  # read from InputProfileManager, not guessed

var _mode: bool = false
var _profile: String = ""
var _custom: Dictionary = {}
var _chosen: bool = false
var _had_config: bool = false
var _saved_config: String = ""


func _ipm() -> Node:
	return InputProfileManager


## Once per FILE: snapshotting the config per test makes the first arm create it and every later
## teardown faithfully restore the pollution. Same reasoning as the sibling face-convention file.
func before_all() -> void:
	_had_config = FileAccess.file_exists(CONFIG)
	_saved_config = FileAccess.get_file_as_string(CONFIG) if _had_config else ""


func after_all() -> void:
	if _had_config:
		var f := FileAccess.open(CONFIG, FileAccess.WRITE)
		if f != null:
			f.store_string(_saved_config)
			f.close()
	elif FileAccess.file_exists(CONFIG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))


func before_each() -> void:
	var m: Node = _ipm()
	if m == null:
		return
	_mode = m.nintendo_mode
	_profile = m.active_profile
	_custom = m.custom_bindings.duplicate(true)
	_chosen = m.profile_chosen_by_user


func after_each() -> void:
	var m: Node = _ipm()
	if m == null:
		return
	m.nintendo_mode = _mode
	m.custom_bindings = _custom.duplicate(true)
	m.active_profile = _profile
	m.profile_chosen_by_user = _chosen
	m.apply_profile(_profile)


func _bound(action: String) -> Array:
	return _ipm().get_current_button_indices(action)


func _nav() -> Array:
	var c: Dictionary = load(IPM).get_script_constant_map()
	assert_true(c.has("NAVIGATION_ACTIONS"),
		"the universal-context set must be a named const, or neither guard can reach it")
	return c["NAVIGATION_ACTIONS"] as Array


## ⛔ THE FILE-LEVEL FLOOR, derived from this file's own source. Every arm drives members on a
## dynamically-typed receiver, so a rename aborts the enclosing arm and -- once any assert has run
## in it -- the file scores PASSING with the subject never driven.
func test_the_manager_exposes_every_member_this_file_drives() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://test/unit/test_confirm_cannot_be_bound_onto_a_direction.gd")
	assert_true(src.find("binding_would_trap_the_player") > -1,
		"POSITIVE CONTROL: this file's source must be readable, or the derivation below runs on " +
		"an empty window and passes having checked nothing")
	var names: Dictionary = {}
	var rx := RegEx.create_from_string("\\bm\\.([A-Za-z_][A-Za-z0-9_]*)")
	for hit in rx.search_all(src):
		names[hit.get_string(1)] = true
	assert_gt(names.size(), 3, "CONTROL: the derivation must find the members this file drives")
	var m: Node = _ipm()
	var missing: Array = []
	for n in names:
		if m.has_method(str(n)) or str(n) in m:
			continue
		missing.append(str(n))
	assert_eq(missing, [],
		"every member this file reaches must exist -- a missing one aborts its arm and the file " +
		"can still score green. Derived: %s" % [names.keys()])


## CONTROL FIRST: the widened corpus must not invent a conflict on an untouched profile.
func test_the_stock_profile_is_still_conflict_free() -> void:
	var m: Node = _ipm()
	m.apply_profile("Standard")
	assert_eq(m.detect_conflicts(), [],
		"adding the navigation actions to the conflict corpus must report NOTHING at stock -- " +
		"no remappable action sits on a direction, and the directions do not collide")


## ⛔ THE REFUSAL. Binding Confirm onto a direction is the one rebind with no way back, so it is
## refused at the API rather than merely displayed.
func test_confirm_onto_a_direction_is_refused_with_a_reason() -> void:
	var m: Node = _ipm()
	var nav: Array = _nav()
	assert_gt(nav.size(), 0, "CONTROL: the navigation set must be populated")
	var up: Array = _bound(str(nav[0]))
	assert_false(up.is_empty(), "CONTROL: %s must be bound to a pad button" % str(nav[0]))

	var trap: Dictionary = m.binding_would_trap_the_player("ui_accept", [int(up[0])])
	assert_true(trap.get("trapped", false),
		"binding Confirm onto %s must be REFUSED: the direction consumes the event first, so no " % str(nav[0])
		+ "row can be activated afterwards and Reset is unreachable")
	var why: String = str(trap.get("reason", ""))
	## The reason must name the CONSEQUENCE, not the collision: "shares D-pad Up" does not tell the
	## player that nothing can be confirmed afterwards.
	assert_true(why.to_lower().contains("confirm"),
		"the reason must say the direction would also confirm: '%s'" % why)
	assert_true(why.to_lower().contains("undo") or why.to_lower().contains("activat"),
		"and that there would be no way back: '%s'" % why)


## And the refusal REACHES the state, not just the query -- set_custom_binding checks it too, so a
## caller bypassing the capture UI cannot strand the player either.
func test_the_refusal_leaves_the_binding_untouched() -> void:
	var m: Node = _ipm()
	var nav: Array = _nav()
	var up: Array = _bound(str(nav[0]))
	assert_false(up.is_empty(), "CONTROL: the direction must be bound")
	var before: Array = _bound("ui_accept")
	assert_false(before.is_empty(), "CONTROL: Confirm must be bound before the attempt")

	m.set_custom_binding("ui_accept", [int(up[0])])
	assert_eq(_bound("ui_accept"), before,
		"a refused bind must leave Confirm where it was -- a refusal that returns early AFTER " +
		"writing is not a refusal")


## ⛔ THE ARM THAT STOPS THIS OVER-REFUSING. The other seven are survivable: losing the battle log
## to a direction is annoying, not a trap, so it must be REPORTED and allowed. Without this arm a
## blanket refusal would pass every other assertion in this file.
func test_a_survivable_direction_collision_is_reported_not_refused() -> void:
	var m: Node = _ipm()
	var nav: Array = _nav()
	var up_action: String = str(nav[0])
	var up: Array = _bound(up_action)
	assert_false(up.is_empty(), "CONTROL: the direction must be bound")
	assert_eq(m.detect_conflicts(), [], "CONTROL: start conflict-free")

	var trap: Dictionary = m.binding_would_trap_the_player("battle_open_log", [int(up[0])])
	assert_false(trap.get("trapped", false),
		"the battle log on a direction is survivable and must NOT be refused: '%s'"
		% str(trap.get("reason", "")))

	m.set_custom_binding("battle_open_log", [int(up[0])])
	assert_true(int(up[0]) in _bound("battle_open_log"), "CONTROL: the rebind must have applied")

	## NAME THE PAIR, DO NOT COUNT -- a bare size() passed against the old source for a collision
	## the arm had not created (the sibling file's recorded mistake).
	var found := false
	for c in m.detect_conflicts():
		var actions: Array = c.get("actions", [])
		if int(c.get("button", -1)) == int(up[0]) \
				and "battle_open_log" in actions and up_action in actions:
			found = true
	assert_true(found,
		"detect_conflicts must report battle_open_log and %s sharing button %d -- its corpus was " % [up_action, int(up[0])]
		+ "the remappable eight, so a collision with a direction was unreachable and it said None")


## The conflict LINE has to be readable: ControlsMenu renders it through ACTION_LABELS with
## `.get(a, a)`, so a direction with no entry printed a raw action id at the player.
func test_every_direction_has_a_player_facing_label() -> void:
	var m: Node = _ipm()
	for a in _nav():
		var label: String = str(m.ACTION_LABELS.get(str(a), ""))
		assert_ne(label, "", "%s must have a label, or the conflict line prints its action id" % str(a))
		assert_false(label.begins_with("ui_"),
			"%s's label must not be the raw id: '%s'" % [str(a), label])
