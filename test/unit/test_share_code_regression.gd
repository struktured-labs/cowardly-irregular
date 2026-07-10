extends GutTest

## Feature 2026-07-09: clipboard share codes (COWIR1: + base64(gzip(json))) —
## the first sharing path that actually leaves a player's machine (Discord/
## forum paste) and the only workable one on web, where user://script_exports
## is IndexedDB. Pins the round-trip, every rejection path, and that decode
## validates rules BEFORE returning (untrusted input by definition).

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")
const CHAR := "share_code_test_char"


func _valid_script() -> Dictionary:
	return {"rules": [
		{"conditions": [{"type": "enemy_has_status", "status": "stun"}],
		 "actions": [{"type": "ability", "id": "fire", "target": "weakest_to_ability"}],
		 "enabled": true},
	]}


func after_each() -> void:
	AutobattleSystem.character_scripts.erase(CHAR)
	AutobattleSystem.character_profiles.erase(CHAR)
	AutobattleSystem.character_profiles.erase("no_such_char_zzz")


func test_share_code_round_trip() -> void:
	AutobattleSystem.set_character_script(CHAR, _valid_script())
	var code := SSM.encode_share_code(CHAR)
	assert_true(code.begins_with(SSM.SHARE_CODE_PREFIX), "code carries the format prefix")
	var decoded := SSM.decode_share_code(code)
	assert_false(decoded.is_empty(), "own code must decode")
	assert_eq(decoded.get("type"), "autobattle_script")
	var rules: Array = decoded.get("script", {}).get("rules", [])
	assert_eq(rules.size(), 1, "the rule survives the trip")
	assert_eq(str(rules[0]["conditions"][0]["type"]), "enemy_has_status")
	# whitespace-padded paste (Discord adds trailing newlines) still decodes
	assert_false(SSM.decode_share_code("  " + code + "\n").is_empty(),
		"decode must strip paste whitespace")


func test_unknown_character_shares_its_default_script() -> void:
	# get_character_script NEVER returns empty — unknown ids get the stock
	# default profile, so Shift+E always yields a valid, decodable code.
	var code := SSM.encode_share_code("no_such_char_zzz")
	assert_true(code.begins_with(SSM.SHARE_CODE_PREFIX), "default script still encodes")
	assert_false(SSM.decode_share_code(code).is_empty(), "and round-trips")


func test_garbage_rejections_all_return_empty() -> void:
	for bad in ["", "hello", "COWIR1:", "COWIR1:!!!not-base64!!!",
			"COWIR1:" + Marshalls.utf8_to_base64("not gzip"),
			"COWIR2:" + Marshalls.utf8_to_base64("wrong prefix")]:
		assert_true(SSM.decode_share_code(bad).is_empty(),
			"garbage code %s must decode to {}" % bad.left(24))


func test_decode_rejects_codes_carrying_invalid_rules() -> void:
	# A structurally-perfect code whose RULES fail the grammar must be
	# rejected at decode — untrusted input never reaches apply half-checked.
	var payload := {"version": 1, "type": "autobattle_script", "character_id": CHAR,
		"script": {"rules": [{"conditions": [{"type": "always"}],
			"actions": [{"type": "attack", "target": "not_a_real_target"}], "enabled": true}]}}
	var packed: PackedByteArray = JSON.stringify(payload).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var code := SSM.SHARE_CODE_PREFIX + Marshalls.raw_to_base64(packed)
	assert_true(SSM.decode_share_code(code).is_empty(),
		"a code with grammar-invalid rules must be rejected at decode")


func test_autogrind_share_code_round_trip() -> void:
	var prev: Array = AutogrindSystem.get_autogrind_rules()
	AutogrindSystem.set_autogrind_rules([
		{"conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}], "enabled": true},
	])
	var code := SSM.encode_autogrind_share_code()
	assert_true(code.begins_with(SSM.SHARE_CODE_PREFIX), "autogrind code carries the same prefix")
	var decoded := SSM.decode_share_code(code)
	assert_eq(decoded.get("type"), "autogrind_rules", "decode branches on payload type")
	assert_eq((decoded.get("rules", []) as Array).size(), 1, "rules survive the trip")
	AutogrindSystem.set_autogrind_rules(prev)


func test_apply_autogrind_rules_now_validates() -> void:
	# The gap this tick closed: apply_autogrind_rules applied UNVALIDATED
	# while the autobattle path validated — an untrusted paste with a bogus
	# condition type would have applied raw.
	var prev: Array = AutogrindSystem.get_autogrind_rules()
	var bad := {"type": "autogrind_rules", "rules": [
		{"conditions": [{"type": "definitely_not_a_condition_zzz"}], "actions": [{"type": "stop_grinding"}], "enabled": true},
	]}
	assert_false(SSM.apply_autogrind_rules(bad),
		"grammar-invalid autogrind rules must be refused at apply")
	assert_eq(str(AutogrindSystem.get_autogrind_rules()), str(prev),
		"refused import must not mutate the active rules")


func test_autogrind_footer_documents_the_bindings() -> void:
	# Discoverability: the console's footer must list the file AND code flows
	# (they existed with zero mention — undiscoverable features are half-built).
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")
	assert_true("[E/I]: Files" in src and "[Sh+E/I]: Codes" in src,
		"the autogrind footer documents export/import and share codes")


func test_editor_wires_the_clipboard_bindings() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")
	assert_true("_copy_share_code" in src and "_paste_share_code" in src, "handlers exist")
	assert_true("clipboard_set" in src and "clipboard_get" in src, "clipboard wired both ways")
	assert_true("Sh+E:CopyCode" in src and "Sh+I:PasteCode" in src, "legend documents the bindings")
