extends RefCounted
## The job ids of a given TYPE, derived from data/jobs.json.
##
## ⛔ A HAND-LISTED ROSTER IS A CORPUS THAT SHRINKS QUIETLY. A guard listing its own jobs keeps
## checking exactly the jobs it listed: add a starter and the guard stays green while covering one
## fewer. Both sprite guards that hand-listed one were CORRECT when measured 2026-09-17 — which is
## the point. Correct today and kept correct by nothing is the shape this fleet closed eight times
## in one day, in eight different subsystems.
##
## Types are CLAUDE.md's: 0 starter · 1 advanced · 2 meta.
const JOBS := "res://data/jobs.json"


static func of_types(types: Array) -> Array[String]:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(JOBS))
	if not (parsed is Dictionary):
		return []
	var out: Array[String] = []
	for id in (parsed as Dictionary):
		var rec = (parsed as Dictionary)[id]
		if rec is Dictionary and types.has(int((rec as Dictionary).get("type", -1))):
			out.append(str(id))
	out.sort()
	return out
