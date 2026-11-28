extends GutTest

## ⛔ A GREYED GROUP ROW COULD NOT BE READ. All four Group rows carried `disabled: not can_X`,
## and Win98Menu SKIPS a disabled row (_opening_index continues past it), so the tooltip naming the
## requirement — "requires 4 AP from all members" — sat where the cursor could never land. With
## every row unpayable _opening_index fell back to row 0, itself disabled, and confirm produced the
## generic "Can't use that right now": no cause at all.
##
## And the engine already knew the answer. group_ap_shortfall RETURNS THE MEMBER who is short; the
## menu reduced it to `== null` and threw the name away. Group attacks are a design pillar and this
## is visible at the DEFAULT settings to any party that cannot pay.
##
## The rows carry `reject_reason` now, which keeps them GREYED (Win98Menu:1131 dims a reject_reason
## row exactly as it dims a disabled one) but LANDABLE — and still refusing, because
## _row_unavailable reads both keys and every confirm path consults it.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")
## This file assigns BattleManager's party/order/index/current/enemies. The helper derives its
## surface from get_property_list(), so a field added tomorrow is covered without editing this.
const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")

var _battle_state: RefCounted = null


func before_each() -> void:
	_battle_state = BattleStateHelper.new()
	_battle_state.snapshot()


func after_each() -> void:
	if _battle_state != null:
		_battle_state.restore()


## Named for its job, so every DIGIT in a reason comes from a number rather than from a name.
func _pc(job_id: String, ap: int, abilities: Array) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = job_id.capitalize() if job_id != "" else "Goblin"
	c.job = {"id": job_id, "abilities": abilities}
	c.max_hp = 500
	c.current_hp = 500
	c.is_alive = true
	c.current_ap = ap
	return c


## PC 0 acts, so group_participants() pools the whole party. specs: [job_id, ap, abilities].
func _party(specs: Array) -> Array[Combatant]:
	var party: Array[Combatant] = []
	for s in specs:
		party.append(_pc(str((s as Array)[0]), int((s as Array)[1]), (s as Array)[2] as Array))
	BattleManager.player_party.assign(party)
	BattleManager.selection_order.assign(party)
	BattleManager.selection_index = 0
	BattleManager.current_combatant = party[0]
	BattleManager.enemy_party.assign([_pc("", 0, [])])
	return party


func _scene_for(party: Array[Combatant]) -> Node:
	var scene = autofree(SceneScript.new())
	scene.party_members.assign(party)
	scene.test_enemies.assign(BattleManager.enemy_party)
	for m in party:
		var sprite := AnimatedSprite2D.new()
		add_child_autofree(sprite)
		scene.party_sprite_nodes.append(sprite)
	var enemy_sprite := AnimatedSprite2D.new()
	add_child_autofree(enemy_sprite)
	scene.enemy_sprite_nodes.append(enemy_sprite)
	add_child_autofree(scene)
	return scene


## Every Group submenu row the REAL builder produced, keyed by id.
func _group_rows(scene, actor: Combatant) -> Dictionary:
	var out: Dictionary = {}
	for item in MenuScript.new(scene).build_command_menu_items_with_targets(actor):
		if str(item.get("id", "")) == "group_menu":
			for sub in (item.get("submenu", []) as Array):
				out[str((sub as Dictionary).get("id", ""))] = sub
	return out


## mage/cleric/bard puts arcane_tempest (min_members 3) on offer, so one build exercises all four
## rows. At 0 AP nothing is payable.
func _broke_party() -> Array[Combatant]:
	return _party([["mage", 0, ["fire", "blizzard"]], ["cleric", 0, ["cure"]], ["bard", 0, []]])


const ALL_FOUR: Array = ["group_all_out", "group_combo_magic", "group_limit", "group_formation"]


## FLOOR: a rename reds naming the symbol, instead of an arm aborting mid-frame and scoring green.
func test_the_symbols_this_file_drives_exist() -> void:
	var menu = MenuScript.new(_scene_for(_broke_party()))
	assert_true(menu.has_method("_group_ap_reason"),
		"FLOOR: _group_ap_reason turns the shortfall into something a player can read")
	assert_true(BattleManager.has_method("group_ap_shortfall"),
		"FLOOR: the engine side must still name the member who is short")
	var w98: Win98Menu = autofree(Win98Menu.new())
	assert_true(w98.has_method("_row_unavailable"),
		"FLOOR: _row_unavailable is the predicate every confirm path consults")


## THE DEFECT. Not one of the four may be `disabled`, and not one may be silent.
func test_every_unpayable_group_row_is_landable_and_says_why() -> void:
	var party := _broke_party()
	var rows := _group_rows(_scene_for(party), party[0])
	for id in ALL_FOUR:
		assert_true(rows.has(id),
			"CONTROL: the %s row must be built, or this arm proves nothing about it" % id)
	var skipped: Array = []
	var silent: Array = []
	for id in ALL_FOUR:
		if not rows.has(id):
			continue
		var row: Dictionary = rows[id]
		if bool(row.get("disabled", false)):
			skipped.append(id)
		if str(row.get("reject_reason", "")) == "":
			silent.append(id)
	assert_eq(skipped, [],
		"a disabled row is SKIPPED by the cursor, so the player cannot reach the one place its "
		+ "requirement is written: %s" % str(skipped))
	assert_eq(silent, [],
		"and a row with no reason falls through to the generic 'Can't use that right now', which "
		+ "names no cause while group_ap_shortfall already knows it: %s" % str(silent))


## Landable is NOT usable. Driven through the real predicate, not a replica of it.
func test_a_reasoned_row_still_refuses_the_attack() -> void:
	var party := _broke_party()
	var rows := _group_rows(_scene_for(party), party[0])
	var w98: Win98Menu = autofree(Win98Menu.new())
	for id in ALL_FOUR:
		assert_true(rows.has(id), "CONTROL: %s must be built" % id)
		if not rows.has(id):
			continue
		assert_true(w98._row_unavailable(rows[id]),
			"%s must still be REFUSED: making the row landable so its reason can be read must not " % id
			+ "let confirm fire an attack the engine would reject anyway")


## The reason must name WHO, which is the part a bare 'Not enough AP' cannot give.
func test_the_reason_names_the_member_and_both_numbers() -> void:
	var party := _party([["mage", 4, ["fire", "blizzard"]], ["cleric", 4, ["cure"]], ["bard", 1, []]])
	var rows := _group_rows(_scene_for(party), party[0])
	assert_true(rows.has("group_limit"), "CONTROL: the Limit Break row is built")
	if not rows.has("group_limit"):
		return
	var reason: String = str(rows["group_limit"].get("reject_reason", ""))
	gut.p("Limit Break reason: '%s'" % reason)
	assert_true("Bard" in reason,
		"the reason must NAME the member who is short — one flush party and one straggler is the "
		+ "ordinary case, and 'Not enough AP' does not say whose: got '%s'" % reason)
	assert_true("4" in reason, "and the AP Limit Break needs: got '%s'" % reason)
	assert_true("1" in reason, "and what that member actually has: got '%s'" % reason)


## ⛔ COMBO MAGIC HAS TWO CAUSES AND THEY ARE NOT INTERCHANGEABLE. Waiting a turn fixes AP; it
## never fixes a party that cannot field two elements. Both rendered as the same grey row.
func test_combo_magic_distinguishes_its_two_causes() -> void:
	var ap_party := _party([["mage", 4, ["fire", "blizzard"]], ["cleric", 1, ["cure"]]])
	var ap_rows := _group_rows(_scene_for(ap_party), ap_party[0])
	assert_true(ap_rows.has("group_combo_magic"), "CONTROL: the Combo Magic row is built (AP case)")
	var el_party := _party([["fighter", 4, []], ["rogue", 4, []]])
	var el_rows := _group_rows(_scene_for(el_party), el_party[0])
	assert_true(el_rows.has("group_combo_magic"), "CONTROL: and in the element case")
	if not (ap_rows.has("group_combo_magic") and el_rows.has("group_combo_magic")):
		return
	var ap_reason: String = str(ap_rows["group_combo_magic"].get("reject_reason", ""))
	var el_reason: String = str(el_rows["group_combo_magic"].get("reject_reason", ""))
	gut.p("combo AP cause: '%s' | element cause: '%s'" % [ap_reason, el_reason])
	assert_ne(ap_reason, "", "CONTROL: a combo nobody can pay for must say something")
	assert_ne(el_reason, "", "CONTROL: and so must one the party cannot element")
	assert_ne(ap_reason, el_reason,
		"the two causes must read differently: a player told 'needs AP' will wait a turn, and a "
		+ "party of two physical jobs will never field two elements however long it waits. Both: '%s'"
		% ap_reason)
	assert_true("AP" in ap_reason, "the AP cause must say AP: '%s'" % ap_reason)
	assert_true("element" in el_reason, "the element cause must say elements: '%s'" % el_reason)


## ⛔ THE FORMATION ROW USES ITS OWN COST. arcane_tempest is 3 AP each, a number no
## GROUP_AP_COST entry carries — drop the ap_cost argument and the fallback is 1, so the row would
## say "needs 1 AP" while the engine wants 3. A confidently wrong reason is worse than silence.
func test_the_formation_reason_uses_the_formations_own_cost() -> void:
	var party := _party([["mage", 2, ["fire", "blizzard"]], ["cleric", 4, ["cure"]], ["bard", 4, []]])
	var rows := _group_rows(_scene_for(party), party[0])
	assert_true(rows.has("group_formation"),
		"CONTROL: arcane_tempest must be on offer for mage/cleric/bard, or this arm is vacuous")
	if not rows.has("group_formation"):
		return
	var reason: String = str(rows["group_formation"].get("reject_reason", ""))
	gut.p("Formation reason: '%s'" % reason)
	assert_true("3 AP" in reason,
		"the Formation reason must name the formation's OWN 3 AP cost, not the 1 AP fallback that "
		+ "group_ap_shortfall uses when no cost is passed: got '%s'" % reason)
	assert_true("Mage" in reason, "and the member who is short: got '%s'" % reason)


## CONTROL — a payable row carries NO reason and is fully usable. Without this, an implementation
## that always attaches a reason would satisfy every arm above while refusing every group attack.
func test_a_payable_row_carries_no_reason_at_all() -> void:
	var party := _party([["mage", 4, ["fire", "blizzard"]], ["cleric", 4, ["cure"]], ["bard", 4, []]])
	var rows := _group_rows(_scene_for(party), party[0])
	var w98: Win98Menu = autofree(Win98Menu.new())
	for id in ALL_FOUR:
		assert_true(rows.has(id), "CONTROL: %s must be built" % id)
		if not rows.has(id):
			continue
		assert_eq(str(rows[id].get("reject_reason", "")), "",
			"CONTROL: a payable %s must carry no reason at all" % id)
		assert_false(w98._row_unavailable(rows[id]),
			"CONTROL: and must be fully usable — a reason that is always present is this same bug "
			+ "wearing the other mask, and every arm above would pass")
