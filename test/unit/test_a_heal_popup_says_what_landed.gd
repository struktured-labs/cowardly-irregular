extends GutTest

## ⛔ THE GREEN NUMBER WAS WHAT WAS ASKED FOR, NOT WHAT ARRIVED. `Combatant.heal()` returns the amount
## that actually landed — it clamps at max_hp, HALVES under curse, and returns 0 for the dead — and
## two sites emitted the REQUEST instead:
##
##   Four Heroes formation   heals the party 25% and floated "+250 HP!" over a member who gained 100
##   magic drain             drain_percentage, same shape, on every drain spell in the game
##
## The curse case is the one that matters beyond cosmetics: halved healing is a real mechanic and the
## floating number was the player's ONLY evidence of it. It read as if curse did nothing.
##
## Found by running the reverse twin-path sweep a second time — the grind's `_drain_to` has logged
## `heal()`'s RETURN since it was written, and live logged the request. Two other live sites already
## do it correctly (the regen arm and the passive heal), so this was two stragglers rather than a
## convention.
##
## ⚠️ THE REVIVE SITES ARE NOT THIS BUG and must not be "fixed": `healing_done.emit(target,
## target.current_hp)` is correct there, because a revived combatant goes from 0 to current_hp, so
## current_hp IS the amount healed. One of them documents that in place.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"

var _saved_party: Array
var _saved_enemies: Array
var _saved_persist: bool


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	seed(20260916)


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _combatant(name: String, hp: int, cur: int = -1) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.max_hp = hp
	c.current_hp = cur if cur >= 0 else hp
	c.attack = 120
	c.magic = 120
	c.defense = 0
	c.is_alive = true
	return c


## The drain cast, with every healing_done payload it emitted.
func _drain_and_watch(caster: Combatant, target: Combatant) -> Array:
	var seen: Array = []
	var tap := func(who: Combatant, amount: int) -> void:
		if who == caster:
			seen.append(amount)
	BattleManager.healing_done.connect(tap)
	BattleManager.player_party.assign([caster] as Array[Combatant])
	BattleManager.enemy_party.assign([target] as Array[Combatant])
	BattleManager._execute_magic_ability(caster, {
		"type": "magic", "drain_percentage": 50.0, "damage_multiplier": 3.0, "power": 3.0,
	}, [target])
	BattleManager.healing_done.disconnect(tap)
	return seen


func test_a_full_hp_drainer_is_not_told_it_healed() -> void:
	var caster := _combatant("Mira", 600)
	var target := _combatant("Goblin", 99999)
	assert_eq(caster.current_hp, caster.max_hp, "CONTROL: the caster has no room to heal")
	var seen: Array = _drain_and_watch(caster, target)
	assert_eq(seen, [], "a drain that healed nothing must float nothing: %s" % str(seen))


func test_a_wounded_drainer_is_told_what_it_got() -> void:
	## Anti-vacuity: the guard must gate on what LANDED, not suppress the popup.
	var caster := _combatant("Mira", 600, 100)
	var target := _combatant("Goblin", 99999)
	var before: int = caster.current_hp
	var seen: Array = _drain_and_watch(caster, target)
	assert_eq(seen.size(), 1, "one popup for one drain: %s" % str(seen))
	assert_eq(int(seen[0]), caster.current_hp - before,
		"and the number is exactly the HP that arrived")


func test_a_cursed_drainer_is_told_the_halved_amount() -> void:
	## The case that is more than cosmetic: curse halves healing, and this number was the player's
	## only evidence the curse was doing anything at all.
	var caster := _combatant("Mira", 900, 100)
	caster.add_status("curse", 3)
	var target := _combatant("Goblin", 99999)
	var before: int = caster.current_hp
	var seen: Array = _drain_and_watch(caster, target)
	assert_eq(seen.size(), 1, "the cursed drainer still gets a popup: %s" % str(seen))
	assert_eq(int(seen[0]), caster.current_hp - before,
		"showing the HALVED amount that actually landed, not the amount the spell asked for")


func test_no_site_emits_a_requested_heal_instead_of_a_returned_one() -> void:
	## Source-side, because the two behavioural arms above drive ONE of the two sites. The formation
	## special needs a full four-member group attack to reach, which these fixtures cannot build.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	## ⚠️ MY FIRST VERSION OF THIS ARM CHECKED A NAME, NOT A PROPERTY. It asserted the absence of
	## `healing_done.emit(caster, drained)` — and the FIXED code still contains that exact string,
	## because `drained` is now heal()'s return rather than the request. The arm red on correct code
	## and would have stayed green on the bug had I named the new variable anything else. What decides
	## it is the ASSIGNMENT, so that is what these pin.
	assert_true(code.contains("var healed: int = p.heal(heal_amount)"),
		"Four Heroes captures heal()'s return")
	assert_false(code.contains("healing_done.emit(p, heal_amount)"),
		"and does not emit the 25% it asked for")
	assert_true(code.contains("var drained: int = caster.heal("),
		"the drain captures heal()'s return rather than computing the request and discarding it")
	assert_false(code.contains("caster.heal(drained)"),
		"the pre-fix shape — compute the request, heal with it, emit the request — stays gone")
	## The revive sites are CORRECT and this arm must not drift into breaking them.
	assert_eq(code.count("healing_done.emit(target, target.current_hp)"), 2,
		"the two REVIVE emits stay as they are — a revived combatant goes 0 -> current_hp, so current_hp IS the heal")
