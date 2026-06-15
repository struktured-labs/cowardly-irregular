extends GutTest

## Defensive regression: PartyStatusScreen.gd's nav input handler must
## not push focused_index out of [0, party.size()) when the party is
## empty.
##
## Bug shape:
##   • Pre-fix the right-press path did:
##       focused_index = min(party.size() - 1, focused_index + 1)
##     With an empty party (size 0), that's min(-1, focused_index + 1).
##     For focused_index == 0, the result is -1.
##   • _rebuild_detail's guard was only `if focused_index >= party.size(): return`.
##     That misses the negative direction — `-1 >= 0` is false. So
##     `party[focused_index]` would attempt `party[-1]`, which on an
##     empty array raises an out-of-bounds error.
##   • The screen can open against an empty party in test paths and
##     during the brief save-load race when GameState.player_party has
##     been cleared but not yet rehydrated.
##
## Fix: (1) gate both nav paths on a non-empty party; (2) widen
## _rebuild_detail's guard to cover negative indices as defense-in-depth.
##
## Tests:
##   • Source pins: _input's left and right paths both guard on
##     party.size() == 0
##   • Source pin: _rebuild_detail handles `focused_index < 0`
##   • Behavioural: right-press against an empty party leaves
##     focused_index at 0, no out-of-bounds error

const PARTY_STATUS_SCREEN_PATH := "res://src/ui/PartyStatusScreen.gd"
const PartyStatusScreenScript := preload("res://src/ui/PartyStatusScreen.gd")


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_input_left_guards_empty_party() -> void:
	var text := _read(PARTY_STATUS_SCREEN_PATH)
	var idx := text.find("func _input")
	assert_gt(idx, -1, "_input must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The first ui_left branch must include a party-size guard.
	var left_idx := body.find("ui_left")
	assert_gt(left_idx, -1, "ui_left branch must exist")
	var left_slice := body.substr(left_idx, 400)
	assert_true(left_slice.contains("party.size() == 0"),
		"ui_left branch must gate on `party.size() == 0` so an empty party doesn't navigate")


func test_input_right_guards_empty_party() -> void:
	var text := _read(PARTY_STATUS_SCREEN_PATH)
	var idx := text.find("func _input")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	var right_idx := body.find("ui_right")
	assert_gt(right_idx, -1, "ui_right branch must exist")
	var right_slice := body.substr(right_idx, 400)
	assert_true(right_slice.contains("party.size() == 0"),
		"ui_right branch must gate on `party.size() == 0` so an empty party doesn't push focused_index to -1")


func test_rebuild_detail_guards_negative_index() -> void:
	# The _input guards prevent focused_index from going negative under
	# normal operation, but _rebuild_detail's own bounds check should
	# defend against any future regression. Pre-fix the guard was only
	# `>= party.size()`, missing the < 0 direction.
	var text := _read(PARTY_STATUS_SCREEN_PATH)
	var idx := text.find("func _rebuild_detail")
	assert_gt(idx, -1, "_rebuild_detail must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("focused_index < 0"),
		"_rebuild_detail must guard `focused_index < 0` (defense in depth) so party[focused_index] can't blow up on party[-1]")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_right_press_against_empty_party_does_not_negate_focused_index() -> void:
	var screen: PartyStatusScreen = PartyStatusScreenScript.new()
	add_child_autofree(screen)
	# Empty party + visible required to enter the nav branches.
	screen.party = []
	screen.focused_index = 0
	screen.visible = true
	# Synthesise a ui_right action press.
	var event := InputEventAction.new()
	event.action = "ui_right"
	event.pressed = true
	screen._input(event)
	assert_eq(screen.focused_index, 0,
		"right-press against an empty party must NOT push focused_index negative")
	# Same for left.
	var event_left := InputEventAction.new()
	event_left.action = "ui_left"
	event_left.pressed = true
	screen._input(event_left)
	assert_eq(screen.focused_index, 0,
		"left-press against an empty party must NOT push focused_index negative")
