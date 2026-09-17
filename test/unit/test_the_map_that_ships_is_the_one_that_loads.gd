extends GutTest

## World 2-6 could not load their overworld in ANY exported build, and World 1 could.
##
## `MapImageLoader.load_rows` reads the map with `FileAccess.get_file_as_bytes` — RAW BYTES,
## not `load()`. An imported PNG does not ship its original file: the exporter packs the
## `.ctex` under `.godot/imported/` plus the `.import` sidecar, and the raw path is absent.
## Measured inside a real exported pck on godot 4.4.1-stable:
##
##                    ResourceLoader.exists   FileAccess.file_exists   load()
##   an imported png         TRUE                    FALSE              TRUE
##   a plain json            TRUE                    TRUE               TRUE
##
## So `FileAccess` — the one predicate that is genuinely wrong for imported resources — is
## the one this loader must use, because it is the only one that answers "are the raw bytes
## here". `importer="keep"` is what makes them here.
##
## Confirmed in the live web pck's own file table: `overworld_w1.png` present as a raw entry,
## w2-w6 present ONLY as `.import` sidecars. The caller then push_errors and RETURNS before
## setting a single tile — no map at all, not a broken one.
##
## Six rows, five wrong, and the right one is the one every test names: every map-png test in
## this tree reads `overworld_w1.png`, including the file called `test_per_world_map_palette`.
## It cannot fail in the editor or under run_tests.sh either, because there the raw file is
## sitting on disk. It only fails once packed.
##
## The corpus is DERIVED from the MAP_IMAGE consts rather than listed, so world 7 is covered
## the day someone declares it.

const SRC_ROOT := "res://src"


func _gd_files(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if d.current_is_dir():
			if not entry.begins_with("."):
				_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()


## Every res:// path declared as a MAP_IMAGE const anywhere in src/.
func _declared_map_images() -> Array:
	var files: Array = []
	_gd_files(SRC_ROOT, files)
	var re := RegEx.create_from_string('const\\s+MAP_IMAGE\\s*:\\s*String\\s*=\\s*"(res://[^"]+)"')
	var paths: Array = []
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		if src == "":
			continue
		for m in re.search_all(src):
			var p: String = m.get_string(1)
			if not paths.has(p):
				paths.append(p)
	paths.sort()
	return paths


func test_the_corpus_is_derived_and_not_empty() -> void:
	var paths := _declared_map_images()
	assert_gt(paths.size(), 1, "found %d MAP_IMAGE consts in src/ — a guard that enumerates no subjects is not a passing one, and a corpus of one is the defect this file exists for" % paths.size())
	gut.p("MAP_IMAGE consts found: %s" % str(paths))


func test_every_declared_map_image_ships_its_raw_bytes() -> void:
	var offenders: Array = []
	for raw in _declared_map_images():
		var p: String = str(raw)
		var imp: String = p + ".import"
		if not FileAccess.file_exists(imp):
			offenders.append("%s has NO .import sidecar at all" % p)
			continue
		var body := FileAccess.get_file_as_string(imp)
		if not body.contains('importer="keep"'):
			var which := "importer=?"
			var re := RegEx.create_from_string('importer="([^"]+)"')
			var m := re.search(body)
			if m != null:
				which = 'importer="%s"' % m.get_string(1)
			offenders.append("%s is %s" % [p, which])
	assert_eq(offenders.size(), 0, "these map images do not ship their raw bytes, so MapImageLoader's FileAccess read finds nothing once packed and the world generates NO tiles: %s" % str(offenders))


func test_the_loader_still_reads_raw_bytes_so_keep_is_still_required() -> void:
	## The premise arm. `importer="keep"` is only the right answer while the loader reads
	## bytes; if it ever moves to load(), this requirement is obsolete and should be revisited
	## rather than silently kept.
	var src := FileAccess.get_file_as_string("res://src/exploration/MapImageLoader.gd")
	assert_true(src.contains("FileAccess.get_file_as_bytes"), "MapImageLoader no longer reads raw bytes — re-derive whether importer=\"keep\" is still required before trusting the arm above")
	assert_true(src.contains("FileAccess.file_exists"), "MapImageLoader no longer gates on FileAccess.file_exists — the packing requirement this file pins may have changed")
