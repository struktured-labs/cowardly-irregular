extends SceneTree

## Win-rate / time-to-kill harness for the difficulty pass (2026-10-24, struktured via grokbot).
##
## ⛔ IT DRIVES THE GAME'S OWN BUILDERS, NOT COPIES OF THEM. test_mordaine_battle_integration builds
## a party by hand (`max_hp = 120 + level * 8`), which measures a fiction: the real party goes through
## GameLoop._create_party -> JobSystem.assign_job/assign_secondary_job -> EquipmentSystem.equip_* ->
## PassiveSystem.ensure_equipped -> Combatant.recalculate_stats. Enemies go through GameLoop's own
## `_combatant_for_headless`. A reimplementation of either would be a second instrument that drifts.
##
## ⛔ AND A COMBATANT MUST BE IN THE SCENE TREE OR ITS GEAR AND PASSIVES SILENTLY DO NOT APPLY.
## recalculate_stats reaches the two systems by ABSOLUTE path (`has_node("/root/EquipmentSystem")`),
## which is false for any node outside the tree -- no warning, no error, just base+job+level stats.
## _create_party parents the five to the GameLoop, so this file REPARENTS each one to `root` and
## recalculates there. The first version of this harness skipped that and measured a party with no
## equipment, no passives and no secondary job while reporting a clean positive control, because the
## level multiplier (the thing the control checked) is applied BEFORE all three.
##
## Enemies are RAW monsters.json rows (nested `stats`), which is the shape the autogrind path feeds
## `_combatant_for_headless`. EncounterSystem._create_enemy_data FLATTENS instead, for the live
## spawner; passing that shape here would silently yield the 50 HP / 10 ATK defaults.
##
##   BAL_LEVEL=5 BAL_TRIALS=30 BAL_ENEMIES=goblin,goblin BAL_GEAR=1 BAL_JOBS=fighter,cleric \
##     XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy -s res://tools/balance_harness.gd
##
## BAL_GEAR=0 strips the three equipment slots, the equipped passives and the secondary job, which is
## what the pre-equipment baseline measured. Both arms come off ONE roster so the only difference is
## the kit.

## ⛔ NOT preload(), and Combatant is not referenced by class_name either. A preload resolves at
## SCRIPT-COMPILE time, which in a `-s` run happens BEFORE the autoloads are registered -- and
## GameLoop.gd and Combatant.gd both name JobSystem/EquipmentSystem/SoundManager in function bodies,
## which are compile errors while those identifiers do not exist. Measured: the whole dependency
## chain failed to compile and the harness reported "JobSystem autoload absent" about a tree that
## has all 33 of them one frame later. Load after the first frame instead.
var GameLoopScript: Resource
var ResolverScript: Resource

var _fail := 0


func _env(key: String, dflt: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else dflt


## "attack=0.85,magic=0.9" -> {"attack": 0.85, "magic": 0.9}
func _kv(spec: String) -> Dictionary:
	var out: Dictionary = {}
	for pair in spec.split(",", false):
		var bits := str(pair).split("=", false)
		if bits.size() == 2:
			out[str(bits[0]).strip_edges()] = float(bits[1])
	return out


## Rewrites the LOADED jobs dict, so assign_job / recalculate_stats run the real pipeline over the
## proposed numbers. mdef_from_def replaces the job's authored magic_defense with a ratio of its
## defense -- the shipped jobs sit near 0.5x, which is why boss magic is effectively unmitigated.
func _apply_job_whatifs(scale: Dictionary, mdef_from_def: float, rate_ratio: float) -> void:
	var js = root.get_node_or_null("JobSystem")
	if js == null or not ("jobs" in js):
		_die("JobSystem has no `jobs` dict -- the what-if knobs would silently do nothing")
		return
	for jid in js.jobs:
		var job: Variant = js.jobs[jid]
		if not job is Dictionary or not (job as Dictionary).has("stat_modifiers"):
			continue
		var mods: Dictionary = (job as Dictionary)["stat_modifiers"]
		if mdef_from_def > 0.0 and mods.has("defense"):
			mods["magic_defense"] = int(round(float(mods["defense"]) * mdef_from_def))
		for stat in scale:
			if mods.has(stat):
				mods[stat] = int(round(float(mods[stat]) * float(scale[stat])))
		if not is_equal_approx(rate_ratio, 1.0):
			for stat in mods.keys():
				if stat in ["max_hp", "max_mp", "attack", "defense", "magic", "magic_defense", "speed"]:
					mods[stat] = int(round(float(mods[stat]) * rate_ratio))


func _apply_enemy_whatif(mdb: Dictionary, eid: String, scale: Dictionary) -> void:
	if scale.is_empty():
		return
	var row: Dictionary = mdb[eid]
	var st: Dictionary = row.get("stats", {})
	for stat in scale:
		if st.has(stat):
			st[stat] = int(round(float(st[stat]) * float(scale[stat])))


func _die(msg: String) -> void:
	print("[BAL] FAIL: %s" % msg)
	_fail += 1


func _init() -> void:
	await process_frame   # autoloads are children of root only from here on
	GameLoopScript = load("res://src/GameLoop.gd")
	ResolverScript = load("res://src/autogrind/HeadlessBattleResolver.gd")

	var level := int(_env("BAL_LEVEL", "5"))
	var trials := int(_env("BAL_TRIALS", "30"))
	var enemy_ids := _env("BAL_ENEMIES", "goblin,goblin").split(",", false)
	var want_jobs := _env("BAL_JOBS", "").split(",", false)
	var gear := _env("BAL_GEAR", "1") != "0"
	var seed_base := int(_env("BAL_SEED", "1"))
	var want_log := _env("BAL_LOG", "0") != "0"
	## WHAT-IF knobs. Each one edits the DATA the real pipeline reads, never the result it produced:
	## BAL_PARTY_SCALE / BAL_PARTY_MDEF_FROM_DEF rewrite JobSystem's in-memory stat_modifiers before
	## assign_job, BAL_ENEMY_SCALE rewrites the monsters.json row before _combatant_for_headless, and
	## BAL_LEVEL_RATE is folded into the job mods by the exact ratio of the two level multipliers --
	## level_mult MULTIPLIES the job mods, so scaling them by (new/old) is identical to changing the
	## rate, and leaves passives and gear (applied afterwards) untouched, which is also what a real
	## rate change would do. Measuring a proposal by post-hoc editing the OUTPUT would price gear and
	## passives into the change, which is the error the first version of this harness made in reverse.
	var level_rate := float(_env("BAL_LEVEL_RATE", "0.04"))
	var party_scale := _kv(_env("BAL_PARTY_SCALE", ""))
	var enemy_scale := _kv(_env("BAL_ENEMY_SCALE", ""))
	var mdef_from_def := float(_env("BAL_PARTY_MDEF_FROM_DEF", "0"))

	for autoload in ["JobSystem", "EquipmentSystem", "PassiveSystem", "GameState"]:
		if root.get_node_or_null(autoload) == null:
			_die("%s autoload absent -- the party would not use the real stat pipeline" % autoload)
			quit(1); return
	## Memory rule: an autobattle-driving run must not write the player's script exports. The run is
	## already XDG-sandboxed, but the flag is what the shipped tests use and costs nothing.
	var abs_node = root.get_node_or_null("AutobattleSystem")
	if abs_node != null and "_test_disable_persistence" in abs_node:
		abs_node._test_disable_persistence = true

	var mdb: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	if mdb == null or mdb.is_empty():
		_die("monsters.json did not parse"); quit(1); return
	for eid in enemy_ids:
		if not mdb.has(eid):
			_die("no monster '%s' in monsters.json" % eid); quit(1); return

	var rate_ratio := (1.0 + (level - 1) * level_rate) / (1.0 + (level - 1) * 0.04)
	_apply_job_whatifs(party_scale, mdef_from_def, rate_ratio)
	for eid in enemy_ids:
		_apply_enemy_whatif(mdb, str(eid), enemy_scale)
	if not party_scale.is_empty() or not enemy_scale.is_empty() or mdef_from_def > 0.0 or not is_equal_approx(level_rate, 0.04):
		print("[BAL] WHAT-IF  level_rate=%.3f (x%.4f on job mods)  party_scale=%s  mdef_from_def=%.2f  enemy_scale=%s" % [
			level_rate, rate_ratio, str(party_scale), mdef_from_def, str(enemy_scale)])

	var gl = GameLoopScript.new()   # never added to the tree; the party is reparented out of it

	print("[BAL] level=%d trials=%d gear=%s jobs=%s enemies=%s" % [
		level, trials, ("FULL KIT" if gear else "STRIPPED"),
		("all" if want_jobs.is_empty() else ",".join(want_jobs)), ",".join(enemy_ids)])
	_print_party_blocks(gl, want_jobs, level)
	_print_enemy_block(mdb, enemy_ids)

	var wins := 0
	var rounds_total := 0
	var rounds_n := 0
	var hp_pct_total := 0.0
	var reasons: Dictionary = {}

	for t in range(trials):
		seed(seed_base + t)   # reproducible: the resolver is stochastic (29 rng sites)
		var party := _build_party(gl, want_jobs, level, gear)
		var enemies := _build_enemies(gl, mdb, enemy_ids)
		var resolver = ResolverScript.new()
		if t == 0:
			_print_script_block(party)
		var result: Dictionary = resolver.resolve_battle(party, enemies)
		if t == 0 and want_log:
			print("[BAL] --- battle log, trial 0 ---")
			for line in (result.get("log", []) as Array):
				print("[BAL] | %s" % str(line))
			print("[BAL] --- end log ---")
		if bool(result.get("victory", false)):
			wins += 1
		if result.has("rounds"):
			rounds_total += int(result["rounds"]); rounds_n += 1
		var r := str(result.get("termination_reason", ""))
		reasons[r] = int(reasons.get(r, 0)) + 1
		var alive_hp := 0.0
		var max_hp := 0.0
		for c in party:
			max_hp += float(c.max_hp)
			alive_hp += float(max(0, c.current_hp))
		if max_hp > 0.0:
			hp_pct_total += alive_hp / max_hp * 100.0
		_free_party(party)
		for c in enemies:
			c.queue_free()

	print("")
	print("[BAL] ===== RESULT (gear=%s) =====" % ("FULL KIT" if gear else "STRIPPED"))
	print("[BAL] win rate      %d/%d = %.1f%%" % [wins, trials, 100.0 * wins / max(1, trials)])
	if rounds_n > 0:
		print("[BAL] mean rounds   %.2f  (time-to-kill, over %d battles reporting it)" % [float(rounds_total) / rounds_n, rounds_n])
	else:
		print("[BAL] mean rounds   (the result dict carries no round count)")
	print("[BAL] party HP left %.1f%% mean" % (hp_pct_total / max(1, trials)))
	for r in reasons:
		print("[BAL] termination   %-16s %d" % [("(none)" if r == "" else r), reasons[r]])
	quit(_fail)


## The game's own roster, reparented into the tree so recalculate_stats can reach
## /root/EquipmentSystem and /root/PassiveSystem. BAL_JOBS FILTERS this party; it never invents one.
func _build_party(gl, want_jobs: PackedStringArray, level: int, gear: bool) -> Array:
	gl._create_party()
	var party: Array = []
	for c in gl.party.duplicate():
		gl.remove_child(c)
		var jid: String = str((c.job as Dictionary).get("id", "")) if c.job is Dictionary else ""
		if not want_jobs.is_empty() and not want_jobs.has(jid):
			c.free()
			continue
		root.add_child(c)
		if not gear:
			c.equipped_weapon = ""
			c.equipped_armor = ""
			c.equipped_accessory = ""
			c.equipped_passives.clear()
			c.secondary_job = null
			c.secondary_job_id = ""
		c.job_level = level
		c.recalculate_stats()
		c.current_hp = c.max_hp
		c.current_mp = c.max_mp
		c.is_alive = true
		party.append(c)
	gl.party.clear()
	return party


func _free_party(party: Array) -> void:
	for c in party:
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
		c.queue_free()


func _build_enemies(gl, mdb: Dictionary, enemy_ids: PackedStringArray) -> Array:
	var out: Array = []
	for eid in enemy_ids:
		var row: Dictionary = (mdb[str(eid)] as Dictionary).duplicate(true)
		row["id"] = str(eid)
		out.append(gl._combatant_for_headless(row))
	return out


## Both arms are printed so a reader can check them against the running game, and the delta between
## them is the POSITIVE CONTROL for the reparenting above: a kit that applies moves at least one
## stat. Zero delta on every member means the tree reach failed and the run is the bare-stats
## measurement wearing the full-kit label.
func _print_party_blocks(gl, want_jobs: PackedStringArray, level: int) -> void:
	print("[BAL] party at level %d (job stat_modifiers x level_mult %.2f, then passives, then gear):" % [
		level, 1.0 + (level - 1) * 0.04])
	var bare := _build_party(gl, want_jobs, level, false)
	var bare_rows: Dictionary = {}
	for c in bare:
		bare_rows[str(c.combatant_name)] = [c.max_hp, c.max_mp, c.attack, c.defense, c.magic, c.magic_defense, c.speed]
	_free_party(bare)

	var full := _build_party(gl, want_jobs, level, true)
	var moved := 0
	for c in full:
		var now := [c.max_hp, c.max_mp, c.attack, c.defense, c.magic, c.magic_defense, c.speed]
		var was: Array = bare_rows.get(str(c.combatant_name), now)
		print("[BAL]   %-7s hp %-6d mp %-5d atk %-5d def %-5d mag %-5d mdef %-5d spd %d" % [
			c.combatant_name, now[0], now[1], now[2], now[3], now[4], now[5], now[6]])
		var deltas: Array[String] = []
		for i in range(now.size()):
			var d: int = int(now[i]) - int(was[i])
			if d != 0:
				deltas.append("%s%+d" % [["hp", "mp", "atk", "def", "mag", "mdef", "spd"][i], d])
				moved += 1
		print("[BAL]     kit (gear+passives+secondary): %s  [%s / %s / %s]" % [
			("NOTHING" if deltas.is_empty() else " ".join(deltas)),
			c.equipped_weapon, c.equipped_armor, c.equipped_accessory])
	_free_party(full)
	if moved == 0:
		_die("the full kit moved no stat on any member -- recalculate_stats could not reach /root/EquipmentSystem, so this run is the BARE measurement mislabelled")


## WHICH SCRIPT the party runs decides the answer as much as its stats do: with no script every
## member takes a plain weapon ATTACK (AutobattleSystem._get_default_action) and the Cleric's 713
## magic never casts. _create_party names the members Fighter/Cleric/Rogue/Mage/Bard, which
## _get_character_id lowercases into exactly the job aliases create_default_character_script routes,
## so the shipped per-job defaults DO load -- printed here rather than assumed.
func _print_script_block(party: Array) -> void:
	var abs_node = root.get_node_or_null("AutobattleSystem")
	if abs_node == null:
		print("[BAL] autobattle: AutobattleSystem absent -- every member takes a plain attack")
		return
	for c in party:
		var cid: String = str(c.combatant_name).to_lower().replace(" ", "_")
		var sc: Dictionary = abs_node.get_character_script(cid)
		var rules: Array = sc.get("rules", [])
		print("[BAL] autobattle %-7s id=%-8s rules=%d%s" % [
			c.combatant_name, cid, rules.size(),
			("  ** NO RULES -- plain attack only **" if rules.is_empty() else "")])


func _print_enemy_block(mdb: Dictionary, enemy_ids: PackedStringArray) -> void:
	print("[BAL] enemies:")
	for eid in enemy_ids:
		var row: Dictionary = mdb[str(eid)]
		var s: Dictionary = row.get("stats", {})
		print("[BAL]   %-24s lvl %-4s hp %-6s atk %-5s def %-5s mag %-5s spd %s" % [
			str(eid), str(row.get("level", "?")), str(s.get("max_hp", "?")), str(s.get("attack", "?")),
			str(s.get("defense", "?")), str(s.get("magic", "?")), str(s.get("speed", "?"))])
