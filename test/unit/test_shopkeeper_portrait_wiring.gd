extends GutTest

## Live-playtest regression (2026-07-17 → cowir-main msg 2772):
##
## Struktured saw the Chapel of Light keeper Sister Lenora rendered by the
## CharacterCustomization procedural face composite (features composited
## from HAIR_STYLE + HAIR_COLOR + EYE_SHAPE enums) and called it "shitty
## proc gen" — "looks like a serial killer. I think we need a sprite guy."
##
## Root cause: ShopScene's description panel loaded CharacterPortrait
## (procedural) unconditionally. No PNG-preferred path existed.
##
## Fix: KEEPER_PORTRAIT_PATHS maps ShopType → bespoke portrait PNG under
## assets/sprites/portraits/keepers/, checked BEFORE the procedural
## fallback. This test pins:
##   (1) All 4 ShopType enum values are present in KEEPER_PORTRAIT_PATHS.
##   (2) Every registered PNG path resolves on disk — art-exists-implies-
##       wired (same ratchet class that caught cowir-main's guard.png
##       repoint at v3.33.201).

const SHOP_SCENE := "res://src/exploration/ShopScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_keeper_portrait_paths_registered_for_every_shop_type() -> void:
	# All 4 ShopType enum values must have a KEEPER_PORTRAIT_PATHS entry —
	# a new ShopType added without art would silently fall back to the
	# procedural face composite struktured explicitly asked us to retire.
	var src := _read(SHOP_SCENE)
	assert_true(src.contains("KEEPER_PORTRAIT_PATHS"),
		"ShopScene.gd must declare KEEPER_PORTRAIT_PATHS — the wiring map is what makes bespoke keeper art win over the CharacterCustomization procedural draw")
	for shop_type in ["ShopType.ITEM", "ShopType.BLACK_MAGIC", "ShopType.WHITE_MAGIC", "ShopType.BLACKSMITH"]:
		assert_true(src.contains(shop_type + ":"),
			"KEEPER_PORTRAIT_PATHS must have a %s entry — otherwise that shop's keeper renders proc-gen" % shop_type)


func test_every_registered_keeper_portrait_exists_on_disk() -> void:
	# Art-exists-implies-wired ratchet: if KEEPER_PORTRAIT_PATHS points
	# at a PNG, that PNG must exist. A missing file is a live regression
	# to the CharacterCustomization draw (same defect class the guard.png
	# ratchet caught in v3.33.201).
	for keeper in ["willow", "mortimer", "lenora", "brutus"]:
		var path := "res://assets/sprites/portraits/keepers/%s.png" % keeper
		assert_true(FileAccess.file_exists(path),
			"%s must exist on disk — KEEPER_PORTRAIT_PATHS references it and a missing file drops the shop to procedural (Chapel of Light 'serial killer' regression from msg 2772)" % path)


func test_shopscene_prefers_png_over_procedural_before_customization_check() -> void:
	# Pin the ORDER: PNG check must happen BEFORE the shopkeeper_customization
	# branch, otherwise a shop that also has a customization would still
	# render procedural regardless of whether a bespoke PNG exists.
	var src := _read(SHOP_SCENE)
	var png_idx := src.find("keeper_png_path")
	var cust_idx := src.find("if shopkeeper_customization:")
	assert_gt(png_idx, -1, "ShopScene must have a keeper_png_path lookup")
	assert_gt(cust_idx, -1, "ShopScene must still keep the procedural fallback branch")
	assert_lt(png_idx, cust_idx,
		"PNG-preferred check must precede the procedural CharacterPortrait branch — otherwise procedural wins and the whole point of the wiring is defeated")
