extends GutTest

## Autogrind hands its battle engine a terrain and only ONE of the two engines read it.
##
##   GameLoop._on_grind_battle_requested(enemies, terrain)
##     :5866  _current_terrain = terrain          <- the value arrives, both branches see it
##     :5870  _resolve_headless_battle(enemies)   <- LUDICROUS SPEED: terrain dropped on the floor
##     :5874  _start_autogrind_battle(enemies)    <- normal speed: battle_scene.set_terrain(...)
##
## So the same party, grinding the same rules in the same cave, dealt different elemental damage
## depending on a SPEED setting. Live scales fire by 0.75 and ice by 1.25 in a cave
## (BattleManager._get_terrain_modifiers, TERRAIN_MODIFIER_VALUE = 0.25); the headless resolver
## scaled neither, because it contained zero occurrences of "terrain" outside one comment that
## names live's terrain path while mirroring everything around it.
##
## HOW A PLAYER REACHES IT: the console is the overworld menu's `autogrind` row, ungated by map,
## and GameLoop:5739 seeds the session with `_current_terrain` — the CURRENT map's terrain. Start a
## grind standing in whispering_cave ("cave"), harmonia_village ("village") or eldertree_hollow
## ("forest") and the divergence is live until the first region rotation, after which
## AutogrindController:503 overwrites it with a WORLD_REGIONS id — all six of which are
## `overworld`/`*_overworld` and match no arm of live's table, so both engines agree at 1.0 again.
## That bound is why the arms below pin a rotation id as the EQUAL case rather than assuming it.
##
## Weather rides the same line in live (BattleManager:5278) and was missing for the same reason.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"
const LOOP := "res://src/GameLoop.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()
	if AutogrindSystem:
		AutogrindSystem._test_disable_persistence = true


func _combatant(name: String, hp: int = 999999) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 99999,
		"attack": 20, "defense": 10, "magic": 60, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	return c


## Damage one cast of `ability_id` deals with the resolver standing on `terrain`. Fire/blizzard
## author no damage_variance and magic does not crit, so this is exact rather than sampled.
func _damage_on(terrain: String, ability_id: String) -> int:
	var caster := _combatant("Caster")
	var target := _combatant("Victim")
	_res._player_party = [target]
	_res._enemy_party = [caster]
	_res.terrain = terrain
	seed(0x7E22A1)
	var before: int = target.current_hp
	_res._resolve_ability(caster, ability_id, [target])
	return before - target.current_hp


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func test_a_cave_grind_reduces_fire_like_the_live_engine_does() -> void:
	var ab: Dictionary = _authored("fire")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("element", "")), "fire",
		"CONTROL: fire must still author the element the cave table reduces")
	var plains: int = _damage_on("plains", "fire")
	var cave: int = _damage_on("cave", "fire")
	gut.p("    fire: plains %d -> cave %d" % [plains, cave])
	assert_gt(plains, 0, "CONTROL: the spell must land at all, or both arms measure nothing")
	assert_lt(cave, plains,
		"a cave grind fired fire at full strength — live reduces it 25% and the grind must too")


func test_a_cave_grind_boosts_ice_like_the_live_engine_does() -> void:
	var ab: Dictionary = _authored("blizzard")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("element", "")), "ice",
		"CONTROL: blizzard must still author the element the cave table boosts")
	var plains: int = _damage_on("plains", "blizzard")
	var cave: int = _damage_on("cave", "blizzard")
	gut.p("    ice: plains %d -> cave %d" % [plains, cave])
	assert_gt(plains, 0, "CONTROL: blizzard must land at all (ice arm)")
	assert_gt(cave, plains,
		"the cave boosts ice in live and the grind reported the plains number")


## The rotation ids are the EQUAL case, and that is the whole bound on the defect above.
func test_a_rotation_region_is_plains_equivalent_on_both_engines() -> void:
	if _authored("fire").is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var plains: int = _damage_on("plains", "fire")
	for region in ["overworld", "suburban_overworld", "abstract_overworld"]:
		assert_eq(_damage_on(region, "fire"), plains,
			"%s must scale nothing — it matches no arm of live's table, and an inequality means the terrain string grew a meaning the live engine does not share" % region)


## The 46 existing resolve_battle callers pass no terrain; none of them may move.
func test_the_default_terrain_scales_nothing() -> void:
	if _authored("fire").is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var fresh = ResolverScript.new()
	assert_eq(fresh.terrain, "plains",
		"the resolver's default terrain must stay plains-equivalent or every existing caller shifts")
	assert_eq(_damage_on("plains", "fire"), _damage_on(fresh.terrain, "fire"),
		"the default must deal exactly what plains deals")


## ⛔ THE ENGINE MUST NOT READ THE ROLLING GLOBAL. GameState._advance_weather re-rolls at random
## during _process, so a resolver that asked it per cast produced different damage run to run —
## measured, it red test_autogrind_pierces_what_it_pierces_regression at 31 where it expects 45.
## The snapshot lives on the caller (GameLoop), and this arm is behavioural on purpose: a source
## pin would pass the moment someone reintroduced the read through a differently-spelled helper.
func test_the_engine_reads_its_own_weather_not_the_worlds() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("set_weather") or _authored("fire").is_empty():
		pass_test("GameState autoload unavailable")
		return
	var was: String = str(gs.get_weather())
	gs.set_weather("clear")
	var calm: int = _damage_on("plains", "fire")
	gs.set_weather("rain")
	var wet: int = _damage_on("plains", "fire")
	gut.p("    world weather clear %d -> rain %d (engine must not move)" % [calm, wet])
	assert_gt(calm, 0, "CONTROL: fire must land at all under clear world weather (snapshot arm)")
	assert_eq(wet, calm,
		"the world's weather moved this engine's damage — it is reading the rolling global again")
	_res.weather = "rain"
	var owned: int = _damage_on("plains", "fire")
	gut.p("    engine's own weather rain: %d" % owned)
	assert_lt(owned, calm,
		"CONTROL: rain must still reduce fire when the engine is TOLD it is raining, or the arm above passes for the wrong reason")
	gs.set_weather(was)


## The override must answer from the STRING it is given and never from live's cached battle state.
func test_the_override_does_not_consult_live_cached_terrain() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pass_test("BattleManager autoload unavailable")
		return
	bm.set_terrain("plains")
	assert_almost_eq(bm.get_terrain_damage_modifier("fire", "cave"), 0.75, 0.001,
		"an explicit cave must reduce fire even while the cached battle terrain is plains")
	assert_almost_eq(bm.get_terrain_damage_modifier("fire", "forest"), 1.25, 0.001,
		"forest boosts fire")
	bm.set_terrain("cave")
	assert_almost_eq(bm.get_terrain_damage_modifier("fire"), 0.75, 0.001,
		"CONTROL: the no-argument form must still answer from set_terrain — live's callers use it")
	assert_almost_eq(bm.get_terrain_damage_modifier("fire", "plains"), 1.0, 0.001,
		"an explicit plains must override a cached cave, or the argument is being ignored")
	bm.set_terrain("plains")


## Spelling, not behaviour: this pins the one production hand-off, which no headless test can drive.
func test_gameloop_hands_the_headless_resolver_its_terrain() -> void:
	var code: String = GdSource.code_of(LOOP)
	assert_gt(code.length(), 50000, "CONTROL: GameLoop was actually read")
	var at: int = code.find("func _resolve_headless_battle")
	assert_gt(at, 0, "CONTROL: the headless branch's function must still exist")
	assert_true(code.substr(at, 400).contains("resolver.terrain = _current_terrain"),
		"_resolve_headless_battle stopped handing the resolver its terrain — the ludicrous-speed path is back to scaling nothing, and no behavioural arm in this file can see it")


## Derived from this file's own source: every symbol reached on the resolver must exist on it.
func test_every_resolver_symbol_this_file_reaches_exists() -> void:
	var mine: String = GdSource.code_of(get_script().resource_path)
	assert_gt(mine.length(), 1000, "CONTROL: this test file was actually read")
	var rx := RegEx.new()
	rx.compile("_res\\.([A-Za-z_][A-Za-z0-9_]*)")
	var reached: Dictionary = {}
	for m in rx.search_all(mine):
		reached[m.get_string(1)] = true
	assert_gt(reached.size(), 2, "CONTROL: the derivation found almost nothing — the regex is stale")
	## WHAT THIS COVERS, measured rather than assumed: a CLEAN rename — one that updates its own
	## internal call sites, so nothing else in the suite reds. Renaming `terrain` that way left this
	## the only arm naming the symbol. A rename that does NOT compile is loud by other means (the
	## behavioural arms collapse to 0 damage and EC=1), so this floor is not what catches that.
	var probe = ResolverScript.new()
	for sym in reached.keys():
		assert_true(probe.has_method(sym) or sym in probe,
			"this file reaches HeadlessBattleResolver.%s and the resolver no longer has it" % sym)
	gut.p("    floored: %s" % ", ".join(PackedStringArray(reached.keys())))
