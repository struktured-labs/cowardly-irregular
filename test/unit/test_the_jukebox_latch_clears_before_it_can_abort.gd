extends GutTest

## _play_selected sets `_generating = true`, awaits two frames, then plays the track. The latch
## exists to cover THAT await window — nothing after it is asynchronous.
##
## ⛔ IT USED TO BE CLEARED LAST, BELOW `SoundManager.play_music()`. A GDScript error aborts its
## enclosing function, so an error inside play_music left `_generating` true with no path back:
## `:333` refuses every later play, and the input guard swallows ui_up / ui_down / ui_accept.
## Back still works (it is deliberately exempt), so the symptom is a jukebox that answers only
## Cancel until the player closes and reopens it — SettingsMenu builds a fresh instance each
## time, which is the only reason this is per-open rather than per-session.
##
## 🔑 A SOURCE-ORDER RATCHET, like test_interior_music_routing's guard-before-stop_music arm,
## because the defect IS the order and the abort that reveals it cannot be staged from a test:
## play_music would have to fail, and a SoundManager that fails on demand is a different subject.

const JUKEBOX := "res://src/ui/JukeboxMenu.gd"


func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	assert_not_null(f, "could not open %s" % p)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## The body of one function, so an occurrence elsewhere in the file cannot answer for this one.
func _func_body(src: String, fname: String) -> String:
	var lines := src.split("\n")
	var start := -1
	for i in range(lines.size()):
		if lines[i].begins_with("func %s(" % fname):
			start = i
			break
	assert_gt(start, -1, "func %s not found — renamed? this ratchet is now about nothing" % fname)
	if start == -1:
		return ""
	for j in range(start + 1, lines.size()):
		if lines[j].begins_with("func "):
			return "\n".join(lines.slice(start, j))
	return "\n".join(lines.slice(start))


func test_the_latch_is_released_above_the_call_that_can_abort() -> void:
	var body := _func_body(_read(JUKEBOX), "_play_selected")
	var lines := body.split("\n")

	## The MAIN-PATH release is the one at a single tab. The other `_generating = false` sits two
	## tabs in, on the build-excluded-track branch, which returns and cannot reach play_music.
	var release := -1
	var plays := -1
	for i in range(lines.size()):
		if lines[i] == "\t_generating = false" and release == -1:
			release = i
		if lines[i].contains("SoundManager.play_music(") and plays == -1:
			plays = i

	assert_gt(release, -1,
		"no main-path `_generating = false` in _play_selected — the latch is never released on the normal path")
	assert_gt(plays, -1,
		"CONTROL: _play_selected must still call SoundManager.play_music, or this ratchet guards nothing")
	assert_lt(release, plays,
		"the latch is released at line %d of _play_selected, BELOW play_music at line %d — an abort in play_music strands `_generating` true, and the menu then answers only Cancel until it is reopened" % [release, plays])


func test_control_the_latch_still_guards_the_await_window() -> void:
	## The fix must not have moved the release ABOVE the awaits it exists to cover — that would
	## leave the double-entry the latch was added for. Both awaits must precede the release.
	var body := _func_body(_read(JUKEBOX), "_play_selected")
	var lines := body.split("\n")
	var raise := -1
	var release := -1
	var last_await := -1
	for i in range(lines.size()):
		if lines[i] == "\t_generating = true":
			raise = i
		if lines[i] == "\t_generating = false" and release == -1:
			release = i
		if lines[i].contains("await "):
			last_await = i

	assert_gt(raise, -1, "CONTROL: _play_selected must still raise the latch")
	assert_gt(last_await, -1, "CONTROL: _play_selected must still await — the latch exists for that window")
	assert_lt(raise, last_await,
		"the latch is raised at %d but the last await is at %d — it no longer covers the window it was added for" % [raise, last_await])
	assert_lt(last_await, release,
		"the latch is released at %d, BEFORE the last await at %d — the double-entry it guards against is back" % [release, last_await])
