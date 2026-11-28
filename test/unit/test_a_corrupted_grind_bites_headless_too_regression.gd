extends GutTest

## A grind past meta_corruption 2.0 gives its monsters corruption_effects (AutogrindSystem.create_scaled_enemy_data):
## reality_bending (a hit carries the target's defence), time_distortion, stat_drain (1%/round party erosion). Live
## stored them (BattleEnemySpawner) and BattleManager applied them; the ludicrous-speed path dropped them at
## GameLoop._combatant_for_headless and HeadlessBattleResolver read none, so a corrupted grind scored easier headless
## than it played. Each arm compares the same fight with and without the corruption.

const GameLoopScript := preload("res://src/GameLoop.gd")
const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _bm_players: Array = []
var _bm_enemies: Array = []
var _bm_round: int = 0


func before_each() -> void:
	_bm_players = BattleManager.player_party.duplicate()
	_bm_enemies = BattleManager.enemy_party.duplicate()
	_bm_round = BattleManager.current_round


func after_each() -> void:
	BattleManager.current_round = _bm_round
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	for c in _bm_players:
		BattleManager.player_party.append(c)
	for c in _bm_enemies:
		BattleManager.enemy_party.append(c)


func _row(effects: Array) -> Dictionary:
	var r := {"id": "slime", "name": "Slime", "stats": {"max_hp": 680, "attack": 40, "defense": 20, "magic": 10, "speed": 8}}
	if not effects.is_empty():
		r["corruption_effects"] = effects
	return r


func _enemy(effects: Array) -> Combatant:
	var gl: Node = autofree(GameLoopScript.new())
	var e: Combatant = gl._combatant_for_headless(_row(effects))
	autofree(e)
	return e


func _hero() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.initialize({"name": "Hero", "max_hp": 900, "max_mp": 30, "attack": 200, "defense": 60, "magic": 100, "speed": 10})
	return c


func _lend(resolver, party: Array, enemies: Array) -> void:
	resolver._player_party = party
	resolver._enemy_party = enemies
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	for c in party:
		BattleManager.player_party.append(c)
	for c in enemies:
		BattleManager.enemy_party.append(c)


func test_a_headless_monster_carries_its_rows_corruption() -> void:
	assert_false(_enemy([]).has_meta("corruption_effects"), "CONTROL: an uncorrupted row builds a clean monster")
	var e := _enemy(["reality_bending", "stat_drain"])
	assert_eq(e.get_meta("corruption_effects", []), ["reality_bending", "stat_drain"], "a headless monster must keep the corruption its row was scaled with")


func test_reality_bending_carries_the_defence_into_a_headless_hit() -> void:
	var resolver = HBR.new()
	var target := _hero()
	var plain := _enemy([])
	var bent := _enemy(["reality_bending"])
	var hit_seed := -1
	for s in range(1, 40):
		seed(s)
		if resolver._roll_attack_strike(plain, target, 1.0).get("fate", "") == "hit":
			hit_seed = s
			break
	assert_gt(hit_seed, 0, "CONTROL: some seed lands the plain strike")
	seed(hit_seed)
	var plain_dmg: int = int(resolver._roll_attack_strike(plain, target, 1.0).get("damage", 0))
	seed(hit_seed)
	var bent_dmg: int = int(resolver._roll_attack_strike(bent, target, 1.0).get("damage", 0))
	assert_eq(bent_dmg, plain_dmg + target.defense, "a reality-bent headless hit must carry the target's defence, as live's does")


func test_stat_drain_erodes_the_party_each_headless_round() -> void:
	var clean_hero := _hero()
	var clean = HBR.new()
	_lend(clean, [clean_hero], [_enemy([])])
	var before: int = clean_hero.attack
	clean._tick_round_start()
	assert_eq(clean_hero.attack, before, "CONTROL: an uncorrupted round leaves the party's attack alone")
	var hero := _hero()
	var drained = HBR.new()
	_lend(drained, [hero], [_enemy(["stat_drain"])])
	drained._tick_round_start()
	assert_eq(hero.attack, before - maxi(1, int(before * 0.01)), "a stat_drain monster must erode the party 1% per headless round, as live does")


## The drain outlived its battle on the real party (autogrind review), so a long corrupted grind ground it to 1.
func test_back_to_back_drained_battles_leave_the_party_whole() -> void:
	var hero := _hero()
	var before: int = hero.attack
	for battle in 2:
		var r = HBR.new()
		_lend(r, [hero], [_enemy(["stat_drain"])])
		r._tick_round_start()
		r._tick_round_start()
		assert_lt(hero.attack, before, "CONTROL: battle %d's rounds drained the party" % battle)
		r._restore_bm(BattleManager, [], [], 0)
		assert_eq(hero.attack, before, "after headless battle %d the party's attack must be what it was before the drain" % battle)
	assert_false(hero.has_meta("_drain_base"), "the drain's record is gone once the battle ends")


func test_live_end_battle_undoes_the_drain() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var at: int = src.find("func end_battle(")
	assert_gt(at, -1, "CONTROL: end_battle was found")
	var body: String = src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("undo_stat_drain(player_party)"), "live end_battle must put back what stat_drain took")
	var hero := _hero()
	var before: int = hero.attack
	_lend(HBR.new(), [hero], [_enemy(["stat_drain"])])
	BattleManager._apply_corruption_effects_on_round_start()
	assert_lt(hero.attack, before, "CONTROL: live's tick drained the party")
	BattleManager.undo_stat_drain([hero])
	assert_eq(hero.attack, before, "undo_stat_drain restores the pre-drain attack")


func test_a_recompute_drops_the_drain_record() -> void:
	var hero := _hero()
	_lend(HBR.new(), [hero], [_enemy(["stat_drain"])])
	BattleManager._apply_corruption_effects_on_round_start()
	assert_true(hero.has_meta("_drain_base"), "CONTROL: the drain left its record")
	hero.recalculate_stats()
	assert_false(hero.has_meta("_drain_base"), "a recompute already undid the drain, so its record must not undo it again")
