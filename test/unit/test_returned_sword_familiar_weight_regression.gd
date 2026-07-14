extends GutTest

## Queue #2 (cowir-main msg 2147/2149): returned_sword is now a real weapon
## with the Familiar Weight passive — +10% damage vs any enemy the party
## has already seen or defeated. Story-authored quest reward from
## world1_untested_edge; item description in items.json specified the intent.
##
## Guards:
##  1. equipment.json entry exists, sword-type, ATK ~14, familiar_weight_bonus authored.
##  2. equip_weapon accepts the id (would fail loudly pre-fix).
##  3. Damage scaling: unseen target → baseline; seen target → +bonus%; already-defeated
##     target → +bonus%. Zero bonus when the sword isn't equipped.
##  4. Called at both damage sites: basic melee (line ~3600) and physical ability (~3964).

const BM_PATH: String = "res://src/battle/BattleManager.gd"


func _bm() -> Node:
	# _sum_equipment_special_effect + BestiarySystem lookup route through
	# /root autoload paths, so the BM node needs a tree parent.
	var bm: Node = load(BM_PATH).new()
	add_child_autofree(bm)
	return bm


func _combatant(name_str: String, wep_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name_str
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	c.job = {"id": "fighter"}
	if wep_id != "":
		c.equipped_weapon = wep_id
	return c


## ── Data / equipment integrity ──────────────────────────────────────────

func test_returned_sword_lives_in_equipment_json() -> void:
	assert_true(EquipmentSystem.weapons.has("returned_sword"),
		"returned_sword must be authored in equipment.json weapons")
	var w: Dictionary = EquipmentSystem.weapons["returned_sword"]
	assert_eq(str(w.get("weapon_type", "")), "sword")
	assert_eq(int(w.get("stat_mods", {}).get("attack", 0)), 14,
		"story spec: 'good ATK' — 14 sits between iron 12 and flame 18")
	var se: Dictionary = w.get("special_effects", {})
	assert_true(se.has("familiar_weight_bonus"),
		"Familiar Weight bonus must be authored under special_effects for _sum_equipment_special_effect")
	assert_almost_eq(float(se["familiar_weight_bonus"]), 0.10, 0.001,
		"+10% is the intent from the items.json description")


func test_equip_weapon_accepts_returned_sword() -> void:
	var pc := _combatant("Hero")
	var ok: bool = EquipmentSystem.equip_weapon(pc, "returned_sword")
	assert_true(ok, "equip_weapon must accept the id — pre-promotion, this failed")
	assert_eq(str(pc.equipped_weapon), "returned_sword")
	pc.free()


## ── Damage scaling ──────────────────────────────────────────────────────

func test_no_bonus_when_sword_not_equipped() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "iron_sword")
	var target := _combatant("Slime")
	target.set_meta("monster_type", "slime")
	BestiarySystem.mark_seen("slime")
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 100), 100,
		"iron_sword owner gets baseline damage — no familiar weight effect")
	attacker.free(); target.free()


func test_no_bonus_when_target_unseen() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "returned_sword")
	var target := _combatant("Unseen")
	target.set_meta("monster_type", "__test_never_seen_monster_zzz")
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 100), 100,
		"sword equipped but target unseen → no bonus")
	attacker.free(); target.free()


func test_bonus_applies_when_target_seen() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "returned_sword")
	var target := _combatant("Slime")
	target.set_meta("monster_type", "slime")
	BestiarySystem.mark_seen("slime")
	# 100 * 1.10 = 110
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 100), 110,
		"seen target → +10% (rounded)")
	attacker.free(); target.free()


func test_bonus_applies_when_target_previously_defeated() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "returned_sword")
	var target := _combatant("CaveRat")
	target.set_meta("monster_type", "cave_rat")
	BestiarySystem.mark_defeated("cave_rat")
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 100), 110,
		"defeated implies seen — bonus still applies")
	attacker.free(); target.free()


func test_rounds_bonus() -> void:
	# 55 * 1.10 = 60.5 → round to 61
	var bm := _bm()
	var attacker := _combatant("Hero", "returned_sword")
	var target := _combatant("Slime")
	target.set_meta("monster_type", "slime")
	BestiarySystem.mark_seen("slime")
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 55), 61)
	attacker.free(); target.free()


## ── Wiring guard ─────────────────────────────────────────────────────────

func test_bonus_is_called_from_both_damage_sites() -> void:
	# Cheap textual pin: both the basic-melee resolution (near the
	# pattern_recognition call) and the physical-ability path (after
	# _apply_counter_repeated_damage_mod) must invoke the new helper,
	# else weapons with special_effects.familiar_weight_bonus become
	# silent-noop for ability damage. If either site drops out during
	# refactor, this test loudly complains.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var count: int = src.count("_apply_familiar_weight_bonus(")
	assert_gte(count, 3,
		"expected the helper's definition + 2 call sites (basic + physical ability); found %d" % count)
