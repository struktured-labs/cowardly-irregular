extends GutTest

## The ability sequences (Fire tier, Fighter/Rogue, Raise) shipped their phases SILENT on purpose: a phase naming a cue
## that does not exist reds the phase-sound guard, so the keys and the cues land together here (cowir-main 23787).

const FX := preload("res://src/battle/FractalFX.gd")
const MANIFEST := "res://data/sfx_manifest.json"
## sequence id -> [phase kind, the cue that phase must name]
const KEYED := {
	"fire_battle": ["eruption", "beat_fire_impact"], "fira_battle": ["eruption", "beat_fira_impact"],
	"glory_firaga": ["eruption", "beat_firaga_impact"], "melee_power_strike": ["ring", "beat_power_strike_impact"],
	"melee_cleave": ["arc", "beat_cleave_sweep"], "melee_shield_bash": ["emit", "beat_shield_bash_impact"],
	"melee_backstab_crit": ["arc", "beat_backstab_crit"], "rogue_scan": ["emit", "beat_scan_lock"],
	"rogue_smoke_bomb": ["puff", "beat_smoke_bomb_puff"], "raise_battle": ["flash", "beat_raise_halo"],
}
const FIRE_TIER: Array[String] = ["beat_fire_impact", "beat_fira_impact", "beat_firaga_impact"]


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func _file(sfx: Dictionary, key: String) -> String:
	return "res://" + str((sfx.get(key, {}) as Dictionary).get("file", ""))


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
	assert_eq(bad, [], "these sequences play their big moment in silence: %s" % [bad])


## The tier is heard AT the hit (cowir-battle 23590): three different files, each longer than the tier below.
func test_the_fire_tier_escalates_at_the_impact() -> void:
	var sfx := _sfx()
	var hashes := {}
	var prev := 0.0
	for key in FIRE_TIER:
		assert_true(sfx.has(key), "%s missing from the manifest" % key)
		hashes[FileAccess.get_sha256(_file(sfx, key))] = key
		var d := float((sfx.get(key, {}) as Dictionary).get("duration_seconds", 0.0))
		assert_gt(d, prev, "%s (%.2fs) must outlast the tier below (%.2fs)" % [key, d, prev])
		prev = d
	assert_eq(hashes.size(), FIRE_TIER.size(), "two fire tiers land on the same sound, so Firaga hits like Fire")


## The cast cue plays at the ACTION's start, a sequence's `start` before its first phase, so the gather needs its own swell.
func test_every_fire_tier_gathers_out_loud() -> void:
	for seq_id in ["fire_battle", "fira_battle", "glory_firaga"]:
		assert_true(_keys_of(seq_id, "gather").has("beat_fire_open"), "%s gathers in silence before its bolt" % seq_id)
		assert_gt(float(FX.load_sequence(seq_id).get("start", 0.0)), 0.0, "CONTROL: %s still starts after the cast pose; if not, the gather doubles the cast cue" % seq_id)
