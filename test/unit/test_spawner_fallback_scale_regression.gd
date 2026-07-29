extends GutTest

## BattleEnemySpawner.MONSTER_TYPES kept pre-×10 stats after the re-denomination. 2026-07-29.
##
## My ×10 pass rewrote monsters.json and jobs.json. It could not see eleven stat blocks hardcoded
## in GDScript — a slime at max_hp 80 while the same slime in monsters.json reads 680.
##
## LATENT, NOT LIVE, and worth stating precisely. spawn_enemies() (the hardcoded path) is reached
## from a dev test-battle entry and three ERROR fallbacks:
##   monsters.json failed to load · forced_enemies produced zero spawns · no valid encounter ids
## Normal encounters go through spawn_from_data, which reads monsters.json.
##
## But the fallback exists to keep the game DIAGNOSABLE when data fails, and at ×1 against a ×10
## party it would produce one-hit fights — which reads as a balance bug, not a data-load failure.
## The fallback's whole job is to fail legibly, and a wrong denomination makes it fail deceptively.
##
## Found by asking where stats live OTHER than the files I rewrote. The absolute-threshold sweep
## that found the tank gate and the magnitude sweep that found the steal divisor both scan src/ for
## stats in ARITHMETIC; a literal stat block in a const array matches neither shape.


func _fallback_blocks() -> Array:
	# Parsed from source: the const is not exported and cannot be read through the class at test
	# time without instantiating the spawner's scene dependencies.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleEnemySpawner.gd")
	var start: int = src.find("const MONSTER_TYPES")
	assert_gt(start, -1, "MONSTER_TYPES must exist — if it was renamed this guard measures nothing")
	var stop: int = src.find("\n]", start)
	var block: String = src.substr(start, stop - start)
	var out: Array = []
	var re := RegEx.create_from_string("(?s)\"max_hp\":\\s*(\\d+).*?\"attack\":\\s*(\\d+).*?\"defense\":\\s*(\\d+)")
	for m in re.search_all(block):
		out.append({"max_hp": int(m.get_string(1)), "attack": int(m.get_string(2)),
			"defense": int(m.get_string(3))})
	return out


func test_the_fallback_blocks_are_in_the_current_denomination() -> void:
	# Compared against the JSON entry for the SAME monster where one exists — the strongest
	# available check, because it needs no threshold at all. All eleven ids are in monsters.json.
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var src := FileAccess.get_file_as_string("res://src/battle/BattleEnemySpawner.gd")
	var start: int = src.find("const MONSTER_TYPES")
	var block: String = src.substr(start, src.find("\n]", start) - start)
	var re := RegEx.create_from_string("(?s)\"id\":\\s*\"(\\w+)\".*?\"max_hp\":\\s*(\\d+)")
	var offenders: Array = []
	var compared: int = 0
	for m in re.search_all(block):
		var id: String = m.get_string(1)
		var hardcoded: int = int(m.get_string(2))
		if not mons.has(id):
			continue
		var authored: int = int(((mons[id] as Dictionary).get("stats", {}) as Dictionary).get("max_hp", 0))
		if authored <= 0:
			continue
		compared += 1
		# Within an order of magnitude of the authored value. Not equality — the fallback is
		# allowed to differ as a rough default; it is not allowed to be a different denomination.
		if hardcoded * 5 < authored:
			offenders.append("%s: fallback %d vs authored %d (%.1f× behind)"
				% [id, hardcoded, authored, float(authored) / float(maxi(1, hardcoded))])
	assert_gt(compared, 5, "must actually compare blocks — a regex that matches nothing passes")
	assert_eq(offenders, [], "fallback stat blocks left at the old scale:\n  %s" % "\n  ".join(offenders))


func test_fallback_hp_is_in_the_same_band_as_authored_monsters() -> void:
	# The general form, for any fallback whose id is NOT in monsters.json. Derived from the
	# authored corpus rather than a chosen floor.
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var weakest: int = 1 << 30
	for id in mons:
		var hp: int = int(((mons[id] as Dictionary).get("stats", {}) as Dictionary).get("max_hp", 0))
		if hp > 0:
			weakest = mini(weakest, hp)
	var blocks: Array = _fallback_blocks()
	assert_gt(blocks.size(), 5, "positive control — the parse must find the blocks")
	var offenders: Array = []
	for b in blocks:
		if int(b["max_hp"]) * 5 < weakest:
			offenders.append("max_hp %d against a corpus minimum of %d" % [int(b["max_hp"]), weakest])
	assert_eq(offenders, [], "fallback monsters an order of magnitude below the weakest authored "
		+ "monster — the fallback would resolve every fight in one hit and read as a balance bug "
		+ "rather than the data-load failure it signals:\n  %s" % "\n  ".join(offenders))


func test_speed_and_mp_were_not_scaled_here_either() -> void:
	# The data pass deliberately left the MP economy and turn order alone. A fallback that scaled
	# them would diverge from the authored corpus in the opposite direction.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleEnemySpawner.gd")
	var start: int = src.find("const MONSTER_TYPES")
	var block: String = src.substr(start, src.find("\n]", start) - start)
	var re := RegEx.create_from_string("\"speed\":\\s*(\\d+)")
	var found: int = 0
	for m in re.search_all(block):
		found += 1
		assert_lt(int(m.get_string(1)), 100,
			"speed is comparative and was not part of the ×10 pass — scaling it here would break "
			+ "the `speed >= 18` assassin gate for fallback spawns")
	assert_gt(found, 5, "positive control — speeds must actually be read")
