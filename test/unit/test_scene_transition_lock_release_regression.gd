extends GutTest

## Regression: SceneTransition.transition_from_battle() must release the
## "battle_transition" InputLockManager lock UNCONDITIONALLY — not gate
## it on the player node being non-null.
##
## Bug shape:
##   • transition_to_battle pushes the lock at the very top, before any
##     player guards.
##   • transition_from_battle used to release it INSIDE `if player:`.
##     If the player was freed between the push and the pop (a mid-
##     battle scene change, a corrupted save load mid-fight, MapSystem
##     getting torn down), pop_lock never ran. InputLockManager._locks
##     kept the "battle_transition" entry forever.
##   • Every subsequent overworld load would see is_locked() == true
##     and OverworldPlayer.refuses to move. Permanent freeze, no
##     in-game recovery.
##
## Fix: move the pop_lock out of the `if player:` block so it runs
## regardless of whether the player node is reachable.
##
## Tests:
##   • Source pin: pop_lock("battle_transition") in transition_from_
##     battle is OUTSIDE any `if player:` conditional
##   • Behavioural: push the lock, call transition_from_battle, assert
##     the lock is gone afterwards even when player is null

const SCENE_TRANSITION_PATH := "res://src/transitions/SceneTransition.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pin ────────────────────────────────────────────────────────────────

func test_pop_lock_not_gated_on_player_in_transition_from_battle() -> void:
	# Find the pop_lock line and the `if player:` line in code (NOT in
	# comments — the teaching doc comment after the fix cites the legacy
	# `if player:` shape to explain what changed). Skip comment lines so
	# the lint can't trip on its own explanation.
	var text := _read(SCENE_TRANSITION_PATH)
	var idx := text.find("func transition_from_battle")
	assert_gt(idx, -1, "transition_from_battle must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Reduce the body to non-comment lines while preserving rough ordering
	# via line numbers (each non-comment line keeps its absolute position).
	var lines := body.split("\n")
	var pop_line: int = -1
	var player_gate_line: int = -1
	for i in lines.size():
		var ln: String = str(lines[i])
		if ln.strip_edges().begins_with("#"):
			continue
		if pop_line == -1 and ln.contains("pop_lock(\"battle_transition\")"):
			pop_line = i
		if player_gate_line == -1 and ln.contains("if player:"):
			player_gate_line = i
	assert_gt(pop_line, -1,
		"pop_lock(\"battle_transition\") must appear in transition_from_battle (non-comment)")
	if player_gate_line > -1:
		assert_lt(pop_line, player_gate_line,
			"pop_lock(\"battle_transition\") must appear BEFORE the `if player:` gate — otherwise a null player leaks the lock")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_lock_released_even_when_player_null() -> void:
	# Drive the actual code path: push the lock, force MapSystem.player to
	# null, call transition_from_battle, assert the lock is gone.
	# (The full function awaits fades — we cancel that out by setting
	# fade_duration to 0 on a standalone instance.)
	if not InputLockManager:
		pending("InputLockManager autoload unavailable")
		return
	if not MapSystem:
		pending("MapSystem autoload unavailable")
		return
	# Snapshot state we'll mutate.
	var prior_player: Node2D = MapSystem.get_player()
	MapSystem.set_player(null)
	InputLockManager.push_lock("battle_transition")
	assert_true(InputLockManager.is_locked(),
		"setup sanity: lock must be held after push")

	# Drive a standalone SceneTransition with fade_duration=0 so the awaits
	# in fade_to_black/fade_from_black resolve immediately.
	var STScript: GDScript = load(SCENE_TRANSITION_PATH)
	var st: CanvasLayer = STScript.new()
	add_child_autofree(st)
	# _ready creates the fade overlay, which is required for the tweens.
	st.fade_duration = 0.0

	await st.transition_from_battle(true)

	assert_false(InputLockManager.is_locked(),
		"battle_transition lock must be released after transition_from_battle even when MapSystem.player is null")

	# Restore (in case downstream tests depend on this).
	MapSystem.set_player(prior_player)
