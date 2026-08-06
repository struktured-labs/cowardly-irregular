extends GutTest

## Every manifest audio entry must actually LOAD (2026-08-06).
##
## Presence on disk is not loadability. Godot serves audio through the import cache, so a
## file can be `git`-tracked, byte-perfect and unopenable: `FileAccess.file_exists()` is TRUE
## while `ResourceLoader.exists()` is FALSE until it has been imported. That gap shipped 11
## status cues with no committed `.import` sidecar — they existed, they were manifest-
## registered, and they were silent in the build.
##
## WHAT THIS CATCHES, honestly scoped:
##   · a manifest entry pointing at a renamed/deleted file (advance_queue's own sidecar was
##     a fossil of exactly this — the .ogg was renamed to advance_queue_arcade.ogg)
##   · an asset that cannot import in a clean checkout, which is what a fold gate and an
##     export both are
## WHAT IT DOES NOT CATCH: an uncommitted `.import` on the authoring machine. Locally the
## sidecar exists, so this passes; it fails where it matters instead — a fresh clone. Do not
## read a local green as proof the sidecar was committed.
##
## Built at a CLEAN state (0 unloadable of 271 sfx + 152 real tracks) — which is the only
## honest moment to add a ratchet. A guard installed over existing breakage has to bless it.

const SFX_MANIFEST := "res://data/sfx_manifest.json"
const MUSIC_MANIFEST := "res://data/music_manifest.json"


func _parse(path: String) -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


func test_premise_both_manifests_parse() -> void:
	## Every count below is vacuous if a manifest silently parsed to nothing.
	var sfx: Dictionary = _parse(SFX_MANIFEST).get("sfx", {})
	var mus: Dictionary = _parse(MUSIC_MANIFEST).get("tracks", {})
	assert_gt(sfx.size(), 200, "PREMISE: sfx manifest parsed to %d entries — implausible" % sfx.size())
	assert_gt(mus.size(), 100, "PREMISE: music manifest parsed to %d entries — implausible" % mus.size())


func test_every_sfx_entry_loads() -> void:
	var sfx: Dictionary = _parse(SFX_MANIFEST).get("sfx", {})
	var unloadable: Array[String] = []
	var checked: int = 0
	for key in sfx.keys():
		var entry: Variant = sfx[key]
		if not (entry is Dictionary):
			continue
		var rel: String = str(entry.get("file", ""))
		assert_false(rel.is_empty(), "sfx '%s' has no file field — every sfx cue is expected to have one" % key)
		if rel.is_empty():
			continue
		checked += 1
		if not ResourceLoader.exists("res://" + rel):
			unloadable.append("%s -> %s" % [key, rel])
	assert_gt(checked, 200, "control: only %d sfx entries were checked — the sweep is broken" % checked)
	assert_eq(unloadable.size(), 0,
		"%d sfx cue(s) are manifest-registered and CANNOT LOAD. Present-on-disk is not loadable; check the .import sidecar is committed and the path still matches the file: %s" % [unloadable.size(), unloadable])


func test_every_real_music_track_loads() -> void:
	## Placeholders are exempt BY DECLARATION, not by allowlist — see the next test.
	var mus: Dictionary = _parse(MUSIC_MANIFEST).get("tracks", {})
	var unloadable: Array[String] = []
	var checked: int = 0
	for key in mus.keys():
		var entry: Variant = mus[key]
		if not (entry is Dictionary):
			continue
		if bool(entry.get("placeholder", false)):
			continue
		var rel: String = str(entry.get("file", ""))
		checked += 1
		if rel.is_empty() or not ResourceLoader.exists("res://" + rel):
			unloadable.append("%s -> %s" % [key, rel if not rel.is_empty() else "<no file field>"])
	assert_gt(checked, 100, "control: only %d non-placeholder tracks checked — the sweep is broken" % checked)
	assert_eq(unloadable.size(), 0,
		"%d music track(s) are manifest-registered and CANNOT LOAD: %s" % [unloadable.size(), unloadable])


func test_a_placeholder_must_declare_what_it_is_waiting_for() -> void:
	## The exemption carries its own justification. A bare `placeholder: true` would be a
	## permission-to-skip flag — the shape that becomes muscle memory by the second use.
	## Requiring `planned_file` means you can only explain it green, never silence it green.
	var mus: Dictionary = _parse(MUSIC_MANIFEST).get("tracks", {})
	var placeholders: Array[String] = []
	var undeclared: Array[String] = []
	for key in mus.keys():
		var entry: Variant = mus[key]
		if not (entry is Dictionary) or not bool(entry.get("placeholder", false)):
			continue
		placeholders.append(str(key))
		if str(entry.get("planned_file", "")).is_empty():
			undeclared.append(str(key))
	assert_eq(undeclared.size(), 0,
		"placeholder track(s) with no `planned_file`: %s — a placeholder that doesn't say what it's waiting for is just a missing asset with a flag on it" % [undeclared])
	assert_lt(placeholders.size(), 10,
		"%d placeholder tracks (%s). This exemption is meant to be rare; if it is growing, the manifest is drifting from the bank." % [placeholders.size(), placeholders])


func test_no_orphaned_import_sidecars() -> void:
	## An `.import` whose asset is gone is a fossil, and a misleading one: advance_queue.ogg
	## was renamed to advance_queue_arcade.ogg and its stale sidecar sat there implying the
	## old path was real. A tool then assumed that path and blinded a 17-cue family.
	var orphans: Array[String] = []
	for dir_path in ["res://assets/audio/sfx", "res://assets/audio/music"]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			if not d.current_is_dir() and name.ends_with(".ogg.import"):
				var asset: String = dir_path + "/" + name.trim_suffix(".import")
				if not FileAccess.file_exists(asset):
					orphans.append(asset)
			name = d.get_next()
		d.list_dir_end()
	assert_eq(orphans.size(), 0,
		"%d orphaned .import sidecar(s) — the .ogg is gone but its sidecar remains, which makes a dead path look live: %s" % [orphans.size(), orphans])
