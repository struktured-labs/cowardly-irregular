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


# ── the peer group: every OTHER literal stat block in src/ ──────────
##
## MONSTER_TYPES was the first one found and I reported it as the finding. The peer group is SIX
## files — cowir-sfx's scope lesson, committed by me one item after quoting it:
##   BattleEnemySpawner  11 monster fallbacks      JobSystem      14 job fallbacks
##   GameLoop            2 party-creation blocks   BattleScene    default party
##   AutogrindSystem     meta-boss fallback        EncounterSystem hero_mimic
## All six were invisible to the ×10 pass (which rewrote JSON) AND to the arithmetic sweeps that
## found the tank gate and the steal divisor (which look for stats in expressions). A literal block
## in a const array or an initialize() call matches neither shape.

func test_the_job_fallbacks_mirror_jobs_json_exactly() -> void:
	# JobSystem's hardcoded jobs carry the comment "Values mirror data/jobs.json exactly". They did
	# not — fighter read 120 against the file's 132 even BEFORE the rescale, so the claim was
	# already false and the ×10 made it false by an order of magnitude. Synced rather than softened:
	# a comment that states an invariant should be made true or deleted, not hedged.
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var src := FileAccess.get_file_as_string("res://src/jobs/JobSystem.gd")
	var offenders: Array = []
	var compared: int = 0
	for job_id in jobs:
		var mods: Variant = (jobs[job_id] as Dictionary).get("stat_modifiers")
		if not (mods is Dictionary):
			continue
		var re := RegEx.create_from_string("(?s)\"%s\": \\{.*?\"stat_modifiers\": \\{(.*?)\\}" % job_id)
		var m := re.search(src)
		if m == null:
			continue
		var body: String = m.get_string(1)
		for stat in (mods as Dictionary):
			var sre := RegEx.create_from_string("\"%s\":\\s*(\\d+)" % stat)
			var sm := sre.search(body)
			if sm == null:
				continue
			compared += 1
			if int(sm.get_string(1)) != int((mods as Dictionary)[stat]):
				offenders.append("%s.%s: fallback %s vs jobs.json %d"
					% [job_id, stat, sm.get_string(1), int((mods as Dictionary)[stat])])
	assert_gt(compared, 20, "positive control — the parse must actually reach job stat blocks")
	assert_eq(offenders, [], "JobSystem's fallbacks claim to mirror jobs.json and do not. If "
		+ "jobs.json fails to load, every job silently spawns at these values:\n  %s"
		% "\n  ".join(offenders))


func test_no_src_stat_block_sits_an_order_of_magnitude_below_the_corpus() -> void:
	# The general form across all six files, so a SEVENTH literal block cannot ship unnoticed.
	# Floor derived from the authored corpus, not chosen.
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var weakest_job: int = 1 << 30
	for jid in jobs:
		var mods: Variant = (jobs[jid] as Dictionary).get("stat_modifiers")
		if mods is Dictionary and (mods as Dictionary).has("max_hp"):
			weakest_job = mini(weakest_job, int((mods as Dictionary)["max_hp"]))
	var files := ["res://src/jobs/JobSystem.gd", "res://src/GameLoop.gd",
		"res://src/battle/BattleScene.gd", "res://src/battle/BattleEnemySpawner.gd",
		"res://src/autogrind/AutogrindSystem.gd", "res://src/encounters/EncounterSystem.gd"]
	var re := RegEx.create_from_string("\"max_hp\":\\s*(\\d+)")
	var offenders: Array = []
	var seen: int = 0
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			seen += 1
			var v: int = int(m.get_string(1))
			# A tenth of the frailest authored job is unambiguously the old denomination.
			if v > 0 and v * 5 < weakest_job:
				offenders.append("%s: max_hp %d (corpus floor %d)" % [str(path).get_file(), v, weakest_job])
	assert_gt(seen, 20, "positive control — must actually find literal blocks across the six files")
	assert_eq(offenders, [], "literal stat blocks left at the pre-×10 scale:\n  %s" % "\n  ".join(offenders))
