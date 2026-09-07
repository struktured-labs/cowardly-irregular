extends GutTest

## Layer-six guard: two data sources feed one surface, one silently wins.
##
## THE CLASS (cowir-story msg 2957, from being bitten twice): a dialogue
## rewrite that ships clean, diffs correctly, passes the suite — and changes
## nothing in game, because a second file silently outranks the one you
## edited. Unlike the five provenance traps found alongside it, no git-side
## check can catch this one: both contents are CORRECT. Only the consumer's
## choice between them is surprising, so no amount of diff-reading finds it.
##
## THE INSTANCE THIS GUARDS (cowir-ai, introduced 2026-07-16): for a persona
## carrying both keys, a resolved quest bucket shadows `fallbacks[]` on the
## static idle path. For Scholar Milo the shadow is TOTAL — he gives
## chapter_three, all three buckets are authored, and every quest state maps
## to one, so his fallbacks never render when the player walks up to him.
## They are NOT dead: they still render inside an active LLM conversation.
## That split is worse than fully-dead, because a spot-check can land on the
## working path and confirm the wrong conclusion.
##
## WHY AN ANNOTATION AND NOT A COLLISION CHECK (cowir-battle msg 2963,
## cowir-sfx msg 2960): the precedence is INTENDED — quest-phase lines should
## outrank generic fallbacks; that's the feature. So a check that fires on the
## collision would fire only on correct configs and demand a suppression flag
## to silence it, and `"_shadow_ok": true` becomes muscle memory by the second
## NPC. A check whose correct case requires suppression is not a check.
##
## So this ratchet requires the shadowed key to carry a note NAMING what
## outranks it. There is deliberately NO silencing path: you cannot make this
## green by suppressing it, only by explaining it — and the explanation is the
## deliverable. Cost scales correctly too: 1 annotation on an undocumented
## precedence is the missing documentation itself (contrast cowir-sfx's 40
## shadowed SOUNDS keys, where an established documented contract made a
## ratchet a graveyard and a comment the right remedy).

const PERSONA_PATH: String = "res://data/cutscenes/npc_showcase_personas.json"
const NPC_SOURCE_PATH: String = "res://src/exploration/OverworldNPC.gd"

## The key a shadowed fallbacks[] must carry. Not an opt-out — an explanation.
const NOTE_KEY: String = "_fallbacks_note"

## Long enough that a degenerate `"note": "ok"` can't satisfy the requirement.
const MIN_NOTE_CHARS: int = 80

## Keys that would turn this ratchet into a suppression flag. None may exist.
const FORBIDDEN_SUPPRESSION_KEYS: Array[String] = [
	"_shadow_ok", "_ignore_shadow", "_skip_shadow_check",
	"_fallbacks_shadow_ok", "_suppress_shadow",
]


func _load_personas() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(PERSONA_PATH)
	assert_false(raw.is_empty(), "persona JSON must exist and be readable: %s" % PERSONA_PATH)
	var json := JSON.new()
	assert_eq(json.parse(raw), OK, "persona JSON must parse: %s" % json.get_error_message())
	assert_true(json.data is Dictionary, "persona JSON root must be a Dictionary")
	return json.data as Dictionary


## Personas where a resolved bucket can shadow fallbacks[] — the collision set.
func _shadowed_personas() -> Array:
	var out: Array = []
	for name in _load_personas().keys():
		var entry: Variant = _load_personas()[name]
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry as Dictionary
		var q: Variant = e.get("quest_state_lines")
		var f: Variant = e.get("fallbacks")
		var has_buckets: bool = q is Dictionary and not (q as Dictionary).is_empty()
		var has_fallbacks: bool = f is Array and not (f as Array).is_empty()
		if has_buckets and has_fallbacks:
			out.append(name)
	return out


# ── The general rule (no name list — survives new NPCs) ──────────────────────

func test_every_shadowed_persona_carries_an_explanatory_note() -> void:
	var personas: Dictionary = _load_personas()
	var shadowed: Array = _shadowed_personas()
	for name in shadowed:
		var e: Dictionary = personas[name]
		assert_true(e.has(NOTE_KEY),
			("'%s' defines BOTH quest_state_lines and a non-empty fallbacks[], so its fallbacks are shadowed " +
			"on the static idle path. It must carry '%s' naming what outranks them — otherwise the next author " +
			"edits those lines, sees no change in game, and has no way to find out why.") % [name, NOTE_KEY])


func test_the_note_is_substantive_not_a_token() -> void:
	var personas: Dictionary = _load_personas()
	for name in _shadowed_personas():
		var note: String = str((personas[name] as Dictionary).get(NOTE_KEY, "")).strip_edges()
		assert_gte(note.length(), MIN_NOTE_CHARS,
			"'%s' %s must actually explain the precedence (>= %d chars) — a token string would satisfy the letter of this ratchet and none of its purpose" % [name, NOTE_KEY, MIN_NOTE_CHARS])


func test_the_note_names_what_outranks_the_fallbacks() -> void:
	var personas: Dictionary = _load_personas()
	for name in _shadowed_personas():
		var note: String = str((personas[name] as Dictionary).get(NOTE_KEY, "")).to_lower()
		assert_true(note.find("quest_state_lines") != -1,
			"'%s' %s must name the key that wins (quest_state_lines) — 'this may be overridden' tells the reader nothing actionable" % [name, NOTE_KEY])


func test_the_note_names_BOTH_halves_of_the_split() -> void:
	# The whole reason this is worse than fully-dead: it renders on ONE path.
	# A note that only says "shadowed" would leave the next author unsure which
	# spot-check counts as evidence.
	var personas: Dictionary = _load_personas()
	for name in _shadowed_personas():
		var note: String = str((personas[name] as Dictionary).get(NOTE_KEY, "")).to_lower()
		var names_dead_path: bool = note.find("idle") != -1 or note.find("static") != -1
		var names_live_path: bool = note.find("conversation") != -1 or note.find("dynamicconversation") != -1 or note.find("dynamic chat") != -1
		assert_true(names_dead_path,
			"'%s' %s must name the path where the fallbacks DON'T render (static/idle)" % [name, NOTE_KEY])
		assert_true(names_live_path,
			"'%s' %s must name the path where they DO still render (inside an LLM conversation) — otherwise a spot-check on the working path reads as 'my edit worked'" % [name, NOTE_KEY])


# ── No silencing path may ever be introduced ─────────────────────────────────

func test_no_persona_carries_a_suppression_flag() -> void:
	var personas: Dictionary = _load_personas()
	for name in personas.keys():
		var entry: Variant = personas[name]
		if not (entry is Dictionary):
			continue
		for forbidden in FORBIDDEN_SUPPRESSION_KEYS:
			assert_false((entry as Dictionary).has(forbidden),
				("'%s' carries suppression key '%s'. This ratchet has no opt-out BY DESIGN — a check whose correct " +
				"case requires a suppression flag stops being a check (cowir-sfx msg 2960 / cowir-battle msg 2963). " +
				"Explain the precedence in '%s' instead of silencing it.") % [name, forbidden, NOTE_KEY])


func test_ratchet_source_declares_no_opt_out() -> void:
	var src: String = FileAccess.get_file_as_string("res://test/unit/test_persona_shadow_annotation_ratchet.gd")
	assert_true(src.find("NO silencing path") != -1,
		"the no-opt-out property is this ratchet's entire design rationale and must stay documented in it")


# ── The current instance stays covered ───────────────────────────────────────

func test_milo_is_currently_the_shadowed_persona() -> void:
	# Not a name list the rule depends on — a canary. If Milo drops off this
	# list, either the shadow was resolved (good, verify intentionally) or the
	# detection broke (bad). Either way a human should look.
	var shadowed: Array = _shadowed_personas()
	assert_true(shadowed.has("Scholar Milo"),
		"Scholar Milo is the known shadowed persona; if he no longer matches, confirm whether the precedence changed or this ratchet stopped detecting it")


func test_milos_shadow_is_total_on_the_static_path() -> void:
	# Structural, not probabilistic: he gives chapter_three and every quest
	# state maps to an authored bucket, so fallbacks[] NEVER render on idle.
	# If a bucket is ever removed the shadow becomes partial and the note's
	# "never render" wording would overstate — fail so it gets reworded.
	var e: Dictionary = _load_personas()["Scholar Milo"]
	var buckets: Dictionary = e.get("quest_state_lines", {})
	for required in ["pre_task_1", "in_progress", "post_quest"]:
		var b: Variant = buckets.get(required)
		assert_true(b is Array and not (b as Array).is_empty(),
			"bucket '%s' must stay authored — every chapter_three state maps to a bucket, which is what makes the shadow total rather than occasional" % required)


# ── Code-side pin (the reader who's in the .gd, not the .json) ───────────────

func test_precedence_site_is_annotated_in_source() -> void:
	var src: String = FileAccess.get_file_as_string(NPC_SOURCE_PATH)
	assert_true(src.find("PRECEDENCE:") != -1,
		"the line that chooses bucket-over-dialogue_lines must say so — the JSON note serves the data reader, this serves the code reader")
	assert_true(src.find("_quest_state_bucket_rotation(_quest_bucket)") != -1,
		"the precedence site itself must still exist; if this moved, move the annotation with it")
