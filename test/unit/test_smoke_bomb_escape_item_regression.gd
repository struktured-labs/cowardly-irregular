extends GutTest

## Smoke Bomb costs 100 gold and its description reads "Guarantees escape from
## non-boss battles". It was consumed and did nothing.
##
## items.json authors effects {"escape_battle": true}. ItemSystem deliberately does
## not resolve that key itself and lists it in _CALLER_HANDLED_EFFECT_KEYS, whose
## comment states the contract explicitly:
##
##   escape_battle -> BattleManager._execute_item gates escape before consume
##
## BattleManager did not contain the string "escape_battle" anywhere. The routing
## the comment described was never built, so the documented handler-coverage test
## saw the key as "handled" (it is in the caller-handled list) while no caller
## handled it. Two corpora agreeing on a key the consumer never reads — the same
## shape as burn/burning and the quest notify_flag gap.
##
## Note the near-miss for anyone searching: there are TWO smoke_bombs. The Rogue
## ABILITY (abilities.json) escapes correctly via _execute_escape_ability's
## guaranteed_escape branch. The ITEM (items.json) is the broken one, and grepping
## "smoke_bomb" in BattleManager returns the ability's hits, which is why this
## looked wired.
##
## Runtime, not a source pin: the three existing _execute_item guards in
## test_battle_manager_silent_fail_surfaces are all substring assertions on the
## function body, and a source pin cannot see a key that is never read.

var _saved_state
var _saved_pp: Array = []
var _saved_ep: Array = []
var _saved_escape: bool = true


func before_each() -> void:
	_saved_state = BattleManager.current_state
	_saved_pp = BattleManager.player_party.duplicate()
	_saved_ep = BattleManager.enemy_party.duplicate()
	_saved_escape = BattleManager.escape_allowed


func after_each() -> void:
	# BattleManager is an autoload and GUT is one process — restore unconditionally.
	BattleManager.escape_allowed = _saved_escape
	BattleManager.current_state = _saved_state
	BattleManager.player_party.clear()
	for c in _saved_pp:
		BattleManager.player_party.append(c)
	BattleManager.enemy_party.clear()
	for c in _saved_ep:
		BattleManager.enemy_party.append(c)


func _make_user() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Tester"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	c.add_item("smoke_bomb", 2)
	return c


func test_smoke_bomb_actually_ends_a_non_boss_battle() -> void:
	var user := _make_user()
	assert_true(user.has_item("smoke_bomb"),
		"precondition: the user must hold the item, else _execute_item returns early "
		+ "and this test proves nothing")
	BattleManager.player_party.clear()
	BattleManager.player_party.append(user)
	BattleManager.escape_allowed = true
	watch_signals(BattleManager)

	BattleManager._execute_item(user, "smoke_bomb", [])

	assert_signal_emitted(BattleManager, "battle_ended",
		"a Smoke Bomb in a non-boss battle must END the battle — before the fix it was "
		+ "consumed, the turn was spent, and the fight continued")
	assert_false(user.has_item("smoke_bomb", 2),
		"the item must be consumed on a successful escape")


func test_smoke_bomb_refuses_a_boss_battle_and_is_not_consumed() -> void:
	var user := _make_user()
	BattleManager.player_party.clear()
	BattleManager.player_party.append(user)
	# start_battle sets this false when a boss is present.
	BattleManager.escape_allowed = false
	watch_signals(BattleManager)

	BattleManager._execute_item(user, "smoke_bomb", [])

	assert_signal_not_emitted(BattleManager, "battle_ended",
		"the description promises escape from NON-BOSS battles; a boss fight must not end")
	assert_true(user.has_item("smoke_bomb", 2),
		"ItemSystem's contract says the caller gates escape BEFORE consume — refusing "
		+ "must not eat the item, or the gate costs the player 100 gold to learn")


## Control: the escape branch must be specific to the escape key, not something that
## ends the battle on any item use. Without this, a bug that ended every battle would
## pass the first test.
func test_a_normal_item_does_not_end_the_battle() -> void:
	var user := _make_user()
	user.add_item("potion", 1)
	if not user.has_item("potion"):
		pending("no 'potion' item in the corpus to use as a control")
		return
	user.current_hp = 10
	BattleManager.player_party.clear()
	BattleManager.player_party.append(user)
	BattleManager.escape_allowed = true
	watch_signals(BattleManager)

	BattleManager._execute_item(user, "potion", [user])

	assert_signal_not_emitted(BattleManager, "battle_ended",
		"a healing item must not end the battle — the escape branch must key off "
		+ "escape_battle, not fire on any successful item use")
