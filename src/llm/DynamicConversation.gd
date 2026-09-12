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

## Baseline NPC-open → player-reply → NPC-reply exchange cycles.
const MAX_EXCHANGES: int = 4

## Hard ceiling on the dynamic cap — B always exits sooner if the player wants out.
const MAX_EXCHANGES_CEILING: int = 10

## Extra cycles granted when the NPC has quest-phase voice notes to spend.
const EXCHANGE_BONUS_QUEST_VOICE: int = 2

## Extra cycles granted when the party is visibly in trouble — there is something to talk about.
const EXCHANGE_BONUS_PARTY_DISTRESS: int = 2

## Sentinel value returned by DialogueChoiceMenu when the player cancels.
## Choices to REQUEST from the model. One slot of MAX_CHOICES is reserved for the
## exit that _ensure_farewell fills.
##
## Asking for the full MAX_CHOICES meant the model's LAST choice was replaced and
## silently discarded on every turn it did not itself produce an exit — and it
## essentially never does. Measured against live llama3, 5 samples of the reply
## prompt: 4 distinct choices every time, ZERO containing an exit, so 3 of 3
## replayed sets lost their fourth. The prompt asks for choices "covering a range
## of tones: curious, cautious, friendly, direct" and one tone was then dropped.
##
## Requesting one fewer costs the player nothing — the menu is the same size —
## and every line the model writes now survives to the screen.
const REQUESTED_CHOICES: int = DialoguePrompts.MAX_CHOICES - 1

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
## Milo v2 (msg 2600) — quest-state bucket lines threaded into build_npc_opening
## as "recent voice notes" so the LLM matches the current-quest-phase tone.
## Passed from OverworldNPC after resolving GameState.quests state → persona bucket.
var _quest_state_lines: Array = []
## Live party snapshot (HP/KO, gold, supplies) resolved once per conversation.
var _party_state: Dictionary = {}

## What this NPC remembers the player saying, loaded once at run() start.
var _memory_lines: Array = []

## Player choices made THIS conversation — becomes the next visit's memory.
var _player_lines: Array = []

## Reward identity — empty disables rewards for this NPC (ConversationRewards refuses "").
var _npc_id: String = ""
var _quest_bucket: String = ""


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
	quest_state_lines: Array = [],
	npc_id: String = "",
	quest_bucket: String = "",
) -> void:
	_npc_name      = npc_name      if npc_name      != "" else "NPC"
	_npc_persona   = npc_persona   if npc_persona   != "" else "friendly villager"
	_location      = location      if location      != "" else "an unknown place"
	_event_log     = event_log
	_fallback_lines = fallback_lines.duplicate()
	# Wave F R3 fix — opening_lines is optional; when empty the opening turn
	# falls back to _fallback_lines (legacy behavior).
	_opening_lines = opening_lines.duplicate()
	# Milo v2 (msg 2600) — optional per-NPC quest_state_lines, threaded into
	# build_npc_opening so the LLM matches the current-quest-phase voice.
	_quest_state_lines = quest_state_lines.duplicate()
	_npc_id = npc_id
	_quest_bucket = quest_bucket


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
	_party_state = _resolve_party_state()
	_player_lines.clear()
	_memory_lines = ConversationMemory.recall(get_node_or_null("/root/GameState"), _npc_id)
	_state = State.IDLE

	# Freeze the player.
	_set_player_movement(player, false)

	_register_with_llm_service()
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

	# abort() drops _active before the loop breaks, so this pays out only on a
	# conversation the player actually saw through.
	if _active:
		await _maybe_grant_reward()
		ConversationMemory.remember(get_node_or_null("/root/GameState"), _npc_id, _player_lines)

	# Unfreeze the player.
	_set_player_movement(player, true)

	_active = false
	_player = null
	_unregister_with_llm_service()
	conversation_ended.emit(_npc_name)


## Returns true while a conversation is in progress.
func is_active() -> bool:
	return _active


## Exchanges completed in the last run — what ConversationRewards gates on.
func get_exchange_count() -> int:
	return _exchange_count


## Pays out at most one reward per NPC per quest phase; ConversationRewards owns
## every eligibility rule, so the LLM cannot talk its way into a payout.
func _maybe_grant_reward() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var line: String = ConversationRewards.grant_if_earned(gs, _npc_id, _quest_bucket, _exchange_count)
	if line == "":
		return
	var sound: Node = get_node_or_null("/root/SoundManager")
	if sound != null and sound.has_method("play_ui"):
		sound.play_pickup("item_obtain")
	await _show_npc_line(line)


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
	_unregister_with_llm_service()


# ── State handlers ────────────────────────────────────────────────────────────

func _do_opening() -> void:
	var opening_line: String = await _fetch_npc_opening()
	_last_npc_line = opening_line

	await _show_npc_line(opening_line)

	_exchange_count += 1
	_state = State.PLAYER_TURN


func _do_player_turn(player: Node) -> void:
	# Enforce exchange cap: if we're at the limit, skip to sign-off.
	if _exchange_count >= _exchange_cap():
		_state = State.NPC_REPLY
		return

	var choices: Array[String] = await _fetch_player_choices()
	if choices.is_empty():
		# No choices available — end gracefully.
		_state = State.DONE
		return

	# A menu whose every option ENDS the conversation is, to the player, the same
	# as no menu at all. Runs before _ensure_farewell, which would return early.
	_ensure_something_to_say(choices)
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

	# Remembered only past the farewell check. A goodbye is how you LEAVE a
	# conversation, not something you would recognise being reminded you said —
	# and it is always LAST, so it otherwise took a slot of the two we keep.
	if _last_player_line != "":
		_player_lines.append(_last_player_line)

	# Player made a real choice — advance to NPC reply.
	_state = State.NPC_REPLY


func _do_npc_reply() -> void:
	# On sign-off (exchange limit or player is ending): give a closing line.
	if _exchange_count >= _exchange_cap():
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
		_quest_state_lines,
		_resolve_time_of_day(),
		_party_state,
		_memory_lines,
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

	# Dedicated sign-off builder — frames the line as a GOODBYE and threads
	# the conversation tail so the farewell reacts to what was just said.
	# Previously this reused the opening-topical builder, whose prompt told
	# the LLM "Generate exactly ONE opening line spoken by the NPC when the
	# player approaches." — sign-offs often came back reading like greetings.
	var prompt: String = DialoguePrompts.build_npc_sign_off(
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
		DialoguePrompts.SCHEMA_NPC_OPENING,
		DialoguePrompts.FALLBACK_NPC_OPENING,
	)
	_set_thinking(false)

	var validated: Dictionary = DialoguePrompts.validate_npc_opening(raw)
	return validated.get("line", SIGN_OFF_FALLBACK)


func _fetch_player_choices() -> Array[String]:
	var fallback_dict: Dictionary = DialoguePrompts._trimmed_fallback_choices(
		REQUESTED_CHOICES
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
		REQUESTED_CHOICES,
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
		REQUESTED_CHOICES,
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
		_quest_state_lines,
		_resolve_time_of_day(),
		_party_state,
		_memory_lines,
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
			REQUESTED_CHOICES,
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
		REQUESTED_CHOICES,
		_quest_state_lines,
		_party_state,
		_memory_lines,
		_resolve_time_of_day(),
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
		REQUESTED_CHOICES,
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

	# Wrap the menu in a CanvasLayer at the scene root. DynamicConversation
	# is parented to an OverworldNPC (Node2D in world space); adding the
	# menu directly under us makes get_viewport_rect/anchor math evaluate
	# against the world canvas, not the screen viewport, so the panel
	# landed in the upper-right of the window. A CanvasLayer renders in
	# screen space — anchors and positions are viewport-absolute.
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "DynConvChoiceMenuLayer"
	ui_layer.layer = 95  # Above world (default 0), below transitions (100).
	# Attach to the main scene root rather than self so the layer survives
	# briefly if this Node2D gets reparented mid-conversation.
	var root_attach: Node = get_tree().current_scene
	if root_attach == null:
		root_attach = self
	root_attach.add_child(ui_layer)

	_choice_menu = DialogueChoiceMenu.new()
	_choice_menu.name = "DynConvChoiceMenu"
	ui_layer.add_child(_choice_menu)

	var chosen: String = await _choice_menu.present(choices)

	if _choice_menu != null and is_instance_valid(_choice_menu):
		_choice_menu.queue_free()
		_choice_menu = null
	if is_instance_valid(ui_layer):
		ui_layer.queue_free()

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


## Replace a menu whose every option is an exit with the authored fallbacks.
##
## `validate_player_choices` already answers "nothing usable" with the fallback
## set — three times, for a non-Dictionary reply, a non-Array `choices`, and an
## empty survivor list. A menu of nothing but goodbyes is the same state one step
## later and takes the same answer: the player opened a conversation and has
## nothing they can say.
##
## It became reachable when the dedupe landed: three identical goodbyes collapse
## to ONE, and `_ensure_farewell` then returns early because a farewell exists, so
## the player gets a single-option menu whose only option leaves. Measured:
##   ["Farewell.", "Farewell.", "Farewell."]  -> ["Farewell."]
##   ["Goodbye.", "Goodbye.", "Farewell."]    -> ["Goodbye.", "Farewell."]  (fine)
## The failure is non-monotonic — a partially usable reply produced a WORSE menu
## than a completely unusable one, which is why nothing upstream caught it.
##
## Farewell POSITION is untouched and stays the parked design question:
## `_ensure_farewell` runs immediately after this and owns where the exit sits.
func _ensure_something_to_say(choices: Array[String]) -> void:
	if choices.is_empty():
		return
	for c in choices:
		if not _is_farewell(c):
			return
	choices.clear()
	var fallback: Array = DialoguePrompts.FALLBACK_PLAYER_CHOICES["choices"] as Array
	for s in fallback:
		if choices.size() >= REQUESTED_CHOICES:
			break
		if not _is_farewell(str(s)):
			choices.append(str(s))


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
	# A QUESTION IS NEVER A GOODBYE, whatever it opens with. These are prefix
	# matches, so "Take care of that wound — how did you get it?" and "I should go
	# looking for the dragon. Where is its lair?" both read as exits and end the
	# conversation the player was trying to continue. The first is a line the model
	# is MORE likely to write since party condition reached the prompt.
	# Direction matters: a missed farewell costs one extra turn, and the player
	# still has B and the guaranteed exit option. A false farewell cannot be undone
	# — it ends the conversation, banks the memory and settles the reward claim.
	if lower.ends_with("?"):
		return false
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


## Day/night compose (msg 2659): pull current band from GameState for prompt injection; "" if clock is absent (older builds / hermetic tests).
func _resolve_time_of_day() -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_time_of_day_name"):
		return ""
	return str(gs.get_time_of_day_name())


## Register this conversation with LLMService so a scene-change abort_all
## reaches us. Guarded — autoload may be absent in test harnesses.
func _register_with_llm_service() -> void:
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc != null and svc.has_method("register_conversation"):
		svc.register_conversation(self)


func _unregister_with_llm_service() -> void:
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc != null and svc.has_method("unregister_conversation"):
		svc.unregister_conversation(self)


## Dynamic exchange cap — a conversation with more to say earns more turns.
## B still exits at any point; this only moves where the NPC signs off on its own.
func _exchange_cap() -> int:
	var cap: int = MAX_EXCHANGES
	if not _quest_state_lines.is_empty():
		cap += EXCHANGE_BONUS_QUEST_VOICE
	if bool(_party_state.get("in_distress", false)):
		cap += EXCHANGE_BONUS_PARTY_DISTRESS
	return mini(cap, MAX_EXCHANGES_CEILING)


## Snapshot live party state for the prompt. Every read is guarded — a shape
## change in GameState must degrade to a thinner prompt, never break dialogue.
func _resolve_party_state() -> Dictionary:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not ("player_party" in gs):
		return {}
	var out: Dictionary = {}
	var members: Array = []
	var distress: bool = false
	var tally: Dictionary = {}
	for entry in (gs.player_party as Array):
		if not (entry is Dictionary):
			continue
		var cur: int = int(entry.get("current_hp", 0))
		var mx: int = int(entry.get("max_hp", 0))
		var alive: bool = bool(entry.get("is_alive", true))
		if not alive or (mx > 0 and float(cur) / float(mx) < 0.35):
			distress = true
		members.append({
			"name": str(entry.get("name", "?")),
			"job": str(entry.get("job_id", entry.get("job", "adventurer"))),
			"condition": DialoguePrompts.describe_condition(cur, mx, alive),
		})
		var inv: Variant = entry.get("inventory", {})
		if inv is Dictionary:
			for item_id in (inv as Dictionary):
				tally[item_id] = int(tally.get(item_id, 0)) + int((inv as Dictionary)[item_id])
	if not members.is_empty():
		out["members"] = members
	out["in_distress"] = distress
	if "party_gold" in gs:
		out["gold"] = int(gs.party_gold)
	var notable: Array = _top_items(tally)
	if not notable.is_empty():
		out["notable_items"] = notable
	return out


## The few items worth an NPC's notice — highest count first, ids humanised.
func _top_items(tally: Dictionary, limit: int = 4) -> Array:
	var ids: Array = tally.keys()
	ids.sort_custom(func(a, b): return int(tally[a]) > int(tally[b]))
	var out: Array = []
	for i in mini(limit, ids.size()):
		var id_str: String = str(ids[i])
		var n: int = int(tally[id_str])
		var pretty: String = id_str.replace("_", " ")
		out.append("%s x%d" % [pretty, n] if n > 1 else pretty)
	return out
