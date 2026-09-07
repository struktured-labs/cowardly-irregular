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
# `sfx` here is the CUTSCENE JSON step type, not a method — no `func play_sfx` exists, so it matches nothing in src and the JSON scanner covers those refs separately.
# Hoisted so the scope guard can READ this alternation — play_death escaped the audit for months because the list was restated by hand and nothing compared it to SoundManager.
const SFX_CALL_PATTERN := "play_(?:ui|battle|battle_scaled|ability|attack_hit|sfx|death|ambient|status_if_authored)\\(\\s*\"([a-zA-Z_0-9]+)\""
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
	# 2026-08-19: the four victory-kit entries retired here exactly as line 39 predicted —
	# the assets landed, the keys resolve, and this list is the FORWARD audit's copy of the
	# same retirement the reverse audit's KNOWN_PENDING_CONSUMER needed. Two lists, one
	# event: a kit landing retires entries in BOTH, and fixing only one leaves a red.
	# 2026-07-04: allowlist empty — quest_complete asset landed alongside
	# the QuestTracker branch (feature/sfx-quest-complete-relanding).
	# New orphans still fail loud below.
	#
	# 2026-07-25 (cowir-main msg 2929): DELIBERATELY TEMPORARY, and the
	# self-check below is what retires it. The windup consumer is wired in
	# _animate_melee_attack while its asset lives on cowir-sfx's unfolded
	# branch (feature/sfx-windup-prototype @ e33cb0d3) — cowir-main is
	# folding both together so struktured can hear it in motion. Until that
	# fold, the key legitimately doesn't resolve on main.
	# WHEN THE SFX BRANCH FOLDS: test_allowlist_has_no_stale_entries fails
	# and tells you to delete this line. That's intended — don't re-add it.
	# IF STRUKTURED RULES NO: delete the consumer line in BattleScene
	# _animate_melee_attack AND this entry together; the prototype is
	# explicitly throwaway.
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


var _visited_src: Dictionary = {}


func _scan_src_for_sfx_calls() -> Dictionary:
	## Walks src/**/*.gd, extracts the literal sfx key argument from
	## play_ui / play_battle / play_battle_scaled / play_ability /
	## play_attack_hit / play_sfx calls. Returns {key: true} set.
	var refs: Dictionary = {}
	_visited_src.clear()
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
				_visited_src[full] = true
				_extract_sfx_keys_from_text(_read_text(full), refs)
		name = dir.get_next()


func _extract_sfx_keys_from_text(text: String, refs: Dictionary) -> void:
	# Capture .play_<X>("KEY"...) where X is one of the play methods that
	# takes a literal sfx key. Skip play_music (different system).
	var regex := RegEx.new()
	# Matches: play_ui("foo") | play_battle("foo") | play_battle_scaled("foo" | play_ability("foo" | play_attack_hit("foo" | play_sfx("foo"
	regex.compile(SFX_CALL_PATTERN)
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

	# VACUITY: orphans derive ONLY from all_refs, so a scanner that stops matching passes at zero coverage — mutation-proven 2026-08-22, both arms. Name a known-present member, not a count.
	assert_true(code_refs.has("menu_select"),
		"src scanner found no 'menu_select' (125 literal call sites) — the play_* regex has stopped matching and the orphan audit below is scanning NOTHING")
	assert_true(json_refs.has("boss_defeat_stinger"),
		"cutscene scanner found no 'boss_defeat_stinger' (19 play_sfx steps) — the JSON walk has stopped matching and cutscene sfx are unaudited")

	# RESOLUTION SIDE: every canary below names the SCANNER's output and is upstream of `resolvable` — a polluted resolution set makes every key resolve, new_orphans stays empty, and the audit passes having adjudicated nothing. Both directions, because a set that answers true to everything and one that answers false to everything fail differently.
	assert_true(resolvable.has("menu_select"),
		"a key that IS in the manifest does not read as resolvable — the resolution set is broken and every audited key will be reported as an orphan")
	assert_false(resolvable.has("__never_authored_sfx_probe__"),
		"a fabricated key reads as RESOLVABLE — the resolution set is polluted and every real orphan below will be silently absorbed")

	# METHOD LIST: the scanner's play_* alternation is a SECOND pattern with its own unaudited complement — play_death and play_ambient sat outside it and their literal keys went unscanned. Name one key per covered method; play_status is EXCLUDED BY CONSTRUCTION (it builds "status_" + arg, so no literal key exists to match) and its cues stay unauditable here.
	for pair in [["enemy_death", "play_death"], ["weather_rain", "play_ambient"]]:
		assert_true(code_refs.has(pair[0]),
			"scanner lost coverage of %s — its literal sfx keys are unaudited, and a key-presence check on the OTHER methods still passes" % pair[1])

	# FAMILY B: _walk_src returns SILENTLY on a null DirAccess, so a lost subdir drops its files unnoticed. Canaries cover the THREE HIGHEST-DENSITY sfx dirs (ui 33 files / exploration 21 / battle 4); 8 sparser dirs stay uncovered — stated, not implied.
	for required in ["res://src/exploration/ShopScene.gd", "res://src/battle/BattleScene.gd", "res://src/ui/ItemsMenu.gd"]:
		assert_true(_visited_src.has(required),
			"the src walk never reached %s — a subdirectory failed to open and its sfx calls are unaudited, which a key-presence check cannot see" % required)

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
	# fail_test-only: a dead loader leaves `stale` empty and this reports "pruned" while unable to tell. GUT's Risky flag cannot catch it here — _read_text's assert_not_null counts as an assert for every caller, so no test in this file can ever score Risky (measured: remove that line and this test flips to [Risky]).
	assert_true(manifest_keys.has("menu_select"),
		"the manifest loader returned nothing — this test cannot distinguish a pruned allowlist from an unreadable manifest, and would report the list clean either way")
	assert_true(sounds_keys.has("attack_hit"),
		"the SOUNDS scrape returned nothing — same blindness on the other resolution source")

	var stale: Array = []
	for orphan in KNOWN_ORPHAN_SFX:
		if manifest_keys.has(orphan) or sounds_keys.has(orphan):
			stale.append(orphan)
	if not stale.is_empty():
		fail_test("KNOWN_ORPHAN_SFX contains entries that now DO resolve — remove them: %s" % [stale])


func test_every_allowlisted_orphan_is_actually_REACHABLE_by_the_scanner() -> void:
	# An allowlist entry the scanner cannot emit is INERT and looks identical to one doing real work — injury_sting sat here 4 days that way because play_death was outside the method list; the pruner cannot see it, asking only "does it resolve NOW", never "was it ever detected".
	var reachable: Dictionary = _scan_src_for_sfx_calls()
	for k in _scan_cutscene_sfx_refs():
		reachable[k] = true
	assert_true(reachable.has("menu_select"),
		"scanner returned nothing — this reachability check would pass every entry vacuously")
	var inert: Array = []
	for orphan in KNOWN_ORPHAN_SFX:
		if not reachable.has(orphan):
			inert.append(orphan)
	if not inert.is_empty():
		fail_test("KNOWN_ORPHAN_SFX entries no call site can produce — either the consumer was removed (delete the line) or the scanner cannot see its play_* method (widen the alternation): %s" % [inert])


func test_scanner_scope_covers_every_sound_key_taking_play_method() -> void:
	# The alternation IS the audit's scope — a second pattern with its own complement — so derive the requirement from SoundManager's DECLARATIONS, a source disjoint from the call sites being audited, rather than restating the list and trusting it.
	var open_at: int = SFX_CALL_PATTERN.find("(?:")
	var close_at: int = SFX_CALL_PATTERN.find(")", open_at)
	assert_gt(open_at, -1, "pattern has no alternation group — this guard cannot read the scope")
	var covered: PackedStringArray = SFX_CALL_PATTERN.substr(open_at + 3, close_at - open_at - 3).split("|")
	assert_true(covered.has("ui"), "scope parse lost a known member ('ui') — the guard would pass vacuously")

	var decl := RegEx.new()
	decl.compile("func (play_[a-z_0-9]+)\\(sound_key")
	var declared: Array = []
	for m in decl.search_all(_read_text(SOUND_MANAGER_PATH)):
		declared.append(m.get_string(1))
	assert_gt(declared.size(), 3, "almost no play_*(sound_key) declarations found — the scrape is broken and this guard would pass vacuously")

	var uncovered: Array = []
	for method in declared:
		if not covered.has(method.substr(5)):
			uncovered.append(method)
	if not uncovered.is_empty():
		fail_test("SoundManager accepts a literal sound_key through these methods but the scanner's alternation omits them — their call sites are UNAUDITED: %s" % [uncovered])


func test_sounds_dict_scrape_finds_a_known_entry() -> void:
	## Sanity check on the source-text SOUNDS scrape — if the parser
	## stops finding entries (e.g. the const SOUNDS = {} block gets
	## restructured), the orphan audit would silently see zero
	## resolutions and fail false-positive on everything.
	var sounds_keys: Dictionary = _load_sounds_dict_keys()
	for canary in ["attack_hit", "menu_select", "ability_fire"]:
		assert_true(sounds_keys.has(canary),
			"SOUNDS dict scrape must find '%s' — if missing, the scrape is broken and every test will false-positive" % canary)
