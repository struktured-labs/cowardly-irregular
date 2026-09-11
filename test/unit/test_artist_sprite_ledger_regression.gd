extends GutTest

## The durable rule struktured demanded 2026-08-17 ("why does this always
## happen") after PR #5 nearly reintroduced pre-purge sprite bytes over artist
## work — the third event of this class (July-2 bulk regen, July-11 purge,
## PR #5). Every tracked PNG under the PINNED_DIRS below is content-pinned in
## data/artist_sprite_ledger.json.
## ANY byte change — a fold taking the wrong side, a regen script, a stale
## branch — goes red here unless `tools/update_artist_ledger.py` was run and
## its diff committed DELIBERATELY alongside the art. The ledger diff in
## review is the intentionality record the artist-collab rules require.

const LEDGER := "res://data/artist_sprite_ledger.json"

## ⚠️ PINNED_DIRS IS HALF OF A PAIR. tools/update_artist_ledger.py carries the same
## list as its `git ls-files` arguments, in Python, and nothing makes the two files
## agree at edit time. Losing a dir THERE is the silent direction — its pins stop
## being written and its files become unenrollABLE, not unenrolled — so the third
## arm below checks the two lists against each other THROUGH the ledger it wrote.
## portraits/ and npcs/ joined 2026-09-11: 13 bulk regen tools write into them and
## 116 hardcoded res:// paths in src/ read them, with zero content pins either side.
const PINNED_DIRS: Array[String] = [
	"assets/sprites/jobs",
	"assets/sprites/monsters",
	"assets/sprites/portraits",
	"assets/sprites/npcs",
]

## One artist-era file per pinned dir, so a dir emptying out cannot pass as a clean run.
const PIN_CONTROLS: Array[String] = [
	"assets/sprites/jobs/bard/advance.png",
	"assets/sprites/monsters/slime.png",
	"assets/sprites/portraits/fighter.png",
	"assets/sprites/npcs/elder_theron/overworld.png",
]


func _ledger() -> Dictionary:
	var raw := FileAccess.get_file_as_string(LEDGER)
	assert_ne(raw, "", "ledger readable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "ledger parses")
	return parsed as Dictionary


func test_every_pinned_sprite_matches_its_ledger_hash() -> void:
	var ledger := _ledger()
	# A FLOOR, not a count: art only ever arrives, so this reds on a bulk DELETION and
	# never on a legitimate addition. Do not convert it to assert_eq.
	assert_gte(ledger.size(), 800, "ledger covers the sprite surface — a drop this size is a bulk loss, not an edit")
	for control in PIN_CONTROLS:
		assert_true(ledger.has(control), "control: %s pinned (wrong-shape-zero guard)" % control)
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
	for dir_path in PINNED_DIRS:
		_scan("res://" + dir_path, ledger, missing)
	assert_eq(missing.size(), 0,
		"new sprite files must be enrolled — run tools/update_artist_ledger.py:\n" + "\n".join(missing))


func test_the_tool_and_this_test_cover_the_same_dirs() -> void:
	var ledger := _ledger()
	var pinned_roots := {}
	for path in ledger:
		var parts := str(path).split("/")
		if parts.size() >= 3:
			pinned_roots["%s/%s/%s" % [parts[0], parts[1], parts[2]]] = true
	# Tool wider than test: those pins ARE hash-checked above, but new files beside
	# them are never enrolled and nothing says so. This is the direction that is quiet.
	for root in pinned_roots:
		assert_true(PINNED_DIRS.has(root),
			"the ledger pins %s but no _scan root visits it — add it to PINNED_DIRS" % root)
	# Test wider than tool: the unpinned arm reds too, so this one only names the dir.
	for root in PINNED_DIRS:
		assert_true(pinned_roots.has(root),
			"%s is scanned but holds zero pins — tools/update_artist_ledger.py dropped it from PINNED_DIRS" % root)


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
			# .pre_* are pipeline rollback copies. MOST are gitignored scratch the tool cannot pin,
		# so demanding one would be unsatisfiable — but .pre_artist.png is NOT in .gitignore and
		# IS tracked and pinned. Skipping those here is safe only because the hash arm above
		# iterates the LEDGER, not the disk, so it checks them anyway. Over-matching is the
		# safe direction; do not narrow this to the exact gitignored suffixes.
			if not ledger.has(full.trim_prefix("res://")):
				missing.append(full)
		f = dir.get_next()
	dir.list_dir_end()
