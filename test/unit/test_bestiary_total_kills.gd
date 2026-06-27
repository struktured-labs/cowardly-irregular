extends GutTest

## tick 263: bestiary header total-kills aggregate.
##
## Builds on tick 262's per-monster defeat counter. Header gets
## "· N kills" suffix so the player sees their cumulative grind
## tally without drilling into each entry. Hidden on narrow viewports
## (already collapses the seen/defeated split) and when the total is
## 0 (no "· 0 kills" noise on a brand-new save).


func before_each() -> void:
	GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["defeated_monsters"] = {}
	GameState.game_constants.erase("defeated_counts")
	BestiarySystem.reload()


# ── BestiarySystem.total_kills aggregate ───────────────────────────

func test_total_kills_zero_baseline() -> void:
	assert_eq(BestiarySystem.total_kills(), 0,
		"empty state must return 0 total kills")


func test_total_kills_sums_across_monsters() -> void:
	for i in range(3):
		BestiarySystem.mark_defeated("slime")
	for i in range(2):
		BestiarySystem.mark_defeated("bat")
	for i in range(1):
		BestiarySystem.mark_defeated("goblin")
	assert_eq(BestiarySystem.total_kills(), 6,
		"3 slime + 2 bat + 1 goblin = 6 total")


func test_total_kills_handles_legacy_save_safely() -> void:
	# Pre-tick-263 saves have no defeated_counts dict. total_kills
	# must return 0 without crash (matches get_defeat_count's
	# legacy-save policy).
	GameState.game_constants.erase("defeated_counts")
	assert_eq(BestiarySystem.total_kills(), 0,
		"legacy save without defeated_counts dict must return 0")


# ── BestiaryMenu source pin: header renders kills when > 0 ────────

func test_menu_renders_total_kills_when_positive() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	assert_true(src.contains("BestiarySystem.total_kills()"),
		"BestiaryMenu must call BestiarySystem.total_kills()")
	assert_true(src.contains("total_kills > 0"),
		"BestiaryMenu must gate '· N kills' on total_kills > 0 (no zero noise)")
	assert_true(src.contains("\" · %d kills\""),
		"BestiaryMenu must render ' · <N> kills' suffix on the seen/defeated line")


# ── Narrow viewport: kills suffix skipped ──────────────────────────

func test_menu_narrow_viewport_skips_kills_line() -> void:
	# Pin: the narrow_viewport branch builds the short text directly
	# without inspecting total_kills. Catches a regression where the
	# kills suffix leaks into the small header and overflows the
	# 200px label width.
	var src: String = FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	var narrow_idx: int = src.find("if narrow_viewport:")
	var else_idx: int = src.find("else:", narrow_idx)
	assert_gt(narrow_idx, -1)
	assert_gt(else_idx, narrow_idx)
	var narrow_body: String = src.substr(narrow_idx, else_idx - narrow_idx)
	assert_false(narrow_body.contains("kills"),
		"narrow viewport branch must NOT render the kills suffix (label is only 200px wide)")


# ── Stays in sync with per-monster get_defeat_count ──────────────

func test_total_equals_sum_of_per_monster_counts() -> void:
	# Pin the invariant. Avoids a future refactor that breaks one but
	# not the other.
	BestiarySystem.mark_defeated("slime")
	BestiarySystem.mark_defeated("slime")
	BestiarySystem.mark_defeated("bat")
	var summed: int = 0
	summed += BestiarySystem.get_defeat_count("slime")
	summed += BestiarySystem.get_defeat_count("bat")
	assert_eq(BestiarySystem.total_kills(), summed,
		"total_kills must equal the sum of get_defeat_count across all monsters")
