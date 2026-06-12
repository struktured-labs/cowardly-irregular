## DialoguePrompts — schema definitions and prompt builders for LLM-driven dialogue.
##
## Centralises every prompt template and JSON schema used by the dialogue pillar
## so that call sites (DialogueChoiceGenerator, etc.) never embed raw strings.
##
## Design principles:
##   - All schemas are Dictionaries of { key → type_spec } exactly as LLMService
##     expects for _guard_json validation (string type names or enum Arrays).
##   - All build_* methods return a fully-formed prompt String ready to pass
##     directly to LLMService.complete_json() or LLMService.choose().
##   - Every schema has a matching FALLBACK_* constant so callers never need to
##     invent fallback values.
##   - No runtime state is stored here; this class is entirely functional/static.
##
## JSON output shapes
## ──────────────────
##   NPC opening statement
##     { "line": String }          — single greeting/opening line for the NPC
##
##   Player choice menu
##     { "choices": Array }        — ordered list of up to MAX_CHOICES strings;
##                                   each entry is a short player dialogue option

class_name DialoguePrompts
extends RefCounted


# ── Limits ────────────────────────────────────────────────────────────────────

## Maximum number of player-choice options the LLM may return.
const MAX_CHOICES: int = 4

## Hard character cap for a single NPC opening line.
const MAX_LINE_CHARS: int = 200

## Hard character cap for each individual choice string.
const MAX_CHOICE_CHARS: int = 80

## How many recent EventLog entries to include in prompts.
const CONTEXT_EVENTS: int = 5


# ── Schemas (passed to LLMService.complete_json for guard validation) ─────────

## Schema for NPC opening statement responses.
## Expected JSON: { "line": "..." }
const SCHEMA_NPC_OPENING: Dictionary = {
	"line": "String",
}

## Schema for player choice menu responses.
## Expected JSON: { "choices": [...] }
const SCHEMA_PLAYER_CHOICES: Dictionary = {
	"choices": "Array",
}


# ── Fallback constants ────────────────────────────────────────────────────────

## Fallback NPC opening response used when the LLM fails or returns garbage.
## Returned as a validated Dictionary matching SCHEMA_NPC_OPENING.
const FALLBACK_NPC_OPENING: Dictionary = {
	"line": "...",
}

## Fallback player choices returned on any failure.
## Four generic JRPG conversation openers that are always valid.
const FALLBACK_PLAYER_CHOICES: Dictionary = {
	"choices": [
		"Tell me more.",
		"What's going on around here?",
		"Do you need help?",
		"Farewell.",
	],
}


# ── Prompt builders: NPC opening ──────────────────────────────────────────────

## Build a prompt asking the LLM to generate a single NPC opening statement.
##
## Parameters:
##   npc_name       — display name of the NPC (e.g. "Elder Theron")
##   npc_persona    — short personality blurb (e.g. "wise elder, formal tone")
##   location       — current map/area name (e.g. "Verdant Vale Village")
##   recent_events  — Array[Dictionary] from EventLog.recent(); may be empty
##
## Returns a prompt String ready for LLMService.complete_json().
static func build_npc_opening(
	npc_name: String,
	npc_persona: String,
	location: String,
	recent_events: Array,
) -> String:
	var ctx_block: String = _format_events(recent_events, CONTEXT_EVENTS)

	return (
		"You are writing dialogue for a meta-aware JRPG called 'Cowardly Irregular'.\n"
		+ "Generate exactly ONE opening line spoken by the NPC when the player approaches.\n"
		+ "\n"
		+ "NPC: %s\n" % npc_name
		+ "Persona: %s\n" % npc_persona
		+ "Location: %s\n" % location
		+ ctx_block
		+ "\n"
		+ "Rules:\n"
		+ "- Stay in character; no modern slang unless the setting demands it.\n"
		+ "- Maximum %d characters.\n" % MAX_LINE_CHARS
		+ "- Do NOT include the NPC name or speaker label in the line.\n"
		+ "- Respond with ONLY valid JSON: {\"line\": \"<text>\"}\n"
	)


## Build a prompt asking the LLM for a contextual NPC opening, with an explicit
## topic hint to guide flavour (e.g. "a recent boss defeat" or "the party's low HP").
##
## Convenience overload of build_npc_opening; the topic is appended to persona.
static func build_npc_opening_topical(
	npc_name: String,
	npc_persona: String,
	location: String,
	topic: String,
	recent_events: Array,
) -> String:
	var extended_persona: String = "%s — today's topic: %s" % [npc_persona, topic]
	return build_npc_opening(npc_name, extended_persona, location, recent_events)


# ── Prompt builders: player choice menu ──────────────────────────────────────

## Build a prompt asking the LLM to generate N player dialogue choices.
##
## Parameters:
##   npc_name       — who the player is talking to
##   npc_line       — the NPC's current/opening line (sets context for player reply)
##   num_choices    — how many choices to generate (clamped to [1, MAX_CHOICES])
##   recent_events  — Array[Dictionary] from EventLog.recent(); may be empty
##
## Returns a prompt String ready for LLMService.complete_json().
static func build_player_choices(
	npc_name: String,
	npc_line: String,
	num_choices: int,
	recent_events: Array,
) -> String:
	var count: int = clampi(num_choices, 1, MAX_CHOICES)
	var ctx_block: String = _format_events(recent_events, CONTEXT_EVENTS)

	return (
		"You are writing player dialogue options for a meta-aware JRPG called 'Cowardly Irregular'.\n"
		+ "The player just heard the following from %s:\n" % npc_name
		+ "  \"%s\"\n" % npc_line
		+ ctx_block
		+ "\n"
		+ "Generate exactly %d short player dialogue choices the player can respond with.\n" % count
		+ "\n"
		+ "Rules:\n"
		+ "- Each choice is a first-person player statement or question, max %d characters.\n" % MAX_CHOICE_CHARS
		+ "- Choices should cover a range of tones: curious, cautious, friendly, direct.\n"
		+ "- Do NOT number the choices or add bullet points.\n"
		+ "- Respond with ONLY valid JSON: {\"choices\": [\"...\", \"...\"]}\n"
	)


## Build a player-choices prompt that emphasises a specific emotional tone.
## Useful for scenes where the narrative dictates a narrower choice range
## (e.g. a confrontation scene wants choices in the aggressive/nervous range).
##
## tone_hint — short label like "tense", "comedic", "solemn" injected into rules.
static func build_player_choices_toned(
	npc_name: String,
	npc_line: String,
	num_choices: int,
	tone_hint: String,
	recent_events: Array,
) -> String:
	var count: int = clampi(num_choices, 1, MAX_CHOICES)
	var ctx_block: String = _format_events(recent_events, CONTEXT_EVENTS)

	return (
		"You are writing player dialogue options for a meta-aware JRPG called 'Cowardly Irregular'.\n"
		+ "The player just heard the following from %s:\n" % npc_name
		+ "  \"%s\"\n" % npc_line
		+ ctx_block
		+ "\n"
		+ "Generate exactly %d short player dialogue choices.\n" % count
		+ "\n"
		+ "Rules:\n"
		+ "- Tone: %s — all choices should feel consistent with this mood.\n" % tone_hint
		+ "- Each choice is a first-person player statement or question, max %d characters.\n" % MAX_CHOICE_CHARS
		+ "- Do NOT number the choices or add bullet points.\n"
		+ "- Respond with ONLY valid JSON: {\"choices\": [\"...\", \"...\"]}\n"
	)


# ── Validation helpers ─────────────────────────────────────────────────────────

## Validate and sanitise an LLM-returned NPC opening Dictionary.
##
## Accepts the raw Variant from LLMService.complete_json().
## Returns a safe Dictionary matching SCHEMA_NPC_OPENING, falling back to
## FALLBACK_NPC_OPENING on any problem — never returns null or crashes.
##
## Clamps line length to MAX_LINE_CHARS.
static func validate_npc_opening(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return FALLBACK_NPC_OPENING.duplicate()

	var d: Dictionary = raw as Dictionary
	var line: Variant = d.get("line", null)
	if not (line is String) or (line as String).strip_edges().is_empty():
		return FALLBACK_NPC_OPENING.duplicate()

	var s: String = (line as String).strip_edges()
	if s.length() > MAX_LINE_CHARS:
		s = s.left(MAX_LINE_CHARS)

	return {"line": s}


## Validate and sanitise an LLM-returned player choices Dictionary.
##
## Accepts the raw Variant from LLMService.complete_json().
## Returns a safe Dictionary with a non-empty "choices" Array of Strings.
## Falls back to FALLBACK_PLAYER_CHOICES on any problem.
##
## Clamps each choice to MAX_CHOICE_CHARS and drops non-String entries.
static func validate_player_choices(raw: Variant, expected_count: int) -> Dictionary:
	var count: int = clampi(expected_count, 1, MAX_CHOICES)

	if not (raw is Dictionary):
		return _trimmed_fallback_choices(count)

	var d: Dictionary = raw as Dictionary
	var raw_choices: Variant = d.get("choices", null)
	if not (raw_choices is Array):
		return _trimmed_fallback_choices(count)

	var choices_arr: Array = raw_choices as Array
	var out: Array[String] = []
	for item in choices_arr:
		if not (item is String):
			continue
		var s: String = (item as String).strip_edges()
		if s.is_empty():
			continue
		if s.length() > MAX_CHOICE_CHARS:
			s = s.left(MAX_CHOICE_CHARS)
		out.append(s)
		if out.size() >= count:
			break

	if out.is_empty():
		return _trimmed_fallback_choices(count)

	return {"choices": out}


# ── Internal helpers ──────────────────────────────────────────────────────────

## Format recent EventLog entries as a compact context block for inclusion in prompts.
## Returns empty string when events is empty.
static func _format_events(events: Array, limit: int) -> String:
	if events.is_empty():
		return ""

	var n: int = mini(events.size(), limit)
	var lines: PackedStringArray = PackedStringArray()
	var start: int = events.size() - n
	for i in range(start, events.size()):
		var entry: Dictionary = events[i]
		var summary: String = str(entry.get("summary", ""))
		var etype: String = str(entry.get("type", ""))
		if summary.is_empty():
			continue
		lines.append("  [%s] %s" % [etype, summary])

	if lines.is_empty():
		return ""

	return "\nRecent events:\n" + "\n".join(lines) + "\n"


## Return a copy of FALLBACK_PLAYER_CHOICES trimmed to `count` items.
static func _trimmed_fallback_choices(count: int) -> Dictionary:
	var src: Array = FALLBACK_PLAYER_CHOICES["choices"] as Array
	var trimmed: Array[String] = []
	var limit: int = mini(count, src.size())
	for i in range(limit):
		trimmed.append(str(src[i]))
	return {"choices": trimmed}
