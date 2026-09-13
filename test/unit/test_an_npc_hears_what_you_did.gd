extends GutTest

## The NPC's "what just happened" was five doors.
##
## `EventLog` records `area_entered` on EVERY map transition, and the NPC prompt
## takes the last `CONTEXT_EVENTS` (5) rows. Walking into a village, into a shop
## and back out is three rows — so by the time the player reaches someone to talk
## to, everything the party DID has been pushed out by where it WALKED.
##
## Measured on a realistic evening, boss defeat → level up → item → walk to town:
##
##     recent(5)          [area_entered] ×5, two of them one shop door
##                        the Cave Rat King, the level and the Sigil all gone
##     recent_varied(5)   level_up · boss_defeat · item_obtained · area_entered
##
## ⛔ THE SLICE HAPPENS AT THE SOURCE, which is why the formatter could not fix it.
## `DynamicConversation` calls `recent(CONTEXT_EVENTS)` at all five prompt sites,
## so the boss defeat is discarded before `_format_events` ever sees the array.
## Collapsing in the renderer would have been a no-op on the real path.
##
## `recent_varied` collapses consecutive same-type RUNS to their newest member.
## Chronology is preserved and the run keeps its LATEST entry, because that is
## where the party actually is — an NPC in Harmonia should hear "Entered
## Harmonia", not "Entered Whispering Cave Exit".
##
## ⚠️ Deliberately NOT applied to the rebalance daemon's window (`GameLoop` passes
## `recent(10)`): a difficulty trend wants the real sequence, including how much
## walking happened. `recent()` is unchanged and this file pins that too.

const DP := preload("res://src/llm/DialoguePrompts.gd")

var _log: EventLog


func before_each() -> void:
	_log = EventLog.new()


## The measured evening: three things done, then a walk to town.
func _an_evening() -> void:
	_log.record(EventLog.TYPE_LEVEL_UP, "Rilla reached level 12", {})
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "The party defeated the Cave Rat King", {})
	_log.record(EventLog.TYPE_ITEM_OBTAINED, "Obtained the Ember Sigil", {})
	for a in ["Whispering Cave Exit", "World 1 Overworld", "Harmonia", "Harmonia Item Shop", "Harmonia"]:
		_log.record(EventLog.TYPE_AREA_ENTERED, "Entered %s" % a, {})


func _types(rows: Array) -> Array[String]:
	var out: Array[String] = []
	for r in rows:
		out.append(str((r as Dictionary).get("type", "")))
	return out


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_walk_to_town_cannot_erase_the_boss_you_killed() -> void:
	## THE ARM. Five doors used to fill the whole window.
	_an_evening()
	var rows: Array = _log.recent_varied(DP.CONTEXT_EVENTS)
	assert_true(_types(rows).has(EventLog.TYPE_BOSS_DEFEAT),
		("the NPC cannot hear about the boss the party just killed — the window is %s. "
		+ "area_entered is recorded on every map transition, so walking to town erases it.")
		% str(_types(rows)))
	assert_true(_types(rows).has(EventLog.TYPE_ITEM_OBTAINED), "nor the item they picked up")
	assert_true(_types(rows).has(EventLog.TYPE_LEVEL_UP), "nor the level they gained")


func test_the_old_selector_really_did_lose_them() -> void:
	## THE PREMISE, pinned so the header's numbers stay checkable. If `recent`
	## ever stops being crowdable this fix is redundant and should be re-read.
	_an_evening()
	var rows: Array = _log.recent(DP.CONTEXT_EVENTS)
	assert_eq(_types(rows), ([EventLog.TYPE_AREA_ENTERED, EventLog.TYPE_AREA_ENTERED,
		EventLog.TYPE_AREA_ENTERED, EventLog.TYPE_AREA_ENTERED, EventLog.TYPE_AREA_ENTERED] as Array[String]),
		"recent() must still be the crowdable one — this fix exists because it is")


# ── the collapse must keep the right member and the right order ───────────────

func test_a_collapsed_run_keeps_where_the_party_IS() -> void:
	## Newest of the run, not oldest: an NPC in Harmonia should not be told the
	## party just entered the cave exit they left four doors ago.
	_an_evening()
	var rows: Array = _log.recent_varied(DP.CONTEXT_EVENTS)
	var last: Dictionary = rows[rows.size() - 1]
	assert_eq(str(last.get("summary", "")), "Entered Harmonia",
		"the surviving area row must be the newest: %s" % str(last))


func test_chronology_survives() -> void:
	## Same contract as recent(): oldest first.
	_an_evening()
	var rows: Array = _log.recent_varied(DP.CONTEXT_EVENTS)
	assert_eq(_types(rows), ([EventLog.TYPE_LEVEL_UP, EventLog.TYPE_BOSS_DEFEAT,
		EventLog.TYPE_ITEM_OBTAINED, EventLog.TYPE_AREA_ENTERED] as Array[String]),
		"order must be oldest-first and unshuffled: %s" % str(_types(rows)))


func test_the_limit_is_respected() -> void:
	for i in 40:
		_log.record(EventLog.TYPE_CUSTOM, "thing %d" % i, {})
		_log.record(EventLog.TYPE_LEVEL_UP, "level %d" % i, {})
	assert_lte(_log.recent_varied(3).size(), 3, "never more rows than asked for")
	assert_eq(_log.recent_varied(0).size(), 0, "a zero request yields nothing")


# ── it must not disturb what already worked ───────────────────────────────────

func test_a_log_with_no_runs_is_returned_unchanged() -> void:
	## CORRECT-WORK: collapsing must do nothing when nothing repeats.
	_log.record(EventLog.TYPE_LEVEL_UP, "a", {})
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "b", {})
	_log.record(EventLog.TYPE_ITEM_OBTAINED, "c", {})
	assert_eq(_log.recent_varied(5).size(), 3, "three distinct types, three rows")
	assert_eq(_types(_log.recent_varied(5)), _types(_log.recent(5)),
		"with no runs it must agree with recent() exactly")


func test_recent_is_untouched_for_the_trend_window() -> void:
	## CONTROL on the deliberate non-change: the rebalance daemon reads recent(10)
	## and wants the real sequence. If recent() ever starts collapsing, that window
	## silently stops seeing how much walking happened.
	_an_evening()
	assert_eq(_log.recent(8).size(), 8, "recent() must return every row, runs included")


# ── the call sites ────────────────────────────────────────────────────────────

func test_the_dialogue_paths_use_the_varied_selector_and_the_daemon_does_not() -> void:
	## SOURCE CHECK, named as one. The arms above drive the selector directly; this
	## pins that the prompt paths actually call it, and that the trend path does not.
	var conv: String = _code_only(
		FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd"),
		"func _resolve_party_state() -> Dictionary:")
	assert_eq(conv.count("_event_log.recent_varied("), 5,
		"all five NPC prompt sites must take the varied window (found %d)"
		% conv.count("_event_log.recent_varied("))
	assert_eq(conv.count("_event_log.recent("), 0,
		"no NPC prompt site may still take the crowdable window")
	var loop: String = _code_only(
		FileAccess.get_file_as_string("res://src/GameLoop.gd"), "func _ready() -> void:")
	assert_true(loop.find("event_log.recent(10)") != -1,
		("the rebalance daemon's trend window must stay raw — a trend wants the real "
		+ "sequence, including the walking"))


func test_the_fixture_really_recorded() -> void:
	## CONTROL: every arm reads rows back out. A log that recorded nothing would
	## make the has()-checks fail for the wrong reason and the size checks pass.
	_an_evening()
	assert_eq(_log.size(), 8, "the evening must be eight rows")
	assert_gt(_log.recent_varied(5).size(), 0, "and the selector must return some")


func _code_only(src: String, must_survive: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	var in_doc: bool = false
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		var code: String = line if hash_at == -1 else line.substr(0, hash_at)
		var trimmed: String = code.strip_edges()
		if in_doc:
			if trimmed.ends_with("\"\"\""):
				in_doc = false
			continue
		if trimmed.begins_with("\"\"\""):
			if trimmed.count("\"\"\"") % 2 == 1:
				in_doc = true
			continue
		out.append(code)
	var stripped: String = "\n".join(out)
	assert_true(stripped.find(must_survive) != -1,
		"STRIPPER CONTROL: '%s' must survive stripping" % must_survive)
	return stripped
