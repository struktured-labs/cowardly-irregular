extends GutTest

## cowir-deploy's .236 web render smoke went red on "game_over screen never appeared within 30s",
## deterministically, both attempts. Cause was my own v3.33.231 change: the spotlight-duel path
## now awaits _wait_for_confirm_victory, which blocks up to 120s on ui_accept.
##
## Two defects, and the smoke only exposed the smaller one:
##   1. the smoke drives that path with no player, so nothing ever presses
##   2. THE REAL ONE — BattleScene builds the victory overlay only `if not turbo_mode`, so a
##      spotlight win at turbo awaited a confirm for a prompt that was never drawn. Two minutes
##      frozen with the cutscene still up, until the 120s bail.
## The wait is now conditional on there being something on screen to confirm.

const GL_SRC := "res://src/GameLoop.gd"


func _fn_body(name: String) -> String:
	var src := FileAccess.get_file_as_string(GL_SRC)
	var i: int = src.find("func %s(" % name)
	assert_gt(i, -1, "CONTROL: %s must still exist in GameLoop" % name)
	var nxt: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (nxt - i) if nxt > i else 2500)


func test_the_confirm_wait_returns_early_when_no_overlay_is_on_screen() -> void:
	var body := _fn_body("_wait_for_confirm_victory")
	assert_true(body.contains('get_node_or_null("VictoryResults") == null'),
		"the wait must check for the overlay it is waiting on")
	var guard_at: int = body.find('VictoryResults") == null')
	var loop_at: int = body.find("while Time.get_ticks_msec()")
	assert_gt(loop_at, 0, "CONTROL: the 120s wait loop is still there")
	assert_true(guard_at > 0 and guard_at < loop_at,
		"the guard must come BEFORE the wait loop — after it, it guards nothing")


func test_the_120s_bail_is_still_there_as_a_backstop() -> void:
	# The guard handles "no overlay". A built overlay with a player who walks away still needs
	# the bail, so removing it while adding the guard would trade one hang for another.
	var body := _fn_body("_wait_for_confirm_victory")
	assert_true(body.contains("120000"), "the bounded-wait backstop must survive the guard")


func test_the_smoke_taps_through_the_duel_victory() -> void:
	# The render smoke is the only consumer that drives a duel win with no human attached.
	var src := FileAccess.get_file_as_string(GL_SRC)
	var i: int = src.find("BattleManager.end_battle(true)")
	assert_gt(i, -1, "CONTROL: the smoke's duel leg still force-resolves the duel")
	var leg := src.substr(i, 600)
	assert_true(leg.contains('_smoke_tap("ui_accept")'),
		"the duel leg must press through the victory sequence like the post-battle leg does")


func test_the_spotlight_path_still_shows_the_sequence_at_all() -> void:
	# Guard against "fixing" the smoke by deleting the feature struktured asked for.
	var body := _fn_body("_on_battle_ended")
	var block_at: int = body.find("if _spotlight_duel_active:")
	assert_gt(block_at, -1, "CONTROL: the spotlight short-circuit still exists")
	var emit_at: int = body.find("spotlight_battle_ended.emit(victory)", block_at)
	var wait_at: int = body.find("await _wait_for_confirm_victory()", block_at)
	assert_true(wait_at > 0 and wait_at < emit_at,
		"a duelist must still get the victory sequence before the cutscene resumes")
