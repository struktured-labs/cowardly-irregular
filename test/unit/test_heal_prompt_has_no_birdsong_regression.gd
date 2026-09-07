extends GutTest

## struktured rejected the cure spell twice as "a chirping bird". The first fix swapped the
## ASSET and left the PROMPT saying "birdsong and dewdrops" — so the manifest still described
## the sound he rejected, and any regeneration would have restored it silently. The prompt is
## the generator's input; an asset fix that leaves it stale is one `elevenlabs_sfx.py` run
## from being undone.

const MANIFEST := "res://data/sfx_manifest.json"
const BIRD_WORDS := ["birdsong", "chirp", "tweet", "songbird"]


func _sfx() -> Dictionary:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(raw, "", "manifest unreadable — every check below would pass vacuously")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse as a Dictionary")
	return (parsed as Dictionary).get("sfx", {})


func test_no_heal_cue_asks_the_generator_for_a_bird() -> void:
	var sfx := _sfx()
	assert_gt(sfx.size(), 50, "manifest holds few entries — the scan below would be vacuous")
	assert_true(sfx.has("heal"), "the 'heal' key is what _on_healing_done plays; if it is gone this guard is watching nothing")

	var offenders: Array = []
	for key in sfx:
		var k := str(key)
		if not ("heal" in k or "cure" in k):
			continue
		var prompt := str((sfx[key] as Dictionary).get("prompt", "")).to_lower()
		for w in BIRD_WORDS:
			# "no birdsong" is a NEGATIVE instruction and is the desired shape, not a request.
			if w in prompt and not ("no " + w) in prompt:
				offenders.append("%s: %s" % [k, w])
	if not offenders.is_empty():
		fail_test("heal/cure prompts REQUEST bird sounds — regenerating from these restores the cue struktured rejected: %s" % [offenders])


func test_the_scan_actually_reaches_prompts() -> void:
	# Without this the loop above passes on a manifest whose entries carry no prompt at all.
	var sfx := _sfx()
	var with_prompt := 0
	for key in sfx:
		var k := str(key)
		if ("heal" in k or "cure" in k) and str((sfx[key] as Dictionary).get("prompt", "")) != "":
			with_prompt += 1
	assert_gt(with_prompt, 3, "fewer than 4 heal/cure entries carry a prompt — the bird scan is reading empty strings")


func test_a_bird_word_is_still_detectable_somewhere_in_the_manifest() -> void:
	# Names a KNOWN-PRESENT member: weather_sunny and night_crickets_wind want birds on purpose.
	# If this returns zero the matcher is broken and the heal scan above proves nothing.
	var sfx := _sfx()
	var ambient_bird := 0
	for key in sfx:
		var prompt := str((sfx[key] as Dictionary).get("prompt", "")).to_lower()
		for w in BIRD_WORDS:
			if w in prompt:
				ambient_bird += 1
				break
	assert_gt(ambient_bird, 0, "no prompt anywhere mentions a bird — the word matcher is broken, so the heal scan's clean result is meaningless")
