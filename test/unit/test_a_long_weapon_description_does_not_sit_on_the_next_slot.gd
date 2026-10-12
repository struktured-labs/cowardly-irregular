extends GutTest

## Equip The Returned Sword, open PARTY STATUS, and the word "Armor" was overprinted with the
## second line of the weapon's description — two strings drawn on top of each other, neither
## readable. Found by rendering the screen at 1280x720 and looking at it.
##
## ⛔ THE ROW STRIDE WAS A CONSTANT AND THE CONTENT WAS NOT. `_add_equipment_row` draws its slot
## label at y, the item name at y+14 and the description at y+32 in a 30px band; the caller
## advanced `cy += 44` between rows. So a description occupying two lines reaches y+56 and lands
## on the next slot's label at y+44. 44 was only ever enough for a one-line description, and 71
## of the 121 authored item descriptions need more than one line.
##
## 🔑 THIS IS THE COLLISION I DECLINED TO GUARD AGAINST IN ItemsMenu AN HOUR AGO, AND THE
## DIFFERENCE IS THE DATA. There the effects row is pushed by a hard-coded 60px and the longest
## flavour wraps to about 42px, so nothing authored can reach it — I removed the derived-height
## change for being untestable. Here the same shape IS reached, by a real shipped weapon, so the
## derived height is the fix and this arm is what holds it.
##
## ⚠️ AND MY ItemsMenu GUARD WOULD NOT HAVE CAUGHT THIS. It asserts labels end inside the panel
## horizontally. This defect is entirely vertical: every label here is comfortably inside its
## parent's width. Two invariants, and the one I wrote first does not imply the other.

## ⚠ equipment.json, NOT items.json. My first version derived from items.json and the arm
## red with "the weapon description must be on screen" — PartyStatusScreen resolves through
## EquipmentSystem, so an item id that is not an equippable weapon renders no description at
## all. The control caught it, which is the control doing its job.
const EQUIPMENT_JSON := "res://data/equipment.json"

var _screen = null


func after_each() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null


func _longest_described_weapon() -> Array:
	## [weapon_id, description] for the longest authored WEAPON description. Derived, so the arm
	## follows the data rather than naming today's worst case.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(EQUIPMENT_JSON))
	assert_true(parsed is Dictionary, "CONTROL: equipment.json must parse")
	if not (parsed is Dictionary):
		return ["", ""]
	var weapons: Variant = (parsed as Dictionary).get("weapons", {})
	if not (weapons is Dictionary):
		return ["", ""]
	var best_id := ""
	var best := ""
	for k in (weapons as Dictionary):
		var v = (weapons as Dictionary)[k]
		if not (v is Dictionary):
			continue
		var d := str((v as Dictionary).get("description", ""))
		if d.length() > best.length():
			best = d
			best_id = str(k)
	return [best_id, best]


func _build(weapon_id: String):
	var c = load("res://src/battle/Combatant.gd").new()
	c.combatant_name = "Bram"
	c.equipped_weapon = weapon_id
	add_child_autofree(c)
	var s = load("res://src/ui/PartyStatusScreen.gd").new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(s)
	_screen = s
	await get_tree().process_frame
	s.setup([c])
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _label_with(root: Node, exact: String) -> Label:
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Label and (n as Label).text == exact:
			return n as Label
	return null


func _label_starting(root: Node, prefix: String) -> Label:
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Label and (n as Label).text.begins_with(prefix):
			return n as Label
	return null


func test_control_the_corpus_has_a_description_that_needs_two_lines() -> void:
	## Without this the arm below could pass on a one-line description, which never collided.
	var pair := _longest_described_weapon()
	assert_ne(str(pair[0]), "", "CONTROL: a longest-described item must be derivable")
	assert_gt(str(pair[1]).length(), 120,
		"CONTROL: the weapon description used below must be long enough to wrap past one line, got %d"
		% [str(pair[1]).length()])


func test_the_row_stride_grows_for_a_description_that_wraps() -> void:
	## ⛔ MEASURED ON THE SLOT LABELS, NOT ON THE DESCRIPTION'S REPORTED HEIGHT. A Label's
	## `size.y` is NOT its text height: measured here, a two-line label inside a plain Control
	## reports size=(592, 2604) while `get_line_count()` correctly says 2 and the font API
	## correctly says 28px. My first version of this arm read `desc.size.y` and failed with
	## "the description runs to y=2676", which is a number about the Control's rect and nothing
	## about the text. The slot labels' own positions are the thing the player sees collide.
	var pair := _longest_described_weapon()
	if str(pair[0]) == "":
		return
	var screen = await _build(str(pair[0]))
	var weapon := _label_with(screen, "Weapon")
	var armor := _label_with(screen, "Armor")
	var desc := _label_starting(screen, str(pair[1]).substr(0, 24))
	assert_not_null(weapon, "CONTROL: the Weapon slot label must be on screen")
	assert_not_null(armor, "CONTROL: the Armor slot label must be on screen")
	assert_not_null(desc, "CONTROL: the weapon description must be on screen")
	if weapon == null or armor == null or desc == null:
		return
	assert_gt(desc.get_line_count(), 1,
		"CONTROL: this description must actually WRAP, or the collision cannot occur (got %d line(s))"
		% [desc.get_line_count()])
	var stride: float = armor.position.y - weapon.position.y
	assert_gt(stride, 44.0,
		"the Weapon row advances %.0fpx to the Armor row, and 44 was the old constant — a "
		% [stride] + "description on %d lines reaches past it, so 'Armor' is drawn ON TOP of the "
		% [desc.get_line_count()] + "description's last line and neither is readable")


func test_control_a_row_with_no_description_still_advances_by_44() -> void:
	## ⛔ MY FIRST VERSION OF THIS ARM ASSERTED EVERY STRIDE > 44 AND RED ON CORRECT CODE.
	## Only a row holding a WRAPPED description needs more room; Armor and Accessory are empty in
	## this fixture, so their 44 is right. The arm that caught my over-reach is now the control
	## that stops the fix from simply inflating every row — which would pass the arm above and
	## push Accessory off the panel on a three-item loadout.
	var pair := _longest_described_weapon()
	if str(pair[0]) == "":
		return
	var screen = await _build(str(pair[0]))
	var armor := _label_with(screen, "Armor")
	var accessory := _label_with(screen, "Accessory")
	assert_not_null(armor, "CONTROL: the Armor slot label must be on screen")
	assert_not_null(accessory, "CONTROL: the Accessory slot label must be on screen")
	if armor == null or accessory == null:
		return
	assert_eq(accessory.position.y - armor.position.y, 44.0,
		"Armor has nothing equipped and so no description — its row must still advance by the "
		+ "plain 44, not by a stride inflated for everyone")


func test_control_a_slotless_member_still_lays_out() -> void:
	## The fix changes the stride for every row, including the ones with no description at all.
	var screen = await _build("")
	for name in ["Weapon", "Armor", "Accessory"]:
		assert_not_null(_label_with(screen, str(name)),
			"CONTROL: %s must still render with nothing equipped" % [name])
	var w := _label_with(screen, "Weapon")
	var a := _label_with(screen, "Armor")
	if w != null and a != null:
		assert_gt(a.position.y, w.position.y, "CONTROL: the rows must still descend")
