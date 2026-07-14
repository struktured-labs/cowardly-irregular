extends GutTest

## Regression test for the AutobattleGridEditor export/import wiring.
##
## Feature: "Autobattle scripting IS the game." The existing ScriptShareManager
## export/import API (export_character_script / export_all_scripts / import_file
## / apply_character_script, files under user://script_exports/) was already
## present but had NO surface in the autobattle grid editor — players could not
## save, load, or share scripts from the place they author them. This wires
## Export (E) and Import (I, via a controller-navigable file picker) into the
## grid editor, seeding the design's "Hall of Fame for novel strategies."
##
## What this guards:
##   1. The editor exposes the export/import wiring (methods + picker member).
##   2. An exported-then-imported script round-trips a character's rules through
##      ScriptShareManager and back into the editor's visible grid.
##   3. The import picker is a submenu that blocks grid input while open (so it
##      doesn't steal navigation from the grid).
##   4. The scroll-follow / MAX_RULES behavior added earlier still works after a
##      round-trip (importing rebuilds the grid + resets scroll, doesn't regress).
##
## Uses the real user://script_exports/ path (same as ScriptShareManager) and
## cleans up the files it writes afterward.

const GridEditorScript = preload("res://src/ui/autobattle/AutobattleGridEditor.gd")

const VIEW_W := 1280
const VIEW_H := 720

# Files _export_script() may write for the "hero" character. Cleaned up after.
const _EXPORT_FILES := ["hero_autobattle.json", "party_autobattle.json"]


func before_each() -> void:
	_cleanup_exports()


func after_each() -> void:
	_cleanup_exports()


func _cleanup_exports() -> void:
	for fname in _EXPORT_FILES:
		var path = ScriptShareManager.EXPORT_DIR + fname
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _make_editor() -> AutobattleGridEditor:
	var editor = GridEditorScript.new()
	editor.size = Vector2(VIEW_W, VIEW_H)
	add_child_autofree(editor)
	# _ready() runs on add_child; setup() rebuilds UI + grid with real data.
	editor.setup("hero", "Hero", null, [])
	return editor


func _distinctive_rules() -> Array:
	"""A recognizable multi-rule script we can fingerprint after a round-trip."""
	return [
		{
			"conditions": [{"type": "hp_percent", "op": "<", "value": 25}],
			"actions": [{"type": "defer"}],
			"enabled": true
		},
		{
			"conditions": [{"type": "ap", "op": ">=", "value": 3}],
			"actions": [{"type": "attack", "target": "highest_hp_enemy"}],
			"enabled": true
		},
		{
			"conditions": [{"type": "always"}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
			"enabled": true
		},
	]


# --- 1. Wiring exists -------------------------------------------------------

func test_editor_exposes_export_import_wiring() -> void:
	var editor = _make_editor()
	assert_true(editor.has_method("_export_script"),
		"editor must expose _export_script() so players can save scripts")
	assert_true(editor.has_method("_open_share_picker"),
		"editor must expose _open_share_picker() to list importable files")
	assert_true(editor.has_method("_import_script_file"),
		"editor must expose _import_script_file() to apply a chosen export")
	assert_true("_share_picker" in editor,
		"editor must declare a _share_picker submenu member")


# --- 2. Export -> import round-trips a character's rules ---------------------

func test_export_then_import_roundtrips_rules() -> void:
	var editor = _make_editor()

	# Author a distinctive script and export it from the editor.
	editor.rules = _distinctive_rules()
	editor._refresh_grid()
	editor._export_script()

	# The character export file must now exist on disk.
	var char_path = ScriptShareManager.EXPORT_DIR + "hero_autobattle.json"
	assert_true(FileAccess.file_exists(char_path),
		"_export_script() must write the character's autobattle export via ScriptShareManager")

	# Corrupt the in-editor + in-system rules so a successful import is observable.
	editor.rules = [{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "defer"}],
		"enabled": true
	}]
	editor._save_script()
	editor._refresh_grid()
	assert_eq(editor.rules.size(), 1, "precondition: rules clobbered to a single row")

	# Re-import the exported file through the editor's wiring.
	var ok = editor._import_script_file("hero_autobattle.json")
	assert_true(ok, "_import_script_file() must report success for a valid export")

	# Rules must be restored to the distinctive script (3 rows, fingerprint intact).
	assert_eq(editor.rules.size(), 3,
		"imported rules must replace the clobbered single row with the 3-rule script")
	assert_eq(editor.rules[0]["conditions"][0]["type"], "hp_percent",
		"first imported rule's condition must round-trip")
	assert_eq(editor.rules[0]["actions"][0]["type"], "defer",
		"first imported rule's action must round-trip")
	assert_eq(editor.rules[1]["actions"][0]["target"], "highest_hp_enemy",
		"second imported rule's target must round-trip")

	# And the applied script must be live in AutobattleSystem too.
	var live = AutobattleSystem.get_character_script("hero")
	assert_eq(live.get("rules", []).size(), 3,
		"import must apply the script to AutobattleSystem, not just the editor view")


func test_party_bundle_is_exported() -> void:
	# With a party present, _export_script also writes a shareable party bundle.
	var hero = autofree(Combatant.new())
	hero.combatant_name = "Hero"
	var editor = GridEditorScript.new()
	editor.size = Vector2(VIEW_W, VIEW_H)
	add_child_autofree(editor)
	editor.setup("hero", "Hero", hero, [hero])

	editor.rules = _distinctive_rules()
	editor._refresh_grid()
	editor._export_script()

	var bundle_path = ScriptShareManager.EXPORT_DIR + "party_autobattle.json"
	assert_true(FileAccess.file_exists(bundle_path),
		"_export_script() with a party must also write a party_autobattle.json bundle")

	var data = ScriptShareManager.import_file("party_autobattle.json")
	assert_eq(data.get("type"), "autobattle_bundle",
		"party export must be a recognizable autobattle_bundle")


# --- 3. Import picker is a submenu that freezes grid input -------------------

func test_open_share_picker_creates_blocking_submenu() -> void:
	var editor = _make_editor()
	# Export so the picker has at least one file to list.
	editor.rules = _distinctive_rules()
	editor._export_script()

	editor._open_share_picker()
	assert_not_null(editor._share_picker,
		"_open_share_picker() must create the picker overlay when exports exist")
	assert_true(editor._share_picker.visible,
		"picker overlay must be visible while open")

	# While the picker is open, grid navigation must NOT move the grid cursor —
	# the picker consumes input as a submenu (mirrors the VirtualKeyboard guard).
	editor.cursor_row = 0
	editor.cursor_col = 0
	var ev = InputEventAction.new()
	ev.action = "ui_down"
	ev.pressed = true
	editor._input(ev)
	assert_eq(editor.cursor_row, 0,
		"grid cursor must not move while the import picker submenu is open")

	# Closing returns control to the grid.
	editor._close_share_picker()
	assert_null(editor._share_picker, "closing must tear down the picker overlay")


func test_open_share_picker_with_no_exports_does_not_open() -> void:
	var editor = _make_editor()
	# Guarantee an empty export dir so the "no files" path is exercised in
	# isolation (other suites may have left unrelated json exports behind).
	_purge_all_exports()
	assert_eq(ScriptShareManager.list_exports().size(), 0, "precondition: no exports")

	editor._open_share_picker()
	assert_null(editor._share_picker,
		"picker must not open (and must not crash) when there are no export files")


func _purge_all_exports() -> void:
	"""Remove every .json in the export dir for an isolated 'no files' check."""
	if not DirAccess.dir_exists_absolute(ScriptShareManager.EXPORT_DIR):
		return
	for fname in ScriptShareManager.list_exports():
		DirAccess.remove_absolute(ScriptShareManager.EXPORT_DIR + fname)


# --- 4. Round-trip does not regress scroll-follow / MAX_RULES ----------------

func test_import_resets_scroll_and_respects_cap() -> void:
	var editor = _make_editor()

	# Build and export a long (capped) script, scroll to the bottom.
	editor.rules.clear()
	for i in range(editor.MAX_RULES):
		editor.rules.append({
			"conditions": [{"type": "always"}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
			"enabled": true
		})
	editor._refresh_grid()
	editor.cursor_row = editor.rules.size() - 1
	editor._update_cursor()
	assert_gt(editor._scroll_offset, 0.0, "precondition: scrolled down on a long script")

	editor._export_script()
	var ok = editor._import_script_file("hero_autobattle.json")
	assert_true(ok, "long script must import cleanly")

	# Import rebuilds the grid from the top: cursor + scroll reset, no overflow.
	assert_eq(editor.cursor_row, 0, "import must reset the grid cursor to the top")
	assert_eq(editor._scroll_offset, 0.0, "import must reset scroll to the top")
	assert_lte(editor.rules.size(), editor.MAX_RULES,
		"imported rule count must still honor the MAX_RULES cap")
