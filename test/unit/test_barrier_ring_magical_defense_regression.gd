extends GutTest

## The Barrier Ring is a floor-4 chest in the Glacial Sanctum. Its description says it
## boosts physical and magical defense. Equipping it raised Defense and Magic.
## Magic is spell power. Magical hits — the battle preview, the watched executor, and
## the autogrind resolver — all divide by magic_defense, which the ring never touched.
## The status screen's Magic Defense row and the equipment bonus list showed the same gap.
## Unequip, job change, and save/load all rebuild through recalculate_stats, so they
## kept the wrong stat too.

const RING := "barrier_ring"
const INCOMING := 500


func before_each() -> void:
	assert_not_null(EquipmentSystem, "EquipmentSystem autoload required")
	assert_not_null(JobSystem, "JobSystem autoload required")
	assert_not_null(BattleManager, "BattleManager autoload required")


func test_a_player_can_find_a_ring_that_promises_magical_defense() -> void:
	var ring := EquipmentSystem.get_accessory(RING)
	assert_false(ring.is_empty(), "barrier_ring must be a real accessory")
	var desc := str(ring.get("description", "")).to_lower()
	assert_true("physical" in desc and "magical defense" in desc,
		"the chest copy must still be the claim this file defends — rewriting it would hide the bug")
	var cave := IceDragonCaveScene.new()
	assert_eq(str(cave.forced_item_chests.get("ice_dragon_cave_f4_c0", "")), "equipment:" + RING,
		"the ring has to be a chest a player can open")
	cave.free()


func test_wearing_it_raises_magic_defense_and_not_spell_power() -> void:
	var bare := _fighter("Bare")
	var wearer := _fighter("Ring")
	assert_true(EquipmentSystem.equip_accessory(wearer, RING), "equip must succeed")
	var mods: Dictionary = EquipmentSystem.get_accessory(RING).get("stat_mods", {})
	assert_false(mods.has("magic"),
		"the ring was granting Magic (+spell power). The description never says that")
	assert_true(mods.has("magic_defense"),
		"magical defense has to be a stat_mods entry or recalculate_stats cannot apply it")
	assert_gt(int(mods.get("defense", 0)), 0, "the physical half of the description must stay")
	assert_eq(wearer.defense - bare.defense, int(mods.get("defense", 0)),
		"physical defense must land as the authored flat bonus")
	assert_gt(int(mods.get("magic_defense", 0)), 0, "the magical-defense bonus must be a real amount")
	assert_eq(wearer.magic_defense - bare.magic_defense, int(mods.get("magic_defense", 0)),
		"Magic Defense must rise by the ring's bonus — that is the stat a spell divides by")
	assert_eq(wearer.magic, bare.magic, "the ring must not change spell power")
	var listed: Dictionary = EquipmentSystem.get_equipment_mods(wearer)
	assert_gt(int(listed.get("magic_defense", 0)), 0,
		"the equipment bonus list (status and equipment screens) must show the Magic Defense bonus")
	assert_eq(int(listed.get("magic", 0)), 0,
		"those screens must not advertise a Magic bonus the ring does not grant")
	assert_eq(StatNames.short_code("magic_defense"), "MDF")
	assert_eq(StatNames.display_name("magic_defense"), "Magic Defense")
	var again := wearer.magic_defense
	assert_true(EquipmentSystem.equip_accessory(wearer, RING))
	assert_eq(wearer.magic_defense, again, "equipping the same ring twice must not stack the bonus")


func test_a_magic_hit_and_its_preview_hurt_less_until_the_ring_comes_off() -> void:
	var bare := _fighter("Bare")
	var wearer := _fighter("Ring")
	assert_true(EquipmentSystem.equip_accessory(wearer, RING))
	var caster := _fighter("Caster")
	var spell := {"type": "magic", "damage_multiplier": 2.0}
	var preview_bare: int = BattleManager.estimate_ability_damage(caster, bare, spell)
	var preview_ring: int = BattleManager.estimate_ability_damage(caster, wearer, spell)
	assert_lt(preview_ring, preview_bare,
		"the battle preview reads magic_defense — the ring has to lower the quoted spell damage")
	_fill(bare)
	_fill(wearer)
	var hit_bare: int = bare.take_damage(INCOMING, true)
	var hit_ring: int = wearer.take_damage(INCOMING, true)
	assert_lt(hit_ring, hit_bare,
		"watched fights and the autogrind resolver both call take_damage(amount, true), which divides by magic_defense")
	_fill(bare)
	_fill(wearer)
	var phys_bare: int = bare.take_damage(INCOMING, false)
	var phys_ring: int = wearer.take_damage(INCOMING, false)
	assert_lt(phys_ring, phys_bare, "the physical-defense half must still reduce a physical hit")
	assert_true(EquipmentSystem.unequip_slot(wearer, EquipmentSystem.EquipSlot.ACCESSORY))
	assert_eq(wearer.equipped_accessory, "")
	assert_eq(wearer.magic_defense, bare.magic_defense, "unequip must give the magical defense back")
	assert_eq(wearer.magic, bare.magic, "unequip must not leave a spell-power change behind")
	assert_eq(wearer.defense, bare.defense, "unequip must give the physical defense back")


func test_job_change_and_save_load_keep_the_magical_defense() -> void:
	var bare := _fighter("Bare")
	var wearer := _fighter("Ring")
	assert_true(EquipmentSystem.equip_accessory(wearer, RING))
	var saved: Dictionary = wearer.to_dict()
	var loaded := Combatant.new()
	add_child_autofree(loaded)
	loaded.from_dict(saved)
	assert_true(JobSystem.assign_job(loaded, str(saved.get("job_id", "fighter"))))
	assert_true(EquipmentSystem.equip_accessory(loaded, str(saved.get("equipped_accessory", ""))),
		"Continue re-equips the saved accessory")
	assert_gt(loaded.magic_defense, bare.magic_defense,
		"a loaded ring wearer must still have more Magic Defense than the same job without it")
	assert_eq(loaded.magic, bare.magic, "load must not restore a spell-power bonus")
	assert_eq(loaded.magic_defense - bare.magic_defense, wearer.magic_defense - bare.magic_defense,
		"load must restore the same Magic Defense the equipped ring granted")
	assert_true(JobSystem.assign_job(bare, "mage"))
	assert_true(JobSystem.assign_job(wearer, "mage"))
	bare.recalculate_stats()
	wearer.recalculate_stats()
	assert_eq(wearer.equipped_accessory, RING, "changing jobs must leave the ring equipped")
	assert_gt(wearer.magic_defense, bare.magic_defense,
		"after a job change the ring's Magic Defense has to sit on top of the new job")
	assert_eq(wearer.magic, bare.magic, "a job change must not turn the ring into spell power")
	assert_gt(wearer.defense, bare.defense, "a job change must keep the physical defense")
	assert_true(EquipmentSystem.unequip_slot(wearer, EquipmentSystem.EquipSlot.ACCESSORY))
	wearer.recalculate_stats()
	assert_eq(wearer.magic_defense, bare.magic_defense, "unequip after a job change must drop the bonus")


func _fighter(who: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = who
	assert_true(JobSystem.assign_job(c, "fighter"), "setup assign fighter failed")
	c.recalculate_stats()
	return c


func _fill(c: Combatant) -> void:
	c.current_hp = c.max_hp
	c.is_alive = true
