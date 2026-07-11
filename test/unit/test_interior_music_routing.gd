extends GutTest

## Interior sub-area music routing (2026-07-11).
##
## Pins the three load-bearing behaviors of the interior_ music seam:
## 1. INHERIT-ON-MISSING — entering a room whose interior_* track isn't
##    authored yet must keep the current village bed playing (guard runs
##    BEFORE stop_music, so unauthored rooms never go silent).
## 2. World-variant resolution — interior_tavern_steampunk outranks
##    interior_tavern when both exist (monster-sheet lookup pattern).
## 3. Room wiring — every room in the dedicated-track table returns its
##    interior_* key; standalone rooms (Tavern/Inn/Shop extend Node2D)
##    call play_area_music with it directly.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"

## BaseInterior subclasses: [file, expected _get_music_track return]
const OVERRIDE_ROOMS: Array[Array] = [
	["res://src/maps/interiors/HarmoniaChapelInterior.gd",       "interior_chapel"],
	["res://src/maps/interiors/HarmoniaLibraryInterior.gd",      "interior_library"],
	["res://src/maps/interiors/ScripturaBookshopInterior.gd",    "interior_library"],
	["res://src/maps/interiors/ScripturaGuildInterior.gd",       "interior_scriptorium"],
	["res://src/maps/interiors/MapleCommunityCenterInterior.gd", "interior_office"],
	["res://src/maps/interiors/EnrichmentAnnexInterior.gd",      "interior_office"],
	["res://src/maps/interiors/MapleHeightsArcadeInterior.gd",   "interior_arcade"],
	["res://src/maps/interiors/RivetRowUnionHallInterior.gd",    "interior_union_hall"],
	["res://src/maps/interiors/NodePrimeDaemonLoungeInterior.gd", "interior_lounge"],
]

## Standalone Node2D rooms: [file, expected play_area_music argument]
const DIRECT_CALL_ROOMS: Array[Array] = [
	["res://src/maps/interiors/TavernInterior.gd", "interior_tavern"],
	["res://src/maps/interiors/InnInterior.gd",    "interior_inn"],
	["res://src/maps/interiors/ShopInterior.gd",   "interior_shop"],
]


func _sound_manager() -> Node:
	return get_node_or_null("/root/SoundManager")


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_inherit_on_missing_keeps_current_area() -> void:
	# The missing-track path is fully synchronous: play_area_music must
	# return before any state mutation or stop_music. If this regresses,
	# unauthored rooms cut the village music to silence.
	var sm := _sound_manager()
	if sm == null:
		pass_test("SoundManager autoload unavailable in this context")
		return
	var prev_area: String = sm._current_area
	var prev_playing: bool = sm._music_playing
	sm._current_area = "village"
	sm._music_playing = true
	sm.play_area_music("interior_zz_unauthored_room")
	assert_eq(sm._current_area, "village",
		"missing interior track must inherit: _current_area untouched (no takeover, no stop_music)")
	sm._current_area = prev_area
	sm._music_playing = prev_playing


func test_guard_sits_before_stop_music_in_source() -> void:
	# Order matters: the inherit guard is only safe if it runs before
	# play_area_music's stop_music() call.
	var src := _read(SOUND_MANAGER)
	var fn_start: int = src.find("func play_area_music(")
	assert_true(fn_start >= 0, "play_area_music must exist")
	var guard_pos: int = src.find("begins_with(\"interior_\")", fn_start)
	var stop_pos: int = src.find("stop_music()", fn_start)
	assert_true(guard_pos >= 0, "play_area_music must carry the interior_ inherit guard")
	assert_true(stop_pos >= 0, "play_area_music must still stop before switching real areas")
	assert_true(guard_pos < stop_pos,
		"interior_ inherit guard must run BEFORE stop_music — otherwise missing tracks cause silence")


func test_world_variant_outranks_base_key() -> void:
	var sm := _sound_manager()
	if sm == null:
		pass_test("SoundManager autoload unavailable in this context")
		return
	var probe_base := "interior_zz_probe"
	var probe_variant: String = probe_base + "_" + str(sm._get_current_world_suffix())
	sm._music_manifest[probe_base] = {"file": "x"}
	sm._music_manifest[probe_variant] = {"file": "x"}
	var resolved: String = sm._resolve_interior_track(probe_base)
	sm._music_manifest.erase(probe_base)
	sm._music_manifest.erase(probe_variant)
	assert_eq(resolved, probe_variant,
		"per-world variant (monster-sheet pattern) must outrank the base interior key")


func test_interior_shop_track_is_wired_and_loadable() -> void:
	# The adopted "The Merchant's Welcome" track: manifest key renamed
	# shop -> interior_shop; the OGG must exist for the shop rooms.
	var manifest_text := _read("res://data/music_manifest.json")
	var parsed: Variant = JSON.parse_string(manifest_text)
	assert_true(parsed is Dictionary and parsed.has("tracks"), "manifest parses")
	var tracks: Dictionary = parsed["tracks"]
	assert_true(tracks.has("interior_shop"), "manifest must carry interior_shop (renamed from orphaned 'shop')")
	assert_false(tracks.has("shop"), "old 'shop' key must be gone — one source of truth")
	var stream = load("res://" + str(tracks["interior_shop"].get("file", "")))
	assert_not_null(stream, "interior_shop OGG must load")


func test_override_rooms_return_their_interior_keys() -> void:
	for entry in OVERRIDE_ROOMS:
		var src := _read(entry[0])
		assert_true(src.contains("return \"" + entry[1] + "\""),
			"%s must return %s" % [entry[0], entry[1]])


func test_standalone_rooms_call_play_area_music_directly() -> void:
	# Tavern/Inn/Shop extend Node2D (not BaseInterior) — their music
	# arrives via a direct play_area_music call in _ready.
	for entry in DIRECT_CALL_ROOMS:
		var src := _read(entry[0])
		assert_true(src.contains("play_area_music(\"" + entry[1] + "\")"),
			"%s must call play_area_music(\"%s\") directly (standalone scene, no BaseInterior flow)" % [entry[0], entry[1]])
