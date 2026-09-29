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
	gs.game_constants["cutscene_flag_chapter5_complete"] = true
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
	var locking: int = 0
	for id in PARTY_CHAT.REGISTRY:
		if s[0].is_available(id) and _tempo_flag() in PARTY_CHAT.REGISTRY[id].get("lock", []):
			locking += 1
	assert_gt(locking, 0, "CONTROL: some offered chat locks on the Tempo")
	s[1].set_story_flag(_tempo_flag())
	assert_false(s[0].is_available(LOCKED), "the chat stages the Tempo alive; it must not play after the Tempo is beaten")
	assert_eq(s[0].available_count(), before - locking, "the menu's count must drop by exactly the chats that lock on the Tempo")
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
	var dd := DirAccess.open("res://src/maps/dungeons")
	for f in dd.get_files():
		src += FileAccess.get_file_as_string("res://src/maps/dungeons/" + f)
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


func test_mordaines_chats_close_when_she_falls() -> void:
	var s: Array = _system()
	var mordaine_chats := ["world1_chapter5", "world1_chapter7", "world1_chapter8", "world1_guidance_capital"]
	for id in mordaine_chats:
		assert_true(s[0].is_available(id), "CONTROL: %s is offered while Mordaine rules" % id)
	## DragonCave writes a dungeon boss's defeat exactly like this (boss_flag_key -> dungeon_flags).
	s[1].game_constants["dungeon_flags"] = {"world1_mordaine_defeated": true}
	for id in mordaine_chats:
		assert_false(s[0].is_available(id), "%s presents Mordaine as ruling; it must close once she is beaten" % id)


## W1 boss -> the flag its defeat writes. A chat that names one must lock on it, unless its unlock already needs that defeat.
const W1_BOSSES := {
	"\\bTempo\\b|calling card": "w1_tempo_defeated",
	"\\bWarden\\b": "w1_warden_defeated",
	"\\bArbiter\\b": "w1_arbiter_defeated",
	"\\bCurator\\b": "w1_curator_defeated",
	"(?i)\\bmordaine\\b|\\bchancellor\\b": "world1_mordaine_defeated",
}


func _chat_text(id: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % id))
	var out: Array = []
	_texts(parsed, out)
	return " ".join(out)


func _texts(v: Variant, out: Array) -> void:
	if v is Dictionary:
		if (v as Dictionary).get("text") is String:
			out.append(v["text"])
		for k in v:
			_texts(v[k], out)
	elif v is Array:
		for x in v:
			_texts(x, out)


func test_every_w1_chat_that_names_a_w1_boss_closes_when_that_boss_falls() -> void:
	var missing: Array = []
	var checked := 0
	for id in PARTY_CHAT.REGISTRY:
		var e: Dictionary = PARTY_CHAT.REGISTRY[id]
		if int(e.get("world", 0)) != 1:
			continue
		var text: String = _chat_text(str(id))
		for pat in W1_BOSSES:
			var re := RegEx.new()
			re.compile(pat)
			if re.search(text) == null:
				continue
			checked += 1
			var flag: String = W1_BOSSES[pat]
			if flag in e.get("unlock", []) or flag in e.get("lock", []):
				continue
			missing.append("%s names %s but does not lock on %s" % [id, pat, flag])
	assert_gt(checked, 4, "CONTROL: several W1 chats name a W1 boss, saw %d" % checked)
	assert_eq(missing, [], "a chat that stages a boss alive must close once that boss is beaten: %s" % [missing])
