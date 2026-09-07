extends GutTest

## tick 140 regression: EquipmentMenu must never render an EQUIPPED
## item as "(empty)" just because the id doesn't resolve in
## EquipmentSystem (Scriptweaver custom item, save-format drift,
## or an item that was removed from data/equipment.json after a
## save was made). Pre-fix the menu would silently say "(empty)"
## for a slot that actually held something, so the player saw an
## "unarmed" state when they were actually wearing armor.

const EQUIPMENT_MENU := "res://src/ui/EquipmentMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _fn_body(name: String) -> String:
	var src := _read(EQUIPMENT_MENU)
	var idx: int = src.find("func " + name)
	assert_gt(idx, -1, "%s must exist" % name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_get_equipped_name_falls_back_to_resolver_for_unknown_id() -> void:
	# Pin: the function uses ItemNameResolver.resolve for unknown ids.
	# Without this fallback, an unknown-but-non-empty equipped_id
	# rendered as "(empty)" — misleading the player.
	var body := _fn_body("_get_equipped_name")
	assert_true(body.contains("ItemNameResolver.resolve(equipped_id)"),
		"_get_equipped_name must call ItemNameResolver.resolve for unknown ids")
	# Pin: there's a final fallback after the match for ids that
	# don't resolve in EquipmentSystem at all.
	assert_true(body.contains("if not equipped_id.is_empty():\n\t\treturn ItemNameResolver.resolve(equipped_id)"),
		"final fallback must resolve unknown-but-non-empty equipped_id")


func test_get_equipped_name_keeps_empty_for_truly_unequipped() -> void:
	# Negative pin: truly-empty (unequipped) slots still say "(empty)".
	# The fix must not regress that semantic.
	var body := _fn_body("_get_equipped_name")
	# Each slot must check is_empty and return "(empty)" first.
	var empty_check_count: int = 0
	var search_from: int = 0
	while true:
		var found: int = body.find("if equipped_id.is_empty():\n\t\t\t\treturn \"(empty)\"", search_from)
		if found < 0:
			break
		empty_check_count += 1
		search_from = found + 1
	assert_gte(empty_check_count, 3,
		"each of the 3 slots must keep the empty-id short-circuit")


func test_get_equipped_name_uses_dict_name_when_present() -> void:
	# Pin: when EquipmentSystem DOES know the item, the dict's "name"
	# field is preferred. Resolver fallback only when EquipmentSystem
	# is silent.
	var body := _fn_body("_get_equipped_name")
	# Each slot's positive branch reads .get("name", ...) and
	# falls back through ItemNameResolver.
	for getter in ["get_weapon", "get_armor", "get_accessory"]:
		assert_true(body.contains("EquipmentSystem.%s(equipped_id)" % getter),
			"slot must call EquipmentSystem.%s" % getter)
	assert_true(body.contains(".get(\"name\", ItemNameResolver.resolve(equipped_id))"),
		"dict name preferred; resolver is the default-fallback inside .get()")


func test_create_item_row_uses_resolver_fallback() -> void:
	# Pin: the second fix — _create_item_row's name_label fallback.
	# Pre-fix it fell back to raw id (e.g. "iron_sword") for
	# externally-passed items not in EquipmentSystem. Now resolver.
	var src := _read(EQUIPMENT_MENU)
	var idx: int = src.find("name_label.text = item_data.get")
	assert_gt(idx, -1, "name_label assignment must exist")
	var end_of_line: int = src.find("\n", idx)
	var line: String = src.substr(idx, end_of_line - idx)
	assert_true(line.contains("ItemNameResolver.resolve(item_id)"),
		"_create_item_row name fallback must use ItemNameResolver — not raw item_id")
	assert_false(line.contains("\"name\", item_id)"),
		"old raw-id fallback must be gone — was leaking snake_case")


func test_runtime_unknown_equipped_returns_resolver_output() -> void:
	# Runtime check: instantiate, attach a mock character with a
	# weapon id that doesn't exist in EquipmentSystem, and verify
	# the result is something other than "(empty)".
	var script_class = load(EQUIPMENT_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	# Build a minimal mock character.
	var mock = RefCounted.new()
	# Combatant has these three fields directly accessible.
	# Use a fake Combatant-shaped object via a script.
	var mock_script := GDScript.new()
	mock_script.source_code = """
extends RefCounted
var equipped_weapon: String = \"definitely_unknown_xyz\"
var equipped_armor: String = \"\"
var equipped_accessory: String = \"\"
"""
	var err: int = mock_script.reload()
	assert_eq(err, OK, "mock script must compile")
	inst.character = mock_script.new()
	var name_text: String = inst._get_equipped_name(0)
	assert_ne(name_text, "(empty)",
		"unknown equipped weapon must NOT render as '(empty)' — that misleads the player")
	# Should be the resolver output (prettified id since unknown).
	assert_eq(name_text, "Definitely Unknown Xyz",
		"resolver should produce the prettified form of the unknown id")
