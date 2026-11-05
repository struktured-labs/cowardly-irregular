extends GutTest

## Story's canon ruling 21964 / cowir-main 21961, 21966: in W2-W6 a party member's job reads as THAT world's name
## (data/job_world_names.json: the Cleric is a School Nurse) everywhere a player reads it; W1 keeps the base name.
## Six lanes had claimed six copies of one defect, `job.get("name")` read for display, so this is ONE mechanism:
## Combatant.job_display_name() / job_display_name_for_id(id), and KEY reads use the id (job_id_key()).
## The guard below is DERIVED over src: every raw job-name read must be the helper, a named fallback, or a site
## still PENDING its lane's conversion (owner named). A pending entry reds when its read is gone, so the list only shrinks.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SRC := "res://src"

## path → [allowed raw reads, kind, owner/reason]. Kinds: HELPER (the one display read) · FALLBACK (after a
## display-name call, for a job with no id) · PENDING (a display read its lane converts in the .772 batch).
const ALLOWED := {
	"res://src/battle/Combatant.gd": [1, "HELPER", "job_display_name()'s own read, for a job dict with no id"],
	"res://src/ui/JobMenu.gd": [2, "FALLBACK", "after get_job_display_name, only when the job has no id"],
	"res://src/ui/autobattle/AutobattleGridEditor.gd": [1, "PENDING", "cowir-controller (editor header)"],
	"res://src/ui/MenuScene.gd": [4, "PENDING", "unassigned UI (party/status rows): cowir-main to route"],
	"res://src/ui/StatusMenu.gd": [1, "PENDING", "unassigned UI: cowir-main to route"],
	"res://src/ui/EquipmentMenu.gd": [1, "PENDING", "unassigned UI: cowir-main to route"],
	"res://src/ui/PartyStatusScreen.gd": [4, "PENDING", "unassigned UI: cowir-main to route"],
	"res://src/maps/interiors/EldertreeGraftingHouseInterior.gd": [1, "PENDING", "cowir-story/overworld (an NPC names the leader's job)"],
}

var _guard
var _saved_world := 1


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_world = int(GameState.current_world)


func after_each() -> void:
	GameState.current_world = _saved_world
	_guard.restore()


func _rx() -> RegEx:
	var rx := RegEx.new()
	rx.compile("job\\.get\\(\"name\"|job\\[\"name\"\\]|job\\.name\\b")
	return rx


func _raw_reads() -> Dictionary:
	var rx := _rx()
	var out := {}
	var stack: Array[String] = [SRC]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			var full := "%s/%s" % [dir_path, n]
			if d.current_is_dir():
				if not n.begins_with("."):
					stack.append(full)
			elif n.ends_with(".gd"):
				var count := 0
				for line in FileAccess.get_file_as_string(full).split("\n"):
					if line.strip_edges().begins_with("#"):
						continue
					count += rx.search_all(line).size()
				if count > 0:
					out[full] = count
			n = d.get_next()
	return out


func test_the_detector_sees_the_shapes_it_forbids() -> void:
	var rx := _rx()
	for planted in ['x = member.job.get("name", "Fighter")', 'y = c.job["name"]', 'z = str(member.job.name)']:
		assert_not_null(rx.search(planted), "CONTROL: the detector catches %s" % planted)
	for fine in ['job_display_name()', 'job.get("id", "")', 'get_job(jid).get("name", "")']:
		assert_null(rx.search(fine), "CONTROL: the detector passes %s" % fine)


func test_no_job_name_is_read_for_display_outside_the_helper() -> void:
	var found := _raw_reads()
	assert_gt(found.size(), 0, "CONTROL: the walk found the helper's own read at least")
	var over: Array = []
	for path in found:
		var allowed: int = int(ALLOWED.get(path, [0])[0])
		if int(found[path]) > allowed:
			over.append("%s: %d raw job-name read(s), %d allowed" % [path, found[path], allowed])
	assert_eq(over, [], "a job name read for DISPLAY must go through Combatant.job_display_name() / job_display_name_for_id()")


## The list can only shrink: an allowance its file no longer needs reds, so a converted site is crossed off.
func test_every_allowance_is_still_needed() -> void:
	var found := _raw_reads()
	var stale: Array = []
	for path in ALLOWED:
		var have: int = int(found.get(path, 0))
		if have < int(ALLOWED[path][0]):
			stale.append("%s allows %d but reads %d (%s): lower or remove its entry" % [path, ALLOWED[path][0], have, ALLOWED[path][2]])
	assert_eq(stale, [], "a converted site leaves a stale allowance")


func test_a_job_reads_as_its_worlds_name() -> void:
	var c := Combatant.new()
	add_child_autofree(c)
	c.job = JobSystem.get_job("cleric")
	assert_false((c.job as Dictionary).is_empty(), "CONTROL: the cleric job exists")
	GameState.current_world = 1
	var w1 := c.job_display_name()
	assert_eq(w1, str(c.job.get("name", "")), "W1 keeps the base name, byte for byte")
	GameState.current_world = 2
	var w2 := c.job_display_name()
	assert_eq(w2, JobSystem.get_job_display_name("cleric"), "W2 reads the world's name")
	assert_ne(w2, w1, "CONTROL: the cleric really is renamed in W2, or this arm proves nothing")
	assert_eq(Combatant.job_display_name_for_id("cleric"), w2, "the id form agrees (autogrind's stored rule values)")
	assert_eq(c.job_id_key(), "cleric", "and the KEY stays the id in every world")


## sprites 21968: VictoryOverlay keyed the portrait by the job NAME lowercased, so time_mage looked for
## "time mage.png" (absent) on main, and every job would miss in W2. The results row now carries the id.
func test_a_victory_portrait_is_keyed_by_the_job_id() -> void:
	var c := Combatant.new()
	add_child_autofree(c)
	c.job = JobSystem.get_job("time_mage")
	assert_false((c.job as Dictionary).is_empty(), "CONTROL: the time_mage job exists")
	assert_ne(str(c.job.get("name", "")).to_lower(), "time_mage", "CONTROL: its name lowercased is NOT its id, the case that broke")
	var path: String = HybridSpriteLoader.portrait_path(c.job_id_key())
	assert_ne(path, "", "the id resolves a portrait path")
	assert_true(ResourceLoader.exists(path), "and the portrait exists: %s" % path)
	var src := FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	assert_string_contains(src, 'cr.get("job_id"', "VictoryOverlay keys the portrait by the results row's job_id")
	assert_string_contains(FileAccess.get_file_as_string("res://src/battle/BattleManager.gd"), '"job_id": combatant.job_id_key()', "and BattleManager writes it")
