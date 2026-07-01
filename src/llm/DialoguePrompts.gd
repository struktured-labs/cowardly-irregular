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

## Schema for NPC follow-up reply (response to the player's chosen line).
## Expected JSON: { "line": "..." }
const SCHEMA_NPC_REPLY: Dictionary = {
	"line": "String",
}

## Schema for the optional combined NPC-reply + next-choices payload, used
## when both fit comfortably under the prompt budget. Saves one round trip.
const SCHEMA_COMBINED_REPLY: Dictionary = {
	"reply":   "String",
	"choices": "Array",
}

## Schema for the boss strategic-intent picker. The LLM picks ONE of the
## boss's pre-authored scripted_intents (aggress / turtle / etc.) based on
## battle state, plus a short in-character taunt. The validator enforces
## intent_id ∈ available_intents — the LLM cannot invent ability names
## (see BossDialogue's "STAKES GUARDRAIL: never let the LLM name an
## ability" — strategy lives at the intent level only).
const SCHEMA_BOSS_INTENT: Dictionary = {
	"intent_id": "String",
	"reason":    "String",
	"taunt":     "String",
}

## Schema for the party-combat-line generator (PC speaks an in-character line at a battle event).
const SCHEMA_PARTY_LINE: Dictionary = {
	"line": "String",
	"mood": "String",
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

## Generic conversational continuations used when the NPC-reply LLM call
## fails or returns garbage. Cycled by the caller so successive failures
## don't repeat the same line.
const FALLBACK_NPC_REPLY_LINES: Array = [
	"Hmm... go on.",
	"I see.",
	"That's something to think on.",
	"Is that so?",
	"You don't say.",
	"Interesting...",
	"Perhaps you have a point.",
]

## Default fallback envelope for a single NPC reply.
const FALLBACK_NPC_REPLY: Dictionary = {
	"line": "Hmm... go on.",
}

## Default fallback envelope for the combined reply+choices payload.
const FALLBACK_COMBINED_REPLY: Dictionary = {
	"reply": "Hmm... go on.",
	"choices": [
		"Tell me more.",
		"What's going on around here?",
		"Do you need help?",
		"Farewell.",
	],
}

## Fallback boss intent envelope. intent_id is intentionally empty here —
## validate_boss_intent's caller treats empty intent_id as "use the
## deterministic weighted-random picker" so the existing strategy layer
## takes over silently.
const FALLBACK_BOSS_INTENT: Dictionary = {
	"intent_id": "",
	"reason":    "",
	"taunt":     "",
}

## Hard cap on the LLM's freeform reason/taunt strings so a runaway
## generation doesn't blow up the combat log.
const MAX_BOSS_TAUNT_CHARS: int = 140
const MAX_BOSS_REASON_CHARS: int = 240

## Fallback envelope for party-line — empty line signals caller to use scripted pool.
const FALLBACK_PARTY_LINE: Dictionary = {
	"line": "",
	"mood": "neutral",
}

const MAX_PARTY_LINE_CHARS: int = 140
const PARTY_LINE_MOODS: Array[String] = ["anxious", "cocky", "focused", "panicked", "neutral"]

## Allowlist of valid boss intent_id tags accepted by validate_boss_intent_reply.
## Includes the 3 original intents (aggress, turtle, exploit_pattern) plus 6 widened
## counter-strategy tags (fire_resist, ice_resist, lightning_resist, focus_healer,
## defense_boost, rotate_aggro). Unknown intent_id values fall back cleanly.
const _BOSS_INTENT_ALLOWLIST := [
	"aggress", "turtle", "exploit_pattern",
	"fire_resist", "ice_resist", "lightning_resist",
	"focus_healer", "defense_boost", "rotate_aggro",
]

const AUTOBATTLE_GRAMMAR_DESCRIPTION := """Autobattle rules are evaluated top-to-bottom, first match wins.
Each rule shape:
  {conditions: [...], actions: [...], enabled: true}

Conditions (AND-chained). type is one of:
  hp_percent, mp_percent, ap, has_status, enemy_hp_percent, ally_hp_percent,
  turn, enemy_count, ally_count, item_count, setup_complete,
  ally_has_status, ally_mp_percent, always
Each numeric condition takes op ∈ {<, <=, ==, >=, >, !=} and value.
has_status / ally_has_status take a 'status' field (e.g. 'poison').

Actions (executed in order, up to 4 per rule). type is one of:
  attack, ability, item, defer
ability requires id (e.g. 'cure', 'fire').
item requires id (e.g. 'potion').

Targets. Values:
  lowest_hp_enemy, highest_hp_enemy, random_enemy,
  highest_speed_enemy, highest_atk_enemy, lowest_magic_defense_enemy,
  lowest_hp_ally, all_allies, self

Canonical example:
  {\"conditions\":[{\"type\":\"ally_has_status\",\"status\":\"poison\"},
                   {\"type\":\"mp_percent\",\"op\":\">=\",\"value\":15}],
   \"actions\":[{\"type\":\"ability\",\"id\":\"esuna\",\"target\":\"lowest_hp_ally\"}],
   \"enabled\":true}

Prefer specific rules over general ones. Put the fallback (a rule with
{type:'always'} condition and an attack action) last."""

const AUTOGRIND_GRAMMAR_DESCRIPTION := """Autogrind rules control the WHOLE PARTY's grind session (not per-character).
Rules are evaluated top-to-bottom, first match wins.

Conditions (AND-chained). type is one of:
  party_hp_min, party_hp_avg, party_mp_avg, alive_count, member_dead,
  member_injured, corruption, efficiency, battles_done, win_streak,
  time_elapsed, inventory_items, ability_learned, reached_level,
  rare_item_found, always
Numeric conditions take op ∈ {<, <=, ==, >=, >, !=} and value.

Actions. type is one of:
  stop_grinding, heal_party, restore_mp, flee_battle, switch_profile
switch_profile requires character_id (PC id string) and profile_index (int).

Canonical example:
  {\"conditions\":[{\"type\":\"party_hp_min\",\"op\":\"<\",\"value\":30}],
   \"actions\":[{\"type\":\"heal_party\"}],
   \"enabled\":true}

Put the fallback (a rule with {type:'always'} condition) last, if any."""


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


# ── Prompt builder: NPC sign-off ─────────────────────────────────────────────

## Build a prompt asking the LLM to generate a single CLOSING line — the
## NPC's farewell when the exchange limit hits or the player ends the chat.
##
## Crucially this is NOT another opening: previously the sign-off path
## delegated to build_npc_opening_topical("a polite farewell"), whose prompt
## literally said "Generate exactly ONE opening line spoken by the NPC when
## the player approaches." The LLM had to fight that framing, and the result
## often read like another greeting. This builder frames the line as a
## farewell explicitly, threads the conversation tail so the goodbye actually
## reacts to what was just said, and reuses the SCHEMA_NPC_OPENING shape so
## validate_npc_opening still applies.
static func build_npc_sign_off(
	npc_name: String,
	npc_persona: String,
	location: String,
	recent_events: Array,
	last_npc_line: String,
	player_line: String,
) -> String:
	var ctx_block: String = _format_events(recent_events, CONTEXT_EVENTS)

	var history_block: String = ""
	if last_npc_line.strip_edges() != "":
		history_block += "\nYou previously said:\n  \"%s\"\n" % last_npc_line.strip_edges()
	if player_line.strip_edges() != "":
		history_block += "The player just responded:\n  \"%s\"\n" % player_line.strip_edges()

	return (
		"You are writing dialogue for a meta-aware JRPG called 'Cowardly Irregular'.\n"
		+ "Generate exactly ONE closing line — the NPC's farewell as the conversation ends.\n"
		+ "\n"
		+ "NPC: %s\n" % npc_name
		+ "Persona: %s\n" % npc_persona
		+ "Location: %s\n" % location
		+ history_block
		+ ctx_block
		+ "\n"
		+ "Rules:\n"
		+ "- This is a GOODBYE, not a greeting; do NOT restart the conversation.\n"
		+ "- React briefly to the player's last words if appropriate, then close warmly.\n"
		+ "- Stay in character; no modern slang unless the setting demands it.\n"
		+ "- Maximum %d characters.\n" % MAX_LINE_CHARS
		+ "- Do NOT include the NPC name or speaker label in the line.\n"
		+ "- Respond with ONLY valid JSON: {\"line\": \"<text>\"}\n"
	)


# ── Prompt builders: NPC follow-up reply ─────────────────────────────────────

## Build a prompt asking the LLM to generate a single NPC follow-up line
## that responds to the player's most recent dialogue choice.
##
## Crucially, this prompt threads BOTH the prior NPC line and the player's
## chosen response into the context — without this, the call site silently
## reuses build_npc_opening and the conversation devolves into two
## interleaved monologues (see plan slice item 5).
##
## Parameters:
##   npc_name       — display name of the NPC
##   npc_persona    — short personality blurb
##   location       — current map/area name
##   recent_events  — Array[Dictionary] from EventLog.recent(); may be empty
##   last_npc_line  — the NPC's previous spoken line (may be "")
##   player_line    — the player's chosen response (may be "")
##
## Returns a prompt String ready for LLMService.complete_json().
static func build_npc_reply(
	npc_name: String,
	npc_persona: String,
	location: String,
	recent_events: Array,
	last_npc_line: String,
	player_line: String,
) -> String:
	var ctx_block: String = _format_events(recent_events, CONTEXT_EVENTS)

	var history_block: String = ""
	if last_npc_line.strip_edges() != "":
		history_block += "\nYou previously said:\n  \"%s\"\n" % last_npc_line.strip_edges()
	if player_line.strip_edges() != "":
		history_block += "The player just responded:\n  \"%s\"\n" % player_line.strip_edges()

	return (
		"You are writing dialogue for a meta-aware JRPG called 'Cowardly Irregular'.\n"
		+ "Generate exactly ONE follow-up line spoken by the NPC, responding directly to what the player just said.\n"
		+ "\n"
		+ "NPC: %s\n" % npc_name
		+ "Persona: %s\n" % npc_persona
		+ "Location: %s\n" % location
		+ history_block
		+ ctx_block
		+ "\n"
		+ "Rules:\n"
		+ "- Acknowledge or react to the player's specific words; do NOT restart the conversation.\n"
		+ "- Stay in character; no modern slang unless the setting demands it.\n"
		+ "- Maximum %d characters.\n" % MAX_LINE_CHARS
		+ "- Do NOT include the NPC name or speaker label in the line.\n"
		+ "- Respond with ONLY valid JSON: {\"line\": \"<text>\"}\n"
	)


## Build a single-round-trip prompt that asks the LLM for BOTH the NPC's
## follow-up line AND the next set of player choices in one response.
## Used when the prompt budget allows — halves the latency.
##
## Parameters mirror build_npc_reply plus num_choices.
##
## Returns a prompt String ready for LLMService.complete_json().
static func build_combined_reply(
	npc_name: String,
	npc_persona: String,
	location: String,
	recent_events: Array,
	last_npc_line: String,
	player_line: String,
	num_choices: int,
) -> String:
	var count: int = clampi(num_choices, 1, MAX_CHOICES)
	var ctx_block: String = _format_events(recent_events, CONTEXT_EVENTS)

	var history_block: String = ""
	if last_npc_line.strip_edges() != "":
		history_block += "\nYou previously said:\n  \"%s\"\n" % last_npc_line.strip_edges()
	if player_line.strip_edges() != "":
		history_block += "The player just responded:\n  \"%s\"\n" % player_line.strip_edges()

	return (
		"You are writing dialogue for a meta-aware JRPG called 'Cowardly Irregular'.\n"
		+ "Produce BOTH the NPC's follow-up line AND %d short player dialogue choices in one JSON object.\n" % count
		+ "\n"
		+ "NPC: %s\n" % npc_name
		+ "Persona: %s\n" % npc_persona
		+ "Location: %s\n" % location
		+ history_block
		+ ctx_block
		+ "\n"
		+ "Rules:\n"
		+ "- The NPC reply must react to the player's specific words; max %d characters.\n" % MAX_LINE_CHARS
		+ "- Each player choice is a first-person statement/question, max %d characters.\n" % MAX_CHOICE_CHARS
		+ "- Choices should cover a range of tones: curious, cautious, friendly, direct.\n"
		+ "- Do NOT number the choices or add bullet points.\n"
		+ "- Respond with ONLY valid JSON: {\"reply\": \"<text>\", \"choices\": [\"...\", \"...\"]}\n"
	)


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


# ── Prompt builder: boss strategic intent ─────────────────────────────────────

## Build the prompt asked of the LLM at each boss phase transition.
##
## ctx is a BossIntentContext (passed as Dictionary via to_dict()) so this
## function stays decoupled from the class. The LLM picks ONE of
## ctx.available_intents and writes a short in-character taunt for the
## moment the new posture lands.
##
## Parameters:
##   display_name — boss display name (e.g. "Chancellor Mordaine")
##   ctx          — Dictionary from BossIntentContext.to_dict()
##
## Returns a prompt String ready for LLMService.complete_json().
static func build_boss_intent(
	display_name: String,
	ctx: Dictionary,
) -> String:
	var persona: String = str(ctx.get("persona", ""))
	if persona.is_empty():
		persona = "A formidable JRPG boss."
	var phase: int = int(ctx.get("phase", 1))
	var hp_pct: float = float(ctx.get("boss_hp_pct", 100.0))
	var mp_pct: float = float(ctx.get("boss_mp_pct", 100.0))
	var ap: int = int(ctx.get("boss_ap", 0))
	var boss_status: Array = ctx.get("boss_status", []) as Array
	var party: Array = ctx.get("party", []) as Array
	var intents: Array = ctx.get("available_intents", []) as Array
	var recent: Array = ctx.get("recent_actions", []) as Array

	var party_lines: PackedStringArray = PackedStringArray()
	for member in party:
		if not (member is Dictionary):
			continue
		var alive: bool = bool(member.get("is_alive", true))
		var alive_tag: String = "alive" if alive else "DEAD"
		var status_arr: Array = member.get("status", []) as Array
		var status_tag: String = ("/" + ",".join(_strs_packed(status_arr))) if status_arr.size() > 0 else ""
		party_lines.append("  - %s (%s): HP %d%%, AP %d %s%s" % [
			str(member.get("name", "?")),
			str(member.get("job_id", "?")),
			int(member.get("hp_pct", 100)),
			int(member.get("ap", 0)),
			alive_tag,
			status_tag,
		])

	var recent_lines: PackedStringArray = PackedStringArray()
	for entry in recent:
		if not (entry is Dictionary):
			continue
		var kind: String = str(entry.get("kind", ""))
		var actor: String = str(entry.get("actor", "?"))
		var ability: String = str(entry.get("ability_id", "?"))
		var target: String = str(entry.get("target", ""))
		var dmg: int = int(entry.get("damage", 0))
		var dmg_tag: String = (" (%d dmg)" % dmg) if dmg != 0 else ""
		var tgt_tag: String = (" → %s" % target) if target != "" else ""
		recent_lines.append("  - [%s] %s used %s%s%s" % [kind, actor, ability, tgt_tag, dmg_tag])

	var intent_block: String = ""
	for id in intents:
		intent_block += "  - %s\n" % str(id)
	if intent_block.is_empty():
		intent_block = "  - (no scripted intents available — return empty intent_id)\n"

	var boss_status_tag: String = ", ".join(_strs_packed(boss_status)) if boss_status.size() > 0 else "none"
	var party_block: String = "\n".join(party_lines) if party_lines.size() > 0 else "  (no live party data)"
	var recent_block: String = "\n".join(recent_lines) if recent_lines.size() > 0 else "  (no recent actions)"

	return (
		"You are the strategic mind of %s, a boss in the meta-aware JRPG 'Cowardly Irregular'.\n" % display_name
		+ "Stay rigorously in character. Persona:\n"
		+ "  %s\n" % persona
		+ "\n"
		+ "It is the start of phase %d.\n" % phase
		+ "Your state: HP %d%%, MP %d%%, AP %d, status: %s.\n" % [int(hp_pct), int(mp_pct), ap, boss_status_tag]
		+ "Party state:\n%s\n" % party_block
		+ "Recent exchange (oldest → newest):\n%s\n" % recent_block
		+ "\n"
		+ "Pick exactly ONE intent for this phase from this list (anything else is a parse error):\n"
		+ intent_block
		+ "\n"
		+ "Rules:\n"
		+ "- intent_id MUST be one of the listed values, verbatim.\n"
		+ "- reason: one short sentence (≤ %d chars) explaining WHY this intent fits the moment. Internal use only.\n" % MAX_BOSS_REASON_CHARS
		+ "- taunt: one in-character line (≤ %d chars) to surface in the combat log. No quote marks.\n" % MAX_BOSS_TAUNT_CHARS
		+ "- Respond with ONLY valid JSON: {\"intent_id\": \"...\", \"reason\": \"...\", \"taunt\": \"...\"}\n"
	)


# ── Prompt builder: party combat line ────────────────────────────────────────

## Build the prompt asked of the LLM when a party member speaks a combat line.
static func build_party_line(
	persona: String,
	signature_phrases: Array,
	ctx: Dictionary,
) -> String:
	var event_kind: String = str(ctx.get("event_kind", "turn_start"))
	var speaker_name: String = str(ctx.get("speaker_name", "the character"))
	var speaker_job: String = str(ctx.get("speaker_job_id", "fighter"))
	var hp_pct: float = float(ctx.get("speaker_hp_pct", 100.0))
	var mp_pct: float = float(ctx.get("speaker_mp_pct", 100.0))
	var status: Array = ctx.get("speaker_status", []) as Array
	var personality: String = str(ctx.get("speaker_personality", ""))
	var party: Array = ctx.get("party", []) as Array
	var enemies: Array = ctx.get("enemies", []) as Array
	var recent: Array = ctx.get("recent_actions", []) as Array
	var event_data: Dictionary = ctx.get("event_data", {}) as Dictionary

	var sig_block: String = ""
	for phrase in signature_phrases:
		sig_block += "  - %s\n" % str(phrase)
	if sig_block.is_empty():
		sig_block = "  (none)\n"

	var party_lines: PackedStringArray = PackedStringArray()
	for member in party:
		if not (member is Dictionary):
			continue
		var alive_tag: String = "alive" if bool(member.get("is_alive", true)) else "DEAD"
		party_lines.append("  - %s (%s): HP %d%%, %s" % [
			str(member.get("name", "?")),
			str(member.get("job_id", "?")),
			int(member.get("hp_pct", 100)),
			alive_tag,
		])

	var enemy_lines: PackedStringArray = PackedStringArray()
	for foe in enemies:
		if not (foe is Dictionary):
			continue
		enemy_lines.append("  - %s: HP %d%%" % [
			str(foe.get("name", "?")),
			int(foe.get("hp_pct", 100)),
		])

	var recent_lines: PackedStringArray = PackedStringArray()
	for entry in recent:
		if not (entry is Dictionary):
			continue
		recent_lines.append("  - %s used %s%s" % [
			str(entry.get("actor", "?")),
			str(entry.get("ability_id", "?")),
			(" (%d dmg)" % int(entry.get("damage", 0))) if int(entry.get("damage", 0)) != 0 else "",
		])

	var status_tag: String = ", ".join(_strs_packed(status)) if status.size() > 0 else "none"
	var party_block: String = "\n".join(party_lines) if party_lines.size() > 0 else "  (solo)"
	var enemy_block: String = "\n".join(enemy_lines) if enemy_lines.size() > 0 else "  (no enemies)"
	var recent_block: String = "\n".join(recent_lines) if recent_lines.size() > 0 else "  (no recent actions)"
	var personality_block: String = ("Personality trait: %s.\n" % personality) if not personality.is_empty() else ""

	var event_hint: String = _party_line_event_hint(event_kind, event_data)
	var moods: String = ", ".join(PARTY_LINE_MOODS)

	return (
		"You voice %s, the party's %s, in the meta-aware JRPG 'Cowardly Irregular'.\n" % [speaker_name, speaker_job]
		+ "Stay rigorously in character. Persona:\n"
		+ "  %s\n" % persona
		+ personality_block
		+ "Signature phrases (use the rhythm — do NOT copy verbatim every turn):\n"
		+ sig_block
		+ "\n"
		+ "Your state: HP %d%%, MP %d%%, status: %s.\n" % [int(hp_pct), int(mp_pct), status_tag]
		+ "Party state:\n%s\n" % party_block
		+ "Enemies:\n%s\n" % enemy_block
		+ "Recent exchange (oldest → newest):\n%s\n" % recent_block
		+ "\n"
		+ "Trigger: %s. %s\n" % [event_kind, event_hint]
		+ "\n"
		+ "Rules:\n"
		+ "- line: ONE in-character utterance (≤ %d chars). No quote marks. No NPC names other than party/enemy listed above.\n" % MAX_PARTY_LINE_CHARS
		+ "- mood: ONE of %s.\n" % moods
		+ "- Respond with ONLY valid JSON: {\"line\": \"...\", \"mood\": \"...\"}\n"
	)


## Per-event hint string used in build_party_line.
static func _party_line_event_hint(event_kind: String, event_data: Dictionary) -> String:
	match event_kind:
		"turn_start":
			return "Your initiative just landed. Say something short before you act."
		"low_hp":
			return "You just dropped below 25%% HP. React in voice — worry, cockiness, prayer, etc., per your persona."
		"big_hit_taken":
			var amt: int = int(event_data.get("damage", 0))
			return "You just took a chunky hit (%d damage). React without breaking character." % amt
		"used_signature_ability":
			var ability: String = str(event_data.get("ability_id", "your signature move"))
			return "You just landed %s — flex or downplay it per your persona." % ability
		"victory":
			return "The party just won. You speak FIRST — set the tone for the post-battle moment."
		_:
			return "Speak a single line that fits the moment, in voice."


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


## Validate and sanitise an LLM-returned NPC reply Dictionary.
##
## Accepts the raw Variant from LLMService.complete_json().
## Returns a safe Dictionary matching SCHEMA_NPC_REPLY, falling back to
## a cycled FALLBACK_NPC_REPLY_LINES entry on any problem. Never crashes.
##
## Clamps line length to MAX_LINE_CHARS.
static func validate_npc_reply(raw: Variant, cycle_index: int = 0) -> Dictionary:
	if not (raw is Dictionary):
		return _fallback_reply(cycle_index)

	var d: Dictionary = raw as Dictionary
	var line: Variant = d.get("line", null)
	if not (line is String) or (line as String).strip_edges().is_empty():
		return _fallback_reply(cycle_index)

	var s: String = (line as String).strip_edges()
	if s.length() > MAX_LINE_CHARS:
		s = s.left(MAX_LINE_CHARS)

	return {"line": s}


## Validate the combined reply+choices payload from build_combined_reply.
## On any failure, falls back to a coherent reply + the default choice set.
static func validate_combined_reply(raw: Variant, expected_count: int, cycle_index: int = 0) -> Dictionary:
	var count: int = clampi(expected_count, 1, MAX_CHOICES)

	if not (raw is Dictionary):
		return _fallback_combined(count, cycle_index)

	var d: Dictionary = raw as Dictionary
	var reply_raw: Variant = d.get("reply", null)
	var reply: String = ""
	if reply_raw is String and not (reply_raw as String).strip_edges().is_empty():
		reply = (reply_raw as String).strip_edges()
		if reply.length() > MAX_LINE_CHARS:
			reply = reply.left(MAX_LINE_CHARS)
	else:
		reply = _fallback_reply_line(cycle_index)

	# Reuse validate_player_choices for the choices side.
	var choices_dict: Dictionary = validate_player_choices(
		{"choices": d.get("choices", [])},
		count,
	)

	return {
		"reply":   reply,
		"choices": choices_dict.get("choices", []),
	}


## Validate and sanitise an LLM-returned boss intent Dictionary.
##
## Accepts the raw Variant from LLMService.complete_json() and the list
## of intent IDs the boss currently has access to (already phase-filtered
## by BossIntentContext.available_intents).
##
## Returns a safe Dictionary matching SCHEMA_BOSS_INTENT. On ANY failure —
## raw isn't a Dictionary, intent_id missing, intent_id not in available,
## reason/taunt malformed — returns FALLBACK_BOSS_INTENT (intent_id == "")
## so the caller's deterministic path takes over. Never crashes, never
## returns an intent the boss can't actually execute.
##
## Clamps reason to MAX_BOSS_REASON_CHARS and taunt to MAX_BOSS_TAUNT_CHARS.
static func validate_boss_intent(raw: Variant, available_intents: Array) -> Dictionary:
	if not (raw is Dictionary):
		return FALLBACK_BOSS_INTENT.duplicate()

	var d: Dictionary = raw as Dictionary
	var intent_raw: Variant = d.get("intent_id", null)
	if not (intent_raw is String):
		return FALLBACK_BOSS_INTENT.duplicate()
	var intent_id: String = (intent_raw as String).strip_edges()
	if intent_id.is_empty():
		return FALLBACK_BOSS_INTENT.duplicate()

	# Gate: intent_id MUST be in the boss's pre-filtered intent list.
	# This is the stakes guardrail — the LLM never invents an intent.
	var allowed: bool = false
	for a in available_intents:
		if str(a) == intent_id:
			allowed = true
			break
	if not allowed:
		return FALLBACK_BOSS_INTENT.duplicate()

	var reason: String = ""
	var reason_raw: Variant = d.get("reason", "")
	if reason_raw is String:
		reason = (reason_raw as String).strip_edges()
		if reason.length() > MAX_BOSS_REASON_CHARS:
			reason = reason.left(MAX_BOSS_REASON_CHARS)

	var taunt: String = ""
	var taunt_raw: Variant = d.get("taunt", "")
	if taunt_raw is String:
		taunt = (taunt_raw as String).strip_edges()
		if taunt.length() > MAX_BOSS_TAUNT_CHARS:
			taunt = taunt.left(MAX_BOSS_TAUNT_CHARS)

	return {
		"intent_id": intent_id,
		"reason":    reason,
		"taunt":     taunt,
	}


## Validate and sanitise an LLM-returned boss intent reply using the hardcoded
## _BOSS_INTENT_ALLOWLIST. Simpler than validate_boss_intent — does not require
## a caller-provided available_intents array, only checks against the global allowlist.
##
## Returns a safe Dictionary matching SCHEMA_BOSS_INTENT. On ANY failure — raw
## isn't a Dictionary, intent_id missing, intent_id not in _BOSS_INTENT_ALLOWLIST,
## reason/taunt malformed — returns FALLBACK_BOSS_INTENT (intent_id == "") so the
## caller's deterministic path takes over. Never crashes, never returns an intent
## not in the allowlist.
##
## Clamps reason to MAX_BOSS_REASON_CHARS and taunt to MAX_BOSS_TAUNT_CHARS.
static func validate_boss_intent_reply(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return FALLBACK_BOSS_INTENT.duplicate()

	var d: Dictionary = raw as Dictionary
	var intent_raw: Variant = d.get("intent_id", null)
	if not (intent_raw is String):
		return FALLBACK_BOSS_INTENT.duplicate()
	var intent_id: String = (intent_raw as String).strip_edges()
	if intent_id.is_empty():
		return FALLBACK_BOSS_INTENT.duplicate()

	# Gate: intent_id MUST be in the allowlist.
	if not (intent_id in _BOSS_INTENT_ALLOWLIST):
		return FALLBACK_BOSS_INTENT.duplicate()

	var reason: String = ""
	var reason_raw: Variant = d.get("reason", "")
	if reason_raw is String:
		reason = (reason_raw as String).strip_edges()
		if reason.length() > MAX_BOSS_REASON_CHARS:
			reason = reason.left(MAX_BOSS_REASON_CHARS)

	var taunt: String = ""
	var taunt_raw: Variant = d.get("taunt", "")
	if taunt_raw is String:
		taunt = (taunt_raw as String).strip_edges()
		if taunt.length() > MAX_BOSS_TAUNT_CHARS:
			taunt = taunt.left(MAX_BOSS_TAUNT_CHARS)

	return {
		"intent_id": intent_id,
		"reason":    reason,
		"taunt":     taunt,
	}


## Validate party-line LLM output. Empty line ⇒ caller routes to scripted fallback.
static func validate_party_line(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return FALLBACK_PARTY_LINE.duplicate()
	var d: Dictionary = raw as Dictionary
	var line_raw: Variant = d.get("line", "")
	if not (line_raw is String):
		return FALLBACK_PARTY_LINE.duplicate()
	var line: String = (line_raw as String).strip_edges()
	if line.is_empty():
		return FALLBACK_PARTY_LINE.duplicate()
	if line.length() > MAX_PARTY_LINE_CHARS:
		line = line.left(MAX_PARTY_LINE_CHARS)
	var mood: String = "neutral"
	var mood_raw: Variant = d.get("mood", "neutral")
	if mood_raw is String:
		var m: String = (mood_raw as String).strip_edges().to_lower()
		if m in PARTY_LINE_MOODS:
			mood = m
	return {
		"line": line,
		"mood": mood,
	}


# ── Internal helpers ──────────────────────────────────────────────────────────


## Coerce an Array into a PackedStringArray (drops non-Stringables).
## Used by build_boss_intent's status-tag joiners.
static func _strs_packed(items: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for x in items:
		out.append(str(x))
	return out

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
		var tags: String = _format_event_tags(entry)
		lines.append("  [%s] %s%s" % [etype, summary, tags])

	if lines.is_empty():
		return ""

	return "\nRecent events:\n" + "\n".join(lines) + "\n"


## Surface rich-data flags from an EventLog entry as terse trailing tags so
## the LLM can react to HOW something happened, not just THAT it did. Only
## flags that are TRUE / non-default contribute — false flags would be
## prompt noise that the LLM would helpfully but pointlessly acknowledge.
##
## Current decorations:
##   boss_defeat → "[autobattled]" if tactics.pure_autobattle,
##                 "[jailbreak landed]" if tactics.jailbreak_landed,
##                 "[all-out attack]" if tactics.all_out_attack_used.
## Returns "" when the entry has no decorable data or no truthy flags.
static func _format_event_tags(entry: Dictionary) -> String:
	var etype: String = str(entry.get("type", ""))
	var data: Variant = entry.get("data", {})
	if not (data is Dictionary):
		return ""
	var d: Dictionary = data as Dictionary
	var tags: PackedStringArray = PackedStringArray()
	match etype:
		"boss_defeat":
			var t: Variant = d.get("tactics", {})
			if t is Dictionary:
				var td: Dictionary = t as Dictionary
				if bool(td.get("pure_autobattle", false)):
					tags.append("autobattled")
				if bool(td.get("jailbreak_landed", false)):
					tags.append("jailbreak landed")
				if bool(td.get("all_out_attack_used", false)):
					tags.append("all-out attack")
	if tags.is_empty():
		return ""
	return " [%s]" % ", ".join(tags)


## Return a copy of FALLBACK_PLAYER_CHOICES trimmed to `count` items.
static func _trimmed_fallback_choices(count: int) -> Dictionary:
	var src: Array = FALLBACK_PLAYER_CHOICES["choices"] as Array
	var trimmed: Array[String] = []
	var limit: int = mini(count, src.size())
	for i in range(limit):
		trimmed.append(str(src[i]))
	return {"choices": trimmed}


## Cycle through FALLBACK_NPC_REPLY_LINES so consecutive failures don't
## repeat the same line back to the player.
static func _fallback_reply_line(cycle_index: int) -> String:
	var src: Array = FALLBACK_NPC_REPLY_LINES
	if src.is_empty():
		return "..."
	var idx: int = posmod(cycle_index, src.size())
	return str(src[idx])


## Validated fallback envelope for a single NPC reply.
static func _fallback_reply(cycle_index: int) -> Dictionary:
	return {"line": _fallback_reply_line(cycle_index)}


## Validated fallback envelope for the combined reply+choices payload.
static func _fallback_combined(count: int, cycle_index: int) -> Dictionary:
	var choices_dict: Dictionary = _trimmed_fallback_choices(count)
	return {
		"reply":   _fallback_reply_line(cycle_index),
		"choices": choices_dict.get("choices", []),
	}
