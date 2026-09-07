extends RefCounted
class_name AutobattleRuleTemplates

## Starter rule presets for per-character autobattle scripts. Sibling of
## AutogrindRuleTemplates (same catalog/find/install API) — kept separate
## because autobattle is per-character while autogrind is party-level.
##
## Catalog: data/autobattle_rule_templates.json. 3 stances per starter job
## (Defensive / Balanced / Aggressive). Adding a template is one JSON entry.

const CATALOG_PATH: String = "res://data/autobattle_rule_templates.json"

static var _cached_catalog: Array = []


static func catalog() -> Array:
	if _cached_catalog.is_empty():
		_cached_catalog = _load_catalog()
	return _cached_catalog


static func _load_catalog() -> Array:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("[AutobattleRuleTemplates] Catalog missing: %s" % CATALOG_PATH)
		return []
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_warning("[AutobattleRuleTemplates] Catalog unreadable: %s" % CATALOG_PATH)
		return []
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[AutobattleRuleTemplates] Catalog root is not a dict")
		return []
	var raw: Array = parsed.get("templates", [])
	var out: Array = []
	for entry in raw:
		if entry is Dictionary and entry.has("id") and entry.has("name") \
				and entry.has("job_id") and entry.has("rules"):
			out.append(entry.duplicate(true))
	return out


## Return the template with matching id, or empty dict.
static func find(id: String) -> Dictionary:
	for t in catalog():
		if t.get("id", "") == id:
			return t.duplicate(true)
	return {}


## All templates for one job, catalog order (defensive, balanced, aggressive).
static func find_for_job(job_id: String) -> Array:
	var out: Array = []
	for t in catalog():
		if t.get("job_id", "") == job_id:
			out.append(t.duplicate(true))
	return out


## Build the character-script dict a template installs — the same shape
## AutobattleSystem.get_character_script returns / set_character_script writes.
static func build_script(template: Dictionary, character_id: String) -> Dictionary:
	return {
		"character_id": character_id,
		"name": str(template.get("name", "Preset")),
		"rules": (template.get("rules", []) as Array).duplicate(true),
	}


## Install a template as a NEW autobattle profile for one character via the
## passed-in autobattle_system (usually the AutobattleSystem autoload —
## duck-typed so tests can supply a fake). Returns the new profile index,
## or -1 on failure (unknown id, at max profiles, null/incapable system).
## Does NOT leave the new profile active — the player's currently-active
## profile is restored after the write (same contract as AutogrindRuleTemplates).
static func install_as_new_profile(template_id: String, autobattle_system, character_id: String) -> int:
	var t := find(template_id)
	if t.is_empty() or autobattle_system == null or character_id == "":
		return -1
	for m in ["create_new_profile", "get_active_profile_index", "set_active_profile", "set_character_script"]:
		if not autobattle_system.has_method(m):
			return -1
	var idx: int = autobattle_system.create_new_profile(character_id, str(t.get("name", "Preset")))
	if idx < 0:
		return -1
	# set_character_script writes the ACTIVE profile, so flip → write → restore.
	var previous_active: int = autobattle_system.get_active_profile_index(character_id)
	autobattle_system.set_active_profile(character_id, idx)
	autobattle_system.set_character_script(character_id, build_script(t, character_id))
	autobattle_system.set_active_profile(character_id, previous_active)
	return idx


static func _reset_cache_for_test() -> void:
	_cached_catalog.clear()
