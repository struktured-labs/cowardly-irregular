extends GutTest

## Milo v2 (msg 2600) — LLM-off quest-state bucketed idle picker.
##
## When LLMService is unavailable (or the NPC isn't LLM-opt-in), OverworldNPC's
## static path plays dialogue_lines. This test covers the cycle-3 enhancement:
## for LLM-opt-in NPCs whose persona has a quest_state_lines block, the static
## path OVERRIDES dialogue_lines with the bucket matching this NPC's quest
## state — so LLM-off Milo speaks his quest-aware idle lines (pre_task_1 /
## in_progress / post_quest) instead of his generic fallbacks.
##
## Bucket mapping (QuestSystem state → persona bucket):
##   ""            → pre_task_1
##   "active"      → in_progress
##   "completed"   → post_quest
##   "turned_in"   → post_quest
##   (else)        → "" (no override — keep dialogue_lines)
##
## Money-pick weighting: the *_money_pick_index sibling picks the line for the
## FIRST visit to a fresh bucket (per-bucket visit counter). Subsequent visits
## rotate through the bucket. Bucket transitions restart the money-pick rotation.


const NPC_SCRIPT_PATH: String = "res://src/exploration/OverworldNPC.gd"
const PERSONA_JSON: String = "res://data/cutscenes/npc_showcase_personas.json"


## Stub QuestSystem covering just the methods the picker consumes.
## _quests is intentionally untyped Array — assigning a generic array literal to
## a typed Array[String] field silently fails in Godot 4 (documented pitfall).
class StubQuestSys:
	extends Node
	var _quests: Array = []
	var _giver_map: Dictionary = {}
	var _state_map: Dictionary = {}
	var last_state_lookup: String = ""

	func get_all_ids() -> Array:
		return _quests

	func get_quest(qid: String) -> Dictionary:
		return {"giver": {"npc_id": str(_giver_map.get(qid, ""))}}

	func get_state(qid: String) -> String:
		last_state_lookup = qid
		return str(_state_map.get(qid, ""))


## Minimal-surface stub proving the defensive has_method guards work.
class StubQuestSysNoMethods:
	extends Node


func _make_npc() -> Node:
	var NPC: Script = load(NPC_SCRIPT_PATH)
	var npc = NPC.new()
	npc.dynamic = true
	npc.persona = "milo"
	npc.npc_id = "milo"
	npc.npc_name = "Scholar Milo"
	add_child_autofree(npc)
	return npc


func _make_quest_sys(giver_npc_id: String, state: String) -> Node:
	var stub = StubQuestSys.new()
	stub._quests = ["chapter_three"]
	stub._giver_map["chapter_three"] = giver_npc_id
	stub._state_map["chapter_three"] = state
	add_child_autofree(stub)
	return stub


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


# ── Persona-cache load surface

func test_setup_persona_data_populates_quest_state_lines_for_milo() -> void:
	# _make_npc() adds the NPC to the tree — _ready fires _setup_persona_data
	# (gated on dynamic=true, satisfied by _make_npc).
	var npc = _make_npc()
	# Give the cache a beat to load — _setup_persona_data is sync but persona
	# lookup keys off npc_name, so verify it landed for Milo.
	assert_eq(npc._persona_quest_state_lines.size(), 3,
		"Milo's persona must load 3 buckets (pre_task_1, in_progress, post_quest)")
	for bucket in ["pre_task_1", "in_progress", "post_quest"]:
		assert_true(npc._persona_quest_state_lines.has(bucket),
			"bucket '%s' must be present" % bucket)
		assert_eq(int(npc._persona_quest_state_lines[bucket].size()), 5,
			"bucket '%s' must contain 5 lines per cowir-story contract (msg 2603)" % bucket)


func test_money_pick_indices_load_from_json_sibling_keys() -> void:
	var npc = _make_npc()
	assert_eq(int(npc._persona_quest_state_money_picks.get("pre_task_1", -1)), 4,
		"pre_task_1_money_pick_index (=4) must load, matching cowir-story's per-bucket weight-boost target")
	assert_eq(int(npc._persona_quest_state_money_picks.get("in_progress", -1)), 1,
		"in_progress_money_pick_index (=1) must load")
	assert_eq(int(npc._persona_quest_state_money_picks.get("post_quest", -1)), 1,
		"post_quest_money_pick_index (=1) must load")


func test_comment_key_is_skipped_not_treated_as_bucket() -> void:
	var npc = _make_npc()
	assert_false(npc._persona_quest_state_lines.has("_comment"),
		"_comment key from the JSON metadata must be filtered out of bucket cache — it's documentation, not a bucket")


func test_persona_without_quest_state_lines_does_not_crash() -> void:
	# Theron has no quest_state_lines block; loader must silently no-op.
	var NPC: Script = load(NPC_SCRIPT_PATH)
	var npc = NPC.new()
	npc.dynamic = true
	npc.persona = "elder"
	npc.npc_id = "theron"
	npc.npc_name = "Elder Theron"
	add_child_autofree(npc)
	assert_eq(int(npc._persona_quest_state_lines.size()), 0,
		"Theron has no quest_state_lines in JSON — cache must be empty, not crash")
	assert_eq(int(npc._persona_quest_state_money_picks.size()), 0,
		"no money-pick indices when the bucket block is absent")


# ── Bucket resolution

func test_bucket_null_quest_sys_returns_empty() -> void:
	var npc = _make_npc()
	assert_eq(npc._quest_state_bucket_for_npc(null), "",
		"null QuestSystem must be handled defensively (returns \"\", no override)")


func test_bucket_missing_methods_returns_empty() -> void:
	var npc = _make_npc()
	var stub = StubQuestSysNoMethods.new()
	add_child_autofree(stub)
	assert_eq(npc._quest_state_bucket_for_npc(stub), "",
		"QuestSystem lacking get_all_ids/get_quest/get_state must fall back to no override, not crash")


func test_bucket_npc_gives_no_quest_returns_empty() -> void:
	var npc = _make_npc()
	var stub = _make_quest_sys("someone_else", "active")
	assert_eq(npc._quest_state_bucket_for_npc(stub), "",
		"NPC not the giver of any quest → no bucket override — generic dialogue_lines rule")


func test_bucket_state_empty_maps_to_pre_task_1() -> void:
	var npc = _make_npc()
	var stub = _make_quest_sys("milo", "")
	assert_eq(npc._quest_state_bucket_for_npc(stub), "pre_task_1",
		"quest state \"\" (unstarted/offerable) → pre_task_1 bucket")


func test_bucket_state_active_maps_to_in_progress() -> void:
	var npc = _make_npc()
	var stub = _make_quest_sys("milo", "active")
	assert_eq(npc._quest_state_bucket_for_npc(stub), "in_progress",
		"quest state \"active\" → in_progress bucket")


func test_bucket_state_completed_maps_to_post_quest() -> void:
	var npc = _make_npc()
	var stub = _make_quest_sys("milo", "completed")
	assert_eq(npc._quest_state_bucket_for_npc(stub), "post_quest",
		"quest state \"completed\" → post_quest bucket")


func test_bucket_state_turned_in_maps_to_post_quest() -> void:
	var npc = _make_npc()
	var stub = _make_quest_sys("milo", "turned_in")
	assert_eq(npc._quest_state_bucket_for_npc(stub), "post_quest",
		"quest state \"turned_in\" → post_quest bucket (parity with completed)")


func test_bucket_unknown_state_returns_empty() -> void:
	var npc = _make_npc()
	var stub = _make_quest_sys("milo", "some_future_state_we_dont_know")
	assert_eq(npc._quest_state_bucket_for_npc(stub), "",
		"unknown quest state → no override — safer to fall back to dialogue_lines than to guess a bucket")


# ── Rotation + money-pick

func test_rotation_empty_bucket_key_returns_empty() -> void:
	var npc = _make_npc()
	assert_eq(int(npc._quest_state_bucket_rotation("").size()), 0,
		"bucket \"\" (no override) must return [] — signals static-path to use dialogue_lines")


func test_rotation_missing_bucket_returns_empty() -> void:
	var npc = _make_npc()
	assert_eq(int(npc._quest_state_bucket_rotation("nonexistent_bucket").size()), 0,
		"bucket not in persona → [] — signals static-path to use dialogue_lines")


func test_rotation_first_visit_starts_with_money_pick_for_pre_task_1() -> void:
	# Milo's pre_task_1_money_pick_index = 4 (index 4, the "sacrament" line).
	var npc = _make_npc()
	var rotated: Array = npc._quest_state_bucket_rotation("pre_task_1")
	assert_eq(int(rotated.size()), 5, "rotation preserves the 5-line bucket size")
	var money_line: String = str(npc._persona_quest_state_lines["pre_task_1"][4])
	assert_eq(str(rotated[0]), money_line,
		"first visit to pre_task_1 (visit_count 0) must start with money-pick index 4 — the weight-boost target lands first")


func test_rotation_second_visit_advances_past_money_pick() -> void:
	# Simulate a completed first visit by bumping the per-bucket counter.
	var npc = _make_npc()
	npc._quest_state_bucket_visits["pre_task_1"] = 1
	var rotated: Array = npc._quest_state_bucket_rotation("pre_task_1")
	# money_pick=4, count=1 → start = (4+1) % 5 = 0
	var expected_first: String = str(npc._persona_quest_state_lines["pre_task_1"][0])
	assert_eq(str(rotated[0]), expected_first,
		"visit_count 1 with money_pick 4 rotates start to (4+1)%5=0 — advances past money-pick to line 0")


func test_rotation_in_progress_money_pick_lands_first() -> void:
	# in_progress_money_pick_index = 1 (index 1, the "if you tell me how" line).
	var npc = _make_npc()
	var rotated: Array = npc._quest_state_bucket_rotation("in_progress")
	var money_line: String = str(npc._persona_quest_state_lines["in_progress"][1])
	assert_eq(str(rotated[0]), money_line,
		"in_progress first visit lands on money-pick index 1 — the 'if you tell me how' paradox line")


func test_rotation_missing_money_pick_defaults_to_zero() -> void:
	# Manually seed a bucket without a money-pick entry (defensive path).
	var npc = _make_npc()
	npc._persona_quest_state_lines["synthetic_bucket"] = ["A", "B", "C"]
	# no money-pick set for synthetic_bucket
	var rotated: Array = npc._quest_state_bucket_rotation("synthetic_bucket")
	assert_eq(str(rotated[0]), "A",
		"missing money-pick index falls back to 0 — first line lands first, matches old dialogue_lines default")


# ── Source-inspection regression pins

func test_source_static_path_consults_bucket_rotation() -> void:
	var src = _read(NPC_SCRIPT_PATH)
	assert_true(src.find("_quest_state_bucket_rotation(") != -1,
		"static path must call _quest_state_bucket_rotation — regression: silent revert to dialogue_lines-only")
	assert_true(src.find("_quest_state_bucket_for_npc(") != -1,
		"static path must resolve the bucket via _quest_state_bucket_for_npc")


func test_source_loader_captures_quest_state_lines_block() -> void:
	var src = _read(NPC_SCRIPT_PATH)
	assert_true(src.find("quest_state_lines") != -1,
		"_setup_persona_data must read the JSON's quest_state_lines block")
	assert_true(src.find("_money_pick_index") != -1,
		"loader must recognize the *_money_pick_index sibling keys per cowir-story JSON schema")


func test_persona_json_still_carries_milo_quest_state_lines() -> void:
	# Guard: if the JSON regresses on merge, this test flags immediately.
	var text = _read(PERSONA_JSON)
	assert_true(text.find("quest_state_lines") != -1,
		"npc_showcase_personas.json must retain Milo's quest_state_lines block (cowir-story commit 4b57188f)")
	assert_true(text.find("pre_task_1") != -1 and text.find("in_progress") != -1 and text.find("post_quest") != -1,
		"all three v2 buckets must be present in the persona JSON")
