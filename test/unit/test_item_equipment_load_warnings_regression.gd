extends GutTest

## Companion to tick 28 (JobSystem / PassiveSystem). ItemSystem and
## EquipmentSystem had the same shape: silent fallback to hardcoded
## defaults when items.json / equipment.json was missing, malformed,
## or had a non-Dict root. A corrupted production data file would
## silently run the game with the tiny default set instead of the
## 117-item / 60-equipment real content.
##
## Fix: push_warning every fallback path, naming the file + reason.

const ITEM_SYSTEM := "res://src/items/ItemSystem.gd"
const EQUIPMENT_SYSTEM := "res://src/jobs/EquipmentSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_item_load_fallbacks_push_warning() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("items.json not found at"),
		"missing items.json must push_warning (was print-only 'Warning:')")
	assert_true(src.contains("items.json parsed but root is not a Dictionary"),
		"non-Dict-root items.json must push_warning")
	assert_true(src.contains("items.json parse error:"),
		"parse-error items.json must push_warning")
	# Confirm push_warning is actually invoked — substring match on
	# the message isn't enough if someone changes 'print' to
	# 'printerr' without escalating.
	assert_true(src.contains("push_warning(\"[ItemSystem]"),
		"ItemSystem load paths must call push_warning, not just print")


func test_equipment_load_fallbacks_push_warning() -> void:
	var src := _read(EQUIPMENT_SYSTEM)
	assert_true(src.contains("equipment.json not found at"),
		"missing equipment.json must push_warning (was print-only 'Warning:')")
	assert_true(src.contains("equipment.json parsed but root is not a Dictionary"),
		"non-Dict-root equipment.json must push_warning")
	assert_true(src.contains("equipment.json parse error:"),
		"parse-error equipment.json must push_warning")
	assert_true(src.contains("push_warning(\"[EquipmentSystem]"),
		"EquipmentSystem load paths must call push_warning, not just print")
