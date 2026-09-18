extends GutTest

## The remap system was correct under `nintendo_mode = true` and broken under `false`, and every
## existing guard runs at the default — which is `true`.
##
## ⛔ THE ROOT CAUSE IS ONE DICTIONARY HOLDING TWO COORDINATE SYSTEMS. `custom_bindings` stores
## PRE-convention indices: `apply_profile` runs them through `face_convention_indices`, which swaps
## SOUTH<->EAST for ui_accept/ui_cancel while the Xbox/PlayStation convention is on. But
## `set_custom_binding` stored the captured PHYSICAL index straight into that table, and
## `get_current_button_indices` / `detect_conflicts` read the table as if it were what the pad has.
##
## Four measured consequences, all from that one mismatch:
##   1. a rebind of Confirm/Cancel MOVED on the next apply_profile — bind physical 1, reload, it is
##      on 0. The player's own remap silently relocates.
##   2. the trap guard was BLIND: binding Confirm onto Cancel's button reported trapped=false and
##      left BOTH on that button — the exact lockout that guard exists to prevent, on the Controls
##      screen, which is where the player is standing when they do it.
##   3. detect_conflicts() returned [] for that same collision.
##   4. get_action_button_label / face_position_for_action named the pre-swap button.
##
## 📌 `test_a_remap_cannot_lock_you_in_regression` is a good file that pins (2) and could not see
## it: it never turns the convention off. Same shape as the eight paging arms that each pulled one
## trigger — the fixture, not the arms.
##
## ⚠️ These arms MUTATE the profile manager and the InputMap. `before_each` snapshots and
## `after_each` restores, including `profile_chosen_by_user`, which load_config sets and nothing
## resets — a leaked `true` suppresses pad autodetection for every later file in the process.

const CONFIG := "user://input/controls.json"

var _mode: bool = true
var _profile: String = ""
var _custom: Dictionary = {}
var _chosen: bool = false
## ⛔ set_custom_binding() calls save_config(), which WRITES user://input/controls.json. Deploy
## suites run UNSANDBOXED, so this file would overwrite the player's real remaps. It also poisons
## the next test in the SAME run: measured — my own probes left a Custom profile on disk and the
## neighbouring lockout guard then failed its own CONTROL, which reads as a defect in the subject.
var _saved_config: String = ""
var _had_config: bool = false


func _ipm() -> Node:
	return get_node_or_null("/root/InputProfileManager")


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


## ⛔ ONCE PER FILE, NOT PER TEST, AND THAT IS THE WHOLE POINT. Snapshotting in before_each means
## the FIRST arm creates the file, the second arm snapshots what the first left, and every later
## teardown faithfully restores the pollution. Measured: the config survived a full run of this file
## with a per-test snapshot, and the question "did this exist before I started" only has one answer
## per file.
func before_all() -> void:
	_had_config = FileAccess.file_exists(CONFIG)
	_saved_config = FileAccess.get_file_as_string(CONFIG) if _had_config else ""


func after_all() -> void:
	if _had_config and _saved_config != "":
		## open(WRITE) TRUNCATES before store_string runs, so an empty snapshot would write ZERO
		## bytes over the player's file. Guard on CONTENT.
		if FileAccess.get_file_as_string(CONFIG) != _saved_config:
			DirAccess.make_dir_recursive_absolute("user://input")
			var f := FileAccess.open(CONFIG, FileAccess.WRITE)
			if f:
				f.store_string(_saved_config)
				f.close()
	elif FileAccess.file_exists(CONFIG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))


## One function's body, bounded by the next top-level `func` — a fixed width is the coincidental
## value shape, and these functions are long enough to be cut by one.
func _func_body(src: String, header: String) -> String:
	var at: int = src.find(header)
	if at < 0:
		return ""
	var stop: int = src.find("\nfunc ", at + header.length())
	return src.substr(at, stop - at) if stop > at else src.substr(at)


func _bound(action: String) -> Array:
	var out: Array = []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append((e as InputEventJoypadButton).button_index)
	out.sort()
	return out


## Puts the manager in the configuration every arm here needs: Xbox/PlayStation convention ON.
func _xbox_convention() -> Node:
	var m: Node = _ipm()
	m.nintendo_mode = false
	m.apply_profile("Standard")
	return m


## ⛔ THE CONTROL THAT MAKES EVERY ARM BELOW MEAN SOMETHING. If the convention does not actually
## move ui_accept off the table's index, none of these scenarios is the one being defended.
func test_the_convention_really_does_swap_confirm_and_cancel() -> void:
	var m: Node = _ipm()
	assert_not_null(m, "CONTROL: InputProfileManager autoload must be present")
	if m == null:
		return
	m.nintendo_mode = false
	var raw: Array = m.get_profile_bindings("Standard").get("ui_accept", [])
	assert_false(raw.is_empty(), "CONTROL: Standard must bind ui_accept")
	assert_ne(m.face_convention_indices("ui_accept", raw), raw,
		"CONTROL: with nintendo_mode off the convention must MOVE ui_accept, or these arms all "
		+ "measure the case that was already working")


## "Current" must mean what the pad has, not what the table stores.
func test_current_indices_agree_with_the_input_map() -> void:
	var m: Node = _xbox_convention()
	for action in ["ui_accept", "ui_cancel"]:
		assert_eq(m.get_current_button_indices(action), _bound(action),
			"get_current_button_indices(%s) must equal what is actually bound — everything " % action
			+ "downstream (the trap guard, the conflict list, the button label) reads it")


## ⛔ THE LOCKOUT. Measured before the fix: trapped=false, and both actions ended up on button 1.
func test_binding_confirm_onto_cancels_button_is_refused_under_the_xbox_convention() -> void:
	var m: Node = _xbox_convention()
	var cancel_btn: Array = _bound("ui_cancel")
	assert_false(cancel_btn.is_empty(), "CONTROL: Cancel must be bound to a pad button")
	var target: int = int(cancel_btn[0])
	assert_false(target in _bound("ui_accept"),
		"CONTROL: they must start on DIFFERENT buttons, or there is no collision to create")

	assert_true(m.binding_would_trap_the_player("ui_accept", [target]).get("trapped", false),
		"binding Confirm onto Cancel's physical button must be refused — the Controls screen "
		+ "checks ui_accept first, so a shared button fires Confirm and the screen never closes")

	m.set_custom_binding("ui_accept", [target])
	assert_false(target in _bound("ui_accept"),
		"…and the refusal must actually hold: Confirm is on %d, which Cancel also uses" % target)


func test_a_real_collision_is_reported_by_detect_conflicts() -> void:
	var m: Node = _xbox_convention()
	## Drive a collision the trap guard does NOT cover, so this arm tests the detector rather than
	## the refusal: battle_defer onto ui_accept's button is survivable and therefore permitted.
	var accept_btn: Array = _bound("ui_accept")
	assert_false(accept_btn.is_empty(), "CONTROL: Confirm must be bound")
	assert_eq(m.detect_conflicts(), [], "CONTROL: the stock profile must start conflict-free")

	m.set_custom_binding("battle_defer", [int(accept_btn[0])])
	assert_true(int(accept_btn[0]) in _bound("battle_defer"), "CONTROL: the rebind must have applied")

	## ⛔ NAME THE PAIR, DO NOT COUNT. `size() > 0` passed against the OLD source: reading the
	## pre-convention table, battle_defer's new index collided with ui_cancel's RAW entry, so a
	## conflict was reported — a different one, about buttons the pad does not have in those places.
	## The arm was green for a collision I had not created.
	var found := false
	for c in m.detect_conflicts():
		var actions: Array = c.get("actions", [])
		if int(c.get("button", -1)) == int(accept_btn[0]) \
				and "battle_defer" in actions and "ui_accept" in actions:
			found = true
	assert_true(found,
		"detect_conflicts must report battle_defer and ui_accept sharing button %d — it read the "
		% int(accept_btn[0]) + "pre-convention table, so it saw neither where they actually are")


## ⛔ THE ONE A PLAYER MEETS WITHOUT DOING ANYTHING UNUSUAL: rebind, restart, it moved.
func test_a_rebind_to_a_swapped_index_survives_a_reapply() -> void:
	var m: Node = _xbox_convention()
	## Move Cancel aside so binding Confirm to a swap index is legal rather than a trap.
	m.set_custom_binding("ui_cancel", [3])
	var accept_now: Array = _bound("ui_accept")
	assert_false(3 in accept_now, "CONTROL: Confirm must not already be on 3")

	## Pick the swap index Confirm is NOT currently on, so the rebind is a real change.
	var target: int = 1 if not (1 in accept_now) else 0
	m.set_custom_binding("ui_accept", [target])
	assert_true(target in _bound("ui_accept"),
		"CONTROL: the rebind must take effect immediately, or the reload arm proves nothing")

	m.apply_profile("Custom")
	assert_true(target in _bound("ui_accept"),
		"the player's rebind must survive a reapply: they pressed physical %d, and the table " % target
		+ "stored that raw so apply_profile swapped it to the other face")

	m.apply_profile("Custom")
	assert_true(target in _bound("ui_accept"),
		"…and must not oscillate — a second reapply swapping it back would be the same defect")


## The convention being ON must not itself change a rebind of a NON-face action.
func test_a_shoulder_rebind_is_untouched_by_the_convention() -> void:
	var m: Node = _xbox_convention()
	m.set_custom_binding("battle_advance", [7])
	assert_true(7 in _bound("battle_advance"), "CONTROL: the rebind applied")
	m.apply_profile("Custom")
	assert_true(7 in _bound("battle_advance"),
		"only ui_accept/ui_cancel are swapped; every other action must round-trip untouched")


## ⛔ THE SIBLINGS THE FIRST FIX HID, found by asking CLAUDE.md's "a fix hides its own siblings" of
## my own change. Two functions read the same pre-convention table and only one applied the swap:
## `glyph_for_action` did, `button_name_for_action` did not.
##
## ⚠️ THAT ONE IS NOT OBSERVABLE TODAY AND I AM NOT CLAIMING IT IS. `BUTTON_NAMES` covers indices
## 4/6/7/9/10 and the convention swaps only 0<->1, so both readers return "" for accept/cancel
## whatever the mode. It is corrected for symmetry with its twin and because adding any face button
## to BUTTON_NAMES would make it live — so the arm pins the SOURCE consistency, which is the part
## that can actually go wrong, rather than a behaviour that cannot currently differ.
func test_both_button_readers_apply_the_face_convention() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/input/InputProfileManager.gd")
	assert_gt(src.length(), 1000, "CONTROL: the manager must be readable")
	## ⛔ PER FUNCTION, NOT A GLOBAL COUNT. My first version counted the call across the file and
	## required >= 2 — and apply_profile supplies a THIRD occurrence, so reverting
	## button_name_for_action left 2 and the arm passed on the mutation.
	for fn in ["func glyph_for_action(", "func button_name_for_action("]:
		var body: String = _func_body(src, fn)
		assert_gt(body.length(), 0, "CONTROL: %s must exist to have a body" % fn)
		assert_true(body.contains("face_convention_indices("),
			"%s reads the PRE-convention table and must apply the swap — its twin does, and one " % fn
			+ "naming a face the other does not is the asymmetry that put the wrong button on the "
			+ "Controls screen")


## The Controls screen's button-TEST overlay maps a pressed PHYSICAL button back to its action. It
## read the raw table too, so with the convention on it named the wrong one — on the screen whose
## whole purpose is telling the player what a button does.
func test_the_button_test_overlay_maps_a_physical_press_to_the_right_action() -> void:
	var m: Node = _xbox_convention()
	var accept_btn: Array = _bound("ui_accept")
	var cancel_btn: Array = _bound("ui_cancel")
	assert_false(accept_btn.is_empty() or cancel_btn.is_empty(), "CONTROL: both must be bound")
	assert_ne(accept_btn[0], cancel_btn[0], "CONTROL: they must be on different buttons")

	## The overlay's lookup, as ControlsMenu performs it.
	assert_true(int(accept_btn[0]) in m.get_current_button_indices("ui_accept"),
		"pressing Confirm's physical button must map to Confirm")
	assert_false(int(accept_btn[0]) in m.get_current_button_indices("ui_cancel"),
		"…and must NOT also map to Cancel — the raw table put them the other way round")


## ⛔ THE SOURCE PIN, because the overlay's lookup lives in ControlsMenu and cannot be driven here
## without standing up the whole screen. It must ask the manager what is bound, not index the table.
func test_the_overlay_asks_what_is_bound() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/ControlsMenu.gd")
	assert_gt(src.length(), 1000, "CONTROL: ControlsMenu must be readable")
	assert_true(src.contains("if btn in InputProfileManager.get_current_button_indices(action):"),
		"the test overlay must resolve a pressed button through get_current_button_indices — "
		+ "indexing the profile table directly names the pre-convention action")
