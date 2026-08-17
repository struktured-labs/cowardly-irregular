extends GutTest

## The durable rule struktured demanded 2026-08-17 ("why does this always
## happen") after PR #5 nearly reintroduced pre-purge sprite bytes over artist
## work — the third event of this class (July-2 bulk regen, July-11 purge,
## PR #5). Every tracked PNG under assets/sprites/jobs/** and
## assets/sprites/monsters/** is content-pinned in data/artist_sprite_ledger.json.
## ANY byte change — a fold taking the wrong side, a regen script, a stale
## branch — goes red here unless `tools/update_artist_ledger.py` was run and
## its diff committed DELIBERATELY alongside the art. The ledger diff in
## review is the intentionality record the artist-collab rules require.

const LEDGER := "res://data/artist_sprite_ledger.json"


func _ledger() -> Dictionary:
	var raw := FileAccess.get_file_as_string(LEDGER)
	assert_ne(raw, "", "ledger readable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "ledger parses")
	return parsed as Dictionary


func test_every_pinned_sprite_matches_its_ledger_hash() -> void:
	var ledger := _ledger()
	assert_gte(ledger.size(), 300, "ledger covers the sprite surface (398 at authoring)")
	# Control: a known artist file is pinned (wrong-shape-zero guard).
	assert_true(ledger.has("assets/sprites/jobs/bard/advance.png"), "control: artist bard sheet pinned")
	var mismatches := []
	for path in ledger:
		var res_path: String = "res://" + str(path)
		var actual := FileAccess.get_sha256(res_path)
		if actual == "":
			mismatches.append("%s: MISSING on disk (deletion must be acknowledged in the ledger)" % path)
		elif actual != str(ledger[path]):
			mismatches.append("%s: content changed without a ledger update" % path)
	assert_eq(mismatches.size(), 0,
		"sprite bytes changed without running tools/update_artist_ledger.py — if this change is DELIBERATE, run it and commit the diff; if you didn't change sprites, a fold just regressed artist work:\n" + "\n".join(mismatches))


func test_no_unpinned_sprites_in_protected_dirs() -> void:
	var ledger := _ledger()
	var missing := []
	for dir_path in ["res://assets/sprites/jobs", "res://assets/sprites/monsters"]:
		_scan(dir_path, ledger, missing)
	assert_eq(missing.size(), 0,
		"new sprite files must be enrolled — run tools/update_artist_ledger.py:\n" + "\n".join(missing))


func _scan(dir_path: String, ledger: Dictionary, missing: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if dir.current_is_dir():
			if not f.begins_with("."):
				_scan(full, ledger, missing)
		elif f.ends_with(".png") and not (".pre_" in f):
			# .pre_normalize/.pre_palette are gitignored pipeline scratch — only shipping sprites need pins.
			if not ledger.has(full.trim_prefix("res://")):
				missing.append(full)
		f = dir.get_next()
	dir.list_dir_end()
