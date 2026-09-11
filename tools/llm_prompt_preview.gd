extends SceneTree

## Renders a real assembled NPC prompt to stdout. See tools/llm_prompt_preview.sh.
##
## Calls the SHIPPING builders, so what you read is what the model receives — a
## hand-written approximation would drift the moment a block is added, which is
## the exact class of defect this lane spent 2026-09-10 fixing.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const OUT_PATH := "res://tmp/llm_prompt_preview.txt"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var kind: String = args[0] if args.size() > 0 else "opening"
	var rich: bool = not args.has("--bare")

	var party: Dictionary = {} if not rich else {
		"members": [
			{"name": "Rilla", "job": "cleric", "condition": "barely standing (9% health)"},
			{"name": "Bram", "job": "fighter", "condition": "DOWNED — unconscious and being carried"},
		],
		"gold": 7,
	}
	var events: Array = [] if not rich else [{"type": "boss", "summary": "Pyrroth the Ember Wyrm defeated"}]
	var quest: Array = [] if not rich else ["The wyrm's death has not eased my mind."]
	var memory: Array = [] if not rich else ["I'm hunting the ember wyrm."]
	var tod: String = "" if not rich else "night"

	var out: String = ""
	match kind:
		"reply":
			out = DP.build_combined_reply(
				"Elder Theron", "a weary village elder who has seen too much",
				"Harmonia Village", events, "You return to me, battered and worn.",
				"What do you know of the wyrm?", 4, quest, party, memory, tod)
		"rules":
			out = DP.build_rule_composition(
				"autobattle",
				"Heal whoever is hurt worst when they drop under 40%, cure poison if anyone has it, otherwise hit the weakest enemy.",
				[])
		"signoff":
			out = DP.build_npc_sign_off(
				"Elder Theron", "a weary village elder who has seen too much",
				"Harmonia Village", events, "You return to me, battered and worn.",
				"I must go.")
		"party":
			# Keys verified against PartyCombatLineContext.to_dict — every key the
			# formatter reads is produced there, checked rather than assumed.
			# Persona and phrases lifted VERBATIM from data/job_personas.json — a
			# preview seeded with invented data misleads about what the model sees.
			out = DP.build_party_line(
				"You are Sister Veridian, a Watchful Cleric of the Liturgical Order of the Eternal Loop — an old sect that believes this entire JRPG is sacred scripture and every encounter is a verse to be read carefully. You catalogue the party by their wounds, not their names: Fighter is \"the bruised shoulder,\" Mage is \"the singed sleeve,\" Rogue is \"the new limp.\" Kind but firm, you speak in clipped liturgical cadence — short blessings, longer rebukes. You distrust autobattle scripts that skip prayers. You know the white magic IS the engine clamping HP values and you find that beautiful. Staff held two-handed. Never panicked. Always counting turns like rosary beads.",
				["The Loop provides. Hold still.", "Wounds are just save points the body forgot.", "Stitched. Logged. Forgiven.", "Mercy is a stat. Mine is capped."],
				{
				"event_kind": "big_hit_taken",
				"speaker_name": "Rilla", "speaker_job_id": "cleric",
				"speaker_hp_pct": 22.0, "speaker_mp_pct": 40.0,
				"speaker_status": ["poison"],
				"speaker_personality": "Cautious",
				"party": [
					{"name": "Rilla", "job_id": "cleric", "hp_pct": 22.0, "is_alive": true},
					{"name": "Bram", "job_id": "fighter", "hp_pct": 90.0, "is_alive": true},
				],
				"enemies": [{"name": "Chancellor Mordaine", "hp_pct": 48.0}],
				"recent_actions": [
					{"kind": "party_action", "actor": "bram", "ability_id": "cleave", "target": "single_enemy", "damage": 0},
				],
				"event_data": {"damage": 340, "is_crit": true},
			})
		"intent":
			out = DP.build_boss_intent("Chancellor Mordaine", {
				"persona": "The usurper. Cold, procedural, certain the throne is a calculation.",
				"phase": 2,
				"boss_hp_pct": 48.0, "boss_mp_pct": 70.0, "boss_ap": 2,
				"boss_status": [],
				"party": [
					{"name": "Rilla", "job_id": "cleric", "hp_pct": 22.0, "mp_pct": 40.0,
					 "ap": 0, "is_alive": true, "status": ["poison"]},
					{"name": "Bram", "job_id": "fighter", "hp_pct": 90.0, "mp_pct": 100.0,
					 "ap": 1, "is_alive": true, "status": []},
				],
				"recent_actions": [
					{"kind": "party_action", "actor": "bram", "ability_id": "cleave", "target": "single_enemy", "damage": 0},
					{"kind": "party_action", "actor": "rilla", "ability_id": "cure", "target": "lowest_hp_ally", "damage": 0},
					{"kind": "party_action", "actor": "bram", "ability_id": "cleave", "target": "single_enemy", "damage": 0},
				],
				"available_intents": ["aggress", "turtle", "exploit_pattern"],
				"time_of_day": "night",
				"party_automation": "scripted",
				"party_scripts": [{
					"name": "Rilla", "job_id": "cleric",
					"rules": "1. IF ally_hp_percent < 40 THEN cure (lowest_hp_ally)\n2. IF always THEN attack (lowest_hp_enemy)",
				}],
				"learned_patterns_counter": "focus_healer",
			})
		_:
			out = DP.build_npc_opening(
				"Elder Theron", "a weary village elder who has seen too much",
				"Harmonia Village", events, quest, tod, party, memory)
	# Written to a FILE, not stdout: autoload boot logging ("Loaded 289
	# abilities", the InputProfileManager block) prints AFTER quit() and lands in
	# any stdout capture, so a shell redirect picks up 26 lines of noise the
	# caller would have to guess the shape of. A file is the only surface the
	# engine's own logging cannot reach.
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[llm_prompt_preview] cannot write %s" % OUT_PATH)
		quit(1)
		return
	f.store_string(out)
	f.close()
	quit(0)
