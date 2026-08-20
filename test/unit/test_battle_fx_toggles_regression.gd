extends GutTest

## The "ridiculous menu of toggles" (struktured 2026-08-14): every juice feature gets a
## per-flag toggle. Pins: GameState sparse overrides outrank BattleJuice defaults, the
## settings menu builds one row per registered flag with a generic fx_ handler, flags
## persist beside the other settings, and every registered flag is actually CONSUMED
## somewhere (a toggle wired to nothing is the menu lying).

const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")


func after_each() -> void:
	if GameState:
		GameState.battle_fx_flags.clear()
	BattleJuice.flags.clear()


func test_gamestate_override_outranks_default() -> void:
	assert_true(BattleJuice.flag("camera_zoom"), "defaults true")
	GameState.battle_fx_flags["camera_zoom"] = false
	assert_false(BattleJuice.flag("camera_zoom"), "GameState sparse override wins")
	GameState.battle_fx_flags.erase("camera_zoom")
	assert_true(BattleJuice.flag("camera_zoom"), "erasing the override restores the default")


func test_menu_registry_and_handler() -> void:
	var flags: Array = SettingsMenuScript.BATTLE_FX_FLAGS
	assert_gte(flags.size(), 12, "the menu is appropriately ridiculous (12+ toggles)")
	var names := []
	for fx in flags:
		assert_eq(fx.size(), 3, "each entry is [key, label, description]")
		assert_false(fx[0] in names, "flag keys unique")
		names.append(fx[0])
	assert_true("steal_sauce" in names, "control: a known flag is registered")
	var src := FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	assert_true('begins_with("fx_")' in src, "generic handler covers every row — no per-flag elif sprawl")
	assert_true("save_settings" in src.substr(src.find('begins_with("fx_")'), 600), "toggling persists immediately")


func test_flags_persist_with_settings() -> void:
	var src := FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	assert_true('"battle_fx_flags"' in src, "flags in the settings dict")
	assert_true('settings["battle_fx_flags"] is Dictionary' in src, "load is type-guarded against corrupt files")


func test_every_registered_flag_is_consumed() -> void:
	# A toggle wired to nothing is the menu lying — every key must appear in a flag() call somewhere in src/
	# Scan the whole presentation surface, not a hand-list: the list went stale the first
	# time a consumer landed in a file nobody remembered to add (BattleCommandMenu, 2026-08-14).
	var consumers := ""
	for dir_path in ["res://src/battle", "res://src/ui"]:
		consumers += _concat_gd_files(dir_path)
	assert_true('flag("' in consumers, "CONTROL: the scan actually found flag() calls")
	for fx in SettingsMenuScript.BATTLE_FX_FLAGS:
		assert_true('flag("%s")' % fx[0] in consumers, "flag '%s' has a live consumer" % fx[0])


func _concat_gd_files(dir_path: String) -> String:
	var out := ""
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out += FileAccess.get_file_as_string(dir_path + "/" + f)
	for sub in d.get_directories():
		out += _concat_gd_files(dir_path + "/" + sub)
	return out
