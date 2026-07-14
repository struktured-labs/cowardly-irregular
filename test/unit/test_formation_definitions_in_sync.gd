extends GutTest

## The six formation specials are defined TWICE — BattleCommandMenu.
## FORMATIONS (interactive battle) and HeadlessBattleResolver.FORMATIONS
## (autogrind). They agree today, but they're hand-maintained mirrors:
## a drift (added formation, tweaked ap_cost / required_jobs) would make
## a formation trigger in manual play but not autogrind, or resolve with
## a different AP cost — a SILENT parity break that also violates the
## "autogrind: no hidden yield tax" design ruling (autogrind must match
## interactive, never be secretly cheaper/costlier). This ratchet fails
## the moment one copy is edited without the other. Only the gameplay
## fields are compared — the menu's display-only name/tooltip may differ.
## Also covers ACTION_SPEEDS (BattleManager vs HeadlessBattleResolver) —
## same interactive/autogrind mirror, drives speed-sorted turn order.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const MENU := preload("res://src/battle/BattleCommandMenu.gd")
const BATTLE_MANAGER := preload("res://src/battle/BattleManager.gd")


func _gameplay_map(formations: Array) -> Dictionary:
	var out: Dictionary = {}
	for f in formations:
		out[str(f["id"])] = {
			"required_jobs": f.get("required_jobs", []),
			"min_members": int(f.get("min_members", -1)),
			"ap_cost": int(f.get("ap_cost", -1)),
		}
	return out


func test_same_formation_id_set() -> void:
	var r := _gameplay_map(RESOLVER.FORMATIONS)
	var m := _gameplay_map(MENU.FORMATIONS)
	assert_eq(r.keys().size(), 6, "resolver must define 6 formations")
	var r_ids: Array = r.keys(); r_ids.sort()
	var m_ids: Array = m.keys(); m_ids.sort()
	assert_eq(r_ids, m_ids,
		"the two FORMATIONS copies must define the SAME formation ids — a missing one silently can't trigger in that battle path")


func test_gameplay_fields_match_per_formation() -> void:
	var r := _gameplay_map(RESOLVER.FORMATIONS)
	var m := _gameplay_map(MENU.FORMATIONS)
	var drift: Array = []
	for fid in r:
		if not m.has(fid):
			continue
		# required_jobs order matters for the detection match — compare as-is
		if str(r[fid]["required_jobs"]) != str(m[fid]["required_jobs"]):
			drift.append("%s.required_jobs: resolver=%s menu=%s" % [fid, r[fid]["required_jobs"], m[fid]["required_jobs"]])
		if r[fid]["min_members"] != m[fid]["min_members"]:
			drift.append("%s.min_members: resolver=%d menu=%d" % [fid, r[fid]["min_members"], m[fid]["min_members"]])
		if r[fid]["ap_cost"] != m[fid]["ap_cost"]:
			drift.append("%s.ap_cost: resolver=%d menu=%d (autogrind/interactive AP parity break)" % [fid, r[fid]["ap_cost"], m[fid]["ap_cost"]])
	assert_eq(drift.size(), 0,
		"formation gameplay fields drifted between the two copies: %s" % str(drift))


func test_action_speeds_match_across_battle_paths() -> void:
	# ACTION_SPEEDS drives execution ORDER (speed-sorted). It's mirrored
	# in BattleManager (interactive) and HeadlessBattleResolver
	# (autogrind); a drift would resolve the same actions in a different
	# order between the two paths — a silent parity break.
	var bm: Dictionary = BATTLE_MANAGER.ACTION_SPEEDS
	var res: Dictionary = RESOLVER.ACTION_SPEEDS
	var drift: Array = []
	for key in bm:
		if not res.has(key):
			drift.append("%s: missing from resolver" % key)
		elif int(res[key]) != int(bm[key]):
			drift.append("%s: manager=%d resolver=%d" % [key, int(bm[key]), int(res[key])])
	for key in res:
		if not bm.has(key):
			drift.append("%s: missing from BattleManager" % key)
	assert_eq(drift.size(), 0,
		"ACTION_SPEEDS drifted between interactive + autogrind battle paths (turn-order parity break): %s" % str(drift))
