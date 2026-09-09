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


func test_the_smoke_waits_for_the_duel_to_unwind_before_the_next_battle() -> void:
	## .239 fixed the 120s hang and exposed the race behind it: start_solo_battle stays suspended
	## on `await spotlight_battle_ended`, and resuming it returns to exploration. The smoke used to
	## start the dragon fight the moment BattleManager went INACTIVE — which is when the BATTLE
	## ended, not when the DUEL finished unwinding — so the resolver iterated freed combatants.
	var src := FileAccess.get_file_as_string(GL_SRC)
	var i: int = src.find("BattleManager.end_battle(true)")
	assert_gt(i, -1, "CONTROL: the smoke's duel leg still force-resolves the duel")
	var leg := src.substr(i, 2400)  # window must clear the unwind wait added below end_battle
	var wait_at: int = leg.find("while _spotlight_duel_active")
	var next_at: int = leg.find('_start_battle_async(["shadow_dragon"]')
	assert_gt(wait_at, -1, "the smoke must wait on the duel flag, not just on battle state")
	assert_gt(next_at, -1, "CONTROL: the game-over leg still starts the dragon fight")
	assert_lt(wait_at, next_at, "the wait has to come BEFORE the next battle or it guards nothing")


func test_the_unwind_wait_is_bounded_and_loud() -> void:
	# An unbounded wait here would trade a 120s hang for a different one, and a silent timeout
	# would let the race back in while still printing PASS — the failure mode this leg already
	# carries a comment about for its own battle wait.
	var src := FileAccess.get_file_as_string(GL_SRC)
	var i: int = src.find("while _spotlight_duel_active")
	var body := src.substr(i, 400)
	assert_true(body.contains("_dwait < 15.0"), "the unwind wait must be bounded")
	assert_true(body.contains("_smoke_failed = true"), "and must FAIL loudly rather than proceed into the race")


func test_the_unwind_loop_actually_presses_the_button_it_is_waiting_on() -> void:
	## The first fix deadlocked: end_battle(true) makes BattleManager INACTIVE immediately, so the
	## battle-state loop (which taps) exits before pressing anything, and the flag loop (which did
	## not tap) then waited on a confirm no one would ever give. _spotlight_duel_active cannot clear
	## until _wait_for_confirm_victory returns, and that needs a press — so the loop waiting on the
	## flag is the loop that has to send one.
	var src := FileAccess.get_file_as_string(GL_SRC)
	var i: int = src.find("while _spotlight_duel_active")
	assert_gt(i, -1, "CONTROL: the unwind wait still exists")
	var body := src.substr(i, 260)
	assert_true(body.contains('_smoke_tap("ui_accept")'),
		"the loop waiting on the confirm must press the confirm, or it waits forever")
