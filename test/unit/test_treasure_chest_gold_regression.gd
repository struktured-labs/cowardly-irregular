extends GutTest

## Regression: opening a gold treasure chest must actually add gold to
## GameState.party_gold. Pre-fix the chest fired its "Found N Gold!"
## floating text and emitted chest_opened with the amount, but no
## listener touched GameState — so the gold counter on PartyStatusScreen
## (and shop scenes, autogrind stats, etc.) stayed at whatever value it
## had before the chest opened. Silent failure: the player THINKS they
## got gold, the inventory says otherwise.

const TREASURE_CHEST_PATH := "res://src/exploration/TreasureChest.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_gold_branch_calls_gamestate_add_gold() -> void:
	# Source-level pin: the "gold" match arm must call GameState.add_gold,
	# not just construct the contents_text. Catches anyone re-deleting
	# the call or commenting it out (which is how the bug originally
	# made it to production — the "(if implemented)" comment was there
	# from the start).
	var text = _read(TREASURE_CHEST_PATH)
	var match_idx = text.find("\"gold\":")
	assert_true(match_idx > -1, "TreasureChest must still have a gold match arm")
	# 900-char window: the multi-line defensive comment between the match
	# arm header and the actual call eats into the simple `+500` bound.
	# Bigger window is harmless — the next match arm is `"item":` which
	# we don't want to confuse with the gold path either, but item match
	# arms don't contain `add_gold` so the assertion stays narrow.
	var window = text.substr(match_idx, 900)
	assert_true(window.find("GameState.add_gold(") > -1,
		"gold match arm must call GameState.add_gold(gold_amount) — the entire bug was that this call was missing")
	# Defensive guard so test-context invocations without GameState
	# don't crash (and CI doesn't fail on missing autoload).
	assert_true(window.find("has_method(\"add_gold\")") > -1,
		"gold add must guard `has_method` so test/debug callers without GameState don't crash")
	assert_false(window.find("# Add gold to party (if implemented)") > -1,
		"Stale TODO comment must be gone — its presence was the original tell that the call was missing")


func test_opening_gold_chest_actually_increases_party_gold() -> void:
	# Behavioral: stand up a TreasureChest configured for gold, drive the
	# open path, assert GameState.party_gold went up by the right amount.
	# The match-arm body is part of _on_open — we drive it via the
	# public API to ensure the wiring works end-to-end.
	if not GameState:
		pending("GameState autoload missing")
		return
	var prev_gold: int = int(GameState.party_gold)
	var prev_multiplier: float = GameState.game_constants.get("gold_multiplier", 1.0)
	# Force the gold_multiplier to 1.0 so the test arithmetic is exact.
	# add_gold rounds via int(amount * multiplier), so a non-1.0
	# multiplier would skew the assertion.
	GameState.game_constants["gold_multiplier"] = 1.0

	var script = load(TREASURE_CHEST_PATH)
	var chest = script.new()
	chest.chest_id = "test_fixture_gold"
	add_child_autofree(chest)
	chest.contents_type = "gold"
	chest.gold_amount = 250

	# Drive the open path directly. _open_chest takes a player Node2D
	# but doesn't actually dereference it in the gold branch — a stub
	# Node2D is enough to satisfy the type signature for unit-test
	# purposes. (interact() is the public surface that walks into
	# _open_chest after a player-press check; bypassing it skips the
	# already-opened guard which isn't relevant here either.)
	var stub_player := Node2D.new()
	add_child_autofree(stub_player)
	chest._open_chest(stub_player)

	assert_eq(int(GameState.party_gold), prev_gold + 250,
		"party_gold must increase by chest gold_amount (got %d, expected %d)" % [
			int(GameState.party_gold), prev_gold + 250])

	# Restore state.
	GameState.party_gold = prev_gold
	GameState.game_constants["gold_multiplier"] = prev_multiplier
