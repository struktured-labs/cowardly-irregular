extends GutTest

## cowir-story msg 2158 — returned_sword's Familiar Weight also fires on
## enemies in the sword's OWN static ledger (W1 map-visible roster), not
## just BestiarySystem's seen/defeated set. Union semantics: either half
## qualifies. Description stays silent about the seed so the exploit-
## mindset discovery gradient the story-side wants stays intact.

const BM_PATH: String = "res://src/battle/BattleManager.gd"


func _bm() -> Node:
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


## ── Data spec: the seed is authored + kept out of the description ──────

func test_returned_sword_declares_the_static_seed() -> void:
	var w: Dictionary = EquipmentSystem.weapons.get("returned_sword", {})
	assert_false(w.is_empty(), "returned_sword entry must still exist")
	var seed: Array = w.get("familiar_weight_static_seed", []) as Array
	assert_gt(seed.size(), 0, "static seed must be authored (empty defeats the story-side ask)")
	# The exact set is cowir-story's design intent — pin the W1-visible
	# roster so a future edit is deliberate. Keep-in-sync with msg 2158.
	for expected in ["slime", "bat", "goblin", "wolf", "spider", "cave_skeleton"]:
		assert_true(expected in seed,
			"story-authored W1 seed must include '%s'" % expected)


func test_description_stays_silent_about_the_seed() -> void:
	# cowir-story msg 2158: "Nothing about this to be documented in the
	# description; it's a variant read on inspect." Player has to notice.
	var w: Dictionary = EquipmentSystem.weapons.get("returned_sword", {})
	var desc: String = str(w.get("description", ""))
	assert_false(desc.to_lower().contains("static"),
		"description must not say 'static' / hint at the pre-seed")
	assert_false(desc.to_lower().contains("pre-seed") or desc.to_lower().contains("preseed"),
		"description must not say pre-seed / preseed")


func test_no_other_weapon_carries_a_seed_by_accident() -> void:
	# Guard against a copy-paste that silently gives another weapon the
	# same easter-egg — the flavor belongs to returned_sword alone.
	for wid in EquipmentSystem.weapons:
		if wid == "returned_sword":
			continue
		var w: Dictionary = EquipmentSystem.weapons[wid]
		assert_false(w.has("familiar_weight_static_seed"),
			"weapon '%s' must not carry a static seed (returned_sword only in v1)" % wid)


## ── Runtime: bonus fires on seed hits without a bestiary entry ─────────

func test_bonus_fires_on_seed_hit_with_no_bestiary_entry() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "returned_sword")
	var target := _combatant("Slime")
	target.set_meta("monster_type", "slime")
	# Ensure the party has NOT seen slime — the seed is the only reason
	# the bonus lands. Bestiary counts get pruned across suite runs so we
	# don't need a "mark_unseen"; the seen dict starts empty per-battle-
	# test if _reset was called; anchor via a monster_type unlikely to be
	# marked by any other test.
	target.set_meta("monster_type", "__test_seeded_slime")
	# Add __test_seeded_slime to the sword's seed dynamically so this
	# assertion tests the RUNTIME union, not the shipped catalog data.
	EquipmentSystem.weapons["returned_sword"]["familiar_weight_static_seed"] = ["__test_seeded_slime"]
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 100), 110,
		"unseen but seed-listed target → +10% via the sword's own memory")
	# Restore for other tests
	EquipmentSystem.weapons["returned_sword"]["familiar_weight_static_seed"] = ["slime", "bat", "goblin", "wolf", "spider", "cave_skeleton"]
	attacker.free(); target.free()


func test_bonus_still_fires_on_bestiary_hit_when_seed_misses() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "returned_sword")
	var target := _combatant("SomeMob")
	target.set_meta("monster_type", "__test_seeded_bestiary_only")
	BestiarySystem.mark_seen("__test_seeded_bestiary_only")
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 100), 110,
		"target seen by the party (but NOT in seed) → +10%")
	attacker.free(); target.free()


func test_no_bonus_when_target_is_neither_in_bestiary_nor_seed() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "returned_sword")
	var target := _combatant("Ghost")
	target.set_meta("monster_type", "__test_never_seeded_or_bestiary_zzz")
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 100), 100,
		"unknown to both ledgers → baseline damage (regression guard)")
	attacker.free(); target.free()


func test_no_bonus_when_sword_not_equipped_even_if_target_seeded() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "iron_sword")
	var target := _combatant("Slime")
	target.set_meta("monster_type", "slime")
	BestiarySystem.mark_seen("slime")  # bestiary hit too — must still no-op
	assert_eq(bm._apply_familiar_weight_bonus(attacker, target, 100), 100,
		"seed lives on the sword; without the sword equipped, no bonus")
	attacker.free(); target.free()


## ── Helper contract ─────────────────────────────────────────────────────

func test_static_seed_helper_unions_slots() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "returned_sword")
	var seed: PackedStringArray = bm._familiar_weight_static_seed(attacker)
	assert_true("slime" in seed and "bat" in seed and "cave_skeleton" in seed,
		"the sword's seed shows up in the union")
	attacker.free()


func test_static_seed_helper_is_empty_when_no_seeded_item_equipped() -> void:
	var bm := _bm()
	var attacker := _combatant("Hero", "iron_sword")
	assert_eq(bm._familiar_weight_static_seed(attacker).size(), 0,
		"no seeded item → empty seed union")
	attacker.free()
