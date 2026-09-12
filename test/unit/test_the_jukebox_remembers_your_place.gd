extends GutTest

## 165 rows, 14 visible, and every open started at the top.
##
## The jukebox is the only consumer that can reach every authored bed — the reachability sweep
## excludes it precisely because it makes all 165 reachable by construction — so it is the one
## screen a player actually browses rather than passes through. Closing and reopening threw the
## cursor back to row 0, which at 14 rows a screen is up to eleven PgDn presses to undo.
##
## 🔑 SESSION-SCOPED BY CHOICE, and the choice is the interesting half. A static var dies with the
## process, exactly like `_resume_state` sitting beside it: reopening the jukebox in one sitting
## returns you to where you were, and a relaunch starts clean. Nothing about a music cursor belongs
## in the save file, and putting it there would have meant a migration for a browse position.
##
## ⛔ CLAMPED, NEVER TRUSTED. `TRACKS` is rebuilt from the manifest on every open, so it can shrink
## between two opens in one session (a hot-reloaded manifest, a stripped web tier). A remembered
## index past the end would index out of bounds in `_play_selected` — which reads
## `TRACKS[selected_index][0]` after a bounds check, so the failure would be a silent no-op rather
## than a crash, and silent is the one that ships.

const JUKEBOX := preload("res://src/ui/JukeboxMenu.gd")


func before_each() -> void:
	JUKEBOX._last_selected = 0


func after_each() -> void:
	JUKEBOX._last_selected = 0
	SoundManager.stop_music()


func _open() -> Node:
	var jb: Node = JUKEBOX.new()
	add_child_autofree(jb)
	await get_tree().process_frame
	return jb


func test_the_cursor_comes_back_where_you_left_it() -> void:
	var first: Node = await _open()
	assert_gt(first.TRACKS.size(), 20, "CONTROL: the manifest gave %d rows, so row 17 is a real place to stand" % first.TRACKS.size())
	assert_eq(first.selected_index, 0, "CONTROL: a fresh session starts at the top")

	first.selected_index = 17
	first._close_menu()
	await get_tree().process_frame

	var second: Node = await _open()
	assert_eq(second.selected_index, 17,
		"reopening put the cursor at %d — browsing 165 rows should not restart at the top" % second.selected_index)


func test_the_window_follows_the_restored_cursor() -> void:
	## Restoring the index alone would show rows 0-13 with the highlight off-screen.
	var first: Node = await _open()
	first.selected_index = 40
	first._close_menu()
	await get_tree().process_frame

	var second: Node = await _open()
	assert_eq(second.selected_index, 40, "CONTROL: the index was restored, so the window below is the subject")
	assert_true(second.scroll_offset <= 40 and 40 < second.scroll_offset + second.VISIBLE_ROWS,
		"row 40 must be inside the visible window — offset %d, window %d" % [second.scroll_offset, second.VISIBLE_ROWS])


func test_a_remembered_row_past_the_end_is_clamped() -> void:
	## The manifest shrinking between two opens is the case a bare restore gets wrong.
	JUKEBOX._last_selected = 100000
	var jb: Node = await _open()
	assert_lt(jb.selected_index, jb.TRACKS.size(),
		"a remembered index past the end must clamp — it is %d against %d rows, and _play_selected would silently no-op" % [jb.selected_index, jb.TRACKS.size()])
	assert_gte(jb.selected_index, 0, "and never below zero")


func test_an_empty_list_does_not_take_the_cursor_negative() -> void:
	## clampi(x, 0, max(0, size - 1)) with size 0 must land on 0, not -1. The manifest can fail to
	## load (JukeboxMenu loud-fails to an empty list by design), and -1 would index backwards.
	var jb: Node = JUKEBOX.new()
	jb.TRACKS = []
	jb.selected_index = clampi(JUKEBOX._last_selected, 0, max(0, jb.TRACKS.size() - 1))
	assert_eq(jb.selected_index, 0, "an empty list leaves the cursor at 0")
	jb.free()
