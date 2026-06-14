## DynamicConversation — LLM-driven NPC conversation state machine.
##
## Drives a full NPC interaction loop:
##   1. IDLE         — waiting for the player to initiate a conversation.
##   2. OPENING      — fetching/displaying the NPC's LLM-generated greeting.
##   3. PLAYER_TURN  — presenting a DialogueChoiceMenu of LLM-generated player options.
##   4. NPC_REPLY    — fetching/displaying the NPC's follow-up line.
##   5. DONE         — exchange limit reached or player chose to end; conversation closed.
##
## Exchange limit: up to MAX_EXCHANGES (4) NPC→player→NPC cycles.  After that,
## the NPC delivers a short sign-off line and the conversation ends.
##
## Fallback contract:
##   - If LLMService is unavailable, `dialogue_lines` (from the owner NPC) are
##     used verbatim instead of generated text.
##   - If generated player choices are empty/invalid, FALLBACK_PLAYER_CHOICES
##     from DialoguePrompts is used.
##   - Nothing in this class can crash or stall the game; every await is guarded.
##
## Signals:
##   conversation_started  — emitted once at the top of every new conversation.
##   conversation_ended    — emitted once when the machine reaches DONE.
##
## Usage (from NPC scripts):
##   var dc: DynamicConversation = DynamicConversation.new()
##   dc.setup(npc_name, npc_persona, location_name, event_log, fallback_lines)
##   add_child(dc)
##   await dc.run(player_node)

extends Node
class_name DynamicConversation


# ── Signals ───────────────────────────────────────────────────────────────────

signal conversation_started(npc_name: String)
signal conversation_ended(npc_name: String)


# ── Constants ─────────────────────────────────────────────────────────────────

## Maximum NPC-open → player-reply → NPC-reply exchange cycles.
const MAX_EXCHANGES: int = 4

## Sentinel value returned by DialogueChoiceMenu when the player cancels.
const CHOICE_CANCELLED: String = ""

## Fallback sign-off line used when the exchange limit is reached.
const SIGN_OFF_FALLBACK: String = "Take care, traveler. Safe journeys."

## When true, the NPC reply and next player choices are fetched in a single
## combined LLM call (halves round trips when the prompt budget allows).
## Flag-gated so both code paths remain testable in isolation.
const MERGE_REPLY_AND_CHOICES: bool = true


# ── State enum ────────────────────────────────────────────────────────────────

enum State {
	IDLE,
	OPENING,
	PLAYER_TURN,
	NPC_REPLY,
	DONE,
}


# ── Configuration (set via setup()) ──────────────────────────────────────────

var _npc_name:      String = "NPC"
var _npc_persona:   String = "friendly villager"
var _location:      String = "an unknown place"
var _event_log:     EventLog = null      # May be null — prompts skip context gracefully.
var _fallback_lines: Array  = []         # Static dialogue_lines from the NPC.
## Wave F R3 fix — authored "opening" lines from npc_showcase_personas.json.
## When set and the LLM is unavailable, the opening turn samples from this
## richer per-character list instead of the flatter fallbacks list.
var _opening_lines: Array  = []


# ── Runtime state ─────────────────────────────────────────────────────────────

var _state:          State  = State.IDLE
var _exchange_count: int    = 0
var _last_npc_line:  String = ""
var _last_player_line: String = ""   # Most-recent player choice; threaded into NPC-reply prompt.
var _npc_dialogue:   Node   = null   # NPCDialogue instance (lazy-init).
var _choice_menu:    DialogueChoiceMenu = null
var _active:         bool   = false
## R2 — the player node frozen by run(), tracked so abort() can restore
## movement even when called from outside the run() coroutine (e.g. a
## scene-change-triggered teardown). Cleared on normal completion.
var _player:         Node   = null

## Optional staging area used by the combined-call path: when MERGE_REPLY_AND_CHOICES
## is true, _do_npc_reply fetches both the reply AND the next choices in a
## single round trip and stashes the choices here for the next PLAYER_TURN to
## consume (so _fetch_player_choices skips the second call).
var _pending_choices: Array[String] = []
var _has_pending_choices: bool = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

## R4 — keep the conversation's await loop alive even while the scene tree is
## paused. This node awaits LLM responses and drives a child choice menu whose
## input handling must also survive pause; PROCESS_MODE_ALWAYS covers both this
## node's processing and (via propagation) any child left at PROCESS_MODE_INHERIT.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ── Public API ────────────────────────────────────────────────────────────────

## Configure the state machine before calling run().
## All parameters are optional — unset values use safe defaults.
##
##   npc_name      — display name of the NPC (e.g. "Elder Theron")
##   npc_persona   — one-line personality description for the LLM prompt
##   location      — area/map name for context (e.g. "Verdant Vale Village")
##   event_log     — EventLog instance from GameState; may be null
##   fallback_lines — Array of Strings; used when LLM is unavailable
func setup(
	npc_name:      String,
	npc_persona:   String,
	location:      String,
	event_log:     EventLog,
	fallback_lines: Array,
	opening_lines: Array = [],
) -> void:
	_npc_name      = npc_name      if npc_name      != "" else "NPC"
	_npc_persona   = npc_persona   if npc_persona   != "" else "friendly villager"
	_location      = location      if location      != "" else "an unknown place"
	_event_log     = event_log
	_fallback_lines = fallback_lines.duplicate()
	# Wave F R3 fix — opening_lines is optional; when empty the opening turn
	# falls back to _fallback_lines (legacy behavior).
	_opening_lines = opening_lines.duplicate()


## Run the full conversation loop and await its completion.
## Freezes `player` movement while the conversation is active.
## MUST be awaited; returns when the conversation is in State.DONE.
func run(player: Node) -> void:
	if _active:
		return

	_active = true
	_player = player
	_exchange_count = 0
	_last_npc_line  = ""
	_last_player_line = ""
	_pending_choices.clear()
	_has_pending_choices = false
	_state = State.IDLE

	# Freeze the player.
	_set_player_movement(player, false)

	conversation_started.emit(_npc_name)
	_state = State.OPENING

	# ── Main loop ─────────────────────────────────────────────────────────────
	while _state != State.DONE:
		match _state:
			State.OPENING:
				await _do_opening()
			State.PLAYER_TURN:
				await _do_player_turn(player)
			State.NPC_REPLY:
				await _do_npc_reply()

	# Unfreeze the player.
	_set_player_movement(player, true)

	_active = false
	_player = null
	conversation_ended.emit(_npc_name)


## Returns true while a conversation is in progress.
func is_active() -> bool:
	return _active


## Abort a running conversation immediately (e.g. on scene change).
##
## R2 — full, idempotent teardown. Safe to call at ANY state (including before
## run() ever started) and any number of times. Performs best-effort cleanup so
## a scene-change-triggered abort can never strand the player frozen or leave
## the thinking indicator / choice menu on screen:
##   • state          → DONE (breaks the run() loop on its next iteration)
##   • thinking dots   → hidden (set_thinking(false))
##   • choice menu     → dismissed + freed (_cleanup_ui)
##   • player movement → restored (set_can_move(true))
##
## NOTE: LLMService.cancel_all() is intentionally NOT called here — in-flight
## request cancellation is wired at the scene-change site by another agent.
func abort() -> void:
	var was_active: bool = _active

	# Always force the loop to terminate and drop the active flag, regardless
	# of prior state, so a second abort() (or an abort before run()) is a no-op
	# beyond re-asserting the cleaned-up state.
	_state = State.DONE
	_active = false

	# Hide the "thinking" indicator (idempotent on the NPCDialogue).
	_set_thinking(false)

	# Dismiss + free the choice menu.
	_cleanup_ui()

	# Restore player movement so the overworld isn't left frozen. Only meaningful
	# if we actually froze someone; guarded by is_instance_valid inside the setter.
	if was_active and _player != null:
		_set_player_movement(_player, true)
	_player = null


# ── State handlers ────────────────────────────────────────────────────────────

func _do_opening() -> void:
	var opening_line: String = await _fetch_npc_opening()
	_last_npc_line = opening_line

	await _show_npc_line(opening_line)

	_exchange_count += 1
	_state = State.PLAYER_TURN


func _do_player_turn(player: Node) -> void:
	# Enforce exchange cap: if we're at the limit, skip to sign-off.
	if _exchange_count >= MAX_EXCHANGES:
		_state = State.NPC_REPLY
		return

	var choices: Array[String] = await _fetch_player_choices()
	if choices.is_empty():
		# No choices available — end gracefully.
		_state = State.DONE
		return

	# Ensure a "Farewell." / exit option is always last.
	_ensure_farewell(choices)

	var chosen: String = await _show_choice_menu(choices)

	# Store the chosen line BEFORE the cancel/farewell check so the eventual
	# sign-off path (or future analytics) still has access to whatever the
	# player picked. Without this, the player's words were discarded the
	# moment _do_player_turn returned, leaving _fetch_npc_reply with nothing
	# to react to (regression noted in plan slice item 5).
	_last_player_line = chosen if chosen != CHOICE_CANCELLED else ""

	if chosen == CHOICE_CANCELLED or _is_farewell(chosen):
		_state = State.DONE
		return

	# Player made a real choice — advance to NPC reply.
	_state = State.NPC_REPLY


func _do_npc_reply() -> void:
	# On sign-off (exchange limit or player is ending): give a closing line.
	if _exchange_count >= MAX_EXCHANGES:
		var sign_off: String = await _fetch_npc_sign_off()
		await _show_npc_line(sign_off)
		_state = State.DONE
		return

	# Normal follow-up — context-aware reply that threads the prior NPC line
	# and the player's chosen response into the prompt (no more silent reuse
	# of _fetch_npc_opening — see plan slice item 5).
	var reply: String = ""
	if MERGE_REPLY_AND_CHOICES and _llm_available():
		# Single round trip: get reply + next-turn choices in one call.
		var combined: Dictionary = await _fetch_combined_reply()
		reply = str(combined.get("reply", ""))
		var next_choices: Variant = combined.get("choices", [])
		_pending_choices.clear()
		if next_choices is Array:
			for item in (next_choices as Array):
				if item is String:
					_pending_choices.append(item as String)
		_has_pending_choices = not _pending_choices.is_empty()
	else:
		reply = await _fetch_npc_reply()

	# Wave F B10 fix — guard against empty/whitespace-only replies that
	# would render a blank dialogue panel. Combined-reply fetches can
	# return {"reply": "", "choices": [...]} when the LLM forgets the
	# reply field; fall back to the deterministic per-turn line so the
	# player always sees the NPC say something.
	if reply.strip_edges() == "":
		reply = DialoguePrompts._fallback_reply_line(_exchange_count)

	_last_npc_line = reply
	await _show_npc_line(reply)

	_exchange_count += 1
	_state = State.PLAYER_TURN


# ── LLM fetch helpers ─────────────────────────────────────────────────────────

func _fetch_npc_opening() -> String:
	var recent: Array = []
	if _event_log != null:
		recent = _event_log.recent(DialoguePrompts.CONTEXT_EVENTS)

	# Fast path: LLM unavailable.
	if not _llm_available():
		# Wave F R3 fix — prefer the authored opening lines when available
		# (richer voice than the per-turn fallbacks list).
		return _fallback_opening_line()

	var prompt: String = DialoguePrompts.build_npc_opening(
		_npc_name,
		_npc_persona,
		_location,
		recent,
	)

	# Wave C: surface the "thinking" indicator while the LLM is composing.
	# Cleared on BOTH success and fallback so a 6s client timeout doesn't
	# leave the dots spinning forever (set_thinking is idempotent).
	_set_thinking(true)
	var raw: Variant = await _safe_complete_json(
		prompt,
		DialoguePrompts.SCHEMA_NPC_OPENING,
		DialoguePrompts.FALLBACK_NPC_OPENING,
	)
	_set_thinking(false)

	var validated: Dictionary = DialoguePrompts.validate_npc_opening(raw)
	return validated.get("line", _fallback_opening_line())


func _fetch_npc_sign_off() -> String:
	# Generate a context-aware closing line, or fall back gracefully.
	if not _llm_available():
		return SIGN_OFF_FALLBACK

	var recent: Array = []
	if _event_log != null:
		recent = _event_log.recent(DialoguePrompts.CONTEXT_EVENTS)

	var prompt: String = DialoguePrompts.build_npc_opening_topical(
		_npc_name,
		_npc_persona,
		_location,
		"a polite farewell — end the conversation warmly",
		recent,
	)

	_set_thinking(true)
	var raw: Variant = await _safe_complete_json(
		prompt,
		DialoguePrompts.SCHEMA_NPC_OPENING,
		DialoguePrompts.FALLBACK_NPC_OPENING,
	)
	_set_thinking(false)

	var validated: Dictionary = DialoguePrompts.validate_npc_opening(raw)
	return validated.get("line", SIGN_OFF_FALLBACK)


func _fetch_player_choices() -> Array[String]:
	var fallback_dict: Dictionary = DialoguePrompts._trimmed_fallback_choices(
		DialoguePrompts.MAX_CHOICES
	)
	var fallback_arr: Array[String] = []
	for s in fallback_dict.get("choices", []):
		fallback_arr.append(str(s))

	# Combined-call shortcut: if _do_npc_reply already fetched the next
	# choices alongside the reply, consume them now and skip the second
	# LLM round trip entirely.
	if _has_pending_choices:
		var pending: Array[String] = _pending_choices.duplicate()
		_pending_choices.clear()
		_has_pending_choices = false
		if not pending.is_empty():
			return pending

	if not _llm_available():
		return fallback_arr

	var recent: Array = []
	if _event_log != null:
		recent = _event_log.recent(DialoguePrompts.CONTEXT_EVENTS)

	var prompt: String = DialoguePrompts.build_player_choices(
		_npc_name,
		_last_npc_line,
		DialoguePrompts.MAX_CHOICES,
		recent,
	)

	_set_thinking(true)
	var raw: Variant = await _safe_complete_json(
		prompt,
		DialoguePrompts.SCHEMA_PLAYER_CHOICES,
		DialoguePrompts.FALLBACK_PLAYER_CHOICES,
	)
	_set_thinking(false)

	var validated: Dictionary = DialoguePrompts.validate_player_choices(
		raw,
		DialoguePrompts.MAX_CHOICES,
	)

	var out: Array[String] = []
	for item in validated.get("choices", []):
		if item is String:
			out.append(item as String)
	if out.is_empty():
		return fallback_arr
	return out


## Fetch a context-aware follow-up NPC line that responds to the player's
## most recent chosen line. This is the dedicated reply fetcher — distinct
## from _fetch_npc_opening which is for greetings.
func _fetch_npc_reply() -> String:
	if not _llm_available():
		return DialoguePrompts._fallback_reply_line(_exchange_count)

	var recent: Array = []
	if _event_log != null:
		recent = _event_log.recent(DialoguePrompts.CONTEXT_EVENTS)

	var prompt: String = DialoguePrompts.build_npc_reply(
		_npc_name,
		_npc_persona,
		_location,
		recent,
		_last_npc_line,
		_last_player_line,
	)

	_set_thinking(true)
	var raw: Variant = await _safe_complete_json(
		prompt,
		DialoguePrompts.SCHEMA_NPC_REPLY,
		DialoguePrompts.FALLBACK_NPC_REPLY,
	)
	_set_thinking(false)

	var validated: Dictionary = DialoguePrompts.validate_npc_reply(raw, _exchange_count)
	return str(validated.get("line", DialoguePrompts._fallback_reply_line(_exchange_count)))


## Fetch BOTH the NPC reply and the next set of player choices in a single
## LLM call. Returns the combined dictionary; caller drains the choices
## into _pending_choices to skip the next _fetch_player_choices round trip.
func _fetch_combined_reply() -> Dictionary:
	# Caller pre-checks _llm_available — fast path the unavailable case.
	if not _llm_available():
		return DialoguePrompts._fallback_combined(
			DialoguePrompts.MAX_CHOICES,
			_exchange_count,
		)

	var recent: Array = []
	if _event_log != null:
		recent = _event_log.recent(DialoguePrompts.CONTEXT_EVENTS)

	var prompt: String = DialoguePrompts.build_combined_reply(
		_npc_name,
		_npc_persona,
		_location,
		recent,
		_last_npc_line,
		_last_player_line,
		DialoguePrompts.MAX_CHOICES,
	)

	_set_thinking(true)
	var raw: Variant = await _safe_complete_json(
		prompt,
		DialoguePrompts.SCHEMA_COMBINED_REPLY,
		DialoguePrompts.FALLBACK_COMBINED_REPLY,
	)
	_set_thinking(false)

	return DialoguePrompts.validate_combined_reply(
		raw,
		DialoguePrompts.MAX_CHOICES,
		_exchange_count,
	)


# ── UI helpers ────────────────────────────────────────────────────────────────

func _show_npc_line(line: String) -> void:
	_ensure_npc_dialogue()
	if _npc_dialogue == null or not is_instance_valid(_npc_dialogue):
		return

	await _npc_dialogue.say(
		_npc_name,
		line,
		"villager",  # theme — caller may override by subclassing
		"villager",  # portrait
	)


func _show_choice_menu(choices: Array[String]) -> String:
	if _choice_menu != null and is_instance_valid(_choice_menu):
		_choice_menu.queue_free()
		_choice_menu = null

	_choice_menu = DialogueChoiceMenu.new()
	_choice_menu.name = "DynConvChoiceMenu"
	add_child(_choice_menu)

	var chosen: String = await _choice_menu.present(choices)

	if _choice_menu != null and is_instance_valid(_choice_menu):
		_choice_menu.queue_free()
		_choice_menu = null

	return chosen


func _ensure_npc_dialogue() -> void:
	if _npc_dialogue != null and is_instance_valid(_npc_dialogue):
		return
	var NPCDialogueClass = load("res://src/cutscene/NPCDialogue.gd")
	if NPCDialogueClass == null:
		push_error("[DynamicConversation] Failed to load NPCDialogue.gd")
		return
	_npc_dialogue = NPCDialogueClass.new()
	_npc_dialogue.name = "DynConvNPCDialogue"
	add_child(_npc_dialogue)


## Wave C: toggle the dialogue thinking indicator. Lazy-init's the NPCDialogue
## so the indicator can flash even before the first line is shown. Safe to call
## from BOTH success and fallback paths — set_thinking on the dialogue is
## idempotent.
func _set_thinking(active: bool) -> void:
	_ensure_npc_dialogue()
	if _npc_dialogue == null or not is_instance_valid(_npc_dialogue):
		return
	if _npc_dialogue.has_method("set_thinking"):
		_npc_dialogue.set_thinking(active)


func _cleanup_ui() -> void:
	if _choice_menu != null and is_instance_valid(_choice_menu):
		_choice_menu.dismiss()
		_choice_menu.queue_free()
		_choice_menu = null
	# Do NOT free _npc_dialogue — the NPCDialogue may be mid-sentence.
	# NPCDialogue teardown is handled by its own lifecycle.


# ── Utility ───────────────────────────────────────────────────────────────────

func _llm_available() -> bool:
	# Engine.has_singleton("LLMService") is ALWAYS FALSE for autoloads in Godot 4
	# (it only matches native engine singletons). Look up the autoload node via
	# the scene tree root instead.
	var svc: Node = get_node_or_null("/root/LLMService")
	return svc != null and svc.is_available()


## Await a complete_json call on LLMService, guarded against missing singleton.
func _safe_complete_json(prompt: String, schema: Dictionary, fallback: Variant) -> Variant:
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc == null:
		return fallback
	var result: Variant = await svc.complete_json(prompt, schema, fallback)
	return result


func _fallback_npc_line() -> String:
	if _fallback_lines.is_empty():
		return "..."
	# Cycle through fallback lines using the exchange count to vary them.
	var idx: int = _exchange_count % _fallback_lines.size()
	return str(_fallback_lines[idx])


## Wave F R3 fix — pick a per-character opening line when the LLM is
## unavailable. Prefer the richer `openings` list authored in
## data/cutscenes/npc_showcase_personas.json; only fall through to the
## flatter `fallbacks` set if openings weren't supplied.
func _fallback_opening_line() -> String:
	if not _opening_lines.is_empty():
		var idx: int = randi() % _opening_lines.size()
		return str(_opening_lines[idx])
	return _fallback_npc_line()


## Ensure the choices list always ends with a farewell option.
## If one is already present anywhere, we don't add a duplicate.
func _ensure_farewell(choices: Array[String]) -> void:
	for c in choices:
		if _is_farewell(c):
			return
	# Append a farewell option, but only if we haven't already hit the max.
	if choices.size() < DialoguePrompts.MAX_CHOICES:
		choices.append("Farewell.")
	else:
		# Replace last entry with farewell to stay within capacity.
		choices[choices.size() - 1] = "Farewell."


func _is_farewell(choice: String) -> bool:
	var lower: String = choice.strip_edges().to_lower()
	return (
		lower == "farewell." or
		lower == "farewell" or
		lower.begins_with("farewell") or
		lower == "goodbye." or
		lower == "goodbye" or
		lower.begins_with("goodbye") or
		lower.begins_with("good-bye") or
		lower.begins_with("take care") or
		lower.begins_with("i should go") or
		lower.begins_with("i'll be going")
	)


func _set_player_movement(player: Node, can_move: bool) -> void:
	if player != null and is_instance_valid(player) and player.has_method("set_can_move"):
		player.set_can_move(can_move)
