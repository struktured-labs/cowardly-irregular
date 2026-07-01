extends RefCounted
class_name AutogrindRuleTemplates

## Starter rule presets for autogrind. Templates install as fresh named profiles
## so a player can accept a curated setup without clobbering their own.
##
## Catalog: data/autogrind_rule_templates.json. Adding a template is one JSON
## entry — the picker + evaluator + persistence all keep working.

const CATALOG_PATH: String = "res://data/autogrind_rule_templates.json"

static var _cached_catalog: Array = []


static func catalog() -> Array:
	if _cached_catalog.is_empty():
		_cached_catalog = _load_catalog()
	return _cached_catalog


static func _load_catalog() -> Array:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("[AutogrindRuleTemplates] Catalog missing: %s" % CATALOG_PATH)
		return []
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[AutogrindRuleTemplates] Catalog root is not a dict")
		return []
	var raw: Array = parsed.get("templates", [])
	var out: Array = []
	for entry in raw:
		if entry is Dictionary and entry.has("id") and entry.has("name") and entry.has("rules"):
			out.append(entry.duplicate(true))
	return out


## Return the template with matching id, or empty dict.
static func find(id: String) -> Dictionary:
	for t in catalog():
		if t.get("id", "") == id:
			return t.duplicate(true)
	return {}


## Install a template as a NEW autogrind profile via the passed-in autogrind_system
## (usually the AutogrindSystem autoload — duck-typed so tests can supply a fake).
## Returns the new profile index, or -1 on failure (unknown id, at max profiles).
## Does NOT switch to the new profile — the UI decides whether to activate it.
static func install_as_new_profile(template_id: String, autogrind_system) -> int:
	var t := find(template_id)
	if t.is_empty() or autogrind_system == null:
		return -1
	if not autogrind_system.has_method("create_new_autogrind_profile"):
		return -1
	var idx: int = autogrind_system.create_new_autogrind_profile(str(t.get("name", "Template")))
	if idx < 0:
		return -1
	# Templates ship their own rules; overwrite the empty rule set that
	# create_new_autogrind_profile seeded with. Use set_autogrind_rules if
	# the system supports "write to a specific profile" — otherwise switch
	# active, write, restore.
	var rules: Array = (t.get("rules", []) as Array).duplicate(true)
	var previous_active: int = 0
	if autogrind_system.has_method("get_active_autogrind_profile_index"):
		previous_active = autogrind_system.get_active_autogrind_profile_index()
	if autogrind_system.has_method("set_active_autogrind_profile"):
		autogrind_system.set_active_autogrind_profile(idx)
	if autogrind_system.has_method("set_autogrind_rules"):
		autogrind_system.set_autogrind_rules(rules)
	if autogrind_system.has_method("set_active_autogrind_profile"):
		autogrind_system.set_active_autogrind_profile(previous_active)
	return idx


static func _reset_cache_for_test() -> void:
	_cached_catalog.clear()
