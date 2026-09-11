extends GutTest

## An NPC has TWO id derivations, and they do not agree. Today that is invisible; one authoring
## flag makes it a silent reward failure.
##
##   OverworldNPC.get_npc_id()            name.to_lower().replace(" ","_").replace("'","").replace("-","_")
##   ConversationRewards.resolve_npc_id() name.to_lower().replace(" ","_").strip_edges()
##
## Both prefer an explicit `npc_id`, so they diverge only for an NPC that declares none and whose
## NAME carries an apostrophe or a hyphen. Measured live 2026-09-11 across 66 maps / 212 NPCs:
## EIGHT diverge -- ADMIN-01, DEBUG-7, FIREWALL-ALPHA, SUDO-1, User-7734, ARIA-9, Half-Grown Figure,
## Maint. Unit M-07 -- keyed `admin_01` by the quest system and `admin-01` by the reward ledger.
##
## 🔑 IT IS UNREACHABLE TODAY, AND THAT IS A MEASUREMENT, NOT AN ASSUMPTION. `resolve_npc_id` is
## called on exactly one path, `_run_dynamic_conversation`, gated on `dynamic and persona != ""`.
## Three NPCs in the game pass that gate -- Elder Theron, Scholar Milo, Guard Boris -- and all three
## declare an explicit npc_id, so both derivations return it and agree. All eight divergent NPCs are
## LLM=false. The two id spaces are also disjoint stores: quest ids go to QuestSystem, reward ids to
## the `llm_conversation_reward_claims` ledger, and nothing reads across.
##
## ⚠️ SO THIS IS A TRIPWIRE ON THE PRECONDITION, NOT A FIX. The bug arrives the day someone sets
## `dynamic = true` and a persona on an NPC whose name has a hyphen -- a one-line authoring change,
## in this lane, with no other symptom: the reward table has a `default` entry, so the payout still
## resolves, it is the CLAIM LEDGER that keys under the other spelling. @cowir-autogrind flagged the
## restatement family; @cowir-ai narrowed the live divergence to this one site.

const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")
const ConversationRewards := preload("res://src/llm/ConversationRewards.gd")

const DIRS := [
	"res://src/maps/villages", "res://src/maps/interiors",
	"res://src/maps/dungeons", "res://src/exploration",
]
## Named, not counted: a total can stay green with the walk half dead.
const KNOWN_LLM_NPCS := ["Elder Theron", "Scholar Milo", "Guard Boris"]


func _walk(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c.has_method("get_npc_id"):
			acc.append(c)
		_walk(c, acc)


func _reward_id(npc: Node) -> String:
	var authored = npc.get("npc_id")
	return ConversationRewards.resolve_npc_id(
		str(authored) if authored != null else "", str(npc.get("npc_name")))


func test_no_npc_on_the_reward_path_answers_to_two_ids() -> void:
	var two_ids: Array = []
	var divergent_anywhere: Array = []
	var llm_names: Array = []
	var npcs_seen := 0
	var maps_built := 0

	for dir_path in DIRS:
		for path in MapScripts.maps_in(dir_path):
			var vp := SubViewport.new()
			vp.size = Vector2i(64, 64)
			vp.world_2d = World2D.new()
			add_child_autofree(vp)
			var map_node = load(path).new()
			vp.add_child(map_node)
			await get_tree().physics_frame
			await get_tree().process_frame
			maps_built += 1

			var npcs: Array = []
			_walk(map_node, npcs)
			for npc in npcs:
				npcs_seen += 1
				var quest_id: String = str(npc.get_npc_id())
				var reward_id: String = _reward_id(npc)
				if quest_id != reward_id:
					divergent_anywhere.append("%s '%s' %s vs %s" % [path.get_file(), str(npc.get("npc_name")), quest_id, reward_id])
				var dyn = npc.get("dynamic")
				var persona = npc.get("persona")
				if not (dyn != null and bool(dyn) and persona != null and str(persona) != ""):
					continue
				llm_names.append(str(npc.get("npc_name")))
				if quest_id != reward_id:
					two_ids.append("%s: '%s' is '%s' to quests and '%s' to the reward ledger" % [
						path.get_file(), str(npc.get("npc_name")), quest_id, reward_id])

	assert_gt(maps_built, 50, "CONTROL: only %d maps built — the walk is broken" % maps_built)
	assert_gt(npcs_seen, 150, "CONTROL: only %d NPCs found — the zero below would be free" % npcs_seen)
	for who in KNOWN_LLM_NPCS:
		assert_true(who in llm_names,
			"CONTROL: %s is an LLM showcase NPC and the walk did not reach them; found %s" % [who, str(llm_names)])

	## This guard exists BECAUSE the two derivations disagree. If they ever stop, it is dead weight
	## and this arm says so instead of quietly passing forever.
	assert_gt(divergent_anywhere.size(), 0,
		"the two id derivations now agree everywhere — unify them for real and DELETE this test, it guards nothing")

	assert_eq(two_ids, [],
		("an NPC on the LLM reward path answers to two different ids: %s\n" +
		"The payout still resolves (the table has a `default`), but the CLAIM LEDGER keys under the\n" +
		"reward spelling while everything else uses the quest one — so the claim never sticks.\n" +
		"FIX: give the NPC an explicit `npc_id`, which both derivations return unchanged.") % str(two_ids))
