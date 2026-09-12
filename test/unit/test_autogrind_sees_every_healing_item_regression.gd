extends GutTest

## `item_depleted` is ON by default and stops the grind when nobody can heal. The check asked for
## `potion` and `hi_potion` BY ID, and items.json holds eight HP-restoring items. So a party carrying
## 99 X-Potions and 5 Elixirs — strictly better healing than a potion — read as "Healing items
## depleted" and the grind refused to run, before the first battle, with a message saying something
## ran out that the player never had.
##
## ⛔ THE GRIND ITSELF NEVER HAD THIS LIMIT, which is what makes it a defect and not a balance choice.
## The item comes from the player's OWN rule (`action["item_id"]` in HeadlessBattleResolver) and is
## executed through ItemSystem.use_item, so a rule saying "use x_potion" always worked. Only the
## safety net could not see it — a gate narrower than the thing it gates.
##
## Same shape as the items-formatter fix earlier this session: the file already derived this
## correctly ONE function away (`_is_healing_item`, "effects-driven so new healing items ... with
## zero code change") and the gate hardcoded a pair instead.

var _sys

## Every id in items.json whose effects restore HP, and the one that cannot be used mid-grind.
const HP_RESTORATIVES := ["potion", "hi_potion", "mega_potion", "x_potion", "elixir", "megalixir", "phoenix_down"]
const SAVE_POINT_ONLY := "tent"
## Restores MP, not HP. Must NOT satisfy the gate — a party holding only Ethers cannot stay alive.
const MP_ONLY := ["ether", "hi_ether"]


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_sys = AutogrindSystem
	_sys.set_interrupt_rules({"hp_threshold": 0.0, "party_death": false, "item_depleted": true, "max_battles": 999})


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false
	_sys.set_interrupt_rules({"hp_threshold": 20.0, "party_death": true, "item_depleted": true, "max_battles": 100})
	_sys.grind_party = _party([])


## ⛔ grind_party is Array[Combatant]. Assigning an untyped `[c]` literal raises a script error that
## ABORTS THE ENCLOSING TEST — GUT then reports "did not assert" (Risky), the suite exits 0, and six
## of seven arms measure nothing while looking green. Measured: Passing 1 / Risky 6 / EC=0. The
## discriminator is authored-vs-executed, never the exit code. Always build the typed array first.
func _party(members: Array) -> Array[Combatant]:
	var typed: Array[Combatant] = []
	for m in members:
		typed.append(m)
	return typed


func _member_holding(item_id: String, qty: int = 5) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Probe", "max_hp": 100, "max_mp": 50, "attack": 20, "defense": 15, "magic": 10, "speed": 12})
	if item_id != "":
		c.add_item(item_id, qty)
	add_child_autofree(c)
	return c


## THE ARM THAT WOULD HAVE CAUGHT IT. Every HP restorative must satisfy the gate on its own.
func test_any_hp_restorative_keeps_the_grind_running() -> void:
	var blocked: Array = []
	for item_id in HP_RESTORATIVES:
		_sys.grind_party = _party([_member_holding(item_id)])
		var reason: String = _sys._check_interrupt_conditions()
		if reason != "":
			blocked.append("%s -> '%s'" % [item_id, reason])
	gut.p("  checked %d HP restoratives; blocked: %s" % [HP_RESTORATIVES.size(), blocked])
	assert_eq(blocked, [],
		"a party holding these could heal, and the grind refused to run: %s" % [blocked])
	## A floor, not ==: items.json may gain restoratives and this must not need editing to stay true.
	assert_gte(HP_RESTORATIVES.size(), 7, "CONTROL: the corpus shrank; re-derive it from items.json")
	assert_true(HP_RESTORATIVES.has("x_potion") and HP_RESTORATIVES.has("elixir"),
		"CONTROL: the two ids the shipped bug was reported against must be in the corpus")


## The control. With NOTHING, the gate must still fire — otherwise the arm above passes because the
## gate is dead, not because it is right.
func test_an_empty_party_still_trips_the_gate() -> void:
	_sys.grind_party = _party([_member_holding("")])
	assert_eq(_sys._check_interrupt_conditions(), "Healing items depleted",
		"a party with no items at all must still stop the grind — otherwise the safety net is off, not widened")


## A zero-quantity entry is not a held item, and `for item_id in inventory` sees the KEY regardless —
## which is why the gate tests `> 0` and not mere presence.
## ⚠️ I first wrote this using remove_item and claimed it leaves a 0 behind. MEASURED: it does not,
## it deletes the key ({ } after spending the last potion), so that version exercised the
## empty-inventory path the arm above already covers. Planting the 0 directly is what reaches the
## branch, and a 0 CAN arrive that way — any writer that decrements without cleaning up.
func test_a_zero_quantity_key_does_not_count_as_healing() -> void:
	var c := _member_holding("potion", 1)
	c.remove_item("potion", 1)
	gut.p("  remove_item leaves: %s  (no 0-key, so the branch needs one planted)" % [c.inventory])
	c.inventory["potion"] = 0
	_sys.grind_party = _party([c])
	assert_eq(_sys._check_interrupt_conditions(), "Healing items depleted",
		"a 0-quantity potion key satisfied the gate — presence is not possession")


## ⛔ MP is not HP. Reusing _is_healing_item (which includes heal_mp) would pass a party that cannot
## restore a single hit point — a different wrong answer, so the widening has its own predicate.
func test_mp_only_items_do_not_satisfy_the_gate() -> void:
	for item_id in MP_ONLY:
		_sys.grind_party = _party([_member_holding(item_id)])
		assert_eq(_sys._check_interrupt_conditions(), "Healing items depleted",
			"'%s' restores MP only and satisfied the HP-depletion gate — the party cannot heal" % item_id)
		assert_true(_sys._is_healing_item(item_id),
			"CONTROL: '%s' IS a healing item for the Iron Vigil streak — the two predicates must genuinely differ here, or this arm proves nothing" % item_id)


## A Tent heals 50% and is save_point_only, so counting it claims the player can heal with something
## they cannot reach mid-grind. Effect keys alone cannot separate it from an X-Potion.
func test_a_save_point_only_item_does_not_satisfy_the_gate() -> void:
	_sys.grind_party = _party([_member_holding(SAVE_POINT_ONLY)])
	assert_eq(_sys._check_interrupt_conditions(), "Healing items depleted",
		"a Tent satisfied the gate — it is save_point_only and cannot be used mid-grind")
	assert_false(_sys._is_battle_hp_restorative(SAVE_POINT_ONLY),
		"the predicate itself must reject save_point_only, not just this call site")


## One member holding the items is enough — the gate asks about the PARTY, not each member.
func test_one_stocked_member_covers_the_party() -> void:
	_sys.grind_party = _party([_member_holding(""), _member_holding(""), _member_holding("x_potion")])
	assert_eq(_sys._check_interrupt_conditions(), "",
		"two empty-handed members and one carrying X-Potions stopped the grind — the party can heal")


## The predicate must read items.json, not a list. This is the property the old code lacked, and the
## reason the fix is not simply a longer hardcoded pair.
func test_the_predicate_is_data_driven_not_a_hardcoded_list() -> void:
	var src := FileAccess.get_file_as_string("res://src/autogrind/AutogrindSystem.gd")
	var i: int = src.find("func _is_battle_hp_restorative")
	assert_gt(i, -1, "the predicate is gone — the gate is back to naming ids")
	var body: String = src.substr(i, 900)
	assert_true(body.contains("get_item("),
		"_is_battle_hp_restorative does not ask ItemSystem — a longer hardcoded list is the same defect with more entries")
	assert_true(body.contains("save_point_only"),
		"the predicate does not exclude save_point_only, so a Tent counts as reachable healing")
