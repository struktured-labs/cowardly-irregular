extends GutTest

## The villages side of the hole `test_non_medieval_dungeons_must_override_the_music_key` closed for
## dungeons after VertexApex — the World 6 finale that inherited "cave" and scored the last fight of
## a six-world game to World 1.
##
## ⛔ `test_w2_w6_village_music_routes_correctly` asserts that every W2-W6 village overrides the
## hook, and it iterates a HAND-LISTED const. A new village added to src/maps/villages/ and not
## added to that list is covered by nothing: it inherits BaseVillage's "village", which plays
## `village_medieval` — World 1's generic bed — AND resolves to the MEDIEVAL battle suffix. That is
## the same defect twice over, and it is the bug that shipped as "five W1 villages wore the capital's
## theme" (8a4463ff5) reappearing in a world where medieval is simply wrong.
##
## 🔑 DERIVED FROM DISK, AND THE WORLD COMES FROM A DIFFERENT READ. The corpus is every .gd in the
## villages directory; each file's world comes from `GameLoop.WORLD_PREFIXES`, the map-id vocabulary
## the rest of the game routes by. Asking SoundManager which world a village is in would be the
## shared-denominator mistake: that resolver is the thing under test.

const VILLAGE_DIR := "res://src/maps/villages/"
const GAMELOOP := preload("res://src/GameLoop.gd")
const SOUND_MANAGER_PATH := "res://src/audio/SoundManager.gd"
## The base class DEFINES the default, so it cannot be asked to override it.
const BASE := "BaseVillage.gd"


func _village_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(VILLAGE_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") and f != BASE:
			out.append(f)
	out.sort()
	return out


## `EldertreeVillage.gd` -> `eldertree_village`. Answers WHERE the village is, in the game's own
## map-id vocabulary — not which id it passes to play_area_music, which for a non-overriding
## village is the generic "village".
func _map_id_for(file_name: String) -> String:
	var base: String = file_name.trim_suffix(".gd")
	var out: String = ""
	for i in base.length():
		var c: String = base[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower():
			out += "_"
		out += c.to_lower()
	return out


func _world_of(map_id: String) -> int:
	for entry in GAMELOOP.WORLD_PREFIXES:
		if map_id.begins_with(str(entry[0])):
			return int(entry[1])
	return 0


func _src(file_name: String) -> String:
	return FileAccess.get_file_as_string(VILLAGE_DIR + file_name)


func _declared_id(src: String) -> String:
	var i: int = src.find("func _get_music_area_id")
	if i < 0:
		return ""
	var body: String = src.substr(i, 260)
	var r: int = body.find("return \"")
	if r < 0:
		return ""
	var rest: String = body.substr(r + 8)
	return rest.substr(0, rest.find("\""))


func test_control_the_corpus_and_the_authority_are_both_real() -> void:
	## Either half silently empty makes every arm below a green about nothing.
	var files := _village_files()
	assert_gt(files.size(), 10,
		"CONTROL: only %d village scripts found in %s — the directory read failed" % [files.size(), VILLAGE_DIR])
	assert_gt(GAMELOOP.WORLD_PREFIXES.size(), 20,
		"CONTROL: WORLD_PREFIXES has %d entries — the authority read failed" % GAMELOOP.WORLD_PREFIXES.size())
	assert_true(FileAccess.file_exists(VILLAGE_DIR + BASE), "CONTROL: %s must exist" % BASE)


func test_control_every_village_file_resolves_to_a_world() -> void:
	## The floor that makes the next arm mean anything. An id WORLD_PREFIXES does not match scores 0,
	## which is not 1 — so without this arm it would read as "non-medieval, and it overrides" or slip
	## through as "medieval enough". Name the file instead.
	var unmatched: Array[String] = []
	for f in _village_files():
		var id: String = _map_id_for(f)
		if _world_of(id) == 0:
			unmatched.append("%s -> derived map id '%s', which no WORLD_PREFIXES entry matches" % [f, id])
	assert_eq(unmatched.size(), 0,
		"a village whose world cannot be derived is outside every arm in this file:\n%s" % "\n".join(unmatched))


func test_a_village_outside_world_one_must_say_where_it_is() -> void:
	var offenders: Array[String] = []
	var checked: int = 0
	for f in _village_files():
		var w: int = _world_of(_map_id_for(f))
		if w == 1:
			continue
		checked += 1
		if _src(f).find("func _get_music_area_id") > -1:
			continue
		offenders.append("%s is World %d and does not override _get_music_area_id, so it inherits BaseVillage's \"village\" — which plays village_medieval, World 1's bed, and resolves to the MEDIEVAL battle suffix" % [f, w])
	assert_gt(checked, 4,
		"CONTROL: only %d non-medieval villages walked — a green below would be vacuous" % checked)
	assert_eq(offenders.size(), 0, "\n".join(offenders))


func test_a_village_that_overrides_names_its_own_world() -> void:
	## The other direction: an override is not enough, it must point at the right world. A W4 village
	## declaring a W2 key routes to the wrong bed just as surely as no override at all.
	var wrong: Array[String] = []
	var checked: int = 0
	for f in _village_files():
		var declared: String = _declared_id(_src(f))
		if declared == "" or declared == "village":
			continue
		checked += 1
		var own: int = _world_of(_map_id_for(f))
		var says: int = _world_of(declared)
		if says != own:
			wrong.append("%s is World %d but declares '%s', which is World %d" % [f, own, declared, says])
	assert_gt(checked, 6,
		"CONTROL: only %d villages declare an id — the extractor is not reading the overrides" % checked)
	assert_eq(wrong.size(), 0, "\n".join(wrong))


func test_every_declared_village_id_has_a_dispatcher_arm() -> void:
	## An id with no arm in play_area_music's match falls to `_:`, which plays the OVERWORLD bed.
	## Inside a village that is audible and wrong, and no other arm here would notice.
	var sm: String = FileAccess.get_file_as_string(SOUND_MANAGER_PATH)
	assert_gt(sm.length(), 1000, "CONTROL: SoundManager read back %d chars" % sm.length())
	var ids: Array[String] = ["village"]
	for f in _village_files():
		var d: String = _declared_id(_src(f))
		if d != "" and not ids.has(d):
			ids.append(d)
	assert_gt(ids.size(), 7, "CONTROL: only %d distinct village ids collected" % ids.size())
	var armless: Array[String] = []
	for id in ids:
		if sm.find("\t\t\"%s\":\n" % id) < 0:
			armless.append(id)
	assert_eq(armless.size(), 0,
		"village ids with no arm in play_area_music, so they fall to `_:` and play the overworld bed: %s" % str(armless))


func test_this_derivation_sees_everything_the_hand_list_does() -> void:
	## Cross-check against the const this file exists to outgrow. The derived non-medieval set must
	## CONTAIN the hand-listed one — if it does not, the derivation is narrower than what is already
	## covered and this file is a downgrade rather than an addition.
	var listed: Array[String] = []
	var other: String = FileAccess.get_file_as_string("res://test/unit/test_w2_w6_village_music_routes_correctly.gd")
	assert_gt(other.length(), 500, "CONTROL: the sibling guard read back %d chars" % other.length())
	for f in _village_files():
		if other.find(f) > -1:
			listed.append(f)
	assert_gt(listed.size(), 4,
		"CONTROL: only %d village files are named by the hand-listed guard — the cross-read failed" % listed.size())
	var missed: Array[String] = []
	for f in listed:
		if _world_of(_map_id_for(f)) == 1:
			continue
		if _src(f).find("func _get_music_area_id") < 0:
			missed.append(f)
	assert_eq(missed.size(), 0,
		"these are hand-listed as W2-W6 and this file's derivation would not have required an override: %s" % str(missed))
