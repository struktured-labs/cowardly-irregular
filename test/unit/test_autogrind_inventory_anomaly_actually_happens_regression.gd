extends GutTest

## ⛔ A HALF-FIX OF MY OWN, FOUND BY @cowir-adhoc'S PATTERN RATHER THAN BY A TEST.
##
## `check_fatigue_event` emits "Inventory anomaly — items corrupted" and the controller applies the
## effect AFTERWARDS. So the player is told first, and the effect used to take nothing most of the
## time: it picked ONE random alive member and checked four hardcoded ids.
##
##     item_loss could steal    potion · hi_potion · ether · hi_ether
##     items.json restoratives  11 — elixir, mega_potion, x_potion, megalixir, phoenix_down,
##                              mega_ether, tent are all invisible to it
##
## A five-member party carrying X-Potions lost nothing on every roll. Two independent reasons for one
## no-op: the wrong SET, and one random member instead of the party.
##
## 🔑 It became a VISIBLE lie only when I wired the authored descriptions to the console. Before that
## the player saw a generic "[FATIGUE #n]" line, so the gap cost nothing — my own fix is what turned a
## latent shortcut into a false statement, which is why this is mine and not a balance question.
##
## The residue is stated rather than hidden: a party carrying NOTHING still sees the message. That one
## cannot be fixed here — it needs the announcement to describe an outcome instead of an intent, which
## means moving the emit out of check_fatigue_event and changing who announces. Logged loudly instead.

var _sys

## Every restorative in items.json, so this reds if the data grows a kind the effect cannot see.
const RESTORATIVES := ["potion", "hi_potion", "ether", "hi_ether", "elixir", "mega_potion",
	"x_potion", "megalixir", "phoenix_down", "mega_ether", "tent"]
## The four the pre-fix effect knew about.
const OLD_FOUR := ["potion", "hi_potion", "ether", "hi_ether"]


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_sys = AutogrindSystem


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


func _member(item_id: String = "", qty: int = 2) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "P", "max_hp": 500, "max_mp": 50, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	if item_id != "":
		c.add_item(item_id, qty)
	return c


func _party(members: Array) -> Array:
	return members


## THE ARM THAT WOULD HAVE CAUGHT IT: every restorative must be corruptible on its own.
func test_every_restorative_can_be_corrupted() -> void:
	var blind: Array = []
	for item_id in RESTORATIVES:
		var m := _member(item_id)
		var taken: String = _sys.corrupt_one_restorative(_party([m]))
		if taken != item_id or m.get_item_count(item_id) != 1:
			blind.append("%s -> took '%s', %d left" % [item_id, taken, m.get_item_count(item_id)])
	gut.p("  checked %d restoratives; invisible to the effect: %s" % [RESTORATIVES.size(), blind])
	assert_eq(blind, [],
		"the fatigue event says these were corrupted and the effect cannot see them: %s" % [blind])
	## A floor, not ==: items.json may gain restoratives and this must not need editing to stay true.
	assert_gte(RESTORATIVES.size(), 11, "CONTROL: the corpus shrank — re-derive it from items.json")
	for k in OLD_FOUR:
		assert_true(RESTORATIVES.has(k), "CONTROL: the pre-fix four must remain in the corpus, missing %s" % k)


## THE SECOND NO-OP: a stocked teammate must not be invisible because a different member was picked.
## Run repeatedly — the pick is random, so a single pass could pass by luck.
func test_a_stocked_teammate_is_never_missed() -> void:
	for _i in range(25):
		var empty_a := _member()
		var empty_b := _member()
		## ⛔ `potion`, deliberately — it is one of the PRE-FIX four. Using x_potion here made this arm
		## depend on the SET fix as well, so restoring the old id list redded both arms and neither
		## isolated its own cause. Measured: predicted Failing 1, got 2. With a potion this arm fails
		## ONLY for the scope bug, and the restoratives arm fails ONLY for the set bug.
		var holder := _member("potion", 1)
		var taken: String = _sys.corrupt_one_restorative(_party([empty_a, empty_b, holder]))
		assert_eq(taken, "potion",
			"two empty-handed members and one carrying a potion, and the effect took '%s' — it is checking one member, not the party" % taken)
		assert_eq(holder.get_item_count("potion"), 0, "the item was reported taken but is still held")


## Exactly ONE item goes, not a stack and not one per member.
func test_exactly_one_item_is_corrupted() -> void:
	var a := _member("potion", 3)
	var b := _member("ether", 3)
	var taken: String = _sys.corrupt_one_restorative(_party([a, b]))
	assert_ne(taken, "", "nothing was corrupted from a party holding two kinds")
	var total: int = a.get_item_count("potion") + b.get_item_count("ether")
	assert_eq(total, 5, "expected exactly one of six items gone, %d remain" % total)


## An empty party returns "" so the caller can SAY so. This is the residue, pinned as a contract:
## the effect must not pretend, and the controller logs it.
func test_an_empty_party_reports_that_nothing_was_taken() -> void:
	assert_eq(_sys.corrupt_one_restorative(_party([_member(), _member()])), "",
		"an empty-handed party must report '' so the caller knows the announcement was not realised")
	var ctrl := FileAccess.get_file_as_string("res://src/autogrind/AutogrindController.gd")
	assert_true(ctrl.contains("nothing was corrupted"),
		"the controller does not log the no-op — the player has already been told items were corrupted, so this must at least be diagnosable")


## Dead members are not robbed: the effect is flavour about the living party's supplies.
func test_a_dead_member_is_not_robbed() -> void:
	var dead := _member("potion", 2)
	dead.is_alive = false
	assert_eq(_sys.corrupt_one_restorative(_party([dead])), "",
		"an item was taken from a dead party member")
	assert_eq(dead.get_item_count("potion"), 2, "the dead member's items were touched")


## ⛔ A corrupted item is NOT a consumed item. Counting it would inflate the player's items-used stat
## and break their Iron Vigil streak for a heal that never happened.
func test_corruption_does_not_count_as_consumption() -> void:
	_sys.items_consumed.clear()
	_sys.battles_without_heal = 7
	var m := _member("potion", 2)
	assert_eq(_sys.corrupt_one_restorative(_party([m])), "potion", "CONTROL: the corruption must have happened")
	assert_eq(_sys.items_consumed.size(), 0,
		"a corrupted item was recorded as consumed — it inflates the items-used stat with a heal that never happened")
	assert_eq(_sys.battles_without_heal, 7,
		"corruption broke the Iron Vigil streak, which tracks items the player USED")
