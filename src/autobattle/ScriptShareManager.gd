extends RefCounted
class_name ScriptShareManager

## ScriptShareManager — Export/import autobattle scripts and autogrind rules as JSON.
## Files go to user://script_exports/ for easy sharing between players.

const EXPORT_DIR = "user://script_exports/"
const FILE_VERSION = 1

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
static func import_file(filename: String) -> Dictionary:
	var path = EXPORT_DIR + filename
	if not FileAccess.file_exists(path):
		print("[SHARE] File not found: %s" % path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("[SHARE] Cannot open: %s" % path)
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		print("[SHARE] Invalid JSON in %s" % filename)
		return {}

	var data: Dictionary = json.data
	if not data.has("type") or not data.has("version"):
		print("[SHARE] Missing type/version in %s" % filename)
		return {}

	return data


## Apply an imported autobattle script to a character.
static func apply_character_script(character_id: String, data: Dictionary) -> bool:
	if data.get("type") == "autobattle_script":
		var script = data.get("script", {})
		if script.is_empty():
			return false
		AutobattleSystem.set_character_script(character_id, script)
		print("[SHARE] Applied script to %s" % character_id)
		return true

	if data.get("type") == "autobattle_bundle":
		var scripts = data.get("scripts", {})
		if scripts.has(character_id):
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
		print("[SHARE] Cannot write to %s" % path)
		return ""

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("[SHARE] Exported to %s" % path)
	return path
