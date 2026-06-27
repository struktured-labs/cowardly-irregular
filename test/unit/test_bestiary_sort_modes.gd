extends GutTest

## tick 267: BestiarySystem.get_seen_entries_sorted now accepts a
## sort_mode parameter. Default ("level") preserves the historical
## level-ASC+name-ASC ordering. New modes:
##   - "kills": most-defeated first (autobattle planning hint)
##   - "name":  plain alphabetical
##
## BestiaryMenu cycles through the 3 modes on ui_left.


func before_each() -> void:
	GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["defeated_monsters"] = {}
	GameState.game_constants.erase("defeated_counts")
	GameState.game_constants.erase("seen_monsters_last_location")
	BestiarySystem.reload()


# ── Sort-mode constants pinned ────────────────────────────────────

func test_sort_mode_constants_exposed() -> void:
	assert_eq(BestiarySystem.SORT_LEVEL, "level")
	assert_eq(BestiarySystem.SORT_KILLS, "kills")
	assert_eq(BestiarySystem.SORT_NAME, "name")


# ── Default sort unchanged (backward compatible) ──────────────────

func test_default_sort_is_level_ascending() -> void:
	# Fixture: seen 2 monsters, the lower-level one should come first.
	if BestiarySystem.get_monster_data("slime").is_empty() \
			or BestiarySystem.get_monster_data("goblin").is_empty():
		push_warning("[test] missing slime/goblin fixtures — skipping")
		return
	BestiarySystem.mark_seen("goblin")
	BestiarySystem.mark_seen("slime")
	var entries: Array = BestiarySystem.get_seen_entries_sorted()
	# Slime is level 1, goblin is level 3 (per data/monsters.json).
	# Even with no argument, slime must come first.
	assert_eq(entries[0]["id"], "slime", "default sort must put lower-level first")


# ── Kills mode: most-defeated first ───────────────────────────────

func test_kills_mode_orders_by_defeat_count_desc() -> void:
	if BestiarySystem.get_monster_data("slime").is_empty() \
			or BestiarySystem.get_monster_data("goblin").is_empty():
		push_warning("[test] missing fixtures — skipping")
		return
	BestiarySystem.mark_seen("slime")
	BestiarySystem.mark_seen("goblin")
	# Goblin killed 5 times, slime killed 2.
	for i in range(2):
		BestiarySystem.mark_defeated("slime")
	for i in range(5):
		BestiarySystem.mark_defeated("goblin")
	var entries: Array = BestiarySystem.get_seen_entries_sorted(BestiarySystem.SORT_KILLS)
	assert_eq(entries[0]["id"], "goblin",
		"kills mode must put highest defeat_count first (goblin=5 > slime=2)")
	assert_eq(entries[1]["id"], "slime")


func test_kills_mode_falls_back_to_level_then_name() -> void:
	# Two entries with equal defeat counts must use level-ASC then name-ASC.
	if BestiarySystem.get_monster_data("slime").is_empty() \
			or BestiarySystem.get_monster_data("goblin").is_empty():
		push_warning("[test] missing fixtures — skipping")
		return
	BestiarySystem.mark_defeated("slime")
	BestiarySystem.mark_defeated("goblin")
	var entries: Array = BestiarySystem.get_seen_entries_sorted(BestiarySystem.SORT_KILLS)
	# Both have defeat_count=1; tiebreak goes to level.
	assert_eq(entries[0]["id"], "slime",
		"equal counts tiebreak by level (slime level 1 < goblin level 3)")


# ── Name mode: pure alphabetical ──────────────────────────────────

func test_name_mode_orders_alphabetically() -> void:
	if BestiarySystem.get_monster_data("slime").is_empty() \
			or BestiarySystem.get_monster_data("goblin").is_empty() \
			or BestiarySystem.get_monster_data("bat").is_empty():
		push_warning("[test] missing fixtures — skipping")
		return
	BestiarySystem.mark_seen("slime")
	BestiarySystem.mark_seen("goblin")
	BestiarySystem.mark_seen("bat")
	var entries: Array = BestiarySystem.get_seen_entries_sorted(BestiarySystem.SORT_NAME)
	# Resolved display names: "Bat", "Goblin", "Slime".
	assert_eq(entries[0]["name"], "Bat")
	assert_eq(entries[1]["name"], "Goblin")
	assert_eq(entries[2]["name"], "Slime")


# ── Unknown mode falls back to default (level) ────────────────────

func test_unknown_sort_mode_falls_back_to_level() -> void:
	if BestiarySystem.get_monster_data("slime").is_empty() \
			or BestiarySystem.get_monster_data("goblin").is_empty():
		push_warning("[test] missing fixtures — skipping")
		return
	BestiarySystem.mark_seen("slime")
	BestiarySystem.mark_seen("goblin")
	var entries: Array = BestiarySystem.get_seen_entries_sorted("nonsense_mode")
	# Same behavior as default — slime first.
	assert_eq(entries[0]["id"], "slime",
		"unknown sort_mode must fall through to default level-ASC behavior")


# ── BestiaryMenu cycles through the 3 modes ───────────────────────

func test_menu_declares_sort_cycle_constant() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	assert_true(src.contains("_SORT_CYCLE: Array[String] = [\"level\", \"kills\", \"name\"]"),
		"BestiaryMenu must declare the sort-cycle list as a const")


func test_menu_handles_ui_left_to_cycle() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	assert_true(src.contains("is_action_pressed(\"ui_left\")"),
		"BestiaryMenu must handle ui_left to advance the sort cycle")
	assert_true(src.contains("_sort_mode_idx = (_sort_mode_idx + 1) % _SORT_CYCLE.size()"),
		"ui_left handler must wrap around the 3-element cycle")
	assert_true(src.contains("func _re_sort_and_refresh"),
		"helper to re-fetch entries and rebuild the list must exist")


func test_menu_passes_sort_mode_to_system() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	# Both the initial _ready load AND the _re_sort_and_refresh path
	# must pass the current mode.
	assert_true(src.contains("BestiarySystem.get_seen_entries_sorted(_SORT_CYCLE[_sort_mode_idx])"),
		"_ready / refresh must pass the current sort mode to BestiarySystem")
