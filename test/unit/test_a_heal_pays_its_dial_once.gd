extends GutTest

## ⛔ ONE DIAL, TWO MULTIPLICATIONS. `healing_multiplier` is the Scriptweaver's flagship promise —
## `_execute_meta_ability`'s `constant_modification` arm turns it +/-10%, clamped [0.5, 2.0]. Exactly
## two places consume it, and on a healing SPELL they run in series on the same cast:
##
##   BattleManager._execute_healing_ability   int(heal_amount * GameState.get_constant(...))  UNCLAMPED
##   Combatant.heal()                         int(h * clampf(game_constants[...], 0.1, 10.0))
##
## So the dial is SQUARED for a spell and applied ONCE for a potion (items call heal() directly).
## A Scriptweaver who nudges it to 1.1 gets +21% on Cure and +10% on a Potion, and the ability's own
## battle-log line quotes the number it moved, not the number it delivered.
##
## ⛔ AND THE UNCLAMPED READ DEFEATS THE CLAMP THE SECOND READ EXISTS FOR. `heal()`'s comment says the
## [0.1, 10.0] band is there "so a broken passive can't black-hole or runaway healing"; a factor of
## 100 applied outside that band and 10 inside it is 1000x, which is the runaway the band names.
##
## ⛔ AND THE MENU QUOTES NEITHER FACTOR. `BattleCommandMenu._build_ability_menu_item` renders
## " ~+%d" from `heal_amount * (1 + magic/20)` alone — no dial, no `healing_boost` passive (+50%, on
## the RECEIVER, which is where heal() reads passives), no curse (-50%). The caption lens again: a
## surface describing a computation it did not perform.
##
## Every arm is BEHAVIOURAL — it casts and reads the HP that arrived. `int(x * mult)` was one refactor
## away from any source pattern; "what did the target actually receive" survives every rewrite.

const MENU := preload("res://src/battle/BattleCommandMenu.gd")
const HEAL_ABILITY := "cure"
const DIAL := "healing_multiplier"


## The single_ally branch reads exactly these two members off the scene and nothing else, so a live
## BattleScene would add a viewport and a sprite tree to measure a string with.
class FakeScene extends RefCounted:
	var party_members: Array = []
	var party_sprite_nodes: Array = []


var _saved_dial: float = 1.0


func before_each() -> void:
	_saved_dial = float(GameState.game_constants.get(DIAL, 1.0))


func after_each() -> void:
	GameState.game_constants[DIAL] = _saved_dial


func _combatant(magic_stat: int, max_hp_v: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Mender", "max_hp": max_hp_v, "max_mp": 999,
		"attack": 10, "defense": 10, "magic": magic_stat, "speed": 10})
	## In the tree deliberately: heal() reads game_constants through `get_tree()` and PassiveSystem
	## through `has_node`, and both are skipped outright for a Combatant that is not inside one.
	add_child_autofree(c)
	return c


## What the target actually received. Called through a helper so that if a later branch of the
## executor aborts, the abort dies in ITS frame and the HP delta is already banked.
func _delivered(caster: Combatant, target: Combatant, ability: Dictionary) -> int:
	target.current_hp = 1
	BattleManager._execute_healing_ability(caster, ability, [target])
	return target.current_hp - 1


## The " ~+N" a player reads off the row, or -1 if the row carried no quote at all.
func _quoted(caster: Combatant, target: Combatant) -> int:
	var scene := FakeScene.new()
	scene.party_members = [target]
	var menu = MENU.new(scene)
	var item: Dictionary = menu._build_ability_menu_item(
		HEAL_ABILITY, caster, [] as Array[Combatant], Transform2D.IDENTITY)
	var sub: Array = item.get("submenu", [])
	if sub.is_empty():
		return -1
	var label: String = str((sub[0] as Dictionary).get("label", ""))
	if not label.contains("~+"):
		return -1
	return label.split("~+")[1].to_int()


func test_the_dial_and_a_quoting_heal_exist_to_measure_with() -> void:
	assert_true(GameState.game_constants.has(DIAL),
		"CONTROL: %s must be a real game constant, or every arm here moves a key nothing reads" % DIAL)
	var ability: Dictionary = JobSystem.get_ability(HEAL_ABILITY)
	assert_false(ability.is_empty(),
		"CONTROL: %s must resolve, or the menu arm builds an empty item and compares -1 to 0" % HEAL_ABILITY)
	assert_gt(int(ability.get("heal_amount", 0)), 0,
		"CONTROL: %s must author a positive heal_amount, or the quote and the delivery are both 0" % HEAL_ABILITY)
	assert_eq(str(ability.get("target_type", "")), "single_ally",
		"CONTROL: %s must route to the menu's single_ally branch — that is the branch that quotes" % HEAL_ABILITY)


func test_doubling_the_dial_doubles_the_heal() -> void:
	var caster := _combatant(20, 100)
	var target := _combatant(0, 100000000)
	var ability := {"type": "healing", "heal_amount": 100}
	GameState.game_constants[DIAL] = 1.0
	var d1: int = _delivered(caster, target, ability)
	GameState.game_constants[DIAL] = 2.0
	var d2: int = _delivered(caster, target, ability)
	assert_gt(d1, 0,
		"CONTROL: the undialed heal must land, or the comparison below is 0 against 0")
	assert_eq(d2, d1 * 2,
		("a dial of 2.0 must double a heal, not square it — a potion at this dial heals 2x because "
		+ "ItemSystem calls Combatant.heal() once. The spell path multiplies in "
		+ "_execute_healing_ability AND again inside heal(): %d vs the %d a doubled heal is")
		% [d2, d1 * 2])


func test_past_the_clamp_ceiling_the_dial_stops_mattering() -> void:
	var caster := _combatant(20, 100)
	var target := _combatant(0, 100000000)
	var ability := {"type": "healing", "heal_amount": 100}
	GameState.game_constants[DIAL] = 10.0
	var at_ceiling: int = _delivered(caster, target, ability)
	GameState.game_constants[DIAL] = 100.0
	var past_ceiling: int = _delivered(caster, target, ability)
	assert_gt(at_ceiling, 0,
		"CONTROL: the heal at the clamp ceiling must land, or both sides are 0 and agree vacuously")
	assert_eq(past_ceiling, at_ceiling,
		("heal() clamps the dial to [0.1, 10.0] so a runaway value cannot run away. A second read "
		+ "OUTSIDE that clamp reinstates exactly what it forbids: %d at a dial of 100 against %d at "
		+ "the ceiling of 10") % [past_ceiling, at_ceiling])


func test_the_row_quotes_what_the_cast_will_deliver() -> void:
	var ability: Dictionary = JobSystem.get_ability(HEAL_ABILITY)
	if ability.is_empty():
		pending("needs the %s ability; the control arm reports why" % HEAL_ABILITY)
		return
	var caster := _combatant(20, 100)
	var target := _combatant(0, 100000000)
	## Each row names a factor the engine applies to a heal. The first is the positive control: with
	## every factor at identity the quote and the delivery already agree, so a row that disagrees is
	## naming its own factor rather than a broken parse.
	var rows: Array = [
		{"what": "no factor at all (CONTROL)", "dial": 1.0, "curse": false},
		{"what": "the Scriptweaver dial at 2.0", "dial": 2.0, "curse": false},
		{"what": "a cursed target (heal() halves it)", "dial": 1.0, "curse": true},
		{"what": "the dial AND a curse together", "dial": 2.0, "curse": true},
	]
	var wrong: Array[String] = []
	for row in rows:
		GameState.game_constants[DIAL] = float(row["dial"])
		target.remove_status("curse")
		if bool(row["curse"]):
			target.add_status("curse", 99)
		var quoted: int = _quoted(caster, target)
		var delivered: int = _delivered(caster, target, ability)
		if quoted != delivered:
			wrong.append("%s: the row reads ~+%d, the cast delivers %d" % [row["what"], quoted, delivered])
	target.remove_status("curse")
	assert_eq(wrong, [],
		("the ~+N on an ally row is the only number a player has before committing MP; it must equal "
		+ "what the cast will add. Factors the quote is blind to: %s") % str(wrong))
