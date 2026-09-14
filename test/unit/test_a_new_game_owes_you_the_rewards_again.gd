extends GutTest

## A second playthrough must not inherit the first one's reward claims.
##
## `ConversationRewards` records payouts in `GameState.game_constants` under
## `llm_conversation_reward_claims`, plus a cooldown stamp under
## `llm_conversation_reward_last_battle`. Neither key is cleared by anything that
## names it — grep `src/` and the only references are ConversationRewards' own.
##
## They survive New Game today only because `reset_game_state()` rebuilds
## `game_constants` WHOLESALE from `DEFAULT_GAME_CONSTANTS`. That is incidental,
## not designed: nothing says "clear the reward claims", and the same incidental
## protection is what `ConversationMemory` documents at its line 24.
##
## ⛔ THE EDIT THIS DEFENDS IS AN ORDINARY ONE. `game_constants` is the widest dict
## in the save — cutscene flags, dungeon_flags, bestiary, quest markers — and the
## load path ALREADY does a selective rebuild-then-merge for exactly that reason
## (`_apply_save_data`, and the 2026-07-02 / 2026-07-04 leak fixes CLAUDE.md
## records). The day someone makes the NEW GAME path selective too, a second
## playthrough silently inherits every NPC already paid in the first, and the
## player never hears about it — the reward simply never comes.
##
## Measured before writing this: claim `elder_theron@post_quest` at battle 40,
## `reset_game_state()`, and the ledger is `{}`, the stamp unset, the NPC eligible.
## This pins that, so the protection stops being a side effect nobody can see.

const GS := preload("res://src/meta/GameState.gd")
const CR := preload("res://src/llm/ConversationRewards.gd")

const NPC := "elder_theron"
const PHASE := "post_quest"


## A finished playthrough: this NPC has been paid, at battle 40.
func _a_completed_run() -> Node:
	var gs = GS.new()
	autofree(gs)
	gs.battles_won = 40
	CR.mark_claimed(gs, NPC, PHASE)
	return gs


# ── the defect this defends ───────────────────────────────────────────────────

func test_a_claim_does_not_survive_into_the_next_playthrough() -> void:
	## THE ARM. The player starts over; this NPC owes them again.
	var gs: Node = _a_completed_run()
	assert_true((gs.game_constants.get(CR.LEDGER_KEY, {}) as Dictionary).has("%s@%s" % [NPC, PHASE]),
		"CONTROL: the first playthrough must actually have claimed")
	gs.reset_game_state()
	gs.battles_won = 0
	assert_eq((gs.game_constants.get(CR.LEDGER_KEY, {}) as Dictionary).size(), 0,
		("a reward claim survived New Game — every NPC paid in the previous run is "
		+ "silently unpayable in this one, and nothing tells the player"))


func test_the_npc_is_actually_eligible_again_not_just_unlisted() -> void:
	## The ledger being empty is the mechanism; this is the consequence. An empty
	## ledger with a surviving cooldown stamp would still refuse.
	var gs: Node = _a_completed_run()
	gs.reset_game_state()
	gs.battles_won = 0
	var verdict: Array = CR.evaluate(gs, NPC, PHASE, CR.MIN_EXCHANGES)
	assert_true(bool(verdict[0]),
		"the NPC must owe a reward again in a fresh run, got: %s" % str(verdict[1]))


func test_the_cooldown_stamp_does_not_survive_either() -> void:
	## `llm_conversation_reward_last_battle` is the other half. Carried over at 40
	## while battles_won restarts at 0, `_battles_since_last` sees -40 — which its
	## own guard turns into "eligible", so this is belt-and-braces rather than a
	## second failure. Pinned because that guard is the only thing making it safe.
	var gs: Node = _a_completed_run()
	gs.reset_game_state()
	assert_false(gs.game_constants.has(CR.LAST_BATTLE_KEY),
		"the cooldown stamp survived New Game: %s" % str(gs.game_constants.get(CR.LAST_BATTLE_KEY, "")))


# ── it must not weaken the gate that makes claims stick ───────────────────────

func test_within_one_playthrough_a_claim_still_blocks() -> void:
	## CORRECT-WORK. The whole point of the ledger is that an NPC pays once per
	## quest phase; a fix for the leak must not turn that off.
	var gs: Node = _a_completed_run()
	gs.battles_won = 99
	var verdict: Array = CR.evaluate(gs, NPC, PHASE, CR.MIN_EXCHANGES)
	assert_false(bool(verdict[0]),
		"an already-paid NPC must stay paid inside one playthrough: %s" % str(verdict[1]))
	assert_true(str(verdict[1]).contains("already rewarded"),
		"and refuse for THAT reason, not the cooldown: %s" % str(verdict[1]))


func test_a_different_quest_phase_still_re_opens_the_npc() -> void:
	## CONTROL on the claim key: identity is NPC + phase, so advancing the quest
	## re-opens the same NPC exactly once. A leak fix must not collapse that.
	var gs: Node = _a_completed_run()
	gs.battles_won = 99
	var verdict: Array = CR.evaluate(gs, NPC, "in_progress", CR.MIN_EXCHANGES)
	assert_true(bool(verdict[0]),
		"a new quest phase must re-open the NPC: %s" % str(verdict[1]))


# ── the premise ───────────────────────────────────────────────────────────────

func test_new_game_still_rebuilds_the_whole_dict() -> void:
	## THE PREMISE, and the thing that makes this file a ratchet rather than a
	## restatement. Nothing clears these two keys BY NAME; they go because the
	## dict is rebuilt. If that becomes selective, the arms above are the warning.
	var gs = GS.new()
	autofree(gs)
	gs.game_constants["a_key_no_default_carries"] = true
	gs.reset_game_state()
	assert_false(gs.game_constants.has("a_key_no_default_carries"),
		("reset_game_state no longer rebuilds game_constants wholesale. The reward "
		+ "ledger is cleared ONLY by that rebuild — nothing clears it by name — so a "
		+ "selective reset must add the two ConversationRewards keys explicitly."))
	for k in GS.DEFAULT_GAME_CONSTANTS:
		assert_true(gs.game_constants.has(k), "CONTROL: the defaults must still be present (%s)" % k)
		break
