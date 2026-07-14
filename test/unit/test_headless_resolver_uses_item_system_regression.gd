extends GutTest

## tick 394: HeadlessBattleResolver._resolve_item routes through
## ItemSystem.use_item so autogrind item handling matches live
## battle exactly.
##
## Pre-fix: hardcoded handlers for potion / hi_potion / ether /
## hi_ether plus an unconditional heal(50) default. The default
## silently mishandled every other item:
##   - mega_potion silently healed 50 instead of 100
##   - phoenix_down silently healed 50 instead of reviving
##   - holy_water/bomb_fragment silently healed 50 instead of
##     damaging an enemy
##   - power_drink/speed_tonic silently healed 50 instead of
##     applying their buff
## All silently corrupted autogrind reward / tier calculations.

const HBR_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, max_hp: int = 100, max_mp: int = 50) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": max_hp, "max_mp": max_mp,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_routes_through_item_system() -> void:
	var src := _read(HBR_PATH)
	var fn_idx: int = src.find("func _resolve_item")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("ItemSystem"),
		"_resolve_item must reference ItemSystem")
	assert_true(body.contains("use_item"),
		"_resolve_item must call ItemSystem.use_item")


func test_mega_potion_heals_correct_amount() -> void:
	# mega_potion authors heal_hp=100. Pre-fix the hardcoded default
	# arm only healed 50.
	var its = Engine.get_main_loop().root.get_node_or_null("ItemSystem")
	if its == null:
		pending("ItemSystem autoload required")
		return
	if not its.items.has("mega_potion"):
		pending("mega_potion item data required")
		return
	var hbr: GDScript = load(HBR_PATH)
	var resolver: Object = hbr.new()
	add_child_autofree(resolver)
	var user: Combatant = _make("User", 200, 50)
	user.add_item("mega_potion", 1)
	var target: Combatant = _make("Target", 200, 50)
	target.current_hp = 50
	resolver._resolve_item(user, "mega_potion", target)
	# Live ItemSystem heals 100 (per data); pre-fix the hardcoded
	# default would have healed only 50.
	assert_gt(target.current_hp, 100,
		"mega_potion must heal MORE than 50 HP — pre-fix the unconditional fallback healed 50")


func test_unknown_item_does_not_fizzle_to_heal() -> void:
	# Pre-fix any unknown item healed the target 50. Post-fix routes
	# through ItemSystem.use_item which surfaces a warning + returns
	# false without unintended HP changes.
	var its = Engine.get_main_loop().root.get_node_or_null("ItemSystem")
	if its == null:
		pending("ItemSystem autoload required")
		return
	var hbr: GDScript = load(HBR_PATH)
	var resolver: Object = hbr.new()
	add_child_autofree(resolver)
	var user: Combatant = _make("User", 100, 50)
	user.add_item("__not_a_real_item__", 1)
	var target: Combatant = _make("Target", 100, 50)
	target.current_hp = 50
	resolver._resolve_item(user, "__not_a_real_item__", target)
	# Unknown item should NOT silently heal target back to 100.
	assert_lt(target.current_hp, 100,
		"unknown item must NOT silently heal target — pre-fix everything healed 50")
