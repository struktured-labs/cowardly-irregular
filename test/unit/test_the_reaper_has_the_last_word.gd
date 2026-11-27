extends GutTest
## 2026-11-27 (cowir-story; main 28204): a grind meta-boss that wipes the party ends the session on the Summary, so its
## `player_wiped` line belongs there: AutogrindController keeps it as `meta_boss_last_word`, and the Summary's advice slot shows it.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SUMMARY := "res://src/ui/autogrind/AutogrindSummary.gd"
const CONTROLLER := "res://src/autogrind/AutogrindController.gd"

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	AutogrindState.restore(_ag)


func _texts(n: Node, acc: Array) -> Array:
	if n is Label:
		acc.append(str(n.text))
	for c in n.get_children():
		_texts(c, acc)
	return acc


func _built(id: String) -> Dictionary:
	for _i in 200:
		for collapse in [false, true]:
			var d: Dictionary = AutogrindSystem.build_meta_boss_enemy_data(collapse)
			if str(d.get("id", "")) == id:
				return d
	return {}


func test_every_grind_meta_boss_has_a_wipe_line() -> void:
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var judged := 0
	for id in monsters:
		if not (monsters[id] is Dictionary) or not bool(monsters[id].get("autogrind_spawned", false)):
			continue
		judged += 1
		var d := _built(str(id))
		assert_false(d.is_empty(), "CONTROL: the real builder produced %s" % id)
		var line: String = load(CONTROLLER).meta_boss_wipe_line(d)
		assert_true(line.begins_with(str(d.get("name", "")) + ": "), "%s's wipe line is signed with its name: '%s'" % [id, line])
		var want: Array = (monsters[id].get("dialogue", {}) as Dictionary).get("player_wiped", [])
		assert_gt(want.size(), 0, "%s has a wipe line" % id)
		if want.size() > 0:
			assert_true(line.ends_with(str(want[0])), "%s says its own words" % id)
	assert_gt(judged, 1, "CONTROL: the autogrind roster was read")


func test_the_wipe_line_is_kept_before_the_stop_and_reported() -> void:
	var src := FileAccess.get_file_as_string(CONTROLLER)
	var keep := src.find("_meta_boss_last_word = meta_boss_wipe_line(_current_meta_boss_data)")
	assert_gt(keep, 0, "CONTROL: the meta-boss defeat branch keeps its wipe line")
	assert_eq(src.find('stop_grind("Defeated by meta-boss")', keep), src.find('stop_grind("Defeated by meta-boss")'), "kept BEFORE stop_grind, which clears the boss data")
	var c: Node = load(CONTROLLER).new()
	add_child_autofree(c)
	c._meta_boss_last_word = "Permadeath Reaper: x"
	assert_eq(str(c.get_grind_stats().get("meta_boss_last_word", "")), "Permadeath Reaper: x", "the final stats carry it to the Summary")


func test_the_summary_shows_the_last_word() -> void:
	var line := "Permadeath Reaper: You staked it. I only kept the bet."
	var s: Node = load(SUMMARY).new()
	add_child_autofree(s)
	s.setup({"battles_won": 7, "total_exp": 120, "elapsed_seconds": 90.0, "meta_boss_last_word": line}, "Defeated by meta-boss")
	await wait_frames(3)
	assert_has(_texts(s, []), line, "the Summary shows the meta-boss's last word")


func test_an_ordinary_stop_shows_no_last_word() -> void:
	## CONTROL: without the key, the Summary renders nothing signed by a meta-boss.
	var s: Node = load(SUMMARY).new()
	add_child_autofree(s)
	s.setup({"battles_won": 7, "total_exp": 120, "elapsed_seconds": 90.0}, "Manual stop")
	await wait_frames(3)
	for t in _texts(s, []):
		assert_false(str(t).begins_with("Permadeath Reaper:") or str(t).begins_with("Adaptive Slime:"), "no meta-boss speaks on an ordinary stop: '%s'" % t)
