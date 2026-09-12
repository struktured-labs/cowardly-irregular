extends GutTest

## Finish Milo's thesis quest and he goes back to talking like you never did it.
##
## Every showcase NPC can carry `quest_state_lines` in its persona — buckets of
## authored voice keyed to where the player is in the quest that NPC gives. The
## resolver mapped QuestSystem's state to a bucket like this:
##
##     if state == "active":                            return "in_progress"
##     if state == "completed" or state == "turned_in": return "post_quest"
##     if state == "":                                  return "pre_task_1"
##
## ⛔ **QuestSystem writes "complete".** `"completed"` and `"turned_in"` occur
## NOWHERE else in src/ — the only two mentions in the whole tree were those two
## comparisons. So `post_quest` could never be selected, and a finished quest fell
## through to `""`, which means *no override at all*.
##
## Driven through the real resolver against the real QuestSystem, before the fix:
##
##     quest absent   -> "pre_task_1"    ✅
##     state "active" -> "in_progress"   ✅
##     state "complete" -> ""            ❌  should be "post_quest"
##
## What it costs: Scholar Milo's persona declares **five authored post_quest
## lines** and a money-pick index for them. They were unreachable on BOTH paths —
## the scripted rotation and the LLM prompt's `quest_state_lines` block, which is
## how the model is told what this character sounds like right now. The one
## moment the feature exists for — the player comes back having done the thing —
## is the one moment it never fired.
##
## The map is now declared rather than chained, and pinned against QuestSystem's
## OWN writers: every state string that file assigns must be a key here. A hand
## list agrees with itself; this one reds when QuestSystem learns a new state.

const NPCScript = preload("res://src/exploration/OverworldNPC.gd")
const QID := "world1_chapter_three"
const QUEST_SRC := "res://src/quests/QuestSystem.gd"

var _saved_quests: Dictionary


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)


func after_each() -> void:
	GameState.quests = _saved_quests


## A bare giver — enough to resolve a bucket, not enough to own persona lines.
func _milo() -> Node:
	var npc: Node = NPCScript.new()
	npc.npc_name = "Scholar Milo"
	npc.npc_id = "scholar_milo"
	add_child_autofree(npc)
	return npc


## The real thing: `dynamic` after _ready re-runs the persona overlay, so the
## authored buckets are actually loaded.
func _milo_with_persona() -> Node:
	var npc: Node = _milo()
	npc.dynamic = true
	return npc


func _bucket_for(state: Variant) -> String:
	if state == null:
		GameState.quests.erase(QID)
	else:
		GameState.quests[QID] = {"state": str(state), "objective_index": 0}
	return str(_milo()._quest_state_bucket_for_npc(QuestSystem))


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_completed_quest_reaches_the_post_quest_voice() -> void:
	## THE ARM. "complete" is what QuestSystem writes; the resolver was reading for
	## two strings the codebase has never contained.
	assert_eq(_bucket_for("complete"), "post_quest",
		"a finished quest must select the post-quest bucket")


func test_the_other_two_buckets_still_resolve() -> void:
	## CONTROL, and it is what made the defect hard to see: two thirds of the
	## feature worked, so the NPC visibly changed voice as the quest progressed and
	## only the last step was dead.
	assert_eq(_bucket_for(null), "pre_task_1", "an unstarted quest is pre_task_1")
	assert_eq(_bucket_for("active"), "in_progress", "an accepted quest is in_progress")


func test_an_unknown_state_still_means_no_override() -> void:
	## The contract for "" is unchanged: no bucket, keep the authored default.
	assert_eq(_bucket_for("gibberish"), "", "an unrecognised state must not invent a bucket")


# ── the authored lines are actually reachable now ─────────────────────────────

func test_the_five_post_quest_lines_are_reachable() -> void:
	## The consequence a player meets. The bucket is only worth resolving if the
	## lines behind it exist, and they are what the LLM prompt carries as this
	## character's current voice.
	GameState.quests[QID] = {"state": "complete", "objective_index": 6}
	var npc: Node = _milo_with_persona()
	var bucket: String = str(npc._quest_state_bucket_for_npc(QuestSystem))
	assert_eq(bucket, "post_quest", "CONTROL: the bucket must resolve before its lines can matter")
	assert_gt(npc._quest_state_bucket_rotation(bucket).size(), 0,
		"the post-quest bucket must yield authored lines — they are the point of the fix")


func test_the_rotation_probe_is_not_blind() -> void:
	## POSITIVE CONTROL on the arm above, and it caught me: a bare NPC has no
	## persona loaded, so `_quest_state_bucket_rotation` returns 0 for EVERY bucket
	## — including ones that work. A zero there says nothing about the bucket.
	var bare: Node = _milo()
	assert_eq(bare._quest_state_bucket_rotation("in_progress").size(), 0,
		"a persona-less NPC returns nothing for a bucket that is otherwise fine")
	var loaded: Node = _milo_with_persona()
	assert_gt(loaded._quest_state_bucket_rotation("in_progress").size(), 0,
		"and the loaded one does return lines — so the probe can tell the two apart")


func test_the_llm_path_gets_the_same_bucket() -> void:
	## The prompt reads `_persona_quest_state_lines[bucket]` directly rather than
	## through the rotation, so the fix has to reach that lookup too.
	var npc: Node = _milo_with_persona()
	assert_true(npc._persona_quest_state_lines.has("post_quest"),
		"the persona must carry a post_quest bucket for the prompt to find")
	assert_gt((npc._persona_quest_state_lines["post_quest"] as Array).size(), 0,
		"and it must be non-empty, or the prompt block renders nothing")


# ── the premise: the map must track QuestSystem's own writers ─────────────────

func test_every_state_questsystem_writes_has_a_bucket() -> void:
	## THE RATCHET. The bug was a map that agreed with itself about strings the
	## writer never produced. Derive the writers instead: every state literal
	## QuestSystem assigns must be a key here.
	var written: Array[String] = _states_questsystem_writes()
	assert_gte(written.size(), 2,
		"CONTROL: the scan derived only %d written states — the derivation is broken" % written.size())
	var unmapped: Array[String] = []
	for st in written:
		if not NPCScript.QUEST_STATE_BUCKETS.has(st):
			unmapped.append(st)
	assert_eq(unmapped, ([] as Array[String]),
		"QuestSystem writes these states and no bucket answers them: %s" % ", ".join(unmapped))


func test_the_map_does_not_answer_states_nobody_writes() -> void:
	## The other direction, and it is the exact shape of the bug: a key for a state
	## that is never written reads as coverage and is dead.
	var written: Array[String] = _states_questsystem_writes()
	var ghosts: Array[String] = []
	for key in NPCScript.QUEST_STATE_BUCKETS:
		var k: String = str(key)
		if k == "":
			continue  # the absent quest — no writer, by definition
		if not written.has(k):
			ghosts.append(k)
	assert_eq(ghosts, ([] as Array[String]),
		"buckets keyed on states QuestSystem never writes: %s" % ", ".join(ghosts))


## Every `"state"` literal QuestSystem assigns, in either form it uses.
func _states_questsystem_writes() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(QUEST_SRC)
	var out: Array[String] = []
	for pattern in ["{\"state\": \"", "[\"state\"] = \""]:
		var at: int = src.find(pattern)
		while at != -1:
			var start: int = at + pattern.length()
			var close: int = src.find("\"", start)
			if close > start:
				var val: String = src.substr(start, close - start)
				if not out.has(val):
					out.append(val)
			at = src.find(pattern, at + 1)
	return out
