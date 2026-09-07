extends GutTest

## tick 262: per-monster kill counter.
##
## Builds on tick 146's defeated boolean. Players grinding for drops
## or hitting an autobattle target ("farm slime for 50 bones") want
## to know how many they've already killed. The defeated flag is
## binary; the count is the actual signal.
##
## Stored in GameState.game_constants["defeated_counts"]: {id: int}.
## Initialized lazily by mark_defeated; absent for legacy saves.
## get_defeat_count returns 0 for unrecorded ids.


func before_each() -> void:
	GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["defeated_monsters"] = {}
	GameState.game_constants.erase("defeated_counts")
	BestiarySystem.reload()


# ── First defeat creates the dict and sets count to 1 ──────────────

func test_first_defeat_creates_counts_dict() -> void:
	assert_false(GameState.game_constants.has("defeated_counts"),
		"baseline: dict absent before any defeat")
	BestiarySystem.mark_defeated("slime")
	assert_true(GameState.game_constants.has("defeated_counts"),
		"mark_defeated must lazily create defeated_counts dict")
	assert_eq(BestiarySystem.get_defeat_count("slime"), 1,
		"first kill must read as 1")


# ── Counts increment per kill ──────────────────────────────────────

func test_subsequent_defeats_increment_count() -> void:
	for i in range(5):
		BestiarySystem.mark_defeated("slime")
	assert_eq(BestiarySystem.get_defeat_count("slime"), 5,
		"5 kills must accumulate to 5")


# ── Empty id is rejected (mirrors mark_defeated guard) ─────────────

func test_empty_id_does_not_pollute_counts_dict() -> void:
	BestiarySystem.mark_defeated("")
	var counts: Dictionary = GameState.game_constants.get("defeated_counts", {})
	assert_false(counts.has(""),
		"empty monster_id rejected by mark_defeated must not leak into defeated_counts")


# ── Unknown id still counts (matches tick 245 write-anyway policy) ─

func test_unknown_id_count_recorded() -> void:
	# Mirrors tick 245: unknown ids get push_warning but still write
	# (story-agent rename / drift recovery). Same applies to count.
	BestiarySystem.mark_defeated("__unknown_future_monster")
	assert_eq(BestiarySystem.get_defeat_count("__unknown_future_monster"), 1,
		"unknown id still increments — preserves credit if id arrives via reload")


# ── Legacy save (no defeated_counts key) reads 0 ──────────────────

func test_legacy_save_returns_zero_for_any_id() -> void:
	# Pre-tick-262 saves have no defeated_counts entry. get_defeat_count
	# must not crash or push_warning — silent zero.
	GameState.game_constants.erase("defeated_counts")
	assert_eq(BestiarySystem.get_defeat_count("anything"), 0,
		"legacy save with no defeated_counts must return 0 without crash")


# ── get_seen_entries_sorted exposes defeat_count ────────────────────

func test_seen_entries_include_defeat_count_field() -> void:
	if BestiarySystem.get_monster_data("slime").is_empty():
		push_warning("[test] slime missing from monsters.json — skipping")
		return
	BestiarySystem.mark_defeated("slime")
	BestiarySystem.mark_defeated("slime")
	BestiarySystem.mark_defeated("slime")
	var entries: Array = BestiarySystem.get_seen_entries_sorted()
	var slime_entry: Dictionary = {}
	for e in entries:
		if e.id == "slime":
			slime_entry = e
			break
	assert_false(slime_entry.is_empty(), "slime entry must exist")
	assert_eq(int(slime_entry.get("defeat_count", -1)), 3,
		"defeat_count field must reflect actual kill count (BestiaryMenu reads it)")


# ── UI source pin: "Killed: %d" only renders when count > 0 ───────

func test_menu_renders_killed_count_when_gt_zero() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	assert_true(src.contains("defeat_count > 0"),
		"BestiaryMenu must gate 'Killed:' line on defeat_count > 0 (no 'Killed: 0' noise)")
	assert_true(src.contains("\"   Killed: %d\""),
		"BestiaryMenu must render '   Killed: <count>' suffix on the rewards line")


# ── Cross-pin: defeated flag is still set in parallel ──────────────

func test_count_and_defeated_flag_stay_in_sync() -> void:
	# Pin the invariant: if count > 0 then is_defeated must be true.
	# Otherwise the bestiary would show stats unlocked but no kill ribbon.
	BestiarySystem.mark_defeated("slime")
	assert_true(BestiarySystem.is_defeated("slime"),
		"is_defeated must remain in sync with defeat_count > 0")
	assert_true(BestiarySystem.is_seen("slime"),
		"defeat → seen invariant preserved (tick 146)")
