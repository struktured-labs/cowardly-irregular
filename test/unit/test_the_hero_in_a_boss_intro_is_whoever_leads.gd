extends GutTest

## 17 boss intros speak as "Hero:", a name no party member has, and BattleDialogue was never handed the party, so the label read "Hero" every time.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BattleDialogueScript := preload("res://src/ui/BattleDialogue.gd")

var _held_party: Array = []
var _held_leader: int = 0


func before_each() -> void:
	_held_party = GameState.player_party.duplicate(true)
	_held_leader = GameState.party_leader_index


func after_each() -> void:
	GameState.player_party = _held_party
	GameState.party_leader_index = _held_leader


func _member(name: String, job: String, alive: bool = true) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name
	c.job = {"id": job}
	c.is_alive = alive
	autofree(c)
	return c


func _first_line(party: Array, line: String) -> Dictionary:
	var d = BattleDialogueScript.new()
	add_child_autofree(d)
	d.set_party(party)
	d.show_boss_intro("Cave Rat King", [line])
	return d._dialogue_queue[0] if d._dialogue_queue.size() > 0 else {}


func test_the_leader_speaks_the_hero_line() -> void:
	GameState.player_party = [{"name": "Kit", "job_id": "rogue"}]
	GameState.party_leader_index = 0
	var e := _first_line([_member("Fighter", "fighter"), _member("Kit", "rogue")], "Hero: Are you serious?")
	assert_eq(str(e.get("speaker", "")), "Kit", "the label must be the party leader, not a name nobody has")
	assert_eq(str(e.get("theme", "")), "rogue", "the leader's job decides the look")
	assert_eq(str(e.get("text", "")), "Are you serious?", "CONTROL: the line itself is untouched")


func test_a_downed_leader_hands_the_line_to_someone_standing() -> void:
	GameState.player_party = [{"name": "Fighter", "job_id": "fighter"}]
	GameState.party_leader_index = 0
	var e := _first_line([_member("Fighter", "fighter", false), _member("Cleric", "cleric")], "Hero: We came all this way for THIS?")
	assert_eq(str(e.get("speaker", "")), "Cleric", "a KO'd leader cannot speak; the first member standing does")
	assert_eq(str(e.get("theme", "")), "healer", "the Cleric's drawn look")


func test_no_party_keeps_the_old_label() -> void:
	var e := _first_line([], "Hero: Did... did that rat just talk?")
	assert_eq(str(e.get("speaker", "")), "Hero", "with no party to read, degrade to the authored label rather than blank")


func test_a_boss_line_is_not_touched() -> void:
	var e := _first_line([_member("Fighter", "fighter")], "Rat King: Kneel.")
	assert_eq(str(e.get("speaker", "")), "Rat King", "CONTROL: only the Hero speaker is resolved")


func test_the_battle_scene_hands_the_dialogue_its_party() -> void:
	var code: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	assert_true(code.contains("func _show_boss_intro_dialogue"), "CONTROL: BattleScene code must survive comment-stripping")
	var calls: int = code.count("_battle_dialogue.show_boss_intro(")
	var wired: int = code.count("_battle_dialogue.set_party(party_members)")
	assert_gt(calls, 0, "CONTROL: the boss intro call sites must be found")
	assert_eq(wired, calls, "every boss-intro call must hand the dialogue the party first, or the Hero line has nobody to resolve to")


func test_no_cutscene_speaker_is_named_hero() -> void:
	var bad: Array = []
	var d := DirAccess.open("res://data/cutscenes")
	for f in d.get_files():
		if f.ends_with(".json") and FileAccess.get_file_as_string("res://data/cutscenes/" + f).contains("\"speaker\": \"Hero\""):
			bad.append(f)
	assert_eq(bad, [], "cutscenes are not resolved at runtime; name the party member: %s" % [bad])
