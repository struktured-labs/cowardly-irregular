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


# ── Runtime state ─────────────────────────────────────────────────────────────

var _state:          State  = State.IDLE
var _exchange_count: int    = 0
var _last_npc_line:  String = ""
var _npc_dialogue:   Node   = null   # NPCDialogue instance (lazy-init).
var _choice_menu:    DialogueChoiceMenu = null
var _active:         bool   = false


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
) -> void:
	_npc_name      = npc_name      if npc_name      != "" else "NPC"
	_npc_persona   = npc_persona   if npc_persona   != "" else "friendly villager"
	_location      = location      if location      != "" else "an unknown place"
	_event_log     = event_log
	_fallback_lines = fallback_lines.duplicate()


## Run the full conversation loop and await its completion.
## Freezes `player` movement while the conversation is active.
## MUST be awaited; returns when the conversation is in State.DONE.
func run(player: Node) -> void:
	if _active:
		return

	_active = true
	_exchange_count = 0
	_last_npc_line  = ""
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
	conversation_ended.emit(_npc_name)


## Returns true while a conversation is in progress.
func is_active() -> bool:
	return _active


## Abort a running conversation immediately (e.g. on scene change).
## Emits conversation_ended and cleans up UI.
func abort() -> void:
	if not _active:
		return
	_state = State.DONE
	_cleanup_ui()


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

	# Normal follow-up.
	var reply: String = await _fetch_npc_opening()   # Reuse opening fetch for context-aware reply.
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
		return _fallback_npc_line()

	var prompt: String = DialoguePrompts.build_npc_opening(
		_npc_name,
		_npc_persona,
		_location,
		recent,
	)

	var raw: Variant = await _safe_complete_json(
		prompt,
		DialoguePrompts.SCHEMA_NPC_OPENING,
		DialoguePrompts.FALLBACK_NPC_OPENING,
	)

	var validated: Dictionary = DialoguePrompts.validate_npc_opening(raw)
	return validated.get("line", _fallback_npc_line())


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

	var raw: Variant = await _safe_complete_json(
		prompt,
		DialoguePrompts.SCHEMA_NPC_OPENING,
		DialoguePrompts.FALLBACK_NPC_OPENING,
	)

	var validated: Dictionary = DialoguePrompts.validate_npc_opening(raw)
	return validated.get("line", SIGN_OFF_FALLBACK)


func _fetch_player_choices() -> Array[String]:
	var fallback_dict: Dictionary = DialoguePrompts._trimmed_fallback_choices(
		DialoguePrompts.MAX_CHOICES
	)
	var fallback_arr: Array[String] = []
	for s in fallback_dict.get("choices", []):
		fallback_arr.append(str(s))

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

	var raw: Variant = await _safe_complete_json(
		prompt,
		DialoguePrompts.SCHEMA_PLAYER_CHOICES,
		DialoguePrompts.FALLBACK_PLAYER_CHOICES,
	)

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


func _cleanup_ui() -> void:
	if _choice_menu != null and is_instance_valid(_choice_menu):
		_choice_menu.dismiss()
		_choice_menu.queue_free()
		_choice_menu = null
	# Do NOT free _npc_dialogue — the NPCDialogue may be mid-sentence.
	# NPCDialogue teardown is handled by its own lifecycle.


# ── Utility ───────────────────────────────────────────────────────────────────

func _llm_available() -> bool:
	if not Engine.has_singleton("LLMService"):
		return false
	var svc = Engine.get_singleton("LLMService")
	return svc != null and svc.is_available()


## Await a complete_json call on LLMService, guarded against missing singleton.
func _safe_complete_json(prompt: String, schema: Dictionary, fallback: Variant) -> Variant:
	if not Engine.has_singleton("LLMService"):
		return fallback
	var svc = Engine.get_singleton("LLMService")
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
