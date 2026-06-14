extends GutTest

## Regression: the W2-W5 "Find the portal to the next world" portal objectives
## must gate on the w<N>_dungeon_cleared flags the world bosses actually write
## via unlock_story_flag → GameState.set_story_flag (DragonCave.gd:509;
## SuburbanUnderground.gd:21, SteampunkMechanism.gd:17, AssemblyCore.gd:18,
## RootProcess.gd:17 set w2..w5_dungeon_cleared) — NOT the phantom
## w<N>_boss_defeated flags, which are written nowhere in src/ or data/. If a
## portal objective gates on a phantom flag, beating that world's boss never
## clears it and the objective stays stuck as the active one forever.
##
## NOTE: W1's own "Find the portal to the next world" objective legitimately
## gates on rat_king_defeated (then w1_boss_defeated → "Enter the Mundane
## Sprawl"); that flag pair IS written by the W1 flow, so it is correct and
## excluded from the *_dungeon_cleared assertion. There are FIVE portal-style
## objectives total (W1 + W2-W5); only the four W2-W5 ones use *_dungeon_cleared.
##
## The advance tests drive the actual boss-defeat write path (set_story_flag on
## the dungeon's unlock_story_flag) after fully completing World 1, so they
## exercise the real integration rather than pre-setting a phantom flag.

const QUEST_LOG_PATH := "res://src/ui/QuestLog.gd"
const QUEST_TRACKER_PATH := "res://src/exploration/QuestTracker.gd"

# Every W1 objective flag (QuestLog.CHAPTERS[0] / QuestTracker W1 block) — set
# all of these to genuinely complete World 1 before testing W2 advancement.
const _W1_FLAGS := [
	"prologue_complete",
	"chapter1_complete",
	"chapter2_complete",
	"chapter3_complete",
	"rat_king_defeated",
	"w1_boss_defeated",
]

# Flags the test mutates; saved/restored around each run. before_each resets
# every one to false, so the downstream W3-W6 flags here also guarantee a
# deterministic active objective regardless of state leaked by earlier tests.
const _TOUCHED_FLAGS := [
	"prologue_complete",
	"chapter1_complete",
	"chapter2_complete",
	"chapter3_complete",
	"rat_king_defeated",
	"w1_boss_defeated",
	"w2_entered",
	"w2_dungeon_cleared",
	"w3_entered",
	"w3_dungeon_cleared",
	"w4_entered",
	"w4_dungeon_cleared",
	"w5_entered",
	"w5_dungeon_cleared",
	"w6_entered",
]

var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_flags.clear()
	if GameState:
		for flag in _TOUCHED_FLAGS:
			_saved_flags[flag] = GameState.get_story_flag(flag)
			GameState.set_story_flag(flag, false)


func after_each() -> void:
	if GameState:
		for flag in _TOUCHED_FLAGS:
			GameState.set_story_flag(flag, _saved_flags.get(flag, false))


func _portal_flags(objectives: Array) -> Array:
	# Returns the flag of every "Find the portal" objective in the supplied
	# objective list (in story order).
	var out: Array = []
	for obj in objectives:
		if str(obj.get("text", "")).find("Find the portal") > -1:
			out.append(str(obj.get("flag", "")))
	return out


func _assert_portal_flags_aligned(portal_flags: Array, reader: String) -> void:
	# There are FIVE portal-style objectives: W1's (rat_king_defeated, the
	# legitimate W1 flow flag) plus one per W2-W5 world. The W1 entry is the
	# first in story order; the remaining four MUST gate on the written
	# *_dungeon_cleared flags, never the phantom *_boss_defeated flags.
	assert_eq(portal_flags.size(), 5,
		"%s should have five portal objectives (W1 + one per W2-W5 world)" % reader)
	if portal_flags.size() < 5:
		return

	# W1 portal objective legitimately gates on rat_king_defeated.
	assert_eq(portal_flags[0], "rat_king_defeated",
		"%s W1 portal objective must gate on rat_king_defeated, got: '%s'" % [reader, portal_flags[0]])

	# W2-W5 portal objectives must gate on the written *_dungeon_cleared flags.
	var w2_w5_flags := portal_flags.slice(1)
	for flag in w2_w5_flags:
		assert_true(flag.ends_with("_dungeon_cleared"),
			"%s W2-W5 portal objective must gate on the written *_dungeon_cleared flag, got: '%s'" % [reader, flag])
		assert_false(flag.ends_with("_boss_defeated"),
			"%s W2-W5 portal objective must NOT gate on the never-written *_boss_defeated flag, got: '%s'" % [reader, flag])
	assert_true(w2_w5_flags.has("w2_dungeon_cleared"), "%s W2 portal must use w2_dungeon_cleared" % reader)
	assert_true(w2_w5_flags.has("w3_dungeon_cleared"), "%s W3 portal must use w3_dungeon_cleared" % reader)
	assert_true(w2_w5_flags.has("w4_dungeon_cleared"), "%s W4 portal must use w4_dungeon_cleared" % reader)
	assert_true(w2_w5_flags.has("w5_dungeon_cleared"), "%s W5 portal must use w5_dungeon_cleared" % reader)


func test_quest_log_portal_objectives_use_dungeon_cleared_flags() -> void:
	# Walk every chapter's objectives and confirm the W2-W5 portal objectives
	# gate on the w<N>_dungeon_cleared flags the bosses actually write — never
	# the phantom w<N>_boss_defeated flags (written nowhere in src/ or data/).
	# W1's own portal objective legitimately gates on rat_king_defeated.
	var script = load(QUEST_LOG_PATH)
	var portal_flags: Array = []
	for chapter in script.CHAPTERS:
		portal_flags.append_array(_portal_flags(chapter["objectives"]))

	_assert_portal_flags_aligned(portal_flags, "QuestLog")


func test_quest_tracker_portal_objectives_use_dungeon_cleared_flags() -> void:
	var script = load(QUEST_TRACKER_PATH)
	var portal_flags := _portal_flags(script.OBJECTIVES)

	_assert_portal_flags_aligned(portal_flags, "QuestTracker")


func _complete_world1() -> void:
	# Fully complete World 1 so Chapter 2 is genuinely the active chapter.
	# Without this, the active objective is still a W1 objective and the W2
	# portal is never reached.
	for flag in _W1_FLAGS:
		GameState.set_story_flag(flag, true)


func test_quest_log_banner_advances_after_real_w2_boss_defeat() -> void:
	# Simulate the real boss-defeat write path: SuburbanUnderground sets
	# unlock_story_flag = "w2_dungeon_cleared", which DragonCave writes via
	# GameState.set_story_flag(unlock_story_flag). We drive THAT flag (not the
	# phantom one) and assert the QuestLog banner advances past the Ch2 portal
	# objective instead of staying stuck on it.
	#
	# Pre-condition: World 1 must be fully complete and W2 entered so the Ch2
	# portal objective (gated on w2_dungeon_cleared) is genuinely the active one.
	_complete_world1()
	GameState.set_story_flag("w2_entered", true)

	var ql_before = _stand_up_quest_log()
	var banner_before = _find_node_recursive(ql_before, "NextBanner") as Label
	assert_not_null(banner_before, "Banner should render while Ch2 portal is the active objective")
	if banner_before:
		assert_true(banner_before.text.find("Clockwork Dominion") > -1,
			"Before clearing the dungeon, banner should be stuck on the Ch2 portal objective, got: '%s'" % banner_before.text)

	# Real boss defeat: the dungeon's unlock_story_flag is written.
	GameState.set_story_flag("w2_dungeon_cleared", true)

	var ql_after = _stand_up_quest_log()
	var banner_after = _find_node_recursive(ql_after, "NextBanner") as Label
	# Once the Ch2 portal objective completes, the active objective must move on
	# (Ch3 is still locked, so the banner falls back to empty / absent) — it
	# must NOT still be stuck on the Ch2 portal objective.
	if banner_after:
		assert_true(banner_after.text.find("Clockwork Dominion") == -1,
			"After w2_dungeon_cleared, banner must advance past the Ch2 portal objective, got: '%s'" % banner_after.text)
	else:
		# Banner absent because Ch3 is locked — also a valid "advanced" state.
		pass_test("After w2_dungeon_cleared the Ch2 portal banner is no longer shown")


func test_quest_tracker_advances_after_real_w2_boss_defeat() -> void:
	# Pre-condition: World 1 complete + W2 entered. The tracker shows the text
	# of the last reached flag, so with w2_entered set (and dungeon not cleared)
	# the active objective is the W2 explore/find-portal phase ("Explore the
	# Mundane Sprawl"), NOT yet the Clockwork Dominion portal.
	_complete_world1()
	GameState.set_story_flag("w2_entered", true)
	var tracker = load(QUEST_TRACKER_PATH).new()
	add_child_autofree(tracker)
	tracker.setup(self)

	tracker._update_objective()
	assert_eq(tracker._current_objective, "Explore the Mundane Sprawl",
		"Before clearing the dungeon, tracker should show the W2 explore objective, got: '%s'" % tracker._current_objective)
	assert_true(tracker._current_objective.find("Clockwork Dominion") == -1,
		"Before clearing the dungeon, tracker must NOT yet show the Clockwork Dominion portal, got: '%s'" % tracker._current_objective)

	# Real boss defeat write path: the dungeon's unlock_story_flag is written.
	GameState.set_story_flag("w2_dungeon_cleared", true)
	tracker._update_objective()
	# Clearing w2_dungeon_cleared advances the tracker to the next goal — the
	# portal to the Clockwork Dominion. Had the objective gated on the phantom
	# w2_boss_defeated flag, the tracker would have stayed stuck here.
	assert_true(tracker._current_objective.find("Clockwork Dominion") > -1,
		"After w2_dungeon_cleared, tracker must advance to the Clockwork Dominion portal objective, got: '%s'" % tracker._current_objective)


func _stand_up_quest_log() -> Node:
	var script = load(QUEST_LOG_PATH)
	var ql = script.new()
	add_child_autofree(ql)
	ql._build_ui()
	return ql


func _find_node_recursive(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found = _find_node_recursive(child, target_name)
		if found:
			return found
	return null
