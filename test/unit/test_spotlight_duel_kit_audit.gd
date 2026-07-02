extends GutTest

## Pre-playtest hazard from the 2026-07-01 spotlight-duels handoff:
## "Cleric duel win (survive_turns) needs `pray` reachable at ch1 —
## kit-audited OK, but verify." This suite makes that audit permanent:
## each duel's PC must have the TOOLS its win condition demands, at
## the data level, so a jobs.json / abilities.json / monsters.json
## edit can't silently make a duel unwinnable. All checks are
## deterministic reads of the shipped JSON — no simulation.

var _monsters: Dictionary
var _jobs: Dictionary
var _abilities: Dictionary

const DUELS := {
	"fighter": "fighter_skeleton_knight",
	"cleric": "cleric_survive_target",
	"rogue": "rogue_lockward",
	"mage": "mage_prismatic_construct",
	"bard": "bard_hostile_courtier",
}


func before_all() -> void:
	_monsters = _load_collection("res://data/monsters.json", "monsters")
	_jobs = _load_collection("res://data/jobs.json", "jobs")
	_abilities = _load_collection("res://data/abilities.json", "abilities")


func _load_collection(path: String, key: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var body: Variant = raw[key] if (raw is Dictionary and raw.has(key)) else raw
	if body is Array:
		var by_id: Dictionary = {}
		for entry in body:
			by_id[entry.get("id", "")] = entry
		return by_id
	return body


## Kit at duel level = base abilities + everything unlocked at or
## below the miniboss level via abilities_at_level.
func _kit_at_duel_level(job_id: String) -> Array:
	var job: Dictionary = _jobs[job_id]
	var duel_level: int = int(_monsters[DUELS[job_id]].get("level", 1))
	var kit: Array = (job.get("abilities", []) as Array).duplicate()
	var by_level: Dictionary = job.get("abilities_at_level", {})
	for lvl_key in by_level:
		if int(str(lvl_key)) <= duel_level:
			kit.append_array(by_level[lvl_key])
	return kit


func test_all_duel_minibosses_configured() -> void:
	for pc in DUELS:
		var mid: String = DUELS[pc]
		assert_true(_monsters.has(mid), "%s must exist in monsters.json" % mid)
		var m: Dictionary = _monsters[mid]
		assert_true(bool(m.get("spotlight_duel", false)), "%s must be flagged spotlight_duel" % mid)
		assert_eq(str(m.get("spotlight_pc", "")), pc)
		var stats: Dictionary = m.get("stats", {})
		assert_gt(int(stats.get("max_hp", 0)), 0, "%s needs real stats" % mid)
		assert_true(_abilities.has(str(m.get("signature_ability", ""))),
			"%s signature_ability must resolve in abilities.json" % mid)


func test_cleric_can_sustain_the_survive_duel() -> void:
	var kit := _kit_at_duel_level("cleric")
	# Pray (free move) is the MP engine the duel is designed around.
	var free_move: Dictionary = _jobs["cleric"].get("free_move", {})
	assert_eq(str(free_move.get("ability_id", "")), "pray")
	var pray: Dictionary = _abilities.get("pray", {})
	var pray_mp: int = int(pray.get("mp_amount", 0))
	assert_gt(pray_mp, 0, "pray must restore MP or the sustain loop breaks")
	# A real heal must be in the base-or-duel-level kit...
	var best_heal: Dictionary = {}
	for aid in kit:
		var a: Dictionary = _abilities.get(str(aid), {})
		if int(a.get("heal_amount", 0)) > int(best_heal.get("heal_amount", 0)):
			best_heal = a
	assert_gt(int(best_heal.get("heal_amount", 0)), 0,
		"cleric kit at duel level must contain a heal with heal_amount")
	# ...and be castable every other turn on pray income alone
	# (cast turn + pray turn = infinite sustain regardless of MP pool).
	assert_true(int(best_heal.get("mp_cost", 999)) <= pray_mp * 2,
		"heal must be affordable on a heal/pray alternation (cost ≤ 2× pray income)")
	# Incoming pressure must stay below that sustain: attack per round
	# ≤ half the heal per 2-round cycle, with the survive window sane.
	var target: Dictionary = _monsters["cleric_survive_target"]
	var wc: Dictionary = target.get("win_condition", {})
	assert_eq(str(wc.get("type", "")), "survive_turns")
	assert_between(int(wc.get("value", 0)), 4, 12, "survive window sanity band")
	var atk: int = int(target.get("stats", {}).get("attack", 0))
	assert_true(atk * 2 <= int(best_heal.get("heal_amount", 0)) + 20,
		"survive-target attack (%d/round) must not out-pace the heal cycle (%d per 2 rounds + bulk margin)" % [atk, int(best_heal.get("heal_amount", 0))])


func test_bard_can_reach_three_sways() -> void:
	var kit := _kit_at_duel_level("bard")
	var songs: Array = []
	for aid in kit:
		var a: Dictionary = _abilities.get(str(aid), {})
		if str(a.get("type", "")) == "song":
			songs.append(a)
	assert_gt(songs.size(), 0, "bard kit at duel level must contain songs — sways only count off type=='song'")
	# Riff (free move) must out-earn the cheapest song on a 2-turn
	# cycle so 3 sways are reachable from any MP state.
	assert_eq(str(_jobs["bard"].get("free_move", {}).get("ability_id", "")), "riff")
	var riff_mp: int = int(_abilities.get("riff", {}).get("mp_amount", 0))
	var cheapest: int = 9999
	for s in songs:
		cheapest = mini(cheapest, int(s.get("mp_cost", 9999)))
	assert_true(cheapest <= riff_mp * 2,
		"cheapest song (%d MP) must be affordable on a song/riff alternation (%d per 2 turns)" % [cheapest, riff_mp])
	var wc: Dictionary = _monsters["bard_hostile_courtier"].get("win_condition", {})
	assert_eq(str(wc.get("status", "")), "swayed")
	assert_between(int(wc.get("value", 0)), 1, 6, "sway threshold sanity band")


func test_mage_can_exploit_the_weakness_cycle() -> void:
	var kit := _kit_at_duel_level("mage")
	var weaknesses: Array = _monsters["mage_prismatic_construct"].get("weaknesses", [])
	assert_gt(weaknesses.size(), 1, "prismatic construct must cycle across 2+ weaknesses")
	var covered: Dictionary = {}
	for aid in kit:
		var a: Dictionary = _abilities.get(str(aid), {})
		var el: String = str(a.get("element", "")) if a.get("element") != null else ""
		if el != "" and el in weaknesses:
			covered[el] = true
	assert_eq(covered.size(), weaknesses.size(),
		"mage kit at duel level must cover EVERY cycled weakness %s (covered: %s)" % [str(weaknesses), str(covered.keys())])


func test_physical_duels_are_killable_in_reasonable_rounds() -> void:
	# Fighter and Rogue duels are straight hp_zero fights. Guard the
	# tuning relation: miniboss HP must fall within ~20 rounds of the
	# PC's basic output (atk − def/2 floor-1 per the damage formula),
	# using the miniboss's OWN attack stat as a same-tier proxy for
	# the PC's — keeps the check data-only and level-independent.
	for pc in ["fighter", "rogue"]:
		var m: Dictionary = _monsters[DUELS[pc]]
		var stats: Dictionary = m.get("stats", {})
		var proxy_atk: int = int(stats.get("attack", 0))
		var per_round: int = maxi(1, proxy_atk - int(stats.get("defense", 0)) / 2)
		assert_true(per_round * 20 >= int(stats.get("max_hp", 0)),
			"%s: %d HP needs ≤20 rounds at ~%d dmg/round — duel would drag past its welcome" % [DUELS[pc], int(stats.get("max_hp", 0)), per_round])


func test_sway_tracking_reaches_the_courtier() -> void:
	# BattleManager counts sways for tracks_sway_stacks monsters OR the
	# hardcoded courtier id. The data currently relies on the id
	# fallback — pin that at least ONE of the two hooks is live so a
	# rename doesn't silently orphan the win condition.
	var m: Dictionary = _monsters["bard_hostile_courtier"]
	var id_hook: bool = str(m.get("id", "")) == "bard_hostile_courtier"
	var data_hook: bool = bool(m.get("tracks_sway_stacks", false))
	assert_true(id_hook or data_hook,
		"courtier must be reachable by the sway counter (id fallback or tracks_sway_stacks)")
