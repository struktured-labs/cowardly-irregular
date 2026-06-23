## RebalanceDaemon — proposes LLM-guided game_constants adjustments
## based on recent EventLog signals.
##
## Per user directive 2026-06-22 ("the game needs to be constantly
## attempting to rebalance itself using the llm as guidance"), the
## daemon listens for high-signal events (party wipes, boss defeats)
## and asks the LLM whether the game's difficulty needs a nudge.
##
## Trust tier (per the directive):
##   - The LLM PROPOSES adjustments — small game_constants deltas
##     (exp_multiplier ±5%, gold_multiplier ±5%, encounter_rate
##     ±10%, etc).
##   - The daemon applies small proposals automatically when their
##     confidence is high and they're within the safe-delta cap.
##   - Larger proposals are surfaced as PENDING for the player to
##     review (UI lands in a follow-up tick).
##
## This tick is the SCAFFOLD only — consider() logs what it WOULD
## propose without calling the LLM yet. The autoload wiring +
## structured-output schema + apply path land in subsequent ticks so
## the surface stays manageable per tick.
##
## State lives on GameState (var rebalance_daemon: RebalanceDaemon)
## so save/load can persist the pending + applied histories without
## an extra autoload.

class_name RebalanceDaemon
extends RefCounted

## Trigger types — what kind of event provoked a rebalance consideration.
## Match EventLog.TYPE_* constants where there's overlap so the daemon
## can be wired without translation.
const TRIGGER_PARTY_WIPE := "party_wipe"
const TRIGGER_BOSS_DEFEAT := "boss_defeat"
const TRIGGER_AREA_ENTERED := "area_entered"
const TRIGGER_MANUAL := "manual"

## Cap on how many proposals we'll hold pending review. Older proposals
## get dropped (oldest first) — same ring pattern as EventLog.
const PENDING_CAP: int = 20

## Cap on applied-history retention. Useful for the "what did the AI
## change for me last hour" diegetic surface.
const APPLIED_CAP: int = 50

## Minimum seconds between consider() calls regardless of trigger.
## Without this, a flurry of TYPE_AREA_ENTERED events could spam the
## LLM. Set on the daemon instance so a future settings panel can
## tune the cadence.
var min_consideration_interval_sec: float = 60.0

var pending: Array[Dictionary] = []
var applied: Array[Dictionary] = []
var _last_consideration_ts: int = 0


## Public entry point. GameLoop calls this from party_wipe / boss_defeat
## handlers (and any future trigger site). Returns true if the trigger
## was actually considered, false if it was throttled by the cadence
## guard.
##
## For now this is a STUB — it records a proposal stub and prints. The
## LLM call + structured-output schema + safe-apply lands in tick 42+.
func consider(trigger_type: String, context: Dictionary) -> bool:
	var now: int = int(Time.get_unix_time_from_system())
	if _last_consideration_ts > 0 \
			and (now - _last_consideration_ts) < int(min_consideration_interval_sec):
		print("[REBALANCE] throttled (%ds since last) — trigger=%s" % [
			now - _last_consideration_ts, trigger_type])
		return false
	_last_consideration_ts = now
	# Stub proposal — what the LLM-driven version will eventually return.
	# Recorded so the pending UI (later tick) has something to display
	# and so tests can assert the daemon was reached.
	var proposal: Dictionary = {
		"trigger": trigger_type,
		"ts": now,
		"context_summary": _summarize_context(context),
		"status": "stub",  # tick 42 swaps to 'awaiting_llm' then 'proposed'
		"deltas": [],
	}
	pending.append(proposal)
	while pending.size() > PENDING_CAP:
		pending.pop_front()
	print("[REBALANCE] considered trigger=%s context=%s (stub — LLM call lands tick 42+)"
		% [trigger_type, proposal["context_summary"]])
	return true


## Compress the context dict into a short string for logs + tests.
## Keeps the daemon decoupled from any specific event-data schema —
## context just gets summarized as best-effort key=value pairs.
func _summarize_context(context: Dictionary) -> String:
	var parts: Array[String] = []
	for key in context.keys():
		var v_str: String = str(context[key])
		if v_str.length() > 40:
			v_str = v_str.substr(0, 37) + "..."
		parts.append("%s=%s" % [str(key), v_str])
	return ", ".join(parts) if parts.size() > 0 else "(empty)"


## Save/load — daemon state rides on GameState's save dict so the
## pending review queue and applied history survive sessions.
func to_dict() -> Dictionary:
	return {
		"pending": pending.duplicate(true),
		"applied": applied.duplicate(true),
		"last_consideration_ts": _last_consideration_ts,
	}


func from_dict(data: Dictionary) -> void:
	pending.clear()
	for entry in data.get("pending", []):
		if entry is Dictionary:
			pending.append(entry)
	applied.clear()
	for entry in data.get("applied", []):
		if entry is Dictionary:
			applied.append(entry)
	_last_consideration_ts = int(data.get("last_consideration_ts", 0))
