extends GutTest

## cowir-main 2026-11-05 (names are story's lane): a name a player reads is the DATA's name, never one built from an id.
## Ids stay FF-shaped by ruling (summon_bahamut, phoenix_down, firaga), and items/abilities/jobs carry their own names
## (Resurgo Plume, Ignis Maximus, W2's Mall Cop), so `id.capitalize()` on a player surface prints the wrong word.
## A literal sweep cannot see it (test_a_name_is_our_own reads strings); this arm judges the CALL that builds the name.

const SOURCE_ROOT := "res://src"
## Anything ending in .capitalize(), with any .replace(...) between the receiver and it.
const CAPITALIZED := "([\\w\\.\\]\\)\"]+?)((?:\\.replace\\([^()]*\\))*)\\.capitalize\\(\\)"
## A receiver that names an item, ability, job, spell or passive id. Keyed on the NAME, so a renamed variable escapes.
const NAMED_ID := "(?i)(item|abilit|job|spell|passive)|^jid$"
## The line reads the data's own name, so the capitalize is that lookup's fallback.
const READS_DATA := "get\\(\"(name|label|title)\"|get_job_display_name|ItemNameResolver|_display_name\\(|\\b(?<v>\\w+) if \\k<v> != \"\" else "
## (the last form is `shown if shown != "" else id...`: the id only when the looked-up name came back empty)
## Fallbacks whose data read sits on a NEIGHBOURING line. Each must still exist, so the list can only shrink.
const KNOWN_FALLBACKS := {
	"src/GameLoop.gd": ["var ability_name: String = ability_id.replace(\"_\", \" \").capitalize()", "overwritten by JobSystem's name on the next lines"],
	"src/ui/AbilitiesMenu.gd": ["\"name\": ability_id.replace(\"_\", \" \").capitalize(),", "the stub returned only after JobSystem.get_ability found nothing"],
	"src/items/ItemNameResolver.gd": ["return item_id.replace(\"_\", \" \").capitalize()", "the resolver's own last resort, after every table"],
}

var _saved_world: int = 1


func before_each() -> void:
	_saved_world = int(GameState.current_world)


func after_each() -> void:
	GameState.current_world = _saved_world


## [path, line, receiver] for every capitalize in `text` whose receiver names an id and whose line reads no data name.
func _offenders(path: String, text: String) -> Array:
	var cap := RegEx.new()
	cap.compile(CAPITALIZED)
	var named := RegEx.new()
	named.compile(NAMED_ID)
	var data := RegEx.new()
	data.compile(READS_DATA)
	var out: Array = []
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		if line.strip_edges().begins_with("#") or not line.contains(".capitalize()") or data.search(line) != null:
			continue
		for m in cap.search_all(line):
			var last: String = m.get_string(1).get_slice(".", m.get_string(1).get_slice_count(".") - 1)
			last = last.lstrip("\")](").rstrip("\")](")
			if named.search(last) != null:
				out.append([path, i + 1, line.strip_edges()])
	return out


func _source_files() -> Array:
	var out: Array = []
	var dirs: Array = [SOURCE_ROOT]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir + "/" + sub)
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				out.append(dir + "/" + f)
	return out


func test_the_detector_sees_the_shapes_it_forbids() -> void:
	for planted in ["return \"Use %s\" % item_id.capitalize()", "parts.append(str(jid).capitalize())",
			"emit(\"%s mimics %s\" % [a, _last_ability_cast_id.capitalize().replace(\"_\", \" \")])",
			"var d: String = item_id.replace(\"_\", \" \").capitalize()"]:
		assert_eq(_offenders("planted", planted).size(), 1, "CONTROL: the detector must catch: %s" % planted)
	for fine in ["ability.get(\"name\", ability_id.replace(\"_\", \" \").capitalize())", "return shown if shown != \"\" else ability_id.capitalize()", "var region := map_id.capitalize()",
			"label.text = element.capitalize()", "# item_id.capitalize() in a comment"]:
		assert_eq(_offenders("fine", fine).size(), 0, "the detector must leave alone: %s" % fine)


func test_no_source_line_builds_an_items_abilitys_or_jobs_name_from_its_id() -> void:
	var files := _source_files()
	assert_gt(files.size(), 200, "CONTROL: the walk of %s must read the game's scripts" % SOURCE_ROOT)
	var built: Array = []
	var excused_seen := {}
	for path in files:
		var rel: String = path.trim_prefix("res://")
		for o in _offenders(rel, FileAccess.get_file_as_string(path)):
			if KNOWN_FALLBACKS.has(rel) and o[2] == KNOWN_FALLBACKS[rel][0]:
				excused_seen[rel] = true
				continue
			built.append("%s:%d %s" % o)
	assert_eq(built, [], "names built from an id; read the data's name (ItemNameResolver, JobSystem.get_job_display_name, get(\"name\", ...))")
	for rel in KNOWN_FALLBACKS:
		assert_true(excused_seen.has(rel), "%s is excused (%s) but that line is gone: remove the entry" % [rel, KNOWN_FALLBACKS[rel][1]])


## "Requires: ✗Mall Cop, ✗School Nurse" -> {"Mall Cop": true, ...}: every job name on the formations page.
func _required_names_shown() -> Dictionary:
	var menu = load("res://src/ui/FormationsMenu.gd").new()
	add_child_autofree(menu)
	var shown := {}
	for n in menu.find_children("*", "Label", true, false):
		var t: String = (n as Label).text
		if t.begins_with("Requires: "):
			for part in t.trim_prefix("Requires: ").split(", "):
				shown[part.substr(1)] = true
	return shown


func test_the_formations_page_names_each_job_as_this_world_does() -> void:
	var formations: Array = load("res://src/battle/BattleCommandMenu.gd").FORMATIONS
	assert_gt(formations.size(), 3, "CONTROL: the formation table must load")
	GameState.current_world = 2
	var renamed := 0
	var want := {}
	for f in formations:
		for jid in f.get("required_jobs", []):
			var name: String = JobSystem.get_job_display_name(str(jid))
			want[name] = str(jid)
			if name != str(jid).capitalize():
				renamed += 1
	assert_gt(renamed, 0, "CONTROL: in world 2 some required job must have a name that is not its id, or this arm proves nothing")
	var shown := _required_names_shown()
	assert_gt(shown.size(), 3, "CONTROL: the page must list its requirements")
	for name in want:
		assert_true(shown.has(name), "the formations page must name %s as %s, the world-2 name every other screen uses (shows %s)" % [want[name], name, shown.keys()])
