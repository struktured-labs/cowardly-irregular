extends GutTest

## W2 wiring PR-C/D (2026-07-08): community center + Enrichment Annex.
## Pins: interior registration (GameLoop dispatch + INTERIOR_MAP_IDS + village
## doors), quest-fixture placement, the forms chain end-to-end (all 3 step-3
## paths), relocated's multi-path rescue seams, variance step 4 at the desk,
## fine_print's three credential routes incl. the Rogue gap cascade, and the
## cross-quest completion presentation fix in run_giver_dialogue.

const W2_FLAGS := [
	"quest_world2_forms_in_triplicate_notice_read",
	"quest_world2_forms_in_triplicate_backlog_obtained",
	"quest_world2_forms_in_triplicate_complaints_processed",
	"quest_world2_forms_in_triplicate_complete",
	"quest_world2_relocated_annex_found",
	"quest_world2_relocated_kids_freed",
	"quest_world2_relocated_complete",
	"quest_world2_acceptable_variance_flower_examined",
	"quest_world2_acceptable_variance_variance_granted",
	"quest_world2_fine_print_credential_obtained",
	"quest_world2_fine_print_form_obtained",
	"quest_world2_fine_print_rogue_gap_used",
	"cutscene_flag_world2_chapter1_complete",
]

var _qs: Node


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	GameState.quests.clear()
	for f in W2_FLAGS:
		GameState.set_story_flag(f, false)
	GameState.game_constants.erase("relocated_officer_baseline")
	GameState.game_constants.erase("fine_print_mailbox_baseline")


func after_each() -> void:
	before_each()


# ── Registration ──

func test_interiors_registered_in_game_loop() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	for id in ["maple_community_center", "enrichment_annex"]:
		assert_true(src.contains("\"%s\":" % id), "%s has a dispatch arm" % id)
		assert_true(id in _interior_ids_block(src), "%s uses the interior transition" % id)


## INTERIOR_MAP_IDS containment via source (const lives on the GameLoop script).
func _interior_ids_block(src: String) -> String:
	var start := src.find("const INTERIOR_MAP_IDS")
	return src.substr(start, src.find("]", start) - start)


func test_village_doors_and_spawns() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/maps/villages/MapleHeightsVillage.gd")
	for token in ["community_center_exit", "annex_exit",
			"maple_community_center", "enrichment_annex",
			"MissingPackage.gd", "CivicBackDoor.gd"]:
		assert_true(src.contains(token), "Maple Heights wires %s" % token)


func test_interiors_place_quest_fixtures() -> void:
	var cc: String = FileAccess.get_file_as_string("res://src/maps/interiors/MapleCommunityCenterInterior.gd")
	assert_true(cc.contains("BulletinBoard.gd"), "board placed in community center")
	assert_true(cc.contains("CivicFrontDesk.gd"), "desk placed in community center")
	assert_true(cc.contains("front_desk_clerk_w2"), "clerk npc present")
	var annex: String = FileAccess.get_file_as_string("res://src/maps/interiors/EnrichmentAnnexInterior.gd")
	assert_true(annex.contains("AnnexLiberation.gd"), "liberation zone placed in annex")
	for kid in ["annex_kid_1", "annex_kid_6", "annex_compliance_officer"]:
		assert_true(annex.contains(kid), "annex places %s" % kid)


# ── forms_in_triplicate: the full chain ──

func test_forms_full_chain_desk_paths() -> void:
	assert_true(_qs.is_offerable("world2_forms_in_triplicate"))
	_qs.accept("world2_forms_in_triplicate")
	# step 0 is custom notice_read (giver is a board, not a talk NPC)
	assert_eq(_qs.get_objective_index("world2_forms_in_triplicate"), 0)
	GameState.set_story_flag("quest_world2_forms_in_triplicate_notice_read")
	_qs.notify_flag("quest_world2_forms_in_triplicate_notice_read")
	assert_eq(_qs.get_objective_index("world2_forms_in_triplicate"), 1, "notice read → backlog")
	# desk: backlog handout
	GameState.set_story_flag("quest_world2_forms_in_triplicate_backlog_obtained")
	_qs.notify_flag("quest_world2_forms_in_triplicate_backlog_obtained")
	assert_eq(_qs.get_objective_index("world2_forms_in_triplicate"), 2, "backlog → processing")
	# desk path (a)/(b) equivalent: processed flag
	GameState.set_story_flag("quest_world2_forms_in_triplicate_complaints_processed")
	_qs.notify_flag("quest_world2_forms_in_triplicate_complaints_processed")
	assert_eq(_qs.get_objective_index("world2_forms_in_triplicate"), 3, "processed → turn-in")
	# turn-in at the carrier
	var done: String = _qs.notify_talk("mail_carrier_w2")
	assert_eq(done, "world2_forms_in_triplicate", "carrier turn-in completes forms")
	assert_true(GameState.get_story_flag("quest_world2_forms_in_triplicate_complete"))


func test_forms_path_c_carrier_files_and_turns_in_one_talk() -> void:
	_qs.accept("world2_forms_in_triplicate")
	GameState.set_story_flag("quest_world2_forms_in_triplicate_notice_read")
	_qs.notify_flag("quest_world2_forms_in_triplicate_notice_read")
	GameState.set_story_flag("quest_world2_forms_in_triplicate_backlog_obtained")
	_qs.notify_flag("quest_world2_forms_in_triplicate_backlog_obtained")
	# ONE talk to the carrier: emitter fires processing, then the talk pass
	# satisfies the now-unlocked final step — file + turn-in, one conversation.
	var done: String = _qs.notify_talk("mail_carrier_w2")
	assert_true(GameState.get_story_flag("quest_world2_forms_in_triplicate_complaints_processed"),
		"path (c): the carrier's dialogue emitter processes the backlog")
	assert_eq(done, "world2_forms_in_triplicate", "same talk completes the quest")


func test_desk_source_covers_all_grants() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/CivicFrontDesk.gd")
	for flag in ["backlog_obtained", "complaints_processed", "variance_granted",
			"credential_obtained", "form_obtained"]:
		assert_true(src.contains(flag), "front desk handles %s" % flag)
	assert_true(src.contains("_at_custom_step"), "grants are current-objective-gated")


# ── relocated: multi-path rescue ──

func test_relocated_annex_entry_emits_found() -> void:
	GameState.set_story_flag("cutscene_flag_world2_chapter1_complete")
	_qs.accept("world2_relocated")
	assert_eq(_qs.get_objective_index("world2_relocated"), 1)
	# AnnexLiberation._on_annex_entered's flag path, simulated
	GameState.set_story_flag("quest_world2_relocated_annex_found")
	_qs.notify_flag("quest_world2_relocated_annex_found")
	assert_eq(_qs.get_objective_index("world2_relocated"), 2, "walking in IS finding it")
	GameState.set_story_flag("quest_world2_relocated_kids_freed")
	_qs.notify_flag("quest_world2_relocated_kids_freed")
	assert_eq(_qs.get_objective_index("world2_relocated"), 3, "rescue → report back")
	var done: String = _qs.notify_talk("mail_carrier_w2")
	assert_eq(done, "world2_relocated")
	assert_true(GameState.get_story_flag("quest_world2_relocated_complete"),
		"mirror flag gates Casper's respawn + wrong_blue")


func test_liberation_source_has_all_three_paths() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/AnnexLiberation.gd")
	assert_true(src.contains("cleric"), "path (a): Cleric-lead walkout")
	assert_true(src.contains("bard"), "path (b): Bard disruption")
	assert_true(src.contains("cranky_lady"), "path (c): fight the officer")
	assert_true(src.contains("relocated_officer_baseline"), "victory via bestiary baseline")
	assert_true(src.contains("_send_kids_home"), "kids leave post-rescue")


# ── acceptable_variance step 4 at the desk ──

func test_variance_completes_at_desk_then_gerald() -> void:
	_qs.accept("world2_acceptable_variance")
	GameState.set_story_flag("quest_world2_acceptable_variance_flower_examined")
	_qs.notify_flag("quest_world2_acceptable_variance_flower_examined")
	_qs.notify_talk("mrs_pemberton_w2")
	assert_eq(_qs.get_objective_index("world2_acceptable_variance"), 3, "at the 44-Omega step")
	GameState.set_story_flag("quest_world2_acceptable_variance_variance_granted")
	_qs.notify_flag("quest_world2_acceptable_variance_variance_granted")
	assert_eq(_qs.get_objective_index("world2_acceptable_variance"), 4)
	var done: String = _qs.notify_talk("gerald_w2")
	assert_eq(done, "world2_acceptable_variance", "Gerald turn-in completes variance")


# ── fine_print: three credential routes ──

func test_fine_print_desk_route() -> void:
	_qs.accept("world2_fine_print")
	assert_eq(_qs.get_objective_index("world2_fine_print"), 1, "accept skips talk-to-giver")
	GameState.set_story_flag("quest_world2_fine_print_credential_obtained")
	_qs.notify_flag("quest_world2_fine_print_credential_obtained")
	GameState.set_story_flag("quest_world2_fine_print_form_obtained")
	_qs.notify_flag("quest_world2_fine_print_form_obtained")
	assert_eq(_qs.get_objective_index("world2_fine_print"), 3, "credential + form → turn-in")
	var done: String = _qs.notify_talk("madame_orrery_w2")
	assert_eq(done, "world2_fine_print")


func test_fine_print_rogue_gap_cascades_both_flags() -> void:
	_qs.accept("world2_fine_print")
	# CivicBackDoor's exact sequence: cred set+notify, then form set+notify.
	GameState.set_story_flag("quest_world2_fine_print_rogue_gap_used")
	GameState.set_story_flag("quest_world2_fine_print_credential_obtained")
	_qs.notify_flag("quest_world2_fine_print_credential_obtained")
	GameState.set_story_flag("quest_world2_fine_print_form_obtained")
	_qs.notify_flag("quest_world2_fine_print_form_obtained")
	assert_eq(_qs.get_objective_index("world2_fine_print"), 3,
		"one back-door interact cascades through both custom steps")


func test_fine_print_mailbox_route_source() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/MissingPackage.gd")
	assert_true(src.contains("rogue_mailbox"), "path A fights the mailbox")
	assert_true(src.contains("fine_print_mailbox_baseline"), "victory via bestiary baseline")
	var back: String = FileAccess.get_file_as_string("res://src/exploration/CivicBackDoor.gd")
	assert_true(back.contains("rogue_gap_used"), "Rogue gap flags its variant")
	assert_true(back.contains("form_obtained"), "Rogue gap grants the form too")


func test_rogue_mailbox_monster_resolves() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var data: Dictionary = JSON.parse_string(raw)
	assert_true(data.has("rogue_mailbox"), "rogue_mailbox exists in monsters.json")
	for ab in data.get("rogue_mailbox", {}).get("abilities", []):
		assert_false(JobSystem.get_ability(ab).is_empty(),
			"rogue_mailbox ability %s resolves" % ab)


# ── cross-quest completion presentation (the silent-forms fix) ──

func test_giver_dialogue_presents_cross_quest_completion() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/quests/QuestSystem.gd")
	var active_branch := src.substr(src.find("var completed_qid := notify_talk"))
	assert_true(active_branch.contains("run_completion_dialogue(completed_qid"),
		"run_giver_dialogue must present a DIFFERENT quest's final talk, not drop it")
