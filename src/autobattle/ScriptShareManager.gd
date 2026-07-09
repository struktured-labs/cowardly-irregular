extends RefCounted
class_name ScriptShareManager

## ScriptShareManager — Export/import autobattle scripts and autogrind rules as JSON.
## Files go to user://script_exports/ for easy sharing between players.

const EXPORT_DIR = "user://script_exports/"
const FILE_VERSION = 1
## Clipboard share codes: "COWIR1:" + base64(gzip(json)) — the only sharing path that works on web (user:// is IndexedDB) and survives a Discord paste.
const SHARE_CODE_PREFIX = "COWIR1:"
const SHARE_CODE_MAX_DECOMPRESSED = 262144


## Compact clipboard share code for one character's active script ("" if none).
static func encode_share_code(character_id: String) -> String:
	var script = AutobattleSystem.get_character_script(character_id)
	if script.is_empty():
		return ""
	var data = {
		"version": FILE_VERSION,
		"type": "autobattle_script",
		"character_id": character_id,
		"script": script,
	}
	var raw: PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_GZIP)
	return SHARE_CODE_PREFIX + Marshalls.raw_to_base64(packed)


## Decode + validate a share code. Returns the export dict ({} on ANY failure —
## bad prefix, bad base64, bad gzip, bad JSON, or rules failing the grammar).
static func decode_share_code(code: String) -> Dictionary:
	var c := code.strip_edges()
	if not c.begins_with(SHARE_CODE_PREFIX):
		return {}
	var packed: PackedByteArray = Marshalls.base64_to_raw(c.substr(SHARE_CODE_PREFIX.length()))
	if packed.is_empty():
		return {}
	var raw: PackedByteArray = packed.decompress_dynamic(SHARE_CODE_MAX_DECOMPRESSED, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("type") != "autobattle_script":
		return {}
	var errs := validate_imported_script(parsed.get("script", {}))
	if not errs.is_empty():
		push_warning("[SHARE] Share code rejected — %d invalid rule(s): %s" % [errs.size(), str(errs)])
		return {}
	return parsed

## Export a character's active autobattle script to a JSON file.
## Returns the file path on success, empty string on failure.
static func export_character_script(character_id: String) -> String:
	var script = AutobattleSystem.get_character_script(character_id)
	if script.is_empty():
		print("[SHARE] No script found for %s" % character_id)
		return ""

	var export_data = {
		"version": FILE_VERSION,
		"type": "autobattle_script",
		"character_id": character_id,
		"exported_at": Time.get_datetime_string_from_system(),
		"script": script,
	}

	var filename = "%s_autobattle.json" % character_id
	return _write_export(filename, export_data)


## Export all party autobattle scripts as a single bundle.
static func export_all_scripts(party: Array) -> String:
	var scripts: Dictionary = {}
	for member in party:
		if member is Combatant:
			var char_id = member.combatant_name.to_lower().replace(" ", "_")
			var script = AutobattleSystem.get_character_script(char_id)
			if not script.is_empty():
				scripts[char_id] = script

	if scripts.is_empty():
		print("[SHARE] No scripts to export")
		return ""

	var export_data = {
		"version": FILE_VERSION,
		"type": "autobattle_bundle",
		"exported_at": Time.get_datetime_string_from_system(),
		"scripts": scripts,
	}

	var filename = "party_autobattle.json"
	return _write_export(filename, export_data)


## Export autogrind rules to a JSON file.
static func export_autogrind_rules() -> String:
	var rules = AutogrindSystem.get_autogrind_rules()
	if rules.is_empty():
		print("[SHARE] No autogrind rules to export")
		return ""

	var export_data = {
		"version": FILE_VERSION,
		"type": "autogrind_rules",
		"exported_at": Time.get_datetime_string_from_system(),
		"rules": rules,
	}

	var filename = "autogrind_rules.json"
	return _write_export(filename, export_data)


## Import a script/rules file. Returns a dict with "type" and content, or empty on failure.
## Tick 168: every failure mode now uses push_warning instead of
## print. Imports are player-driven (user picks a file to import
## a friend's autobattle script). When import silently fails, the
## player has no signal beyond "the script didn't appear" — no
## hint whether the file was missing, malformed, or wrong shape.
## push_warning surfaces in the editor warnings panel + CI test
## runs. Also added the missing root-Dictionary check (pre-fix
## a parsed-but-non-Dict root would crash on the typed assignment
## `var data: Dictionary = json.data` at the next line).
static func import_file(filename: String) -> Dictionary:
	var path = EXPORT_DIR + filename
	if not FileAccess.file_exists(path):
		push_warning("[SHARE] Import file not found: %s" % path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("[SHARE] Import file exists but FileAccess.open failed: %s" % path)
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		push_warning("[SHARE] Import file '%s' JSON parse error: %s" % [filename, json.get_error_message()])
		return {}

	if not (json.data is Dictionary):
		push_warning("[SHARE] Import file '%s' parsed but root is not a Dictionary — expected a script/bundle export" % filename)
		return {}

	var data: Dictionary = json.data
	if not data.has("type") or not data.has("version"):
		push_warning("[SHARE] Import file '%s' missing required 'type' or 'version' fields — not a valid export" % filename)
		return {}

	return data


## Apply an imported autobattle script to a character.
## Validate an imported script's rules against the engine's grammar (shallow —
## structure + registered condition/target types, NOT fizzle/kit checks, since a
## shared script may have been authored for a different character/job). Returns
## the flattened error list ([] = clean). Guards against a hand-edited, malformed,
## or newer-version shared script silently misbehaving at runtime once applied.
static func validate_imported_script(script: Dictionary) -> Array:
	var errors: Array = []
	if not script.has("rules"):
		return ["script has no 'rules' key — not a valid export"]
	var rules = script["rules"]
	if typeof(rules) != TYPE_ARRAY:
		return ["'rules' is not an array"]
	for i in range(rules.size()):
		var rule = rules[i]
		if typeof(rule) != TYPE_DICTIONARY:
			errors.append("rule %d is not a dictionary" % i)
			continue
		for e in AutobattleSystem.validate_rule(rule):
			errors.append("rule %d: %s" % [i, str(e)])
	return errors


static func apply_character_script(character_id: String, data: Dictionary) -> bool:
	if data.get("type") == "autobattle_script":
		var script = data.get("script", {})
		if script.is_empty():
			return false
		var errs := validate_imported_script(script)
		if not errs.is_empty():
			push_warning("[SHARE] Rejected import for %s — %d invalid rule(s): %s" % [character_id, errs.size(), str(errs)])
			return false
		AutobattleSystem.set_character_script(character_id, script)
		print("[SHARE] Applied script to %s" % character_id)
		return true

	if data.get("type") == "autobattle_bundle":
		var scripts = data.get("scripts", {})
		if scripts.has(character_id):
			var errs := validate_imported_script(scripts[character_id])
			if not errs.is_empty():
				push_warning("[SHARE] Rejected bundled import for %s — %d invalid rule(s): %s" % [character_id, errs.size(), str(errs)])
				return false
			AutobattleSystem.set_character_script(character_id, scripts[character_id])
			print("[SHARE] Applied bundled script to %s" % character_id)
			return true

	return false


## Apply an imported autobattle bundle to all matching characters.
static func apply_script_bundle(data: Dictionary) -> int:
	if data.get("type") != "autobattle_bundle":
		return 0
	var scripts = data.get("scripts", {})
	var count = 0
	for char_id in scripts:
		var errs := validate_imported_script(scripts[char_id])
		if not errs.is_empty():
			# Skip the malformed one, keep importing the rest — a single bad
			# entry shouldn't sink an otherwise-good bundle.
			push_warning("[SHARE] Skipped bundled script for %s — %d invalid rule(s): %s" % [char_id, errs.size(), str(errs)])
			continue
		AutobattleSystem.set_character_script(char_id, scripts[char_id])
		count += 1
	print("[SHARE] Applied %d scripts from bundle" % count)
	return count


## Apply imported autogrind rules.
static func apply_autogrind_rules(data: Dictionary) -> bool:
	if data.get("type") != "autogrind_rules":
		return false
	var rules = data.get("rules", [])
	if rules.is_empty():
		return false
	AutogrindSystem.set_autogrind_rules(rules)
	print("[SHARE] Applied autogrind rules (%d rules)" % rules.size())
	return true


## List all available export files.
static func list_exports() -> Array[String]:
	var files: Array[String] = []
	if not DirAccess.dir_exists_absolute(EXPORT_DIR):
		return files
	var dir = DirAccess.open(EXPORT_DIR)
	if not dir:
		return files
	dir.list_dir_begin()
	var filename = dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			files.append(filename)
		filename = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


## Get a human-readable summary of an export file without fully loading it.
static func get_export_summary(filename: String) -> String:
	var data = import_file(filename)
	if data.is_empty():
		return "Invalid file"
	var type_str = data.get("type", "unknown")
	var date = data.get("exported_at", "unknown")
	match type_str:
		"autobattle_script":
			var char_id = data.get("character_id", "?")
			var rules_count = data.get("script", {}).get("rules", []).size()
			return "%s script (%d rules) — %s" % [char_id, rules_count, date]
		"autobattle_bundle":
			var count = data.get("scripts", {}).size()
			return "Party bundle (%d characters) — %s" % [count, date]
		"autogrind_rules":
			var count = data.get("rules", []).size()
			return "Autogrind rules (%d rules) — %s" % [count, date]
	return "%s — %s" % [type_str, date]


## Internal: write export data to file.
static func _write_export(filename: String, data: Dictionary) -> String:
	if not DirAccess.dir_exists_absolute(EXPORT_DIR):
		DirAccess.make_dir_recursive_absolute(EXPORT_DIR)

	var path = EXPORT_DIR + filename
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		## Tick 168: push_warning so the editor + CI surface this.
		## Export failures matter: the player triggered the export
		## expecting a file to land. Silent failure breaks the
		## share workflow (they hand a friend a path that doesn't
		## exist).
		push_warning("[SHARE] Could not open %s for write — export will fail (error: %s)" % [path, FileAccess.get_open_error()])
		return ""

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("[SHARE] Exported to %s" % path)
	return path
