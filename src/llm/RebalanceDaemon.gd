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


## Schema the LLM response must match. LLMService._guard_json validates
## required keys + type/enum constraints; deeper delta-level validation
## happens in the apply path (tick 44+).
##
## verdict — overall direction. 'no_change' means LLM thinks the curve
## is fine; daemon records the proposal but applies zero deltas.
## confidence — LLM's self-assessment (0.0-1.0). Used by the apply
## layer to decide auto-apply vs surface-for-review.
## deltas — the actual adjustments. Each entry is { constant: String,
## multiplier: float, reason: String }. Schema validates Array; per-
## entry checks happen later.
## reason — short prose explanation for the diegetic "what did the AI
## change for me" surface.
const REBALANCE_SCHEMA: Dictionary = {
	"verdict":    ["nudge_easier", "nudge_harder", "no_change"],
	"confidence": "float",
	"deltas":     "Array",
	"reason":     "String",
}


## Safe multiplier band. Deltas outside [SAFE_DELTA_MIN, SAFE_DELTA_MAX]
## go into the review queue instead of auto-applying. Tunable so a
## settings panel can be more/less conservative later.
const SAFE_DELTA_MIN: float = 0.85
const SAFE_DELTA_MAX: float = 1.15

## Confidence threshold for auto-apply. Below this and the proposal
## goes to review even if deltas are in the safe band.
const AUTO_APPLY_CONFIDENCE: float = 0.7


## Safelist of game_constants the daemon is allowed to nudge. Anything
## outside this list gets rejected at apply time — no surprise edits
## to story flags, save corruption, or anything load-bearing.
const ALLOWED_CONSTANTS: Array[String] = [
	"exp_multiplier",
	"gold_multiplier",
	"encounter_rate",
]

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


## Build the LLM prompt for a rebalance consideration. Public so tests
## (and a future debug overlay) can inspect what the daemon would send
## without firing a real call.
func build_prompt(trigger_type: String, context: Dictionary, recent_events: Array = []) -> String:
	var lines: Array[String] = []
	lines.append("You are the difficulty curator for a JRPG. The player just experienced a high-signal event.")
	lines.append("")
	lines.append("EVENT: %s" % trigger_type)
	lines.append("CONTEXT:")
	for key in context.keys():
		var v_str: String = str(context[key])
		if v_str.length() > 200:
			v_str = v_str.substr(0, 197) + "..."
		lines.append("  %s: %s" % [str(key), v_str])
	if recent_events.size() > 0:
		lines.append("")
		lines.append("RECENT EVENTS (oldest first):")
		for ev in recent_events:
			if ev is Dictionary:
				lines.append("  [%s] %s" % [str(ev.get("type", "?")), str(ev.get("summary", "?"))])
	lines.append("")
	lines.append("Propose at most ONE small adjustment to game constants. Stay subtle (±15%% max). If the curve looks fine, choose 'no_change'.")
	lines.append("")
	lines.append("Allowed constants:")
	lines.append("  exp_multiplier   (XP gain rate)")
	lines.append("  gold_multiplier  (gold drop rate)")
	lines.append("  encounter_rate   (random encounter frequency)")
	lines.append("")
	lines.append("Respond with JSON ONLY matching this shape:")
	lines.append("  { \"verdict\": \"nudge_easier\" | \"nudge_harder\" | \"no_change\",")
	lines.append("    \"confidence\": 0.0-1.0,")
	lines.append("    \"deltas\": [ { \"constant\": <name>, \"multiplier\": 0.85-1.15, \"reason\": <short string> } ],")
	lines.append("    \"reason\": \"short overall explanation for the player\" }")
	return "\n".join(lines)


## Async: ask the LLM to fill in a pending proposal. Caller is a Node
## that can await — see GameLoop's wipe / boss-defeat handlers.
## Returns true on success (proposal updated with deltas), false if
## the proposal idx is invalid OR LLM unavailable OR fallback was hit.
func request_llm_proposal(proposal_idx: int, recent_events: Array = []) -> bool:
	if proposal_idx < 0 or proposal_idx >= pending.size():
		return false
	var proposal: Dictionary = pending[proposal_idx]
	var trigger: String = str(proposal.get("trigger", ""))
	var context_summary: String = str(proposal.get("context_summary", ""))
	# Reconstruct minimal context for the prompt — full context was
	# summarized to a string at consider() time. The summary is enough
	# for the LLM to react; richer context is a future ehancement.
	var ctx: Dictionary = {"summary": context_summary}
	var prompt: String = build_prompt(trigger, ctx, recent_events)
	proposal["status"] = "awaiting_llm"
	proposal["prompt_chars"] = prompt.length()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		proposal["status"] = "failed_no_tree"
		return false
	var svc: Node = tree.root.get_node_or_null("LLMService")
	if svc == null or not svc.has_method("complete_json") or not svc.is_available():
		proposal["status"] = "failed_unavailable"
		return false
	var fallback: Variant = null
	var result: Variant = await svc.complete_json(prompt, REBALANCE_SCHEMA, fallback)
	if not (result is Dictionary):
		proposal["status"] = "failed_fallback"
		return false
	var r: Dictionary = result as Dictionary
	proposal["verdict"]    = str(r.get("verdict", "no_change"))
	proposal["confidence"] = float(r.get("confidence", 0.0))
	proposal["deltas"]     = r.get("deltas", [])
	proposal["reason"]     = str(r.get("reason", ""))
	proposal["status"]     = "proposed"
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


## Result strings for try_auto_apply — keeps the caller's match arms
## stable even if the internal flow changes.
const APPLY_NO_CHANGE := "no_change"
const APPLY_APPLIED := "applied"
const APPLY_NEEDS_REVIEW := "needs_review"
const APPLY_REJECTED := "rejected"


## Try to auto-apply a proposal that's reached status='proposed'.
## Returns one of:
##   APPLY_NO_CHANGE   — verdict was 'no_change', nothing to apply,
##                       proposal logged into applied[] with empty deltas
##   APPLY_APPLIED     — all deltas were safe + confidence met threshold,
##                       written to game_constants and proposal moved to applied[]
##   APPLY_NEEDS_REVIEW — at least one delta was outside the safe band
##                        OR confidence was below threshold; proposal
##                        stays in pending[] with status='needs_review'
##                        for player UI to surface
##   APPLY_REJECTED    — proposal references an unsafe constant (not in
##                       ALLOWED_CONSTANTS), or proposal idx is invalid;
##                       proposal status set to 'rejected', NOT applied
##
## The caller is GameLoop's _kick_off_rebalance_fetch (after
## request_llm_proposal returns true). Settings UI will also call it
## when the player clicks "Apply" on a needs_review proposal.
func try_auto_apply(proposal_idx: int) -> String:
	if proposal_idx < 0 or proposal_idx >= pending.size():
		return APPLY_REJECTED
	var proposal: Dictionary = pending[proposal_idx]
	var verdict: String = str(proposal.get("verdict", ""))
	var confidence: float = float(proposal.get("confidence", 0.0))
	var deltas: Variant = proposal.get("deltas", [])
	if not (deltas is Array):
		proposal["status"] = "rejected"
		return APPLY_REJECTED
	# verdict='no_change' = LLM says the curve is fine. Move proposal
	# into applied[] for the diegetic log, but apply nothing.
	if verdict == "no_change":
		proposal["status"] = "applied_no_change"
		_move_to_applied(proposal_idx)
		return APPLY_NO_CHANGE
	# Reject malformed deltas before any other check — unknown
	# constants must never write into game_constants.
	for delta in deltas:
		if not (delta is Dictionary):
			proposal["status"] = "rejected"
			return APPLY_REJECTED
		var constant_name: String = str(delta.get("constant", ""))
		if constant_name not in ALLOWED_CONSTANTS:
			proposal["status"] = "rejected"
			return APPLY_REJECTED
	# Auto-apply gates: confidence + each multiplier in safe band.
	# Failing either sends the proposal to review, not rejection — the
	# constants ARE valid, just outside the auto-apply comfort zone.
	if confidence < AUTO_APPLY_CONFIDENCE:
		proposal["status"] = "needs_review"
		return APPLY_NEEDS_REVIEW
	for delta in deltas:
		var multiplier: float = float((delta as Dictionary).get("multiplier", 1.0))
		if multiplier < SAFE_DELTA_MIN or multiplier > SAFE_DELTA_MAX:
			proposal["status"] = "needs_review"
			return APPLY_NEEDS_REVIEW
	# All checks passed — apply the deltas to GameState.game_constants.
	var gs: Node = _resolve_game_state()
	if gs == null or not ("game_constants" in gs):
		# Can't apply without GameState — mark for review so the deltas
		# aren't lost.
		proposal["status"] = "needs_review"
		return APPLY_NEEDS_REVIEW
	var applied_changes: Array = []
	for delta in deltas:
		var d: Dictionary = delta
		var constant_name: String = str(d.get("constant", ""))
		var multiplier: float = float(d.get("multiplier", 1.0))
		if gs.game_constants.has(constant_name):
			var before: float = float(gs.game_constants[constant_name])
			var after: float = before * multiplier
			gs.game_constants[constant_name] = after
			applied_changes.append({
				"constant":   constant_name,
				"before":     before,
				"after":      after,
				"multiplier": multiplier,
			})
	proposal["status"] = "applied"
	proposal["applied_changes"] = applied_changes
	_move_to_applied(proposal_idx)
	return APPLY_APPLIED


## Build the human-readable line the diegetic "what did the AI change
## for me" surface shows. Public so the toast / settings UI can use
## the same formatter.
func summarize_applied(proposal: Dictionary) -> String:
	var verdict: String = str(proposal.get("verdict", ""))
	if verdict == "no_change":
		return "Auto-rebalance: no change needed."
	var changes: Array = proposal.get("applied_changes", [])
	if changes.is_empty():
		return "Auto-rebalance: proposed but no changes applied."
	var parts: Array[String] = []
	for c in changes:
		var name: String = str(c.get("constant", "?"))
		var mult: float = float(c.get("multiplier", 1.0))
		var pct: int = int(round((mult - 1.0) * 100.0))
		var sign: String = "+" if pct >= 0 else ""
		parts.append("%s %s%d%%" % [name, sign, pct])
	return "Auto-rebalance: " + ", ".join(parts)


func _move_to_applied(proposal_idx: int) -> void:
	var proposal: Dictionary = pending[proposal_idx]
	pending.remove_at(proposal_idx)
	applied.append(proposal)
	while applied.size() > APPLIED_CAP:
		applied.pop_front()


func _resolve_game_state() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameState")


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
