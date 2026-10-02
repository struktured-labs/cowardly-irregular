extends GutTest

## Regression (struktured on moonshot, 2026-10-01, v3.33.552): "whats up with the question mark icons in battle menu".
## AbilityIcons/ItemIcons gated each icon on FileAccess.file_exists(".../<key>.png"). An export packs the IMPORTED icon, not
## the png (measured on the .552 binary: ability_icons 0 raw .png / 22 .import, item_icons 0 / 29), so in every shipped build
## every ability drew "unknown" (?) and every item the pouch, while the editor and this suite, reading the working copy, were fine.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## Reads raw bytes on purpose: its pngs are importer="keep" and ship raw (tools/check_raw_assets_shipped.py guards that).
const RAW_READERS := ["res://src/exploration/MapImageLoader.gd"]


func test_no_imported_asset_is_gated_on_file_exists() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for path in _gd_files("res://src"):
		if path in RAW_READERS:
			continue
		scanned += 1
		var code: String = GdSource.code_of(path)
		var at := code.find("FileAccess.file_exists(")
		while at >= 0:
			var call := code.substr(at, code.find(")", at) - at + 1)
			if call.contains("png") or call.contains(".ogg") or call.contains(".wav") or call.contains("texture"):
				offenders.append("%s: %s" % [path.get_file(), call])
			at = code.find("FileAccess.file_exists(", at + 1)
	assert_gt(scanned, 100, "SCOPE: the walk reached src")
	assert_eq(offenders, [] as Array[String],
		"an imported asset (png/ogg/wav) is gated on FileAccess.file_exists, which is false in every exported pack; use ResourceLoader.exists: %s" % [offenders])


func test_the_icon_modules_resolve_a_real_key_and_fall_back_only_for_a_missing_one() -> void:
	assert_ne(AbilityIcons.texture_for_key("fire"), AbilityIcons.texture_for_key("no_such_key_x"),
		"CONTROL: a real ability key must not resolve to the same texture as a missing one")
	assert_true(ResourceLoader.exists(AbilityIcons.png_path("fire")), "SCOPE: the fire icon is a resource the loader can see")
	assert_true(ItemIcons._png_exists("potion") or ItemIcons._png_exists(ItemIcons.icon_key("potion")),
		"the potion icon must resolve through the loader, not fall back to the pouch")


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var p: String = root + "/" + n
		if d.current_is_dir():
			out.append_array(_gd_files(p))
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()
	return out
