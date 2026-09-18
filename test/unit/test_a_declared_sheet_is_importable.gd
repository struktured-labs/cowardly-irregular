extends GutTest

## Every sheet the MANIFEST declares must be IMPORTABLE, not merely present on disk.
##
## `HybridSpriteLoader` resolves art through `data/sprite_manifest.json` and reaches a `.png` only
## through its `.png.import` sidecar. Without one the file is never imported: `load()` returns null,
## the loader falls back to procedural art, and the character still draws — so nothing looks wrong.
## `DirAccess` and `FileAccess` both report the file as present, which is why a scan cannot see it.
## This lane has already had 42 sheets in exactly that state, per the measurement recorded in
## test_world_dressed_sprite_lookup.gd — cited, not re-measured here.
##
## ⛔ THIS IS DETECTABLE HERE AND WAS SIMPLY NOT ASKED. `ResourceLoader.exists()` answers correctly
## under run_tests.sh — the gap was that nothing posed the question for the MANIFEST's corpus.
## Do not read the neighbouring map guard's editor-vs-export split into this file: that one is about
## RAW BYTES (`FileAccess.get_file_as_bytes`), which are present on disk in dev and absent once
## packed. This defect is visible in both places.
##
## SCOPE, vs the neighbouring guard: `test_world_dressed_sprite_lookup.gd` checks exactly
## `idle_<suffix>.png` under `assets/sprites/jobs/`. This checks every declaration in the manifest,
## derived from the file the loader reads rather than from a naming pattern on disk.
##
## ⛔ THE MANIFEST DECLARES IN TWO SHAPES AND THE FIRST VERSION OF THIS FILE SAW ONE.
## A monster or NPC entry carries a LITERAL `res://....png`. A job entry carries a `path` to a
## DIRECTORY plus an `animations` list, and `HybridSpriteLoader.job_asset_path()` composes
## `<path>/<anim>.png` at call time. Walking for strings that end in `.png` therefore found 303
## literal paths and ZERO of the 145 composed ones — so the arms below covered monsters, NPCs and
## tilesets while missing every job sheet, which is the largest and most visible category.
## Measured 2026-09-17, one release after shipping the narrow version. Both shapes now, with a
## SEPARATE floor per shape, because a single total would have stayed green through that gap.
##
## Triggers: SCOPE (corpus collapsed) · IMPORTABLE (a declaration Godot cannot reach) ·
## KEEP (raw-only, the mirror of the map fix) · PROBE (the instrument stopped discriminating).

const MANIFEST := "res://data/sprite_manifest.json"
const LITERAL_FLOOR := 200
const COMPOSED_FLOOR := 100


func _walk(node: Variant, acc: Array) -> Array:
	if node is Dictionary:
		for k in node:
			var v = node[k]
			if v is String and v.begins_with("res://") and v.ends_with(".png"):
				acc.append(v)
			else:
				_walk(v, acc)
	elif node is Array:
		for v in node:
			_walk(v, acc)
	return acc


## Job-shaped entries: a directory plus an animations list, composed exactly as
## HybridSpriteLoader.job_asset_path() composes them.
func _composed(parsed: Variant) -> Array:
	var out: Array = []
	if not (parsed is Dictionary):
		return out
	for sec_name in parsed:
		var sec = parsed[sec_name]
		if not (sec is Dictionary):
			continue
		for key in sec:
			var entry = sec[key]
			if not (entry is Dictionary):
				continue
			var base = entry.get("path")
			var anims = entry.get("animations")
			if base is String and anims is Array and str(base).begins_with("res://"):
				for a in anims:
					out.append("%s/%s.png" % [str(base), str(a)])
	return out


func _declared() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var acc: Array = _walk(parsed, [])
	acc.append_array(_composed(parsed))
	var uniq: Dictionary = {}
	for p in acc:
		uniq[p] = true
	var out: Array = uniq.keys()
	out.sort()
	return out


## Every entry lands in a named bucket, and the DANGEROUS bucket must be empty.
##
## _composed() reaches its answer past three bare `continue`s, and a skipped entry is
## indistinguishable from an absent one: it is simply not in the corpus. The floors have headroom
## (145 composed against a floor of 100), so ~45 job animations could stop being checked without
## any asserted count moving. cowir-sfx hit this exact shape in the SFX manifest the same day —
## three bare continues under one assert_gt(checked, 100) against a real corpus of 321.
##
## Pinned by REASON, not count: a `path` that is a DIRECTORY means the loader COMPOSES the
## filenames, so the entry must supply a list to compose from. A count reds on a legitimate new
## job and stays green on exactly the drop it exists to catch.
func test_a_directory_declaration_must_carry_a_list_to_compose() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "SCOPE: the manifest did not parse as a Dictionary")
	if not (parsed is Dictionary):
		return
	var literal_png := 0
	var composed_ok := 0
	var orphaned: Array = []
	for sec_name in parsed:
		var sec = parsed[sec_name]
		if not (sec is Dictionary):
			continue
		for key in sec:
			var entry = sec[key]
			if not (entry is Dictionary):
				continue
			var base = entry.get("path")
			if not (base is String) or not str(base).begins_with("res://"):
				continue
			if str(base).ends_with(".png"):
				literal_png += 1
			elif entry.get("animations") is Array:
				composed_ok += 1
			else:
				orphaned.append("%s/%s" % [sec_name, key])
	assert_gt(literal_png + composed_ok, 200,
		"SCOPE: only %d entr(ies) declare a usable res:// path — this arm is no longer reading the manifest's shape" % (literal_png + composed_ok))
	assert_eq(orphaned.size(), 0,
		"BUCKET: %d entr(ies) declare a DIRECTORY path with no list of animations, so nothing composes their filenames and they leave the corpus silently: %s" % [orphaned.size(), orphaned])


## The floor. Every arm below reads this corpus, so a manifest that stops declaring sheets would
## make all of them vacuously green — which is exactly how a guard outlives the thing it guards.
func test_the_corpus_is_derived_and_carries_BOTH_shapes() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var literal: Array = _walk(parsed, [])
	var composed: Array = _composed(parsed)
	# Separate floors. A single total is what let the composed shape go missing for a release:
	# 303 literal paths comfortably cleared any combined floor while 145 job sheets went unchecked.
	assert_gt(literal.size(), LITERAL_FLOOR,
		"SCOPE(literal): only %d literal res://*.png declaration(s) — monsters, NPCs and tilesets declare this way, so the arms below have lost that half" % literal.size())
	assert_gt(composed.size(), COMPOSED_FLOOR,
		"SCOPE(composed): only %d path(s) composed from a `path` + `animations` entry. JOB sheets declare this way and HybridSpriteLoader.job_asset_path() builds them at call time; a walk for strings ending in .png finds NONE of them" % composed.size())
	# The shapes must stay disjoint: an overlap means one derivation started duplicating the other,
	# which inflates the totals and hides a collapse in either.
	var lit: Dictionary = {}
	for x in literal:
		lit[x] = true
	var dupes: Array = []
	for x in composed:
		if lit.has(x):
			dupes.append(x)
	assert_eq(dupes.size(), 0,
		"SHAPES: %d path(s) appear in BOTH derivations (%s...). They are meant to be disjoint; an overlap means a total can stay healthy while one shape empties" % [dupes.size(), dupes.slice(0, 3)])

	# WIRING. The two floors above read the derivations DIRECTLY; every arm below reads
	# _declared(). Proving a derivation exists says nothing about whether the checks consume it —
	# measured: deleting the composed append from _declared() left both floors green and the
	# importable arm blind to all 145 job sheets, which is the very bug this file was fixing.
	var declared := _declared()
	var seen: Dictionary = {}
	for d in declared:
		seen[d] = true
	var dropped: Array = []
	for c in composed:
		if not seen.has(c):
			dropped.append(c)
	assert_eq(dropped.size(), 0,
		"WIRING: _declared() drops %d composed path(s) (%s...). The floors above still pass because they derive independently, so the arms below would report a clean corpus they never looked at" % [dropped.size(), dropped.slice(0, 3)])


func test_the_probe_can_see_absence() -> void:
	var declared := _declared()
	if declared.is_empty():
		return
	var absent: String = declared[0].replace(".png", "__no_such_variant.png")
	assert_false(ResourceLoader.exists(absent),
		"PROBE: ResourceLoader.exists() answered TRUE for %s, which is not on disk. The importable arm cannot detect anything while the instrument says yes to everything." % absent)
	var any_yes := false
	for p in declared:
		if ResourceLoader.exists(p):
			any_yes = true
			break
	assert_true(any_yes,
		"PROBE: ResourceLoader.exists() answered FALSE for all %d declarations. The instrument is saying no to everything, so the arm below would report the whole corpus as broken — suspect the probe before the art." % declared.size())


func test_every_declared_sheet_is_importable() -> void:
	var declared := _declared()
	var unreachable: Array = []
	for p in declared:
		if not ResourceLoader.exists(p):
			unreachable.append(p)
	assert_eq(unreachable, [],
		("IMPORTABLE: %d declared sheet(s) that Godot cannot reach. Each is present on disk and " +
		"invisible to the game: the loader falls back to procedural art and nothing reports it. " +
		"Run: godot --headless --audio-driver Dummy --import  : %s") % [unreachable.size(), unreachable])


## The mirror of the overworld-map fix. Those PNGs are read as RAW BYTES so they carry
## importer="keep"; a sheet is read through load(), so "keep" makes it unreachable. The same
## one-word edit is correct there and wrong here, which is why this is asserted rather than assumed.
func test_no_declared_sheet_is_raw_only() -> void:
	var declared := _declared()
	var kept: Array = []
	for p in declared:
		var sidecar: String = str(p) + ".import"
		if not FileAccess.file_exists(sidecar):
			kept.append("%s has NO .import sidecar at all" % p)
			continue
		var body: String = FileAccess.get_file_as_string(sidecar)
		if body.contains('importer="keep"'):
			kept.append('%s is importer="keep"' % p)
	assert_eq(kept, [],
		("KEEP: %d declared sheet(s) ship raw instead of imported. load() returns null for these " +
		"in an exported build while the editor is fine. importer=\"keep\" belongs on assets read " +
		"with FileAccess.get_file_as_bytes(), not on art the loader load()s : %s") % [kept.size(), kept])


## ⛔ "IMPORTABLE" IS A DEV-TREE PROPERTY AND THE ARM ABOVE READS AS A SHIPPING ONE.
##
## `ResourceLoader.exists()` answers from THIS checkout. A declaration whose art matches an
## export exclude_filter imports here and is ABSENT from every shipped build — so the arm above
## says "importable" about art no player can ever load, which is the opposite of what a reader
## takes it to mean. Same pcK-semantics gap as the one this file's header is about, one layer out:
## there the wrong PREDICATE, here the wrong TREE.
##
## Four entries match today, all four alternate-art staging rows that no job id reaches
## (bard_sdxl, mage_sdxl, rogue_sdxl via `jobs/*_sdxl/*`; rogue_artist via `jobs/*_artist/*`).
## Nothing is broken. The arm exists so a SHIPPING sheet cannot join them silently — you cannot
## silence it green, only add the id to the list with a reason.
const EXCLUDED_BY_DESIGN := ["bard_sdxl", "mage_sdxl", "rogue_sdxl", "rogue_artist"]


func _exclude_patterns() -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string("res://export_presets.cfg").split("\n"):
		var t := line.strip_edges()
		if not t.begins_with("exclude_filter="):
			continue
		for raw in t.split("=", true, 1)[1].strip_edges().trim_prefix("\"").trim_suffix("\"").split(","):
			var pat := raw.strip_edges()
			if pat != "" and not out.has(pat):
				out.append(pat)
	return out


## Builds (id -> declared paths). `_declared()` above returns a FLAT path list, which cannot
## answer "which entry owns this", and that is what the message below has to name.
func _declared_by_id() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var out: Dictionary = {}
	if not (parsed is Dictionary):
		return out
	for section in (parsed as Dictionary):
		var body = (parsed as Dictionary)[section]
		if not (body is Dictionary) or str(section).begins_with("_"):
			continue
		for id in (body as Dictionary):
			var entry = (body as Dictionary)[id]
			if not (entry is Dictionary):
				continue
			var paths: Array = []
			var top = (entry as Dictionary).get("path", "")
			var anims = (entry as Dictionary).get("animations", null)
			if str(top) != "" and anims is Array:
				for a in (anims as Array):
					paths.append("%s/%s.png" % [str(top), str(a)])
			elif str(top) != "":
				paths.append(str(top))
			for sub in (entry as Dictionary).values():
				if sub is Dictionary and str((sub as Dictionary).get("path", "")) != "":
					paths.append(str((sub as Dictionary)["path"]))
			if not paths.is_empty():
				out[str(id)] = paths
	return out


func test_a_declared_sheet_that_ships_is_not_export_excluded() -> void:
	var patterns := _exclude_patterns()
	assert_gt(patterns.size(), 5,
		"SCOPE: parsed %d exclude patterns from export_presets.cfg — a corpus this small means the parse broke, and every result below would be a clean sweep of nothing" % patterns.size())

	var by_id := _declared_by_id()
	assert_gt(by_id.size(), 20,
		"SCOPE: only %d declaring entries found — the id walk broke" % by_id.size())

	var offenders: Array[String] = []
	var matched_known := 0
	for id in by_id:
		for raw in by_id[id]:
			var path: String = str(raw).replace("res://", "")
			var hit := ""
			for pat in patterns:
				if path.match(str(pat)) or path.match("*/" + str(pat)):
					hit = str(pat)
					break
			if hit == "":
				continue
			if EXCLUDED_BY_DESIGN.has(str(id)):
				matched_known += 1
			else:
				offenders.append("%s (%s matches %s)" % [str(id), path, hit])

	assert_gt(matched_known, 0,
		"CONTROL: not one of %s matched an exclude pattern, so the matcher answers NO to everything and the arm below cannot fail" % str(EXCLUDED_BY_DESIGN))
	assert_eq(offenders.size(), 0,
		"these sheets are DECLARED in the manifest and EXCLUDED from every export, so they import in this checkout and are absent for every player: %s. Either the art ships or the declaration goes — and if the exclusion is deliberate, add the id to EXCLUDED_BY_DESIGN with the reason" % str(offenders))
