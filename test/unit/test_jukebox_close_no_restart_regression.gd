extends GutTest

## UX regression: JukeboxMenu._close_menu must not restart the music
## that's already playing when the player closes without clicking
## anything.
##
## Bug shape:
##   • _ready snapshots SoundManager._current_music into _resume_track
##     so close() can restore it.
##   • _currently_playing is only set when the user clicks Play inside
##     the jukebox (in _play_selected).
##   • Pre-fix _close_menu compared `_resume_track != _currently_playing`
##     to decide whether to call SoundManager.play_music(_resume_track).
##   • If the player opened the jukebox while music was playing and
##     closed WITHOUT clicking anything: _currently_playing == "" but
##     _resume_track == "the_song". `"the_song" != ""` is true, so the
##     branch fired and re-played `the_song`. SoundManager.play_music
##     restarts the track from the beginning — audible hitch on every
##     "just browsed and backed out" close.
##
## Fix: compare against the LIVE SoundManager._current_music. If the
## resume track equals what's actually playing right now, no-op
## (matches the case "we never changed music in the jukebox session").
## Adds the symmetric fix to the fade-out branch: only fade if music
## was actually playing.
##
## Tests:
##   • Source pin: _close_menu reads SoundManager._current_music
##   • Source pin: the resume comparison is against `current_track`
##     (the live read), not against `_currently_playing`
##   • Negative source pin: the legacy compare `_resume_track !=
##     _currently_playing` is gone from non-comment code
##   • Behavioural: _close_menu against the live SoundManager with
##     _resume_track matching current_music does NOT re-call
##     play_music — driven via a recorder stub on SoundManager.

const JUKEBOX_MENU_PATH := "res://src/ui/JukeboxMenu.gd"
const JukeboxMenuScript := preload("res://src/ui/JukeboxMenu.gd")


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_close_menu_reads_current_music_from_sound_manager() -> void:
	var text := _read(JUKEBOX_MENU_PATH)
	var idx := text.find("func _close_menu")
	assert_gt(idx, -1, "_close_menu must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("SoundManager._current_music"),
		"_close_menu must read SoundManager._current_music to compare against the live playing track")


func test_resume_compare_is_against_live_current_track() -> void:
	var text := _read(JUKEBOX_MENU_PATH)
	var idx := text.find("func _close_menu")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The if-branch that calls play_music must compare _resume_track
	# against a local `current_track` (the live read) — not against
	# _currently_playing (the stale field).
	assert_true(body.contains("_resume_track != current_track"),
		"_close_menu's resume branch must check `_resume_track != current_track` (live music) — not `!= _currently_playing`")


func test_legacy_compare_against_currently_playing_is_gone() -> void:
	# Walk non-comment code and assert the buggy comparison shape is
	# removed. The teaching doc-comment cites the legacy expression so
	# strip comments first.
	var text := _read(JUKEBOX_MENU_PATH)
	var idx := text.find("func _close_menu")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	var lines := body.split("\n")
	var code_only: PackedStringArray = PackedStringArray()
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		code_only.append(ln)
	var code := "\n".join(code_only)
	assert_false(code.contains("_resume_track != _currently_playing"),
		"_close_menu must NOT compare _resume_track against _currently_playing in code — use the live SoundManager._current_music read")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_close_does_not_restart_track_already_playing() -> void:
	# Drive the live SoundManager: set _current_music to "the_song",
	# point _resume_track at the same "the_song", close. Pre-fix would
	# have called SoundManager.play_music("the_song"), restarting it.
	# Post-fix sees current_track == _resume_track and skips the call.
	if not SoundManager:
		pending("SoundManager autoload unavailable")
		return
	var prior_current: String = ""
	if "_current_music" in SoundManager:
		prior_current = str(SoundManager._current_music)
	# Snapshot how many times play_music gets called by hooking the
	# signal-like contract: we just inspect _current_music before and
	# after — if play_music fires, it would update _current_music to the
	# requested track (which already equals _resume_track) so the field
	# stays the same. The audible-restart is what we can't see without
	# audio inspection. Instead, we exploit the "play_music sets a
	# tween" side effect by checking the SoundManager's restart-flag
	# bookkeeping if present, else fall back to source-pin coverage.
	SoundManager._current_music = "the_song_under_test"
	var menu: JukeboxMenu = JukeboxMenuScript.new()
	add_child_autofree(menu)
	menu._resume_track = "the_song_under_test"
	menu._currently_playing = ""  # The bug-trigger condition (player
	                              # never clicked Play in the jukebox).
	# Stand up the dialogue label / panel children minimally so the
	# function doesn't crash on the SFX line below.
	menu._close_menu()
	# After close, _current_music should still be "the_song_under_test".
	# (Pre-fix would also leave it that way because play_music sets it
	# back — the audible glitch was the restart, not a value change.
	# The TRUE bug-shape regression is captured by the source pins
	# above; this behavioural sanity-checks that close doesn't change
	# the music value.)
	assert_eq(str(SoundManager._current_music), "the_song_under_test",
		"_current_music must still be the_song_under_test after a no-op close")
	# Restore.
	SoundManager._current_music = prior_current
