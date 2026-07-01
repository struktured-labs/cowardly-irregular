extends GutTest

## Structural regression for the 5 spotlight-duel minibosses in monsters.json.
##
## Per cowir-main spec msg 1950 + win-condition schema msg 1963:
##   fighter_skeleton_knight — hp_zero (default)
##   cleric_survive_target   — survive_turns 8
##   rogue_lockward          — hp_zero (default)
##   mage_prismatic_construct — hp_zero (default)
##   bard_hostile_courtier   — status_threshold "swayed" 3
##
## Guards that the 5 IDs stay wired, spotlight_pc mapping matches the starter
## jobs, and the two non-standard win_condition entries remain data-driven so
## the engine's dispatch keeps picking them up. Also pins the signature/victory
## SFX keys against cowir-sfx's manifest (msg 2012).

const MONSTERS_PATH: String = "res://data/monsters.json"

const SPOTLIGHT_IDS: Array[String] = [
	"fighter_skeleton_knight",
	"cleric_survive_target",
	"rogue_lockward",
	"mage_prismatic_construct",
	"bard_hostile_courtier",
]

const STARTER_JOBS: Array[String] = ["fighter", "cleric", "rogue", "mage", "bard"]


func _load_monsters() -> Dictionary:
	var f := FileAccess.open(MONSTERS_PATH, FileAccess.READ)
	assert_not_null(f, "monsters.json must open")
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "monsters.json root must be Dictionary")
	if not (parsed is Dictionary):
		return {}
	return parsed as Dictionary


func test_all_5_spotlight_minibosses_present() -> void:
	var data: Dictionary = _load_monsters()
	for mb_id in SPOTLIGHT_IDS:
		assert_true(data.has(mb_id),
			"spotlight miniboss '%s' must exist in monsters.json (regression: renamed/removed)" % mb_id)


func test_each_flagged_as_spotlight_duel() -> void:
	var data: Dictionary = _load_monsters()
	for mb_id in SPOTLIGHT_IDS:
		if not data.has(mb_id):
			continue
		var mb: Dictionary = data[mb_id]
		assert_true(mb.get("spotlight_duel", false) == true,
			"miniboss '%s' must have spotlight_duel: true (used by GameLoop.start_solo_battle gate)" % mb_id)


func test_spotlight_pc_matches_starter_job() -> void:
	var data: Dictionary = _load_monsters()
	for mb_id in SPOTLIGHT_IDS:
		if not data.has(mb_id):
			continue
		var pc_id: String = str(data[mb_id].get("spotlight_pc", ""))
		assert_true(pc_id in STARTER_JOBS,
			"miniboss '%s' spotlight_pc '%s' must be a starter job" % [mb_id, pc_id])


func test_cleric_uses_survive_turns_win_condition() -> void:
	var data: Dictionary = _load_monsters()
	if not data.has("cleric_survive_target"):
		return
	var wc: Dictionary = data["cleric_survive_target"].get("win_condition", {})
	assert_eq(str(wc.get("type", "")), "survive_turns",
		"cleric_survive_target must use survive_turns win_condition (essence: grace, not violence)")
	assert_eq(int(wc.get("value", 0)), 8,
		"cleric_survive_target must survive 8 turns to win (regression: tuning drift)")


func test_bard_uses_status_threshold_win_condition() -> void:
	var data: Dictionary = _load_monsters()
	if not data.has("bard_hostile_courtier"):
		return
	var wc: Dictionary = data["bard_hostile_courtier"].get("win_condition", {})
	assert_eq(str(wc.get("type", "")), "status_threshold",
		"bard_hostile_courtier must use status_threshold win_condition (essence: talked-down)")
	assert_eq(str(wc.get("status", "")), "swayed",
		"bard_hostile_courtier must check 'swayed' status stacks")
	assert_eq(int(wc.get("value", 0)), 3,
		"bard_hostile_courtier must be swayed to 3 stacks to yield (regression: tuning drift)")


func test_default_hp_zero_wins_omit_win_condition() -> void:
	var data: Dictionary = _load_monsters()
	for mb_id in ["fighter_skeleton_knight", "rogue_lockward", "mage_prismatic_construct"]:
		if not data.has(mb_id):
			continue
		var mb: Dictionary = data[mb_id]
		assert_false(mb.has("win_condition"),
			"'%s' must omit win_condition (defaults to hp_zero; explicit field breaks backward-compat semantics)" % mb_id)


func test_each_declares_signature_and_victory_sfx() -> void:
	var data: Dictionary = _load_monsters()
	for mb_id in SPOTLIGHT_IDS:
		if not data.has(mb_id):
			continue
		var mb: Dictionary = data[mb_id]
		var sig_sfx: String = str(mb.get("signature_sfx", ""))
		var vic_sfx: String = str(mb.get("victory_sfx", ""))
		assert_ne(sig_sfx, "",
			"'%s' must declare signature_sfx (cowir-sfx SFX manifest hook)" % mb_id)
		assert_ne(vic_sfx, "",
			"'%s' must declare victory_sfx (cowir-sfx SFX manifest hook)" % mb_id)
		assert_true(sig_sfx.begins_with("spotlight_"),
			"'%s' signature_sfx '%s' must follow spotlight_<job>_signature convention" % [mb_id, sig_sfx])


func test_mage_prismatic_construct_has_weakness_cycle() -> void:
	var data: Dictionary = _load_monsters()
	if not data.has("mage_prismatic_construct"):
		return
	var cycle: Array = data["mage_prismatic_construct"].get("weakness_cycle", [])
	assert_eq(cycle.size(), 3,
		"prismatic_construct must cycle through 3 elements (fire/ice/lightning)")
	for elem in ["fire", "ice", "lightning"]:
		assert_true(elem in cycle,
			"prismatic_construct weakness_cycle must include '%s'" % elem)


func test_each_has_intro_and_defeat_dialogue() -> void:
	var data: Dictionary = _load_monsters()
	for mb_id in SPOTLIGHT_IDS:
		if not data.has(mb_id):
			continue
		var d: Dictionary = data[mb_id].get("dialogue", {})
		assert_gt((d.get("intro", []) as Array).size(), 0,
			"'%s' must have intro dialogue lines" % mb_id)
		assert_gt((d.get("defeat", []) as Array).size(), 0,
			"'%s' must have defeat dialogue lines" % mb_id)
