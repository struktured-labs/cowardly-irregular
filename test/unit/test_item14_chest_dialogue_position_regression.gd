extends GutTest

## User playtest item 14: "the chests in the overworld, when opened,
## show dialogue boxes htne kind of render in the wrong spot, like
## exactly where chest was, instead of bigger and above, perhaps? but
## something not as on the nose as impl"
##
## Root cause: TreasureChest dialogue panel was 200×50 at y=-70. Panel
## bottom sat at y=-20; chest sprite is 32×32 centered on (0,0) so
## chest top is at y=-16. Only 4px of clearance made the box read as
## "on the chest".
##
## Fix: enlarge to 240×60 + lift to y=-110 so panel bottom (y=-50) has
## 34px of visible air above chest top. Label geometry follows.

const CHEST_PATH := "res://src/exploration/TreasureChest.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_panel_lifted_off_chest() -> void:
	# Pin the y coordinate — anything less negative than -80 leaves
	# the panel visually clinging to the chest sprite (the pre-fix bug).
	var src := _read(CHEST_PATH)
	assert_true(src.contains("panel.position = Vector2(-120, -110)"),
		"chest dialogue panel must sit at y=-110 (36px clear of chest sprite top) — was y=-70 pre-fix, only 4px clear")


func test_panel_grown_bigger() -> void:
	var src := _read(CHEST_PATH)
	assert_true(src.contains("panel.size = Vector2(240, 60)"),
		"chest dialogue panel must be 240×60 (was 200×50 pre-fix) — bigger reads as a proper 'above and floating' UI element vs a chest label")


func test_label_follows_panel() -> void:
	var src := _read(CHEST_PATH)
	assert_true(src.contains("dialogue_label.position = Vector2(-112, -102)"),
		"label position must follow the panel's new y=-110 anchor (8px inset)")
	assert_true(src.contains("dialogue_label.size = Vector2(224, 44)"),
		"label size must fit inside the new 240×60 panel (8px inset all around)")
