extends GutTest

## The confirm waits after a battle debounce the press that ended it ("so the press that ended the
## battle doesn't immediately confirm") on create_timer. They run while the battle scene is still up,
## and BattleScene only restores Engine.time_scale in _exit_tree, so the debounce ran in BATTLE time:
## at 1x (engine 0.25) the 0.5 s gate ignored every confirm press for 2.0 real seconds, and the 0.25 s
## snap-then-dismiss debounce for 1.0 s. Same defect class as MenuRepeat (.746) and TutorialHint.
## Derived: every create_timer in either wait must ignore time scale, so a new one is covered too.

const GL_SRC := "res://src/GameLoop.gd"
const WAITS := ["_wait_for_confirm_victory", "_wait_for_confirm"]


func _body(src: String, fn: String) -> String:
	var i: int = src.find("func %s()" % fn)
	assert_gt(i, -1, "CONTROL: %s must exist in GameLoop" % fn)
	var j: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > i else 2500)


func test_every_confirm_debounce_runs_in_real_seconds() -> void:
	var src := FileAccess.get_file_as_string(GL_SRC)
	var re := RegEx.new()
	re.compile("create_timer\\(([^)]*)\\)")
	var seen := 0
	for fn in WAITS:
		for m in re.search_all(_body(src, fn)):
			seen += 1
			var args: PackedStringArray = m.get_string(1).replace(" ", "").split(",")
			assert_true(args.size() >= 4 and args[3] == "true",
				"%s: create_timer(%s) must pass ignore_time_scale=true, or battle speed stretches the debounce" % [fn, m.get_string(1)])
	assert_gte(seen, 3, "CONTROL: the two waits carry three debounces between them (found %d)" % seen)


func test_battle_speed_is_still_in_force_during_the_wait() -> void:
	## The premise: time_scale is only restored when the battle scene leaves the tree, which is
	## after these waits return. If that ever moves earlier, this fix becomes moot and says so.
	var bs := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var ex: int = bs.find("func _exit_tree")
	assert_gt(ex, -1, "CONTROL: BattleScene has an _exit_tree")
	var nxt: int = bs.find("\nfunc ", ex + 1)
	assert_true("Engine.time_scale = 1.0" in bs.substr(ex, nxt - ex),
		"BattleScene restores time_scale in _exit_tree, i.e. after the confirm wait")
