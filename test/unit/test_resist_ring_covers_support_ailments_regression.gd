extends GutTest

## The Resist Ring (status_resistance 0.3) already shrugs ailments that ride a hit.
## A wolf's howl and a spider's web are support casts, and those rolls never read the ring,
## so a buyer still gets feared and stunned at the full authored chance.

const RING := "resist_ring"
const RUNS := 40

var _saved_party: Array
var _saved_enemies: Array


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	seed(20260926)


func after_each() -> void:
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
	c.max_mp = 9999
	c.current_mp = 9999
	c.is_alive = true
	return c


func _pair(accessory: String) -> Array:
	var monster := _combatant("Wolf")
	var victim := _combatant("Mira")
	victim.equipped_accessory = accessory
	BattleManager.enemy_party.assign([monster] as Array[Combatant])
	BattleManager.player_party.assign([victim] as Array[Combatant])
	return [monster, victim]


func test_authored_chances_sit_at_or_under_the_ring() -> void:
	var howl: Dictionary = JobSystem.get_ability("howl")
	var web: Dictionary = JobSystem.get_ability("web_shot")
	var ring: Dictionary = EquipmentSystem.get_accessory(RING)
	assert_almost_eq(float(howl.get("secondary_chance", -1.0)), 0.3, 0.001,
		"howl's fear chance must stay at 0.3, which the ring's 0.3 fully shrugs")
	assert_eq(str(howl.get("secondary_effect", "")), "fear")
	assert_almost_eq(float(web.get("secondary_chance", -1.0)), 0.25, 0.001,
		"web_shot's stun chance must stay at 0.25, under the ring")
	assert_eq(str(web.get("secondary_effect", "")), "stun")
	assert_almost_eq(float(ring.get("special_effects", {}).get("status_resistance", -1.0)), 0.3, 0.001,
		"the Resist Ring must still author 0.3 status_resistance")


func test_a_howl_does_not_frighten_someone_wearing_the_ring() -> void:
	var howl: Dictionary = JobSystem.get_ability("howl")
	var bare: int = _secondary_hits("", howl, "fear")
	assert_gt(bare, 0, "CONTROL: an unprotected member is frightened by howl, or this arm is about nothing")
	var guarded: int = _secondary_hits(RING, howl, "fear")
	assert_eq(guarded, 0, "howl's 0.3 fear minus the ring's 0.3 must never land")


func test_a_web_does_not_stun_someone_wearing_the_ring() -> void:
	var web: Dictionary = JobSystem.get_ability("web_shot")
	var bare: int = _secondary_hits("", web, "stun")
	assert_gt(bare, 0, "CONTROL: an unprotected member is stunned by the web")
	var guarded: int = _secondary_hits(RING, web, "stun")
	assert_eq(guarded, 0, "web_shot's 0.25 stun minus the ring's 0.3 must never land")


func test_a_support_ailment_reads_the_ring_too() -> void:
	## The secondary dispatcher is not the only gap. A support stun at 0.25 must shrug as well.
	var ability := {"effect": "stun", "success_rate": 0.25, "duration": 2}
	var bare: int = _support_status_hits("", ability, "stun")
	assert_gt(bare, 0, "CONTROL: a 0.25 support stun lands on an unprotected member")
	var guarded: int = _support_status_hits(RING, ability, "stun")
	assert_eq(guarded, 0, "a support stun at 0.25 must be shrugged by the ring")


func test_a_support_slow_under_the_ring_is_shrugged() -> void:
	var ability := {"effect": "speed_down", "success_rate": 0.2, "stat_modifier": 0.5, "duration": 2}
	var bare: int = _support_debuff_hits("", ability)
	assert_gt(bare, 0, "CONTROL: a 0.2 slow lands on an unprotected member")
	var guarded: int = _support_debuff_hits(RING, ability)
	assert_eq(guarded, 0, "a support slow at 0.2 must be shrugged by the ring")


func test_a_ward_still_lands_through_the_ring() -> void:
	## Barrier shares the simple-status arm with stun. The ring must not eat the player's own wards.
	var ability := {"effect": "barrier", "success_rate": 1.0, "duration": 3}
	var guarded: int = _support_status_hits(RING, ability, "barrier")
	assert_eq(guarded, RUNS, "Barrier is a ward, and the ring must not resist it")


func test_a_grind_howl_respects_the_same_ring() -> void:
	var howl: Dictionary = JobSystem.get_ability("howl")
	var bare: int = _grind_secondary_hits("", howl, "fear")
	assert_gt(bare, 0, "CONTROL: the grind still frightens an unprotected member")
	var guarded: int = _grind_secondary_hits(RING, howl, "fear")
	assert_eq(guarded, 0, "a grinding howl must shrug its fear against the ring")


func test_a_grind_web_slow_is_reduced_by_the_ring() -> void:
	## web_shot's slow is a certain support debuff. With the ring it becomes 0.7, not a guarantee.
	var bare: int = _grind_web_slows("")
	assert_eq(bare, RUNS, "CONTROL: an unringed grind web still always slows")
	var guarded: int = _grind_web_slows(RING)
	assert_gt(guarded, 0, "the ring reduces the slow; it does not make webs harmless")
	assert_lt(guarded, RUNS, "a certain slow must no longer be certain once the ring is worn")


func test_a_grind_hedge_on_a_ringed_ally_lands_at_its_raw_chance() -> void:
	## Hedge Position is volatility_down at 0.5, cast on an ally. Live applies it as a buff.
	## The grind used to resist every modifier below 1.0, so the ring shrugged a friendly hedge.
	var hedge: Dictionary = JobSystem.get_ability("hedge_position")
	assert_eq(str(hedge.get("effect", "")), "volatility_down")
	assert_eq(str(hedge.get("target_type", "")), "single_ally")
	assert_almost_eq(float(hedge.get("stat_modifier", -1.0)), 0.5, 0.001,
		"Hedge Position must still author 0.5, the modifier a magnitude check mistakes for a debuff")
	var raw: float = float(hedge.get("success_rate", 1.0))
	assert_almost_eq(raw, 1.0, 0.001,
		"Hedge Position authors no success_rate, so its raw chance is certain")
	var bare: int = _grind_hedges("")
	assert_eq(bare, RUNS, "CONTROL: an unringed ally is hedged on every cast")
	var guarded: int = _grind_hedges(RING)
	assert_eq(guarded, bare,
		"a ring-wearing ally must be hedged at the raw chance, not chance minus the ring")


func _secondary_hits(accessory: String, ability: Dictionary, status: String) -> int:
	var pair: Array = _pair(accessory)
	var monster: Combatant = pair[0]
	var victim: Combatant = pair[1]
	var landed := 0
	for _i in range(RUNS):
		victim.remove_status(status)
		BattleManager._apply_secondary_effect(monster, ability, [victim])
		if victim.has_status(status):
			landed += 1
	return landed


func _support_status_hits(accessory: String, ability: Dictionary, status: String) -> int:
	var pair: Array = _pair(accessory)
	var monster: Combatant = pair[0]
	var victim: Combatant = pair[1]
	var landed := 0
	for _i in range(RUNS):
		victim.remove_status(status)
		BattleManager._execute_support_ability(monster, ability, [victim])
		if victim.has_status(status):
			landed += 1
	return landed


func _support_debuff_hits(accessory: String, ability: Dictionary) -> int:
	var pair: Array = _pair(accessory)
	var monster: Combatant = pair[0]
	var victim: Combatant = pair[1]
	var landed := 0
	for _i in range(RUNS):
		victim.active_debuffs.clear()
		BattleManager._execute_support_ability(monster, ability, [victim])
		if victim.active_debuffs.size() > 0:
			landed += 1
	return landed


func _grind_secondary_hits(accessory: String, ability: Dictionary, status: String) -> int:
	var monster := _combatant("Wolf")
	var victim := _combatant("Mira")
	victim.equipped_accessory = accessory
	var landed := 0
	for _i in range(RUNS):
		victim.remove_status(status)
		var resolver := HeadlessBattleResolver.new()
		resolver._enemy_party = [monster]
		resolver._player_party = [victim]
		resolver._apply_secondary_effect(monster, ability, [victim], str(ability.get("id", "howl")))
		if victim.has_status(status):
			landed += 1
	return landed


func _grind_web_slows(accessory: String) -> int:
	var spider := _combatant("Spider")
	var victim := _combatant("Mira")
	victim.equipped_accessory = accessory
	var slowed := 0
	for _i in range(RUNS):
		victim.active_debuffs.clear()
		victim.status_effects.clear()
		spider.current_mp = spider.max_mp
		var resolver := HeadlessBattleResolver.new()
		resolver._enemy_party = [spider]
		resolver._player_party = [victim]
		resolver._resolve_ability(spider, "web_shot", [victim])
		if victim.active_debuffs.size() > 0:
			slowed += 1
	return slowed


func _grind_hedges(accessory: String) -> int:
	var caster := _combatant("Speculator")
	var ally := _combatant("Mira")
	ally.equipped_accessory = accessory
	var hedged := 0
	for _i in range(RUNS):
		ally.active_buffs.clear()
		ally.active_debuffs.clear()
		caster.current_mp = caster.max_mp
		var resolver := HeadlessBattleResolver.new()
		resolver._player_party = [caster, ally]
		resolver._enemy_party = []
		resolver._resolve_ability(caster, "hedge_position", [ally])
		if _has_named_mod(ally, "hedge_position"):
			hedged += 1
	return hedged


func _has_named_mod(combatant: Combatant, effect_name: String) -> bool:
	for pool in [combatant.active_buffs, combatant.active_debuffs]:
		for entry in pool:
			if str(entry.get("effect", "")) == effect_name:
				return true
	return false
