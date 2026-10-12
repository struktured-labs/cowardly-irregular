extends GutTest
## Between grind battles, EVERY damaged member drank a potion: the gate was `current_hp < max_hp`,
## so one point of chip damage spent an item. Measured on a real grind: seven starting consumables
## gone by battle 2-3, which ended sessions on the item_depleted safety rule rather than on play.
## The MP line directly below both call sites has always gated at 0.5; HP now matches it.
## struktured's ruling, 2026-10-12: heal below 50%.
const GAMELOOP := "res://src/GameLoop.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

var _gl: Node


func before_each() -> void:
	_gl = load(GAMELOOP).new()
	add_child_autofree(_gl)


## The predicate does not exist on the unfixed tree, and calling a missing method ABORTS the arm --
## which scores Risky, not Failed. A sentinel keeps every arm reporting against both trees.
func _drinks(m) -> Variant:
	if not _gl.has_method("_autogrind_should_drink"):
		return "<no predicate>"
	return _gl._autogrind_should_drink(m)


func _member(hp: int, max_hp: int, alive: bool = true) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.initialize({"name": "Tester", "max_hp": max_hp, "max_mp": 10})
	c.current_hp = hp
	c.is_alive = alive
	return c


func test_a_scratch_does_not_cost_an_item() -> void:
	assert_eq(_drinks(_member(99, 100)), false,
		"one point of chip damage must not spend a potion -- this is what drained seven items by battle 3")
	assert_eq(_drinks(_member(50, 100)), false,
		"exactly half is not below half, so it must not drink yet")


func test_a_hurt_member_still_drinks() -> void:
	assert_eq(_drinks(_member(49, 100)), true,
		"below half must still heal, or the grind walks into the next fight wounded")
	assert_eq(_drinks(_member(1, 100)), true,
		"and a nearly-dead member certainly must")


## CONTROL: the gate must not simply always refuse, which would pass the arm above it.
func test_a_full_member_never_drinks() -> void:
	assert_eq(_drinks(_member(100, 100)), false,
		"CONTROL: nothing to heal")


func test_the_dead_and_the_malformed_are_skipped() -> void:
	assert_eq(_drinks(_member(0, 100, false)), false,
		"a KO'd member is revived, not topped up")
	assert_eq(_drinks(_member(0, 0)), false,
		"a zero-max member must not divide its way into a heal")
	assert_eq(_drinks(null), false,
		"and a null must be refused rather than crash the post-battle loop")


## Both post-battle loops are the sibling pair this rule must not drift across -- the whole defect
## class I fixed twice today is one path getting a rule its twin did not.
func test_both_post_battle_loops_ask_the_same_question() -> void:
	## CODE only: a count over raw source counts PROSE. A comment naming either literal would supply
	## a call site that does not exist, or an old gate that is not there -- and the first direction
	## is a false GREEN on the arm that pins both loops to the shared predicate.
	var src: String = GdSource.code_of(GAMELOOP)
	assert_gt(src.length(), 1000, "FLOOR: GameLoop must be readable")
	assert_true(src.contains("func _autogrind_should_drink("),
		"CONTROL: over-stripping and a correct strip are the same green, so a known code site must survive")
	assert_eq(src.count("_autogrind_should_drink(member)"), 2,
		"both post-battle heal loops must go through the shared predicate")
	assert_eq(src.count("current_hp < member.max_hp:"), 0,
		"and neither may keep the old any-damage gate")
