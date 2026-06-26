extends GutTest

## tick 199: JukeboxMenu.TRACKS now loads from music_manifest.json
## instead of a 29-entry hardcoded list that was wildly out of sync
## with the 150-entry live manifest. Pre-fix ids like "battle",
## "boss", "overworld", "cave", "battle_urban", "battle_void"
## didn't exist in the manifest — clicking them did nothing or
## fell back to procedural generation.
##
## Fix: _load_manifest_tracks() walks music_manifest.json.tracks
## and emits [[id, display_name]] sorted by id, with display
## preferring the manifest's "title" field (e.g., "The Realm
## Awakens" for overworld_medieval), falling back to proper
## title-cased id ("battle_slime" → "Battle Slime", not
## "Battle slime" from String.capitalize's first-letter-only
## limitation per tick 186).

const JUKEBOX_MENU := "res://src/ui/JukeboxMenu.gd"


func _cls():
	return load(JUKEBOX_MENU)


# ── Manifest load happy path ──────────────────────────────────────────

func test_load_returns_nonempty() -> void:
	# Pin: live manifest has 150 tracks. After load, the result is
	# also ~150 entries (sanity vs unloaded empty).
	var tracks: Array = _cls()._load_manifest_tracks()
	assert_gt(tracks.size(), 100,
		"manifest load must yield > 100 tracks (live data sanity)")


func test_each_entry_has_id_and_display() -> void:
	var tracks: Array = _cls()._load_manifest_tracks()
	for t in tracks:
		assert_true(t is Array, "each entry must be an Array")
		assert_eq(t.size(), 2, "each entry must be [id, display]")
		assert_true(t[0] is String and t[0].length() > 0,
			"id must be non-empty string")
		assert_true(t[1] is String and t[1].length() > 0,
			"display must be non-empty string")


func test_tracks_sorted_by_id() -> void:
	var tracks: Array = _cls()._load_manifest_tracks()
	var prev: String = ""
	for t in tracks:
		if prev != "":
			assert_true(t[0] >= prev,
				"tracks must be sorted by id ascending (saw '%s' after '%s')" % [t[0], prev])
		prev = t[0]


# ── Display name preference: manifest title > prettified id ────────────

func test_overworld_medieval_uses_manifest_title() -> void:
	# Pin: manifest has "title": "The Realm Awakens" for this id.
	var tracks: Array = _cls()._load_manifest_tracks()
	for t in tracks:
		if t[0] == "overworld_medieval":
			assert_eq(t[1], "The Realm Awakens",
				"overworld_medieval display must use manifest title")
			return
	fail_test("overworld_medieval missing from manifest load")


func test_battle_slime_uses_title_or_prettified_fallback() -> void:
	# Pin: battle_slime is a real id. Whatever the display is, it
	# must NOT have underscores (proves prettification or title-use).
	var tracks: Array = _cls()._load_manifest_tracks()
	for t in tracks:
		if t[0] == "battle_slime":
			assert_false("_" in t[1],
				"display must not contain underscores (title or _titlecase'd id)")
			return
	fail_test("battle_slime missing from manifest load")


# ── _titlecase helper ──────────────────────────────────────────────────

func test_titlecase_multi_word_proper_case() -> void:
	# Pin: proper title case across multiple words (not String.capitalize()'s
	# first-letter-only limitation — see tick 186).
	var cls = _cls()
	assert_eq(cls._titlecase("battle_slime"), "Battle Slime",
		"snake_case 2 parts → 'Battle Slime'")
	assert_eq(cls._titlecase("boss_warden_medieval"), "Boss Warden Medieval",
		"snake_case 3 parts proper-cased")
	assert_eq(cls._titlecase(""), "",
		"empty string returns empty")
	assert_eq(cls._titlecase("single"), "Single",
		"single word capitalized")


# ── Pre-fix stale ids are gone ────────────────────────────────────────

func test_old_stale_const_array_gone() -> void:
	# Negative pin: the old `const TRACKS = [...29 items...]` literal
	# must be gone. The new declaration is `var TRACKS: Array = []`.
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_false(src.contains("[\"battle\", \"Battle (Generic)\"]"),
		"old hardcoded 'battle' entry must be gone")
	assert_false(src.contains("[\"boss\", \"Boss Battle\"]"),
		"old hardcoded 'boss' entry must be gone")
	assert_false(src.contains("[\"battle_void\", \"Battle - Void\"]"),
		"old stale 'battle_void' (manifest uses 'battle_abstract') gone")
	assert_false(src.contains("[\"battle_urban\", \"Battle - Urban\"]"),
		"old stale 'battle_urban' (no such manifest id) gone")
	# Positive pin: TRACKS is now a var, populated dynamically.
	assert_true(src.contains("var TRACKS: Array = []"),
		"TRACKS must be a runtime-populated var")


func test_ready_loads_tracks_before_build_ui() -> void:
	# Pin: _ready() populates TRACKS BEFORE calling _build_ui(),
	# otherwise the row layout uses empty data.
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	var ready_idx: int = src.find("func _ready() -> void:")
	assert_gt(ready_idx, -1)
	# Search within ~400 chars of _ready for the order.
	var ready_body: String = src.substr(ready_idx, 600)
	var load_idx: int = ready_body.find("TRACKS = _load_manifest_tracks()")
	var build_idx: int = ready_body.find("_build_ui()")
	assert_gt(load_idx, -1, "TRACKS = _load_manifest_tracks() must be in _ready")
	assert_gt(build_idx, -1, "_build_ui() must be in _ready")
	assert_lt(load_idx, build_idx,
		"TRACKS must be populated BEFORE _build_ui (else row data is empty)")


# ── Loud-fail surfaces ────────────────────────────────────────────────

func test_loud_fail_pattern_present() -> void:
	# Pin: 4-stage loud-fail (file missing / open fail / parse error /
	# malformed root) — matches BestiarySystem._load_json pattern.
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("music_manifest.json not found"),
		"file-missing warning present")
	assert_true(src.contains("open failed"),
		"open-fail warning present")
	assert_true(src.contains("parse error"),
		"parse-error warning present")
	assert_true(src.contains("missing 'tracks' root key"),
		"missing-key warning present")


# ── Integration sanity: specific manifest ids resolve ──────────────────

func test_manifest_ids_match_known_files() -> void:
	# Pin: at least a handful of canonical ids load. Catches future
	# manifest schema changes that would render the jukebox empty.
	var tracks: Array = _cls()._load_manifest_tracks()
	var ids: PackedStringArray = []
	for t in tracks:
		ids.append(t[0])
	for canonical in ["overworld_medieval", "battle_medieval", "boss_medieval", "village_medieval",
			"battle_slime", "boss_rat_king", "title", "victory", "game_over"]:
		assert_true(canonical in ids,
			"canonical id '%s' must be in manifest" % canonical)
