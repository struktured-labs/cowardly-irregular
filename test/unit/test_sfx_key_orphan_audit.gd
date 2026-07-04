extends GutTest

## Audit: cross-reference sfx keys called from src/ (play_ui /
## play_battle / play_battle_scaled / play_ability / play_attack_hit /
## play_sfx) AND from cutscene JSONs (play_sfx step.sfx field) against
## the union of sfx_manifest.json keys + SoundManager.SOUNDS dict keys.
## Pre-audit found:
##   - 2 code-side orphans (item_obtain — used by KeyItemPopup;
##     menu_error — used by 8+ UI menus for invalid-action feedback)
##   - 21+ JSON-side orphans (cutscene atmospheric sfx — bell_shift,
##     bicycle_bell, boss_spawn, chalk_tap, clock_chime, data_hum,
##     etc.) firing into silence at runtime
##
## Same orphan-ratchet shape as test_cutscene_grant_item_orphan_audit
## and test_cutscene_music_track_orphan_audit: NEW orphans fail loud,
## existing orphans being authored (added to manifest or SOUNDS) close
## quietly, and the stale-pruner test fires to remove resolved entries
## from the allowlist.

const SFX_MANIFEST_PATH := "res://data/sfx_manifest.json"
const SOUND_MANAGER_PATH := "res://src/audio/SoundManager.gd"
const SRC_DIR := "res://src"
const CUTSCENES_DIR := "res://data/cutscenes"

# Snapshot 2026-05-25 — sfx keys called from somewhere but resolving via
# neither sfx_manifest.json nor SoundManager.SOUNDS proc-gen dict.
# Triage:
#   - item_obtain: stinger when KeyItemPopup shows. Used by W1 fragment
#     cutscenes via grant_item handler. cowir-sfx authoring needed.
#   - menu_error: error blip for invalid actions (can't afford, slot
#     locked, etc.). 8+ UI call sites. cowir-sfx authoring needed.
#   - JSON cutscene SFX: atmospheric one-shots layered into specific
#     cutscene beats. cowir-sfx authoring needed; content-adjacent so
#     each entry is its own design call (sample bank vs proc-gen).
const KNOWN_ORPHAN_SFX := {
	# 2026-07-04: cowir-sfx msg 2160 called for a quest_complete jingle
	# (G-major heroic, sox-synth, 1.35s) but the asset lives on their
	# branch — the wiring shipped ahead so it lights up on their merge.
	# SoundManager.play_ui falls back silently to no-op in the meantime.
	"quest_complete": true,
}


func _read_text(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _load_manifest_sfx_keys() -> Dictionary:
	## Returns the keys of sfx_manifest.json's nested .sfx dict.
	var raw = _read_text(SFX_MANIFEST_PATH)
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary and parsed.has("sfx") and parsed["sfx"] is Dictionary:
		var result: Dictionary = {}
		for key in parsed["sfx"]:
			result[key] = true
		return result
	return {}


func _load_sounds_dict_keys() -> Dictionary:
	## Parses the SOUNDS const dict in SoundManager.gd for its top-level
	## keys. Not using a runtime load() because SOUNDS is a const Dict
	## that's intricate to introspect; source-text scrape is more robust.
	var text = _read_text(SOUND_MANAGER_PATH)
	var start = text.find("const SOUNDS = {")
	if start < 0:
		return {}
	# Find the matching closing brace — walk past the const value.
	# Heuristic: scan forward for the next "^}" at the start of a line.
	var keys: Dictionary = {}
	var lines = text.substr(start, 30000).split("\n")
	var depth = 0
	for line in lines:
		# Top-level keys are exactly one level deep in the SOUNDS dict
		# (the SOUNDS dict's direct entries). We track brace depth so
		# nested objects don't contribute their own keys to the count.
		var stripped: String = (line as String).strip_edges()
		if depth == 1:
			# Match `"key": {` or `"key":` patterns
			var quoted_match = stripped
			if quoted_match.begins_with("\""):
				var close_quote = quoted_match.find("\"", 1)
				if close_quote > 1:
					var key = quoted_match.substr(1, close_quote - 1)
					keys[key] = true
		# Update brace depth based on this line.
		var open_count: int = stripped.count("{")
		var close_count: int = stripped.count("}")
		depth += open_count - close_count
		if depth <= 0 and keys.size() > 0:
			break
	return keys


func _scan_src_for_sfx_calls() -> Dictionary:
	## Walks src/**/*.gd, extracts the literal sfx key argument from
	## play_ui / play_battle / play_battle_scaled / play_ability /
	## play_attack_hit / play_sfx calls. Returns {key: true} set.
	var refs: Dictionary = {}
	_walk_src(SRC_DIR, refs)
	return refs


func _walk_src(dir_path: String, refs: Dictionary) -> void:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name = dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full = dir_path + "/" + name
			if dir.current_is_dir():
				_walk_src(full, refs)
			elif name.ends_with(".gd"):
				_extract_sfx_keys_from_text(_read_text(full), refs)
		name = dir.get_next()


func _extract_sfx_keys_from_text(text: String, refs: Dictionary) -> void:
	# Capture .play_<X>("KEY"...) where X is one of the play methods that
	# takes a literal sfx key. Skip play_music (different system).
	var regex := RegEx.new()
	# Matches: play_ui("foo") | play_battle("foo") | play_battle_scaled("foo" | play_ability("foo" | play_attack_hit("foo" | play_sfx("foo"
	regex.compile("play_(?:ui|battle|battle_scaled|ability|attack_hit|sfx)\\(\\s*\"([a-zA-Z_0-9]+)\"")
	for match in regex.search_all(text):
		refs[match.get_string(1)] = true


func _scan_cutscene_sfx_refs() -> Dictionary:
	## Walks data/cutscenes/*.json for play_sfx steps and collects their
	## `sfx` field values.
	var refs: Dictionary = {}
	var dir = DirAccess.open(CUTSCENES_DIR)
	if dir == null:
		return refs
	dir.list_dir_begin()
	var name = dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			var parsed = JSON.parse_string(_read_text(CUTSCENES_DIR + "/" + name))
			if parsed is Dictionary and parsed.has("steps"):
				for step in parsed["steps"]:
					if step is Dictionary and step.get("type", "") == "play_sfx":
						var sfx = str(step.get("sfx", ""))
						if sfx != "":
							refs[sfx] = true
		name = dir.get_next()
	return refs


func test_every_sfx_key_resolves_or_is_allowlisted() -> void:
	var manifest_keys: Dictionary = _load_manifest_sfx_keys()
	var sounds_keys: Dictionary = _load_sounds_dict_keys()
	var resolvable: Dictionary = {}
	for k in manifest_keys: resolvable[k] = true
	for k in sounds_keys: resolvable[k] = true

	assert_gt(manifest_keys.size(), 50, "Test setup: sfx_manifest should have many entries (got %d)" % manifest_keys.size())
	assert_gt(sounds_keys.size(), 20, "Test setup: SOUNDS dict should have many entries (got %d)" % sounds_keys.size())

	var code_refs: Dictionary = _scan_src_for_sfx_calls()
	var json_refs: Dictionary = _scan_cutscene_sfx_refs()

	var all_refs: Dictionary = {}
	for k in code_refs: all_refs[k] = "code"
	for k in json_refs: all_refs[k] = all_refs.get(k, "cutscene JSON")

	var new_orphans: Array = []
	for key in all_refs:
		if resolvable.has(key):
			continue
		if KNOWN_ORPHAN_SFX.has(key):
			continue
		new_orphans.append({"key": key, "source": all_refs[key]})

	if not new_orphans.is_empty():
		var msg: String = "NEW orphan SFX keys (not in manifest, not in SOUNDS, not allowlisted):\n"
		for o in new_orphans:
			msg += "  - %s (called from: %s)\n" % [o.key, o.source]
		msg += "Either author the sfx OR fix the caller OR add to KNOWN_ORPHAN_SFX."
		fail_test(msg)


func test_known_orphan_sfx_list_stays_pruned() -> void:
	var manifest_keys: Dictionary = _load_manifest_sfx_keys()
	var sounds_keys: Dictionary = _load_sounds_dict_keys()
	var stale: Array = []
	for orphan in KNOWN_ORPHAN_SFX:
		if manifest_keys.has(orphan) or sounds_keys.has(orphan):
			stale.append(orphan)
	if not stale.is_empty():
		fail_test("KNOWN_ORPHAN_SFX contains entries that now DO resolve — remove them: %s" % [stale])


func test_sounds_dict_scrape_finds_a_known_entry() -> void:
	## Sanity check on the source-text SOUNDS scrape — if the parser
	## stops finding entries (e.g. the const SOUNDS = {} block gets
	## restructured), the orphan audit would silently see zero
	## resolutions and fail false-positive on everything.
	var sounds_keys: Dictionary = _load_sounds_dict_keys()
	for canary in ["attack_hit", "menu_select", "ability_fire"]:
		assert_true(sounds_keys.has(canary),
			"SOUNDS dict scrape must find '%s' — if missing, the scrape is broken and every test will false-positive" % canary)
