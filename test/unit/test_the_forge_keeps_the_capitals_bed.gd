extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const VillageScript := preload("res://src/maps/villages/HarmoniaVillage.gd")
const ForgeScript := preload("res://src/maps/interiors/BlacksmithInterior.gd")

## ⛔ WALKING INTO THE FORGE SWAPS HARMONIA'S SIGNATURE BED FOR THE GENERIC ONE, AND WALKING OUT
## SWAPS IT BACK. `BlacksmithInterior._get_music_track()` returns `"village"`, which is an AREA id —
## it routes to `_start_village_world_music("medieval")` and plays `village_medieval.ogg` over the
## `village_harmonia.ogg` the player was just listening to.
##
## 🔑 EVERY OTHER HARMONIA INTERIOR GETS THIS RIGHT AND THAT IS WHY IT IS INVISIBLE. The forge was the
## one door in the capital that RESTARTED the music, and its own comment explained why: "no
## smithy-specific music key exists yet, so 'village' is the only real fallback SoundManager
## recognizes".
##
## ⚠️ I FIXED IT TWICE, AND THE FIRST REPAIR WAS HALF-RIGHT. It pointed the forge at `interior_smithy`,
## an unauthored room key, which INHERITS when walked into. Measured an hour later: a save loaded
## INSIDE the room has nothing to inherit, and `_start_interior_music` cold-starts BY WORLD — so the
## room was back to village_medieval, by a different route, and chapel/library/arcade/office/lounge/
## union-hall/bookshop/scriptorium had the same split all along. The village id is the answer that is
## right in BOTH arrival modes; `test_a_room_sounds_the_same_however_you_arrived` pins that over the
## whole population so neither convention can drift back to one-mode-correct.
##
## Derived from the two scripts rather than from literals, so a renamed id reds here instead of
## quietly making this file about nothing.

var _village_area: String = ""
var _forge_id: String = ""


func before_all() -> void:
	var v: Node = VillageScript.new()
	var f: Node = ForgeScript.new()
	_village_area = str(v._get_music_area_id())
	_forge_id = str(f._get_music_track())
	v.free()
	f.free()


func before_each() -> void:
	SoundState.restore()


func after_all() -> void:
	SoundState.restore()


func test_floor_both_scripts_still_declare_their_ids() -> void:
	assert_ne(_village_area, "", "HarmoniaVillage must still declare _get_music_area_id()")
	assert_ne(_forge_id, "", "BlacksmithInterior must still declare _get_music_track()")
	for name in ["play_area_music", "_resolve_interior_track"]:
		assert_true(SoundManager.has_method(name), "SoundManager must still expose %s()" % name)


func test_the_forge_keeps_the_capitals_bed() -> void:
	SoundManager.play_area_music(_village_area)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_not_null(SoundManager._music_player.stream, "CONTROL: the capital's bed must be loaded")
	var capital_bed: String = SoundManager._music_player.stream.resource_path
	## ⛔ WITHOUT THIS CONTROL THE ARM PASSES ON THE BUG whenever Harmonia has no signature bed of its
	## own — both sides would be village_medieval and the comparison would be vacuously true.
	assert_true(capital_bed.ends_with("village_harmonia.ogg"),
		"CONTROL: %s must play its OWN bed, not the generic one — got %s" % [_village_area, capital_bed])

	## ⛔ CONDITIONED ON WHETHER THE ROOM HAS A BED OF ITS OWN, so authoring `interior_smithy`
	## tomorrow does not red a correct change. The claim is "no bed the room did not ask for",
	## not "this exact file" — a coincidental-value pin would fail on the authoring it invites.
	SoundManager._load_music_manifest()
	var authored: String = str(SoundManager._resolve_interior_track(_forge_id)) if _forge_id.begins_with("interior_") else ""
	SoundManager.play_area_music(_forge_id)
	await get_tree().process_frame
	await get_tree().process_frame
	var forge_bed: String = SoundManager._music_player.stream.resource_path if SoundManager._music_player.stream else ""
	if authored == "":
		assert_eq(forge_bed, capital_bed,
			"the forge asked for '%s' and got %s over the capital's %s — one door in Harmonia restarts the music while chapel, library and cartographer all keep it" % [_forge_id, forge_bed.get_file(), capital_bed.get_file()])
	else:
		assert_true(forge_bed.ends_with(str(SoundManager._music_manifest[authored].get("file", "")).get_file()),
			"the forge resolves its own bed '%s' and must be playing it, not %s" % [authored, forge_bed.get_file()])


func test_an_interior_asks_by_room_never_by_another_place() -> void:
	## The durable half, and the one that states what actually went wrong. "village" is a legal id —
	## it is just SOMEBODY ELSE'S: an AREA key routing to _start_village_world_music. A room may name
	## itself (`interior_*`, which inherits when unauthored) or the village it is entered from (which
	## hits the already-playing return). Anything else is a request to change place without moving.
	assert_true(_forge_id.begins_with("interior_") or _forge_id == _village_area,
		"BlacksmithInterior asks for '%s', which is neither an interior_ key nor %s's own id — an area id belonging to a different place restarts the bed on every entry and exit" % [_forge_id, _village_area])
