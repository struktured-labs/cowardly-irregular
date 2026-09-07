## ConversationRewards — decides WHEN a dynamic conversation has earned a reward.
##
## struktured's ask (2026-09-07): "some sequences should end up in rewards but
## you can only get like one reward per some interval so people dont game the llms."
##
## A pure time interval is farmable and teaches the wrong thing: wait N minutes,
## talk to anyone, collect. The gate here is STATE-first — a reward is earned once
## per NPC per quest phase, so re-earning requires the world to change rather than
## the clock to advance. A battle-count cooldown sits underneath as a backstop so a
## player cannot tour every NPC in one sitting and drain the table.
##
## No LLM output is trusted for eligibility. The model writes the line; the game
## decides whether anything is owed. That boundary is the whole anti-gaming design —
## a player who talks the model into offering a prize still gets nothing.

class_name ConversationRewards
extends RefCounted


## Persisted claim ledger lives in GameState.game_constants under this key.
const LEDGER_KEY: String = "llm_conversation_reward_claims"

## Battles that must pass between any two conversation rewards. The backstop.
const BATTLE_COOLDOWN: int = 3

## Exchanges required before a conversation counts as a real one.
const MIN_EXCHANGES: int = 2

## Key under which the last-rewarded battle count is stored.
const LAST_BATTLE_KEY: String = "llm_conversation_reward_last_battle"


## A conversation is rewardable when the player actually engaged, this NPC has not
## already paid out in its current quest phase, and the backstop has elapsed.
## Returns [eligible: bool, reason: String] — the reason is for logs, never the player.
static func evaluate(gs: Node, npc_id: String, quest_bucket: String, exchanges: int) -> Array:
	if gs == null or npc_id == "":
		return [false, "no game state or unnamed npc"]
	if exchanges < MIN_EXCHANGES:
		return [false, "conversation too short (%d < %d)" % [exchanges, MIN_EXCHANGES]]
	if _already_claimed(gs, npc_id, quest_bucket):
		return [false, "already rewarded for %s in phase '%s'" % [npc_id, quest_bucket]]
	var since: int = _battles_since_last(gs)
	if since < BATTLE_COOLDOWN:
		return [false, "backstop: %d of %d battles since last reward" % [since, BATTLE_COOLDOWN]]
	return [true, "eligible"]


## Record the payout. Call ONLY after the reward is actually granted — this is what
## makes the phase gate hold across saves.
static func mark_claimed(gs: Node, npc_id: String, quest_bucket: String) -> void:
	if gs == null or not ("game_constants" in gs):
		return
	var ledger: Dictionary = gs.game_constants.get(LEDGER_KEY, {}) as Dictionary
	ledger[_claim_key(npc_id, quest_bucket)] = true
	gs.game_constants[LEDGER_KEY] = ledger
	gs.game_constants[LAST_BATTLE_KEY] = int(gs.battles_won) if "battles_won" in gs else 0


## Claim identity is NPC + phase, so advancing the quest re-opens the NPC exactly once.
static func _claim_key(npc_id: String, quest_bucket: String) -> String:
	return "%s@%s" % [npc_id, quest_bucket if quest_bucket != "" else "none"]


static func _already_claimed(gs: Node, npc_id: String, quest_bucket: String) -> bool:
	if not ("game_constants" in gs):
		return false
	var ledger: Dictionary = gs.game_constants.get(LEDGER_KEY, {}) as Dictionary
	return bool(ledger.get(_claim_key(npc_id, quest_bucket), false))


## Absent counters must NOT read as "cooldown elapsed" — an unknown state that
## grants rewards is the farmable direction of the same false zero.
static func _battles_since_last(gs: Node) -> int:
	if not ("battles_won" in gs) or not ("game_constants" in gs):
		return 0
	var last: int = int(gs.game_constants.get(LAST_BATTLE_KEY, -BATTLE_COOLDOWN))
	return int(gs.battles_won) - last
