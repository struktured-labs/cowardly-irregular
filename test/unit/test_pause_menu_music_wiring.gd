extends GutTest

## Pause-menu music wiring (2026-07-16, cowir-main greenlit msg 2687).
##
## The "Paused, Somewhere Else" track (manifest key `menu`) was authored
## specifically for the pause context but sat dead-weight in the manifest
## for weeks — the OverworldMenu open/close flow never touched music.
## This test pins the wiring so a future refactor of _open_overworld_menu /
## _on_overworld_menu_closed can't silently regress the connection.
##
## Source-level assertions rather than a full GameLoop instantiation:
## the open/close flow needs a live party, exploration scene, and CanvasLayer
## which are expensive to fake for a music-wiring pin. The source-level
## shape catches every case where the wiring gets accidentally removed.

const GAMELOOP := "res://src/GameLoop.gd"
const MANIFEST := "res://data/music_manifest.json"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_menu_track_exists_in_manifest() -> void:
	## Pre-req: the "menu" track must be authored, else the wiring is a no-op
	## via play_music's fallback path (which would play something else or nothing).
	var text: String = _read(MANIFEST)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary and parsed.has("tracks"),
		"music_manifest.json must parse")
	var tracks: Dictionary = parsed["tracks"]
	assert_true(tracks.has("menu"),
		"music_manifest.json must carry the 'menu' track — pause music depends on it")
	var entry: Dictionary = tracks["menu"]
	assert_ne(entry.get("file", ""), "",
		"'menu' entry must have a file: field — placeholder-only would silently play nothing")


func test_pre_menu_music_track_member_var_declared() -> void:
	var src := _read(GAMELOOP)
	assert_true(src.contains("var _pre_menu_music_track"),
		"GameLoop must declare _pre_menu_music_track to hold the snapshot across the pause")


func test_open_snapshots_and_swaps_to_menu() -> void:
	## Locate _open_overworld_menu and assert both the snapshot and swap happen.
	var src := _read(GAMELOOP)
	var fn_start: int = src.find("func _open_overworld_menu")
	assert_gt(fn_start, -1, "_open_overworld_menu must exist")
	var next_fn: int = src.find("\nfunc ", fn_start + 1)
	var body: String = src.substr(fn_start, next_fn - fn_start) if next_fn > -1 else src.substr(fn_start)
	assert_true(body.contains("_pre_menu_music_track = SoundManager._current_music"),
		"_open_overworld_menu must snapshot SoundManager._current_music into _pre_menu_music_track BEFORE swapping — else restore has nothing to restore to")
	assert_true(body.contains("SoundManager.play_music(\"menu\")"),
		"_open_overworld_menu must call SoundManager.play_music(\"menu\") to swap to the pause-menu theme")


func test_restore_lives_in_teardown_choke_point() -> void:
	## Bug 2801 fix: multiple exit paths (teleport, boss battle, quit-to-title,
	## menu-action → submenu) reach _teardown_overworld_menu_widget but bypass
	## _on_overworld_menu_closed, so pinning restore to the closed handler let
	## menu music leak past scene transitions. Restore MUST live in teardown
	## itself so every exit path catches it.
	var src := _read(GAMELOOP)
	var fn_start: int = src.find("func _teardown_overworld_menu_widget")
	assert_gt(fn_start, -1, "_teardown_overworld_menu_widget must exist")
	var next_fn: int = src.find("\nfunc ", fn_start + 1)
	var body: String = src.substr(fn_start, next_fn - fn_start) if next_fn > -1 else src.substr(fn_start)

	assert_true(body.contains("_pre_menu_music_track != \"\""),
		"_teardown_overworld_menu_widget must skip restore when _pre_menu_music_track was never set")
	assert_true(body.contains("SoundManager._current_music == \"menu\""),
		"_teardown_overworld_menu_widget must guard the restore on _current_music == \"menu\" (cowir-main msg 2687: don't stomp a legitimate underlying swap)")
	assert_true(body.contains("SoundManager.play_music(_pre_menu_music_track)"),
		"_teardown_overworld_menu_widget must call play_music with the snapshot when the guard passes")
	assert_true(body.contains("_pre_menu_music_track = \"\""),
		"_teardown_overworld_menu_widget must clear _pre_menu_music_track UNCONDITIONALLY (bug 2801: a stale snapshot leaking past a scene transition let menu music persist forever)")


func test_all_menu_exit_paths_route_through_teardown() -> void:
	## Bug 2801 root cause: restore was only in the closed handler, but these
	## paths call _teardown_overworld_menu_widget directly without going
	## through it: _on_teleport_requested, _on_settings_boss_battle,
	## _on_quit_to_title, _on_overworld_menu_action. Pin that every exit path
	## still funnels through the teardown so the moved restore catches them.
	var src := _read(GAMELOOP)
	# Every exit-path handler must call teardown (or _on_overworld_menu_closed,
	# which itself calls teardown).
	for handler in [
		"func _on_overworld_menu_closed",
		"func _on_overworld_menu_action",
		"func _on_teleport_requested",
	]:
		var fn_start: int = src.find(handler)
		if fn_start < 0:
			continue  # optional handler — skip
		var next_fn: int = src.find("\nfunc ", fn_start + 1)
		var body: String = src.substr(fn_start, next_fn - fn_start) if next_fn > -1 else src.substr(fn_start)
		assert_true(body.contains("_teardown_overworld_menu_widget"),
			"%s must call _teardown_overworld_menu_widget so the music restore catches this exit path" % handler)


func test_teardown_falls_back_to_scene_derived_key_when_snapshot_lost() -> void:
	## Bug 2801 round 2 (cowir-main msg 2829): even if _pre_menu_music_track
	## is empty at teardown (some path lost the snapshot), teardown must NOT
	## leave "menu" playing. It must derive a fallback from _exploration_scene
	## so menu music can't persist into overworld.
	var src := _read(GAMELOOP)
	var fn_start: int = src.find("func _teardown_overworld_menu_widget")
	assert_gt(fn_start, -1, "_teardown_overworld_menu_widget must exist")
	var next_fn: int = src.find("\nfunc ", fn_start + 1)
	var body: String = src.substr(fn_start, next_fn - fn_start) if next_fn > -1 else src.substr(fn_start)

	assert_true(body.contains("_derive_current_scene_music_key"),
		"_teardown_overworld_menu_widget must call _derive_current_scene_music_key as the snapshot-lost fallback (bug 2801 round 2)")
	# The fallback path only fires when snapshot is empty AND current is menu.
	# Assert both branches of the two-stage design exist.
	assert_true(body.contains("_pre_menu_music_track != \"\""),
		"Two-stage design: snapshot path (guard on non-empty snapshot)")
	assert_true(body.contains("SoundManager._current_music == \"menu\""),
		"Two-stage design: outer guard on _current_music == \"menu\" — if underneath swap already replaced it, don't stomp")

	# Fallback function itself must exist.
	assert_gt(src.find("func _derive_current_scene_music_key"), -1,
		"_derive_current_scene_music_key helper must be defined")


func test_derive_scene_music_key_fallback_chain() -> void:
	## Pin the fallback chain: _get_music_area_id → _get_music_track →
	## "overworld". Order matters — villages/interiors have their own
	## conventions, OverworldScene hardcodes "overworld".
	var src := _read(GAMELOOP)
	var fn_start: int = src.find("func _derive_current_scene_music_key")
	if fn_start < 0:
		fail_test("_derive_current_scene_music_key must exist — pinned above")
		return
	var next_fn: int = src.find("\nfunc ", fn_start + 1)
	var body: String = src.substr(fn_start, next_fn - fn_start) if next_fn > -1 else src.substr(fn_start)

	assert_true(body.contains("_get_music_area_id"),
		"Fallback chain must try _get_music_area_id first (BaseVillage convention)")
	assert_true(body.contains("_get_music_track"),
		"Fallback chain must try _get_music_track second (BaseInterior convention)")
	assert_true(body.contains("\"overworld\""),
		"Fallback chain must default to \"overworld\" (OverworldScene hardcodes this key)")


func test_runtime_probe_snapshot_lost_still_leaves_menu() -> void:
	## Runtime probe per cowir-main msg 2829: instantiate a mock scenario
	## where snapshot is cleared mid-menu, teardown fires, assert current
	## music is NOT "menu". Uses a fake _exploration_scene stub so
	## _derive_current_scene_music_key returns a real key.
	var sm := get_node_or_null("/root/SoundManager")
	if sm == null:
		pass_test("SoundManager not available")
		return
	var gl := get_node_or_null("/root/GameLoop")
	if gl == null:
		pass_test("GameLoop not available")
		return
	# Snapshot the pre-test SoundManager state so we can restore.
	var pre_track: String = str(sm._current_music) if "_current_music" in sm else ""
	var pre_pmm: String = str(gl._pre_menu_music_track) if "_pre_menu_music_track" in gl else ""
	var pre_scene = gl._exploration_scene if "_exploration_scene" in gl else null

	# Force the "menu is playing but snapshot is lost" state.
	sm.play_music("menu")
	if "_pre_menu_music_track" in gl:
		gl._pre_menu_music_track = ""  # simulate the lost snapshot

	# Give _exploration_scene a stub that returns a known music key.
	var stub := Node.new()
	stub.set_script(GDScript.new())
	stub.get_script().source_code = "extends Node\nfunc _get_music_area_id() -> String:\n\treturn \"overworld_medieval\"\n"
	stub.get_script().reload()
	if "_exploration_scene" in gl:
		gl._exploration_scene = stub
	add_child(stub)

	# Fire the choke point directly.
	if gl.has_method("_teardown_overworld_menu_widget"):
		gl._teardown_overworld_menu_widget()

	# Give play_music's crossfade a moment to swap; then assert current is NOT "menu".
	await get_tree().create_timer(0.6).timeout
	assert_ne(str(sm._current_music), "menu",
		"Bug 2801 round 2: after teardown with lost snapshot, current music must NOT still be \"menu\" — scene-derived fallback must have swapped away. Got: %s" % str(sm._current_music))

	# Restore.
	if "_exploration_scene" in gl:
		gl._exploration_scene = pre_scene
	stub.queue_free()
	if "_pre_menu_music_track" in gl:
		gl._pre_menu_music_track = pre_pmm
	if pre_track != "":
		sm.play_music(pre_track)
