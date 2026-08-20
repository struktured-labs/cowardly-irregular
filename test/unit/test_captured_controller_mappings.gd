extends GutTest

## Captured pad mappings load from user:// so a controller can be added without a rebuild.
##
## Every failure path here must be LOUD. A silently-skipped mapping file presents to the player
## as "I mapped my pad and the buttons are still wrong", with nothing in the log — which is the
## same silent-raw-indices failure that cost a full session to diagnose in this subsystem before.

const CM = preload("res://src/input/ControllerMappings.gd")

var _cm: Node
# A real, well-formed SDL mapping: 32-hex GUID, name, at least one binding.
const GOOD := "03000000c82d00000b31000014010000,Test Pad,a:b0,b:b1,platform:Linux"


func before_each() -> void:
	_cm = CM.new()
	add_child_autofree(_cm)


func test_wellformed_accepts_a_real_mapping() -> void:
	assert_true(_cm.is_wellformed(GOOD), "a genuine SDL mapping string must validate")


func test_wellformed_rejects_the_shapes_sdl_silently_ignores() -> void:
	# SDL does not error on a malformed mapping — it ignores it, and the pad stays raw.
	assert_false(_cm.is_wellformed(""), "empty")
	assert_false(_cm.is_wellformed("not,enough"), "too few fields")
	assert_false(_cm.is_wellformed("tooshortguid,Test Pad,a:b0"), "GUID must be 32 hex chars")
	assert_false(_cm.is_wellformed("03000000c82d00000b31000014010000,,a:b0"), "name must not be empty")
	assert_false(_cm.is_wellformed("03000000c82d00000b31000014010000,Test Pad,nobindings"),
		"a mapping with no colon carries no bindings at all")


func test_shipped_mappings_all_validate() -> void:
	# Guards the const array against a typo'd entry that SDL would swallow in silence.
	var bad: Array[String] = []
	for m in CM.MAPPINGS:
		if not _cm.is_wellformed(m):
			bad.append(m.split(",")[0] if m.contains(",") else m)
	assert_eq(bad, [] as Array[String], "shipped mappings that SDL would silently ignore")


func test_absent_file_is_not_an_error() -> void:
	# First launch has no captured file; that is a normal state, not a warning.
	var da := DirAccess.open("user://")
	if da and da.file_exists("input/controller_mappings.json"):
		pass_test("a real captured file exists on this box; skipping the absent-file arm")
		return
	assert_eq(_cm.register_user_mappings(), 0, "absent file loads zero and does not throw")


func test_user_path_is_under_user_not_res() -> void:
	# res:// is read-only in an exported build — a captured mapping written there is lost.
	assert_true(CM.USER_MAPPINGS_PATH.begins_with("user://"),
		"captured mappings must persist somewhere writable in a shipped build")


func test_guid_extraction_survives_a_full_mapping() -> void:
	assert_eq(_cm.guid_of(GOOD), "03000000c82d00000b31000014010000")
