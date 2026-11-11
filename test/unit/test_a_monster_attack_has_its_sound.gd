extends GutTest

## The W1 monster families, the tier-2 ice/thunder impacts and the wore-off beat shipped SILENT on purpose (sprites 24014,
## battle 24013/24017, adhoc 24006): a phase naming a cue that does not exist reds the guards, so keys and cues land together here.

const FX := preload("res://src/battle/FractalFX.gd")
const MANIFEST := "res://data/sfx_manifest.json"
## sequence id -> [phase kind, the cue that phase must name]
const KEYED := {
	"family_bite": ["flash", "family_bite"], "family_bite_big": ["flash", "family_bite_big"], "family_claw": ["streak", "family_claw"],
	"family_slam": ["flash", "family_slam"], "family_slam_quake": ["flash", "family_slam_quake"], "family_spit": ["flash", "family_spit"],
	"family_spray": ["puff", "family_spray"], "family_screech": ["ring", "family_screech"], "family_drain": ["bolt", "family_drain"],
	"family_cloud": ["flash", "family_cloud"], "family_dust": ["flash", "family_dust"],
	"blizzara_battle": ["eruption", "beat_blizzara_impact"], "thundara_battle": ["eruption", "beat_thundara_impact"],
	"wore_off": ["puff", "status_wore_off"],
}
## [tier 1 sequence, tier 2 sequence, the phase kind that lands the spell]
const TIERS := [["blizzard_battle", "blizzara_battle", "eruption"], ["thunder_battle", "thundara_battle", "eruption"]]
## [the bigger cue, the one it must outlast]
const BIGGER := [["family_bite_big", "family_bite"], ["family_slam_quake", "family_slam"]]


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func _file(sfx: Dictionary, key: String) -> String:
	return "res://" + str((sfx.get(key, {}) as Dictionary).get("file", ""))


func _dur(sfx: Dictionary, key: String) -> float:
	return float((sfx.get(key, {}) as Dictionary).get("duration_seconds", 0.0))


func _keys_of(seq_id: String, kind: String) -> Array[String]:
	var out: Array[String] = []
	for ph in FX.load_sequence(seq_id).get("phases", []):
		if ph is Dictionary and str(ph.get("kind", "")) == kind and ph.has("sfx"):
			out.append(str(ph["sfx"]))
	return out


func test_each_sequence_names_its_own_cue_and_the_cue_loads() -> void:
	var sfx := _sfx()
	var bad: Array[String] = []
	for seq_id in KEYED:
		var kind := str(KEYED[seq_id][0])
		var key := str(KEYED[seq_id][1])
		assert_false(FX.load_sequence(seq_id).is_empty(), "CONTROL: sequence %s must exist" % seq_id)
		if not _keys_of(seq_id, kind).has(key):
			bad.append("%s: no %s phase names %s" % [seq_id, kind, key])
		elif not ResourceLoader.exists(_file(sfx, key)):
			bad.append("%s -> %s does not load" % [key, _file(sfx, key)])
	assert_eq(bad, [], "these play their moment in silence: %s" % [bad])


## The tier is heard AT the hit, as Fira's is: tier 2 lands on its own file, and that file outlasts tier 1's.
func test_the_second_tier_lands_on_a_bigger_sound() -> void:
	var sfx := _sfx()
	for row in TIERS:
		var low := _keys_of(str(row[0]), str(row[2]))
		var high := _keys_of(str(row[1]), str(row[2]))
		assert_gt(low.size(), 0, "PREMISE: %s lands with a cue" % row[0])
		assert_gt(high.size(), 0, "PREMISE: %s lands with a cue" % row[1])
		if low.is_empty() or high.is_empty():
			continue
		assert_ne(_file(sfx, high[0]), _file(sfx, low[0]), "%s lands on the sound %s does" % [row[1], row[0]])
		assert_gt(_dur(sfx, high[0]), _dur(sfx, low[0]), "%s's impact must outlast %s's" % [row[1], row[0]])


func test_the_heavier_family_outlasts_the_plain_one() -> void:
	var sfx := _sfx()
	for pair in BIGGER:
		assert_true(sfx.has(pair[0]) and sfx.has(pair[1]), "PREMISE: %s and %s are in the manifest" % pair)
		assert_ne(_file(sfx, str(pair[0])), _file(sfx, str(pair[1])), "%s is its own file" % pair[0])
		assert_gt(_dur(sfx, str(pair[0])), _dur(sfx, str(pair[1])), "%s must outlast %s" % pair)


## A family sequence is ONE event per cue: a second key in one would be two files drifting apart as the speed changes.
func test_a_family_sequence_names_one_new_cue() -> void:
	var sfx := _sfx()
	for seq_id in KEYED:
		if not str(seq_id).begins_with("family_"):
			continue
		var mine: Array[String] = []
		for ph in FX.load_sequence(seq_id).get("phases", []):
			if ph is Dictionary and str(ph.get("sfx", "")).begins_with("family_"):
				mine.append(str(ph["sfx"]))
		assert_eq(mine.size(), 1, "%s names exactly one family cue, got %s" % [seq_id, mine])
		assert_lt(_dur(sfx, str(KEYED[seq_id][1])), 0.9, "%s is heard every monster turn: it stays short" % KEYED[seq_id][1])


## A wore-off is a footnote: authored quieter than the debuff cue it follows (the manifest rows carry the measured level).
func test_the_wore_off_cue_is_its_own_short_file() -> void:
	var sfx := _sfx()
	assert_true(sfx.has("status_wore_off"), "PREMISE: status_wore_off is in the manifest")
	assert_ne(_file(sfx, "status_wore_off"), _file(sfx, "debuff"), "wearing off is not the debuff landing again")
	assert_lt(_dur(sfx, "status_wore_off"), _dur(sfx, "debuff"), "it is shorter than the debuff cue")
	var s = load(_file(sfx, "status_wore_off"))
	assert_not_null(s, "the wore-off file must load")
	if s:
		assert_almost_eq(s.get_length(), _dur(sfx, "status_wore_off"), 0.05, "its authored duration describes the asset")
