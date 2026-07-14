extends GutTest

## When Continue from the title screen failed (save load returned false,
## or the loaded GameState had an empty player_party), the code silently
## fell through to _create_party() — a fresh game. The player saw their
## progress 'disappear' with no explanation.
##
## Fix: emit a Toast warning naming WHY Continue failed before the
## fallback runs. The player at least knows the save couldn't load
## instead of assuming the game lost their data.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(GAME_LOOP_PATH)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_on_title_continue_toasts_on_failure() -> void:
	var body := _body_of("_on_title_continue")
	assert_true(body.contains("Toast.show_warning"),
		"Continue failure path must Toast — silent fallback to default party was a UX trap")
	# Reason string must distinguish 'no save' vs 'load failed' vs 'party empty'.
	assert_true(body.contains("no save found"),
		"failure reason must distinguish the no-save case")
	assert_true(body.contains("save load failed"),
		"failure reason must distinguish the load-failed case")
	assert_true(body.contains("save restored but party data was empty"),
		"failure reason must distinguish the empty-party case")


func test_fallback_party_still_created() -> void:
	# Defensive: even with the Toast, the fallback must still run — the
	# player should land in a playable state, not stranded on a blank
	# screen with only a warning toast. Walk the function line-by-line
	# and skip comments so a stale `_create_party()` in a docstring or
	# code comment can't be mistaken for the real call site.
	var body := _body_of("_on_title_continue")
	var lines := body.split("\n")
	var toast_line := -1
	var party_line := -1
	for i in range(lines.size()):
		var s: String = str(lines[i]).strip_edges()
		if s.begins_with("#"):
			continue
		if toast_line < 0 and s.begins_with("Toast.show_warning"):
			toast_line = i
		if party_line < 0 and s == "_create_party()":
			party_line = i
	assert_gt(toast_line, -1, "Toast call must exist as a real statement")
	assert_gt(party_line, -1, "_create_party fallback must still exist as a real statement")
	assert_lt(toast_line, party_line,
		"Toast must fire before the fresh party is built (so the user sees the warning while transitioning)")
