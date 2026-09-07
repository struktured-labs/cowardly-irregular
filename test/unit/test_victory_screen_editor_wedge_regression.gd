extends GutTest

## struktured 2026-08-23, shipped linux build 08e90acf: "I entered the autobattle menu by
## accident during battle victory sscree and kind of got stuck from there."
##
## SECOND occurrence of the 2026-08-17 wedge. That fix (see
## test_autobattle_editor_battle_end_wedge_regression) contained the CONSEQUENCES of an
## editor that outlives its battle — pause the rebuilt world, block re-triggered encounters,
## block double-commence — and never asked why it was still open. It still was.
##
## Two root causes, both live on main at 8c1de65f:
##   A  current_state stays BATTLE through the victory screen, so ui_menu (Start) there
##      took the in-battle branch and opened the editor over a finished fight.
##   B  nothing tore the editor down at battle end, so it survived into exploration.

const GL := "res://src/GameLoop.gd"


func _fn_body(src: String, fn: String) -> String:
	var i := src.find("func " + fn)
	assert_gt(i, -1, fn + " present")
	var next := src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else -1)


## The guard's PREMISE, checked against the live autoload rather than the source. If someone
## drops VICTORY from is_battle_active()'s exclusion list, guard A silently stops guarding and
## every source pin below still passes. This is the arm that notices.
func test_battlemanager_reports_a_finished_battle_as_inactive() -> void:
	var bm = BattleManager
	assert_not_null(bm, "BattleManager autoload must exist")
	var restore = bm.current_state
	bm.current_state = bm.BattleState.VICTORY
	var on_victory: bool = bm.is_battle_active()
	bm.current_state = bm.BattleState.DEFEAT
	var on_defeat: bool = bm.is_battle_active()
	bm.current_state = bm.BattleState.PLAYER_SELECTING
	var mid_fight: bool = bm.is_battle_active()
	bm.current_state = restore
	assert_false(on_victory, "a battle in VICTORY is over — is_battle_active must say so, or guard A is inert")
	assert_false(on_defeat, "same for DEFEAT")
	assert_true(mid_fight, "CONTROL: a live fight must still read active, else the guard blocks normal play")


## Guard A landed on main independently as _battle_results_are_showing(), gating INSIDE
## _toggle_autobattle_editor — which covers all three entry points (F5, Start, L+R) where an
## earlier draft of this branch guarded only the Start branch. Pinned at the better location.
## OPEN-only by design: the close branch returns before it, so an open editor is never trapped.
func test_start_cannot_open_the_editor_once_the_battle_is_over() -> void:
	var src := FileAccess.get_file_as_string(GL)
	assert_gt(src.find("func _battle_results_are_showing"), -1, "the finished-battle predicate must exist")
	var body := _fn_body(src, "_toggle_autobattle_editor")
	var close_branch := body.find("save_and_close()")
	var guard := body.find("_battle_results_are_showing()")
	var open_work := body.find("_set_battle_menu_visible(false)")
	assert_gt(guard, -1, "the toggle must consult it, so every entry point is covered")
	assert_gt(guard, close_branch, "the guard sits AFTER the close branch — closing must never be blocked")
	assert_lt(guard, open_work, "and BEFORE the open work, or the editor opens anyway")


## Guard B, and the ordering that matters: _on_battle_ended returns early for spotlight duels,
## so a teardown placed after that return would miss every duel.
func test_the_editor_is_torn_down_when_the_battle_ends() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_on_battle_ended")
	var teardown := body.find("_autobattle_editor.save_and_close()")
	var spotlight_return := body.find("spotlight_battle_ended.emit")
	assert_gt(teardown, -1, "battle end must close an open editor — without this it orphans into exploration")
	assert_gt(spotlight_return, -1, "CONTROL: the spotlight early-return is still in this function")
	assert_lt(teardown, spotlight_return, "teardown precedes the spotlight early return, or duels leak the editor")


## save_and_close, not a bare free: it persists the rules the player just edited. A plain
## queue_free here would silently discard their work at every battle end.
func test_teardown_saves_the_players_rules() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_on_battle_ended")
	var i := body.find("_autobattle_editor")
	assert_gt(i, -1, "the teardown block exists")
	var seg := body.substr(i, 400)
	assert_true(seg.contains("save_and_close"),
		"teardown must go through save_and_close — a bare queue_free drops the rules they just wrote")
