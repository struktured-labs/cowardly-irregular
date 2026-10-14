extends GutTest

## Every village layered `ambient_village` — "Medieval village ambient loop. Distant market chatter,
## cart wheels" — under its music, in all six worlds. BaseVillage._get_ambient_key() returned that
## key as a bare constant and not one of the 13 village subclasses overrode it, so a suburban strip
## mall, a clockwork market town, a factory settlement, a digital node and an abstract vertex all
## played a medieval market. Meanwhile ambient_steampunk / ambient_industrial / ambient_digital are
## authored, on disk, and had ZERO consumers anywhere in src/ — three beds that had never played.
##
## The world vocabulary AND the area ids are DERIVED from _get_current_world_suffix's own body, so a
## seventh world, or a renamed area, makes this file demand that world's answer on its own. A
## hardcoded ["medieval", ...] would pass while agreeing with a stale copy of the vocabulary.
##
## Which beds EXIST is read from the manifest, never listed here: the expected answer for a world is
## "the authored bed if there is one, else silence", so authoring ambient_suburban later flips that
## world's arm with no edit to this file.

const SOUNDMANAGER := "res://src/audio/SoundManager.gd"
const BASEVILLAGE := "res://src/maps/villages/BaseVillage.gd"
const MANIFEST := "res://data/music_manifest.json"

var _sm: Node = null
var _area_before: String = ""


func before_each() -> void:
	_sm = get_node_or_null("/root/SoundManager")
	if _sm:
		_area_before = str(_sm._current_area)


func after_each() -> void:
	## Restore even if an arm aborted: a leaked _current_area drags later audio tests.
	if _sm:
		_sm._current_area = _area_before


func _tracks() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("tracks", {})


## (world suffix -> one real area id that reports it), parsed from the match arms themselves.
func _area_for_world() -> Dictionary:
	var src: String = FileAccess.get_file_as_string(SOUNDMANAGER)
	assert_gt(src.length(), 5000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	var start: int = src.find("func _get_current_world_suffix")
	assert_gt(start, 0, "SCOPE control: _get_current_world_suffix not found — every arm below would be vacuous")
	var body: String = src.substr(start, 3000)
	var out: Dictionary = {}
	var pending: Array[String] = []
	for raw_line in body.split("\n"):
		var line: String = str(raw_line).strip_edges()
		if line.begins_with("return \""):
			var suffix: String = line.substr(8, line.length() - 9)
			if suffix != "" and not out.has(suffix) and not pending.is_empty():
				out[suffix] = pending[0]
			pending = []
		elif line.ends_with(":") and line.begins_with("\""):
			pending = []
			for piece in line.trim_suffix(":").split(","):
				var id: String = str(piece).strip_edges().trim_prefix("\"").trim_suffix("\"")
				if id != "":
					pending.append(id)
	return out


func test_the_world_vocabulary_and_its_areas_are_readable() -> void:
	## Control for every arm below. A broken parse would walk an empty map and pass having checked nothing.
	var m: Dictionary = _area_for_world()
	assert_gt(m.size(), 3, "SCOPE control: derived only %s from _get_current_world_suffix — the parse is broken" % [m])
	assert_true(m.has("medieval"), "SCOPE control: no medieval arm derived, so the unchanged-state control cannot run")


func test_the_router_the_behavioural_arms_reach_exists() -> void:
	## FLOOR, and it is load-bearing: every behavioural arm below calls village_ambient_key(). Its
	## absence aborts those frames AFTER _area_for_world()'s own asserts have run, so they score
	## PASSING and the file would be carried by the source-text arm alone — a spelling check.
	assert_true(_sm != null, "SoundManager autoload missing — every behavioural arm here is vacuous")
	assert_true(_sm != null and _sm.has_method("village_ambient_key"),
		"SoundManager.village_ambient_key() is MISSING: the four arms below abort silently without it")


func test_a_village_never_layers_a_medieval_market_on_another_world() -> void:
	if _sm == null:
		return
	var offenders: Array[String] = []
	var checked: int = 0
	for world in _area_for_world().keys():
		if str(world) == "medieval":
			continue
		_sm._current_area = str(_area_for_world()[world])
		checked += 1
		if _sm.village_ambient_key() == "ambient_village":
			offenders.append(str(world))
	assert_gt(checked, 2, "SCOPE control: only %d non-medieval worlds walked" % checked)
	assert_eq(offenders, [], "worlds whose villages still layer the MEDIEVAL village bed: %s" % [offenders])


func test_an_authored_world_bed_is_the_one_that_plays() -> void:
	if _sm == null:
		return
	var tracks: Dictionary = _tracks()
	var wrong: Array[String] = []
	var matched: int = 0
	for world in _area_for_world().keys():
		var authored: String = "ambient_" + str(world)
		if not tracks.has(authored):
			continue
		_sm._current_area = str(_area_for_world()[world])
		matched += 1
		var got: String = _sm.village_ambient_key()
		if got != authored:
			wrong.append("%s wanted %s got '%s'" % [world, authored, got])
	assert_gt(matched, 1, "SCOPE control: the manifest authored only %d per-world ambient beds, so this arm proves little" % matched)
	assert_eq(wrong, [], "worlds with an authored ambient bed that is not what plays: %s" % [wrong])


func test_medieval_still_gets_the_village_bed() -> void:
	## The state the fix did NOT set out to change. Without this, routing every world to silence passes.
	if _sm == null:
		return
	_sm._current_area = str(_area_for_world().get("medieval", "overworld"))
	assert_eq(_sm.village_ambient_key(), "ambient_village",
		"medieval villages must still layer ambient_village — it is their authored bed")


func test_a_world_with_no_authored_bed_gets_silence_not_a_borrowed_one() -> void:
	if _sm == null:
		return
	var tracks: Dictionary = _tracks()
	var bad: Array[String] = []
	var bare: int = 0
	for world in _area_for_world().keys():
		if str(world) == "medieval":
			continue
		if tracks.has("ambient_" + str(world)) or tracks.has("ambient_village_" + str(world)):
			continue
		_sm._current_area = str(_area_for_world()[world])
		bare += 1
		if _sm.village_ambient_key() != "":
			bad.append("%s -> '%s'" % [world, _sm.village_ambient_key()])
	assert_gt(bare, 0, "SCOPE control: every world has an authored bed, so this arm walked nothing")
	assert_eq(bad, [], "worlds with NO authored ambient bed must play none, got: %s" % [bad])


func test_the_village_consumer_asks_the_router() -> void:
	## The helper is dead weight unless BaseVillage routes through it; a bare constant is the defect.
	var src: String = FileAccess.get_file_as_string(BASEVILLAGE)
	assert_gt(src.length(), 2000, "SCOPE control: BaseVillage.gd read back %d chars" % src.length())
	var start: int = src.find("func _get_ambient_key")
	assert_gt(start, 0, "SCOPE control: _get_ambient_key not found in BaseVillage")
	var body: String = src.substr(start, 500)
	assert_true(body.contains("village_ambient_key"),
		"BaseVillage._get_ambient_key must ask SoundManager.village_ambient_key(), not name a bed itself")
