extends GutTest

## tools/elevenlabs_sfx.py refuses to regenerate an entry whose `source` does not start with
## "elevenlabs" — the artist-protection refusal CLAUDE.md asks for at generation time.
##
## ⛔ ITS PREDICATE IS `if src and not src.startswith("elevenlabs")`, SO AN **ABSENT** source is
## falsy and PROCEEDS. The tool's own comment says an unrecognised label "fails CLOSED"; absence
## is not an unrecognised label, and 209 of 346 entries carry none. party_ko was the one entry
## whose prompt DECLARED it was synthesised while no label existed to act on it — a --force run
## would have sent 550 words of prose to ElevenLabs over a deliberately-stepped chiptune cue.
##
## This pins the SHAPE, not the name: any entry announcing non-ElevenLabs provenance in its prompt
## must carry a source label the generator will refuse.

const MANIFEST := "res://data/sfx_manifest.json"
const DECLARES := ["SYNTHESISED", "tools/gen_", "not an ElevenLabs"]


func _sfx() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(f, "CONTROL: the sfx manifest must open, or this file measures nothing")
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "CONTROL: the manifest must parse as a Dictionary")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func test_a_prompt_declaring_synthesis_has_a_source_the_generator_refuses() -> void:
	var sfx := _sfx()
	assert_gt(sfx.size(), 100, "CONTROL: the corpus must be the real manifest, not a stub")
	var declaring: Array = []
	var unguarded: Array = []
	for k in sfx.keys():
		var e: Dictionary = sfx[k] if sfx[k] is Dictionary else {}
		var prompt: String = str(e.get("prompt", ""))
		var declares := false
		for marker in DECLARES:
			if prompt.contains(marker):
				declares = true
		if not declares:
			continue
		declaring.append(str(k))
		var src: String = str(e.get("source", ""))
		## the generator's own predicate, verbatim: an empty src is falsy and PROCEEDS
		if not (src != "" and not src.begins_with("elevenlabs")):
			unguarded.append(str(k))
	## FLOOR: without this the arm passes vacuously the day nobody declares provenance in prose.
	assert_gt(declaring.size(), 0,
		"no entry declares synthesis in its prompt — the scan found nothing to judge, so a pass here means nothing")
	assert_eq(unguarded, [],
		"%d cue(s) announce non-ElevenLabs provenance in their prompt and carry no source label the generator would refuse — a --force run overwrites a hand-built asset: %s" % [unguarded.size(), unguarded])
