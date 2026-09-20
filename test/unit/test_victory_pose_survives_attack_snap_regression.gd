extends GutTest

## F12 2026-09-20: fighter looping a jump, rogue frozen in IDLE on the
## victory screen. Cause: every action arms `_delayed_snap_and_idle` at
## 0.7s, the killing blow ends the battle and play_victory starts, then
## the pending snap calls set_idle and wipes the Celebration. Anyone who
## acted in the last 0.7s engine-time never shows their victory strip.

const BS := "res://src/battle/BattleScene.gd"


func _fn(src: String, name: String) -> String:
	var i: int = src.find("func %s" % name)
	assert_gt(i, -1, "floor: %s exists" % name)
	var nxt: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (nxt - i) if nxt > -1 else 800)


func test_pending_attack_snap_does_not_idle_after_victory() -> void:
	var src: String = FileAccess.get_file_as_string(BS)
	assert_gt(src.length(), 1000, "CONTROL: read BattleScene")
	var body: String = _fn(src, "_delayed_snap_and_idle")
	var guard: int = body.find("_battle_victory")
	var idle: int = body.find("set_idle")
	assert_gt(guard, -1, "_delayed_snap_and_idle must consult the victory latch")
	assert_gt(idle, -1, "floor: set_idle is what the snap does")
	assert_gt(idle, guard, "the victory latch must abort BEFORE set_idle — after is a comment")


func test_reset_attacker_home_does_not_arm_a_snap_once_victory_started() -> void:
	var src: String = FileAccess.get_file_as_string(BS)
	var body: String = _fn(src, "_reset_attacker_home")
	var guard: int = body.find("_battle_victory")
	var timer: int = body.find("create_timer")
	assert_gt(guard, -1, "killing-blow _reset_attacker_home must see the latch")
	assert_gt(timer, -1, "floor: this is the function that arms the 0.7s snap")
	assert_gt(timer, guard, "do not arm a new snap after victory — the delayed path is the other half")
