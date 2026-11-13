extends GutTest

## main 24221 (struktured's easter egg, 2026-11-11): a save that beat the Rat King before the briefing is conceded the five
## spotlight trials. Elder Theron's talk then offers them as optional sparring until each is won: a won trial leaves the
## menu, a trial whose duelist is gone is not offered, a skip refuses rather than commits, and the farewell plays once.

const GameLoopScript := preload("res://src/GameLoop.gd")
const OFFER := "res://data/cutscenes/world1_theron_sparring_offer.json"
const DONE := "res://data/cutscenes/world1_theron_sparring_done.json"
const SPOTLIGHT := {"cleric": "cleric_ch1", "rogue": "rogue_ch3", "mage": "mage_ch3", "fighter": "fighter_ch2", "bard": "bard_ch7"}
const EGG := "cutscene_flag_rat_king_fell_before_the_briefing"
const ALL := ["cleric", "rogue", "mage", "fighter", "bard"]

var _saved: Dictionary = {}


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _saved


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _choice() -> Dictionary:
	for s in _json(OFFER).get("steps", []):
		if s is Dictionary and str(s.get("type", "")) == "choice":
			return s
	return {}


func _arm(flag: String) -> Array:
	for s in _json(OFFER).get("steps", []):
		if s is Dictionary and str(s.get("type", "")) == "branch" and str(s.get("flag", "")) == flag:
			return s.get("if_true", [])
	return []


func _won(jobs: Array) -> Dictionary:
	var f := {EGG: true}
	for j in jobs:
		f["cutscene_flag_theron_trial_won_" + j] = true
	return f


func test_the_routing_table() -> void:
	assert_eq(str(GameLoopScript.THERON_TRIAL_JOBS), str(ALL), "CONTROL: the five conceded trials")
	assert_eq(GameLoopScript.theron_sparring_scene({}, ALL), "", "a save that heard the briefing gets his ordinary talk")
	assert_eq(GameLoopScript.theron_sparring_scene(_won([]), ALL), GameLoopScript.THERON_SPARRING_OFFER_ID, "nothing won: the offer")
	assert_eq(GameLoopScript.theron_sparring_scene(_won(["cleric", "rogue"]), ALL), GameLoopScript.THERON_SPARRING_OFFER_ID, "some won: still the offer")
	assert_eq(GameLoopScript.theron_sparring_scene(_won(ALL), ALL), GameLoopScript.THERON_SPARRING_DONE_ID, "all won: the farewell")
	var done := _won(ALL)
	done["cutscene_flag_theron_sparring_done"] = true
	assert_eq(GameLoopScript.theron_sparring_scene(done, ALL), "", "the farewell plays once")
	assert_eq(GameLoopScript.theron_sparring_scene(_won(["rogue", "mage", "fighter", "bard"]), ["rogue", "mage"]), "",
		"the one open trial has no living duelist: no offer of a menu with nothing in it")
	assert_eq(GameLoopScript.theron_sparring_scene(_won(["rogue"]), ["cleric"]), GameLoopScript.THERON_SPARRING_OFFER_ID,
		"one open trial with a duelist is enough")


func test_each_trial_is_its_spotlight_duel() -> void:
	var opts: Array = _choice().get("options", [])
	assert_eq(opts.size(), ALL.size() + 1, "CONTROL: five trials and a refusal")
	for job in ALL:
		var arm := _arm("theron_spar_pick_" + job)
		assert_false(arm.is_empty(), "the %s pick has an arm" % job)
		var src: Array = _json("res://data/cutscenes/world1_spotlight_%s.json" % SPOTLIGHT[job]).get("steps", []).filter(
			func(s): return s is Dictionary and str(s.get("type", "")) == "battle")
		assert_eq(src.size(), 1, "CONTROL: the %s spotlight has one duel" % job)
		var types: Array = arm.map(func(s): return str(s.get("type", "")))
		var b := types.find("battle")
		assert_gt(b, -1, "the %s arm fights" % job)
		if b < 0 or src.is_empty():
			continue
		assert_eq(arm[b], src[0], "the %s trial is the spotlight's own battle step, so the rewards are the normal path's" % job)
		var clear := arm.find({"type": "set_flag", "flag": "theron_spar_pick_" + job, "value": false})
		assert_between(clear, 0, b - 1, "the %s pick is cleared BEFORE the fight, so a quit mid-duel cannot replay it on the next talk" % job)
		assert_gt(arm.find({"type": "set_flag", "flag": "theron_trial_won_" + job}), b, "the %s trial is marked won only AFTER the fight" % job)


func test_a_won_or_unrunnable_trial_leaves_the_menu() -> void:
	var opts: Array = _choice().get("options", [])
	var flags := _won(["mage"])
	flags["cutscene_flag_theron_trial_unrunnable_bard"] = true
	var shown: Array = opts.filter(func(o): return not CutsceneDirector.choice_option_hidden_by(o, flags)).map(func(o): return str(o.get("text", "")))
	assert_eq(shown, ["The Cleric's trial", "The Rogue's trial", "The Fighter's trial", "Not today."], "the mage's won trial and the absent bard's are not offered")
	assert_false(CutsceneDirector.choice_option_hidden_by({"unless_flag": "x"}, {}), "an unset flag hides nothing")
	assert_true(CutsceneDirector.choice_option_hidden_by({"unless_flag": "x"}, {"cutscene_flag_x": true}), "one name")
	assert_false(CutsceneDirector.choice_option_hidden_by({"text": "plain"}, {"cutscene_flag_x": true}), "no unless_flag: always shown")


func test_the_director_menu_drops_a_won_trial() -> void:
	var director := CutsceneDirector.new()
	add_child_autofree(director)
	GameState.game_constants["cutscene_flag_theron_trial_won_cleric"] = true
	var shown: Array = director._presented_options(_choice().get("options", [])).map(func(o): return str(o.get("text", "")))
	assert_false(shown.has("The Cleric's trial"), "the director's own filter drops the won trial: %s" % str(shown))
	assert_true(shown.has("The Rogue's trial"), "CONTROL: an unwon trial stays")


func test_a_skip_refuses_rather_than_commits() -> void:
	var presented: Array[Dictionary] = []
	for o in _choice().get("options", []):
		presented.append(o)
	assert_eq(str(CutsceneDirector.skip_answer(presented).get("text", "")), "Not today.",
		"a skipped offer answers the refusal: answering a trial would mark it won without a fight")
	var plain: Array[Dictionary] = [{"text": "a"}, {"text": "b"}]
	assert_eq(str(CutsceneDirector.skip_answer(plain).get("text", "")), "a", "CONTROL: with no skip_answer, the first option shown, as before")


func test_the_farewell_closes_itself() -> void:
	var steps: Array = _json(DONE).get("steps", [])
	assert_true(steps.has({"type": "set_flag", "flag": "theron_sparring_done"}), "the farewell writes the flag the routing reads, so it plays once")
	assert_eq(str(_json(OFFER).get("id", "")), GameLoopScript.THERON_SPARRING_OFFER_ID, "CONTROL: the offer's id is the routed one")
	assert_eq(str(_json(DONE).get("id", "")), GameLoopScript.THERON_SPARRING_DONE_ID, "CONTROL: the farewell's id is the routed one")
