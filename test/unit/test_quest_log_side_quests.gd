extends GutTest

## QuestSystem v1 landed with a HUD tracker line only — side quests
## were invisible in every menu. QuestLog now renders a SIDE QUESTS
## section from live QuestSystem state. Behavioral tests against the
## real autoloads with GameState.quests snapshot/restore (hermetic).

const QuestLogClass = preload("res://src/ui/QuestLog.gd")

var _saved_quests: Dictionary


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)


func after_each() -> void:
	GameState.quests = _saved_quests


func _lines_text(log_node: Control) -> String:
	var parts: Array = []
	for line in log_node._build_quest_lines():
		parts.append(str(line.get("text", "")))
	return "\n".join(parts)


func _make_log() -> Control:
	var n: Control = QuestLogClass.new()
	add_child_autofree(n)
	return n


func test_section_header_always_present() -> void:
	GameState.quests = {}
	var text := _lines_text(_make_log())
	assert_true(text.contains("SIDE QUESTS"),
		"side-quest section must render (discoverability) even with nothing tracked")
	assert_true(text.contains("None discovered yet"),
		"empty state must say so instead of a bare header")


func test_active_quest_shows_title_progress_and_giver() -> void:
	GameState.quests = {"world1_fools_spread": {"state": "active", "objective_index": 1}}
	var text := _lines_text(_make_log())
	var q: Dictionary = QuestSystem.get_quest("world1_fools_spread")
	assert_true(text.contains(str(q["title"])), "active quest title must render")
	var total: int = (q["objectives"] as Array).size()
	assert_true(text.contains("(2/%d)" % total),
		"objective progress must show 1-based current step over total")
	var giver: String = str(q["giver"]["display_name"])
	assert_true(text.contains("from " + giver), "giver attribution must render")


func test_completed_quest_shows_checkmark_only() -> void:
	GameState.quests = {"world1_fools_spread": {"state": "complete", "objective_index": 2}}
	var text := _lines_text(_make_log())
	var title: String = str(QuestSystem.get_quest("world1_fools_spread")["title"])
	assert_true(text.contains("✓  " + title), "completed quest renders with checkmark")
	assert_false(text.contains("from "),
		"completed quests don't need giver/objective detail lines")


func test_undiscovered_quests_stay_hidden() -> void:
	# Spoiler-safety: quests the player hasn't accepted must not leak
	# titles into the log.
	GameState.quests = {}
	var text := _lines_text(_make_log())
	for qid in QuestSystem.get_all_ids():
		var title: String = str(QuestSystem.get_quest(qid).get("title", ""))
		if title != "":
			assert_false(text.contains(title),
				"undiscovered quest '%s' must not appear in the log" % title)
