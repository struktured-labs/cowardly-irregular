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


func test_close_restores_only_when_menu_still_current() -> void:
	## The guard is load-bearing per cowir-main msg 2687: if underlying music
	## changed while the menu was open (autogrind end, story flag, stinger
	## resume), restoring _pre_menu_music_track would stomp the legitimate swap.
	var src := _read(GAMELOOP)
	var fn_start: int = src.find("func _on_overworld_menu_closed")
	assert_gt(fn_start, -1, "_on_overworld_menu_closed must exist")
	var next_fn: int = src.find("\nfunc ", fn_start + 1)
	var body: String = src.substr(fn_start, next_fn - fn_start) if next_fn > -1 else src.substr(fn_start)
	assert_true(body.contains("_pre_menu_music_track != \"\""),
		"_on_overworld_menu_closed must skip restore when _pre_menu_music_track was never set (idempotent close)")
	assert_true(body.contains("SoundManager._current_music == \"menu\""),
		"_on_overworld_menu_closed must guard the restore on _current_music == \"menu\" (cowir-main msg 2687: don't stomp a legitimate underlying swap)")
	assert_true(body.contains("SoundManager.play_music(_pre_menu_music_track)"),
		"_on_overworld_menu_closed must call play_music with the snapshot when the guard passes")
	assert_true(body.contains("_pre_menu_music_track = \"\""),
		"_on_overworld_menu_closed must clear _pre_menu_music_track after use (avoids stale-snapshot bugs on a subsequent pause)")
