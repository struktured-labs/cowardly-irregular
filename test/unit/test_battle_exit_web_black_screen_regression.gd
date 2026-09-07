extends GutTest

## Real gameplay regression: GameLoop's battle-exit and autogrind-teardown
## paths must AWAIT _return_to_exploration() — that function is async
## (it awaits the scene-swap _start_exploration), and calling it without
## await lets the next line run BEFORE the new scene is in the tree.
##
## Player report (2026-06-17, Android Samsung / Brave browser):
##   "the web version freezes after a battle exits, or is really slow,
##    not sure which. black screen on my android samsung galaxy phone"
##
## Bug shape:
##   await BattleTransition.play_exit_transition(true)
##   _return_to_exploration()              # ← NOT awaited
##   await BattleTransition.reveal_exploration()
##
##   On desktop the scene swap completes in ~1 frame so reveal_exploration's
##   fade-from-black happens to land just as the new scene appears — no
##   visible artifact. On Android web (Brave especially) the scene
##   instantiation can take 2-5 SECONDS; reveal_exploration starts
##   immediately, fades the iris from black to transparent while nothing
##   is in the tree, and the player stares at a black render until the
##   scene finally appears.
##
## Fix: `await _return_to_exploration()`. The same shape repeats in three
## autogrind teardown / pause paths in GameLoop.gd — fixed in the same
## commit to keep mobile autogrind from flashing summary overlays
## against a half-loaded scene.
##
## Source pins (the GUT runtime can't drive a real scene swap to
## reproduce the race; source pins lock the bug-shape):
##   • _on_battle_ended awaits _return_to_exploration
##   • The other three call sites (autogrind stop x2, pause) also await
##   • No raw `_return_to_exploration()` call outside the function
##     definition itself

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ──────────────────────────────────────────────────────────────

func test_battle_ended_awaits_return_to_exploration() -> void:
	# This is the user-reported site. _on_battle_ended runs at the end of
	# every battle (the most common path), so the await fix lands on
	# every player on every fight.
	var text := _read(GAME_LOOP_PATH)
	var idx := text.find("func _on_battle_ended")
	assert_gt(idx, -1, "_on_battle_ended must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("await _return_to_exploration"),
		"_on_battle_ended must `await _return_to_exploration()` — otherwise reveal_exploration fires before the scene is in the tree and the player sees a black screen on slow scene-load platforms (Android web)")


func test_no_unawaited_return_to_exploration_call_in_source() -> void:
	# Walk all non-comment lines and confirm every call to
	# _return_to_exploration() is preceded by `await ` (or is the
	# function definition itself). Catches future regressions where a
	# new call site is added without await.
	var text := _read(GAME_LOOP_PATH)
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line: String = str(lines[i]).strip_edges()
		# Skip comments + the function definition itself.
		if line.begins_with("#") or line.begins_with("func _return_to_exploration"):
			continue
		# Look for a call that is NOT prefixed by `await `.
		var call_idx := line.find("_return_to_exploration(")
		if call_idx == -1:
			continue
		var prefix := line.substr(0, call_idx).strip_edges(false, true)
		# Acceptable prefixes: "await " or chained ".".
		var has_await: bool = prefix.ends_with("await") or prefix.find("await ") != -1
		# Allow assignment-target / variable-name references — those aren't
		# call sites. We're looking for `(`-terminated calls only.
		assert_true(has_await,
			"Line %d calls _return_to_exploration() without `await` — this causes a black screen on Android web after battle exit. Line: %s" % [i + 1, line])
