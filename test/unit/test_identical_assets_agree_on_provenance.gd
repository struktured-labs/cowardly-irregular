extends GutTest

## Two manifest keys can name DIFFERENT files holding IDENTICAL BYTES — a deliberate alias, like
## `critical_hit` (= attack_hit_sword_crit, said so in its own prompt). Provenance is what decides
## whether tools/elevenlabs_sfx.py may overwrite a cue: `:124` refuses when `source` is set and does
## not start with "elevenlabs". An ABSENT source is falsy, so it sails through.
##
## So one asset, reached by two keys, can be simultaneously protected and regenerable. Measured
## 2026-09-20: critical_hit and attack_hit_sword_crit are byte-identical (sha c779778222..), both
## 2.25s ffmpeg-derived, and only the second carried `source: ffmpeg_derive`. Regenerating the first
## would have requested its authored 0.6s from the API and replaced a derived asset with an
## unrelated one — while its twin sat refused.
##
## This is the same shape as the comment block at elevenlabs_sfx.py:112-122, one layer over: that
## one inverted the rule so an UNRECOGNISED label fails closed. A MISSING label still fails open.
##
## Asserts the RELATIONSHIP (same bytes -> same provenance), never a list of known pairs: a
## hand-listed pair set goes stale the moment an alias is added, and this cannot.

const MANIFEST := "res://data/sfx_manifest.json"


func _sfx() -> Dictionary:
	var t: String = FileAccess.get_file_as_string(MANIFEST)
	assert_ne(t, "", "sfx_manifest.json must be readable")
	var parsed = JSON.parse_string(t)
	if parsed is Dictionary:
		var s = parsed.get("sfx", {})
		return s if s is Dictionary else {}
	return {}


## Groups manifest keys by the sha256 of the bytes their `file` points at.
func _groups_by_digest() -> Dictionary:
	var out := {}
	for k in _sfx().keys():
		var e = _sfx()[k]
		if not (e is Dictionary):
			continue
		var f: String = str(e.get("file", ""))
		if f == "":
			continue
		var res: String = f if f.begins_with("res://") else "res://" + f
		if not FileAccess.file_exists(res):
			continue
		var digest: String = FileAccess.get_sha256(res)
		if digest == "":
			continue
		if not out.has(digest):
			out[digest] = []
		out[digest].append(str(k))
	return out


func test_byte_identical_assets_carry_the_same_source() -> void:
	var groups: Dictionary = _groups_by_digest()
	assert_gt(groups.size(), 0, "VOID, not clean: no manifest entry resolved to a readable file")
	var sfx: Dictionary = _sfx()
	var shared: Array = []
	var disagreeing: Array = []
	for d in groups.keys():
		var keys: Array = groups[d]
		if keys.size() < 2:
			continue
		shared.append(keys)
		var labels := {}
		for k in keys:
			labels[str((sfx[k] as Dictionary).get("source", ""))] = true
		if labels.size() > 1:
			var rendered: Array = []
			for k in keys:
				rendered.append("%s source=%s" % [k, str((sfx[k] as Dictionary).get("source", "<absent>"))])
			disagreeing.append(rendered)
	## Without this the arm is VACUOUS exactly when the manifest has no aliases: the loop body never
	## runs and only the group floor asserts, so a guard about disagreement passes about nothing.
	assert_gt(shared.size(), 0,
		"no two manifest keys share an asset — this guard's subject does not exist; DELETE it rather than leaving it asserting nothing")
	assert_eq(disagreeing, [],
		"byte-identical assets disagree on `source` (%d group(s)) — one key is regen-protected and its twin is not: %s" % [disagreeing.size(), disagreeing])
	print("[provenance-parity] %d shared-asset group(s) across %d distinct digests" % [shared.size(), groups.size()])


func test_a_missing_source_is_what_falls_open() -> void:
	## CONTROL for the mechanism the arm above defends, so a reader need not trust the prose:
	## reproduces elevenlabs_sfx.py:124 and shows an ABSENT label is permissive while an
	## unrecognised one is refused. If this ever fails, the arm above is guarding the wrong field.
	assert_true(_regenerable(""), "CONTROL: an ABSENT source must read as regenerable, or the defect this file guards cannot occur")
	assert_false(_regenerable("ffmpeg_derive"), "a recognised non-elevenlabs source must be refused")
	assert_false(_regenerable("sox_synth"), "a recognised non-elevenlabs source must be refused")
	assert_true(_regenerable("elevenlabs_foley"), "an elevenlabs source must stay regenerable")


## Mirrors tools/elevenlabs_sfx.py:123-126 — set and not starting with "elevenlabs" means refuse.
func _regenerable(src: String) -> bool:
	return not (src != "" and not src.begins_with("elevenlabs"))
