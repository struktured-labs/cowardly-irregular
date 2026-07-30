extends GutTest

## Inns were FREE, everywhere, for every world.
##
## Bug shape (the "two sources, one silently wins" class):
##   • VillageInn._rest_party() charges rest_cost and is pinned by
##     test_village_inn_charges_gold_regression — that test is green.
##   • VillageInn.interact() returns EARLY whenever `interior_target != ""`,
##     and interior_target defaults to "inn_interior". No village overrides
##     it, so _rest_party() is dead code in shipped play.
##   • The live path is InnInterior._do_rest(), which restored HP/MP/AP for
##     the whole party and never touched gold.
##   • Every innkeeper in all six worlds quotes the price out loud
##     ("A room is 50 gold a night", "Fifty gold per sleep cycle", ...) —
##     the prose was the only thing enforcing it.
##
## Player-visible: unlimited full heals at zero cost from the first village
## on, and the innkeeper's stated price is a lie.
##
## The pins here drive the REAL InnInterior in the tree, because a source
## pin on the charged path is exactly what was already green while the
## shipped path charged nothing.

const INN_PATH := "res://src/maps/interiors/InnInterior.gd"
const VillageInnRes = preload("res://src/exploration/VillageInn.gd")
const InnInteriorRes = preload("res://src/maps/interiors/InnInterior.gd")
const CombatantRes = preload("res://src/battle/Combatant.gd")

## A Node with a REAL `party` property — Node.set("party", …) only makes
## metadata, and `game_loop.party` would not resolve.
const _STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

var _prior_gold: int = 0


func before_each() -> void:
	_prior_gold = GameState.party_gold


func after_each() -> void:
	GameState.party_gold = _prior_gold


func _make_stub_gameloop(party: Array) -> Node:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	stub.party = party
	get_tree().root.add_child(stub)
	return stub


func _wounded_member() -> Object:
	var c: Object = CombatantRes.new()
	add_child_autofree(c)
	c.max_hp = 1000
	c.current_hp = 1
	c.max_mp = 40
	c.current_mp = 0
	c.is_alive = true
	return c


func _inn_in_tree() -> Node2D:
	var inn: Node2D = load(INN_PATH).new()
	add_child_autofree(inn)
	return inn


# ── The price has ONE source ─────────────────────────────────────────────────

func test_interior_and_outdoor_inn_quote_the_same_price() -> void:
	# Two inn implementations charging two different numbers is how the
	# shipped path drifted away from the pinned one in the first place.
	assert_eq(InnInteriorRes.REST_COST, VillageInnRes.DEFAULT_REST_COST,
		"the interior (live) inn and the outdoor (legacy) inn must read one shared price constant")


func test_rest_prompt_quotes_the_price_it_will_charge() -> void:
	# Derived from the constant at runtime, so the prompt cannot drift from
	# what _do_rest actually deducts.
	var inn := _inn_in_tree()
	inn._show_rest_prompt()
	var label := _find_label_containing(inn._rest_dialog, "Rest until morning")
	assert_not_null(label, "the rest prompt must render its confirm label")
	if label != null:
		assert_true(label.text.contains("%d G" % InnInteriorRes.REST_COST),
			"the confirm prompt must state the price before the player pays it, got: %s" % label.text)


# ── Behavioural: the shipped rest path ───────────────────────────────────────

func test_resting_deducts_the_price_and_restores_the_party() -> void:
	var member := _wounded_member()
	var stub := _make_stub_gameloop([member])
	var inn := _inn_in_tree()

	GameState.party_gold = 500
	inn._do_rest()  # synchronous up to its first await — spend + restore both land before it
	stub.free()

	assert_eq(int(GameState.get_gold()), 500 - InnInteriorRes.REST_COST,
		"a rest must cost the advertised price (pre-fix: every inn in the game was free)")
	assert_eq(int(member.current_hp), int(member.max_hp), "and still fully heal the party")
	assert_eq(int(member.current_mp), int(member.max_mp), "including MP")

	# Let the success dialog's own timer resolve before teardown frees the inn.
	await get_tree().create_timer(1.8).timeout


func test_rest_is_refused_when_the_party_cannot_pay() -> void:
	var member := _wounded_member()
	var stub := _make_stub_gameloop([member])
	var inn := _inn_in_tree()

	GameState.party_gold = InnInteriorRes.REST_COST - 1
	inn._do_rest()
	stub.free()

	assert_eq(int(GameState.get_gold()), InnInteriorRes.REST_COST - 1,
		"a refused rest must leave gold untouched")
	assert_eq(int(member.current_hp), 1,
		"a refused rest must NOT restore the party — free healing is the whole bug")
	var label := _find_label_containing(inn._rest_dialog, "Not enough gold")
	assert_not_null(label, "the refusal must be surfaced, not silent")


func _find_label_containing(root: Node, needle: String) -> Label:
	if root == null or not is_instance_valid(root):
		return null
	if root is Label and (root as Label).text.contains(needle):
		return root as Label
	for c in root.get_children():
		var found := _find_label_containing(c, needle)
		if found != null:
			return found
	return null
