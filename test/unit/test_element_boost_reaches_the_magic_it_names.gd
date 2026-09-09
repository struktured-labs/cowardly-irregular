extends GutTest

## Pyrroth's Inferno Rage bought a stat its own kit does not read.
##
## The ability authors effect=attack_up + stat_modifier=2.0 + element_boost="fire", and its
## description promises "massively boosting fire attacks". Magic damage reads
## get_buffed_stat("magic", …); the buff was applied to "attack". Pyrroth's kit is 4 magic + 1
## physical, so the W1 fire dragon spent a turn on a buff that touched exactly one of its five
## abilities — and element_boost had ZERO readers anywhere in src/.
##
## This is the SAME defect already fixed on the lightning dragon: BattleManager's own comment on
## Voltharion's Storm Gathering says "Voltharion's kit is 4/5 magic — without this the telegraph
## never lands." One dragon got carried across; the other did not.
##
## ⚠️ The 2.0 is NOT the boost. It was authored for an attack buff nothing read, so it was never
## balanced as a magic multiplier — reviving a dormant branch is what finally tests the numbers it
## preserved. element_boost_modifier (1.5) is the tunable, falling back to stat_modifier when a
## future ability authors only one.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _abilities() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return (parsed as Dictionary).get("abilities", parsed)

func _dragon() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Pyrroth"
	c.magic = 200
	c.attack = 200
	c.max_mp = 999
	c.current_mp = 999
	c.max_hp = 5000
	c.current_hp = 5000
	c.job = {"id": "fire_dragon", "abilities": ["inferno_rage", "fire_breath"]}
	return c

func _victim(hp: int = 100000) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Party Member"
	c.max_hp = hp
	c.current_hp = hp
	c.defense = 10
	c.magic_defense = 10
	return c

## Damage a fresh victim takes from one fire_breath, with the dragon buffed or not.
func _breath_damage(buff_first: bool) -> int:
	var dragon := _dragon()
	var target := _victim()
	_bm.player_party.append(target)
	if buff_first:
		_bm._execute_support_ability(dragon, _abilities()["inferno_rage"], [dragon])
	_bm._execute_magic_ability(dragon, _abilities()["fire_breath"], [target])
	return target.max_hp - target.current_hp

func test_the_boost_reaches_the_dragons_actual_damage() -> void:
	var plain := _breath_damage(false)
	var raging := _breath_damage(true)
	assert_gt(plain, 0, "CONTROL: an unbuffed fire_breath already lands damage")
	assert_gt(raging, plain,
		"Inferno Rage must raise the fire magic it names — plain %d vs raging %d" % [plain, raging])

## Same probe, but with the boost forced to whatever value the caller names.
func _breath_damage_at(elem_mult: float) -> int:
	var dragon := _dragon()
	var target := _victim()
	_bm.player_party.append(target)
	var rage: Dictionary = (_abilities()["inferno_rage"] as Dictionary).duplicate(true)
	rage["element_boost_modifier"] = elem_mult
	_bm._execute_support_ability(dragon, rage, [dragon])
	_bm._execute_magic_ability(dragon, _abilities()["fire_breath"], [target])
	return target.max_hp - target.current_hp

func test_the_multiplier_is_the_authored_one_not_the_attack_buff() -> void:
	## Guards the reason element_boost_modifier is a separate key: falling back to stat_modifier
	## would hit for 2.0x, which nothing has playtested. Damage is NOT linear in the multiplier —
	## the defense divisor bends it — so this brackets the outcome instead of asserting a ratio.
	var ab: Dictionary = _abilities()["inferno_rage"]
	var plain := _breath_damage(false)
	var authored := _breath_damage(true)
	var as_stat_modifier := _breath_damage_at(float(ab["stat_modifier"]))
	assert_gt(authored, plain, "CONTROL: the authored boost does raise damage")
	assert_lt(authored, as_stat_modifier,
		"the fire multiplier must be element_boost_modifier (%.2f → %d dmg), NOT stat_modifier (%.2f → %d)" % [float(ab["element_boost_modifier"]), authored, float(ab["stat_modifier"]), as_stat_modifier])

func test_the_attack_buff_still_lands_for_the_physical_half() -> void:
	## tail_sweep is the one physical ability in the kit — attack_up was never wrong, only narrow.
	var dragon := _dragon()
	_bm._execute_support_ability(dragon, _abilities()["inferno_rage"], [dragon])
	assert_gt(dragon.get_buffed_stat("attack", dragon.attack), dragon.attack,
		"the attack buff must survive — this fix adds a channel, it does not replace one")

func test_the_boost_does_not_leak_into_another_element() -> void:
	var dragon := _dragon()
	var target := _victim()
	_bm.player_party.append(target)
	_bm._execute_support_ability(dragon, _abilities()["inferno_rage"], [dragon])
	assert_almost_eq(_bm._element_buff_bonus(dragon, "fire"), float(_abilities()["inferno_rage"]["element_boost_modifier"]), 0.001,
		"CONTROL: the named element reads back")
	assert_eq(_bm._element_buff_bonus(dragon, "ice"), 0.0,
		"a fire rage must not boost ice — the buff is keyed on the element, not on 'has a boost'")

func test_an_unboosted_support_ability_grants_nothing() -> void:
	## The discriminator. frost_armor authors no element_boost, so it must add no element channel.
	var dragon := _dragon()
	_bm._execute_support_ability(dragon, _abilities()["frost_armor"], [dragon])
	assert_eq(_bm._element_buff_bonus(dragon, "ice"), 0.0,
		"only element_boost creates the buff — otherwise every support ability would grow one")

func test_the_element_boost_owners_are_still_the_ones_this_was_written_for() -> void:
	var owners: Array = []
	var all_abilities: Dictionary = _abilities()
	for aid in all_abilities:
		if str((all_abilities[aid] as Dictionary).get("element_boost", "")) != "":
			owners.append(aid)
	assert_eq(owners, ["inferno_rage"],
		"a new element_boost author needs its own balance pass, not this one's number: " + str(owners))
