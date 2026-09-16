extends SceneTree

## Renders REAL Rule Composer prompts for tools/llm_prompt_bench.py.
##
## Everything here goes through DialoguePrompts and the shipped data. A benchmark that
## measures a hand-written approximation of a prompt measures the approximation — the
## whole point is that the bytes sent are the bytes the game sends.
##
## Kit context is shaped exactly as AutobattleSystem.get_deep_check_kit returns it. It is
## rebuilt from jobs.json here rather than called, because a `-s` script has no autoloads;
## an arm in test_the_kit_is_restated_where_it_is_used pins the shape this must match.

const OUT := "res://tmp/llm_prompt_bench"

const ASKS := [
	{"key": "fighter_basic", "domain": "autobattle", "job": "fighter",
	 "text": "attack the weakest enemy and use a potion when i am hurt"},
	{"key": "cleric_heal", "domain": "autobattle", "job": "cleric",
	 "text": "keep everyone alive, heal whoever is hurt worst and cure status"},
	{"key": "mage_nuke", "domain": "autobattle", "job": "mage",
	 "text": "hit weaknesses with magic, save MP when low"},
	{"key": "rogue_fast", "domain": "autobattle", "job": "rogue",
	 "text": "go for the fastest enemy first and steal when you can"},
	{"key": "bard_support", "domain": "autobattle", "job": "bard",
	 "text": "buff the party early then debuff whatever hits hardest"},
	{"key": "grind_safe", "domain": "autogrind", "job": "",
	 "text": "stop if anyone dies or the party gets low, and heal between fights"},
	{"key": "grind_long", "domain": "autogrind", "job": "",
	 "text": "grind for a long session but bail out if corruption gets high"},
]


func _kit_for(job_id: String) -> Dictionary:
	if job_id == "":
		return {}
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var job_root: Dictionary = jobs.get("jobs", jobs)
	if not job_root.has(job_id):
		return {}
	var job: Dictionary = job_root[job_id]
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ab_root: Dictionary = abilities.get("abilities", abilities)
	var kit: Array = (job.get("abilities", []) as Array).duplicate()
	var free_move: Dictionary = job.get("free_move", {})
	if free_move.has("ability_id"):
		kit.append(free_move["ability_id"])
	var full_kit: Array = kit.duplicate()
	for lvl in (job.get("abilities_at_level", {}) as Dictionary).keys():
		for aid in (job["abilities_at_level"][lvl] as Array):
			full_kit.append(aid)
	var costs: Dictionary = {}
	for aid in kit:
		costs[str(aid)] = int((ab_root.get(str(aid), {}) as Dictionary).get("mp_cost", 0))
	return {
		"resolved": true, "job_id": job_id, "kit": kit, "full_kit": full_kit,
		"max_mp": int((job.get("stat_modifiers", {}) as Dictionary).get("max_mp", 1)),
		"costs": costs,
	}


func _init() -> void:
	var DP = load("res://src/llm/DialoguePrompts.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var scenarios: Array = []
	for ask in ASKS:
		var prompt: String = DP.build_rule_composition(
			str(ask["domain"]), str(ask["text"]), [], _kit_for(str(ask["job"])))
		var path: String = "%s/%s.txt" % [OUT, str(ask["key"])]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(prompt)
		f.close()
		scenarios.append({
			"key": str(ask["key"]), "domain": str(ask["domain"]),
			"ask": str(ask["text"]), "path": ProjectSettings.globalize_path(path),
		})
		print("rendered %s (%d chars)" % [str(ask["key"]), prompt.length()])
	var mf := FileAccess.open("%s/manifest.json" % OUT, FileAccess.WRITE)
	mf.store_string(JSON.stringify({"scenarios": scenarios}))
	mf.close()
	quit()
