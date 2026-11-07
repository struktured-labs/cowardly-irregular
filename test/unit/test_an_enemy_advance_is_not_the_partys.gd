extends GutTest

## An ENEMY Advance played the PARTY's advance_flourish_N, so nothing said "a monster" (cowir-battle 23350).
## struktured via cowir-main 23349: monsters must read as powering up, with their own escalating sound and a defer cue.

const MANIFEST := "res://data/sfx_manifest.json"
const LADDER: Array[String] = ["enemy_advance_2", "enemy_advance_3", "enemy_advance_4"]


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func _file(sfx: Dictionary, key: String) -> String:
	return "res://" + str((sfx.get(key, {}) as Dictionary).get("file", ""))


func test_every_enemy_cue_exists_and_loads() -> void:
	var sfx := _sfx()
	for k in LADDER + ["enemy_defer"]:
		assert_true(sfx.has(k), "%s missing: cowir-battle's hooks fall back to the party cue pitched down" % k)
		assert_true(ResourceLoader.exists(_file(sfx, k)), "%s -> %s does not load" % [k, _file(sfx, k)])


func test_the_enemy_ladder_escalates_in_duration() -> void:
	var sfx := _sfx()
	var prev := 0.0
	var checked := 0
	for k in LADDER:
		var dur := float((sfx.get(k, {}) as Dictionary).get("duration_seconds", 0.0))
		assert_gt(dur, prev, "%s (%.2fs) must be longer than the rung below (%.2fs): the family reads as escalation" % [k, dur, prev])
		prev = dur
		checked += 1
	assert_eq(checked, LADDER.size(), "CONTROL: only %d of %d rungs checked" % [checked, LADDER.size()])


func test_no_enemy_cue_is_a_party_cue_repointed() -> void:
	var sfx := _sfx()
	var pairs := {"enemy_advance_2": "advance_flourish_2", "enemy_advance_3": "advance_flourish_3",
		"enemy_advance_4": "advance_flourish_4", "enemy_defer": "defer"}
	var same: Array[String] = []
	for k in pairs:
		var mine := _file(sfx, k)
		var theirs := _file(sfx, str(pairs[k]))
		assert_true(FileAccess.file_exists(theirs), "CONTROL: the party cue %s must exist to compare against" % pairs[k])
		if mine == theirs or FileAccess.get_sha256(mine) == FileAccess.get_sha256(theirs):
			same.append("%s == %s" % [k, pairs[k]])
	assert_eq(same, [], "an enemy cue is the party's own sound, so a monster's advance reads as a party member's: %s" % [same])
