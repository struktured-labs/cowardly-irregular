extends GutTest

## The manifest declares critical_hit as "Generic crit fallback (= attack_hit_sword_crit)".
## That equality is REAL — the two files are byte-identical on disk — and nothing enforced it.
## Re-encoding one of them breaks it silently: same audio, different bytes, and the manifest's
## "=" quietly becomes false. I did exactly that while sharpening the crit transient
## (2026-08-18) and only caught it because I happened to hash both afterwards.

const CRIT_SWORD := "res://assets/audio/sfx/attack_hit_sword_crit.ogg"
const CRIT_GENERIC := "res://assets/audio/sfx/critical_hit.ogg"
const MANIFEST := "res://data/sfx_manifest.json"


func _bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "must be readable: %s" % path)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b


func test_generic_crit_is_byte_identical_to_the_sword_crit() -> void:
	var a := _bytes(CRIT_SWORD)
	var b := _bytes(CRIT_GENERIC)
	assert_gt(a.size(), 0, "sword crit must be non-empty — an empty read would make the compare below vacuous")
	assert_eq(a.size(), b.size(),
		"critical_hit and attack_hit_sword_crit must be the SAME FILE — the manifest documents them as equal, and a re-encode produces identical audio with different bytes, silently falsifying that")
	assert_true(a == b,
		"byte mismatch: regenerate one from the other with a COPY, never a second encode — libvorbis output is not reproducible across runs")


func test_the_manifest_still_declares_the_equality_this_test_defends() -> void:
	## Guard against the reverse drift: if the "=" claim is ever removed or retargeted,
	## the test above is defending a relationship nobody asserts any more.
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(f, "manifest must be readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary and parsed.has("sfx"), "manifest must parse to {sfx:{...}}")
	var sfx: Dictionary = parsed["sfx"]
	assert_true(sfx.has("critical_hit"), "critical_hit must still be registered")
	assert_true(str(sfx["critical_hit"].get("prompt", "")).contains("attack_hit_sword_crit"),
		"critical_hit's prompt must still name attack_hit_sword_crit as its source — if that link is dropped, the byte-identity guard above is defending an undocumented coincidence")


## NOT TESTED HERE — the transient itself. The defect this branch fixes is that the crit
## reached 90% peak in 123.5ms against the base hit's 0.5ms, reading as a slow swell rather
## than a harder strike. Godot cannot decode ogg samples in-test, so there is no way to pin
## that property from GUT. I drafted a file-size proxy and DELETED it: the pre-fix asset was
## 40746 bytes and the fixed one is 48213, so any threshold catching a revert is a
## coincidental pin between two arbitrary sizes that a legitimate re-encode also trips.
## A guard that cannot fire is worse than none — it reads as coverage. Measure the transient
## with tools/ (numpy/soundfile) when regenerating; see the branch notes for the numbers.
