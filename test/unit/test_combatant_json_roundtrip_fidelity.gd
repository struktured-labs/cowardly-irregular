extends GutTest

## Field-enumeration roundtrip tests rot: purchased_abilities (item 18's
## shop-investment protection) was serialized but absent from the
## protected-key list, so a to_dict refactor could silently drop it.
## This ratchet closes the whole class: to_dict → JSON string → parse →
## from_dict → to_dict must be IDENTICAL, so any field that fails to
## survive the real save path (typed-array coercion included) fails
## here by name — current fields and every future one.


func _populated_combatant() -> Combatant:
	var c = Combatant.new()
	c.combatant_name = "RoundtripHero"
	c.max_hp = 250
	c.current_hp = 101
	c.max_mp = 80
	c.current_mp = 25
	c.current_ap = 2
	c.attack = 30
	c.defense = 22
	c.magic = 15
	c.speed = 14
	c.job_level = 7
	c.job_exp = 350
	c.equipped_weapon = "iron_sword"
	c.equipped_armor = "leather_armor"
	c.equipped_accessory = "power_ring"
	c.secondary_job_id = "rogue"
	var la: Array[String] = ["slash", "guard"]
	c.learned_abilities = la
	var pa: Array[String] = ["fira"]
	c.purchased_abilities = pa
	var lp: Array[String] = ["weapon_mastery"]
	c.learned_passives = lp
	c.equipped_passives = lp.duplicate()
	var pin: Array[String] = ["cure"]
	c.pinned_abilities = pin
	# no pinned overlap: from_dict enforces the tick-161 "pinned don't pollute MRU" invariant
	var mru: Array[String] = ["fire", "blizzard"]
	c.recent_abilities = mru
	var st: Array[String] = ["poison"]
	c.status_effects = st
	var inj: Array[Dictionary] = [{"stat": "attack", "penalty": 2, "description": "old wound"}]
	c.permanent_injuries = inj
	c.inventory = {"potion": 5, "ether": 2}
	c.doom_counter = -1
	return c


func test_to_dict_json_from_dict_to_dict_is_identity() -> void:
	var a = _populated_combatant()
	autofree(a)
	var d1: Dictionary = a.to_dict()
	# The REAL save path: through a JSON string, so typed-array
	# assignment bugs and int/float drift surface here.
	var parsed = JSON.parse_string(JSON.stringify(d1))
	assert_true(parsed is Dictionary, "roundtrip parse must yield a Dictionary")
	var b = Combatant.new()
	autofree(b)
	b.from_dict(parsed)
	var d2: Dictionary = b.to_dict()
	var diffs: Array = []
	for key in d1:
		if not d2.has(key):
			diffs.append("%s: dropped by from_dict/to_dict" % key)
		elif JSON.stringify(d2[key]) != JSON.stringify(d1[key]):
			diffs.append("%s: %s → %s" % [key, JSON.stringify(d1[key]), JSON.stringify(d2[key])])
	for key in d2:
		if not d1.has(key):
			diffs.append("%s: invented by roundtrip" % key)
	assert_eq(diffs.size(), 0,
		"fields that did not survive save→load: %s" % str(diffs))


func test_purchased_abilities_survive_the_save_path() -> void:
	# The motivating field: shop-bought spells are stripped by the
	# dev-toggle/level-gate logic unless this marker survives saves.
	var a = _populated_combatant()
	autofree(a)
	var b = Combatant.new()
	autofree(b)
	b.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	assert_eq(b.purchased_abilities, ["fira"] as Array[String],
		"purchased_abilities must survive JSON roundtrip or bought spells strip on load")
