extends GutTest

## "The Capital" stages the Tempo alive and un-fought, but unlocked after the Rat King while the Eldertree Tempo could already be beaten.

const PARTY_CHAT := preload("res://src/cutscene/PartyChatSystem.gd")
const GAME_STATE := preload("res://src/meta/GameState.gd")
const LOCKED := "world1_chapter7"
const UNLOCK_ONLY := "world1_chapter8"


## A real GameState (not in the tree) so the lock is judged by the real writer and the real reader.
func _system() -> Array:
	var gs = GAME_STATE.new()
	autofree(gs)
	gs.game_constants["cutscene_flag_chapter4_complete"] = true
	var pcs = PARTY_CHAT.new()
	autofree(pcs)
	pcs.game_state_override = gs
	return [pcs, gs]


func _listed(pcs: Object) -> Array:
	return pcs.get_available_chats().map(func(e): return str(e["id"]))


func _tempo_flag() -> String:
	var enc = load("res://src/exploration/MasteriteEncounter.gd").new()
	enc.archetype = "tempo"
	var f: String = enc.defeat_flag()
	enc.free()
	return f


func test_the_capital_is_offered_before_the_tempo_is_beaten() -> void:
	var s: Array = _system()
	assert_true(s[0].is_available(LOCKED), "CONTROL: after the Rat King the chat is offered")
	assert_true(LOCKED in _listed(s[0]), "CONTROL: the menu's list offers it")


func test_the_capital_is_withdrawn_once_the_tempo_is_beaten() -> void:
	var s: Array = _system()
	var before: int = s[0].available_count()
	s[1].set_story_flag(_tempo_flag())
	assert_false(s[0].is_available(LOCKED), "the chat stages the Tempo alive; it must not play after the Tempo is beaten")
	assert_eq(s[0].available_count(), before - 1, "the menu's count must drop by exactly the locked chat")
	assert_false(LOCKED in _listed(s[0]), "the menu's list must not offer it")


func test_a_chat_without_a_lock_is_untouched() -> void:
	var s: Array = _system()
	s[1].set_story_flag(_tempo_flag())
	assert_true(s[0].is_available(UNLOCK_ONLY), "a chat with no lock is unaffected by the Tempo's defeat")


func test_the_lock_is_the_flag_the_defeat_really_writes() -> void:
	assert_eq(_tempo_flag(), "w1_tempo_defeated", "CONTROL: the Masterite writer's own derivation")
	var locks: Array = PARTY_CHAT.REGISTRY[LOCKED].get("lock", [])
	assert_true(_tempo_flag() in locks, "the lock must name the flag the Tempo's defeat writes, or it never fires: %s" % [locks])


func test_every_lock_flag_has_a_writer() -> void:
	var unwritten: Array = []
	var src: String = ""
	for p in ["res://src/GameLoop.gd", "res://src/exploration/MasteriteEncounter.gd"]:
		src += FileAccess.get_file_as_string(p)
	var placed: Array = []
	var d := DirAccess.open("res://src/maps/villages")
	for f in d.get_files():
		var body := FileAccess.get_file_as_string("res://src/maps/villages/" + f)
		var re := RegEx.new()
		re.compile("\\.archetype = \"([a-z_]+)\"")
		for m in re.search_all(body):
			placed.append("w1_%s_defeated" % m.get_string(1))
	assert_gt(placed.size(), 3, "CONTROL: the four W1 Masterite placements must be found")
	for id in PARTY_CHAT.REGISTRY:
		for flag in PARTY_CHAT.REGISTRY[id].get("lock", []):
			if not (str(flag) in placed or src.contains("\"%s\"" % flag)):
				unwritten.append("%s: %s" % [id, flag])
	assert_eq(unwritten, [], "a lock flag nothing writes never locks: %s" % [unwritten])
