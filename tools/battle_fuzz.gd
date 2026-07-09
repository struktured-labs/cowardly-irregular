extends SceneTree

## Battle fuzzer — runs N randomized headless battles through
## HeadlessBattleResolver and reports anomalies. Engine errors surface on
## stderr (grep the output). Usage:
##   godot --headless --audio-driver Dummy -s tools/battle_fuzz.gd -- battles=300 seed=1234
## Deterministic when seed= is given; anomalies print with their seed+index
## so any finding replays exactly.
## KNOWN NOISE: the first -s compile happens before autoloads register and
## prints two SCRIPT ERRORs (Combatant's JobSystem ref); Godot retries after
## boot and the run proceeds — ignore those two lines, grep the rest.

var HBR = null  # lazy-loaded after autoload registration (preload compiles too early under -s)

const JOBS := ["fighter", "cleric", "mage", "rogue", "bard",
	"guardian", "ninja", "summoner", "speculator"]


var _enc: Node = null
var _jobs: Node = null


func _initialize() -> void:
	# Autoloads register after _initialize — wait a frame, then run
	await process_frame
	HBR = load("res://src/autogrind/HeadlessBattleResolver.gd")
	_enc = root.get_node_or_null("/root/EncounterSystem")
	_jobs = root.get_node_or_null("/root/JobSystem")
	if _enc == null or _jobs == null:
		push_error("[FUZZ] autoloads missing (run from the project dir)")
		quit(2)
		return
	var battles := 300
	var seed_val := int(Time.get_unix_time_from_system())
	var mode := "fuzz"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("battles="):
			battles = int(arg.split("=")[1])
		elif arg.begins_with("seed="):
			seed_val = int(arg.split("=")[1])
		elif arg.begins_with("mode="):
			mode = arg.split("=")[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	if mode == "report":
		_balance_report(rng)
		return
	print("[FUZZ] %d battles, seed=%d" % [battles, seed_val])

	var pools: Array = _enc.enemy_pools.keys()
	if pools.is_empty():
		push_error("[FUZZ] no enemy pools loaded — aborting")
		quit(2)
		return

	var wins := 0
	var losses := 0
	var anomalies := 0
	for i in range(battles):
		var party := _random_party(rng)
		var enemies := _random_enemies(rng, pools)
		if enemies.is_empty():
			continue
		var resolver = HBR.new()
		var result: Dictionary = resolver.resolve_battle(party, enemies)
		var rounds := int(result.get("rounds", -1))
		var victory := bool(result.get("victory", false))
		if victory:
			wins += 1
		else:
			losses += 1
		# Anomaly heuristics — each prints seed+index for exact replay.
		if rounds <= 0 or rounds > 500:
			anomalies += 1
			print("[FUZZ][ANOMALY] battle %d (seed %d): rounds=%d result=%s" % [i, seed_val, rounds, str(result).left(200)])
		for c in party + enemies:
			if c.current_hp < 0:
				anomalies += 1
				print("[FUZZ][ANOMALY] battle %d (seed %d): %s ended at NEGATIVE hp %d" % [i, seed_val, c.combatant_name, c.current_hp])
			if c.is_alive and c.current_hp == 0:
				anomalies += 1
				print("[FUZZ][ANOMALY] battle %d (seed %d): %s alive at 0 hp" % [i, seed_val, c.combatant_name])
		for c in party + enemies:
			root.remove_child(c)
			c.free()

	print("[FUZZ] done: %d wins / %d losses / %d anomalies" % [wins, losses, anomalies])
	quit(1 if anomalies > 0 else 0)


## mode=report — balance telemetry: the CANONICAL 5-starter party vs every
## pool at fixed level bands, K battles per cell. Measurement only; the
## table goes to struktured for balance calls (post-F1 difficulty shift).
func _balance_report(rng: RandomNumberGenerator) -> void:
	const K := 40
	const LEVELS := [5, 10, 15, 20]
	print("[REPORT] canonical 5-starter party, %d battles/cell, seed=%d" % [K, rng.seed])
	print("[REPORT] pool | " + " | ".join(LEVELS.map(func(l): return "L%d" % l)))
	var pool_ids: Array = _enc.enemy_pools.keys()
	pool_ids.sort()
	for pool_id in pool_ids:
		var cells: Array = []
		for lvl in LEVELS:
			var wins := 0
			var ran := 0
			for k in range(K):
				var party := _starter_party(lvl)
				var enemies := _pool_enemies(rng, pool_id)
				if enemies.is_empty():
					break
				ran += 1
				var resolver = HBR.new()
				if bool(resolver.resolve_battle(party, enemies).get("victory", false)):
					wins += 1
				for c in party + enemies:
					root.remove_child(c)
					c.free()
			cells.append("--" if ran == 0 else "%3d%%" % int(100.0 * wins / ran))
		print("[REPORT] %-28s | %s" % [pool_id, " | ".join(cells)])
	print("[REPORT] done")
	quit(0)


## Canonical starter base stats — mirrors GameLoop._create_party exactly.
const STARTER_BASES := {
	"fighter": {"max_hp": 150, "max_mp": 50, "attack": 25, "defense": 15, "magic": 12, "speed": 12},
	"cleric": {"max_hp": 100, "max_mp": 120, "attack": 10, "defense": 12, "magic": 28, "speed": 14},
	"mage": {"max_hp": 80, "max_mp": 150, "attack": 8, "defense": 8, "magic": 35, "speed": 12},
	"rogue": {"max_hp": 90, "max_mp": 40, "attack": 18, "defense": 10, "magic": 8, "speed": 22},
	"bard": {"max_hp": 95, "max_mp": 90, "attack": 12, "defense": 9, "magic": 22, "speed": 16},
}


func _starter_party(lvl: int) -> Array:
	var party := []
	for job_id in STARTER_BASES:
		var c = Combatant.new()
		root.add_child(c)
		var base: Dictionary = STARTER_BASES[job_id].duplicate()
		base["name"] = job_id.capitalize()
		c.initialize(base)
		_jobs.assign_job(c, job_id)
		# Level through the game's OWN growth path (stat gains + ability
		# unlocks land exactly as live play) — threshold is level*100.
		if lvl > 1:
			c.gain_job_exp(100 * lvl * (lvl - 1) / 2)
		c.current_ap = 1
		party.append(c)
	return party


func _pool_enemies(rng: RandomNumberGenerator, pool_id: String) -> Array:
	var pool: Array = _enc.enemy_pools.get(pool_id, [])
	if pool.is_empty():
		return []
	var enemies := []
	for i in range(rng.randi_range(2, 3)):
		var eid: String = str(pool[rng.randi_range(0, pool.size() - 1)])
		var c = Combatant.new()
		root.add_child(c)
		c.initialize(_enc._create_enemy_data(eid))
		c.set_meta("monster_type", eid)
		enemies.append(c)
	return enemies


func _random_party(rng: RandomNumberGenerator) -> Array:
	var party := []
	var size := rng.randi_range(1, 5)
	for i in range(size):
		var c = Combatant.new()
		root.add_child(c)  # in-tree BEFORE init/job — Combatant reads passives/equipment via /root
		var lvl := rng.randi_range(1, 25)
		c.initialize({
			"name": "Fuzz%d" % i,
			"max_hp": 80 + lvl * 12,
			"max_mp": 30 + lvl * 4,
			"attack": 10 + lvl * 2,
			"defense": 6 + lvl,
			"magic": 8 + lvl * 2,
			"speed": 8 + rng.randi_range(0, lvl),
		})
		c.job_level = lvl
		_jobs.assign_job(c, JOBS[rng.randi_range(0, JOBS.size() - 1)])
		c.current_ap = rng.randi_range(0, 4)
		party.append(c)
	return party


func _random_enemies(rng: RandomNumberGenerator, pools: Array) -> Array:
	var pool_id: String = pools[rng.randi_range(0, pools.size() - 1)]
	var pool: Array = _enc.enemy_pools.get(pool_id, [])
	if pool.is_empty():
		return []
	var enemies := []
	var count := rng.randi_range(1, 4)
	for i in range(count):
		var eid: String = str(pool[rng.randi_range(0, pool.size() - 1)])
		var data: Dictionary = _enc._create_enemy_data(eid)
		var c = Combatant.new()
		root.add_child(c)
		c.initialize(data)
		c.set_meta("monster_type", eid)
		enemies.append(c)
	return enemies
