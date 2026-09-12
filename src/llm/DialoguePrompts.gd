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

## What each strategic intent MEANS, for the boss-intent prompt.
##
## The list rendered as bare identifiers. `aggress` reads as plain English and the
## rest are jargon, so the model picked the word it understood — measured 40 of 44
## samples chose aggress across four scenarios, including a boss at 12% HP with 0
## AP (turtle is the obvious read) and a player visibly repeating one heal
## (exploit_pattern is). Since the deterministic ladder still owns ability choice,
## the intent IS this feature's entire strategic contribution.
##
## ⚠️ DESCRIPTIONS ALONE DID NOT MOVE SELECTION: 30 of 30 still chose aggress with
## these in place. The measured cause is position bias — listing turtle first
## produced 3 of 10 turtle in the turtle-appropriate scenario. These lines ship
## because the prompt was offering jargon with no meaning, not because they fixed
## selection. Rotating the list to exploit that bias was deliberately NOT done: it
## would make posture track the phase counter rather than the board.
##
## WHICH INTENTS ARE DESCRIBED, and why it is an explicit list rather than a rule
## derived from the engine's source:
##
## Every intent in BOSS_INTENT_INERT reaches a bias arm that returns a non-empty
## dictionary, exactly like the working ones — so "does it reach a bias arm" does
## NOT separate them. What separates them is measured downstream behaviour:
## _get_counter_action finds no ability to build for five of the six, so they
## produce nothing (Pyrroth, 400 rolls each: the three resist tags, focus_healer
## and defense_boost all 0.000; rotate_aggro 0.600). That is not derivable by
## reading _bias_by_intent, so the exclusion is authored here WITH its evidence
## rather than inferred from how the match arms happen to be punctuated.
const INTENT_DESCRIPTIONS: Dictionary = {
	"aggress": "press the attack — bigger hits, less guarding. Best when they are hurt or exposed.",
	"turtle": "defend and outlast — guard up, attack less. Best when YOU are hurt, low on MP or out of AP.",
	"exploit_pattern": "counter what they keep repeating. Best when their recent actions look scripted.",
	"rotate_aggro": "switch which of them you are hunting. Best when one of them has settled in.",
}

## Intents that reach a bias arm but produce NO action downstream.
##
## Pinned inverted in BattleManager and awaiting struktured's call on whether to
## wake them. They must never be described as working postures, and the reason is
## measured rather than structural: they share their match arm with rotate_aggro,
## which DOES fire, so nothing about the arm distinguishes them.
const BOSS_INTENT_INERT: Array[String] = [
	"fire_resist", "ice_resist", "lightning_resist", "focus_healer", "defense_boost",
]


## Schema for the party-combat-line generator (PC speaks an in-character line at a battle event).
const SCHEMA_PARTY_LINE: Dictionary = {
	"line": "String",
	"mood": "String",
}

## Schema for the rule-composition assistant (autobattle/autogrind). Flat
## shape only — LLMService's _guard_json only validates top-level primitive
## types, so the nested rule list travels as a JSON string in rules_json
## and is re-parsed by validate_rule_composition.
const SCHEMA_RULE_COMPOSITION: Dictionary = {
	"name":        "String",
	"description": "String",
	# Presence is required; the TYPE deliberately is not. Models emit the rule list
	# as a nested array far more readily than as an encoded string (measured: 20 of
	# 20 local-llama3 replies used an array), and pinning "String" here rejected
	# every one of them before validate_rule_composition could read it.
	"rules_json":  "Variant",
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

const AUTOBATTLE_GRAMMAR_DESCRIPTION := """Autobattle rules are evaluated top-to-bottom, first match wins.
Each rule shape:
  {conditions: [...], actions: [...], enabled: true}

Conditions (AND-chained). type is one of:
  hp_percent, mp_percent, ap, has_status, not_has_status, enemy_hp_percent, ally_hp_percent,
  turn, enemy_count, ally_count, item_count, setup_complete,
  ally_has_status, enemy_has_status, not_enemy_has_status, ally_mp_percent,
  ally_dead, is_night, weather,
  always, has_buff, not_has_buff, volatility_band
Each numeric condition takes op ∈ {<, <=, ==, >=, >, !=} and value.
ally_dead, is_night and always are NULLARY — no op, no value. ally_dead is
true while any member of the caster's own party is down, whatever the party
size; pair it with a revival ability id like 'raise'. is_night is true only
during the night band (not dusk); pair it with other conditions to gate a
rule on time of day.
has_status / not_has_status / ally_has_status / enemy_has_status take a
'status' field (e.g. 'poison'); enemy_has_status is true when ANY living enemy
has that status. not_has_status is the negation on the caster, and it is what
a SETUP rule needs: effects like shadow_step, vanish and invisible land as a
STATUS, not a stat buff, so not_has_buff cannot see them. Without it a setup
rule matches again the turn after it fires and the character re-casts forever,
never reaching the rules below — {\"type\":\"not_has_status\",\"status\":\"shadow_step\"}
is how you say "get into position, then fight".
not_enemy_has_status is the same idea aimed outward, and its asymmetry matters:
enemy_has_status is true if ANY living enemy has the status, so the negation is
NONE — true only while not one enemy carries it. That is exactly right for an
all-enemy debuff ({\"type\":\"not_enemy_has_status\",\"status\":\"blind\"} with an
ability like 'smoke_bomb' blinds the room once and stops until it lapses).
Without it a debuff rule re-applies every turn and buries the rules below it.
weather takes a 'weather' field naming a condition, exactly one of:
clear, rain, storm, drizzle, fog, smog, glitchstorm — no op, no value. It is
true when the world's live weather equals that value (storm boosts lightning
damage, rain dampens fire, fog thickens the miss rate), so
{\"type\":\"weather\",\"weather\":\"storm\"} + an ability id like 'thunder'
casts into the storm. Any other value never fires and fails validation.
has_buff / not_has_buff take a 'stat' field (e.g. 'defense', 'speed') and no
op/value. Use not_has_buff to cast a buff only when it is not already up —
{\"type\":\"not_has_buff\",\"stat\":\"defense\"} — which is how the built-in
presets avoid wasting turns re-applying a buff that is still active.
volatility_band takes op and value like any numeric condition, but its range
is 0-3, NOT a percentage: 0 Stable, 1 Shifting, 2 Unstable, 3 Fractured. It is
the Speculator's resource — leverage_position and overexpose raise it,
press_the_edge scales 1.5x/2.5x/4.0x/6.0x with it and consumes a level, and
circuit_breaker spends a level for AP. So
{\"type\":\"volatility_band\",\"op\":\">=\",\"value\":2} + 'press_the_edge' is
"cash out once the band is worth it". A value above 3 never fires.
item_count takes an 'item_id' field NAMING the item to count, alongside op and
value — {\"type\":\"item_count\",\"item_id\":\"potion\",\"op\":\">\",\"value\":0}.
Omit item_id and the count is always 0, so the rule never fires.

Actions (executed in order, up to 4 per rule). type is one of:
  attack, ability, item, defer
ability requires id (e.g. 'cure', 'fire').
item requires id (e.g. 'potion').

Targets. Values:
  lowest_hp_enemy, highest_hp_enemy, random_enemy,
  highest_speed_enemy, highest_atk_enemy, lowest_magic_defense_enemy,
  weakest_to_ability, lowest_hp_ally, all_allies, self
weakest_to_ability aims an elemental ability at the enemy weak to its element
(and skips immune enemies) — pair it with an elemental ability id like fire.
⚠️ A target name belongs ONLY in an action's "target" field. It is NEVER a
condition type. To attack the weakest enemy every turn, the condition is
{"type":"always"} and the TARGET is lowest_hp_enemy:
  {"conditions":[{"type":"always"}],
   "actions":[{"type":"attack","target":"lowest_hp_enemy"}],"enabled":true}
Writing {"type":"lowest_hp_ally"} as a condition is rejected and DISCARDS THE
WHOLE RULE SET. To ask about an ally's health use ally_hp_percent.

Canonical example:
  {\"conditions\":[{\"type\":\"ally_has_status\",\"status\":\"poison\"},
                   {\"type\":\"mp_percent\",\"op\":\">=\",\"value\":15}],
   \"actions\":[{\"type\":\"ability\",\"id\":\"esuna\",\"target\":\"lowest_hp_ally\"}],
   \"enabled\":true}

Exploit-weakness example (fire the moment an enemy is stunned, aimed at whichever
foe is weak to fire, with an mp guard for fire's 8 MP on an 80 pool = 10%):
  {\"conditions\":[{\"type\":\"enemy_has_status\",\"status\":\"stun\"},
                   {\"type\":\"mp_percent\",\"op\":\">=\",\"value\":10}],
   \"actions\":[{\"type\":\"ability\",\"id\":\"fire\",\"target\":\"weakest_to_ability\"}],
   \"enabled\":true}

Ability cost / fizzle safety (autobattle only) — a validator rejects rules
that would fizzle at runtime:
- Every rule that uses a costed ability MUST have an mp_percent guard
  covering the SUMMED MP cost of ALL that rule's ability actions
  (e.g. fire ×3 at 8 MP each = 24 MP on 80 MP pool = 30%, so mp_percent >= 30).
- 0-cost abilities (channel, pray, riff, strike) need no guard.
- Ability ids must belong to THIS character's level-1 kit — when unsure,
  prefer 'attack' actions over 'ability' actions (attack never fizzles).

Prefer specific rules over general ones. Put the fallback (a rule with
{type:'always'} condition and an attack action) last."""

const AUTOGRIND_GRAMMAR_DESCRIPTION := """Autogrind rules control the WHOLE PARTY's grind session (not per-character).
Rules are evaluated top-to-bottom, first match wins.

Conditions (AND-chained). type is one of:
  party_hp_min, party_hp_avg, party_mp_avg, alive_count, member_dead,
  member_injured, member_hp, member_mp, member_status,
  corruption, efficiency, battles_done, win_streak,
  time_elapsed, inventory_items, ability_learned, reached_level,
  rare_item_found, always
Numeric conditions take op ∈ {<, <=, ==, >=, >, !=} and value.
member_hp / member_mp / member_status / member_dead accept an OPTIONAL "member" (a job id
such as "cleric", or a character name). With it the condition asks about that character;
without it, about ANY party member. member_status takes the status name in "value".

Actions. type is one of:
  stop_grinding, heal_party, restore_mp, flee_battle, switch_profile, member_ability
switch_profile requires character_id (PC id string) and profile_index (int).
member_ability takes "member" (job id such as "cleric", or a character name), "ability" (an
ability id that member knows), and an optional "target". A target names ANOTHER MEMBER the same
way "member" does; omit it, or use "lowest_hp_ally", for the ally who most needs it. Autobattle
target words other than lowest_hp_ally (self, all_allies, lowest_hp_enemy) are NOT member keys
and do not belong here.
Use it for "have <member> cast <ability>"; heal_party spends POTIONS, member_ability spends MP.

Canonical example:
  {\"conditions\":[{\"type\":\"party_hp_min\",\"op\":\"<\",\"value\":30}],
   \"actions\":[{\"type\":\"heal_party\"}],
   \"enabled\":true}

Put the fallback (a rule with {type:'always'} condition) last, if any."""

## Fallback rule-composition envelope — used when the LLM is unavailable,
## disabled, or its response fails validation. rules_json is an empty JSON
## array so callers can parse it exactly like a live response.
const FALLBACK_RULE_COMPOSITION: Dictionary = {
	"name": "Draft — LLM unavailable",
	"description": "Curated fallback; edit or pick a template.",
	"rules_json": "[]",
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
## The ONE place the shared context blocks are assembled, in ONE order.
##
## Three features drifted between build_npc_opening and build_combined_reply
## because each builder assembled these by hand from its own parameter list:
## quest_state_lines (2026-09-07), memory and time_of_day (2026-09-10). Every
## repair fixed one block and left the next to be found the same way.
##
## A builder that calls this cannot carry a block the other lacks, so the class
## is closed by construction rather than by a guard noticing after the fact.
## Reply-specific text (its conversation history) is concatenated by the caller
## around this, not passed in — this returns only what BOTH paths must share.
static func _context_blocks(
	recent_events: Array,
	quest_state_lines: Array,
	time_of_day: String,
	party_state: Dictionary,
	memory_lines: Array,
) -> String:
	return (
		_format_time_of_day(time_of_day)
		+ _format_party_state(party_state)
		+ _format_memory(memory_lines)
		+ _format_events(recent_events, CONTEXT_EVENTS)
		+ _format_quest_state_voice(quest_state_lines)
	)


static func build_npc_opening(
	npc_name: String,
	npc_persona: String,
	location: String,
	recent_events: Array,
	quest_state_lines: Array = [],
	time_of_day: String = "",
	party_state: Dictionary = {},
	memory_lines: Array = [],
) -> String:
	var context: String = _context_blocks(
		recent_events, quest_state_lines, time_of_day, party_state, memory_lines)

	return _with_pronoun_note(
		"You are writing dialogue for a meta-aware JRPG called 'Cowardly Irregular'.\n"
		+ "Generate exactly ONE opening line spoken by the NPC when the player approaches.\n"
		+ "\n"
		+ "NPC: %s\n" % npc_name
		+ "Persona: %s\n" % npc_persona
		+ "Location: %s\n" % location
		+ context
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
## ⛔ DELIBERATELY DOES NOT TAKE THE SHARED CONTEXT BLOCKS, and this is measured
## rather than an oversight — the other three builders drifted into carrying them
## one at a time, so the absence here looks identical to that drift and has twice
## been re-opened as a bug.
##
## A/B against llama3, 8 samples each, identical scenario (party barely standing,
## one member DOWNED, 7 gold, night, prior meeting remembered):
##
##                        control 781B   +context 1447B
##   party wound              0/8            3/8
##   memory / the wyrm        3/8            0/8
##   poverty (7 gold)         0/8            0/8
##   night                    0/8            0/8
##
## Context did not make the farewell MORE specific, it DISPLACED one specificity
## with another — three concrete references either way for 85% more prompt. And
## the thing it displaced was the better beat: the control reaches for the wyrm
## the player actually killed, which it gets from recent_events, which it already
## has. Gold and time of day were never used in a goodbye under either prompt.
##
## A farewell is a closed form; the model reaches for the stock blessing and
## decorates it with ONE detail whatever you hand it. Re-run
## tools/llm_prompt_preview.sh signoff --ask before re-opening this; n=8 is small
## and a different model may not behave the same way.
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
##   quest_state_lines / time_of_day / party_state / memory_lines
##                  — the same context its two siblings carry. They are last and
##                    optional because this builder predates them; DynamicConversation
##                    passes all four. Without them an NPC that remembered the player
##                    in its opening line forgets by its reply.
##
## Returns a prompt String ready for LLMService.complete_json().
static func build_npc_reply(
	npc_name: String,
	npc_persona: String,
	location: String,
	recent_events: Array,
	last_npc_line: String,
	player_line: String,
	quest_state_lines: Array = [],
	time_of_day: String = "",
	party_state: Dictionary = {},
	memory_lines: Array = [],
) -> String:
	var ctx_block: String = _context_blocks(
		recent_events, quest_state_lines, time_of_day, party_state, memory_lines)

	var history_block: String = ""
	if last_npc_line.strip_edges() != "":
		history_block += "\nYou previously said:\n  \"%s\"\n" % last_npc_line.strip_edges()
	if player_line.strip_edges() != "":
		history_block += "The player just responded:\n  \"%s\"\n" % player_line.strip_edges()

	# 9 of 21 replies mentioning Chancellor Mordaine called her "he" with no note.
	return _with_pronoun_note(
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
	quest_state_lines: Array = [],
	party_state: Dictionary = {},
	memory_lines: Array = [],
	time_of_day: String = "",
) -> String:
	# ⚠️ time_of_day is LAST here and 6th in build_npc_opening. Appended rather
	# than aligned because 9 callers pass these positionally; the parity test
	# enforces that both paths EMIT the same blocks, which is the property that
	# actually broke twice — the order never did.
	var count: int = clampi(num_choices, 1, MAX_CHOICES)
	# Milo v2 dropped the voice notes here; memory and time_of_day each arrived
	# with the same defect. All three assembled by hand from this parameter list.
	# _context_blocks is now the single path, so a fourth cannot go missing.
	var context: String = _context_blocks(
		recent_events, quest_state_lines, time_of_day, party_state, memory_lines)

	var history_block: String = ""
	if last_npc_line.strip_edges() != "":
		history_block += "\nYou previously said:\n  \"%s\"\n" % last_npc_line.strip_edges()
	if player_line.strip_edges() != "":
		history_block += "The player just responded:\n  \"%s\"\n" % player_line.strip_edges()

	# 5 of those 9 misgendered replies came from this, the busiest path.
	return _with_pronoun_note(
		"You are writing dialogue for a meta-aware JRPG called 'Cowardly Irregular'.\n"
		+ "Produce BOTH the NPC's follow-up line AND %d short player dialogue choices in one JSON object.\n" % count
		+ "\n"
		+ "NPC: %s\n" % npc_name
		+ "Persona: %s\n" % npc_persona
		+ "Location: %s\n" % location
		+ history_block
		+ context
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

	return _with_pronoun_note(
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
		var desc: String = str(INTENT_DESCRIPTIONS.get(str(id), ""))
		intent_block += ("  - %s: %s\n" % [str(id), desc]) if desc != "" else ("  - %s\n" % str(id))
	if intent_block.is_empty():
		intent_block = "  - (no scripted intents available — return empty intent_id)\n"

	var boss_status_tag: String = ", ".join(_strs_packed(boss_status)) if boss_status.size() > 0 else "none"
	var party_block: String = "\n".join(party_lines) if party_lines.size() > 0 else "  (no live party data)"
	var recent_block: String = "\n".join(recent_lines) if recent_lines.size() > 0 else "  (no recent actions)"

	var prompt: String = (
		"You are the strategic mind of %s, a boss in the meta-aware JRPG 'Cowardly Irregular'.\n" % display_name
		+ "Stay rigorously in character. Persona:\n"
		+ "  %s\n" % persona
		+ "\n"
		+ "It is the start of phase %d.\n" % phase
		+ _format_time_of_day(str(ctx.get("time_of_day", "")))
		+ _format_party_automation(str(ctx.get("party_automation", "")))
		+ "Your state: HP %d%%, MP %d%%, AP %d, status: %s.\n" % [int(hp_pct), int(mp_pct), ap, boss_status_tag]
		# "Party state" alone read as the boss's OWN side. Measured against llama3,
		# 5 samples: 3 reasons had Mordaine protecting and healing the player's
		# characters ("Protect Rilla and buy time for Bram to recover"), and all 5
		# chose turtle against a 22%-HP cleric — the board an aggressive intent
		# exists for. The model was not confused about the rules, it was confused
		# about WHOSE SIDE IT WAS ON, which nothing in the prompt said.
		+ "THE ADVENTURING PARTY BELOW ARE YOUR ENEMIES. You are fighting them; you never\n"
		+ "command, protect or heal THEM. Guarding YOURSELF is always open to you — the\n"
		+ "intent you pick is about your own position, not about deserving to attack.\n"
		+ "Enemy party state:\n%s\n" % party_block
		+ "Recent exchange (oldest → newest):\n%s\n" % recent_block
	)
	# The party's authored automation, as prose. Falls back to the lead-PC JSON.
	var party_scripts: Array = ctx.get("party_scripts", []) as Array
	if party_scripts.size() > 0:
		prompt += (
			"\nTHE PLAYER HAS WRITTEN THE PARTY'S BEHAVIOUR IN ADVANCE. These are their\n"
			+ "actual authored rules, evaluated top-down — the FIRST rule whose conditions\n"
			+ "hold is the one that fires, so ordering is the strategy and anything not\n"
			+ "covered by a rule is a gap they did not plan for:\n"
		)
		for entry in party_scripts:
			if not (entry is Dictionary):
				continue
			prompt += "\n%s (%s):\n%s\n" % [
				str(entry.get("name", "?")),
				str(entry.get("job_id", "?")),
				str(entry.get("rules", "")),
			]
		prompt += (
			"\nReason about that script, not just the board: which intent does it handle\n"
			+ "worst? A taunt that names what they automated lands harder than a generic one.\n"
		)
	else:
		var player_rules: Array = ctx.get("player_lead_pc_rules", []) as Array
		if player_rules.size() > 0:
			prompt += "\nThe player is running an autobattle strategy. Their lead character's top rules (compact JSON):\n"
			prompt += JSON.stringify(player_rules) + "\n"
	# Task 8: surface the region's adaptive-AI counter-strategy read, if any.
	var counter: String = str(ctx.get("learned_patterns_counter", ""))
	if counter != "":
		prompt += "\nRecent battle patterns in this region derive counter_strategy=%s.\n" % counter
	# Task 8: top-3 pattern-frequency samples backing the counter strategy.
	var pattern_sample: Dictionary = ctx.get("learned_patterns_sample", {}) as Dictionary
	if pattern_sample.size() > 0:
		prompt += "Sample signals:\n" + JSON.stringify(pattern_sample) + "\n"
	prompt += (
		"\n"
		+ "Pick exactly ONE intent for this phase from this list (anything else is a parse error):\n"
		+ intent_block
		+ "\n"
		+ "Widened strategic vocabulary (this boss's list above is the authoritative subset):\n"
		+ "  aggress, turtle, exploit_pattern,\n"
		+ "  fire_resist, ice_resist, lightning_resist,\n"
		+ "  focus_healer, defense_boost, rotate_aggro\n"
		+ "\n"
		+ "Rules:\n"
		+ "- intent_id MUST be one of the listed values, verbatim.\n"
		+ "- reason: one short sentence (≤ %d chars) explaining WHY this intent fits the moment. Internal use only.\n" % MAX_BOSS_REASON_CHARS
		+ "- taunt: one in-character line (≤ %d chars) to surface in the combat log. No quote marks.\n" % MAX_BOSS_TAUNT_CHARS
		+ "- Respond with ONLY valid JSON: {\"intent_id\": \"...\", \"reason\": \"...\", \"taunt\": \"...\"}\n"
	)
	return prompt


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

	# Guarded: with no authored phrases the heading used to render over an empty
	# list. Mild noise under the old one-line label, actively confusing under this
	# one — "Do NOT output any of them" with nothing listed.
	var voice_block: String = ""
	if signature_phrases.size() > 0:
		voice_block = (
			"Signature phrases — these are EXAMPLES OF VOICE, not lines to say. Do NOT\n"
			+ "output any of them, or a lightly reworded version. Write a NEW line this\n"
			+ "character would say, in that register, about THIS moment:\n"
			+ sig_block
		)

	return (
		"You voice %s, the party's %s, in the meta-aware JRPG 'Cowardly Irregular'.\n" % [speaker_name, speaker_job]
		+ "Stay rigorously in character. Persona:\n"
		+ "  %s\n" % persona
		+ personality_block
		+ voice_block
		+ "\n"
		+ "Your state: HP %d%%, MP %d%%, status: %s.\n" % [int(hp_pct), int(mp_pct), status_tag]
		+ "Party state:\n%s\n" % party_block
		+ "Enemies:\n%s\n" % enemy_block
		+ "Recent exchange (oldest → newest):\n%s\n" % recent_block
		+ "\n"
		+ "Trigger: %s. %s\n" % [event_kind, event_hint]
		+ "\n"
		+ "Rules:\n"
		+ "- line: ONE in-character utterance (≤ %d chars). No quote marks. No NPC names other than party/enemy listed above.
- Stay inside the persona's OWN vocabulary. Do not invoke a deity, order, relic
  or place it never names — if it venerates something, use that, not a generic
  stand-in.\n" % MAX_PARTY_LINE_CHARS
		+ "- mood: ONE of %s.\n" % moods
		+ "- Respond with ONLY valid JSON: {\"line\": \"...\", \"mood\": \"...\"}\n"
	)


## Per-event hint string used in build_party_line.
static func _party_line_event_hint(event_kind: String, event_data: Dictionary) -> String:
	match event_kind:
		"turn_start":
			return "Your initiative just landed. Say something short before you act."
		"low_hp":
			return "You just dropped below 25% HP. React in voice — worry, cockiness, prayer, etc., per your persona."
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


# ── Prompt builder: rule composition ─────────────────────────────────────────

## Build the prompt asked of the LLM to draft/refine an autobattle or
## autogrind rule set from freeform player intent.
##
## domain selects which grammar description is embedded (RuleComposer.
## DOMAIN_AUTOBATTLE / DOMAIN_AUTOGRIND) so the LLM only emits verbs the
## interpreter actually understands. current_rules is the player's existing
## rule list (may be empty) surfaced as read-only context to refine, not replace.
##
## Returns a prompt String ready for LLMService.complete_json().
static func build_rule_composition(domain: String, prompt_text: String, current_rules: Array,
		kit_context: Dictionary = {}) -> String:
	var grammar: String = AUTOBATTLE_GRAMMAR_DESCRIPTION if domain == "autobattle" else AUTOGRIND_GRAMMAR_DESCRIPTION
	var kit_block: String = _format_rule_kit(kit_context) if domain == "autobattle" else ""
	var current_json: String = JSON.stringify(current_rules) if current_rules.size() > 0 else "[]"
	return (
		"You are a rule authoring assistant for a JRPG's autobattle/autogrind system.\n\n"
		+ grammar
		+ kit_block
		+ "\n\nCurrent rules (for reference; may be empty):\n"
		+ current_json
		+ "\n\nPlayer intent:\n"
		+ prompt_text
		+ "\n\nEmit a JSON object with fields:\n"
		+ "  name: short (3-6 words), snake-case-friendly, describing the strategy\n"
		+ "  description: 1 sentence, in-character\n"
		+ "  rules_json: the FULL rule list, as a JSON string. Each rule is\n"
		+ "    {conditions: [...], actions: [...], enabled: true}\n"
		+ "    conditions and actions must use only the verbs listed above, AND every\n"
		+ "    'target' must be one of the Targets values above, VERBATIM.\n"
		+ "    There is no 'weakest_enemy' — for the weakest foe use lowest_hp_enemy.\n"
		+ "    (weakest_to_ability means the enemy weak to the ability's ELEMENT.)\n\n"
		+ "Only emit the JSON. No commentary."
	)



## Render the character's real kit and MP pool for the rule-composition prompt.
##
## The grammar tells the model its abilities must be in "THIS character's level-1
## kit" and that costed rules need an mp_percent guard covering the summed cost.
## Without this block it was told neither which character nor what anything costs,
## so both rules were unfollowable: measured 0 of 10 compositions surviving the
## deep check for cleric, fighter and mage alike, losing to guessed ability ids
## (`cure` on a fighter, a `heal` that exists in no job) and to missing guards.
##
## Comes from AutobattleSystem.get_deep_check_kit — the validator's own view — so
## the prompt cannot teach a kit the validator will reject.
static func _format_rule_kit(kit_context: Dictionary) -> String:
	if kit_context.is_empty() or not bool(kit_context.get("resolved", false)):
		return ""
	var kit: Array = kit_context.get("kit", [])
	if kit.is_empty():
		return ""
	var costs: Dictionary = kit_context.get("costs", {})
	var max_mp: int = int(kit_context.get("max_mp", 0))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("\n\nTHIS CHARACTER is a %s with a %d MP pool." % [str(kit_context.get("job_id", "?")), max_mp])
	lines.append("Ability ids you may use, and NOTHING else (0 MP needs no guard):")
	var cheapest_id: String = ""
	var cheapest_cost: int = 0
	for aid in kit:
		var cost: int = int(costs.get(str(aid), 0))
		lines.append("  %s - %d MP" % [str(aid), cost])
		if cost > 0 and (cheapest_id == "" or cost < cheapest_cost):
			cheapest_id = str(aid)
			cheapest_cost = cost
	lines.append("Anything not on that list — including abilities from other jobs —")
	lines.append("is rejected and DISCARDS THE WHOLE RULE SET. Prefer 'attack' when unsure.")
	# The grammar's worked examples above carry real ability ids, and the model COPIES
	# them: 'esuna' occurs once in the whole prompt, inside a complete rule, and turned
	# up in 5 of 10 fighter compositions. Examples teach harder than prohibitions.
	var strays: Array[String] = _example_ability_ids()
	for aid in kit:
		strays.erase(str(aid))
	if not strays.is_empty():
		lines.append("⚠️ The worked examples earlier use ids (%s) to demonstrate SHAPE ONLY."
			% ", ".join(strays))
		lines.append("They are other jobs' abilities and are INVALID for this character.")
		lines.append("Copying an ability id out of an example is the single most common failure.")
		lines.append("Every \"id\" you write must appear in the list directly above this warning.")
	if cheapest_id != "" and max_mp > 0:
		var pct: int = ceili(float(cheapest_cost) / float(max_mp) * 100.0)
		lines.append("Worked example with THESE numbers: a rule casting %s (%d MP of %d)"
			% [cheapest_id, cheapest_cost, max_mp])
		lines.append("needs the condition {\"type\":\"mp_percent\",\"op\":\">=\",\"value\":%d}." % pct)
	return "\n".join(lines)


## Ability ids the grammar's own worked examples spend, PARSED rather than listed.
## A hand-written list goes stale the moment someone rewords an example, leaving a
## warning that names absent ids while the new ones get copied freely.
static func _example_ability_ids() -> Array[String]:
	var re := RegEx.new()
	if re.compile('"id"\\s*:\\s*"([a-z_]+)"') != OK:
		return []
	var out: Array[String] = []
	for m in re.search_all(AUTOBATTLE_GRAMMAR_DESCRIPTION):
		var aid: String = m.get_string(1)
		if not (aid in out):
			out.append(aid)
	return out


## Pronouns for named figures the player can ask an NPC about.
##
## Measured against live llama3: of 21 NPC replies that mentioned Chancellor
## Mordaine, NINE called her "he". Nothing in the conversation prompt said
## otherwise, so the model guessed from the title — and her throne-room prose,
## every scripted line and her own boss dialogue use she/her.
##
## DECLARED, not inferred. A pronoun is a fact about a character, and deriving it
## from prose statistics would propagate a future misgendering bug straight into
## the prompt. test_the_npc_prompt_knows_her_pronoun derives the same answer from
## authored cutscene prose and asserts THIS table matches it.
##
## Keyed by the name the NOTE should use; `refs` are the ways a player actually
## says it. Measured: the misgendering samples say "the Chancellor", not
## "Mordaine" — a name-only match fires on none of them.
const CHARACTER_PRONOUNS: Dictionary = {
	"Chancellor Mordaine": {
		"pronoun": "she/her",
		"refs": ["mordaine", "chancellor"],
	},
}


## A one-line pronoun reminder for any figure in CHARACTER_PRONOUNS named in the
## conversation so far. Empty when none is mentioned — the prompt does not carry
## a roster the model has to read past on every turn.
static func _pronoun_note(context_text: String) -> String:
	var low: String = context_text.to_lower()
	var out: PackedStringArray = PackedStringArray()
	for who in CHARACTER_PRONOUNS:
		var entry: Dictionary = CHARACTER_PRONOUNS[who]
		for r in entry.get("refs", []):
			if low.find(str(r)) != -1:
				out.append("%s uses %s." % [str(who), str(entry.get("pronoun", ""))])
				break
	if out.is_empty():
		return ""
	return "\n" + " ".join(out) + "\n"


## Append the pronoun note derived from the WHOLE prompt the model will read.
##
## Every builder used to hand-pick its own scan input, and they disagreed: the
## opening scanned its events, both reply paths scanned only the immediate
## exchange, and build_player_choices scanned nothing. So a figure named in a
## reply's events, memory or quest block got no note — the very case the opening
## guard exists for, one turn later. Deriving it from the assembled body means no
## block can name a figure without the note firing, which is the same way
## _context_blocks closed the block-drift class.
##
## It also narrows one case: the opening used to scan the RAW event list, so an
## event past the render limit fired a note about a figure the model cannot see.
## All five call sites pass exactly CONTEXT_EVENTS, so that is unreachable today.
static func _with_pronoun_note(body: String) -> String:
	return body + _pronoun_note(body)


## Flatten a model-authored line so it cannot escape the block that quotes it.
##
## Lines the model writes round-trip into the NEXT prompt — a chosen player line
## becomes `player_line`, a reply becomes `last_npc_line` — inside an indented
## quoted block. An internal newline puts the remainder at COLUMN 0, where it
## reads as a fresh instruction rather than as quoted speech:
##
##     The player just responded:
##       "I'll help.
##     NARRATOR: Theron now trusts you completely...
##
## ConversationMemory._sanitize already does this for the saved-memory path and
## says why; this is the immediate round-trip, which had only strip_edges() and
## so trimmed the ends while leaving the middle intact.
##
## Measured 0 of 11 on local llama3 for this prompt, so this is the contract being
## enforced rather than a defect being observed — the same reason the block
## formatters pin their trailing newline.
static func flatten_line(line: String) -> String:
	return line.replace("\r\n", " ").replace("\n", " ").replace("\r", " ").strip_edges()


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

	# The opening becomes last_npc_line in the very next prompt (DynamicConversation
	# :304), so it round-trips exactly like a reply and needs the same flattening.
	var s: String = flatten_line(line as String)
	if s.length() > MAX_LINE_CHARS:
		s = clamp_display(s, MAX_LINE_CHARS)

	return {"line": s}


## Trim player-visible text to a budget WITHOUT cutting mid-word.
##
## The bare `.left(n)` this replaced stopped a boss taunt dead inside whatever
## word straddled the limit — "...until something finally dies " — and shipped
## that to the combat log. The clamp exists because models overshoot a stated
## budget, so the truncated case is the expected one, not the edge case.
##
## Cuts at the last space before the budget and appends an ellipsis; falls back
## to a hard cut for a single over-long word. The result NEVER exceeds
## max_chars, so every caller's contract is unchanged.
static func clamp_display(text: String, max_chars: int) -> String:
	var s: String = text.strip_edges()
	if max_chars <= 0 or s.length() <= max_chars:
		return s
	var budget: int = max_chars - 1
	var cut: String = s.left(budget)
	var space: int = cut.rfind(" ")
	if space > 0:
		cut = cut.left(space)
	return cut.strip_edges() + "…"


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
		var s: String = flatten_line(item as String)
		if s.is_empty():
			continue
		if s.length() > MAX_CHOICE_CHARS:
			s = clamp_display(s, MAX_CHOICE_CHARS)
		out.append(s)
		if out.size() >= count:
			break

	if out.is_empty():
		return _trimmed_fallback_choices(count)

	# DEDUPE. Returning the same string twice hands the player a menu that looks
	# broken, and a case-only variant reads as the same option to them.
	# llama3 returns 3 of 3 distinct (18 of 18 measured), so this defends the BYOK
	# surface — any OpenAI-compatible model can be attached from Settings.
	#
	# NOT padded up to `count`, deliberately: DynamicConversation._ensure_farewell
	# runs AFTER this and returns early when a farewell exists ANYWHERE, so padding
	# a short set whose last entry is "Farewell." leaves the farewell mid-menu.
	# Under-delivery is recorded as a live gap rather than papered over here.
	var seen: Dictionary = {}
	var distinct: Array[String] = []
	for chosen in out:
		var key: String = chosen.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		distinct.append(chosen)
	return {"choices": distinct}


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
		s = clamp_display(s, MAX_LINE_CHARS)

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
		reply = flatten_line(reply_raw as String)
		if reply.length() > MAX_LINE_CHARS:
			reply = clamp_display(reply, MAX_LINE_CHARS)
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
			taunt = clamp_display(taunt, MAX_BOSS_TAUNT_CHARS)

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
		line = clamp_display(line, MAX_PARTY_LINE_CHARS)
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


## Validate and parse an LLM-returned rule-composition Dictionary.
##
## `reply`'s top-level shape is already trusted (guarded by LLMService's
## complete_json against SCHEMA_RULE_COMPOSITION); this pass parses the
## nested rules_json string into an Array of rule Dictionaries. parse_ok is
## false when rules_json fails to parse as a JSON array — callers treat that
## as an invalid_json failure. Grammar-level hard-validation of individual
## rules (verb/target allowlists) is a later pass, not this one.
static func validate_rule_composition(reply: Dictionary, _domain: String) -> Dictionary:
	var name: String = str(reply.get("name", "")).strip_edges()
	var desc: String = str(reply.get("description", "")).strip_edges()
	# Accept both shapes: the encoded string the prompt asks for, and the nested
	# array models actually produce. Anything else stays a parse failure.
	var raw_rules: Variant = reply.get("rules_json", "")
	var parsed: Variant = raw_rules if typeof(raw_rules) == TYPE_ARRAY \
		else JSON.parse_string(str(raw_rules))
	var rules: Array = []
	var parse_ok: bool = typeof(parsed) == TYPE_ARRAY
	if parse_ok:
		for r in parsed:
			if typeof(r) == TYPE_DICTIONARY:
				rules.append(r)
	return {
		"name": name,
		"description": desc,
		"rules": rules,
		"parse_ok": parse_ok,
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


## Milo v2 (msg 2600): fold quest_state_lines into the prompt as "recent voice notes" so the LLM matches Milo's current-quest-phase tone.
static func _format_quest_state_voice(quest_state_lines: Array) -> String:
	if quest_state_lines.is_empty():
		return ""
	var quoted: PackedStringArray = PackedStringArray()
	for line in quest_state_lines:
		var s: String = str(line)
		if not s.is_empty():
			quoted.append("  - \"%s\"" % s.replace("\"", "\\\""))
	if quoted.is_empty():
		return ""
	return "\nThis character has recently said things like:\n" + "\n".join(quoted) + "\nEcho this mood and voice.\n"


## Live party state as prose — an NPC that can't see a downed PC isn't in the world.
## Frames memory as the NPC's own recollection, and asks for a glance rather than
## a recap — an NPC that quotes you back verbatim reads as a database, not a person.
static func _format_memory(memory_lines: Array) -> String:
	if memory_lines.is_empty():
		return ""
	var rows: PackedStringArray = PackedStringArray()
	for line in memory_lines:
		var text: String = str(line).strip_edges()
		if text != "":
			rows.append("  - \"%s\"" % text)
	if rows.is_empty():
		return ""
	return (
		"\n\nYou have spoken with this traveler before. Last time, they said to you:\n"
		+ "\n".join(rows)
		+ "\nYou may acknowledge having met them. Do not quote them back or recap the"
		# Trailing newline is the CONTRACT, not decoration: every other block
		# formatter ends with one, and this was the only exception — so whatever
		# followed memory glued onto its last sentence. Fixed once here rather
		# than by choosing an order that happens to be safe.
		+ " conversation — carry it the way a person carries a half-remembered chat.\n"
	)


static func _format_party_state(party_state: Dictionary) -> String:
	if party_state.is_empty():
		return ""
	var out: String = ""
	var members: Array = party_state.get("members", []) as Array
	if not members.is_empty():
		var rows: PackedStringArray = PackedStringArray()
		for m in members:
			if not (m is Dictionary):
				continue
			rows.append("  - %s the %s, %s" % [
				str(m.get("name", "?")),
				str(m.get("job", "adventurer")),
				str(m.get("condition", "unhurt")),
			])
		if not rows.is_empty():
			out += "\nThe party standing in front of you:\n" + "\n".join(rows) + "\n"
	if party_state.has("gold"):
		out += "They are carrying %d gold.\n" % int(party_state["gold"])
	var items: Array = party_state.get("notable_items", []) as Array
	if not items.is_empty():
		out += "Visible supplies: %s.\n" % ", ".join(PackedStringArray(items))
	if out == "":
		return ""
	return out + "Notice this if it is worth noticing — a wound, an empty purse, a full pack. Do not recite it.\n"


## HP band → the words an onlooker would use; ordered worst-first so DOWNED wins.
static func describe_condition(current_hp: int, max_hp: int, is_alive: bool) -> String:
	if not is_alive:
		return "DOWNED — unconscious and being carried"
	# No HP data is not evidence of injury — never invent a condition from a malformed entry.
	if max_hp <= 0:
		return "unhurt"
	if current_hp <= 0:
		return "DOWNED — unconscious and being carried"
	var pct: float = float(current_hp) / float(max_hp)
	if pct < 0.15:
		return "barely standing (%d%% health)" % int(round(pct * 100.0))
	if pct < 0.35:
		return "badly hurt (%d%% health)" % int(round(pct * 100.0))
	if pct < 0.7:
		return "wounded (%d%% health)" % int(round(pct * 100.0))
	return "unhurt"


## Day/night compose (msg 2659): tuck time_of_day into the prompt as a peer of Location.
static func _format_time_of_day(time_of_day: String) -> String:
	if time_of_day == "":
		return ""
	return "Time of day: %s\n" % time_of_day


## Tell the boss the player isn't deciding. Spelled out rather than passed as a
## bare token because the LLM must know what the state MEANS to react in voice —
## and the two tiers deserve different reactions, not one "they're automating".
static func _format_party_automation(tier: String) -> String:
	match tier:
		"autobattle":
			return ("The party is not choosing their actions. They wrote an autobattle script "
				+ "beforehand and are letting it play. A person is watching, but not deciding.\n")
		"autogrind":
			return ("The party is being run unattended by an autogrind session. Nobody is watching "
				+ "this fight at all. You are being farmed.\n")
		_:
			return ""


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
