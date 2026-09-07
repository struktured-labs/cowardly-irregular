extends GutTest

## Some cues are SYNTHESISED (tools/gen_chiptune_sfx.py) because text-to-audio generation cannot
## hit a chiptune target. Their manifest `prompt` still exists for humans, and a prompt is exactly
## what elevenlabs_sfx.py consumes — so without a refusal, one --force run silently restores the
## sound struktured rejected. This is the birdsong trap: asset fixed, generator input not.

const MANIFEST := "res://data/sfx_manifest.json"
const GENERATOR := "res://tools/elevenlabs_sfx.py"


func _sfx() -> Dictionary:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(raw, "", "manifest unreadable — every check below would be vacuous")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse")
	return (parsed as Dictionary).get("sfx", {})


func test_the_fire_rotation_is_source_locked() -> void:
	# All THREE rotation slots, not just the base: struktured re-reported the whoop after the base
	# alone was re-voiced, because two casts in three still played the untouched variants.
	var sfx := _sfx()
	var missing: Array = []
	for k in ["ability_fire", "ability_fire_v2", "ability_fire_v3"]:
		assert_true(sfx.has(k), "manifest lacks %s" % k)
		if str((sfx[k] as Dictionary).get("source", "")) == "":
			missing.append(k)
	if not missing.is_empty():
		fail_test("fire rotation slots with no `source` lock — a generator run would overwrite them with the rejected whoop: %s" % [missing])


func test_the_generator_refuses_source_locked_entries() -> void:
	var gen := FileAccess.get_file_as_string(GENERATOR)
	assert_ne(gen, "", "elevenlabs_sfx.py unreadable — this check would be vacuous")
	assert_true('src.startswith("tools/")' in gen,
		"the generator does not gate on a tools/ source — nothing stops a --force run from overwriting a synthesised cue")
	assert_false('if entry.get("source"):' in gen,
		"the refusal is too broad: `source` is a provenance label on 88 entries and 11 are elevenlabs-sourced and legitimately regenerable")
	assert_true("REFUSE" in gen,
		"the generator has no refusal path for source-locked entries")


func test_every_source_lock_names_a_tool_that_exists() -> void:
	# A lock pointing at a missing script is worse than none: it blocks regeneration and offers no
	# way to rebuild the asset.
	var sfx := _sfx()
	var locked := 0
	var broken: Array = []
	for key in sfx:
		var src := str((sfx[key] as Dictionary).get("source", ""))
		## `source` is a provenance LABEL on most entries (sox_synth, elevenlabs_foley...). Only a
		## tools/ path is a regeneration lock — the two share a field and mean different things.
		if not src.begins_with("tools/"):
			continue
		locked += 1
		var path := "res://" + src.split(" ")[0]
		if not FileAccess.file_exists(path):
			broken.append("%s -> %s" % [key, path])
	assert_gt(locked, 0, "no source-locked entries found at all — this guard is watching nothing")
	if not broken.is_empty():
		fail_test("source locks naming a script that does not exist: %s" % [broken])
