extends GutTest

## Regression: loading a save from the in-game OverworldMenu -> SaveScreen
## (Mode.LOAD) never rehydrated the live battle party.
##
## Bug (verified 2026-06-14):
##   SaveScreen Mode.LOAD calls SaveSystem.load_game(slot), which writes into
##   GameState — including GameState.player_party (the dict array), gold,
##   story flags and the saved map/position — then emits load_completed(slot).
##   That signal connects ONLY to OverworldMenu._on_load_completed, which used
##   to just call _close_menu(). It never rebuilt GameLoop.party, the live
##   Array[Combatant] that battles (battle_scene.set_party(party),
##   resolver.resolve_battle(party, ...)) and menus consume.
##
##   The title-screen Continue (GameLoop._on_title_continue), the Game-Over
##   Continue, and the F3 quick-load (GameLoop._quick_load_with_toast) all call
##   GameLoop._restore_party_from_save_data() after load_game. The in-game menu
##   Load path did not — so after loading an earlier save to undo a mistake the
##   player silently kept their post-mistake Combatants (HP/MP/level/job/
##   equipment) while the rest of the world reflected the loaded save. A silent
##   state desync (CLAUDE.md: "silent failures are worse than crashes").
##
## Fix:
##   OverworldMenu._on_load_completed now calls _rehydrate_party_after_load(),
##   which locates the GameLoop root via the canonical /root/GameLoop lookup
##   (same idiom as OverworldPlayer) and calls _restore_party_from_save_data()
##   + _start_exploration() — mirroring the quick-load flow — before closing
##   the menu. SaveScreen's signal contract is unchanged (it already emits
##   load_completed correctly); the gap was OverworldMenu swallowing it.

const OVERWORLD_MENU_PATH := "res://src/ui/OverworldMenu.gd"
const SAVESCREEN_PATH := "res://src/ui/SaveScreen.gd"
const OverworldMenuScript := preload("res://src/ui/OverworldMenu.gd")


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _func_body(src: String, fn_signature: String) -> String:
	# Slice a function body from its signature up to the next top-level func.
	var idx = src.find(fn_signature)
	if idx < 0:
		return ""
	var rest = src.substr(idx)
	var next_func = rest.find("\nfunc ", 1)
	if next_func > 0:
		rest = rest.substr(0, next_func)
	return rest


func test_on_load_completed_rehydrates_party_not_just_closes() -> void:
	# The core regression: _on_load_completed must rebuild the live party, not
	# merely close the menu. Pre-fix the entire body was `_close_menu()`.
	var src = _read(OVERWORLD_MENU_PATH)
	var body = _func_body(src, "func _on_load_completed(")
	assert_ne(body, "", "_on_load_completed must exist in OverworldMenu")
	assert_string_contains(body, "_rehydrate_party_after_load()",
		"_on_load_completed must rehydrate the live party after an in-game " +
		"load (regression: pre-fix it only called _close_menu(), leaving " +
		"GameLoop.party stale while GameState reflected the loaded save).")
	assert_string_contains(body, "_close_menu()",
		"_on_load_completed must still close the menu after rehydrating.")


func test_rehydrate_helper_calls_gameloop_restore() -> void:
	# The helper must route to GameLoop._restore_party_from_save_data — the
	# same method the title-Continue / Game-Over / quick-load paths use.
	var src = _read(OVERWORLD_MENU_PATH)
	var body = _func_body(src, "func _rehydrate_party_after_load(")
	assert_ne(body, "", "_rehydrate_party_after_load helper must exist")
	# Canonical GameLoop lookup (matches OverworldPlayer's /root/GameLoop idiom).
	assert_string_contains(body, "/root/GameLoop",
		"_rehydrate_party_after_load must locate GameLoop via the canonical " +
		"/root/GameLoop lookup (matches OverworldPlayer).")
	assert_string_contains(body, "_restore_party_from_save_data",
		"_rehydrate_party_after_load must call GameLoop._restore_party_from_save_data " +
		"to rebuild the live Array[Combatant] from GameState.player_party.")
	# Must guard the method existence before calling (safe outside the loop).
	assert_string_contains(body, "has_method(\"_restore_party_from_save_data\")",
		"_rehydrate_party_after_load must guard has_method before dereferencing " +
		"the GameLoop root (no-op when menu is opened outside the normal loop).")


func test_rehydrate_restarts_exploration_to_apply_saved_position() -> void:
	# Mirrors GameLoop._quick_load_with_toast: re-enter exploration so the
	# player warps to the loaded map/position, only when already exploring.
	var src = _read(OVERWORLD_MENU_PATH)
	var body = _func_body(src, "func _rehydrate_party_after_load(")
	assert_string_contains(body, "_start_exploration",
		"_rehydrate_party_after_load must restart exploration so the loaded " +
		"map/position is applied to the live scene (mirrors quick-load).")
	assert_string_contains(body, "LoopState.EXPLORATION",
		"Exploration restart must be gated on current_state == EXPLORATION " +
		"(don't re-enter exploration from non-exploration contexts).")


func test_savescreen_load_path_emits_load_completed() -> void:
	# SaveScreen's contract is unchanged and correct: Mode.LOAD calls
	# load_game then emits load_completed. Pin it so the fix's upstream
	# assumption doesn't silently regress.
	var src = _read(SAVESCREEN_PATH)
	var body = _func_body(src, "func _handle_confirm(")
	assert_ne(body, "", "SaveScreen._handle_confirm must exist")
	assert_string_contains(body, "SaveSystem.load_game(slot)",
		"SaveScreen Mode.LOAD must call SaveSystem.load_game(slot).")
	assert_string_contains(body, "load_completed.emit(slot)",
		"SaveScreen must emit load_completed(slot) so OverworldMenu can " +
		"rehydrate the live party.")


func test_rehydrate_is_safe_noop_without_gameloop_root() -> void:
	# Runtime: instantiate the menu standalone (no /root/GameLoop present in
	# the test tree) and confirm the helper is a guarded no-op rather than
	# crashing. This also proves the new method parses and is callable.
	var menu = OverworldMenuScript.new()
	add_child_autofree(menu)
	# No /root/GameLoop in the GUT scene tree, so the helper must bail cleanly.
	assert_true(menu.has_method("_rehydrate_party_after_load"),
		"OverworldMenu must expose _rehydrate_party_after_load")
	menu._rehydrate_party_after_load()  # Must not crash.
	assert_true(menu.has_method("_on_load_completed"),
		"OverworldMenu must expose _on_load_completed")
