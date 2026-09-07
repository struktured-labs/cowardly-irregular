extends GutTest

## tick 268: SaveScreen party-portrait preview was capped at 4 but
## the project's party is strict-5. The 5th party member (typically
## Bard, who joins at the Tavern in W1) silently never rendered in
## the save slot preview.
##
## Catches:
##   - the literal cap at the right value
##   - presence of the strict-5 cap comment so a future refactor
##     can't drift the literal without acknowledging the constraint
##
## Why a regex/text pin instead of a behavioral test: SaveScreen
## requires a full UI subscene + save fixtures to drive the render
## path. Source-pin is comparable rigor for a one-number bug.

const SAVE_SCREEN := "res://src/ui/SaveScreen.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Strict-5 cap pinned ───────────────────────────────────────────

func test_party_loop_caps_at_five() -> void:
	var src := _read(SAVE_SCREEN)
	# The party-portrait loop must cap at 5, not 4. Old form was
	# `for i in range(min(party_summary.size(), 4)):`.
	assert_true(src.contains("for i in range(min(party_summary.size(), 5)):"),
		"party portrait loop must cap at 5 (strict-5 party) — was 4 pre-fix")
	# Negative pin: the old buggy form must NOT survive.
	assert_false(src.contains("for i in range(min(party_summary.size(), 4)):"),
		"old cap-at-4 loop must be gone (regression check)")


# ── Loop annotation references the strict-5 constraint ───────────

func test_loop_has_strict_5_annotation() -> void:
	var src := _read(SAVE_SCREEN)
	# Ensures a future refactor sees the constraint without needing
	# to grep CLAUDE.md.
	assert_true(src.contains("strict-5"),
		"SaveScreen must annotate the cap with 'strict-5' so the constraint is visible at the source")


# ── Cross-pin: GameState's MAX_PARTY_SIZE is still 5 ──────────────

func test_game_state_max_party_size_still_5() -> void:
	# If MAX_PARTY_SIZE ever drifts off 5, the SaveScreen cap will need
	# updating too. This pin catches that mismatch class.
	var gs_src: String = FileAccess.get_file_as_string("res://src/meta/GameState.gd")
	assert_true(gs_src.contains("const MAX_PARTY_SIZE: int = 5"),
		"GameState.MAX_PARTY_SIZE must still be 5 — if this drifts, SaveScreen cap needs updating too")
