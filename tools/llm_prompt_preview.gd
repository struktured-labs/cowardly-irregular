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
		"signoff":
			out = DP.build_npc_sign_off(
				"Elder Theron", "a weary village elder who has seen too much",
				"Harmonia Village", events, "You return to me, battered and worn.",
				"I must go.")
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
