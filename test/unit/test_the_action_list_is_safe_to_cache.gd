extends GutTest

## `GamepadDiagnostic.project_actions()` derives the pad-bound action list from the InputMap and
## caches it in a STATIC with no invalidation. Its comment justifies the cache by cost — "parsed
## once and cached; this runs every frame while the overlay is open" — and says nothing about the
## premise that makes it SAFE: that the set cannot change while the process runs.
##
## ⛔ IT CAN. Measured: bind a pad button to a keyboard-only action and the cache still reports the
## old membership.
##     first call    15 actions
##     bind a pad button to `ui_focus_next`
##     second call   15 actions, contains "ui_focus_next"? false
##
## ✅ AND IT IS INERT TODAY, WHICH IS WHY THIS FILE PINS THE PREMISE INSTEAD OF CHANGING THE CACHE:
##     REMAPPABLE actions with NO joypad event    []        so a remap cannot GROW the set
##     apply each of the 4 profiles               15 / 15   gained=[] lost=[]
## Every remappable action already has a pad binding, and `_replace_joypad_buttons` erases and
## re-adds, so membership never moves. The cache is correct — for a reason written down nowhere.
##
## 🔑 The day someone adds a keyboard-only entry to REMAPPABLE_ACTIONS, the diagnostic silently
## stops listing it the moment a player binds it — on the screen whose whole job is answering "my
## button does nothing", which is the exact complaint the derived list was built to fix. That is
## what these arms red on.
##
## ⚠️ DELIBERATELY NOT ASSERTED: that the cache currently equals a fresh derivation. The static is
## filled by whichever test touches it first, so in a batch run that comparison measures the suite's
## ORDER rather than this premise, and a flaky red at the fold costs more than the arm is worth.

const DIAG := preload("res://src/ui/GamepadDiagnostic.gd")

var _saved_profile: String = ""
var _saved_bindings: Dictionary = {}


## ⛔ SNAPSHOT THE BINDINGS THEMSELVES, not just the profile NAME. Re-applying a name restores the
## profile's bindings, which are not the same thing as what this tree had if a custom binding was
## live — and eight other files here apply profiles, so leaving the InputMap altered moves every
## bound index for whatever runs next. apply_profile writes no config, so nothing on disk to reset.
func before_all() -> void:
	_saved_profile = InputProfileManager.active_profile
	for action in InputProfileManager.REMAPPABLE_ACTIONS:
		if InputMap.has_action(action):
			_saved_bindings[action] = _indices(action)


func after_all() -> void:
	for action in _saved_bindings:
		InputProfileManager._replace_joypad_buttons(action, _saved_bindings[action])
	InputProfileManager.active_profile = _saved_profile


func _indices(action: String) -> Array:
	var out: Array = []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append((e as InputEventJoypadButton).button_index)
	out.sort()
	return out


## The set the cache is a snapshot of, derived fresh.
func _joy_bound_actions() -> Array:
	var out: Array = []
	for a in InputMap.get_actions():
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				out.append(String(a))
				break
	out.sort()
	return out


## ⛔ THE CONTROL, and it has to come first: an empty derivation satisfies both arms below —
## "no remappable action lacks a binding" and "no profile changes the set" are each vacuously
## true of nothing.
func test_there_is_a_real_action_set_to_reason_about() -> void:
	var bound: Array = _joy_bound_actions()
	assert_gt(bound.size(), 10,
		"CONTROL: the project binds many actions to a pad; deriving %d means the scan is broken" % bound.size())
	assert_gt(InputProfileManager.REMAPPABLE_ACTIONS.size(), 3,
		"CONTROL: REMAPPABLE_ACTIONS must be populated, got %d" % InputProfileManager.REMAPPABLE_ACTIONS.size())


## PREMISE 1 — a remap cannot GROW the set, because there is nothing for it to add.
func test_no_remappable_action_is_missing_a_pad_binding() -> void:
	var bound: Array = _joy_bound_actions()
	var keyboard_only: Array = []
	for a in InputProfileManager.REMAPPABLE_ACTIONS:
		if InputMap.has_action(a) and not (String(a) in bound):
			keyboard_only.append(String(a))
	assert_true(keyboard_only.is_empty(),
		"%s are remappable but have NO joypad binding, so binding one GROWS the pad-bound action " % [keyboard_only]
		+ "set — and GamepadDiagnostic caches that set in a static with no invalidation, so the "
		+ "diagnostic stops listing exactly the action the player just bound.")


## PREMISE 2 — a profile cannot change the set either. _replace_joypad_buttons erases and re-adds,
## so an action keeps a binding; an omitted action would lose one, which is the direction this arm
## covers and the one no other file here checks.
func test_no_profile_changes_which_actions_have_a_pad_binding() -> void:
	var base: Array = _joy_bound_actions()
	var moved: Array = []
	for p in InputProfileManager.PROFILE_NAMES:
		InputProfileManager.apply_profile(p)
		var now: Array = _joy_bound_actions()
		for a in now:
			if not (a in base):
				moved.append("%s GAINED %s" % [p, a])
		for a in base:
			if not (a in now):
				moved.append("%s LOST %s" % [p, a])
	assert_true(moved.is_empty(),
		"%s — applying a profile changed WHICH actions have a pad binding. The diagnostic's " % [moved]
		+ "cached list is a snapshot taken before that, so the overlay would report the old set "
		+ "for the rest of the process.")


## The cache must at least be a cache OF this function — a derivation that returned something else
## entirely would satisfy both premises above while listing the wrong rows.
func test_the_cached_list_is_drawn_from_the_input_map() -> void:
	var cached: Array = DIAG.project_actions()
	assert_gt(cached.size(), 10, "CONTROL: the cached list must be populated, got %d" % cached.size())
	var bound: Array = _joy_bound_actions()
	var strangers: Array = []
	for a in cached:
		if not (String(a) in bound):
			strangers.append(a)
	assert_true(strangers.is_empty(),
		"%s are listed by the diagnostic but have no joypad binding in the InputMap — the list is " % [strangers]
		+ "supposed to be derived from it, never a hardcoded roster.")
