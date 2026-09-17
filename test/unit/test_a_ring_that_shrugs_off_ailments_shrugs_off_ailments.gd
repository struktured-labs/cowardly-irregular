extends GutTest

## ⛔ THE RESIST RING RESISTED NOTHING A PLAYER CAN BE HIT BY. `status_resistance` (resist_ring, 0.3,
## 800 gold, also a chest in Frosthold) had exactly ONE reader: `_apply_equipment_on_hit_status`,
## which is called only from `_execute_attack` and reads the ATTACKER's equipment for the proc
## chance. Monsters author no equipment at all — `equipped_weapon`/`armor`/`accessory` are written
## only by EquipmentSystem and GameLoop, for party members — so the only attacker who can reach that
## reader is the party itself, and the only statuses it gates are poison_dagger and sleep_dagger.
##
## A player wearing the ring was therefore protected against their own two daggers and nothing else.
##
## Every status a player actually suffers arrives by a different route: 65 monster abilities author
## an `effect` on the physical/magic executors (44 magic, 21 physical), which land in
## `_apply_ability_status` — poison, burn, freeze, stun, blind, silence, confuse, doom. That owner
## never read the key. The fix gives it the SAME formula as the on-hit site so there is one.
##
## ⚠️ The tick-461 guard for this key is all source pins plus a bare-attacker runtime arm, and every
## one of them is green on the build where the ring is inert: they are about the HELPER being
## correct, and the helper is correct. The arms below are about a PLAYER being afflicted.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"
const RING := "resist_ring"

var _saved_party: Array
var _saved_enemies: Array


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	seed(20260916)


func after_each() -> void:
	## Restore process-wide randomness — GUT runs every file in one process and a seeded stream
	## left behind turns a later probabilistic arm deterministic, order-dependently.
	randomize()
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _combatant(name_str: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name_str
	c.max_hp = 999999
	c.current_hp = 999999
	c.attack = 10
	c.magic = 10
	c.defense = 0
	c.is_alive = true
	return c


## A monster ability that inflicts `stun` at the authored chance. clipboard_smack and smash both
## author 0.2, crystal_slam and tail_sweep 0.25 — all under the ring's 0.3.
func _monster_ability(type: String, chance: float) -> Dictionary:
	return {"type": type, "effect": "stun", "effect_chance": chance, "duration": 3,
		"damage_multiplier": 0.1, "power": 0.1}


## Casts `ability` at one party member `runs` times and returns how often the stun landed.
## The victim's HP is huge and the multiplier tiny, so nobody dies and the apply is always reached.
func _times_afflicted(accessory: String, ability: Dictionary, runs: int) -> int:
	var monster := _combatant("Rat")
	var victim := _combatant("Mira")
	victim.equipped_accessory = accessory
	BattleManager.enemy_party.assign([monster] as Array[Combatant])
	BattleManager.player_party.assign([victim] as Array[Combatant])
	var landed: int = 0
	for _i in range(runs):
		victim.remove_status("stun")
		if str(ability.get("type", "")) == "magic":
			BattleManager._execute_magic_ability(monster, ability, [victim])
		else:
			BattleManager._execute_physical_ability(monster, ability, [victim])
		if victim.has_status("stun"):
			landed += 1
	assert_true(victim.is_alive, "CONTROL: the fixture survives every hit, so each run reached the status apply")
	return landed


func test_the_ring_shrugs_off_an_ailment_the_player_is_actually_hit_by() -> void:
	## The shipped case: a 0.25 stun against 0.3 of resistance is shrugged off entirely.
	for type in ["physical", "magic"]:
		var ability := _monster_ability(type, 0.25)
		var without: int = _times_afflicted("", ability, 40)
		assert_gt(without, 0,
			"CONTROL: %s — an unprotected party member IS stunned by this, or the arm is about nothing" % type)
		var with_ring: int = _times_afflicted(RING, ability, 40)
		assert_eq(with_ring, 0,
			"%s: the Resist Ring must shrug off a 0.25 ailment (0.25 - 0.30 clamps to 0)" % type)


func test_the_ring_is_a_reduction_and_not_an_immunity() -> void:
	## Anti-vacuity in the expensive direction: the fix must not turn one accessory into blanket
	## immunity. A certain affliction stays likely — 0.7 — so it both lands and fails across a run.
	var certain := _monster_ability("physical", 1.0)
	var landed: int = _times_afflicted(RING, certain, 200)
	assert_gt(landed, 0, "a 1.0 ailment must still land through the ring (0.70 remains)")
	assert_lt(landed, 200, "and must not land every time, or the resist is not being subtracted")


func test_an_unringed_target_is_unchanged() -> void:
	## The other anti-vacuity: nothing about the ordinary path moved. A monster wears no accessory,
	## so the party's own certain ailments still land every single time.
	var certain := _monster_ability("physical", 1.0)
	var landed: int = _times_afflicted("", certain, 40)
	assert_eq(landed, 40, "a certain ailment against an unprotected target still always lands")


func test_monsters_carry_no_equipment_which_is_why_the_old_reader_was_unreachable() -> void:
	## The precondition the tick-461 guard never stated, and the reason its green was honest and
	## uninformative. Two halves: monsters author no equipment slot, and the reader walks only
	## equipment slots. crystal_golem authors a `special_effects` block of its own
	## (magic_reflect_chance) — a different mechanism, and NOT one this reader can reach.
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	for key in ["equipped_weapon", "equipped_armor", "equipped_accessory"]:
		assert_false(raw.contains("\"%s\"" % key),
			"monsters.json must not author %s — the on-hit reader keys off the ATTACKER's equipment" % key)
	var src: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = src.find("func _sum_equipment_special_effect(")
	assert_gt(at, -1, "CONTROL: the reader survives stripping")
	var body: String = src.substr(at, src.find("\nfunc ", at + 1) - at)
	for slot in ["equipped_weapon", "equipped_armor", "equipped_accessory"]:
		assert_true(body.contains(slot),
			"the reader must walk %s — that is what makes it unreachable for a monster attacker" % slot)
	assert_false(body.contains("monster_database"),
		"and must not read a monster's own special_effects, or the precondition above stops holding")


func test_both_status_sites_share_one_resistance_formula() -> void:
	## Two sites subtract this key now. Pinned together so a later rebalance cannot move one and
	## leave the game with two different meanings for one authored number.
	var src: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = src.find("func _apply_ability_status(")
	assert_gt(at, -1, "CONTROL: the ability owner survives stripping")
	var body: String = src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("_sum_equipment_special_effect(target, \"status_resistance\")"),
		"the ability status owner must consult the TARGET's status_resistance")
	assert_true(body.contains("clampf(effect_chance - resist, 0.0, 1.0)"),
		"and subtract it with the same clamped formula the on-hit site uses")
	var on_hit: int = src.find("func _apply_equipment_on_hit_status(")
	assert_gt(on_hit, -1, "CONTROL: the on-hit site survives stripping")
	var on_hit_body: String = src.substr(on_hit, src.find("\nfunc ", on_hit + 1) - on_hit)
	assert_true(on_hit_body.contains("clampf(chance - resist, 0.0, 1.0)"),
		"the on-hit site keeps its formula, or the two have drifted apart again")
