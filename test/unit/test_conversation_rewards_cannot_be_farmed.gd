extends GutTest

## struktured: "you can only get like one reward per some interval so people dont
## game the llms." The gate is STATE-first — once per NPC per quest phase — with a
## battle-count backstop. A pure interval is farmable by waiting; a phase gate is
## only re-openable by changing the world.
##
## The LLM never decides eligibility. A player who talks the model into promising
## treasure still gets nothing, because the model's output is not an input here.

const CR := preload("res://src/llm/ConversationRewards.gd")


class FakeState:
	extends Node
	var game_constants: Dictionary = {}
	var battles_won: int = 0


func _gs(battles: int = 99) -> FakeState:
	var s := FakeState.new()
	s.battles_won = battles
	return s


func after_each() -> void:
	pass


# ── the happy path exists, so every refusal below is a real refusal

func test_a_real_conversation_is_eligible() -> void:
	var gs := _gs()
	var r: Array = CR.evaluate(gs, "milo", "in_progress", 3)
	assert_true(bool(r[0]), "an engaged conversation with a fresh NPC must be rewardable: %s" % str(r[1]))
	gs.free()


# ── the anti-farm gates

func test_the_same_npc_cannot_pay_twice_in_one_phase() -> void:
	var gs := _gs()
	CR.mark_claimed(gs, "milo", "in_progress")
	var r: Array = CR.evaluate(gs, "milo", "in_progress", 4)
	assert_false(bool(r[0]), "re-talking the same NPC in the same phase must not pay again")
	assert_true(str(r[1]).contains("already rewarded"), "the refusal must name the reason")
	gs.free()


func test_advancing_the_quest_phase_reopens_that_npc() -> void:
	var gs := _gs()
	CR.mark_claimed(gs, "milo", "in_progress")
	gs.battles_won += CR.BATTLE_COOLDOWN
	var r: Array = CR.evaluate(gs, "milo", "post_quest", 3)
	assert_true(bool(r[0]), "a NEW phase is a new conversation worth having: %s" % str(r[1]))
	gs.free()


func test_a_drive_by_conversation_earns_nothing() -> void:
	var gs := _gs()
	var r: Array = CR.evaluate(gs, "milo", "in_progress", 1)
	assert_false(bool(r[0]), "opening and closing a dialogue is not an exchange")
	assert_true(str(r[1]).contains("too short"), "the refusal must name the reason")
	gs.free()


func test_touring_every_npc_hits_the_backstop() -> void:
	var gs := _gs()
	CR.mark_claimed(gs, "milo", "in_progress")
	# A different NPC, so the phase gate does not apply — the backstop must.
	var r: Array = CR.evaluate(gs, "theron", "none", 3)
	assert_false(bool(r[0]), "a second NPC immediately after a payout must hit the battle cooldown")
	assert_true(str(r[1]).contains("backstop"), "the refusal must name the backstop")
	gs.free()


func test_backstop_clears_after_enough_battles() -> void:
	var gs := _gs()
	CR.mark_claimed(gs, "milo", "in_progress")
	gs.battles_won += CR.BATTLE_COOLDOWN
	var r: Array = CR.evaluate(gs, "theron", "none", 3)
	assert_true(bool(r[0]), "the backstop must actually clear, or rewards are unreachable: %s" % str(r[1]))
	gs.free()


# ── the false-zero direction: unknown state must refuse, never grant

func test_missing_counters_refuse_rather_than_pay() -> void:
	var s := Node.new()
	var r: Array = CR.evaluate(s, "milo", "in_progress", 3)
	assert_false(bool(r[0]), "a state object without the counters must NOT be treated as cooldown-elapsed")
	s.free()
	var r2: Array = CR.evaluate(null, "milo", "in_progress", 3)
	assert_false(bool(r2[0]), "a null game state must refuse")


func test_unnamed_npc_refuses() -> void:
	var gs := _gs()
	assert_false(bool(CR.evaluate(gs, "", "in_progress", 3)[0]),
		"an NPC with no id cannot be ledgered, so it must not pay — otherwise it pays every time")
	gs.free()


# ── persistence: the ledger must ride the save, or the gate is per-session only

func test_claims_are_written_where_the_save_will_carry_them() -> void:
	var gs := _gs()
	CR.mark_claimed(gs, "milo", "in_progress")
	assert_true(gs.game_constants.has(CR.LEDGER_KEY),
		"claims must live in game_constants — a session-only ledger resets on load and the gate is farmable by reloading")
	assert_true(gs.game_constants.has(CR.LAST_BATTLE_KEY),
		"the backstop anchor must persist for the same reason")
	gs.free()
