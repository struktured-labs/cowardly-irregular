extends GutTest

## Regression: ALL_ALLIES items (Mega Potion, Mega Ether, Megalixir, Tent)
## only affected ONE party member when used in battle.
##
## Bug: in BattleCommandMenu._on_win98_menu_selection, the no-target fallback
## match grouped TargetType.ALL_ALLIES together with SINGLE_ALLY/SELF and
## collapsed the target list to a single ally (`targets = [it_target]`). So a
## 400g Mega Potion ('Restores 100 HP to all allies') healed only the leader.
## The OVERWORLD ItemsMenu path expanded ALL_ALLIES to the whole party, proving
## intent — only the battle path was broken.
##
## Fix: dedicated ALL_ALLIES arm that fills `targets` from every alive
## party_member. Source-pin tests (cheap) — end-to-end would need the full
## battle autoload + Win98Menu graph; we pin the dispatch surface instead.


const BATTLE_COMMAND_MENU_PATH := "res://src/battle/BattleCommandMenu.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_all_allies_has_dedicated_dispatch_arm() -> void:
	var text = _read(BATTLE_COMMAND_MENU_PATH)
	# There must be a standalone ALL_ALLIES match arm in the item dispatch.
	var idx = text.find("ItemSystem.TargetType.ALL_ALLIES:")
	assert_gt(idx, -1,
		"Item dispatch must have a dedicated ALL_ALLIES match arm (not grouped with SINGLE_ALLY/SELF)")
	# That arm must expand to the whole alive party, not a single ally.
	var slice = text.substr(idx, 400)
	assert_true(slice.find("for m in _scene.party_members") > -1,
		"ALL_ALLIES arm must iterate _scene.party_members to expand to the whole party")
	assert_true(slice.find("m.is_alive") > -1,
		"ALL_ALLIES arm must filter to alive party members")
	assert_true(slice.find("targets.append(m)") > -1,
		"ALL_ALLIES arm must append each alive party member to targets")


func test_all_allies_not_collapsed_to_single_ally() -> void:
	var text = _read(BATTLE_COMMAND_MENU_PATH)
	# The single-target arm (SINGLE_ALLY/SELF) must NOT also list ALL_ALLIES,
	# which was the original bug — ALL_ALLIES rode along and got collapsed to
	# `targets = [it_target]` (one ally).
	assert_eq(
		text.find("ItemSystem.TargetType.SINGLE_ALLY, ItemSystem.TargetType.ALL_ALLIES"),
		-1,
		"ALL_ALLIES must not be grouped with SINGLE_ALLY in the item dispatch match (collapses to one ally)")
	# The single-target arm should still exist for SINGLE_ALLY/SELF.
	assert_gt(
		text.find("ItemSystem.TargetType.SINGLE_ALLY, ItemSystem.TargetType.SELF:"),
		-1,
		"SINGLE_ALLY/SELF must still resolve to a single target")
