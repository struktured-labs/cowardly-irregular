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
##
## BAL_PATH=default|auto|manual|oneshot picks HOW the party plays (see BAL_PATHS below); BAL_BAG=
## potion:5,ether:2 fills the one party bag the item_count conditions read. Every path is an
## autobattle script, because the resolver has no other input — a "manual" row is a competent
## script playing that way, not a human.

## ⛔ NOT preload(), and Combatant is not referenced by class_name either. A preload resolves at
## SCRIPT-COMPILE time, which in a `-s` run happens BEFORE the autoloads are registered -- and
## GameLoop.gd and Combatant.gd both name JobSystem/EquipmentSystem/SoundManager in function bodies,
## which are compile errors while those identifiers do not exist. Measured: the whole dependency
## chain failed to compile and the harness reported "JobSystem autoload absent" about a tree that
## has all 33 of them one frame later. Load after the first frame instead.
var GameLoopScript: Resource
var CombatantScript
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
		else:
			_die("'%s' is not key=value, so the knob it names would silently do nothing" % str(pair))
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
	CombatantScript = load("res://src/battle/Combatant.gd")
	ResolverScript = load("res://src/autogrind/HeadlessBattleResolver.gd")

	var level := int(_env("BAL_LEVEL", "5"))
	var trials := int(_env("BAL_TRIALS", "30"))
	var chain_links := maxi(1, int(_env("BAL_CHAIN", "1")))
	var enemy_ids := _env("BAL_ENEMIES", "goblin,goblin").split(",", false)
	var want_jobs := _env("BAL_JOBS", "").split(",", false)
	var gear := _env("BAL_GEAR", "1") != "0"
	var seed_base := int(_env("BAL_SEED", "1"))
	var want_log := _env("BAL_LOG", "0") != "0"
	var bal_path := _env("BAL_PATH", "default")
	if not (bal_path in BAL_PATHS):
		_die("BAL_PATH='%s' is not one of %s" % [bal_path, str(BAL_PATHS)]); quit(1); return
	## WHAT-IF knobs. Each one edits the DATA the real pipeline reads, never the result it produced:
	## BAL_PARTY_SCALE / BAL_PARTY_MDEF_FROM_DEF rewrite JobSystem's in-memory stat_modifiers before
	## assign_job, BAL_ENEMY_SCALE rewrites the monsters.json row before _combatant_for_headless, and
	## BAL_LEVEL_RATE is folded into the job mods by the exact ratio of the two level multipliers --
	## level_mult MULTIPLIES the job mods, so scaling them by (new/old) is identical to changing the
	## rate, and leaves passives and gear (applied afterwards) untouched, which is also what a real
	## rate change would do. Measuring a proposal by post-hoc editing the OUTPUT would price gear and
	## passives into the change, which is the error the first version of this harness made in reverse.
	var level_rate_env := _env("BAL_LEVEL_RATE", "")
	var level_rate := float(level_rate_env) if level_rate_env != "" else -1.0
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
	## A floor's re-levelled spawn ("imp@L13") becomes its own row here, scaled by the game's own EncounterSystem.apply_spawn_level.
	var es_script: Script = load("res://src/encounters/EncounterSystem.gd")
	var catalog: Dictionary = mdb.duplicate(true)
	for eid in enemy_ids:
		var want_level: int = es_script.spawn_level_of(str(eid))
		if want_level > 0 and mdb.has(es_script.spawn_base_id(str(eid))):
			var row: Dictionary = (mdb[es_script.spawn_base_id(str(eid))] as Dictionary).duplicate(true)
			var flat: Dictionary = (row.get("stats", {}) as Dictionary).duplicate()
			for k in ["level", "exp_reward", "gold_reward"]:
				flat[k] = row.get(k, 1)
			flat = es_script.apply_spawn_level(flat, want_level, catalog)
			for k in ["level", "exp_reward", "gold_reward"]:
				row[k] = flat[k]
			for k in row["stats"]:
				row["stats"][k] = flat.get(k, row["stats"][k])
			mdb[str(eid)] = row
		if not mdb.has(eid):
			_die("no monster '%s' in monsters.json" % eid); quit(1); return

	## BAL_LEVEL_RATE asks "what if the scaled stats grew linearly at this rate instead of on the curve".
	var rate_ratio: float = (1.0 + (level - 1) * level_rate) / CombatantScript.level_multiplier(level) if level_rate >= 0.0 else 1.0
	_apply_job_whatifs(party_scale, mdef_from_def, rate_ratio)
	for eid in enemy_ids:
		_apply_enemy_whatif(mdb, str(eid), enemy_scale)
	## BAL_ENEMY_MDEF_FROM_DEF=0.75: every foe's magic defence becomes that share of its defence. BAL_ABILITY_MULT=fire=1.5,fira=2.5: damage multipliers, in JobSystem's loaded rows.
	var foe_mdef: float = float(_env("BAL_ENEMY_MDEF_FROM_DEF", "0"))
	var ability_mult := _kv(_env("BAL_ABILITY_MULT", ""))
	if foe_mdef > 0.0:
		var done: Dictionary = {}
		for eid in enemy_ids:
			if done.has(str(eid)):
				continue
			done[str(eid)] = true
			var st: Dictionary = (mdb[str(eid)] as Dictionary).get("stats", {})
			st["magic_defense"] = int(round(float(st.get("defense", 0)) * foe_mdef))
	if not ability_mult.is_empty():
		var js_node = root.get_node_or_null("JobSystem")
		for aid in ability_mult:
			if js_node == null or not js_node.abilities.has(aid) or not _ability_db().has(aid):
				_die("BAL_ABILITY_MULT names '%s', which is not a loaded ability" % aid)
				continue
			js_node.abilities[aid]["damage_multiplier"] = float(ability_mult[aid])
			_ability_db()[aid]["damage_multiplier"] = float(ability_mult[aid])
	## BAL_SPREAD / BAL_CRIT_MODE / BAL_ABILITY_CRIT set the dials both engines read (DamageRules); the same names as the live probe.
	var rules: Script = load("res://src/battle/DamageRules.gd") if ResourceLoader.exists("res://src/battle/DamageRules.gd") else null
	if rules != null:
		if _env("BAL_SPREAD", "") != "":   # unset: the rule's own shipped default (0.3), not 1.0
			rules.enemy_spread = float(_env("BAL_SPREAD", ""))
		rules.crit_mode = _env("BAL_CRIT_MODE", "shipped")
		if _env("BAL_ABILITY_CRIT", "") != "":   # unset: the rule's own shipped default
			rules.abilities_inherit_swing_crit = _env("BAL_ABILITY_CRIT", "") == "1"
		print("[BAL] DIALS  enemy_spread=%.2f  crit_mode=%s  abilities_inherit_swing_crit=%s" % [rules.enemy_spread, rules.crit_mode, str(rules.abilities_inherit_swing_crit)])
	elif _env("BAL_SPREAD", "") != "" or _env("BAL_CRIT_MODE", "") != "" or _env("BAL_ABILITY_CRIT", "") != "":
		_die("this tree has no DamageRules, so the spread and crit dials would silently do nothing")
	if foe_mdef > 0.0 or not ability_mult.is_empty():
		print("[BAL] WHAT-IF  enemy_mdef_from_def=%.2f  ability_mult=%s" % [foe_mdef, str(ability_mult)])
	if not party_scale.is_empty() or not enemy_scale.is_empty() or mdef_from_def > 0.0 or level_rate >= 0.0:
		print("[BAL] WHAT-IF  level_rate=%.3f (x%.4f on job mods)  party_scale=%s  mdef_from_def=%.2f  enemy_scale=%s" % [
			level_rate, rate_ratio, str(party_scale), mdef_from_def, str(enemy_scale)])

	var gl = GameLoopScript.new()   # never added to the tree; the party is reparented out of it

	print("[BAL] level=%d trials=%d gear=%s path=%s jobs=%s enemies=%s" % [
		level, trials, ("FULL KIT" if gear else "STRIPPED"), bal_path,
		("all" if want_jobs.is_empty() else ",".join(want_jobs)), ",".join(enemy_ids)])
	_print_party_blocks(gl, want_jobs, level)
	_print_enemy_block(mdb, enemy_ids)

	## The script is installed ONCE, before trial 0, off a probe party built by the same builder
	## every trial uses — so the derived picks (hardest known hit, self-landing buff) come from the
	## real kit at this level rather than from a table. The trials then reuse it by character_id,
	## which is derived from the member NAME and so is stable across rebuilds.
	var probe := _build_party(gl, want_jobs, level, gear)
	_fill_bag(probe)
	_print_bag_block(probe)
	var labels := _install_path_scripts(bal_path, probe)
	var cids: Array[String] = []
	for c in probe:
		cids.append(_char_id(c))
	_print_script_block(probe, bal_path, labels)
	_free_party(probe)
	## BAL_CRIT_RATES=1: each member's plain-swing crit chance under every DamageRules mode, from the grind's rule and from live's.
	if _env("BAL_CRIT_RATES", "0") == "1" and rules != null:
		var keep_mode: String = rules.crit_mode
		var rate_party := _build_party(gl, want_jobs, level, gear)
		var bm_node = root.get_node_or_null("BattleManager")
		var rate_resolver = ResolverScript.new()
		for mode in ["shipped", "comment", "level"]:
			rules.crit_mode = mode
			for c in rate_party:
				print("[BAL] CRIT L%d %-8s %-8s speed %-4d grind %.3f  live %.3f" % [level, mode, _job_id(c), int(c.speed),
						float(rate_resolver._swing_crit_chance(c)), float(bm_node._calculate_crit_chance(c)) if bm_node != null else -1.0])
		rules.crit_mode = keep_mode
		_free_party(rate_party)
	if _fail > 0:
		print("[BAL] refusing to sweep: the path's own scripts did not install, so every row below would be mislabelled")
		quit(_fail); return

	var want_tally: bool = _env("BAL_TALLY", "0") == "1"   # BAL_TALLY=1: per-job damage share, damage per action, per-move weak/plain means
	var wins := 0
	var rounds_total := 0
	var rounds_n := 0
	var hp_pct_total := 0.0
	var win_rounds_total := 0
	var one_shots := 0
	var reasons: Dictionary = {}

	for t in range(trials):
		seed(seed_base + t)   # reproducible: the resolver is stochastic (29 rng sites)
		var party := _build_party(gl, want_jobs, level, gear)
		_fill_bag(party)
		var enemies := _build_enemies(gl, mdb, enemy_ids)
		var resolver = ResolverScript.new()
		if "use_live_enemy_ladder" in resolver:
			resolver.use_live_enemy_ladder = _env("BAL_LADDER", "1") != "0"   # BAL_LADDER=0: the resolver's own picker (strongest ability every round)
		var jobs_by_name: Dictionary = {}
		for c in party:
			jobs_by_name[str(c.combatant_name)] = _job_id(c)
		var trial_state: Dictionary = {}
		var mods: Dictionary = _elemental_mods(enemies)
		var result: Dictionary = resolver.resolve_battle(party, enemies)
		if want_tally:
			_tally_log(result.get("log", []) as Array, jobs_by_name, mods, trial_state)
		## BAL_CHAIN=N: N links back to back, HP carried, BattleManager's between-battle rest between them (cowir-overworld's chained encounters).
		var link_rounds: int = int(result.get("rounds", 0))
		for link in range(1, chain_links):
			if not bool(result.get("victory", false)):
				break
			var bm: Node = get_root().get_node_or_null("BattleManager")
			if bm != null:
				bm.apply_post_battle_restore(party)
			for c in enemies:
				c.queue_free()
			enemies = _build_enemies(gl, mdb, enemy_ids)
			resolver = ResolverScript.new()
			if "use_live_enemy_ladder" in resolver:
				resolver.use_live_enemy_ladder = _env("BAL_LADDER", "1") != "0"   # BAL_LADDER=0: the resolver's own picker (strongest ability every round)
			result = resolver.resolve_battle(party, enemies)
			if want_tally:
				_tally_log(result.get("log", []) as Array, jobs_by_name, mods, trial_state)
			link_rounds += int(result.get("rounds", 0))
		if chain_links > 1:
			result["rounds"] = link_rounds
		if want_tally:
			_tally_close(trial_state, jobs_by_name.values())
		if t == 0 and want_log:
			for c in party:
				print("[BAL] buffed attack %-8s %d (attack %d)  buffed magic %d" % [str(c.combatant_name),
						int(c.get_buffed_stat("attack", c.attack)), int(c.attack), int(c.get_buffed_stat("magic", c.magic))])
			print("[BAL] --- battle log, trial 0 ---")
			for line in (result.get("log", []) as Array):
				print("[BAL] | %s" % str(line))
			print("[BAL] --- end log ---")
		if bool(result.get("victory", false)):
			wins += 1
			win_rounds_total += int(result.get("rounds", 0))
		## Read off the resolver rather than the result dict: `_one_shot` is not one of
		## _build_results' keys, and asking the object is cheaper and more honest than adding a
		## key to a shipped return shape for a harness's benefit.
		if "_one_shot" in resolver and bool(resolver._one_shot):
			one_shots += 1
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
	print("[BAL] ===== RESULT (path=%s gear=%s) =====" % [bal_path, ("FULL KIT" if gear else "STRIPPED")])
	print("[BAL] win rate      %d/%d = %.1f%%" % [wins, trials, 100.0 * wins / max(1, trials)])
	if wins > 0:
		print("[BAL] rounds to win %.2f mean over the %d victories" % [float(win_rounds_total) / wins, wins])
	print("[BAL] one-shots     %d/%d = %.1f%%  (every foe dead in the phase the first damage landed)" % [
		one_shots, trials, 100.0 * one_shots / max(1, trials)])
	if rounds_n > 0:
		print("[BAL] mean rounds   %.2f  (time-to-kill, over %d battles reporting it)" % [float(rounds_total) / rounds_n, rounds_n])
	else:
		print("[BAL] mean rounds   (the result dict carries no round count)")
	print("[BAL] party HP left %.1f%% mean" % (hp_pct_total / max(1, trials)))
	for r in reasons:
		print("[BAL] termination   %-16s %d" % [("(none)" if r == "" else r), reasons[r]])
	print("")
	if want_tally:
		_print_tally(trials)
	_print_fire_counts(bal_path, cids)
	quit(_fail)


## The game's own roster, reparented into the tree so recalculate_stats can reach
## /root/EquipmentSystem and /root/PassiveSystem. BAL_JOBS FILTERS this party; it never invents one.
func _build_party(gl, want_jobs: PackedStringArray, level: int, gear: bool) -> Array:
	if gear and _env("BAL_FROM_SAVE", "") != "":
		return _build_party_from_save(gl, want_jobs, _env("BAL_FROM_SAVE", ""))
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
		if gear:
			_wear_shop_kit(c, jid)
		c.recalculate_stats()
		c.current_hp = c.max_hp
		c.current_mp = c.max_mp
		c.is_alive = true
		party.append(c)
	gl.party.clear()
	_equip_lens(party)
	return party


## BAL_KIT=top|mid: the blacksmith's shelf in place of the starting kit (every W1 smith stocks the whole catalog, so gold is the gate).
## top = the best piece per slot for the member's role; mid = the best piece costing <= 1000. Unset = the starting kit, as before.
func _wear_shop_kit(c, job_id: String) -> void:
	var kit := _env("BAL_KIT", "")
	if kit == "":
		return
	var es = root.get_node_or_null("EquipmentSystem")
	var shop: Script = load("res://src/exploration/VillageShop.gd")
	if es == null or shop == null:
		_die("BAL_KIT asked for but EquipmentSystem / VillageShop is absent"); return
	var cap: int = 1000 if kit == "mid" else 1 << 30
	var offense: String = "attack" if job_id in ["fighter", "rogue"] else "magic"
	var best_w := ""
	var best_w_v := -1.0
	for id in shop.BLACKSMITH_WEAPONS:
		var w: Dictionary = es.get_weapon(str(id))
		var v := float((w.get("stat_mods", {}) as Dictionary).get(offense, 0))
		if not w.is_empty() and int(w.get("cost", 0)) <= cap and v > best_w_v:
			best_w = str(id); best_w_v = v
	var best_a := ""
	var best_a_v := -1.0
	for id in shop.BLACKSMITH_ARMOR:
		var a: Dictionary = es.get_armor(str(id))
		var m: Dictionary = a.get("stat_mods", {})
		var v := float(m.get("defense", 0)) + float(m.get("max_hp", 0)) * 0.5
		if not a.is_empty() and int(a.get("cost", 0)) <= cap and v > best_a_v:
			best_a = str(id); best_a_v = v
	if best_w != "":
		c.equipped_weapon = best_w
	if best_a != "":
		c.equipped_armor = best_a
	if kit == "top":
		c.equipped_accessory = "hp_amulet"


## BAL_LENS=<axis>[:<job>] equips one Lens, because the party this harness built was MISSING THE
## GAME'S OWN ANSWER to the thing I was measuring. `Combatant.take_damage` carries a Warden Lens
## lethal floor -- one survived killing blow per battle, from any HP -- and the first fifteen-boss
## sweep ran with no Lens at all while printing "[LensSystem] Loaded 4 lenses" at startup. Four
## bosses measured 0/20 against a party that cannot hold the mechanic the design points at.
##
## ⛔ EXACTLY ONE LENS EXISTS PER AXIS. `LensSystem.holder_of` returns a single holder and
## `equip_lens` MOVES it rather than duplicating, so "pooled" (struktured 2026-07-27) means
## unbound, not copyable: one party member carries the floor, not five. Equipping it to a second
## member silently takes it off the first, which is why this helper equips ONE.
##
## The key is `combatant_name.to_lower().replace(" ", "_")`, which is what take_damage's floor and
## get_lens_meta_effects both read -- derived from the consumer rather than guessed.
func _equip_lens(party: Array) -> void:
	var spec := _env("BAL_LENS", "")
	if spec == "":
		return
	var bits := spec.split(":", false)
	var axis: String = str(bits[0])
	var want_job: String = str(bits[1]) if bits.size() > 1 else ""
	var ls: Node = root.get_node_or_null("LensSystem")
	var gs: Node = root.get_node_or_null("GameState")
	if ls == null or gs == null:
		print("[BAL] BAL_LENS=%s asked for but LensSystem/GameState absent — NO lens equipped" % spec)
		_fail += 1
		return
	if not (axis in ls.all_axes()):
		print("[BAL] BAL_LENS names axis '%s', which is not one of %s" % [axis, str(ls.all_axes())])
		_fail += 1
		return
	if not (axis in gs.owned_lenses):
		gs.owned_lenses.append(axis)
	var target = null
	for c in party:
		var jid: String = str((c.job as Dictionary).get("id", "")) if c.job is Dictionary else ""
		if want_job == "" or jid == want_job:
			target = c
			break
	if target == null:
		print("[BAL] BAL_LENS wanted job '%s', which is not in this party" % want_job)
		_fail += 1
		return
	var key: String = str(target.combatant_name).to_lower().replace(" ", "_")
	if not ls.equip_lens(key, axis):
		print("[BAL] equip_lens(%s, %s) REFUSED — the lens is not equipped, so this run proves nothing" % [key, axis])
		_fail += 1
		return
	## Read it back through the consumer's own accessor rather than trusting the setter's bool.
	var me: Dictionary = ls.get_lens_meta_effects(key)
	print("[BAL] lens %s -> %s (%s)  meta_effects=%s" % [axis, target.combatant_name, key, str(me)])
	if me.is_empty():
		print("[BAL] the lens equipped but get_lens_meta_effects(%s) is EMPTY — the floor would not fire" % key)
		_fail += 1


## Why a BAL_FROM_SAVE path may not be read, or "" if it is a copy: his live profile is never an input.
static func save_path_refusal(path: String, user_dir: String) -> String:
	if path.strip_edges() == "":
		return "no path given"
	if path.begins_with("user://"):
		return "'%s' is inside user:// -- copy the save out first" % path
	var full := path.simplify_path()
	if user_dir != "" and full.begins_with(user_dir.simplify_path().trim_suffix("/") + "/"):
		return "'%s' is under this run's user data dir %s" % [path, user_dir]
	if "/app_userdata/" in full:
		return "'%s' is inside a godot app_userdata profile -- copy the save out first" % path
	return ""


## BAL_FROM_SAVE=<save.json>: his party exactly as saved, rebuilt by the game's own load path (levels from the save).
func _build_party_from_save(gl, want_jobs: PackedStringArray, path: String) -> Array:
	var refusal := save_path_refusal(path, OS.get_user_data_dir())
	if refusal != "":
		_die("BAL_FROM_SAVE refused: %s" % refusal)
		return []
	var save: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (save is Dictionary) or not ((save as Dictionary).get("party") is Array):
		_die("BAL_FROM_SAVE '%s' has no party array" % path)
		return []
	var gs = root.get_node("GameState")
	gs.player_party.clear()
	for entry in (save as Dictionary)["party"]:
		if entry is Dictionary:
			gs.player_party.append((entry as Dictionary).duplicate(true))
	if not gl._restore_party_from_save_data():
		_die("GameLoop._restore_party_from_save_data refused '%s'" % path)
		return []
	var party: Array = []
	for c in gl.party.duplicate():
		gl.remove_child(c)
		var jid: String = str((c.job as Dictionary).get("id", "")) if c.job is Dictionary else ""
		if not want_jobs.is_empty() and not want_jobs.has(jid):
			c.free()
			continue
		root.add_child(c)
		c.recalculate_stats()
		c.current_hp = c.max_hp
		c.current_mp = c.max_mp
		c.is_alive = true
		party.append(c)
	gl.party.clear()
	_equip_lens(party)
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
		if _env("BAL_NO_KIT", "0") != "0":
			row["abilities"] = []   # BAL_NO_KIT=1: the roster row a grind shipped with through .792 (no abilities: basic attacks only)
		out.append(gl._combatant_for_headless(row))
	return out


## Both arms are printed so a reader can check them against the running game, and the delta between
## them is the POSITIVE CONTROL for the reparenting above: a kit that applies moves at least one
## stat. Zero delta on every member means the tree reach failed and the run is the bare-stats
## measurement wearing the full-kit label.
func _print_party_blocks(gl, want_jobs: PackedStringArray, level: int) -> void:
	print("[BAL] party at level %d (job stat_modifiers x level_mult %.2f, then passives, then gear):" % [
		level, CombatantScript.level_multiplier(level)])
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
func _print_script_block(party: Array, path: String, labels: Dictionary) -> void:
	var abs_node = root.get_node_or_null("AutobattleSystem")
	if abs_node == null:
		print("[BAL] autobattle: AutobattleSystem absent -- every member takes a plain attack")
		return
	for c in party:
		var cid: String = _char_id(c)
		var sc: Dictionary = abs_node.get_character_script(cid)
		var rules: Array = sc.get("rules", [])
		var best: Dictionary = _best_damage_ability(c)
		var buff: Dictionary = _setup_buff_ability(c)
		print("[BAL] autobattle %-7s id=%-8s rules=%-2d %s" % [
			c.combatant_name, cid, rules.size(),
			("** NO RULES -- plain attack only **" if rules.is_empty() else str(labels.get(cid, "shipped default")))])
		if path in ["manual", "oneshot"]:
			print("[BAL]     derived: hit=%s(x%s, %s MP of %d)  setup_buff=%s" % [
				str(best.get("id", "— none known, plain swings only")),
				str(best.get("damage_multiplier", "-")), str(best.get("mp_cost", "-")), int(c.max_mp),
				str(buff.get("id", "— none it can land on itself"))])


func _print_enemy_block(mdb: Dictionary, enemy_ids: PackedStringArray) -> void:
	print("[BAL] enemies:")
	for eid in enemy_ids:
		var row: Dictionary = mdb[str(eid)]
		var s: Dictionary = row.get("stats", {})
		print("[BAL]   %-24s lvl %-4s hp %-6s atk %-5s def %-5s mag %-5s spd %s" % [
			str(eid), str(row.get("level", "?")), str(s.get("max_hp", "?")), str(s.get("attack", "?")),
			str(s.get("defense", "?")), str(s.get("magic", "?")), str(s.get("speed", "?"))])


## ───────────────────────── BAL_PATH: the three ways to fight a boss ─────────────────────────
##
## Carmelo's directive 19478 asks for three paths per boss. ⛔ ALL THREE ARE AUTOBATTLE SCRIPTS,
## because the resolver knows nothing else: HeadlessBattleResolver._selection_phase asks
## `AutobattleSystem.execute_grid_autobattle(combatant)` for every player action and has no second
## input path. So a row labelled "manual" is A COMPETENT SCRIPT PLAYING THAT WAY, never a human —
## it cannot read a tell it was not written for, which is where a real player is strongest and the
## approximation weakest. Say that beside any number this produces.
##
##   default  the shipped per-job script (create_default_character_script) — the pre-existing arm
##   auto     each job's stance=balanced row from data/autobattle_rule_templates.json, UNMODIFIED
##   manual   Bravely Default banking: Default (defer) to AP 3, then Brave the bank into one phase
##   oneshot  zero damage until the bank is full and the buffs are up, then one burst phase
const BAL_PATHS: Array[String] = ["default", "auto", "manual", "oneshot", "best"]

var _abilities: Dictionary = {}


func _char_id(c) -> String:
	return str(c.combatant_name).to_lower().replace(" ", "_")


func _job_id(c) -> String:
	return str((c.job as Dictionary).get("id", "")) if c.job is Dictionary else ""


## {job_id: template} for stance "balanced", keyed off the ROWS' own job_id/stance fields rather
## than the "<job>_balanced" id convention — a renamed id would otherwise select nothing silently.
func _balanced_templates() -> Dictionary:
	var out: Dictionary = {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/autobattle_rule_templates.json"))
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for e in ((raw as Dictionary).get("templates", []) as Array):
		if e is Dictionary and str((e as Dictionary).get("stance", "")) == _env("BAL_STANCE", "balanced"):   # BAL_STANCE=defensive|aggressive for the auto path
			out[str((e as Dictionary).get("job_id", ""))] = e
	return out


func _ability_db() -> Dictionary:
	if _abilities.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
		if typeof(raw) == TYPE_DICTIONARY:
			_abilities = raw
	return _abilities


## The five stat buffs the resolver actually writes to active_buffs (_effect_to_stat's "_up" arms).
## Named rather than tested by the "_up" suffix: inspiring_melody's effect is "mp_restore_and_ap"
## and lands NO buff entry, so a suffix test would pick a setup ability that can never satisfy
## setup_complete and the one-shot path would stall on a rule that looks right.
func _buff_stat_of(effect: String) -> String:
	match effect:
		"attack_up": return "attack"
		"defense_up": return "defense"
		"magic_up": return "magic"
		"speed_up": return "speed"
		"magic_defense_up": return "magic_defense"
	return ""


## The hardest single-target hit this member actually KNOWS, asked through Combatant.knows_ability —
## struktured's own rule ("just have a general guard on if u have the ability or not at all,
## provenance irrelevant"), which is also what AutobattleSystem._combatant_has_learned delegates to.
## DERIVED rather than hand-listed per job: a hand list selects from my map of the kit, and the kits
## move with every level gate and secondary job. {} when the member knows no damage ability.
func _best_damage_ability(c) -> Dictionary:
	var best: Dictionary = {}
	for aid in _ability_db():
		var raw: Variant = _ability_db()[aid]
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		if not (str(row.get("type", "")) in ["physical", "magic"]):
			continue
		if str(row.get("target_type", "")) != "single_enemy":
			continue
		if not row.has("damage_multiplier"):
			continue
		if not c.knows_ability(str(aid)):
			continue
		var mult: float = float(row["damage_multiplier"])
		if best.is_empty():
			best = row
		elif mult > float(best["damage_multiplier"]):
			best = row
		elif is_equal_approx(mult, float(best["damage_multiplier"])) and int(row.get("mp_cost", 99)) < int(best.get("mp_cost", 99)):
			best = row
	return best


## A buff this member can land ON ITSELF, for the one-shot setup. ⛔ `setup_complete`
## (AutobattleSystem:454) is `active_buffs.size() > 0 and current_ap >= 4`, so what matters is a
## buff entry on THIS combatant — which is why all_allies outranks self/single_ally here. A member
## with neither never satisfies the predicate, and the AP-only valve below it is what stops that
## member deferring for the whole battle under a label that says it was trying to one-shot.
func _setup_buff_ability(c) -> Dictionary:
	var best: Dictionary = {}
	for aid in _ability_db():
		var raw: Variant = _ability_db()[aid]
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		if _buff_stat_of(str(row.get("effect", ""))) == "":
			continue
		if not (str(row.get("target_type", "")) in ["all_allies", "single_ally", "self"]):
			continue
		if not c.knows_ability(str(aid)):
			continue
		if best.is_empty():
			best = row
		elif str(row.get("target_type", "")) == "all_allies" and str(best.get("target_type", "")) != "all_allies":
			best = row
	return best


func _cond(t: String, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"type": t}
	for k in extra:
		out[k] = extra[k]
	return out


## "logic": "AND" because create_rule writes it and validate_rule REFUSES any other value — the
## evaluator hard-ANDs and never reads the key, so the field is part of the shared format.
func _rule(conds: Array, acts: Array) -> Dictionary:
	return {"conditions": conds, "actions": acts, "enabled": true, "logic": "AND"}


## The MP percent this member needs to pay for `casts` of `ability` out of its OWN pool, so a
## banked burst never fizzle-consumes the bank it spent three turns collecting.
func _mp_gate(c, ability: Dictionary, casts: int) -> int:
	var cost: int = int(ability.get("mp_cost", 0)) * casts
	if cost <= 0 or int(c.max_mp) <= 0:
		return 0
	return mini(100, int(ceil(float(cost) / float(c.max_mp) * 100.0)))


## N slots of the hardest thing the member can pay for, padded with plain swings. The ability count
## comes from the POOL, not from the slot count: a fourth cast nobody can afford fizzles that slot
## and the bank is spent for nothing.
func _burst_actions(c, best: Dictionary, slots: int) -> Array:
	var acts: Array = []
	if not best.is_empty():
		var cost: int = int(best.get("mp_cost", 0))
		var affordable: int = slots if cost <= 0 else int(float(c.max_mp) / float(maxi(1, cost)))
		for _i in range(mini(slots, maxi(0, affordable))):
			acts.append({"type": "ability", "id": str(best["id"]), "target": "lowest_hp_enemy"})
	while acts.size() < slots:
		acts.append({"type": "attack", "target": "lowest_hp_enemy"})
	return acts


## Bravely Default in a grid: Default until the bank is worth spending, then Brave the whole bank
## into one phase, with the emergency rows ON TOP because first-match-wins is the whole grammar.
func _manual_script(c) -> Dictionary:
	var rules: Array = []
	var best: Dictionary = _best_damage_ability(c)
	rules.append(_rule([_cond("hp_percent", {"op": "<", "value": 35}),
			_cond("item_count", {"item_id": "potion", "op": ">", "value": 0})],
			[{"type": "item", "id": "potion", "target": "self"}]))
	if c.knows_ability("cure"):
		rules.append(_rule([_cond("ally_hp_percent", {"op": "<=", "value": 50}),
				_cond("mp_percent", {"op": ">=", "value": 20})],
				[{"type": "ability", "id": "cure", "target": "lowest_hp_ally", "upgrades": ["cura"]}]))
	if not best.is_empty():
		rules.append(_rule([_cond("ap", {"op": ">=", "value": 3}),
				_cond("mp_percent", {"op": ">=", "value": _mp_gate(c, best, 2)})],
				[{"type": "ability", "id": str(best["id"]), "target": "lowest_hp_enemy"},
				{"type": "ability", "id": str(best["id"]), "target": "lowest_hp_enemy"},
				{"type": "attack", "target": "lowest_hp_enemy"}]))
	rules.append(_rule([_cond("ap", {"op": ">=", "value": 3})],
			[{"type": "attack", "target": "lowest_hp_enemy"},
			{"type": "attack", "target": "lowest_hp_enemy"},
			{"type": "attack", "target": "lowest_hp_enemy"}]))
	rules.append(_rule([_cond("always")], [{"type": "defer"}]))
	return {"rules": rules}


## The canonical one-shot (BattleManager._check_one_shot:9060) is `all_dead and
## _execution_phase_count == _first_damage_phase` — every foe dies in the phase the FIRST damage
## lands, and the setup before it is UNBOUNDED. So this script deals no damage at all until the
## bank is full: it buffs, and otherwise defers, which is the grammar's only zero-damage action.
## The resolver scores the same rule per ROUND (`_one_shot`, :202) and a round here IS one
## execution phase, so the two agree on this harness's shape.
##
## ⚠️ Every member gains +1 AP per round whatever they do and a single action costs none, so a
## party that defers reaches AP 4 ON THE SAME ROUND — the burst lands in one phase by arithmetic,
## not by coordination a per-character script could not express.
func _oneshot_script(c) -> Dictionary:
	var rules: Array = []
	var burst: Array = _burst_actions(c, _best_damage_ability(c), 4)
	var buff: Dictionary = _setup_buff_ability(c)
	rules.append(_rule([_cond("setup_complete")], burst))
	## The valve. Nothing in this party may be able to buff this member, and without this row it
	## would defer for the whole battle while the label said it was attempting a one-shot.
	rules.append(_rule([_cond("ap", {"op": ">=", "value": 4}), _cond("turn", {"op": ">=", "value": 6})], burst))
	if not buff.is_empty():
		rules.append(_rule([_cond("not_has_buff", {"stat": _buff_stat_of(str(buff.get("effect", "")))})],
				[{"type": "ability", "id": str(buff["id"]),
				"target": ("all_allies" if str(buff.get("target_type", "")) == "all_allies" else "self")}]))
	rules.append(_rule([_cond("always")], [{"type": "defer"}]))
	return {"rules": rules}


## One action a turn: the hardest single-target move the member can pay for (BAL_SPELL names it for whoever knows it), else Channel (BAL_CHANNEL=0: a swing).
func _best_script(c) -> Dictionary:
	var rules: Array = []
	var best: Dictionary = _best_damage_ability(c)
	var forced: String = _env("BAL_SPELL", "")
	if forced != "" and c.knows_ability(forced) and _ability_db().has(forced):
		best = _ability_db()[forced]
		best["id"] = forced
	if c.knows_ability("cure"):
		rules.append(_rule([_cond("ally_hp_percent", {"op": "<=", "value": 50}),
				_cond("mp_percent", {"op": ">=", "value": 20})],
				[{"type": "ability", "id": "cure", "target": "lowest_hp_ally", "upgrades": ["cura"]}]))
	if not best.is_empty():
		var conds: Array = [_cond("always")]
		if int(best.get("mp_cost", 0)) > 0:
			conds = [_cond("mp_percent", {"op": ">=", "value": _mp_gate(c, best, 1)})]
		rules.append(_rule(conds, [{"type": "ability", "id": str(best["id"]), "target": "lowest_hp_enemy"}]))
	if _env("BAL_CHANNEL", "1") != "0" and c.knows_ability("channel"):
		rules.append(_rule([_cond("always")], [{"type": "ability", "id": "channel", "target": "self"}]))
	else:
		rules.append(_rule([_cond("always")], [{"type": "attack", "target": "lowest_hp_enemy"}]))
	return {"rules": rules}


## Per-job damage out of the resolver's own log lines. A hit is credited to the name the line starts with; group and formation hits go to one shared row.
var _tally: Dictionary = {}
var _tally_actions: Dictionary = {}
var _tally_other: Dictionary = {}
var _tally_last: String = ""
var _dry: Dictionary = {}
var _rx: Dictionary = {}

func _tally_rx() -> void:
	if not _rx.is_empty():
		return
	for k in [["attack", "^(.+?) attacks (.+) for (\\d+)$"], ["cast", "^(.+?) (?:casts|uses) (\\w+) on (.+) for (\\d+)$"],
			["nomp", "^(.+?) has no MP for (\\w+)$"], ["mp", "^(.+?) restores (\\d+) MP to (.+)$"],
			["defer", "^(.+?) defers$"], ["group", "^(.+?) (?:hits|strikes|blasts|crushes) (.+) for (\\d+)!$"]]:
		_rx[k[0]] = RegEx.create_from_string(k[1])


func _tally_hit(job: String, move: String, weak: String, dmg: int, new_action: bool) -> void:
	var by_move: Dictionary = _tally.get(job, {})
	var row: Dictionary = by_move.get(move + "|" + weak, {"dmg": 0, "hits": 0})
	row["dmg"] = int(row["dmg"]) + dmg
	row["hits"] = int(row["hits"]) + 1
	by_move[move + "|" + weak] = row
	_tally[job] = by_move
	if new_action:
		_tally_actions[job] = int(_tally_actions.get(job, 0)) + 1


func _tally_note(job: String, what: String) -> void:
	var d: Dictionary = _tally_other.get(job, {})
	d[what] = int(d.get(what, 0)) + 1
	_tally_other[job] = d


## `state` is one trial's {job: casts so far, job+"!": true once it stopped casting}; it outlives the chain's links.
func _tally_log(log: Array, jobs_by_name: Dictionary, mods_by_name: Dictionary, state: Dictionary) -> void:
	_tally_rx()
	_tally_last = ""
	for raw in log:
		var line: String = str(raw)
		var m: RegExMatch = _rx["cast"].search(line)
		if m != null and jobs_by_name.has(m.get_string(1)):
			var job: String = jobs_by_name[m.get_string(1)]
			var aid: String = m.get_string(2)
			var row: Dictionary = _ability_db().get(aid, {})
			var elem: String = str(row.get("element", ""))
			var mod: float = float((mods_by_name.get(m.get_string(3), {}) as Dictionary).get(elem, 1.0)) if elem != "" else 1.0
			var weak: String = "weak" if mod > 1.0 else ("resist" if mod < 1.0 else "plain")
			var key: String = m.get_string(1) + ">" + aid
			var spread: bool = str(row.get("target_type", "")) == "all_enemies"
			var fresh: bool = not (spread and _tally_last == key)
			_tally_hit(job, aid, weak, int(m.get_string(4)), fresh)
			_tally_last = key
			if fresh and int(row.get("mp_cost", 0)) > 0 and not state.has(job + "!"):
				state[job] = int(state.get(job, 0)) + 1
			continue
		_tally_last = ""
		m = _rx["attack"].search(line)
		if m != null and jobs_by_name.has(m.get_string(1)):
			_tally_hit(jobs_by_name[m.get_string(1)], "attack", "plain", int(m.get_string(3)), true)
			state[str(jobs_by_name[m.get_string(1)]) + "!"] = true
			continue
		m = _rx["nomp"].search(line)
		if m != null and jobs_by_name.has(m.get_string(1)):
			_tally_note(jobs_by_name[m.get_string(1)], "no-MP fizzle")
			_tally_actions[jobs_by_name[m.get_string(1)]] = int(_tally_actions.get(jobs_by_name[m.get_string(1)], 0)) + 1
			state[str(jobs_by_name[m.get_string(1)]) + "!"] = true
			continue
		m = _rx["mp"].search(line)
		if m != null and jobs_by_name.has(m.get_string(1)):
			_tally_note(jobs_by_name[m.get_string(1)], "MP restore")
			_tally_actions[jobs_by_name[m.get_string(1)]] = int(_tally_actions.get(jobs_by_name[m.get_string(1)], 0)) + 1
			state[str(jobs_by_name[m.get_string(1)]) + "!"] = true
			continue
		m = _rx["defer"].search(line)
		if m != null and jobs_by_name.has(m.get_string(1)):
			_tally_note(jobs_by_name[m.get_string(1)], "defer")
			continue
		m = _rx["group"].search(line)
		if m != null:
			_tally_hit("(group/formation)", m.get_string(1), "plain", int(m.get_string(3)), false)


func _tally_close(state: Dictionary, jobs: Array) -> void:
	for job in jobs:
		var d: Dictionary = _dry.get(job, {"casts": 0, "trials": 0, "dry": 0})
		d["casts"] = int(d["casts"]) + int(state.get(job, 0))
		d["trials"] = int(d["trials"]) + 1
		if state.has(str(job) + "!"):
			d["dry"] = int(d["dry"]) + 1
		_dry[job] = d


func _print_tally(trials: int) -> void:
	var totals: Dictionary = {}
	var grand: int = 0
	for job in _tally:
		var t: int = 0
		for k in _tally[job]:
			t += int(_tally[job][k]["dmg"])
		totals[job] = t
		grand += t
	print("[BAL] ===== DAMAGE by job, %d trials (credited by the log line's first name) =====" % trials)
	for job in totals:
		var acts: int = int(_tally_actions.get(job, 0))
		print("[BAL] %-18s share %5.1f%%  total %7d  actions %5d  dmg/action %7.1f  other %s" % [job,
				100.0 * totals[job] / maxi(1, grand), totals[job], acts,
				(float(totals[job]) / acts if acts > 0 else 0.0), str(_tally_other.get(job, {}))])
		for k in _tally[job]:
			var r: Dictionary = _tally[job][k]
			print("[BAL]     %-22s hits %5d  mean %7.1f" % [k, int(r["hits"]), float(r["dmg"]) / maxi(1, int(r["hits"]))])
	for job in _dry:
		var d: Dictionary = _dry[job]
		if int(d["casts"]) > 0:
			print("[BAL] %-18s paid casts before the first swing/restore/fizzle: %.2f mean; stopped casting in %d/%d trials" % [job,
					float(d["casts"]) / maxi(1, int(d["trials"])), int(d["dry"]), int(d["trials"])])
	print("")


## {enemy name: {element: modifier}} read off the spawned foes, so a logged hit can be called weak or plain.
func _elemental_mods(enemies: Array) -> Dictionary:
	var out: Dictionary = {}
	for e in enemies:
		var d: Dictionary = {}
		for el in ["fire", "ice", "lightning", "dark", "holy", "earth", "wind", "water", "poison"]:
			d[el] = float(e.calculate_elemental_modifier(el))
		out[str(e.combatant_name)] = d
	return out


## BAL_READS=1: the rows a player who reads the weakness writes above the preset's own attack rows, with conditions the grid editor already has:
## for each element the member has a one-foe damage spell of, "an enemy is weak to it -> the best such spell, at the weak foe". Returns how many rows went in.
func _add_weakness_rules(c, rules: Array) -> int:
	var best: Dictionary = {}
	for aid in _ability_db():
		var raw: Variant = _ability_db()[aid]
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		var el: String = str(row.get("element", ""))
		if el == "" or not (str(row.get("type", "")) in ["magic", "physical"]) or not row.has("damage_multiplier"):
			continue
		if str(row.get("target_type", "")) != "single_enemy" or not c.knows_ability(str(aid)):
			continue
		if not best.has(el) or float(row["damage_multiplier"]) > float(best[el]["damage_multiplier"]):
			var keep: Dictionary = row.duplicate()
			keep["id"] = str(aid)
			best[el] = keep
	var at: int = rules.size()
	for i in range(rules.size()):
		var acts: Array = (rules[i] as Dictionary).get("actions", [])
		if acts.is_empty():
			continue
		var first: Dictionary = acts[0]
		if str(first.get("type", "")) == "attack" or str(first.get("target", "")).contains("enemy") or str(first.get("target", "")) == "weakest_to_ability":
			at = i
			break
	var added: int = 0
	for el in best:
		var r: Dictionary = best[el]
		var conds: Array = [_cond("enemy_weak_to", {"element": el})]
		if int(r.get("mp_cost", 0)) > 0:
			conds.append(_cond("mp_percent", {"op": ">=", "value": _mp_gate(c, r, 1)}))
		rules.insert(at + added, _rule(conds, [{"type": "ability", "id": str(r["id"]), "target": "weakest_to_ability"}]))
		added += 1
	return added


## Installs the path's script per member and VERIFIES IT TOOK. Returns {character_id: label}.
func _install_path_scripts(path: String, party: Array) -> Dictionary:
	var picked: Dictionary = {}
	var abs_node = root.get_node_or_null("AutobattleSystem")
	if abs_node == null:
		if path != "default":
			_die("BAL_PATH=%s needs AutobattleSystem, which is absent" % path)
		return picked
	abs_node.reset_rule_fire_counts()
	if path == "default":
		return picked
	var templates: Dictionary = _balanced_templates() if path == "auto" else {}
	if path == "auto" and templates.is_empty():
		_die("BAL_PATH=auto: no stance=balanced rows in data/autobattle_rule_templates.json")
		return picked
	for c in party:
		var cid: String = _char_id(c)
		var jid: String = _job_id(c)
		var script: Dictionary = {}
		var label: String = ""
		match path:
			"auto":
				if not templates.has(jid):
					_die("BAL_PATH=auto: job '%s' has no balanced template, so %s would keep its DEFAULT script while the row wore the auto label" % [jid, cid])
					continue
				var tpl: Dictionary = templates[jid]
				script = {"rules": (tpl.get("rules", []) as Array).duplicate(true)}
				label = str(tpl.get("id", "?"))
				if _env("BAL_READS", "0") == "1":
					var added: int = _add_weakness_rules(c, script["rules"])
					label += " + reads the weakness (%d row(s))" % added
			"manual":
				script = _manual_script(c)
				label = "Default to AP3 then Brave x3"
			"oneshot":
				script = _oneshot_script(c)
				label = "zero damage until setup_complete, then x4"
			"best":
				script = _best_script(c)
				label = "best single-target move every turn"
		## Grammar only. NOT the deep check: AutobattleSystem's own comment records that four
		## SHIPPED presets fail it, because a per-rule scope cannot see the 0-MP rule above the
		## catch-all. Behaviour is judged by the FIRE COUNTS after the sweep instead.
		var bad: Array[String] = []
		for rule in (script.get("rules", []) as Array):
			for e in abs_node.validate_rule(rule):
				bad.append(str(e))
		if not bad.is_empty():
			_die("BAL_PATH=%s built an invalid script for %s: %s" % [path, cid, str(bad)])
			continue
		abs_node.set_character_script(cid, script)
		## Read back through the CONSUMER's accessor — execute_grid_autobattle calls exactly this
		## one. A write that did not take would leave the default script wearing the path's label,
		## which is the single failure this harness cannot survive, so it is a hard stop.
		var wrote: int = (script.get("rules", []) as Array).size()
		var reads: int = (abs_node.get_character_script(cid).get("rules", []) as Array).size()
		if reads != wrote:
			_die("set_character_script(%s) did not take: wrote %d rules, get_character_script reads %d" % [cid, wrote, reads])
			continue
		picked[cid] = label
	abs_node.reset_rule_fire_counts()
	return picked


## THE LABEL'S ONLY PROOF. Installing a script says nothing about whether its distinctive rule ever
## ran: a party that dies during setup produces a perfectly clean 0% row whose script never reached
## its burst. `_rule_fire_counts` is the game's own per-rule counter (AutobattleSystem:200, added so
## that a rule which never fires stops being invisible), summed over the whole sweep because the
## harness writes the scripts once, before trial 0, and nothing resets them after.
func _print_fire_counts(path: String, cids: Array) -> void:
	var abs_node = root.get_node_or_null("AutobattleSystem")
	if abs_node == null:
		return
	print("[BAL] rule fires over the whole run (path=%s); r0 is the top row and first match wins:" % path)
	for cid in cids:
		var fired: Dictionary = abs_node.get_rule_fire_counts(str(cid))
		var turns: int = int(abs_node.get_rule_eval_count(str(cid)))
		var n: int = (abs_node.get_character_script(str(cid)).get("rules", []) as Array).size()
		var parts: Array[String] = []
		for i in range(n):
			parts.append("r%d=%d" % [i, int(fired.get(i, 0))])
		var note: String = ""
		## ⛔ THE DEGENERATE CASE IS THE ONE THAT LOOKS LIKE DATA. A path whose only firing row is
		## its `always` catch-all measured the FALLBACK, and every path has one, so three columns
		## can be three names for the same behaviour and nothing in a win rate says so. Measured on
		## the Calibrant: the engine's own automatic group attack (_try_group_attack runs BEFORE any
		## rule is consulted, and a formation special has no enemy-count gate) consumes the whole
		## party's AP every cooldown window, so no AP-gated row above 1 can ever reach its bank.
		var only_catch_all: bool = not fired.is_empty() and n > 1
		for i in range(n - 1):
			if int(fired.get(i, 0)) > 0:
				only_catch_all = false
		if turns > 0 and fired.is_empty():
			note = "   ** NO RULE EVER FIRED — this row measured the default plain attack **"
		elif only_catch_all:
			note = "   ** ONLY THE CATCH-ALL FIRED — this row measured the fallback, not the path **"
		elif turns > 0 and int(fired.get(0, 0)) == 0 and path == "oneshot":
			note = "   ** setup_complete NEVER HELD — read the valve row (r1), not the label **"
		print("[BAL]   %-10s turns=%-5d %s%s" % [str(cid), turns, " ".join(parts), note])


## One party bag, because that is what the game has: ItemSystem.party_item_count SUMS the members'
## inventories and the resolver mirrors the party into BattleManager.player_party, so
## AutobattleSystem._get_item_count reads the same sum its execution will spend from. Writing the
## same count to five members would be five bags.
func _fill_bag(party: Array) -> void:
	var spec := _env("BAL_BAG", "")
	if spec == "" or party.is_empty():
		return
	for pair in spec.split(",", false):
		var bits := str(pair).split(":", false)
		if bits.size() == 2:
			party[0].inventory[str(bits[0]).strip_edges()] = int(bits[1])


func _print_bag_block(party: Array) -> void:
	var parts: Array[String] = []
	for iid in ["potion", "hi_potion", "ether", "antidote", "phoenix_down"]:
		var n: int = 0
		for c in party:
			n += int(c.get_item_count(iid))
		parts.append("%s=%d" % [iid, n])
	print("[BAL] bag as every item_count condition reads it: %s" % " ".join(parts))
