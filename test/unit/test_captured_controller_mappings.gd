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


## ⛔ TWO SHAPES THE ARM ABOVE CLAIMED AND NEVER DROVE. Its GUID case is `tooshortguid` and its
## message reads "GUID must be 32 hex chars" — the fixture is short, so the LENGTH half was tested
## and the HEX half was decoration, and `is_wellformed` checked only length to match. A message
## that names a rule no fixture exercises is how the rule goes missing from the implementation.
func test_wellformed_rejects_a_guid_that_is_long_enough_but_not_hex() -> void:
	var right_length_wrong_alphabet := "zzzzzzzzc82d00000b31000014010000"
	assert_eq(right_length_wrong_alphabet.length(), 32,
		"CONTROL: the fixture must be 32 chars, or this arm passes on the LENGTH rule and proves nothing")
	assert_false(_cm.is_wellformed("%s,Test Pad,a:b0,platform:Linux" % right_length_wrong_alphabet),
		"a 32-character non-hex GUID matches no device — SDL ignores it in silence")


## The MAPPINGS docstring says platform tagging is what makes an entry apply: a Linux-tagged entry
## does not apply on Windows, and an UNtagged one is not a mapping SDL will use. The capture path
## emits one, so requiring it costs nothing and closes the hand-edited user:// file.
func test_wellformed_rejects_a_mapping_with_no_platform_clause() -> void:
	assert_true(_cm.is_wellformed(GOOD), "CONTROL: GOOD carries platform:Linux and must still pass")
	assert_false(_cm.is_wellformed("03000000c82d00000b31000014010000,Test Pad,a:b0"),
		"without a platform clause SDL will not apply the mapping, and nothing says so")


## ✅ THE CORRECT-CHANGE DIRECTION, which a mutation test never covers: the rule above must accept
## a platform this project does not ship today. `default_platform()` emits the RUNNING platform, so
## a pad captured on Windows carries `platform:Windows` — tightening the check to `platform:Linux`
## would reject a genuine capture from the only person who could make one.
func test_wellformed_accepts_a_platform_this_project_does_not_ship() -> void:
	for platform in ["Windows", "Mac OS X", "Web"]:
		assert_true(_cm.is_wellformed("03000000c82d00000b31000014010000,Test Pad,a:b0,platform:%s" % platform),
			"a %s capture is well-formed — the rule is that a platform is NAMED, not which one" % platform)


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
