extends GutTest

## tick 241: ChapterTitles boss-defeat coverage audit.
##
## Found 1 BUG + 3 missing entries:
##
## BUG: line 44 used cutscene_flag_warden_industrial_defeated (a
## W4 boss flag) but placed it in W3 chapter 4 with title "Warden
## of Steam". Likely a copy-paste error — W3's actual boss is
## Tempo, set via cutscene_flag_tempo_steampunk_defeated by the
## SteampunkMechanism dungeon subclass.
##
## Real impact: a player who defeated the W4 Industrial Warden
## before completing W4 chapter4 would see their save slot
## silently rewind to W3 ch4 "Warden of Steam" because derive()
## walks the array top-to-bottom and the misplaced W3 entry
## matched a W4 boss kill.
##
## Fix: line 44 now uses cutscene_flag_tempo_steampunk_defeated
## with title "Tempo Falls" (the actual W3 boss).
##
## Missing entries (now added):
##   W2: cutscene_flag_warden_suburban_defeated → "Warden of Routine Falls"
##   W4: cutscene_flag_warden_industrial_defeated → "Warden of Industrial Falls"
##   W5: cutscene_flag_arbiter_futuristic_defeated → "Arbiter Falls"
##
## Each entry is placed AFTER its triggering chapter (chapter3
## for W4/W5; chapter3 for W2) so the title transitions from
## "you're approaching the boss" to "you defeated the boss".

const CHAPTER_TITLES := "res://src/save/ChapterTitles.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── BUG FIX: line 44 W3 misplacement ────────────────────────────────

func test_w3_uses_tempo_flag_not_warden_industrial() -> void:
	# Pin: the W3 boss entry uses tempo_steampunk_defeated, not the
	# misplaced warden_industrial_defeated.
	var src := _read(CHAPTER_TITLES)
	# Find the "Tempo Falls" entry — must be in W3.
	assert_true(src.contains("\"cutscene_flag_tempo_steampunk_defeated\"") and src.contains("\"Tempo Falls\""),
		"W3 boss entry must use cutscene_flag_tempo_steampunk_defeated with title 'Tempo Falls'")


func test_w3_no_longer_has_misplaced_warden_industrial() -> void:
	# Negative pin: the W3-placed warden_industrial entry is gone.
	# (warden_industrial_defeated should now ONLY appear in W4.)
	var src := _read(CHAPTER_TITLES)
	# Check the specific bad shape ("warden_industrial_defeated" with world 3).
	# Use the derive() result to confirm semantic correctness instead.
	var cls = load(CHAPTER_TITLES)
	var game_constants := {
		"cutscene_flag_warden_industrial_defeated": true,
	}
	var result: Dictionary = cls.derive(game_constants)
	assert_eq(result["world"], 4,
		"warden_industrial_defeated must derive to world 4 (W4 Industrial Warden), not world 3")


# ── 3 new boss-defeat entries present ──────────────────────────────

func test_w2_warden_defeat_entry_present() -> void:
	var src := _read(CHAPTER_TITLES)
	assert_true(src.contains("\"cutscene_flag_warden_suburban_defeated\""),
		"W2 Warden defeat flag must be in CHAPTERS")
	assert_true(src.contains("\"Warden of Routine Falls\""),
		"W2 boss-defeat title must be 'Warden of Routine Falls'")


func test_w4_warden_defeat_entry_present() -> void:
	var src := _read(CHAPTER_TITLES)
	assert_true(src.contains("\"cutscene_flag_warden_industrial_defeated\""),
		"W4 Industrial Warden defeat flag must be in CHAPTERS (re-placed in correct world)")
	assert_true(src.contains("\"Warden of Industrial Falls\""),
		"W4 boss-defeat title must be 'Warden of Industrial Falls'")


func test_w5_arbiter_defeat_entry_present() -> void:
	var src := _read(CHAPTER_TITLES)
	assert_true(src.contains("\"cutscene_flag_arbiter_futuristic_defeated\""),
		"W5 Arbiter defeat flag must be in CHAPTERS")
	assert_true(src.contains("\"Arbiter Falls\""),
		"W5 boss-defeat title must be 'Arbiter Falls'")


# ── Live derive() returns correct title per defeat flag ─────────────

func test_derive_w2_warden_defeat() -> void:
	var cls = load(CHAPTER_TITLES)
	var game_constants := {
		"cutscene_flag_world2_chapter3_complete": true,
		"cutscene_flag_warden_suburban_defeated": true,
		# chapter4_garage NOT set yet
	}
	var result: Dictionary = cls.derive(game_constants)
	assert_eq(result["title"], "Warden of Routine Falls",
		"derive must return 'Warden of Routine Falls' for W2 boss KO")
	assert_eq(result["world"], 2)


func test_derive_w3_tempo_defeat() -> void:
	var cls = load(CHAPTER_TITLES)
	var game_constants := {
		"cutscene_flag_world3_chapter3_complete": true,
		"cutscene_flag_tempo_steampunk_defeated": true,
		# chapter4 NOT set yet
	}
	var result: Dictionary = cls.derive(game_constants)
	assert_eq(result["title"], "Tempo Falls",
		"derive must return 'Tempo Falls' for W3 boss KO")
	assert_eq(result["world"], 3)


func test_derive_w4_warden_defeat() -> void:
	var cls = load(CHAPTER_TITLES)
	var game_constants := {
		"cutscene_flag_world4_chapter3_complete": true,
		"cutscene_flag_warden_industrial_defeated": true,
	}
	var result: Dictionary = cls.derive(game_constants)
	assert_eq(result["title"], "Warden of Industrial Falls",
		"derive must return 'Warden of Industrial Falls' for W4 boss KO")
	assert_eq(result["world"], 4)


func test_derive_w5_arbiter_defeat() -> void:
	var cls = load(CHAPTER_TITLES)
	var game_constants := {
		"cutscene_flag_world5_chapter3_complete": true,
		"cutscene_flag_arbiter_futuristic_defeated": true,
	}
	var result: Dictionary = cls.derive(game_constants)
	assert_eq(result["title"], "Arbiter Falls",
		"derive must return 'Arbiter Falls' for W5 boss KO")
	assert_eq(result["world"], 5)


# ── Cross-reference: each boss defeat flag is set by a dungeon ──────

func test_boss_defeat_flags_match_dungeon_declarations() -> void:
	# Pin: each new flag corresponds to a defeat_cutscene_flags
	# entry in the dungeon source. Otherwise the ChapterTitles
	# entry would be dead config.
	var w2: String = FileAccess.get_file_as_string("res://src/maps/dungeons/SuburbanUnderground.gd")
	assert_true(w2.contains("cutscene_flag_warden_suburban_defeated"),
		"SuburbanUnderground must set warden_suburban_defeated")
	var w3: String = FileAccess.get_file_as_string("res://src/maps/dungeons/SteampunkMechanism.gd")
	assert_true(w3.contains("cutscene_flag_tempo_steampunk_defeated"),
		"SteampunkMechanism must set tempo_steampunk_defeated")
	var w4: String = FileAccess.get_file_as_string("res://src/maps/dungeons/AssemblyCore.gd")
	assert_true(w4.contains("cutscene_flag_warden_industrial_defeated"),
		"AssemblyCore must set warden_industrial_defeated")
	var w5: String = FileAccess.get_file_as_string("res://src/maps/dungeons/RootProcess.gd")
	assert_true(w5.contains("cutscene_flag_arbiter_futuristic_defeated"),
		"RootProcess must set arbiter_futuristic_defeated")


# ── Cross-pin: tick 240 entries preserved ───────────────────────────

func test_tick_240_entries_preserved() -> void:
	var src := _read(CHAPTER_TITLES)
	assert_true(src.contains("\"Rat King Falls\""),
		"tick 240 'Rat King Falls' entry preserved")
	assert_true(src.contains("\"Calibrant Falls\""),
		"tick 240 'Calibrant Falls' entry preserved")
	assert_true(src.contains("\"The End\""),
		"tick 240 'The End' entry preserved")
