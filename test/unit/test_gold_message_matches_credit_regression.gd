extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## The drop-rate dial lives inside add_gold. Chests, quest rewards, the hearth
## purse, conversation rewards, and Steal/Mug printed the authored amount and
## then credited that amount times the dial. At 2x a chest that said
## "Found 100 Gold!" paid 200. Shop stickers and battle-victory gold were
## already kept consistent with the wallet. These arms are display: the coins
## received stay authored times the dial, and at 1x every sentence is the old one.

const CHEST_GOLD := 100
const QUEST_GOLD := 200
const TALK_GOLD := 40
const STEAL_SEED := 20260925

var _gold: int
var _mult: Variant
var _hearth: bool
var _party: Array
var _reward_summary: String


func before_each() -> void:
	_gold = GameState.party_gold
	_mult = GameState.game_constants.get("gold_multiplier", null)
	_hearth = bool(GameState.get_story_flag(FireplaceSecret.SECRET_FLAG))
	_party = BattleManager.player_party.duplicate()
	_reward_summary = QuestSystem._last_reward_summary


func after_each() -> void:
	randomize()
	GameState.party_gold = _gold
	if _mult == null:
		GameState.game_constants.erase("gold_multiplier")
	else:
		GameState.game_constants["gold_multiplier"] = _mult
	GameState.set_story_flag(FireplaceSecret.SECRET_FLAG, _hearth)
	QuestSystem._last_reward_summary = _reward_summary
	BattleManager.player_party.assign(_alive(_party))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _int_in(text: String, pattern: String) -> int:
	var re := RegEx.new()
	re.compile(pattern)
	var found := re.search(text)
	if found == null:
		return -1
	return int(found.get_string(1))


func _set_dial(dial: float) -> void:
	GameState.game_constants["gold_multiplier"] = dial


func test_a_chest_names_the_coins_it_credits_at_1x_and_2x() -> void:
	var at1 := _open_chest(1.0)
	var at2 := _open_chest(2.0)
	assert_eq(at1["text"], "Found %d Gold!" % CHEST_GOLD,
		"at 1x the chest popup must stay the authored sentence")
	assert_eq(int(at1["paid"]), CHEST_GOLD, "at 1x the wallet receives the authored chest gold")
	assert_eq(int(at1["shown"]), int(at1["paid"]), "at 1x the popup and the wallet must match")
	assert_eq(at2["text"], "Found %d Gold!" % (CHEST_GOLD * 2),
		"at 2x the popup must name the coins the wallet received, not the authored 100")
	assert_eq(int(at2["paid"]), CHEST_GOLD * 2,
		"at 2x the chest must still pay authored times the dial — the line changed, the payout did not")
	assert_eq(int(at2["shown"]), int(at2["paid"]), "at 2x the popup and the wallet must name the same gold")


func test_a_quest_reward_names_the_coins_it_credits_at_1x_and_2x() -> void:
	var at1 := _grant_quest(1.0)
	var at2 := _grant_quest(2.0)
	assert_eq(at1["text"], "Received: %d gold." % QUEST_GOLD,
		"at 1x the quest line must stay the authored sentence")
	assert_eq(int(at1["paid"]), QUEST_GOLD, "at 1x the wallet receives the authored quest gold")
	assert_eq(int(at1["shown"]), int(at1["paid"]), "at 1x the quest line and the wallet must match")
	assert_eq(at2["text"], "Received: %d gold." % (QUEST_GOLD * 2),
		"at 2x the quest line must name the coins credited, not the authored 200")
	assert_eq(int(at2["paid"]), QUEST_GOLD * 2, "at 2x the quest must still pay authored times the dial")
	assert_eq(int(at2["shown"]), int(at2["paid"]), "at 2x the quest line and the wallet must match")


func test_the_hearth_names_the_coins_it_credits_at_1x_and_2x() -> void:
	var at1 := _examine_hearth(1.0)
	var at2 := _examine_hearth(2.0)
	var authored := FireplaceSecret.SECRET_GOLD
	assert_eq(at1["text"], FireplaceSecret.FOUND_LINE + "  (+%d G)" % authored,
		"at 1x the hearth toast must keep its sentence and its authored purse")
	assert_eq(int(at1["paid"]), authored, "at 1x the wallet receives the authored purse")
	assert_eq(int(at1["shown"]), int(at1["paid"]), "at 1x the toast and the wallet must match")
	assert_true(str(at2["text"]).begins_with(FireplaceSecret.FOUND_LINE),
		"the hearth's story sentence must survive; only the purse number moves")
	assert_eq(at2["text"], FireplaceSecret.FOUND_LINE + "  (+%d G)" % (authored * 2),
		"at 2x the toast must name the coins credited")
	assert_eq(int(at2["paid"]), authored * 2, "at 2x the hearth must still pay authored times the dial")
	assert_eq(int(at2["shown"]), int(at2["paid"]), "at 2x the toast and the wallet must match")


func test_a_conversation_reward_names_the_coins_it_credits_at_1x_and_2x() -> void:
	var at1 := _grant_talk(1.0)
	var at2 := _grant_talk(2.0)
	assert_eq(at1["text"], "Take this — %d gold." % TALK_GOLD,
		"at 1x the conversation line must stay the authored sentence")
	assert_eq(int(at1["paid"]), TALK_GOLD, "at 1x the wallet receives the authored conversation gold")
	assert_eq(int(at1["shown"]), int(at1["paid"]), "at 1x the conversation line and the wallet must match")
	assert_eq(at2["text"], "Take this — %d gold." % (TALK_GOLD * 2),
		"at 2x the conversation line must name the coins credited")
	assert_eq(int(at2["paid"]), TALK_GOLD * 2, "at 2x the conversation must still pay authored times the dial")
	assert_eq(int(at2["shown"]), int(at2["paid"]), "at 2x the conversation line and the wallet must match")


func test_steal_and_mug_name_the_coins_they_credit_at_1x_and_2x() -> void:
	var stole1 := _steal(1.0, "stole")
	var stole2 := _steal(2.0, "stole")
	var mug1 := _steal(1.0, "mugs")
	var mug2 := _steal(2.0, "mugs")
	assert_gt(int(stole1["paid"]), 0, "CONTROL: the steal must have paid or the line comparison is about nothing")
	assert_eq(stole1["text"], "[color=yellow]Mira stole %d gold from Goblin![/color]" % int(stole1["shown"]),
		"at 1x the steal log must keep its sentence")
	assert_eq(int(stole1["shown"]), int(stole1["paid"]), "at 1x the steal log and the wallet must match")
	assert_eq(int(stole2["paid"]), int(stole1["paid"]) * 2,
		"at 2x the steal must still pay the 1x take times the dial, not a second time")
	assert_eq(stole2["text"], "[color=yellow]Mira stole %d gold from Goblin![/color]" % int(stole2["paid"]),
		"at 2x the steal log must name the coins credited")
	assert_eq(int(stole2["shown"]), int(stole2["paid"]), "at 2x the steal log and the wallet must match")
	assert_eq(int(mug1["paid"]), int(stole1["paid"]),
		"CONTROL: the same seed must roll the same purse for Mug as for Steal")
	assert_eq(mug1["text"], "[color=yellow]Mira mugs %d gold from Goblin![/color]" % int(mug1["shown"]),
		"at 1x the mug log must keep its sentence")
	assert_eq(int(mug1["shown"]), int(mug1["paid"]), "at 1x the mug log and the wallet must match")
	assert_eq(int(mug2["paid"]), int(mug1["paid"]) * 2, "at 2x mug must still pay the 1x take times the dial")
	assert_eq(mug2["text"], "[color=yellow]Mira mugs %d gold from Goblin![/color]" % int(mug2["paid"]),
		"at 2x the mug log must name the coins credited")
	assert_eq(int(mug2["shown"]), int(mug2["paid"]), "at 2x the mug log and the wallet must match")


func test_a_grind_steal_names_the_coins_the_batch_pays_at_1x_and_2x() -> void:
	var at1 := _grind_steal(1.0)
	var at2 := _grind_steal(2.0)
	assert_gt(int(at1["base"]), 0, "CONTROL: the grind steal must have landed")
	assert_eq(int(at1["paid"]), int(at1["base"]), "at 1x the grind pays the unscaled steal")
	assert_eq(at1["text"], "Rogue steals %d gold from Goblin" % int(at1["base"]),
		"at 1x the grind log must stay the unscaled sentence")
	assert_eq(int(at1["shown"]), int(at1["paid"]), "at 1x the grind log and the payout must match")
	assert_eq(int(at2["base"]), int(at1["base"]), "CONTROL: the same seed must roll the same steal")
	assert_eq(int(at2["paid"]), int(at1["base"]) * 2,
		"at 2x the grind must still pay the unscaled steal times the dial once")
	assert_eq(at2["text"], "Rogue steals %d gold from Goblin" % int(at2["paid"]),
		"at 2x the grind log must name the coins the batch pays")
	assert_eq(int(at2["shown"]), int(at2["paid"]), "at 2x the grind log and the payout must match")


func test_grind_steal_lines_add_up_to_the_batch_when_the_dial_is_fractional() -> void:
	## int(a * 1.5) + int(b * 1.5) can be a coin short of int((a + b) * 1.5). The batch pays the latter.
	_set_dial(1.5)
	var res := HeadlessBattleResolver.new()
	assert_eq(res._steal_share(0, 5) + res._steal_share(5, 10), 15,
		"two steals of 5 must announce 7 and 8, which add to the batch, not 7 and 7")
	res._stolen_gold = 10
	var paid: int = int(res._build_results(false)["gold_gained"])
	assert_eq(paid, 15, "the batch itself must still be int(10 * 1.5) — display must not retune the payout")
	assert_eq(res._steal_share(0, 5) + res._steal_share(5, 10), paid,
		"the lines have to add up to the coins _build_results credits")
	var code: String = GdSource.code_of("res://src/autogrind/HeadlessBattleResolver.gd")
	var at: int = code.find("func _roll_steal")
	assert_gt(at, -1, "CONTROL: _roll_steal survives stripping")
	var stop: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, stop - at)
	assert_true(body.contains("_steal_share("),
		"the grind log must name _steal_share's coins — a per-steal int(amount * dial) drifts off the batch")
	assert_true(body.contains("steals %d gold"), "the log sentence itself must survive")


func _open_chest(dial: float) -> Dictionary:
	_set_dial(dial)
	var chest: TreasureChest = load("res://src/exploration/TreasureChest.gd").new()
	chest.chest_id = "gold_msg_%d" % int(dial * 10)
	chest.contents_type = "gold"
	chest.gold_amount = CHEST_GOLD
	add_child_autofree(chest)
	GameState.set_story_flag("chest_" + chest.chest_id, false)
	var before: int = GameState.party_gold
	var stub := Node2D.new()
	add_child_autofree(stub)
	chest._open_chest(stub)
	var text: String = str(chest.dialogue_label.text)
	return {"text": text, "paid": GameState.party_gold - before, "shown": _int_in(text, "Found (\\d+) Gold!")}


func _grant_quest(dial: float) -> Dictionary:
	_set_dial(dial)
	QuestSystem._last_reward_summary = ""
	var before: int = GameState.party_gold
	QuestSystem._grant_rewards({"rewards": {"gold": QUEST_GOLD}})
	var text: String = QuestSystem._last_reward_summary
	return {"text": text, "paid": GameState.party_gold - before, "shown": _int_in(text, "Received: (\\d+) gold")}


func _examine_hearth(dial: float) -> Dictionary:
	_set_dial(dial)
	GameState.set_story_flag(FireplaceSecret.SECRET_FLAG, false)
	var secret := FireplaceSecret.new()
	add_child_autofree(secret)
	var before: int = GameState.party_gold
	secret._examine()
	var text := ""
	for child in secret.get_children():
		if child is Label and str(child.text).begins_with(FireplaceSecret.FOUND_LINE):
			text = str(child.text)
	return {"text": text, "paid": GameState.party_gold - before, "shown": _int_in(text, "\\(\\+(\\d+) G\\)")}


func _steal(dial: float, verb: String) -> Dictionary:
	_set_dial(dial)
	var rogue := Combatant.new()
	add_child_autofree(rogue)
	rogue.combatant_name = "Mira"
	rogue.max_hp = 400
	rogue.current_hp = 400
	rogue.is_alive = true
	var goblin := Combatant.new()
	add_child_autofree(goblin)
	goblin.combatant_name = "Goblin"
	goblin.max_hp = 400
	goblin.current_hp = 400
	goblin.is_alive = true
	BattleManager.player_party.assign([rogue] as Array[Combatant])
	var lines: Array[String] = []
	var grab := func(message: String) -> void:
		lines.append(message)
	BattleManager.battle_log_message.connect(grab)
	var before: int = GameState.party_gold
	seed(STEAL_SEED)
	BattleManager._award_stolen_gold(rogue, goblin, verb)
	if BattleManager.battle_log_message.is_connected(grab):
		BattleManager.battle_log_message.disconnect(grab)
	var text := "" if lines.is_empty() else lines[0]
	return {"text": text, "paid": GameState.party_gold - before, "shown": _int_in(text, "(\\d+) gold")}


func _grind_steal(dial: float) -> Dictionary:
	_set_dial(dial)
	seed(STEAL_SEED)
	var res := HeadlessBattleResolver.new()
	var rogue := Combatant.new()
	rogue.initialize({"name": "Rogue", "max_hp": 500, "max_mp": 20, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(rogue)
	rogue.combatant_name = "Rogue"
	var goblin := Combatant.new()
	goblin.initialize({"name": "Goblin", "max_hp": 500, "max_mp": 20, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(goblin)
	goblin.combatant_name = "Goblin"
	res._player_party = [rogue]
	res._roll_steal(rogue, {}, [goblin], 1.0)
	var paid: int = int(res._build_results(false)["gold_gained"])
	var text := ""
	for line in res._battle_log:
		if str(line).contains("steals"):
			text = str(line)
	return {"text": text, "paid": paid, "base": res._stolen_gold, "shown": _int_in(text, "steals (\\d+) gold")}
