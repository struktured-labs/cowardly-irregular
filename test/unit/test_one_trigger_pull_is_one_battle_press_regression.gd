extends GutTest

## struktured 2026-09-24: "when I press L trigger it still sorta acts like a turbo button, hard to hit
## it just once" (first reported 2026-09-06 as L2 deferring the next player too). battle_defer and
## battle_advance carry the L2/R2 analog axes, and one pull emits a burst of pressed events with no
## echo flag. The 09-06 fix made Win98Menu's latch static, so it survives the menu swap. But a defer
## closes the menu, and the rest of the pull then reached BattleScene._input, which had no latch, and
## deferred the next character. BattleScene now claims the press through the same static latch, via
## _claim_shoulder.

const SceneScript = preload("res://src/battle/BattleScene.gd")

var _saved_defer: bool
var _saved_advance: bool


func before_each() -> void:
	_saved_defer = Win98Menu._defer_axis_held
	_saved_advance = Win98Menu._advance_axis_held
	Win98Menu._defer_axis_held = false
	Win98Menu._advance_axis_held = false


func after_each() -> void:
	Input.action_release("battle_defer")
	Input.action_release("battle_advance")
	Win98Menu._defer_axis_held = _saved_defer
	Win98Menu._advance_axis_held = _saved_advance


func test_the_tail_of_a_pull_the_menu_took_is_not_a_second_defer() -> void:
	Input.action_press("battle_defer")
	Win98Menu._defer_axis_held = true  # the command menu already acted on this pull, then closed
	assert_false(SceneScript._claim_shoulder("battle_defer"),
		"the rest of one L2 pull deferred the next character: BattleScene had its own, empty latch")


func test_control_a_fresh_pull_is_claimed_and_latches() -> void:
	Input.action_press("battle_defer")
	assert_true(SceneScript._claim_shoulder("battle_defer"), "CONTROL: a fresh pull must defer")
	assert_true(Win98Menu._defer_axis_held, "the claim must latch the shared flag the menu reads")
	assert_false(SceneScript._claim_shoulder("battle_defer"), "and the same pull's next sample must not defer again")


func test_a_stale_latch_does_not_swallow_a_new_press() -> void:
	Win98Menu._defer_axis_held = true  # released between menus, so no handler saw the release
	assert_true(SceneScript._claim_shoulder("battle_defer"),
		"a latch left set after the trigger was released must not eat the next real press")


func test_advance_shares_the_same_rule() -> void:
	Input.action_press("battle_advance")
	Win98Menu._advance_axis_held = true
	assert_false(SceneScript._claim_shoulder("battle_advance"), "R2's tail must not queue a second advance")
	Input.action_release("battle_advance")
	assert_true(SceneScript._claim_shoulder("battle_advance"), "CONTROL: after release, the next pull advances")


func test_both_battle_branches_claim_through_the_helper() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true(src.contains('_claim_shoulder("battle_defer")'), "the defer branch must claim through the shared latch")
	assert_true(src.contains('_claim_shoulder("battle_advance")'), "the advance branch must claim through the shared latch")
