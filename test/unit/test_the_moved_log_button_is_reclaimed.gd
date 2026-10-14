extends GutTest

## ⛔ A DEFECT ON STRUKTURED'S OWN MACHINE, from his `.684` play log. On 2026-10-04 he ruled that L3
## should open the battle log ("reuse L3"); the DEFAULTS were updated and saved Custom profiles were
## not, and no version bump migrated them. His applied bindings, from that log:
##
##     ui_menu         -> buttons [6, 7]      6 = START, 7 = L3
##     battle_open_log -> buttons [7]         7 = L3
##
## Button 7 serves both, and in battle `GameLoop`'s ui_menu branch wins: it opens the AUTOBATTLE
## EDITOR and consumes the press, so L3 never reaches the log. The comment beside that branch
## records the same shape being read before as "a pause menu he could not escape".
##
## 🔑 NO `user://` I/O ANYWHERE IN THIS FILE, which is a requirement rather than a style choice
## (@cowir-main): the fixture is a COPY of his config SHAPE injected into `custom_bindings`, and the
## migration is called directly. His real `controls.json` is never read, written or opened, and
## nothing here depends on the sandbox being in place. The wiring into `load_config` is pinned by a
## source arm instead, so no arm needs a file to exist.
##
## ⚠️ This file WRITES AN AUTOLOAD (`InputProfileManager.custom_bindings`), so it saves and restores
## it -- the leak class that cost a stack at the `.691` fold.

## His shape, transcribed from the log rather than invented.
const HIS_SHAPE := {
	"ui_accept": [1], "ui_cancel": [0],
	"battle_advance": [10], "battle_defer": [9],
	"battle_toggle_auto": [4],
	"ui_menu": [6, 7],
	"battle_open_log": [7],
	"ui_field_menu": [3],
}

var _saved_bindings = null
var _saved_profile = null


func before_each() -> void:
	_saved_bindings = (InputProfileManager.custom_bindings as Dictionary).duplicate(true)
	_saved_profile = InputProfileManager.active_profile


func after_each() -> void:
	if _saved_bindings != null:
		InputProfileManager.custom_bindings = _saved_bindings
	if _saved_profile != null:
		InputProfileManager.active_profile = _saved_profile


func _inject(shape: Dictionary) -> void:
	InputProfileManager.custom_bindings = shape.duplicate(true)


## CONTROL — the defaults this migration enforces must still say what it assumes. If the default
## ui_menu ever reclaims L3, the migration's premise is gone and every arm below is about nothing.
func test_the_default_still_moves_l3_to_the_log() -> void:
	var std: Dictionary = InputProfileManager.PROFILE_STANDARD
	assert_eq(std.get("ui_menu", []), [6],
		"the default ui_menu must still be START only; the migration enforces that move")
	assert_eq(std.get("battle_open_log", []), [7],
		"the default battle_open_log must still own L3")


## HIS CASE — the whole point of the item.
func test_his_stale_config_loses_l3_from_the_menu() -> void:
	_inject(HIS_SHAPE)
	InputProfileManager._migrate_moved_log_button(2)
	assert_eq(InputProfileManager.custom_bindings["ui_menu"], [6],
		"L3 must be reclaimed from ui_menu, leaving START")
	assert_eq(InputProfileManager.custom_bindings["battle_open_log"], [7],
		"the log keeps L3 -- moved, deliberately, not dropped")


## A CONFIG WRITTEN AFTER THE FIX IS NEVER TOUCHED. This is what protects a deliberate rebind: a
## player who puts L3 back on the menu after this ships is at version 3 and never reaches the code.
func test_a_current_config_is_left_alone() -> void:
	_inject(HIS_SHAPE)
	InputProfileManager._migrate_moved_log_button(3)
	assert_eq(InputProfileManager.custom_bindings["ui_menu"], [6, 7],
		"a version-3 config is a deliberate choice and must survive untouched")


## A BUTTON THE DEFAULT STILL CLAIMS IS NOT RECLAIMED, even when it collides. Keying on the
## collision alone would strip START from a config that also bound START to the log.
## ⛔ THE THIRD BUTTON IS WHAT GIVES THIS ARM TEETH, and it took a mutation to find out. With
## ui_menu = [6, 7] and the default check dropped, BOTH buttons are reclaimed, ui_menu empties, and
## the never-empty fallback below restores the default [6] -- so the assertion passed on the very
## defect it exists to catch. My own safety net masked it. An extra button keeps ui_menu non-empty,
## so the fallback cannot fire and the missing default check is visible.
func test_a_button_the_default_still_owns_survives() -> void:
	var shape: Dictionary = HIS_SHAPE.duplicate(true)
	shape["ui_menu"] = [6, 7, 8]
	shape["battle_open_log"] = [6, 7]
	_inject(shape)
	InputProfileManager._migrate_moved_log_button(2)
	var menu: Array = InputProfileManager.custom_bindings["ui_menu"]
	assert_false(menu.is_empty(),
		"PRECONDITION: ui_menu must stay non-empty here, or the fallback masks this arm")
	assert_true(6 in menu,
		"START is still the default's own ui_menu button and must not be reclaimed: got %s" % [menu])
	assert_false(7 in menu, "L3 must still be reclaimed: got %s" % [menu])


## ⛔ ui_menu IS NEVER LEFT EMPTY. A config whose ui_menu is exactly the log's buttons would be
## stripped to nothing, leaving no way to open the menu -- worse than the collision it fixes.
func test_the_menu_is_never_left_with_no_button() -> void:
	var shape: Dictionary = HIS_SHAPE.duplicate(true)
	shape["ui_menu"] = [7]
	shape["battle_open_log"] = [7]
	_inject(shape)
	InputProfileManager._migrate_moved_log_button(2)
	var menu: Array = InputProfileManager.custom_bindings["ui_menu"]
	assert_false(menu.is_empty(),
		"ui_menu must never be emptied by this migration; it falls back to the default")
	assert_eq(menu, [6], "the fallback is the default ui_menu")


## A CLEAN CONFIG IS UNCHANGED — no collision, nothing to do.
func test_a_config_with_no_collision_is_untouched() -> void:
	var shape: Dictionary = HIS_SHAPE.duplicate(true)
	shape["ui_menu"] = [6]
	_inject(shape)
	InputProfileManager._migrate_moved_log_button(2)
	assert_eq(InputProfileManager.custom_bindings["ui_menu"], [6],
		"a config already matching the default must not be rewritten")


## WIRING — asserted at SOURCE so no arm needs a config file to exist. A migration nothing calls is
## the defect one layer over, and `load_config` is the only caller.
func test_load_config_actually_calls_the_migration() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/input/InputProfileManager.gd")
	assert_ne(src, "", "CONTROL: the source must be readable")
	var at: int = src.find("func load_config")
	assert_gt(at, -1, "load_config must exist")
	## ⛔ THE END BOUNDARY MUST HANDLE "LAST FUNCTION IN THE FILE". `load_config` IS the last one, so
	## `find("\nfunc ", …)` returns -1 and `substr(at, -1 - at)` is a window that does not contain
	## the call -- this arm red on correct code until I measured it. My own banked note says a source
	## pin needs BOTH boundaries; this is the end one going missing rather than being wrong.
	var next_func: int = src.find("\nfunc ", at + 10)
	var body: String = src.substr(at) if next_func == -1 else src.substr(at, next_func - at)
	assert_true(body.contains("_migrate_moved_log_button("),
		"load_config must call the migration, or a stale config is never repaired")
	assert_true(src.contains("const CONFIG_VERSION = 3"),
		"CONFIG_VERSION must be 3, or a migrated config is re-migrated on every launch")
