extends GutTest

## UX gap fix 2026-07-04: the Death Sentence doom_counter ticks down each
## round and calls die() at 0 (correct), but it's a Combatant int field —
## NOT a status_effect — so it had NO status-icon indicator. After the
## one-time "☠ X is doomed! (3 turns to KO)" battle-log line scrolled
## away, the player couldn't track the lethal countdown. Now
## _refresh_status_icons appends a "☠ N" icon, and round_started drives a
## per-round refresh (no pop animation) so it — and stun/duration
## counters — visibly tick down.

const SCENE := "res://src/battle/BattleScene.gd"


func _read() -> String:
	return FileAccess.get_file_as_string(SCENE)


func test_doom_counter_gets_an_icon() -> void:
	var src := _read()
	var fn: int = src.find("func _refresh_status_icons")
	assert_gt(fn, -1)
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("combatant.doom_counter > 0"),
		"_refresh_status_icons must surface the doom countdown")
	assert_true(body.contains("\"☠ %d\" % combatant.doom_counter"),
		"the doom icon must show the remaining turn count (☠ N)")


func test_per_round_refresh_wired_and_unwired() -> void:
	var src := _read()
	assert_true(src.contains("round_started.connect(_refresh_all_status_icons)"),
		"round_started must drive a per-round icon refresh so counters visibly tick")
	assert_true(src.contains("round_started.is_connected(_refresh_all_status_icons)"),
		"the per-round refresh must be disconnected in cleanup (no dangling signal)")


func test_per_round_refresh_does_not_pop_animate() -> void:
	var src := _read()
	var fn: int = src.find("func _refresh_all_status_icons")
	assert_gt(fn, -1, "_refresh_all_status_icons must exist")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("_refresh_status_icons(combatant, false)"),
		"the per-round refresh must pass animate=false — popping every icon every round is noise")


func test_doom_mechanic_still_lethal_at_zero() -> void:
	# Behavioral cross-check: the countdown the icon tracks actually kills.
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Doomed"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	c.doom_counter = 1
	c.update_buff_durations()  # one tick → doom_counter 0 → die()
	assert_false(c.is_alive,
		"doom_counter must still reach 0 and KO — the icon just makes the existing mechanic visible")
