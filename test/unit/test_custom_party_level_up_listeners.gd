extends GutTest

## tick 82 regression: _create_party_from_customizations must call
## _wire_party_level_up_listeners() so the character-creation path
## gets the leveled_up + ability_learned signal wiring that the
## default-party path already has.
##
## Original silent gap (caught in tick 82 audit, surfaced by tick 81
## adding Bard's abilities_at_level): _create_party() ends with
## _wire_party_level_up_listeners() at line ~1704, but the parallel
## _create_party_from_customizations builds the party and returns
## without that call. Players who picked custom starting jobs got
## no toast when their characters hit a level-gated unlock
## (Bard@4/8, Fighter@3/6, Cleric@4/8, Mage@4/8, Rogue@3/6) — every
## starter is affected, not just Bard.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body(fn_name: String) -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func " + fn_name)
	assert_gt(idx, -1, "%s must exist" % fn_name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_create_party_from_customizations_wires_listeners() -> void:
	var body := _body("_create_party_from_customizations")
	assert_true(body.contains("_wire_party_level_up_listeners()"),
		"_create_party_from_customizations must call _wire_party_level_up_listeners() — character-creation path silently dropped Toast for level-up unlocks otherwise")


func test_default_create_party_still_wires_listeners() -> void:
	# Don't regress the original wiring while fixing the parallel path.
	var body := _body("_create_party")
	assert_true(body.contains("_wire_party_level_up_listeners()"),
		"_create_party (default party path) must still wire listeners")


func test_wiring_helper_idempotent_via_is_connected_guard() -> void:
	# Make sure the helper is safe to call multiple times. If a future
	# refactor calls _create_party then _create_party_from_customizations
	# (or any save-load reuse path), the second call must not stack
	# multiple connections.
	var body := _body("_wire_party_level_up_listeners")
	assert_true(body.contains("is_connected(_on_party_leveled_up)"),
		"_wire_party_level_up_listeners must guard with is_connected on leveled_up — otherwise repeated calls stack handlers")
	assert_true(body.contains("is_connected(_on_party_ability_learned)"),
		"_wire_party_level_up_listeners must guard with is_connected on ability_learned — symmetric protection")


func test_wiring_happens_after_party_is_built() -> void:
	# Ordering: the wire call must come AFTER the for-loop that adds
	# members to party. Otherwise members added later have no signal
	# wiring.
	var body := _body("_create_party_from_customizations")
	var loop_idx: int = body.find("for i in range(min(customizations.size()")
	var wire_idx: int = body.find("_wire_party_level_up_listeners()")
	assert_gt(loop_idx, -1, "party-building for-loop must exist")
	assert_gt(wire_idx, -1, "wire call must exist")
	assert_lt(loop_idx, wire_idx,
		"_wire_party_level_up_listeners must run AFTER the party-building loop — otherwise no members exist to wire")


func test_save_restore_path_still_wires_listeners() -> void:
	# Sanity: the save-restore path also wires listeners (tick 55).
	# Pin so a future refactor doesn't silently drop that too.
	var body := _body("_restore_party_from_save_data")
	assert_true(body.contains("_wire_party_level_up_listeners()"),
		"_restore_party_from_save_data must still wire listeners — restored Combatants don't carry connections from prior session")
