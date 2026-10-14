extends GutTest

## _resolve_item TOOK the item and then returned on a dead target, so a potion aimed at a member
## who died earlier in the same round was CONSUMED and healed nobody. The REVIVE branch above it
## was already fixed for exactly this -- its own comment records the feather leaving the bag while
## the KO stayed down -- and the general path kept the defect. A fix that hid its own sibling.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = AutogrindState.snapshot_and_isolate()


func after_each() -> void:
	AutogrindState.restore(_snap)


func _member(n: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 100, "max_mp": 40, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	## is_alive is its OWN bool (Combatant:89), NOT derived from current_hp -- setting hp to 0 left
	## every "corpse" ALIVE, so two arms tested the wrong state and the third could not reach the
	## revive branch at all. die() is what the codebase uses.
	if alive:
		c.current_hp = 60
	else:
		c.die()
	return c


## bag == [user] because _resolve_item uses `_player_party if user in _player_party else [user]`,
## and a bare resolver has an empty _player_party -- so the user's own stock IS the bag.
func _resolver():
	var r = HeadlessBattleResolver.new()
	## Only parent it if it is a Node -- `add_child_autofree(<non-Node>)` raises "p_child is null",
	## which is non-fatal here but noise in the log and a real abort if it ever moves earlier.
	if r is Node:
		add_child_autofree(r)
	return r


func test_a_live_target_spends_the_item_and_is_healed() -> void:
	## THE CONTROL. Without it, every arm below passes on a resolver that does nothing at all.
	var user := _member("Bram", true)
	var target := _member("Marta", true)
	target.current_hp = 20
	user.add_item("potion", 1)
	assert_eq(user.get_item_count("potion"), 1, "FIXTURE: the user must hold the potion to spend")
	var r = _resolver()
	r.call("_resolve_item", user, "potion", target)
	assert_eq(user.get_item_count("potion"), 0,
		"a potion used on a LIVE target must be spent — if this is 1 the resolver did nothing and every arm below is vacuous")
	assert_gt(target.current_hp, 20,
		"and the live target must actually be healed, or the spend bought nothing")


func test_an_item_aimed_at_a_corpse_is_not_spent() -> void:
	var user := _member("Bram", true)
	var corpse := _member("Marta", false)
	user.add_item("potion", 1)
	var r = _resolver()
	r.call("_resolve_item", user, "potion", corpse)
	assert_eq(user.get_item_count("potion"), 1,
		"the potion was CONSUMED for a dead target and healed nobody — the liveness check must sit ABOVE the spend")
	assert_eq(corpse.current_hp, 0, "and a corpse must stay down: a potion does not revive")


func test_an_item_aimed_at_nothing_is_not_spent() -> void:
	var user := _member("Bram", true)
	user.add_item("potion", 1)
	var r = _resolver()
	r.call("_resolve_item", user, "potion", null)
	assert_eq(user.get_item_count("potion"), 1,
		"a null target must not spend the item either — same guard, same position")


## The branch the fix must NOT have broken: a revive item on a corpse still spends AND raises.
func test_a_revive_on_a_corpse_still_spends_and_raises() -> void:
	var user := _member("Bram", true)
	var corpse := _member("Marta", false)
	var revive_id: String = _a_revive_item()
	assert_ne(revive_id, "",
		"VOID: items.json has no item with effects.revive — this arm cannot test the branch it exists for")
	if revive_id == "":
		return
	user.add_item(revive_id, 1)
	var r = _resolver()
	r.call("_resolve_item", user, revive_id, corpse)
	assert_eq(user.get_item_count(revive_id), 0,
		"a revive item on a corpse must still be spent — the revive branch sits ABOVE the moved guard and must be untouched")
	assert_true(corpse.is_alive,
		"and it must actually raise them, or the spend bought nothing")


## Derived from items.json rather than hardcoded, so a renamed phoenix_down reds the VOID floor
## above instead of silently skipping the arm.
func _a_revive_item() -> String:
	for id in ItemSystem.items.keys():
		var it: Dictionary = ItemSystem.items[id]
		var fx = it.get("effects", {})
		if fx is Dictionary and bool((fx as Dictionary).get("revive", false)):
			return str(id)
	return ""
