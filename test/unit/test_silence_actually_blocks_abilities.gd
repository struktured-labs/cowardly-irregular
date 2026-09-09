extends GutTest

## The "silence" status blocked nothing — including Mordaine's Void Pulse and Umbraxis's Null Field.
##
## Tick 382 wired null_field's ability_silence effect to the existing "silence" status, reasoning:
## "Multiple downstream consumers already gate offensive actions on has_status(\"silence\")
## (e.g. cast path at line ~2834, magic-ability path)". Measured: that string occurs exactly twice
## in the whole repo — inside that comment, and inside the regression test that quotes the comment.
## No consumer has ever existed. `pacify` is the status that actually gates (3 sites); silence had
## an icon, a colour, a sound cue, a cleanse entry and no effect.
##
## Who was casting it into the void: null_field on shadow_dragon (Umbraxis, "suppresses all
## abilities for one turn") and void_pulse on chancellor_mordaine — the W1 FINAL BOSS — plus
## the_calibrant, castle_warden, null_entity and cartographer_wraith, at a 50% chance on all_enemies.
## The random-debuff pool can roll it too (corrupting_touch, data_corruption).
##
## Gated in JobSystem.can_use_ability so execution, the autobattle path and the MRU command slot all
## read one predicate rather than three that can drift. Basic Attack is deliberately untouched — a
## silenced party is pressured, never stuck.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null
var _log: Array = []

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_log = []
	_bm.battle_log_message.connect(func(m): _log.append(str(m)))

func _caster() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mira"
	c.magic = 100
	c.attack = 100
	c.max_mp = 999
	c.current_mp = 999
	c.max_hp = 500
	c.current_hp = 500
	c.job = {"id": "mage", "abilities": ["fire", "blizzard"]}
	return c

func _victim() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Target"
	c.max_hp = 100000
	c.current_hp = 100000
	c.defense = 10
	c.magic_defense = 10
	return c

func test_a_silenced_caster_cannot_use_an_ability_it_knows() -> void:
	var c := _caster()
	assert_true(JobSystem.can_use_ability(c, "fire"), "CONTROL: unsilenced, the mage can cast Fire")
	c.add_status("silence", 1)
	assert_false(JobSystem.can_use_ability(c, "fire"),
		"silence must block the ability — every consumer the tick-382 comment cited was imaginary")

func test_the_cast_deals_no_damage_while_silenced() -> void:
	## The predicate is only half of it: _execute_ability has to honour it, or the menu greys out
	## a spell the AI and the rule engine still fire.
	var c := _caster()
	var target := _victim()
	_bm.enemy_party.append(target)
	c.add_status("silence", 1)
	_bm._execute_ability(c, "fire", [target])
	assert_eq(target.current_hp, target.max_hp,
		"a silenced cast must not land — this is the surface a player actually sees")

func test_an_unsilenced_cast_still_lands() -> void:
	var c := _caster()
	var target := _victim()
	_bm.enemy_party.append(target)
	_bm._execute_ability(c, "fire", [target])
	assert_lt(target.current_hp, target.max_hp,
		"CONTROL: the same call damages when the status is absent — the gate is the status, not the fixture")

func test_the_player_is_told_why() -> void:
	var c := _caster()
	var target := _victim()
	_bm.enemy_party.append(target)
	c.add_status("silence", 1)
	_bm._execute_ability(c, "fire", [target])
	assert_string_contains("".join(_log), "silenced",
		"a bare \"can't use that right now\" reads as a bug when the cause is a boss debuff")

func test_the_basic_attack_survives() -> void:
	## Silence pressures, it does not stun. If Attack were blocked too, a silenced party would have
	## no legal action at all and the fight would read as broken.
	## Swings repeatedly on purpose: the basic attack carries a ~10%% miss roll, so a single call
	## makes this test fail one run in ten. Caught by a mutation arm that failed for the WRONG
	## reason — the arm did not touch _execute_attack, and the RNG stream differed between runs.
	var c := _caster()
	var target := _victim()
	_bm.enemy_party.append(target)
	c.add_status("silence", 1)
	for _i in 6:
		_bm._execute_attack(c, target)
	assert_lt(target.current_hp, target.max_hp, "a silenced character can still swing")

func test_silence_wears_off() -> void:
	var c := _caster()
	c.add_status("silence", 1)
	assert_false(JobSystem.can_use_ability(c, "fire"), "CONTROL: blocked while the status holds")
	c.remove_status("silence")
	assert_true(JobSystem.can_use_ability(c, "fire"),
		"and castable again once it lifts — a permanent block would be worse than none")

func test_the_bosses_that_cast_it_still_do() -> void:
	## Pins the blast radius this repairs. If a rebalance retires these, the guard should be
	## revisited rather than quietly defending nothing.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	var mons: Dictionary = (parsed as Dictionary).get("monsters", parsed)
	assert_true("null_field" in (mons["shadow_dragon"].get("abilities", []) as Array),
		"Umbraxis still casts Null Field")
	assert_true("void_pulse" in (mons["chancellor_mordaine"].get("abilities", []) as Array),
		"Mordaine still casts Void Pulse")
