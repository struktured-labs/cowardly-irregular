extends GutTest

## tick 444: cover_ally passive's meta_effects.auto_cover_threshold
## now actually redirects basic attacks from low-HP allies to the
## covering Guardian.
##
## Pre-fix passives.json authored:
##   cover_ally: {meta_effects: {auto_cover_threshold: 0.25}}
##   description: "Automatically take hits for allies below 25% HP"
## but no code path read the field. The Guardian's signature
## protection mechanic was decoration.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, max_hp: int = 100) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": max_hp, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func _bm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("BattleManager")


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _maybe_cover_ally"),
		"BattleManager must declare _maybe_cover_ally helper")
	assert_true(src.contains("_get_passive_meta_effect_sum(\"auto_cover_threshold\")"),
		"_maybe_cover_ally must consult ally.auto_cover_threshold")


func test_execute_attack_consults_helper() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_attack")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_maybe_cover_ally(attacker, actual_target)"),
		"_execute_attack must consult _maybe_cover_ally after _retarget_enemy")


func test_helper_skips_player_attacker() -> void:
	# A player attacker is friendly fire / mind_swap weirdness — skip.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _maybe_cover_ally")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if attacker in player_party:"),
		"_maybe_cover_ally must short-circuit when attacker is a player")


func test_helper_max_wins_semantics() -> void:
	# Highest-threshold ally wins (most committed protector).
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _maybe_cover_ally")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if threshold > best_threshold:"),
		"_maybe_cover_ally must keep the highest threshold")


func test_data_still_authors_threshold() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("cover_ally"))
	var me: Variant = data["cover_ally"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(float(me.get("auto_cover_threshold", 0.0)), 0.0,
		"cover_ally must still author auto_cover_threshold > 0")


func _set_parties(bm, party: Array[Combatant], foes: Array[Combatant]) -> Dictionary:
	# player_party / enemy_party are typed Array[Combatant], so a raw
	# Array literal won't assign — pre-built typed arrays must be used.
	var prior := {"p": bm.player_party.duplicate(), "e": bm.enemy_party.duplicate()}
	bm.player_party = party
	bm.enemy_party = foes
	return prior


func _restore_parties(bm, prior: Dictionary) -> void:
	var p: Array[Combatant] = []
	for c in prior["p"]:
		if c is Combatant:
			p.append(c)
	var e: Array[Combatant] = []
	for c in prior["e"]:
		if c is Combatant:
			e.append(c)
	bm.player_party = p
	bm.enemy_party = e


func test_runtime_cover_redirects_low_hp_ally() -> void:
	# Enemy attacks low-HP player; live ally with cover_ally
	# intercepts.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("cover_ally"):
		pending("cover_ally passive required")
		return
	var hurt: Combatant = _make("Hurt", 100)
	hurt.current_hp = 10  # 10% — below 0.25 threshold
	var guard: Combatant = _make("Guard", 200)
	guard.current_hp = 200
	guard.equipped_passives = ["cover_ally"]
	var foe: Combatant = _make("Foe", 100)
	var party: Array[Combatant] = [hurt, guard]
	var foes: Array[Combatant] = [foe]
	var prior := _set_parties(bm, party, foes)
	var picked: Combatant = bm._maybe_cover_ally(foe, hurt)
	assert_eq(picked, guard,
		"low-HP target must be covered by the ally with cover_ally equipped")
	_restore_parties(bm, prior)


func test_runtime_no_cover_above_threshold() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("cover_ally"):
		pending("cover_ally passive required")
		return
	var healthy: Combatant = _make("Healthy", 100)
	healthy.current_hp = 80  # 80% — above 0.25 threshold
	var guard: Combatant = _make("GuardB", 200)
	guard.current_hp = 200
	guard.equipped_passives = ["cover_ally"]
	var foe: Combatant = _make("FoeB", 100)
	var party: Array[Combatant] = [healthy, guard]
	var foes: Array[Combatant] = [foe]
	var prior := _set_parties(bm, party, foes)
	var picked: Combatant = bm._maybe_cover_ally(foe, healthy)
	assert_eq(picked, healthy,
		"target above HP threshold must NOT be covered — wire must respect the threshold")
	_restore_parties(bm, prior)


func test_runtime_no_cover_when_no_guardian() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var hurt: Combatant = _make("HurtC", 100)
	hurt.current_hp = 10
	var ally: Combatant = _make("AllyC", 200)
	ally.current_hp = 200
	ally.equipped_passives = []
	var foe: Combatant = _make("FoeC", 100)
	var party: Array[Combatant] = [hurt, ally]
	var foes: Array[Combatant] = [foe]
	var prior := _set_parties(bm, party, foes)
	var picked: Combatant = bm._maybe_cover_ally(foe, hurt)
	assert_eq(picked, hurt,
		"no cover_ally equipped anywhere → no redirect, target stays")
	_restore_parties(bm, prior)


func test_runtime_no_cover_from_player_attacker() -> void:
	# Edge case: friendly-fire (e.g. mind_swap) — should NOT trigger
	# cover. The attacker being in player_party short-circuits.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("cover_ally"):
		pending("cover_ally passive required")
		return
	var hurt: Combatant = _make("HurtD", 100)
	hurt.current_hp = 10
	var guard: Combatant = _make("GuardD", 200)
	guard.equipped_passives = ["cover_ally"]
	var rogue_ally: Combatant = _make("RogueD", 100)
	var party: Array[Combatant] = [hurt, guard, rogue_ally]
	var foes: Array[Combatant] = []
	var prior := _set_parties(bm, party, foes)
	var picked: Combatant = bm._maybe_cover_ally(rogue_ally, hurt)
	assert_eq(picked, hurt,
		"player attacker → no cover (friendly fire stays on the original target)")
	_restore_parties(bm, prior)
