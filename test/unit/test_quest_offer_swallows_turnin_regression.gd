extends GutTest

## Regression: an OFFERABLE quest at an NPC swallowed every other quest's
## business at that same NPC. run_giver_dialogue's offer branch `return`ed
## before the only notify_talk on the path, and OverworldNPC calls
## notify_talk solely in its `elif not has_giver` arm — so no code ever
## progressed the other quest. Live W2 pairs hit by this:
##   madame_orrery_w2 — gives world2_fine_print, is world2_wrong_blue's FINAL turn-in
##   mail_carrier_w2  — gives world2_relocated, is world2_forms_in_triplicate's FINAL turn-in
##   surplus_teen_w2  — gives world2_configuration_pending, is world2_wrong_blue step 2
## Declining the offer re-offers forever, so the other quest never turned in.

const SHARED_NPC := "zz_shared_giver_fixture"
const OFFER_QID := "zz_fixture_offerable"
const TURNIN_QID := "zz_fixture_turnin"

var _qs: Node


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	GameState.quests.clear()
	_qs._quests[OFFER_QID] = {
		"id": OFFER_QID,
		"title": "Fixture Offer",
		"giver": {"npc_id": SHARED_NPC},
		"dialogue": {},
		"objectives": [{"step": 1, "type": "talk", "target_npc": SHARED_NPC}],
	}
	_qs._quests[TURNIN_QID] = {
		"id": TURNIN_QID,
		"title": "Fixture Turn-In",
		"giver": {"npc_id": "zz_other_giver_fixture"},
		"dialogue": {},
		"objectives": [
			{"step": 1, "type": "talk", "target_npc": "zz_other_giver_fixture"},
			{"step": 2, "type": "talk", "target_npc": SHARED_NPC},
		],
	}


func after_each() -> void:
	_qs._quests.erase(OFFER_QID)
	_qs._quests.erase(TURNIN_QID)
	GameState.quests.clear()


## The shared NPC owns an offer AND another quest's final talk step.
func _arm() -> Node2D:
	GameState.quests[TURNIN_QID] = {"state": "active", "objective_index": 1}
	assert_true(_qs.is_offerable(OFFER_QID), "fixture offer must be offerable")
	assert_eq(_qs.get_state(TURNIN_QID), "active", "fixture turn-in must be active")
	var npc := Node2D.new()
	npc.set("npc_name", "Fixture NPC")
	add_child_autofree(npc)
	return npc


func test_notify_talk_alone_would_turn_it_in() -> void:
	# Positive control: the engine CAN complete this the moment notify_talk runs.
	var npc := _arm()
	assert_eq(_qs.notify_talk(SHARED_NPC), TURNIN_QID, "notify_talk completes the final step")
	assert_eq(_qs.get_state(TURNIN_QID), "complete")
	assert_not_null(npc)


func test_declining_the_offer_still_turns_in_the_other_quest() -> void:
	var npc := _arm()
	# Fire-and-forget: run_giver_dialogue awaits the accept/decline menu.
	_qs.run_giver_dialogue(SHARED_NPC, npc)
	var menu: Node = null
	for _i in range(30):
		await get_tree().process_frame
		menu = get_tree().root.find_child("QuestOfferChoice", true, false)
		if menu != null:
			break
	assert_not_null(menu, "the offer prompt must appear")
	if menu != null:
		menu.dismiss()  # decline
	for _i in range(10):
		await get_tree().process_frame
	assert_eq(_qs.get_state(OFFER_QID), "", "declined offer stays unstarted")
	assert_eq(_qs.get_state(TURNIN_QID), "complete",
		"the other quest's final talk must still land — pre-fix the offer branch returned before notify_talk")
