extends GutTest

## Switching jobs restores the loadout that job last wore by writing the item ids
## straight onto the combatant. The shared bag is the only place unequipped gear
## lives, and that write never took the piece out of the bag or put the piece it
## replaced back. Wear the sword, change to Mage, equip the staff from the bag,
## change back: the sword is on the character AND still in the bag, and the staff
## is in neither — it exists only inside the other job's saved profile.


const SWORD := "iron_sword"
const STAFF := "wooden_staff"
const LEATHER := "leather_armor"
const ROBE := "cloth_robe"
const POWER := "power_ring"
const MAGIC := "magic_ring"
const MISSING := "flame_sword"

var _saved_persist: bool = false
var _gl: Node = null


class BagLoop:
	extends Node
	var equipment_pool: Dictionary = {
		"weapons": [],
		"armors": [],
		"accessories": [],
	}


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	assert_not_null(JobSystem, "JobSystem autoload required")
	assert_not_null(EquipmentSystem, "EquipmentSystem autoload required")
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"a GameLoop is already in the tree — this test would exchange with the wrong bag")
	_gl = BagLoop.new()
	_gl.name = "GameLoop"
	get_tree().root.add_child(_gl)


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	if _gl != null and is_instance_valid(_gl):
		_gl.free()
		_gl = null


func test_weapons_differ_so_a_stale_staff_cannot_match_the_sword() -> void:
	var sword: Dictionary = EquipmentSystem.get_weapon(SWORD).get("stat_mods", {})
	var staff: Dictionary = EquipmentSystem.get_weapon(STAFF).get("stat_mods", {})
	assert_ne(int(sword.get("attack", 0)), int(staff.get("attack", 0)),
		"iron_sword and wooden_staff must differ in attack or the stat oracle is vacuous")
	assert_gt(int(staff.get("magic", 0)), int(sword.get("magic", 0)),
		"the staff must add magic the sword does not, or a leftover staff bonus is invisible")
	assert_false(EquipmentSystem.get_armor(LEATHER).is_empty())
	assert_false(EquipmentSystem.get_armor(ROBE).is_empty())
	assert_false(EquipmentSystem.get_accessory(POWER).is_empty())
	assert_false(EquipmentSystem.get_accessory(MAGIC).is_empty())
	assert_false(EquipmentSystem.get_weapon(MISSING).is_empty(),
		"flame_sword must be a real weapon so the clone check is about ownership, not an unknown id")


func test_switching_back_returns_the_other_jobs_gear_once() -> void:
	var c := _hero()
	_wear(c, SWORD, LEATHER, POWER)
	_bag()["weapons"] = [STAFF]
	_bag()["armors"] = [ROBE]
	_bag()["accessories"] = [MAGIC]
	_assign(c, "mage")
	assert_eq(c.equipped_weapon, SWORD, "first visit forks the loadout — the sword stays worn")
	assert_eq(_owned(c, SWORD), 1)
	assert_eq(_owned(c, STAFF), 1)
	_wear_from_bag(c, "weapon", STAFF)
	_wear_from_bag(c, "armor", ROBE)
	_wear_from_bag(c, "accessory", MAGIC)
	assert_eq(_owned(c, SWORD), 1, "equipping from the bag must not itself duplicate")
	assert_eq(_owned(c, STAFF), 1)
	_assign(c, "fighter")
	assert_eq(c.equipped_weapon, SWORD, "the fighter loadout comes back")
	assert_eq(c.equipped_armor, LEATHER)
	assert_eq(c.equipped_accessory, POWER)
	assert_eq(_owned(c, SWORD), 1, "the sword must not be worn and still sitting in the bag")
	assert_eq(_owned(c, STAFF), 1, "the staff that was worn must be in the bag, once")
	assert_eq(_owned(c, LEATHER), 1)
	assert_eq(_owned(c, ROBE), 1)
	assert_eq(_owned(c, POWER), 1)
	assert_eq(_owned(c, MAGIC), 1)
	assert_eq(_bag()["weapons"].count(SWORD), 0)
	assert_eq(_bag()["weapons"].count(STAFF), 1)
	assert_eq(_bag()["armors"].count(LEATHER), 0)
	assert_eq(_bag()["armors"].count(ROBE), 1)
	assert_eq(_bag()["accessories"].count(POWER), 0)
	assert_eq(_bag()["accessories"].count(MAGIC), 1)
	_assert_matches_worn_gear(c)
	_assert_not_the_other_set(c, STAFF, ROBE, MAGIC)
	_assign(c, "mage")
	assert_eq(c.equipped_weapon, STAFF, "the mage loadout comes back from the bag, not from thin air")
	assert_eq(c.equipped_armor, ROBE)
	assert_eq(c.equipped_accessory, MAGIC)
	assert_eq(_owned(c, SWORD), 1)
	assert_eq(_owned(c, STAFF), 1)
	assert_eq(_bag()["weapons"].count(SWORD), 1)
	assert_eq(_bag()["weapons"].count(STAFF), 0)
	_assert_matches_worn_gear(c)


func test_a_remembered_piece_the_bag_does_not_hold_is_not_cloned() -> void:
	var c := _hero()
	_wear(c, STAFF, ROBE, MAGIC)
	c.job = JobSystem.get_job("fighter").duplicate(true)
	_wear(c, MISSING, LEATHER, POWER)
	c.save_current_profile()
	c.job = JobSystem.get_job("mage").duplicate(true)
	_wear(c, STAFF, ROBE, MAGIC)
	c.recalculate_stats()
	assert_eq(_owned(c, MISSING), 0, "flame_sword is only a memory on the fighter profile")
	assert_eq(_owned(c, STAFF), 1)
	_assign(c, "fighter")
	assert_eq(c.equipped_weapon, STAFF, "a sword the bag does not hold must not appear in the character's hands")
	assert_eq(_owned(c, MISSING), 0, "the remembered sword must not be minted")
	assert_eq(_owned(c, STAFF), 1, "the staff being worn must stay worn, not vanish into the profile")
	assert_eq(_bag()["weapons"].count(STAFF), 0)
	_assert_matches_worn_gear(c)


func test_a_spare_copy_stays_in_the_bag_when_the_loadout_already_wears_one() -> void:
	var c := _hero()
	_wear(c, SWORD, LEATHER, POWER)
	_bag()["weapons"] = [SWORD]
	assert_eq(_owned(c, SWORD), 2, "two owned swords: one worn, one in the bag")
	_assign(c, "mage")
	_assign(c, "fighter")
	assert_eq(c.equipped_weapon, SWORD)
	assert_eq(_owned(c, SWORD), 2, "switching back onto the sword already worn must not eat the spare")
	assert_eq(_bag()["weapons"].count(SWORD), 1)


func _hero() -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Gear Hero"
	assert_true(JobSystem.assign_job(c, "fighter"), "setup assign fighter failed")
	c.secondary_job_id = ""
	c.secondary_job = null
	c.job_level = 1
	c.job_profiles.clear()
	return c


func _bag() -> Dictionary:
	return _gl.equipment_pool


func _wear(c: Combatant, weapon_id: String, armor_id: String, accessory_id: String) -> void:
	c.equipped_weapon = weapon_id
	c.equipped_armor = armor_id
	c.equipped_accessory = accessory_id


func _wear_from_bag(c: Combatant, slot_name: String, item_id: String) -> void:
	var pool_key := "accessories" if slot_name == "accessory" else slot_name + "s"
	var bag: Array = _bag()[pool_key]
	assert_true(bag.has(item_id), "setup: %s must be in the bag before it is equipped" % item_id)
	var old_id := ""
	match slot_name:
		"weapon":
			old_id = c.equipped_weapon
			c.equipped_weapon = item_id
		"armor":
			old_id = c.equipped_armor
			c.equipped_armor = item_id
		"accessory":
			old_id = c.equipped_accessory
			c.equipped_accessory = item_id
	bag.erase(item_id)
	if old_id != "":
		bag.append(old_id)
	c.recalculate_stats()


func _owned(c: Combatant, item_id: String) -> int:
	var n := 0
	for key in ["weapons", "armors", "accessories"]:
		n += (_bag().get(key, []) as Array).count(item_id)
	if c.equipped_weapon == item_id:
		n += 1
	if c.equipped_armor == item_id:
		n += 1
	if c.equipped_accessory == item_id:
		n += 1
	return n


func _assert_matches_worn_gear(c: Combatant) -> void:
	var oracle := _oracle(c, c.equipped_weapon, c.equipped_armor, c.equipped_accessory)
	assert_eq(c.attack, oracle.attack, "attack must follow the gear actually worn")
	assert_eq(c.magic, oracle.magic, "magic must follow the gear actually worn")
	assert_eq(c.defense, oracle.defense, "defense must follow the gear actually worn")
	assert_eq(c.max_hp, oracle.max_hp, "max HP must follow the gear actually worn")
	assert_eq(c.max_mp, oracle.max_mp, "max MP must follow the gear actually worn")


func _assert_not_the_other_set(c: Combatant, weapon_id: String, armor_id: String, accessory_id: String) -> void:
	var other := _oracle(c, weapon_id, armor_id, accessory_id)
	assert_ne(c.attack, other.attack, "attack still includes the gear the job change took off")
	assert_ne(c.magic, other.magic, "magic still includes the gear the job change took off")


func _oracle(c: Combatant, weapon_id: String, armor_id: String, accessory_id: String) -> Combatant:
	var o := Combatant.new()
	add_child_autofree(o)
	o.combatant_name = "Oracle"
	o.job = (c.job as Dictionary).duplicate(true)
	o.job_level = c.job_level
	o.secondary_job = c.secondary_job
	o.secondary_job_id = c.secondary_job_id
	o.equipped_weapon = weapon_id
	o.equipped_armor = armor_id
	o.equipped_accessory = accessory_id
	o.equipped_passives = c.equipped_passives.duplicate()
	o.recalculate_stats()
	return o


func _assign(c: Combatant, job_id: String) -> void:
	var menu := JobMenu.new()
	add_child_autofree(menu)
	menu.character = c
	menu.selected_slot = 0
	var jobs: Array = menu._get_available_jobs()
	var idx: int = jobs.find(job_id)
	assert_ne(idx, -1, "job %s missing from the menu (%s)" % [job_id, str(jobs)])
	if idx < 0:
		return
	menu.selected_job_index = idx
	menu._assign_selected_job()
