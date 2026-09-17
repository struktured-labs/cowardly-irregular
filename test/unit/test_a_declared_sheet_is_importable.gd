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
## `idle_<suffix>.png` under `assets/sprites/jobs/`. This checks EVERY declaration in the manifest —
## walk, attack, dead, cast, monsters, portraits, tilesets — derived from the file the loader reads
## rather than from a naming pattern on disk.
##
## Triggers: SCOPE (corpus collapsed) · IMPORTABLE (a declaration Godot cannot reach) ·
## KEEP (raw-only, the mirror of the map fix) · PROBE (the instrument stopped discriminating).

const MANIFEST := "res://data/sprite_manifest.json"
const CORPUS_FLOOR := 100


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


func _declared() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var acc: Array = _walk(parsed, [])
	var uniq: Dictionary = {}
	for p in acc:
		uniq[p] = true
	var out: Array = uniq.keys()
	out.sort()
	return out


## The floor. Every arm below reads this corpus, so a manifest that stops declaring sheets would
## make all of them vacuously green — which is exactly how a guard outlives the thing it guards.
func test_the_corpus_is_derived_and_not_empty() -> void:
	var declared := _declared()
	assert_gt(declared.size(), CORPUS_FLOOR,
		"SCOPE: only %d .png declaration(s) found in %s. Every other arm in this file reads this corpus, so they are all vacuous below the floor. Either the manifest shrank or _walk() no longer matches its shape." % [declared.size(), MANIFEST])


## The instrument's positive control, derived from the corpus rather than from a literal: if
## ResourceLoader.exists() ever answers true for a path that is not there, the arm below passes
## while proving nothing.
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
