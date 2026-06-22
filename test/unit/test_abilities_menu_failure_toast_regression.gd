extends GutTest

## AbilitiesMenu had three silent-failure paths that fired menu_error
## SFX with no other feedback. The most user-facing was the 'all
## passive slots full' case — the player clicked equip on a passive,
## heard a beep, nothing changed. Indistinguishable from "the button
## did nothing".
##
## Fix: Toast.show_warning on each path with a reason. The slots-full
## case includes the actual count so the player knows what they're up
## against.

const ABILITIES_MENU := "res://src/ui/AbilitiesMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_slots_full_toasts_with_counts() -> void:
	var src := _read(ABILITIES_MENU)
	# Message must include the equipped/max counts so the player can
	# see "I have 4/4 full, must unequip one" rather than a vague
	# "no room".
	assert_true(src.contains("All passive slots full (%d/%d)"),
		"slots-full Toast must show the equipped/max numbers so the player knows the cap")


func test_equip_failure_toasts_with_reason() -> void:
	var src := _read(ABILITIES_MENU)
	assert_true(src.contains("Equip failed (passive requirements not met)"),
		"equip-failed Toast must name the most-likely cause (requirements) — gives the player something to look at")


func test_unequip_failure_toasts() -> void:
	var src := _read(ABILITIES_MENU)
	assert_true(src.contains("Unequip failed"),
		"unequip-failed Toast must exist — even if rare, silent failure is worst")
