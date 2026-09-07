extends RefCounted
class_name AutogrindAchievements

## Achievement catalog + evaluator for autogrind milestones.
##
## Design: data-driven catalog in data/autogrind_achievements.json — future milestones
## are one JSON entry, not a code change. Persistence rides on GameState.story_flags
## so the JobSystem "achievement" unlock condition (JobSystem.gd:723) can already
## check them without new wiring.

const CATALOG_PATH: String = "res://data/autogrind_achievements.json"

static var _cached_catalog: Array = []


static func catalog() -> Array:
	if _cached_catalog.is_empty():
		_cached_catalog = _load_catalog()
	return _cached_catalog


static func _load_catalog() -> Array:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("[AutogrindAchievements] Catalog not found: %s" % CATALOG_PATH)
		return []
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[AutogrindAchievements] Catalog root is not a dict")
		return []
	var raw: Array = parsed.get("achievements", [])
	var out: Array = []
	for entry in raw:
		if entry is Dictionary and entry.has("id") and entry.has("stat_key") and entry.has("threshold"):
			out.append(entry.duplicate(true))
	return out


## Returns achievements whose threshold is met by the given stats dict.
## `stats` should be an autogrind session's get_grind_stats() output (plus any extras).
static func earned_from_stats(stats: Dictionary) -> Array:
	var earned: Array = []
	for a in catalog():
		var stat_key: String = a["stat_key"]
		var threshold: float = float(a["threshold"])
		var value: float = float(stats.get(stat_key, 0))
		if value >= threshold:
			earned.append(a)
	return earned


## Returns [newly_awarded, already_earned] split against GameState.story_flags.
## Does NOT write flags — pass the newly_awarded array to award_all() to persist.
static func split_new_vs_earned(earned: Array, game_state) -> Array:
	var newly: Array = []
	var previously: Array = []
	for a in earned:
		var id: String = a["id"]
		if game_state != null and _is_flag_set(game_state, id):
			previously.append(a)
		else:
			newly.append(a)
	return [newly, previously]


## Write each newly-earned achievement's id to GameState.story_flags.
## Idempotent: re-awarding a set flag is a no-op.
static func award_all(newly_awarded: Array, game_state) -> void:
	if game_state == null:
		return
	for a in newly_awarded:
		var id: String = a["id"]
		_set_flag(game_state, id)


## Convenience: earn + split + award in one call. Returns the split array
## [newly_awarded, already_earned] so the summary UI can render both tiers.
static func check_and_award(stats: Dictionary, game_state) -> Array:
	var earned := earned_from_stats(stats)
	var split := split_new_vs_earned(earned, game_state)
	award_all(split[0], game_state)
	return split


static func _is_flag_set(game_state, flag: String) -> bool:
	if game_state.has_method("is_story_flag_set"):
		return bool(game_state.is_story_flag_set(flag))
	if "story_flags" in game_state:
		return bool(game_state.story_flags.get(flag, false))
	return false


static func _set_flag(game_state, flag: String) -> void:
	if game_state.has_method("set_story_flag"):
		game_state.set_story_flag(flag, true)
		return
	if "story_flags" in game_state:
		game_state.story_flags[flag] = true


## Test helper — clear the module-level cache so a test can rebuild it.
static func _reset_cache_for_test() -> void:
	_cached_catalog.clear()
