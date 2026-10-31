extends GutTest
## A world whose suffix names no bed hears another era: the fallback substitutes medieval, silently.

const MANIFEST := "res://data/music_manifest.json"
const SENTINEL := "__no_arm_matched__"

## PINNED INPUT, DERIVED OUTPUT: one area id per world, the form GameLoop hands play_area_music.
const WORLD_PROBES := {1: "harmonia_village", 2: "maple_heights_village", 3: "brasston_village", 4: "rivet_row_village", 5: "node_prime_village", 6: "vertex_village"}

## Families carrying a bed for ALL SIX suffixes today, each with a `_medieval` fallback that substitutes in silence.
## `ambient` is excluded ON PURPOSE: it ships steampunk/industrial/digital only, so requiring six would red on a non-defect.
const FAMILIES := ["boss", "battle", "danger", "victory", "overworld", "village", "dungeon"]

var _saved_area: String = ""
var _saved_suffix: String = ""


func before_each() -> void:
	_saved_area = SoundManager._current_area
	_saved_suffix = SoundManager._current_world_suffix


func after_each() -> void:
	SoundManager._current_area = _saved_area
	SoundManager._current_world_suffix = _saved_suffix


func _tracks() -> Dictionary:
	var f: FileAccess = FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(f != null, "SCOPE control: %s did not open" % MANIFEST)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	assert_gt(raw.length(), 1000, "SCOPE control: the manifest read back %d chars" % raw.length())
	var parsed: Variant = JSON.parse_string(raw)
	return (parsed as Dictionary).get("tracks", {}) if parsed is Dictionary else {}


## Drives the REAL function, so no source regex can go stale against a refactor of its arms.
func _runtime_suffix(area: String) -> String:
	SoundManager._current_world_suffix = SENTINEL
	SoundManager._current_area = area
	return SoundManager._get_current_world_suffix()


func test_the_probe_can_see_a_world_whose_area_id_stopped_matching() -> void:
	assert_eq(_runtime_suffix("definitely_not_an_area_id"), SENTINEL,
		"CONTROL: an unmatched area must fall through to the persisted suffix. If it does not, the sentinel cannot tell a stale probe from a real answer and every arm in this file is vacuous")

	var seen: Dictionary = {}
	for w in WORLD_PROBES.keys():
		var s: String = _runtime_suffix(str(WORLD_PROBES[w]))
		assert_ne(s, SENTINEL,
			"world %d's probe area '%s' matches no arm in _get_current_world_suffix, so it fell through to the persisted suffix. The PROBE is stale, not the engine — read the match arms and update WORLD_PROBES" % [int(w), str(WORLD_PROBES[w])])
		assert_false(seen.has(s),
			"worlds %s and %d both resolve to suffix '%s' — an arm was copied or a probe fell through" % [str(seen.get(s, "?")), int(w), s])
		seen[s] = int(w)
	assert_eq(seen.size(), WORLD_PROBES.size(),
		"CONTROL: %d distinct suffixes from %d worlds" % [seen.size(), WORLD_PROBES.size()])


func test_every_runtime_suffix_names_a_bed_in_every_complete_family() -> void:
	var tracks: Dictionary = _tracks()
	assert_gt(tracks.size(), 100, "SCOPE control: the manifest carries %d tracks" % tracks.size())

	var orphans: Array[String] = []
	for w in WORLD_PROBES.keys():
		var s: String = _runtime_suffix(str(WORLD_PROBES[w]))
		for fam in FAMILIES:
			if not tracks.has("%s_%s" % [fam, s]):
				orphans.append("world %d -> %s_%s" % [int(w), fam, s])
	assert_true(orphans.is_empty(),
		"the runtime asks for a bed the manifest does not carry, so SoundManager falls back to <family>_medieval and a whole world hears the wrong era with no error at all. Offenders: %s. Either land the bed or put the suffix back" % [orphans])


func test_the_two_world_suffix_vocabularies_agree() -> void:
	var split: Array[String] = []
	for w in WORLD_PROBES.keys():
		var runtime: String = _runtime_suffix(str(WORLD_PROBES[w]))
		var weather: String = WeatherSystem.world_id_for(int(w))
		if runtime != weather:
			split.append("world %d: SoundManager '%s' vs WeatherSystem '%s'" % [int(w), runtime, weather])
	assert_true(split.is_empty(),
		"two independent vocabularies for one surface have diverged: %s. The audio keys follow SoundManager's hand-written arms, weather and costumes follow WeatherSystem.WORLD_IDS, and nothing else makes them agree" % [split])
