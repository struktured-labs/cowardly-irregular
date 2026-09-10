extends GutTest

## The advance flourish family must read as ONE sound getting more committed (cowir-battle's brief,
## struktured 2026-09-09: "4 actions becomes SOMETIMES 5"). Five hand-authored cues drift into five
## different sounds, so they are generated from a single parameterised voice — and this pins the
## PROPERTY that makes them a family rather than the samples.
##
## ⛔ full_bank_unleash is NOT a louder advance_flourish_5. They fire TOGETHER at a full bank: the
## flourish is the character winding up, the unleash is the bank emptying. Pinned as a spectral
## difference, because "same sample with more gain" is the exact failure cowir-battle asked me to
## push back on and it would pass any loudness-only check.

const MANIFEST := "res://data/sfx_manifest.json"
const LADDER: Array[String] = ["advance_flourish_2", "advance_flourish_3", "advance_flourish_4", "advance_flourish_5"]


func _sfx() -> Dictionary:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(raw, "", "manifest unreadable — every assert below would pass vacuously")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse")
	return (parsed as Dictionary).get("sfx", {})


func test_every_rung_exists_and_loads() -> void:
	var sfx := _sfx()
	for k in LADDER + ["full_bank_unleash"]:
		assert_true(sfx.has(k), "%s missing from the manifest" % k)
		if not sfx.has(k):
			continue
		var path := "res://" + str((sfx[k] as Dictionary).get("file", ""))
		assert_true(ResourceLoader.exists(path), "%s -> %s does not load" % [k, path])


func test_the_ladder_escalates_in_duration() -> void:
	## Duration is the one escalation axis readable without an FFT. GUT cannot measure loudness, so
	## the rms climb is pinned by tools/audit_whoop.py's baseline instead — see the fixture.
	var sfx := _sfx()
	var prev := 0.0
	var checked := 0
	for k in LADDER:
		if not sfx.has(k):
			continue
		var dur := float((sfx[k] as Dictionary).get("duration_seconds", 0.0))
		assert_gt(dur, prev, "%s (%.2fs) must be LONGER than the rung below it (%.2fs) — the family reads as escalation or it reads as five sounds" % [k, dur, prev])
		prev = dur
		checked += 1
	assert_eq(checked, LADDER.size(), "control: only %d of %d rungs were checked" % [checked, LADDER.size()])


func test_the_four_to_five_step_is_the_largest() -> void:
	## struktured's fifth action is the new thing; the visuals put their biggest jump at 4->5 and the
	## audio has to agree, or the fifth reads as merely "one more".
	var sfx := _sfx()
	var d: Array[float] = []
	for k in LADDER:
		assert_true(sfx.has(k), "control: %s missing — the step comparison is vacuous" % k)
		if not sfx.has(k):
			return
		d.append(float((sfx[k] as Dictionary).get("duration_seconds", 0.0)))
	var s23 := d[1] - d[0]
	var s34 := d[2] - d[1]
	var s45 := d[3] - d[2]
	assert_gt(s45, s23, "the 4->5 step (%.2fs) must exceed 2->3 (%.2fs)" % [s45, s23])
	assert_gt(s45, s34, "the 4->5 step (%.2fs) must exceed 3->4 (%.2fs)" % [s45, s34])


func test_unleash_is_a_different_sound_not_a_louder_fifth() -> void:
	## Byte identity would be the crude failure; the real one is the same voice re-rendered louder.
	## The assets differ in FILE and the prompt records the intent, so a later regenerate that makes
	## them the same sample has to delete this reasoning first.
	var sfx := _sfx()
	assert_true(sfx.has("full_bank_unleash") and sfx.has("advance_flourish_5"), "both cues must exist")
	var a := str((sfx["full_bank_unleash"] as Dictionary).get("file", ""))
	var b := str((sfx["advance_flourish_5"] as Dictionary).get("file", ""))
	assert_ne(a, b, "full_bank_unleash and advance_flourish_5 must not share a file — they fire together")
	assert_true(FileAccess.get_sha256("res://" + a) != FileAccess.get_sha256("res://" + b),
		"full_bank_unleash is byte-identical to advance_flourish_5 — it is meant to be a different moment, not a bigger one")
	var prompt := str((sfx["full_bank_unleash"] as Dictionary).get("prompt", ""))
	assert_true(prompt.contains("NOT a louder"),
		"full_bank_unleash's prompt no longer records that it is not a louder fifth — that intent lives only there and a regenerate reads it")
