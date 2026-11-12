extends GutTest

## cowir-autogrind's W1 audit (23731/23740): from L15 the party ended a dungeon floor in the phase its first damage
## landed. Cause, in the data: the Mage's -aga tier hit ALL enemies at x5.0, against her best single-target spell's x3.5
## (thundara) and her previous all-enemies spell's x2.2 (chain_lightning). The rule now, for every job, derived from
## jobs.json + abilities.json: a spell that hits everyone never out-hits, per target, the best single-target spell that
## job has by the same level. The -aga tier is x3.0.

## An all-enemies ability allowed to out-hit its job's single-target kit, with the reason.
const DECLARED := {
	"necro_blast": "the Necromancer is a debug-gated meta job whose single-target kit is drain utility (x1.5); its blast is its one damage spell, at 35 MP",
}


func _data(path: String, key: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "CONTROL: %s parses" % path)
	return (parsed as Dictionary).get(key, parsed) if parsed is Dictionary else {}


## [[level, ability_id]] a job learns: its starting list at level 1, then abilities_at_level.
func _kit(job: Dictionary) -> Array:
	var out: Array = []
	for id in job.get("abilities", []):
		out.append([1, str(id)])
	var by_level: Dictionary = job.get("abilities_at_level", {})
	for lv in by_level:
		var ids = by_level[lv] if by_level[lv] is Array else [by_level[lv]]
		for id in ids:
			out.append([int(lv), str(id)])
	return out


func _mult(ability: Dictionary) -> float:
	return float(ability.get("damage_multiplier", 0.0))


func test_no_all_enemies_spell_out_hits_the_jobs_best_single_target_spell() -> void:
	var jobs := _data("res://data/jobs.json", "jobs")
	var abilities := _data("res://data/abilities.json", "abilities")
	var judged := 0
	var over: Array = []
	var used := {}
	for jid in jobs:
		var kit := _kit(jobs[jid])
		for entry in kit:
			var a: Dictionary = abilities.get(entry[1], {})
			if str(a.get("target_type", "")) != "all_enemies" or _mult(a) <= 0.0 or not (str(a.get("type", "")) in ["magic", "physical"]):
				continue
			var best := 0.0
			for other in kit:
				var o: Dictionary = abilities.get(other[1], {})
				if int(other[0]) <= int(entry[0]) and str(o.get("target_type", "")) == "single_enemy" and str(o.get("type", "")) in ["magic", "physical"]:
					best = maxf(best, _mult(o))
			if best <= 0.0:
				continue
			judged += 1
			if _mult(a) > best:
				if DECLARED.has(entry[1]):
					used[entry[1]] = true
				else:
					over.append("%s: %s hits all at x%.1f, over its best single-target x%.1f by L%d" % [jid, entry[1], _mult(a), best, entry[0]])
	assert_gt(judged, 4, "CONTROL: several jobs' all-enemies spells were judged (%d)" % judged)
	assert_eq(over, [], "a spell that hits every enemy must not out-hit, per target, the job's best single-target spell")
	for id in DECLARED:
		assert_true(used.has(id), "DECLARED names %s, which no longer out-hits its job's single-target kit: delete the entry" % id)
		assert_ne(str(DECLARED[id]).strip_edges(), "", "%s needs a reason" % id)


func test_the_mages_top_tier_still_tops_her_all_enemies_ladder() -> void:
	var abilities := _data("res://data/abilities.json", "abilities")
	var chain: float = _mult(abilities.get("chain_lightning", {}))
	assert_gt(chain, 0.0, "CONTROL: chain_lightning is her earlier all-enemies spell")
	for id in ["firaga", "blizzaga", "thundaga"]:
		assert_gt(_mult(abilities.get(id, {})), chain, "%s is still a step up from chain_lightning, so the tier is worth its MP" % id)
