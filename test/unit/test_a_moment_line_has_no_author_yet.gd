extends GutTest

## Spec 2a.1 step 2 — "a line written for THIS MOMENT outranks everything, including a ready pooled
## line" — is shipped, verified, and FED BY NOTHING. Measured on data/job_personas.json: 630 authored
## lines, 17 tagged, 0 carrying a moment tag. So PartyPersonas.has_moment_line cannot return true in
## production, and the six moment tags below describe barks the engine can deliver and never does.
##
## This file is the hand-off, not a complaint: the vocabulary is derived rather than listed, the
## mechanism is proved against a planted line, and the count is pinned at 0 so the first authored
## moment line REDS here and gets its end-to-end check at the moment it lands. Content is
## cowir-story's; the picker, the evaluators and the pool's deference to them are cowir-ai's.

const JOBS: Array[String] = ["fighter", "cleric", "mage", "rogue", "bard"]
const TRIGGERS: Array[String] = ["turn_start", "big_hit_taken", "low_hp", "used_signature_ability", "victory"]

var _saved_rogue: Dictionary = {}


func before_each() -> void:
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)


func after_each() -> void:
	PartyPersonas._data["rogue"] = _saved_rogue


## Derived from the evaluator, so a tag added there joins this vocabulary without an edit here.
func _moment_vocabulary() -> Array[String]:
	var out: Array[String] = []
	for t in VoiceLineTags.SIMPLE_TAGS:
		if VoiceLineTags.is_moment_tag(str(t)):
			out.append(str(t))
	return out


func _authored_moment_lines() -> Array[String]:
	var found: Array[String] = []
	for job in JOBS:
		for trig in TRIGGERS:
			for e in PartyPersonas.get_trigger_entries(job, trig):
				for t in (e.get("tags", []) as Array):
					if VoiceLineTags.is_moment_tag(str(t)):
						found.append("%s/%s [%s]" % [job, trig, t])
						break
	return found


func test_the_moment_vocabulary_is_not_empty() -> void:
	## CONTROL on the derivation: if this ever reads empty, the arms below are vacuous rather than clean.
	var vocab: Array[String] = _moment_vocabulary()
	assert_gte(vocab.size(), 6,
		"the evaluator offers %d moment tags; this file's whole subject is that nothing authors them" % vocab.size())
	for expected in ["ally_down", "last_standing", "enemy_last"]:
		assert_true(vocab.has(expected), "'%s' must still be a moment tag" % expected)


func test_the_mechanism_works_when_a_moment_line_exists() -> void:
	## CONTROL, and the reason the pin below reads "unfed" rather than "broken": with one line
	## planted, the picker sees the moment. Without this arm, a zero could mean either.
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["low_hp"] = ["Generic.", {"line": "Get UP!", "when": "ally_down"}]
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry
	var ctx := PartyCombatLineContext.new()
	ctx.speaker_name = "Vex"
	ctx.party = [{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 0.0, "is_alive": false}]
	ctx.enemies = [{"name": "Slime", "hp_pct": 100.0}]
	assert_true(PartyPersonas.has_moment_line("rogue", "low_hp", ctx),
		"the moment mechanism does not fire even for a planted moment line — this is a real defect, not the authoring gap")


func test_no_moment_line_is_authored_yet() -> void:
	## ⛔ DECLARED GAP. When this reds, the mechanism just gained its first real content: move the
	## authored line into an end-to-end arm (fire it through BattleManager._run_party_line_async and
	## assert it beats a ready pooled line), then raise the count here. Do NOT just raise the count.
	var found: Array[String] = _authored_moment_lines()
	assert_eq(found, ([] as Array[String]),
		"a moment line is authored now (%s) — give it an end-to-end arm before raising this pin" % ", ".join(found))
