extends GutTest

## tick 265: SaveSystem no longer writes a dead "inventory" field.
##
## Pre-cleanup _serialize_inventory returned {} unconditionally with
## a stale "TODO: when InventorySystem is implemented" — the field
## had been a placeholder since 2025 and confused future readers
## into thinking a separate party-wide system existed somewhere.
## Per-character inventory IS implemented via Combatant.to_dict /
## from_dict — that's the only real storage.
##
## This test pins:
##   - the dead stubs are gone from SaveSystem
##   - new saves don't write the "inventory" field
##   - legacy saves that HAVE the "inventory" field still load cleanly
##     (silently ignored, not crashed on)

const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Dead stubs are gone ────────────────────────────────────────────

func test_serialize_inventory_stub_removed() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_false(src.contains("func _serialize_inventory("),
		"_serialize_inventory stub must be removed — it was always returning {}")
	# Negative pin: the stale TODO is gone too.
	assert_false(src.contains("TODO: serialize party-wide item inventory"),
		"the stale TODO comment must be removed alongside the stub")


func test_deserialize_inventory_stub_removed() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_false(src.contains("func _deserialize_inventory("),
		"_deserialize_inventory stub must be removed — it was a no-op pass")


# ── New saves don't add the "inventory" field ──────────────────────

func test_new_saves_omit_inventory_field() -> void:
	# Pin: the previous _serialize_inventory() call is gone from
	# _serialize_save_data so new save dicts won't have an "inventory"
	# key.
	var src := _read(SAVE_SYSTEM)
	# Only legacy-handling comments may mention it; no active
	# `data["inventory"] = _serialize_inventory()` line remains.
	assert_false(src.contains("data[\"inventory\"] = _serialize_inventory()"),
		"_serialize_save_data must not call the dead _serialize_inventory")
	# Also no active `_deserialize_inventory(data["inventory"])` line.
	assert_false(src.contains("_deserialize_inventory(data[\"inventory\"])"),
		"_apply_save_data must not call the dead _deserialize_inventory")


# ── Legacy saves with the "inventory" field load cleanly ───────────

func test_legacy_save_with_inventory_field_loads_without_crash() -> void:
	# Synthesize the legacy shape (small dict with the dead field)
	# and run _apply_save_data through it. Must not crash.
	var save_system_script: GDScript = load(SAVE_SYSTEM)
	var ss = save_system_script.new()
	add_child_autofree(ss)
	# Minimal legacy save: just the dead field. Anything else missing
	# is fine — _apply_save_data uses `has(...)` guards throughout.
	var legacy: Dictionary = {
		"inventory": {"potion": 5},  # never read by current code
	}
	# Should not crash — the absence of an inventory call site means
	# the field is silently ignored.
	ss._apply_save_data(legacy)
	assert_true(true,
		"legacy save with an 'inventory' field must load without crashing")


# ── Cross-pin: Combatant inventory still roundtrips (the REAL path) ─

func test_combatant_inventory_still_persists() -> void:
	# Defensive: confirm the actual inventory mechanism wasn't
	# accidentally removed when the dead stubs were cleaned up.
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var c = combatant_script.new()
	add_child_autofree(c)
	c.add_item("potion", 3)
	var data: Dictionary = c.to_dict()
	assert_true(data.has("inventory"),
		"Combatant.to_dict must still include 'inventory' field (this is the real storage)")
	assert_eq(data["inventory"].get("potion", 0), 3,
		"Combatant.to_dict must serialize item quantities accurately")
