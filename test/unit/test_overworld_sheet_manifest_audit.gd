extends GutTest

## Artist-collab transparency ratchet: every overworld walk sheet on disk
## (jobs + NPCs) must be registered in sprite_manifest.json with a tier tag,
## and every registered entry must resolve on disk. The 26 npc sheets and
## 9 advanced/meta job sheets shipped untracked before this audit — AI-vs-
## artist provenance is a core pillar (the artist has approval rights on
## what ships, so untracked AI sheets are a policy hole, not just tidiness).

const HybridSpriteLoaderScript := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const MANIFEST_PATH := "res://data/sprite_manifest.json"
const VALID_TIERS := ["T0", "T1", "T2", "T3"]

## section name -> disk root holding <name>/overworld.png dirs
const SHEET_ROOTS := {
	"overworld_player_sheets": "res://assets/sprites/jobs",
	"overworld_npc_sheets": "res://assets/sprites/npcs",
}


func _load_manifest() -> Dictionary:
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	assert_not_null(file, "sprite_manifest.json must open")
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	assert_true(parsed is Dictionary, "manifest root must be a Dictionary")
	return parsed if parsed is Dictionary else {}


func _disk_sheet_names(root: String) -> Array:
	var names: Array = []
	var dir = DirAccess.open(root)
	assert_not_null(dir, "sheet root must open: %s" % root)
	for sub in dir.get_directories():
		# FileAccess, not ResourceLoader: a deleted PNG keeps its .ctex, so ResourceLoader.exists
		# enumerates sheets that are gone and this whole audit runs against a phantom corpus.
		if FileAccess.file_exists("%s/%s/overworld.png" % [root, sub]):
			names.append(sub)
	return names


## Sections this file does NOT audit, and WHY. Without this the omission is invisible: the loops
## simply never visit them and every test passes. Measured 2026-09-11 -- overworld_monster_sheets
## was unaudited and nothing said so.
##
## The reason is structural, not neglect: SHEET_ROOTS entries are DIRECTORY-per-sheet
## (<root>/<name>/overworld.png) and _disk_sheet_names walks get_directories(). A FLAT section
## (<root>/<name>.png) cannot be walked that way. Declared here rather than omitted, and EARNED by
## the test below -- an entry claiming "flat" whose paths are not flat refuses.
const FLAT_LAYOUT_SECTIONS := {
	"overworld_monster_sheets": "res://assets/sprites/monsters/overworld",
}


## ⚠️ THE FLAT SECTION IS AUDITED BUT NOT CONSUMED. `overworld_monster_sheets` has ZERO readers in
## src/ -- measured 2026-09-11, its only references outside the manifest are in THIS file. Registering
## a monster sheet there wires NOTHING. The game resolves overworld monster art by COMPOSED PATH:
##   RoamingMonster:147 / MasteriteEncounter:113   "res://assets/sprites/monsters/overworld/%s.png" % monster_id
## So the audit above proves provenance, NOT reachability, and a reader is entitled to assume it
## proves both. This arm checks the property that actually decides whether a player sees the art:
## the FILENAME must match a monster id, because that is the whole contract. 85 of 85 reachable at
## authoring; the direction it defends is dead art accumulating unnoticed, which no other arm sees.
## ⚠️ THE RULE BELOW IS THE CODE'S, NOT THIS FILE'S. The reachability arm depends on the sheet's
## FILENAME being exactly the monster id, and that is true only because two consumers compose the
## path that way -- inline, in both, with no shared helper (NPCs have HybridSpriteLoader
## .npc_overworld_path; monsters have nothing). A guard that restates the convention is a THIRD copy:
## change the template and the game loses every roaming monster's art while the guard stays green.
## So the template is read OUT of the consumers and the arm below is checked against what it finds.
const MONSTER_PATH_CONSUMERS: Array[String] = [
	"res://src/exploration/RoamingMonster.gd",
	"res://src/exploration/MasteriteEncounter.gd",
]


## ⛔ PIN THE STRIPPER, NOT THE CORPUS. A `#`-only strip leaves GDScript docstrings, which are
## STRING LITERALS — so prose naming a path reads as the path. Measured on this file's own arms
## 2026-09-12: gutting RoamingMonster's real composition and leaving a comment that mentioned it
## scored 9/9 GREEN, and a comment-only mention in an unrelated file was flagged as a consumer.
## Both directions, from one hole. The case table below is the cheap route to the seventh variant;
## four lanes broke six of them by planting mutations instead.
func _strip_comments(src: String) -> String:
	var out := ""
	var i := 0
	var in_str := ""          # "" none, else the delimiter we are inside
	while i < src.length():
		var three := src.substr(i, 3)
		if in_str == "" and three == "\"\"\"":
			var close := src.find("\"\"\"", i + 3)
			i = src.length() if close < 0 else close + 3
			continue
		var c := src[i]
		if in_str != "":
			if c == "\\":
				out += c
				i += 1
				if i < src.length():
					out += src[i]
					i += 1
				continue
			if c == in_str:
				in_str = ""
			out += c
			i += 1
			continue
		if c == "\"" or c == "'":
			in_str = c
			out += c
			i += 1
			continue
		if c == "#":
			var nl := src.find("\n", i)
			i = src.length() if nl < 0 else nl
			continue
		out += c
		i += 1
	return out


func test_the_comment_stripper_itself() -> void:
	var cases := [
		["var p = \"KEEP\"", "KEEP", true,  "plain code survives"],
		["# var p = \"GONE\"", "GONE", false, "whole-line comment removed"],
		["var p = \"KEEP\"  # GONE", "GONE", false, "trailing comment removed"],
		["var p = \"KEEP\"  # GONE", "KEEP", true,  "...without eating the code"],
		["## doc GONE", "GONE", false, "## doc comment removed"],
		["var p = \"a#b\"", "a#b", true,  "a # INSIDE a string is not a comment"],
	]
	for c in cases:
		var stripped: String = _strip_comments(str(c[0]))
		assert_eq(stripped.contains(str(c[1])), bool(c[2]), "%s — got %s" % [c[3], stripped])


func _composed_monster_templates() -> Dictionary:
	var re := RegEx.new()
	re.compile("\"(res://assets/sprites/monsters/overworld/[^\"]*)\"")
	var found := {}
	for path in MONSTER_PATH_CONSUMERS:
		var src := _strip_comments(FileAccess.get_file_as_string(path))
		if src == "":
			continue
		var m := re.search(src)
		if m != null:
			found[path] = m.get_string(1)
	return found


## ⚠️ MONSTER_PATH_CONSUMERS IS A HAND-LIST, which is the one shape that agrees with itself. The arm
## below reads the template out of those two files -- but a THIRD file composing its own overworld
## path is invisible to it, and a third file is exactly how a divergence arrives. So the list is
## checked against a derived sweep of src/: the hand-list stays (it is the premise, and deriving the
## premise from the thing under test is how a corpus drains to empty and passes), and this arm makes
## it impossible for the list to be WRONG without saying so.
func test_no_other_file_composes_an_overworld_monster_path() -> void:
	var found := _walk_gd("res://src")
	assert_gt(found.size(), 0, "CONTROL: the src sweep read something — an empty walk agrees with any list")
	var composers := []
	for path in found:
		var src := _strip_comments(FileAccess.get_file_as_string(path))
		if src.contains("assets/sprites/monsters/overworld/"):
			composers.append(path)
	composers.sort()
	var declared := PINNED_CONSUMERS_SORTED()
	assert_eq(composers, declared,
		"src/ composes overworld monster paths in a different set of files than MONSTER_PATH_CONSUMERS names — a file outside the list is never checked for template drift:\n  found:    %s\n  declared: %s" % [composers, declared])


func PINNED_CONSUMERS_SORTED() -> Array:
	var out := []
	for c in MONSTER_PATH_CONSUMERS:
		out.append(c)
	out.sort()
	return out


func _walk_gd(dir_path: String, acc: Array = []) -> Array:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return acc
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if dir.current_is_dir():
			if not f.begins_with("."):
				_walk_gd(full, acc)
		elif f.ends_with(".gd"):
			acc.append(full)
		f = dir.get_next()
	dir.list_dir_end()
	return acc


func test_the_overworld_monster_template_is_what_this_file_assumes() -> void:
	var found := _composed_monster_templates()
	assert_eq(found.size(), MONSTER_PATH_CONSUMERS.size(),
		"a consumer stopped composing an overworld monster path — the reachability arm's premise is gone, not merely unmet: %s" % [found])
	var values := []
	for k in found:
		values.append(found[k])
		# The arm below matches STEM to monster id. That holds only for <root>/%s.png exactly.
		assert_eq(found[k], "res://assets/sprites/monsters/overworld/%s.png",
			"%s composes a path this file's reachability arm cannot model; update BOTH or the arm lies" % k)
	# Two inline copies with no shared helper: they can drift apart silently.
	for v in values:
		assert_eq(v, values[0], "the two consumers compose DIFFERENT paths — one family of monsters is loading from somewhere this file never checks: %s" % [found])


## ⚠️ EVERY OTHER ARM IN THIS FILE IS A REGISTER CLAIM. They compare strings — a filename against a
## monster id, a template against a literal in source — and a string comparison cannot see a sheet
## that is ON DISK but did not IMPORT. That sheet renders NOTHING in game while every arm above stays
## green, because ResourceLoader reads the import cache and DirAccess reads the filesystem. This arm
## asks the question the player's machine asks: does the path the consumers build actually resolve?
func test_the_composed_path_actually_resolves_for_every_monster_with_art() -> void:
	var found := _composed_monster_templates()
	assert_gt(found.size(), 0, "no template to test — the premise arm above explains why")
	var template: String = found[found.keys()[0]]

	var root := "res://assets/sprites/monsters/overworld"
	var dir := DirAccess.open(root)
	assert_true(dir != null, "the flat root is readable")
	var on_disk := []
	for f in dir.get_files():
		if f.ends_with(".png"):
			on_disk.append(f.trim_suffix(".png"))
	assert_gt(on_disk.size(), 0, "the sweep found sheets — an empty root passes everything")

	var unresolved := []
	for id in on_disk:
		if not ResourceLoader.exists(template % id):
			unresolved.append(id)
	# ⛔ ALL failing means the tree is UNIMPORTED, not that the art is broken. Say which, or this
	# arm sends the next reader to look for 85 corrupt PNGs that are fine.
	if unresolved.size() == on_disk.size():
		assert_true(false,
			"NONE of %d sheets resolve through ResourceLoader — this tree is unimported, not broken. Run: XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import" % on_disk.size())
	else:
		assert_eq(unresolved.size(), 0,
			"these sheets sit on disk but do NOT resolve through the loader — they render nothing in game while every string-comparison arm in this file passes:\n" + "\n".join(unresolved))


func test_every_flat_sheet_is_reachable_by_some_monster_id() -> void:
	var raw := FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "monsters.json parses")
	var ids: Dictionary = parsed as Dictionary
	assert_gt(ids.size(), 50, "control: the id corpus is real, not an empty dict passing vacuously")

	# ⚠️ THE SHEET VOCABULARY, NOT THE WORLD VOCABULARY. World 5 is "digital" to sprites and
	# "futuristic" to data/field_elites.json and the audio map. Deriving from field_elites read as
	# rigorous -- a real file, no typed list -- and rejected a correctly named <id>_digital sheet as
	# dead art while accepting an <id>_futuristic one the loader will never ask for. The authority is
	# the constant the loader itself indexes; see test_world_suffix_vocabulary_regression for the split.
	var worlds: Array = []
	for suffix in HybridSpriteLoaderScript.WORLD_SUFFIXES:
		if str(suffix) != "":
			worlds.append(str(suffix))
	assert_gt(worlds.size(), 0, "control: suffixes read from HybridSpriteLoader.WORLD_SUFFIXES, not an empty set")

	var unreachable: Array = []
	var checked := 0
	for section in FLAT_LAYOUT_SECTIONS:
		var root: String = FLAT_LAYOUT_SECTIONS[section]
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".png"):
				continue
			checked += 1
			var stem := f.trim_suffix(".png")
			if ids.has(stem):
				continue
			var matched := false
			for w in worlds:
				if stem.ends_with("_" + str(w)) and ids.has(stem.trim_suffix("_" + str(w))):
					matched = true
					break
			if not matched:
				unreachable.append("%s/%s" % [root, f])
	assert_gt(checked, 0, "the sweep visited sheets — a flat root that walks nothing passes everything")
	assert_eq(unreachable.size(), 0,
		"overworld monster art is loaded by FILENAME (overworld/<monster_id>.png), so a sheet whose name matches no monster id can never be drawn — it is dead weight in the export:\n" + "\n".join(unreachable))


func test_flat_layout_sections_really_are_flat() -> void:
	# The exemption must be EARNED. Without this, FLAT_LAYOUT_SECTIONS is a suppression list that
	# would excuse any section someone wanted out of the audit.
	var manifest := _load_manifest()
	var wrong: Array = []
	for section in FLAT_LAYOUT_SECTIONS:
		var entries = manifest.get(section, {})
		assert_true(entries is Dictionary and not entries.is_empty(),
			"FLAT_LAYOUT_SECTIONS names '%s', which the manifest does not populate -- the entry excuses nothing" % section)
		for name in entries:
			var path := str(entries[name].get("path", ""))
			if path.ends_with("/overworld.png"):
				wrong.append("%s/%s is directory-per-sheet (%s) and belongs in SHEET_ROOTS" % [section, name, path])
	assert_eq(wrong, [], "a section declared FLAT holds directory-per-sheet paths: %s" % str(wrong))


## SHEET_ROOTS is the subject of every loop in this file, and draining it left all three tests GREEN
## (measured 2026-09-11, both magnitudes). The manifest is the independent register: every section
## it declares whose name matches the overworld-sheet shape must be audited here, so removing a
## root leaves its section unclassified rather than simply unvisited.
func test_every_overworld_manifest_section_is_audited() -> void:
	var manifest := _load_manifest()
	assert_gt(manifest.size(), 3, "CONTROL: manifest parsed %d sections -- a short read makes the sweep below free" % manifest.size())
	var unaudited: Array = []
	for section in manifest:
		if not (section is String) or not section.ends_with("_sheets"):
			continue
		if not str(section).begins_with("overworld_"):
			continue
		if not SHEET_ROOTS.has(section) and not FLAT_LAYOUT_SECTIONS.has(section):
			unaudited.append(section)
	assert_eq(unaudited, [],
		("a manifest section of overworld sheets is not in SHEET_ROOTS, so nothing in this file " +
		 "audits it -- disk and manifest can diverge there in silence: %s") % str(unaudited))


func test_every_disk_overworld_sheet_is_registered_with_tier() -> void:
	var manifest := _load_manifest()
	for section in SHEET_ROOTS:
		var entries = manifest.get(section, {})
		assert_true(entries is Dictionary and not entries.is_empty(),
			"manifest must have a populated '%s' section" % section)
		for name in _disk_sheet_names(SHEET_ROOTS[section]):
			assert_true(entries.has(name),
				"%s/%s/overworld.png is on disk but unregistered in %s — every AI sheet needs provenance tracking" % [SHEET_ROOTS[section], name, section])
			if entries.has(name):
				var tier = str(entries[name].get("tier", ""))
				assert_true(tier in VALID_TIERS,
					"%s entry '%s' needs a valid tier (got '%s') — T1=AI prototype, T2/T3=artist" % [section, name, tier])


func test_every_registered_overworld_sheet_exists_on_disk() -> void:
	var manifest := _load_manifest()
	for section in SHEET_ROOTS:
		var entries = manifest.get(section, {})
		for name in entries:
			var path = str(entries[name].get("path", ""))
			# This test is named "exists on disk" and asked ResourceLoader, which answers about the
			# IMPORT CACHE. Measured 2026-09-11: deleting monk/overworld.png and re-importing left
			# this GREEN -- --import rebuilds artifacts from bytes on disk but does not reap an
			# orphan, so load()/ResourceLoader.exists serve a sheet whose source is gone. The
			# premise here was already right (it iterates the manifest, every registered entry by
			# name); only the reader was wrong, and the two are independent.
			# GUT runs against the source tree, never an export, so FileAccess is the correct
			# authority -- do not "fix" this back for exported-build compatibility.
			assert_true(FileAccess.file_exists(path),
				"%s entry '%s' points at missing asset %s — stale manifest entry" % [section, name, path])


func test_registered_paths_match_naming_convention() -> void:
	# Entry key must equal the sheet's directory name — the loaders resolve
	# by convention (npcs/<archetype>/overworld.png), so a drifted key is a
	# silently-wrong provenance record.
	var manifest := _load_manifest()
	for section in SHEET_ROOTS:
		var entries = manifest.get(section, {})
		for name in entries:
			var expected = "%s/%s/overworld.png" % [SHEET_ROOTS[section], name]
			assert_eq(str(entries[name].get("path", "")), expected,
				"%s entry '%s' path must follow the <root>/<name>/overworld.png convention" % [section, name])
