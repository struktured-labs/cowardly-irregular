extends GutTest

## Hold-to-skip only walked top-level set_flag steps. The completion flag
## still landed, so the scene never replayed, and everything else the
## scene would have committed was gone:
##   world1_orrery — fool_card, then the lead_job arm (Unwritten Chord
##     for a Bard, luck charm otherwise), then world1_orrery_complete
##   world1_bram_shield — grant_item untested_shield, then its flag
##   world1_prologue — spotlight_lead_<job> lives inside a lead_job branch
##   world6_orrery — the choice's first answer, orrery_pendant, and the
##     fool_card → wild_card swap, then the completion flags
## A skip during the opening dialogue, or during the dialogue inside the
## reward arm, has to commit those. An abort must not.

const STUB := "res://test/unit/_test_game_loop_stub.gd"

const PROBE_COMPLETE := "skip_probe_scene_complete"
const PROBE_LEAD := "skip_probe_lead_bard"
const PROBE_LEAD_OTHER := "skip_probe_lead_fighter"
const PROBE_CHOICE := "skip_probe_choice_kind"
const PROBE_CHOICE_OTHER := "skip_probe_choice_rest"

var _director: Node = null
var _stub: Node = null
var _leader: Combatant = null
var _appended_host: Node = null
var _prev_job = null
var _prev_leader_index: int = 0
var _prev_constants: Dictionary = {}
var _prev_story: Dictionary = {}
var _prev_counts: Dictionary = {}


func before_each() -> void:
	_prev_leader_index = int(GameState.party_leader_index)
	_prev_constants = GameState.game_constants.duplicate(true)
	_prev_story = GameState.story_flags.duplicate(true) if GameState.story_flags is Dictionary else {}
	_director = CutsceneDirector.new()
	add_child_autofree(_director)
	_mount_bard_leader()


func after_each() -> void:
	_restore_items()
	if _stub != null and is_instance_valid(_stub):
		_stub.free()
	elif _appended_host != null and is_instance_valid(_appended_host) and _leader != null and is_instance_valid(_leader):
		if "party" in _appended_host:
			_appended_host.party.erase(_leader)
		_leader.free()
	_stub = null
	_leader = null
	_appended_host = null
	GameState.party_leader_index = _prev_leader_index
	GameState.game_constants = _prev_constants
	GameState.story_flags = _prev_story


func _mount_bard_leader() -> void:
	var job: Dictionary = JobSystem.get_job("bard")
	var existing := get_tree().root.get_node_or_null("GameLoop")
	if existing != null and "party" in existing and existing.party.size() > 0:
		_leader = existing.party[0]
		_prev_job = _leader.job
		_leader.job = job
		_appended_host = null
	else:
		var host: Node = existing
		if host == null:
			host = load(STUB).new()
			host.name = "GameLoop"
			get_tree().root.add_child(host)
			_stub = host
		else:
			_appended_host = host
		_leader = Combatant.new()
		_leader.combatant_name = "Skip Probe"
		_leader.job = job
		host.add_child(_leader)
		host.party.append(_leader)
	GameState.party_leader_index = 0
	for item_id in ["fool_card", "wild_card", "unwritten_chord", "luck_charm_minor", "untested_shield", "potion", "ether"]:
		_prev_counts[item_id] = _leader.get_item_count(item_id)


func _restore_items() -> void:
	if _leader == null or not is_instance_valid(_leader):
		return
	if _prev_job != null:
		_leader.job = _prev_job
	for item_id in _prev_counts:
		var extra: int = _leader.get_item_count(item_id) - int(_prev_counts[item_id])
		if extra > 0 and _leader.has_method("remove_item"):
			_leader.remove_item(item_id, extra)


func _count(item_id: String) -> int:
	return _leader.get_item_count(item_id) - int(_prev_counts.get(item_id, 0))


func _flag(name: String) -> bool:
	return bool(GameState.game_constants.get("cutscene_flag_" + name, false))


## The tail of a scene, as the skip walker sees it once the opening dialogue has been dismissed.
func _reward_tail() -> Array:
	return [
		{"type": "dialogue", "lines": [{"speaker": "Orrery", "text": "In exchange — take this."}]},
		{"type": "give_item", "item": "fool_card", "quantity": 1},
		{"type": "branch", "condition": "lead_job", "cases": {
			"bard": [
				{"type": "dialogue", "lines": [{"speaker": "Orrery", "text": "Play me something that doesn't exist yet."}]},
				{"type": "give_item", "item": "unwritten_chord", "quantity": 1},
			],
			"default": [
				{"type": "give_item", "item": "luck_charm_minor", "quantity": 1},
			],
		}},
		{"type": "grant_item", "item": "untested_shield", "name": "The Untested Shield", "description": "Bram's gift."},
		{"type": "choice", "prompt": "Her voice doesn't expect an answer.", "options": [
			{"text": "I don't know. But I don't think they went away.", "flag": PROBE_CHOICE},
			{"text": "Maybe they went to be where they could finally stop too.", "flag": PROBE_CHOICE_OTHER},
		]},
		{"type": "update_item", "item": "fool_card", "new_id": "wild_card"},
		{"type": "set_flag", "flag": PROBE_COMPLETE, "value": true},
	]


func test_skipping_the_opening_still_grants_the_card_the_chord_and_the_shield() -> void:
	assert_eq(str(_leader.job.get("id", "")), "bard",
		"control: the live lead is a Bard, so the Orrery arm under test is the chord and not the charm")
	_director._skipping = true
	_director._apply_remaining_set_flag_steps(_reward_tail(), 1)
	assert_eq(_count("wild_card"), 1,
		"skipping the Orrery scene must still hand over the Fool Card — world6 then turns that card into the Wild Card")
	assert_eq(_count("fool_card"), 0,
		"the same skip must still run the later update_item, so the Fool Card does not sit in the bag beside the Wild Card")
	assert_eq(_count("unwritten_chord"), 1,
		"a Bard who skips the Orrery scene must still receive the Unwritten Chord from the lead_job arm")
	assert_eq(_count("luck_charm_minor"), 0,
		"the default charm arm must not also run — the skip takes the same one arm a full play would")
	assert_eq(_count("untested_shield"), 1,
		"skipping Bram's shield scene must still grant The Untested Shield")
	assert_true(_flag(PROBE_CHOICE),
		"a choice the skip never reached still answers with the first option, the same answer a skip on the menu gives")
	assert_false(_flag(PROBE_CHOICE_OTHER),
		"the other answers must stay unset")
	assert_true(_flag(PROBE_COMPLETE),
		"the completion flag still lands, which is why a missed reward can never be replayed")
	assert_true(GameState.get_story_flag(PROBE_COMPLETE),
		"the story-flag mirror of that completion flag has to land too — Quest Log reads the bare name")


func test_skipping_the_prologue_still_records_who_led() -> void:
	var steps: Array = [
		{"type": "narration", "text": "So five people showed up."},
		{"type": "branch", "condition": "lead_job", "cases": {
			"bard": [{"type": "set_flag", "flag": PROBE_LEAD, "value": true}],
			"fighter": [{"type": "set_flag", "flag": PROBE_LEAD_OTHER, "value": true}],
		}},
		{"type": "set_flag", "flag": PROBE_COMPLETE, "value": true},
	]
	_director._skipping = true
	_director._apply_remaining_set_flag_steps(steps, 1)
	assert_true(_flag(PROBE_LEAD),
		"skipping the prologue must still write spotlight_lead_<job> — that flag is what lets the lead act without winning their duel first")
	assert_false(_flag(PROBE_LEAD_OTHER),
		"a Bard lead must not also record the fighter arm")
	assert_true(_flag(PROBE_COMPLETE),
		"prologue_complete still lands on the skip, so the prologue will not play again to repair the missing lead flag")


func test_skipping_inside_the_reward_arm_still_grants_what_it_had_not_reached() -> void:
	_director._skipping = true
	await _director._step_branch({
		"type": "branch",
		"condition": "lead_job",
		"cases": {
			"bard": [
				{"type": "dialogue", "lines": [{"speaker": "Orrery", "text": "Play me something that doesn't exist yet."}]},
				{"type": "give_item", "item": "unwritten_chord", "quantity": 1},
			],
			"default": [
				{"type": "give_item", "item": "luck_charm_minor", "quantity": 1},
			],
		},
	})
	assert_eq(_count("unwritten_chord"), 1,
		"holding skip during the Bard's verse must still grant the chord that comes after that verse")
	assert_eq(_count("luck_charm_minor"), 0,
		"breaking out of the arm must not fall through into the default reward")


func test_an_item_already_given_is_not_given_again() -> void:
	var steps: Array = [
		{"type": "give_item", "item": "potion", "quantity": 1},
		{"type": "give_item", "item": "ether", "quantity": 1},
	]
	_leader.add_item("potion", 1)
	_director._skipping = true
	_director._apply_remaining_set_flag_steps(steps, 1)
	assert_eq(_count("ether"), 1, "the reward still ahead of the skip must be granted")
	assert_eq(_count("potion"), 1, "the reward the scene already handed over must not be handed over a second time")


func test_an_abort_does_not_grant_the_reward_the_arm_had_not_reached() -> void:
	# Both flags: a skip that is also an abort breaks out of the arm, and the flush must not run.
	_director._aborted = true
	_director._skipping = true
	await _director._step_branch({
		"type": "branch",
		"condition": "lead_job",
		"cases": {
			"bard": [
				{"type": "give_item", "item": "unwritten_chord", "quantity": 1},
			],
		},
	})
	assert_eq(_count("unwritten_chord"), 0,
		"an aborted scene must stay replayable and must not commit the rewards it never reached")
