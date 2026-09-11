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
##
## ⚠️ NEGATIVE is a THIRD case, and the docstring above stopped one short of it.
## I reasoned about the absent counter, chose the safe direction, and never asked
## what happens when the subtraction goes below zero — so `since < BATTLE_COOLDOWN`
## thresholded a SIGNED quantity in one direction only.
##
## It is reachable. GameState._apply_save_data restores these two asymmetrically:
##   game_constants   `if save_data.has(...)`          absent -> KEEPS the live dict
##   battles_won      `if save_data.has(...) else 0`   absent -> ZEROED
## So loading a save that predates either key zeroes battles_won while the live
## LAST_BATTLE_KEY survives. Measured: claim at battle 40, then such a load ->
## "backstop: -40 of 3 battles since last reward", and the player must win 43
## battles to earn another, with nothing said.
##
## A negative means the baseline is AHEAD of reality, so it is not a baseline at
## all. Treat it as elapsed rather than as an enormous cooldown: the per-NPC
## per-phase claim ledger is the primary anti-farm gate and is untouched by this,
## while blocking is a silent dead feature with no recovery the player can see.
static func _battles_since_last(gs: Node) -> int:
	if not ("battles_won" in gs) or not ("game_constants" in gs):
		return 0
	var last: int = int(gs.game_constants.get(LAST_BATTLE_KEY, -BATTLE_COOLDOWN))
	var since: int = int(gs.battles_won) - last
	if since < 0:
		return BATTLE_COOLDOWN
	return since


## ── Payout ────────────────────────────────────────────────────────────────────

## Reward CONTENT lives in data, so retuning does not touch code.
const TABLE_PATH: String = "res://data/conversation_rewards.json"

static var _table: Dictionary = {}
static var _table_loaded: bool = false


## Stable reward identity. Personas are keyed by DISPLAY NAME
## (npc_showcase_personas.json), while scenes author npc_id — so neither field
## alone covers every NPC. Prefer the explicit id, slug the name otherwise.
static func resolve_npc_id(npc_id: String, npc_name: String) -> String:
	if npc_id != "":
		return npc_id
	return npc_name.to_lower().replace(" ", "_").strip_edges()


## Evaluate, grant, and record in one step. Returns the announcement line, or
## "" when nothing was owed — callers announce only on a non-empty string.
## mark_claimed fires ONLY after a grant actually lands, so a failed payout
## cannot burn the NPC's one claim for this quest phase.
static func grant_if_earned(gs: Node, npc_id: String, quest_bucket: String, exchanges: int) -> String:
	var verdict: Array = evaluate(gs, npc_id, quest_bucket, exchanges)
	if not bool(verdict[0]):
		return ""
	var summary: String = _grant(gs, _entry_for(npc_id))
	if summary == "":
		return ""
	mark_claimed(gs, npc_id, quest_bucket)
	return summary


## Per-NPC entry falls back to the shared default, never to an empty payout —
## an unlisted NPC that passed the gate still owes the player something.
static func _entry_for(npc_id: String) -> Dictionary:
	_ensure_table()
	var by_npc: Dictionary = _table.get("by_npc", {}) as Dictionary
	if by_npc.has(npc_id):
		return by_npc[npc_id] as Dictionary
	return _table.get("default", {}) as Dictionary


static func _ensure_table() -> void:
	if _table_loaded:
		return
	_table_loaded = true
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("[ConversationRewards] table missing at %s — conversation rewards disabled" % TABLE_PATH)
		return
	var text: String = FileAccess.get_file_as_string(TABLE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_table = parsed as Dictionary
	else:
		push_warning("[ConversationRewards] %s did not parse to a Dictionary — conversation rewards disabled" % TABLE_PATH)


## Test seam: reloads the table on next use.
static func reset_table_cache() -> void:
	_table = {}
	_table_loaded = false


## Grants gold and consumables. Returns a player-facing summary, or "" when
## nothing landed — a table entry of all zeroes must not consume the claim.
static func _grant(gs: Node, entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	var parts: Array = []
	var gold: int = int(entry.get("gold", 0))
	if gold > 0 and gs.has_method("add_gold"):
		gs.add_gold(gold)
		parts.append("%d gold" % gold)
	for raw in (entry.get("items", []) as Array):
		var spec: Dictionary = raw as Dictionary
		var iid: String = str(spec.get("item_id", ""))
		var count: int = maxi(1, int(spec.get("count", 1)))
		if iid == "" or not _grant_item(iid, count):
			continue
		parts.append(ItemNameResolver.resolve(iid) + ("" if count <= 1 else " ×%d" % count))
	if parts.is_empty():
		return ""
	return "Take this — %s." % _join_natural(parts)


## Refuses anything items.json does not know. Equipment lives in its own
## catalogs and reaches the player through GameLoop.equipment_pool, so calling
## add_item with a weapon id creates an inventory entry nothing can ever use.
static func _grant_item(item_id: String, count: int) -> bool:
	var root: Node = _tree_root()
	if root == null:
		return false
	var items: Node = root.get_node_or_null("ItemSystem")
	if items == null or items.get_item(item_id).is_empty():
		push_warning("[ConversationRewards] '%s' does not resolve in items.json — refused (equipment must route through equipment_pool)" % item_id)
		return false
	var loop: Node = root.get_node_or_null("GameLoop")
	if loop == null or not ("party" in loop) or loop.party.is_empty():
		return false
	if not loop.party[0].has_method("add_item"):
		return false
	loop.party[0].add_item(item_id, count)
	return true


## Autoloads are children of the scene-tree root; a static has no tree of its own.
static func _tree_root() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	return (loop as SceneTree).root if loop is SceneTree else null


static func _join_natural(parts: Array) -> String:
	if parts.size() == 1:
		return str(parts[0])
	var head: Array = parts.slice(0, parts.size() - 1)
	return "%s and %s" % [", ".join(head), str(parts[-1])]
