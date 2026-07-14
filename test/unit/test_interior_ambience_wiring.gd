extends GutTest

## 2026-07-01: wire cowir-sfx's interior ambience pack (abbbaa10).
## Pins the BaseInterior._get_ambient_key seam + the three room
## overrides + the anvil-strike hook so a future audio refactor
## can't silently orphan the assets again.

const BaseInteriorScript := preload("res://src/maps/interiors/BaseInterior.gd")
const BlacksmithScript := preload("res://src/maps/interiors/BlacksmithInterior.gd")
const ChapelScript := preload("res://src/maps/interiors/HarmoniaChapelInterior.gd")
const LibraryScript := preload("res://src/maps/interiors/HarmoniaLibraryInterior.gd")


func test_base_interior_ambient_default_is_silent() -> void:
	var base = BaseInteriorScript.new()
	assert_eq(base._get_ambient_key(), "", "BaseInterior default = no room ambience")
	base.free()


func test_room_ambient_overrides() -> void:
	var forge = BlacksmithScript.new()
	var chapel = ChapelScript.new()
	var library = LibraryScript.new()
	assert_eq(forge._get_ambient_key(), "ambient_forge")
	assert_eq(chapel._get_ambient_key(), "ambient_chapel")
	assert_eq(library._get_ambient_key(), "ambient_library")
	forge.free()
	chapel.free()
	library.free()


func test_ambient_keys_exist_in_sfx_manifest() -> void:
	var f := FileAccess.open("res://data/sfx_manifest.json", FileAccess.READ)
	assert_not_null(f, "sfx_manifest.json must be readable")
	var json := JSON.new()
	assert_eq(json.parse(f.get_as_text()), OK)
	var data: Dictionary = json.data
	var sfx: Dictionary = data.get("sfx", data)
	for key in ["ambient_forge", "ambient_chapel", "ambient_library", "anvil_strike"]:
		assert_true(sfx.has(key), "sfx_manifest must define %s (cowir-sfx pack abbbaa10)" % key)


func test_anvil_strike_wired_to_impact_frame() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/maps/interiors/BlacksmithInterior.gd")
	assert_true(src.contains("play_battle(\"anvil_strike\")"),
		"smith impact frame must fire anvil_strike via the battle player (idle in exploration)")
	assert_true(src.contains("_strike_cycle"),
		"anvil clang must keep the 3-strikes-then-rest rhythm, not fire every 0.64s cycle")
