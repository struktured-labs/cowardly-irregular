extends GutTest

## Two-sources-of-truth hardening for spotlight duel win_conditions
## (cowir-story's find, msg 2049).
##
## win_condition can be authored in TWO places:
##   1. monsters.json on the miniboss entry (data-driven default)
##   2. the cutscene battle step (scene-specific override)
## Drift between them is the bug factory — the original bug was the
## monsters.json fields being read by NOTHING while the steps carried
## no inline copy, silently degrading both special duels to HP-zero.
##
## Contracts pinned here:
##   A. GameLoop.start_solo_battle falls back to the enemy's
##      monsters.json win_condition when the step omits it.
##   B. RATCHET: wherever BOTH sources author a win_condition for the
##      same (cutscene battle step → enemy) pair, they must AGREE on
##      type/value/status. Divergence fails this test at author time
##      instead of surfacing as a wrong duel in playtest.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"
const SPOTLIGHT_CUTSCENES: Array = [
	"world1_spotlight_fighter_ch2",
	"world1_spotlight_cleric_ch1",
	"world1_spotlight_rogue_ch3",
	"world1_spotlight_mage_ch3",
	"world1_spotlight_bard_ch7",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _load_json(p: String) -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(p)
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


func test_start_solo_battle_has_monster_fallback() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func start_solo_battle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("EncounterSystem.monster_database.has(enemy_id)"),
		"start_solo_battle must look up the enemy in monster_database when the step omits win_condition")
	assert_true(body.contains("mdata.get(\"win_condition\", {})"),
		"fallback must read the monsters.json win_condition field")
	# Ordering: step override wins — the monster lookup must be the
	# elif/else branch, not the first check.
	var step_idx: int = body.find("_opts.get(\"win_condition\"")
	var monster_idx: int = body.find("mdata.get(\"win_condition\"")
	assert_gt(step_idx, -1)
	assert_gt(monster_idx, -1)
	assert_lt(step_idx, monster_idx,
		"step-inline win_condition must be checked FIRST (override); monsters.json is the fallback default")


func test_step_and_monster_sources_agree() -> void:
	# RATCHET: walk every spotlight cutscene's battle step. If the step
	# carries an inline win_condition AND the enemy's monsters.json
	# entry also authors one, the two must agree on type + value +
	# status. Catches drift at author time.
	var monsters: Dictionary = _load_json("res://data/monsters.json")
	assert_false(monsters.is_empty(), "monsters.json must parse")
	var pairs_checked: int = 0
	for cid in SPOTLIGHT_CUTSCENES:
		var cutscene: Dictionary = _load_json("res://data/cutscenes/%s.json" % cid)
		if cutscene.is_empty():
			continue
		var steps: Variant = cutscene.get("steps", [])
		if not (steps is Array):
			continue
		for step in steps:
			if not (step is Dictionary) or str((step as Dictionary).get("type", "")) != "battle":
				continue
			var enemies: Variant = (step as Dictionary).get("enemies", [])
			if not (enemies is Array) or (enemies as Array).is_empty():
				continue
			var enemy_id: String = str((enemies as Array)[0])
			var step_wc: Variant = (step as Dictionary).get("win_condition", {})
			if not (step_wc is Dictionary) or (step_wc as Dictionary).is_empty():
				continue  # no inline copy — fallback path covers it
			if not monsters.has(enemy_id):
				continue
			var monster_wc: Variant = (monsters[enemy_id] as Dictionary).get("win_condition", {})
			if not (monster_wc is Dictionary) or (monster_wc as Dictionary).is_empty():
				continue  # monster doesn't author one — inline is sole source
			pairs_checked += 1
			var s: Dictionary = step_wc
			var m: Dictionary = monster_wc
			assert_eq(str(s.get("type", "")), str(m.get("type", "")),
				"%s → %s: win_condition.type must agree between cutscene step and monsters.json" % [cid, enemy_id])
			assert_eq(int(s.get("value", 0)), int(m.get("value", 0)),
				"%s → %s: win_condition.value must agree" % [cid, enemy_id])
			assert_eq(str(s.get("status", "")), str(m.get("status", "")),
				"%s → %s: win_condition.status must agree" % [cid, enemy_id])
	# Premise guard: the cleric + bard duels currently author BOTH
	# sources, so at least 2 pairs must have been compared. If this
	# drops to 0 the ratchet has gone blind (data refactor moved the
	# fields) and needs re-pointing.
	assert_gt(pairs_checked, 1,
		"ratchet must compare at least the cleric + bard dual-source pairs — 0/1 means the data shape moved and this test went blind")


func test_special_duels_author_monster_side() -> void:
	# The monsters.json side must keep authoring win_condition for the
	# two special duels — it's the durable data-driven default that
	# survives any future cutscene rewrite.
	var monsters: Dictionary = _load_json("res://data/monsters.json")
	for pair in [["cleric_survive_target", "survive_turns"], ["bard_hostile_courtier", "status_threshold"]]:
		var mid: String = pair[0]
		var expected_type: String = pair[1]
		assert_true(monsters.has(mid), "%s must exist in monsters.json" % mid)
		var wc: Variant = (monsters[mid] as Dictionary).get("win_condition", {})
		assert_true(wc is Dictionary and not (wc as Dictionary).is_empty(),
			"%s must author win_condition in monsters.json (data-driven default)" % mid)
		assert_eq(str((wc as Dictionary).get("type", "")), expected_type,
			"%s win_condition.type must be %s" % [mid, expected_type])
