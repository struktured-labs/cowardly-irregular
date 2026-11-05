extends GutTest

## cowir-story's canon (2026-11-05, 21964): in W2-W6 the party's job name follows the world everywhere a player reads
## it; W1 keeps the base names. The autobattle editor's header printed `combatant.job.name`, the base name, so in W2
## the rule editor said "Cleric" while the world calls her School Nurse. Names come from data/job_world_names.json.
## Also covers the menu screens cowir-main routed here (21975): MenuScene, StatusMenu, EquipmentMenu, PartyStatusScreen.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _saved_world := 1
var _saved_persist := false
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_world = GameState.current_world
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	GameState.current_world = _saved_world
	AutobattleSystem._test_disable_persistence = _saved_persist


## The editor for Mira (no combatant, so the job comes from her character id: cleric), built in `world`.
func _editor_in(world: int) -> Node:
	GameState.current_world = world
	var ed: Node = load(ED).new()
	add_child_autofree(ed)
	ed.setup("mira", "Mira")
	await get_tree().process_frame
	return ed


func _drawn_texts(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return out


func test_the_floor_names_every_member_this_file_drives() -> void:
	var ed: Node = await _editor_in(1)
	for m in ["_get_job_name", "_get_job_id", "setup"]:
		assert_true(ed.has_method(m), "AutobattleGridEditor.%s must exist" % m)
	assert_true(JobSystem.has_method("get_job_display_name"), "JobSystem.get_job_display_name must exist")


func test_in_world_two_the_header_reads_that_worlds_name() -> void:
	var ed: Node = await _editor_in(2)
	var base := str(JobSystem.get_job("cleric").get("name", ""))
	GameState.current_world = 2
	var w2 := JobSystem.get_job_display_name("cleric")
	assert_ne(w2, base, "CONTROL: the data must name the W2 cleric differently from the base, or this arm proves nothing")
	assert_eq(ed._get_job_name(), w2, "the header must use this world's name")
	assert_true(w2 in _drawn_texts(ed), "and that is the text DRAWN in the header: %s" % [_drawn_texts(ed)])
	assert_false(base in _drawn_texts(ed), "the base name must not be drawn in W2")


func test_world_one_keeps_the_base_name() -> void:
	var ed: Node = await _editor_in(1)
	assert_eq(ed._get_job_name(), str(JobSystem.get_job("cleric").get("name", "")), "W1 keeps the base name, byte for byte")


func test_the_portrait_key_stays_on_the_job_id() -> void:
	var ed: Node = await _editor_in(2)
	assert_eq(ed._get_job_id(), "cleric", "the portrait key is the id in every world, not the display name")


## PartyStatusScreen's label is duck-typed (a Dictionary or Object job), so it is judged directly in W2.
func test_the_party_status_label_reads_this_worlds_name() -> void:
	GameState.current_world = 2
	var pss: Object = load("res://src/ui/PartyStatusScreen.gd").new()
	var member := Combatant.new()
	autofree(member)
	member.job = {"id": "cleric", "name": "Cleric"}
	assert_eq(pss._job_label(member), Combatant.job_display_name_for_id("cleric"), "a job with an id reads this world's name")
	member.job = {"name": "Odd Job"}
	assert_eq(pss._job_label(member), "Odd Job", "a job with no id keeps its stored name (the allowed fallback)")
	if pss is Node:
		(pss as Node).free()


## The other routed screens build their label inline; each must ASK the shared helper (battle's guard forbids the raw read).
func test_every_routed_screen_asks_the_shared_helper() -> void:
	for path in ["res://src/ui/MenuScene.gd", "res://src/ui/StatusMenu.gd", "res://src/ui/EquipmentMenu.gd",
			"res://src/ui/autobattle/AutobattleGridEditor.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 100, "PRECONDITION: %s must be readable" % path)
		## Either form of the helper: `job_display_name(` (a Combatant) or `job_display_name_for_id(` (an id). The first
		## version of this arm matched only the former, so the editor's correct id call read as missing.
		assert_true(src.contains("job_display_name(") or src.contains("job_display_name_for_id("),
			"%s must name the job through job_display_name / job_display_name_for_id" % path)
