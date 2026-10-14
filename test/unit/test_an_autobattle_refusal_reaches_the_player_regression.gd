extends GutTest

## An autobattle refusal becomes a DEFER in the caller, so the player watches a scripted caster
## play "🛡 defends — incoming damage halved" with no reason given. Pre-fix the three
## player-actionable refusals in _convert_autobattle_action were print-only, and print reaches the
## log FILE, never the battle log panel.
##
## ⚠️ test_an_autobattle_refusal_says_why_in_both_arms IS GREEN AND WAS GREEN THROUGH THIS. It reads
## the source for a `print(` between each condition and its `return {}`, so it certifies that a
## DEVELOPER can see the reason. Its own docstring describes the player complaint — a Potion rule
## deferring with "nothing in the log" — and a print never fixed it. Same subject, different
## question; this file asks the player's by capturing the SIGNAL, which no print can satisfy.
##
## Scope is deliberate: the two id-is-empty/unknown refusals stay print-only because they are
## authoring bugs with no player remedy. These three are states the player can act on — wait out a
## silence, restore MP, buy more Potions.

var _saved_pp: Array = []
var _saved_ep: Array = []
var _saved_state
var _lines: Array[String] = []
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_saved_pp = BattleManager.player_party.duplicate()
	_saved_ep = BattleManager.enemy_party.duplicate()
	_saved_state = BattleManager.current_state
	AutobattleSystem._test_disable_persistence = true
	_lines.clear()
	_fixture_ids.clear()
	## Autoload state: a reason spoken by one arm would mute the next one's.
	BattleManager._autobattle_refusals_said.clear()
	BattleManager.battle_log_message.connect(_collect)


func after_each() -> void:
	if BattleManager.battle_log_message.is_connected(_collect):
		BattleManager.battle_log_message.disconnect(_collect)
	BattleManager.current_state = _saved_state
	BattleManager.player_party.clear()
	for c in _saved_pp:
		BattleManager.player_party.append(c)
	BattleManager.enemy_party.clear()
	for e in _saved_ep:
		BattleManager.enemy_party.append(e)
	for cid in _fixture_ids:
		AutobattleSystem.character_profiles.erase(cid)


func _collect(message: String) -> void:
	_lines.append(message)


func _said(fragment: String) -> bool:
	for line in _lines:
		if fragment.to_lower() in line.to_lower():
			return true
	return false


func _mage() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.initialize({"name": "Mage", "max_hp": 400, "max_mp": 90,
		"attack": 40, "defense": 40, "magic": 160, "speed": 14})
	c.job = JobSystem.get_job("mage")
	c.job_level = 10
	c.is_alive = true
	return c


func _field(caster: Combatant) -> Combatant:
	var foe := Combatant.new()
	autofree(foe)
	foe.initialize({"name": "Road Slime", "max_hp": 500, "max_mp": 0,
		"attack": 10, "defense": 10, "magic": 1, "speed": 1})
	foe.is_alive = true
	_fixture_ids.append(AutobattleSystem._get_character_id(caster))
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	BattleManager.player_party.append(caster)
	BattleManager.enemy_party.append(foe)
	return foe


func _convert(caster: Combatant, action: Dictionary) -> Dictionary:
	var allies: Array = []
	for a in BattleManager.player_party:
		allies.append(a)
	var foes: Array = []
	for e in BattleManager.enemy_party:
		foes.append(e)
	return BattleManager._convert_autobattle_action(caster, action, allies, foes)


## FLOOR: every symbol this file reaches, named here so a rename reds with the symbol in the message
## rather than letting an arm abort mid-frame and score as a pass.
func test_the_subjects_this_file_drives_all_exist() -> void:
	assert_true(BattleManager.has_method("_convert_autobattle_action"),
		"FLOOR: BattleManager._convert_autobattle_action is the subject of every arm below")
	assert_true(BattleManager.has_method("consumable_bag"),
		"FLOOR: the item arm's stock check reads consumable_bag")
	assert_true(JobSystem.has_method("can_use_ability"),
		"FLOOR: can_use_ability is the authority the refusal asks")
	assert_true(JobSystem.has_method("get_ability_mp_cost"),
		"FLOOR: the MP reason is derived from get_ability_mp_cost, not from a bare mp_cost field")
	assert_true(BattleManager.has_signal("battle_log_message"),
		"FLOOR: battle_log_message is the channel every claim in this file reads")
	var fire: Dictionary = JobSystem.get_ability("fire")
	assert_false(fire.is_empty(), "FLOOR: 'fire' must resolve, or the ability arms drive nothing")
	assert_gt(int(fire.get("mp_cost", 0)), 0,
		"FLOOR: the MP arm needs an ability that actually costs MP")


## CONTROL — the arm that must LAND. Without it every assertion below is satisfied by a refusal
## that fires unconditionally, and "the emit is conditional" is the whole claim.
func test_a_usable_ability_converts_and_says_nothing() -> void:
	var caster := _mage()
	var foe := _field(caster)
	caster.current_mp = caster.max_mp
	var converted := _convert(caster, {"type": "ability", "ability_id": "fire", "targets": [foe]})
	assert_false(converted.is_empty(),
		"CONTROL: an affordable, unsilenced cast must still convert — if this fails the refusal "
		+ "arms below prove nothing")
	assert_eq(str(converted.get("ability_id", "")), "fire")
	assert_eq(_lines, [] as Array[String],
		"CONTROL: a cast that succeeds must not emit a refusal line. Got: %s" % str(_lines))


func test_a_silenced_scripted_caster_is_told_on_screen() -> void:
	var caster := _mage()
	var foe := _field(caster)
	caster.current_mp = caster.max_mp
	caster.add_status("silence", 3)
	var converted := _convert(caster, {"type": "ability", "ability_id": "fire", "targets": [foe]})
	assert_true(converted.is_empty(), "a silenced caster must still refuse the action")
	assert_true(_said("silenced"),
		"the player must be told the cast was refused for SILENCE, on screen. Battle log: %s"
		% str(_lines))
	assert_true(_said("Mage"),
		"the line must name the caster, or the player cannot tell who defended. Got: %s"
		% str(_lines))


func test_a_caster_short_on_mp_is_told_on_screen() -> void:
	var caster := _mage()
	var foe := _field(caster)
	caster.current_mp = 0
	var converted := _convert(caster, {"type": "ability", "ability_id": "fire", "targets": [foe]})
	assert_true(converted.is_empty(), "a cast the caster cannot pay for must refuse")
	assert_true(_said("MP"),
		"MP is the routine refusal and the one a player fixes by resting — it must be on screen. "
		+ "Battle log: %s" % str(_lines))
	assert_false(_said("silenced"),
		"an MP refusal must NOT blame silence — blaming a boss debuff for an empty bar sends the "
		+ "player to the wrong remedy. Got: %s" % str(_lines))


## Silence is checked BEFORE MP in can_use_ability, so a caster who is both must hear the one that
## actually blocks it. Pins the precedence rather than re-asserting either reason.
func test_silence_outranks_mp_in_the_reason_given() -> void:
	var caster := _mage()
	var foe := _field(caster)
	caster.current_mp = 0
	caster.add_status("silence", 3)
	assert_true(_convert(caster, {"type": "ability", "ability_id": "fire", "targets": [foe]}).is_empty())
	assert_true(_said("silenced"),
		"silence is the gate can_use_ability hits first; the reason must match it. Got: %s"
		% str(_lines))
	assert_false(_said("hasn't the MP"),
		"a silenced caster with an empty bar must not be told to go and rest. Got: %s" % str(_lines))


func test_an_empty_bag_says_so_on_screen() -> void:
	var caster := _mage()
	_field(caster)
	var bag: Variant = BattleManager.consumable_bag(caster)
	var held: int = ItemSystem.party_item_count(bag, "potion")
	assert_eq(held, 0,
		"fixture: this arm needs an EMPTY bag, else the refusal never fires and the assert below "
		+ "passes vacuously. Held: %d" % held)
	var converted := _convert(caster, {"type": "item", "item_id": "potion", "targets": [caster]})
	assert_true(converted.is_empty(), "an item the party does not hold must refuse")
	assert_true(_said("potion"),
		"this is the exact complaint the sibling guard's docstring describes — a Potion rule that "
		+ "defers with nothing on screen. The item must be named. Battle log: %s" % str(_lines))


## The Advance loop converts up to FIVE actions per turn, calling this function once each, so one
## cause must not repeat once per queued action. Five identical lines bury a six-line panel.
func test_one_cause_speaks_once_per_turn_not_once_per_queued_action() -> void:
	var caster := _mage()
	var foe := _field(caster)
	caster.current_mp = caster.max_mp
	caster.add_status("silence", 3)
	var action := {"type": "ability", "ability_id": "fire", "targets": [foe]}
	for _i in range(5):
		assert_true(_convert(caster, action).is_empty(), "every one of the five must still refuse")
	assert_eq(_lines.size(), 1,
		"a five-action rule under one silence must say it ONCE, not five times. Got %d: %s"
		% [_lines.size(), str(_lines)])


## CONTROL for the dedupe — it must collapse a REPEAT, never a second distinct cause. Without this
## arm, muting the channel entirely would satisfy the arm above.
func test_two_different_causes_both_speak() -> void:
	var caster := _mage()
	var foe := _field(caster)
	caster.current_mp = caster.max_mp
	caster.add_status("silence", 3)
	_convert(caster, {"type": "ability", "ability_id": "fire", "targets": [foe]})
	## Silence blocks abilities, not items, so the empty bag is a genuinely different refusal.
	_convert(caster, {"type": "item", "item_id": "potion", "targets": [caster]})
	assert_eq(_lines.size(), 2,
		"CONTROL: two distinct causes must both reach the player — the dedupe keys on the REASON, "
		+ "it is not a mute. Got %d: %s" % [_lines.size(), str(_lines)])
	assert_true(_said("silenced") and _said("potion"),
		"both reasons must be named, not just counted. Got: %s" % str(_lines))


## And it must be a PER-TURN collapse, not a permanent one: the same silence on the next turn is
## news again. The floor below pins that the turn entry point is what clears it.
func test_the_same_cause_speaks_again_next_turn() -> void:
	var caster := _mage()
	var foe := _field(caster)
	caster.current_mp = caster.max_mp
	caster.add_status("silence", 3)
	var action := {"type": "ability", "ability_id": "fire", "targets": [foe]}
	_convert(caster, action)
	assert_eq(_lines.size(), 1, "first turn says it once")
	_convert(caster, action)
	assert_eq(_lines.size(), 1, "still the same turn, still once")
	BattleManager._autobattle_refusals_said.clear()
	_convert(caster, action)
	assert_eq(_lines.size(), 2,
		"a new turn must speak again — a permanent mute would leave the player watching a caster "
		+ "defend for the rest of the fight with one line from turn one. Got: %s" % str(_lines))


## FLOOR: the per-turn reset above is only per-TURN if the turn entry point performs it. Source-level
## by necessity — driving _process_grid_autobattle needs the whole selection machine — and it is a
## floor, not the claim: the arms above own the behaviour.
func test_the_turn_entry_point_clears_the_dedupe() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_ne(src, "", "FLOOR: the source must be readable for this floor to mean anything")
	var head: int = src.find("func _process_grid_autobattle")
	assert_gt(head, -1, "FLOOR: _process_grid_autobattle is the per-turn entry point")
	var body_end: int = src.find("\nfunc ", head + 1)
	var body: String = src.substr(head, body_end - head) if body_end > -1 else src.substr(head)
	assert_true(body.contains("_autobattle_refusals_said.clear()"),
		"the turn entry point must clear the spoken-reasons set, or the collapse becomes permanent "
		+ "and a silenced caster explains itself once per battle instead of once per turn")


## The distinction the sibling guard cannot make: a print satisfies it, and only the signal reaches
## the player. If this ever fails because the emits moved to print, the sibling stays green.
func test_the_reason_travels_by_signal_not_by_print() -> void:
	var caster := _mage()
	var foe := _field(caster)
	caster.current_mp = caster.max_mp
	caster.add_status("silence", 3)
	_convert(caster, {"type": "ability", "ability_id": "fire", "targets": [foe]})
	assert_gt(_lines.size(), 0,
		"battle_log_message is the only channel the battle log panel renders. Zero emissions means "
		+ "the reason is print-only again, which is the pre-fix state the sibling guard passed")
