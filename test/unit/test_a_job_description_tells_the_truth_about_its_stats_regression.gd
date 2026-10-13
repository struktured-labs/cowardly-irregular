extends GutTest

## Job descriptions make STAT CLAIMS, and the job screen prints the claim and the number side by
## side — the description in the JOBS panel, the value in the STATS panel one column over. Two of
## them disagreed with their own numbers:
##
##   cleric  "Low HP but high magic"               max_hp 1080, rank  3 of 14, median 925
##   mage    "Low HP but devastating magical..."   max_hp  970, rank  5 of 14, median 925
##
## Cleric was the THIRD-highest-HP job in the game while telling the player it had low HP. Both now
## say "Low attack", which is what they actually are — ranks 13 and 14 of 14.
##
## 🛑 WHY RANK AND NOT A THRESHOLD: "low" is a claim about this job among the others, not about a
## number. A flat cutoff goes stale the moment the catalog is rebalanced — every job could gain 200
## HP and the prose would still be honest. Rank cannot drift that way.
##
## ⚠️ This guard does NOT say which side to fix. A failure means the text and the numbers disagree;
## whether the prose is stale or the balance drifted is a design call. It was called TEXT here
## because the rest of the catalog reads as intentional: the other low-HP casters (necromancer 750,
## time_mage 850, bard 850, summoner 900) are untouched, so cleric and mage were the outliers.

## phrase -> [stat, "high"|"low"]. Matched case-insensitively against the description.
const CLAIMS := {
	"high hp": ["max_hp", "high"],
	"low hp": ["max_hp", "low"],
	"high magic": ["magic", "high"],
	"devastating magical": ["magic", "high"],
	"high speed": ["speed", "high"],
	"low attack": ["attack", "low"],
	"low defence": ["defense", "low"],
	"low defense": ["defense", "low"],
}


func _jobs() -> Dictionary:
	return JobSystem.jobs


## job_id -> 1-based rank for `stat`, highest first.
func _ranks(stat: String) -> Dictionary:
	var pairs: Array = []
	for job_id in _jobs():
		var mods: Dictionary = _jobs()[job_id].get("stat_modifiers", {})
		pairs.append([int(mods.get(stat, 0)), str(job_id)])
	pairs.sort_custom(func(a, b): return a[0] > b[0])
	var out := {}
	for i in range(pairs.size()):
		out[pairs[i][1]] = i + 1
	return out


## A claim is honest when the job sits in the top third (high) or bottom third (low).
func _honest(rank: int, n: int, direction: String) -> bool:
	var third: int = maxi(1, n / 3)
	return rank <= third if direction == "high" else rank >= n - third + 1


## THE REGRESSION: a description claiming a stat the job does not have.
func test_every_stat_claim_matches_the_catalog() -> void:
	var n: int = _jobs().size()
	assert_gt(n, 5, "PRECONDITION: jobs.json must load (got %d)" % n)
	var liars: Array[String] = []
	var checked := 0
	for job_id in _jobs():
		var desc: String = str(_jobs()[job_id].get("description", "")).to_lower()
		for phrase in CLAIMS:
			if not desc.contains(phrase):
				continue
			checked += 1
			var stat: String = CLAIMS[phrase][0]
			var direction: String = CLAIMS[phrase][1]
			var rank: int = int(_ranks(stat).get(str(job_id), 0))
			if not _honest(rank, n, direction):
				var mods: Dictionary = _jobs()[job_id].get("stat_modifiers", {})
				liars.append("%s claims '%s' but %s=%s is rank %d of %d"
					% [job_id, phrase, stat, str(mods.get(stat, 0)), rank, n])
	## CONTROL: the phrase table must actually match the catalog. If an author rewords every
	## description, `checked` collapses to 0 and this file goes green while asserting nothing —
	## the vacuous pass that a bare `assert_eq(liars, [])` cannot distinguish from a clean one.
	assert_gt(checked, 5,
		"CONTROL: CLAIMS must match real descriptions — only %d matched, so this guard has gone "
		% checked + "blind to the catalog it is supposed to read")
	assert_eq(liars, [] as Array[String],
		"a job description claims a stat the job does not have, and the job screen prints the "
		+ "claim next to the number: %s" % [", ".join(liars)])


## CONTROL: the ranker and the honesty rule must both be able to say NO. Without this, a ranker
## returning 1 for everything passes the arm above on any catalog.
func test_the_ranker_and_the_rule_can_both_report_a_lie() -> void:
	var n: int = _jobs().size()
	var hp := _ranks("max_hp")
	assert_eq(hp.size(), n, "CONTROL: every job must be ranked, got %d of %d" % [hp.size(), n])
	var firsts := 0
	for job_id in hp:
		if int(hp[job_id]) == 1:
			firsts += 1
	assert_eq(firsts, 1, "CONTROL: exactly one job may be rank 1, got %d" % firsts)
	assert_false(_honest(3, 14, "low"), "CONTROL: rank 3 of 14 is NOT low — this is the cleric case")
	assert_true(_honest(13, 14, "low"), "CONTROL: rank 13 of 14 IS low — this is the fix")
	assert_true(_honest(2, 14, "high"), "CONTROL: rank 2 of 14 is high")
	assert_false(_honest(5, 14, "high"), "CONTROL: rank 5 of 14 is NOT high")


## The two that were wrong, pinned by name so a revert is unmistakable rather than one entry in a list.
func test_the_two_casters_no_longer_claim_low_hp() -> void:
	for job_id in ["cleric", "mage"]:
		var desc: String = str(_jobs()[job_id].get("description", "")).to_lower()
		assert_false(desc.contains("low hp"),
			"%s claimed 'Low HP' while ranking %d of %d in max_hp"
			% [job_id, int(_ranks("max_hp").get(job_id, 0)), _jobs().size()])
		assert_true(desc.contains("low attack"),
			"%s should name the stat it actually is low in" % job_id)
