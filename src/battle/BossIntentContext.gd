## BossIntentContext — a deterministic snapshot passed to
## BossDialogue.pick_intent so an LLM can reason about strategic posture
## (aggress / turtle / exploit_pattern / …) without poking at live
## Combatant nodes.
##
## DESIGN: The LLM picks an INTENT (a role direction), code chooses the
## exact ability via _bias_by_intent. This context is the LLM's complete
## input — it should be small enough to serialize cleanly into a prompt
## yet rich enough that the choice is informed (boss state, party state,
## phase, last few exchanges).
##
## Keep this RefCounted (no @tool, no class_name needed beyond this file)
## and side-effect-free. BattleManager._build_boss_intent_context() is
## the single producer.
extends RefCounted
class_name BossIntentContext


## Stable persona key (e.g. "chancellor_mordaine") — also the
## BossDialogue.json entry key. Required.
var boss_id: String = ""

## Combat phase the LLM is being asked about (1 / 2 / 3). Required.
var phase: int = 1

## Boss state. Only the fields that matter for posture choice; no Node refs.
var boss_hp_pct: float = 100.0         # 0..100
var boss_mp_pct: float = 100.0
var boss_ap: int       = 0             # current AP (Advance Point bank)
var boss_status: Array = []            # status effects on the boss

## Party state, one entry per slot (alive or dead). Index = battle slot.
##   { name, job_id, hp_pct, mp_pct, ap, is_alive, status:[...] }
var party: Array = []

## Recent turn history (mixed boss + party actions), oldest → newest.
## Each entry: { actor, ability_id, target, damage, kind } where
##   kind ∈ {"boss_action", "party_action", "boss_taunt"}
## Capped at RECENT_LIMIT entries (BattleManager truncates on push).
var recent_actions: Array = []

## Eligible intent IDs for this phase, read off BossDialogue.gd's
## entry["scripted_intents"] and pre-filtered by min_phase. The LLM
## MUST pick one of these; anything else is rejected by the validator.
var available_intents: Array = []

## Optional, human-readable persona text — same string used by
## DynamicConversation. May be empty for bosses without a persona block.
var persona: String = ""


## Hard cap on recent_actions size. Older entries get dropped.
const RECENT_LIMIT: int = 8


## Append a turn to recent_actions, truncating to RECENT_LIMIT.
func push_recent(entry: Dictionary) -> void:
	recent_actions.append(entry)
	while recent_actions.size() > RECENT_LIMIT:
		recent_actions.pop_front()


## Serialize the context as a Dictionary for prompting / logging /
## test inspection. Stable key order so test source-pins don't break.
func to_dict() -> Dictionary:
	return {
		"boss_id": boss_id,
		"phase": phase,
		"boss_hp_pct": boss_hp_pct,
		"boss_mp_pct": boss_mp_pct,
		"boss_ap": boss_ap,
		"boss_status": boss_status.duplicate(),
		"party": party.duplicate(),
		"recent_actions": recent_actions.duplicate(),
		"available_intents": available_intents.duplicate(),
		"persona": persona,
	}
