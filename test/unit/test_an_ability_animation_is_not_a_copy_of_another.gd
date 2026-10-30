extends GutTest

## 13 of 18 starter ability animations were BYTE-IDENTICAL copies of another animation -- the
## rogue's backstab/flee/mug/steal were his walk, the cleric's heal/buff/raise were her advance,
## the bard's four songs shared one strip. Identical SHA256 means copied, not drawn: nobody draws
## two animations to the same byte. A backstab that plays a walk cycle is the defect, and authored
## per-frame rhythm cannot fix it -- the motion is wrong, not the timing.
##
## 8 were composed from each job's own artist frames (tools/gen_ability_from_artist_frames.py).
## The 5 below are NOT composed and each says why. THE LIST MAY ONLY SHRINK: every entry is
## asserted to STILL be a duplicate, so the day one gets real art this file says to drop it.

const MANIFEST := "res://data/sprite_manifest.json"
const JOBS := ["fighter", "cleric", "mage", "rogue", "bard"]
## Animation names that are not ability art -- the shared vocabulary every job carries.
const STANDARD := ["idle", "walk", "attack", "hit", "dead", "cast", "defend", "item",
	"victory", "weak", "advance", "defer"]
## Still a copy, each with the reason it was not composed. Drop an entry when it gains real art.
const LEFT_AS_A_COPY := {
	"fighter/slash": "tools/artist_guard REFUSES it -- it IS the fighter's artist attack",
	"rogue/stab": "tools/artist_guard REFUSES it -- it IS the rogue's artist attack",
	"bard/lullaby": "the bard has two performance poses that read alike; composing three songs from them produced near-identical strips AND would destroy this very signal. Standing artist ask.",
	"bard/battle_hymn": "see bard/lullaby -- deliberate, a standing artist ask",
	"bard/inspiring_melody": "see bard/lullaby -- deliberate, a standing artist ask",
}


func _sheets() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return (parsed as Dictionary).get("sheets", {}) if parsed is Dictionary else {}


## job -> {anim: sha256-of-bytes} for every animation whose PNG is on disk.
func _hashes(job: String) -> Dictionary:
	var sheets := _sheets()
	if not sheets.has(job):
		return {}
	var entry: Dictionary = sheets[job]
	var base := str(entry.get("path", "")).trim_suffix("/")
	var out := {}
	for anim in entry.get("animations", []):
		var p := "%s/%s.png" % [base, str(anim)]
		var bytes := FileAccess.get_file_as_bytes(p)
		if bytes.is_empty():
			continue
		out[str(anim)] = Marshalls.raw_to_base64(bytes).sha256_text()
	return out


## [job/anim, twins] for every ability animation sharing bytes with another animation of that job.
func _duplicated() -> Dictionary:
	var out := {}
	for job in JOBS:
		var h := _hashes(job)
		for anim in h:
			if STANDARD.has(anim):
				continue
			var twins: Array = []
			for other in h:
				if other != anim and h[other] == h[anim]:
					twins.append(str(other))
			if not twins.is_empty():
				twins.sort()
				out["%s/%s" % [job, anim]] = twins
	return out


func test_the_corpus_is_the_real_job_sheets() -> void:
	var total := 0
	for job in JOBS:
		total += _hashes(job).size()
	assert_gt(total, 60,
		"ANTI-VACUITY: only %d job animations were readable, so every arm below is free" % total)


func test_no_ability_animation_is_a_byte_copy_of_another() -> void:
	var dup := _duplicated()
	var unexpected: Array = []
	for key in dup:
		if not LEFT_AS_A_COPY.has(key):
			unexpected.append("%s is byte-identical to %s" % [key, str(dup[key])])
	unexpected.sort()
	assert_eq(unexpected, [],
		("%d ability animation(s) play another animation's art. Compose them " +
		"(tools/gen_ability_from_artist_frames.py) or add them to LEFT_AS_A_COPY with a reason: %s")
		% [unexpected.size(), str(unexpected)])


## The ratchet: an exemption that has gained real art must be DROPPED, not left to rot.
func test_every_exemption_is_still_a_copy() -> void:
	var dup := _duplicated()
	assert_gt(LEFT_AS_A_COPY.size(), 0, "CONTROL: the exemption list has entries to check")
	for key in LEFT_AS_A_COPY:
		assert_true(dup.has(key),
			"%s has its own art now -- drop it from LEFT_AS_A_COPY (reason on file: %s)"
			% [key, LEFT_AS_A_COPY[key]])


## The composed 8 are the point of the exercise: each must be distinct from every sibling.
func test_the_composed_abilities_have_their_own_art() -> void:
	var dup := _duplicated()
	var composed := ["rogue/backstab", "rogue/mug", "rogue/steal", "rogue/flee",
		"cleric/heal", "cleric/buff", "cleric/raise", "bard/discord"]
	for key in composed:
		var parts := key.split("/")
		assert_true(_hashes(parts[0]).has(parts[1]), "CONTROL: %s is on disk and readable" % key)
		assert_false(dup.has(key),
			"%s is a byte-copy again -- a regeneration or a revert put another animation's art back" % key)
