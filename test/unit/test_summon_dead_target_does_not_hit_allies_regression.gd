extends GutTest

## A queued eidolon keeps the enemy list from the moment it was chosen. CTB then
## lets faster allies kill someone on that list before the summon resolves.
## _execute_ability only retargets "physical" and "magic" onto a living foe. A
## summon fell through to the ally retarget, which replaces a dead foe with the
## most wounded party member. Summon Ifrit (3.0x, all enemies, 30 MP) then
## burned that ally, and a field that was already wiped burned the party instead
## of fizzling. The Summoner unlocks when chapter 3 completes — the Rat King —
## so this is a normal W1 cast, not a debug job.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _caster() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Eidolon Caller"
	c.max_hp = 500
	c.current_hp = 500
	c.max_mp = 80
	c.current_mp = 80
	c.magic = 80
	c.job = {"id": "summoner", "abilities": ["summon_ifrit"]}
	_bm.player_party.append(c)
	return c


func _foe(display_name: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = display_name
	c.max_hp = 4000
	c.current_hp = 4000 if alive else 0
	c.is_alive = alive
	_bm.enemy_party.append(c)
	return c


func test_a_dead_foe_on_a_queued_summon_is_not_replaced_by_an_ally() -> void:
	var caster := _caster()
	var gone := _foe("Gone Slime", false)
	var still := _foe("Still Slime", true)
	_bm._execute_ability(caster, "summon_ifrit", [gone, still])
	assert_eq(caster.current_hp, 500,
		"Ifrit must not burn the summoner — a foe who died before the cast resolves is replaced by another foe, the way a queued fire spell already is")
	assert_lt(still.current_hp, 4000,
		"CONTROL: the eidolon still hits the enemy who is actually there")


func test_a_summon_with_no_living_foe_fizzles_instead_of_hitting_the_party() -> void:
	var caster := _caster()
	var gone := _foe("Gone Slime", false)
	var also := _foe("Also Gone", false)
	var log: Array = []
	_bm.battle_log_message.connect(func(msg): log.append(str(msg)))
	_bm._execute_ability(caster, "summon_ifrit", [gone, also])
	assert_eq(caster.current_hp, 500,
		"a wiped field must not turn the eidolon around onto the party")
	assert_eq(caster.current_mp, 80,
		"the cast fizzles before it is paid for, same as a fire spell with nobody left to hit")
	assert_string_contains("".join(log), "fizzles",
		"and the log says why the turn did nothing")
