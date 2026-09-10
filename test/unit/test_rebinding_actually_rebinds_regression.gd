extends GutTest

## Remapping a button did NOTHING unless the player had already switched their controller profile
## to "Custom" — and the remap screen never switches it.
##
## MEASURED before the fix, on the default Standard profile:
##   set_custom_binding("ui_accept", [3])
##   custom_bindings holds [3]      the button was stored
##   InputMap still reports [1]     the binding never applied
##   active_profile still Standard  so save/load discards it on restart too
## ControlsMenu updates its label and plays "menu_select" either way, so every signal the player
## gets says the rebind worked.
##
## The InputMap write was gated on `active_profile == "Custom"` and nothing ever switched. This is
## the definer/consumer shape the fleet spent 2026-09-09 on: a screen writes a value and the thing
## that would consume it is never reached.

var _saved_profile: String = ""
var _saved_custom: Dictionary = {}
var _saved_config: String = ""
var _had_config: bool = false

const CONFIG := "user://input/controls.json"


## set_custom_binding calls save_config(), which writes user://. Deploy suites run UNSANDBOXED, so
## snapshot the real file and put it back — the autobattle-profiles leak of 2026-09-06 in a
## different file.
func before_each() -> void:
	_saved_profile = InputProfileManager.active_profile
	_saved_custom = InputProfileManager.custom_bindings.duplicate(true)
	_had_config = FileAccess.file_exists(CONFIG)
	_saved_config = FileAccess.get_file_as_string(CONFIG) if _had_config else ""


func after_each() -> void:
	InputProfileManager.custom_bindings = _saved_custom.duplicate(true)
	InputProfileManager.active_profile = _saved_profile
	InputProfileManager.apply_profile(_saved_profile)
	if _had_config:
		DirAccess.make_dir_recursive_absolute("user://input")
		var f := FileAccess.open(CONFIG, FileAccess.WRITE)
		if f:
			f.store_string(_saved_config)
			f.close()
	elif FileAccess.file_exists(CONFIG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))


func _buttons(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			out.append(ev.button_index)
	return out


## THE DEFECT. A rebind from a stock profile must reach the engine's map.
func test_a_rebind_on_a_stock_profile_reaches_the_inputmap() -> void:
	InputProfileManager.apply_profile("Standard")
	var before := _buttons("ui_accept")
	assert_false(before.has(3),
		"PRECONDITION: ui_accept must not already be on button 3, or the arm below cannot fail (got %s)" % str(before))
	InputProfileManager.set_custom_binding("ui_accept", [3])
	assert_true(_buttons("ui_accept").has(3),
		"a rebind must actually rebind — it was stored and never applied, while the menu said it worked")


## And the profile must become Custom, or save/load discards the choice on the next launch.
func test_the_rebind_survives_being_saved_and_reloaded() -> void:
	InputProfileManager.apply_profile("Standard")
	InputProfileManager.set_custom_binding("ui_accept", [3])
	assert_eq(InputProfileManager.active_profile, "Custom",
		"rebinding must switch to Custom — a saved 'Standard' reapplies the stock table and drops the rebind")
	InputProfileManager.save_config()
	InputProfileManager.custom_bindings = {}
	InputProfileManager.active_profile = "Standard"
	InputProfileManager.load_config()
	assert_eq(InputProfileManager.active_profile, "Custom", "the saved profile must come back as Custom")
	var loaded: Array = InputProfileManager.custom_bindings.get("ui_accept", [])
	assert_true(loaded.has(3),
		"and the saved button must come back with it, AS AN INT — JSON yields 3.0 and FACE_GLYPHS is int-keyed")
	assert_eq(typeof(loaded[0]), TYPE_INT,
		"a float index renders '?' in every glyph surface; coerce where JSON enters")


## The user-visible half: a rebind that survived a restart must still draw a real glyph.
func test_a_reloaded_rebind_still_renders_a_glyph() -> void:
	InputProfileManager.apply_profile("Standard")
	InputProfileManager.set_custom_binding("ui_accept", [3])
	InputProfileManager.save_config()
	InputProfileManager.custom_bindings = {}
	InputProfileManager.load_config()
	InputProfileManager.apply_profile("Custom")
	var g: String = InputProfileManager.glyph_for_action("ui_accept", "Xbox 360 Controller")
	assert_ne(g, "?",
		"a remapped action must not render '?' after a restart — measured: int 3 gives a glyph, float 3.0 does not")
	assert_eq(g, str(InputProfileManager.FACE_GLYPHS["xbox"][3]),
		"and it must be the glyph for the button the player actually chose")


## CONTROL: the guard on unremappable actions must still refuse, or the arms above would pass on a
## function that rebinds anything at all.
func test_an_unremappable_action_is_still_refused() -> void:
	InputProfileManager.apply_profile("Standard")
	var before := InputProfileManager.active_profile
	InputProfileManager.set_custom_binding("zzq_not_an_action", [3])
	assert_eq(InputProfileManager.active_profile, before,
		"an unremappable action must change nothing — not even the profile")


## Seeding Custom from the LIVE profile rather than _ready's Standard copy is deliberate, and
## currently UNOBSERVABLE: all three shipped profiles are byte-identical (the Ultimate Pro 2 L/R
## swap was aligned 2026-07-29). Pin that, so the moment they diverge this reads as a gap to fill
## rather than a passing test that proved nothing.
func test_the_profiles_are_still_identical_so_the_seeding_arm_is_owed() -> void:
	var a: Dictionary = InputProfileManager.PROFILE_STANDARD
	var b: Dictionary = InputProfileManager.PROFILE_SN30
	var c: Dictionary = InputProfileManager.PROFILE_ULTIMATE_PRO_2
	assert_eq(str(a), str(b), "if these diverge, add an arm that a rebind preserves the OTHER bindings")
	assert_eq(str(a), str(c), "same for Ultimate Pro 2 — seeding from the live profile then becomes testable")
