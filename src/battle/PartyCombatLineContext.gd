## Snapshot passed to DialoguePrompts.build_party_line so an LLM can voice an in-character battle line.
extends RefCounted
class_name PartyCombatLineContext


## Triggering event id; one of EVENT_* below.
var event_kind: String = ""

## Speaker (PC) snapshot. No Node refs — name/job/personality/hp/mp/ap/status only.
var speaker_name: String = ""
var speaker_job_id: String = ""
var speaker_personality: String = ""
var speaker_hp_pct: float = 100.0
var speaker_mp_pct: float = 100.0
var speaker_ap: int = 0
var speaker_status: Array = []

## Party snapshot, one entry per slot (alive or dead).
var party: Array = []

## Enemy snapshot, one entry per slot.
var enemies: Array = []

## Recent turn history; oldest → newest. Capped at RECENT_LIMIT entries.
var recent_actions: Array = []

## Per-event payload (e.g. damage taken, ability id, killed enemy name). Free-form.
var event_data: Dictionary = {}


## Known event ids — match constants in BattleManager._maybe_fire_party_line.
const EVENT_TURN_START := "turn_start"
const EVENT_LOW_HP := "low_hp"
const EVENT_BIG_HIT_TAKEN := "big_hit_taken"
const EVENT_USED_SIGNATURE_ABILITY := "used_signature_ability"
const EVENT_VICTORY := "victory"

const RECENT_LIMIT: int = 6


func push_recent(entry: Dictionary) -> void:
	recent_actions.append(entry)
	while recent_actions.size() > RECENT_LIMIT:
		recent_actions.pop_front()


func to_dict() -> Dictionary:
	return {
		"event_kind": event_kind,
		"speaker_name": speaker_name,
		"speaker_job_id": speaker_job_id,
		"speaker_personality": speaker_personality,
		"speaker_hp_pct": speaker_hp_pct,
		"speaker_mp_pct": speaker_mp_pct,
		"speaker_ap": speaker_ap,
		"speaker_status": speaker_status.duplicate(),
		"party": party.duplicate(),
		"enemies": enemies.duplicate(),
		"recent_actions": recent_actions.duplicate(),
		"event_data": event_data.duplicate(),
	}
