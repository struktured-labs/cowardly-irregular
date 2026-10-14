extends GutTest

## Every village layered `ambient_village` — "Medieval village ambient loop. Distant market chatter,
## cart wheels" — under its music, in all six worlds, AT EVERY SETTING. BaseVillage._get_ambient_key()
## returned that key as a bare constant and not one of the 13 village subclasses overrode it, so a
## suburban strip mall, a clockwork market town, a factory settlement, a digital node and an abstract
## vertex all played a medieval market. The 7 interiors that override the same virtual do it
## correctly, so the hook was right and villages are the surface it never reached.
##
## ⛔ THIS IS THE INTERIM (struktured's call, relayed by cowir-main): the wrong-world bed STOPS, and
## the three authored per-world beds stay unused. `ambient_steampunk` / `ambient_industrial` /
## `ambient_digital` are on disk and pinned UNREACHABLE in test_unreachable_music_is_pinned, whose
## arm reds when a pinned bed becomes reachable. Wiring them is an open question for him
## ("delete, or give W4-W6 an ambient zone"), so the last arm here pins that this change does NOT
## answer it — the pins stay green deliberately, not by luck.
##
## The world vocabulary AND the area ids are DERIVED from _get_current_world_suffix's own body, so a
## seventh world makes this file demand that world's answer on its own.

const SOUNDMANAGER := "res://src/audio/SoundManager.gd"
const BASEVILLAGE := "res://src/maps/villages/BaseVillage.gd"
const MANIFEST := "res://data/music_manifest.json"
const HELD_FOR_STRUKTURED := ["ambient_steampunk", "ambient_industrial", "ambient_digital"]

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


## (world suffix -> one real area id that reports it), parsed from the match arms themselves.
func _area_for_world() -> Dictionary:
	var src: String = FileAccess.get_file_as_string(SOUNDMANAGER)
	assert_gt(src.length(), 5000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	var start: int = src.find("func _get_current_world_suffix")
	assert_gt(start, 0, "SCOPE control: _get_current_world_suffix not found — every arm would be vacuous")
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
	var m: Dictionary = _area_for_world()
	assert_gt(m.size(), 3, "SCOPE control: derived only %s — the parse is broken" % [m])
	assert_true(m.has("medieval"), "SCOPE control: no medieval arm, so the unchanged-state control cannot run")


func test_the_router_the_behavioural_arms_reach_exists() -> void:
	## FLOOR: the arms below call village_ambient_key(). Its absence aborts those frames AFTER
	## _area_for_world()'s own asserts have run, so they would score PASSING and this file would
	## be carried by its source-text arm alone — a spelling check.
	assert_true(_sm != null, "SoundManager autoload missing — every behavioural arm here is vacuous")
	assert_true(_sm != null and _sm.has_method("village_ambient_key"),
		"SoundManager.village_ambient_key() is MISSING: the arms below abort silently without it")


func test_no_village_outside_world_one_layers_a_medieval_market() -> void:
	## THE SUBJECT, and it is audible at every Text Size, not only large ones.
	if _sm == null:
		return
	var offenders: Array[String] = []
	var checked: int = 0
	var areas: Dictionary = _area_for_world()
	for world in areas.keys():
		if str(world) == "medieval":
			continue
		_sm._current_area = str(areas[world])
		checked += 1
		if _sm.village_ambient_key() == "ambient_village":
			offenders.append(str(world))
	assert_gt(checked, 2, "SCOPE control: only %d non-medieval worlds walked" % checked)
	assert_eq(offenders, [], "worlds whose villages still layer the MEDIEVAL village bed: %s" % [offenders])


func test_a_village_outside_world_one_layers_nothing_at_all() -> void:
	## The interim's positive claim: silence, not a borrowed bed of any kind.
	if _sm == null:
		return
	var bad: Array[String] = []
	var checked: int = 0
	var areas: Dictionary = _area_for_world()
	for world in areas.keys():
		if str(world) == "medieval":
			continue
		_sm._current_area = str(areas[world])
		checked += 1
		var got: String = _sm.village_ambient_key()
		if got != "":
			bad.append("%s -> '%s'" % [world, got])
	assert_gt(checked, 2, "SCOPE control: only %d non-medieval worlds walked" % checked)
	assert_eq(bad, [], "non-W1 villages must layer NO ambient bed, got: %s" % [bad])


func test_world_one_still_gets_its_village_bed() -> void:
	## The state this change did NOT set out to touch. Without it, returning "" everywhere passes.
	if _sm == null:
		return
	_sm._current_area = str(_area_for_world().get("medieval", "overworld"))
	assert_eq(_sm.village_ambient_key(), "ambient_village",
		"World 1 villages must still layer ambient_village — it is their authored bed")


func test_the_beds_held_for_struktured_are_still_unreachable_from_here() -> void:
	## ⛔ PINS THAT THIS IS (a) AND NOT (b). The three authored per-world beds are pinned
	## unreachable, and that pin is an open question for struktured. If a later edit routes a
	## village to one of them, test_unreachable_music_is_pinned reds — and so does this, naming
	## which bed, so the next reader learns it was a decision rather than an accident.
	if _sm == null:
		return
	var tracks: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary).get("tracks", {})
	var reached: Array[String] = []
	var areas: Dictionary = _area_for_world()
	for world in areas.keys():
		_sm._current_area = str(areas[world])
		var got: String = _sm.village_ambient_key()
		if got in HELD_FOR_STRUKTURED:
			reached.append("%s -> %s" % [world, got])
	for key in HELD_FOR_STRUKTURED:
		assert_true(tracks.has(key),
			"PREMISE: %s must still be authored, or this arm guards nothing" % key)
	assert_eq(reached, [],
		"a village now reaches a bed HELD for struktured (%s) — that is option (b) and it is his call" % [reached])


func test_the_village_consumer_asks_the_router() -> void:
	## The helper is dead weight unless BaseVillage routes through it; a bare constant is the defect.
	var src: String = FileAccess.get_file_as_string(BASEVILLAGE)
	assert_gt(src.length(), 2000, "SCOPE control: BaseVillage.gd read back %d chars" % src.length())
	var start: int = src.find("func _get_ambient_key")
	assert_gt(start, 0, "SCOPE control: _get_ambient_key not found in BaseVillage")
	assert_true(src.substr(start, 500).contains("village_ambient_key"),
		"BaseVillage._get_ambient_key must ask SoundManager.village_ambient_key(), not name a bed itself")
