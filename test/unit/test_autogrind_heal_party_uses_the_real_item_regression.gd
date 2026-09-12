extends GutTest

## `heal_party` is a PLAYER-AUTHORED autogrind rule action. It consumed a potion and healed a number
## written into the code: `[["hi_potion", 200], ["potion", 50]]`. items.json says 2000 and 500.
## So the rule granted a TENTH of what the item in the player's bag promises, and nothing failed —
## the heal happened, just small, which is the hardest kind of wrong to notice.
##
## Tick 394 already ruled on this exact class in HeadlessBattleResolver._resolve_item: "route through
## ItemSystem.use_item so autogrind item use matches live battle exactly", with a comment listing the
## same failure modes (mega_potion healing 50 instead of 100, phoenix_down healing instead of
## reviving). THIS SITE WAS MISSED BY THAT FIX — a second copy of the defect, one file away, already
## diagnosed. The amounts now come from items.json.
##
## ⛔ The arms below assert against items.json AT RUN TIME. Hardcoding "expect 500" here would put a
## THIRD copy of the number in the repo, which is the defect this fixes.

var _sys
var _items


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_sys = AutogrindSystem
	_items = get_tree().root.get_node_or_null("ItemSystem")


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false
	_sys.grind_party = _party([])


func _party(members: Array) -> Array[Combatant]:
	var typed: Array[Combatant] = []
	for m in members:
		typed.append(m)
	return typed


## max_hp is high enough that a full-size potion cannot cap out — otherwise `heal()` clamps and the
## 10x difference becomes invisible, which would make every arm below pass on the old code.
func _hurt_member(item_id: String, qty: int = 3) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Probe", "max_hp": 9000, "max_mp": 50, "attack": 20, "defense": 15, "magic": 10, "speed": 12})
	if item_id != "":
		c.add_item(item_id, qty)
	add_child_autofree(c)
	## ⛔ AFTER add_child, never before. Combatant._ready() does `current_hp = max_hp`, so a member
	## wounded pre-add enters the tree at FULL HP — heal_party then finds nobody under 80% and no-ops,
	## and the arm reads "restored 0" as a broken fix. Measured: that is exactly how this failed first.
	c.current_hp = 100
	return c


func _authored_heal(item_id: String) -> int:
	var rec: Dictionary = _items.get_item(item_id)
	return int(rec.get("effects", {}).get("heal_hp", 0))


## THE ARM THAT WOULD HAVE CAUGHT IT. The HP actually restored must equal what items.json authors.
func test_heal_party_heals_what_the_item_says() -> void:
	assert_not_null(_items, "CONTROL: ItemSystem autoload must be present or this measures nothing")
	for item_id in _sys.HEAL_PARTY_ITEM_ORDER:
		var authored: int = _authored_heal(item_id)
		assert_gt(authored, 0, "CONTROL: items.json must author a heal_hp for '%s'" % item_id)

		var m := _hurt_member(item_id)
		var before: int = m.current_hp
		_sys.grind_party = _party([m])
		## The REAL entry point a player's rule reaches — apply_autogrind_actions, not the applier.
		## prefer_restoratives would take the MP-casting branch instead, so it is off for this arm.
		_sys.prefer_restoratives = false
		_sys.apply_autogrind_actions([{"type": "heal_party"}])
		var gained: int = m.current_hp - before
		gut.p("  %-10s items.json authors %5d   restored %5d" % [item_id, authored, gained])
		assert_eq(gained, authored,
			"'%s' restored %d where items.json authors %d — a hardcoded amount is back" % [item_id, gained, authored])


## The 10x is the specific regression. Stated as a RELATIONSHIP so it survives a rebalance of
## items.json: whatever the file says, the old literals must no longer be what lands.
func test_the_old_hardcoded_amounts_are_not_what_lands() -> void:
	var stale := {"hi_potion": 200, "potion": 50}
	for item_id in stale.keys():
		var authored: int = _authored_heal(item_id)
		assert_ne(authored, int(stale[item_id]),
			"CONTROL: items.json now authors %d for '%s', the same as the old literal — this arm can no longer tell the fix from the bug" % [authored, item_id])
		var m := _hurt_member(item_id)
		var before: int = m.current_hp
		## ⛔ Through apply_autogrind_actions, NOT _apply_item_to. Calling the applier directly cannot
		## see a regression in heal_party itself — the applier would still be correct while the rule
		## went back to its literals. Measured: restoring the old block gave Failing 1 where I
		## predicted 3, and this arm was one of the two that could not see it.
		_sys.grind_party = _party([m])
		_sys.prefer_restoratives = false
		_sys.apply_autogrind_actions([{"type": "heal_party"}])
		assert_ne(m.current_hp - before, int(stale[item_id]),
			"'%s' restored exactly the old hardcoded %d" % [item_id, stale[item_id]])


## One item consumed per heal, not zero and not two.
func test_exactly_one_item_is_consumed() -> void:
	var m := _hurt_member("potion", 3)
	assert_true(_sys._apply_item_to(m, "potion"), "the applier reported failure on a valid item")
	assert_eq(m.get_item_count("potion"), 2, "expected exactly one potion consumed")


## A refused item must not be silently swallowed — and must not consume something it cannot apply
## when the reason is that nothing can apply it.
func test_an_unknown_item_is_refused_rather_than_healing_a_default() -> void:
	var m := _hurt_member("")
	m.add_item("not_a_real_item_id", 1)
	var before: int = m.current_hp
	var ok: bool = _sys._apply_item_to(m, "not_a_real_item_id")
	gut.p("  unknown id -> applied=%s, hp %d -> %d" % [ok, before, m.current_hp])
	assert_false(ok, "an unknown item id reported success")
	assert_eq(m.current_hp, before,
		"an unknown item healed anyway — the pre-fix resolver's `_: target.heal(50)` default is what made every unknown item a small potion")


## The amount must be READ, not listed. This is the property the old code lacked and the reason the
## fix is not simply correcting two numbers in place.
func test_the_amount_is_read_from_the_item_system_not_a_table() -> void:
	var src := FileAccess.get_file_as_string("res://src/autogrind/AutogrindSystem.gd")
	var i: int = src.find("func _apply_item_to")
	assert_gt(i, -1, "the applier is gone — heal_party is back to naming amounts")
	var body: String = src.substr(i, 900)
	assert_true(body.contains("use_item("),
		"_apply_item_to does not call ItemSystem.use_item, so the amount comes from somewhere else")

	## ⛔ NO ANCHOR. This used to window from `src.find('"heal_party":')` — and the FIRST occurrence of
	## that string is line 776, `"heal_party": "Heal Party"`, a LABEL in an unrelated dict. The window
	## never reached the action block at 2282, so restoring the literals scored GREEN. Measured, and
	## it is the bare-find() defect this lane already catalogued. Banning them FILE-WIDE needs no
	## anchor and is strictly stronger; verified 0 code-only occurrences of each before relying on it.
	var code_only := ""
	for line in src.split("\n"):
		code_only += line.split("#")[0] + "\n"
	for stale in ['["hi_potion", 200]', '["potion", 50]', 'heal(200)', 'heal(50)']:
		assert_false(code_only.contains(stale),
			"AutogrindSystem carries the literal `%s` again — items.json is the one source of a heal amount" % stale)
