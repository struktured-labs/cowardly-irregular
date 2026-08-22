extends GutTest
## Guards that job_world_names.json REACHES the player: authored + tested is not the same as wired.

var _gs: Node = null
var _saved_world: int = 1


func before_each() -> void:
	_gs = get_node_or_null("/root/GameState")
	if _gs != null:
		_saved_world = int(_gs.current_world)


func after_each() -> void:
	if _gs != null:
		_gs.current_world = _saved_world


func test_the_probe_and_its_corpus_are_real() -> void:
	assert_not_null(JobSystem, "JobSystem autoload missing — every assert below would be vacuous")
	assert_not_null(_gs, "GameState autoload missing — the world cannot be varied")
	assert_false(JobSystem.job_world_names.is_empty(), "job_world_names.json did not load")
	assert_true(JobSystem.has_method("get_job_display_name"), "the resolver must exist")


func test_fighter_renames_across_worlds() -> void:
	_gs.current_world = 1
	assert_eq(JobSystem.get_job_display_name("fighter"), "Fighter", "W1 medieval")
	_gs.current_world = 2
	assert_eq(JobSystem.get_job_display_name("fighter"), "Mall Cop", "W2 suburban")
	_gs.current_world = 6
	assert_eq(JobSystem.get_job_display_name("fighter"), "Blunt Instrument", "W6 abstract")


func test_every_starter_job_changes_between_w1_and_w2() -> void:
	for jid in ["fighter", "cleric", "mage", "rogue", "bard"]:
		_gs.current_world = 1
		var w1: String = JobSystem.get_job_display_name(jid)
		_gs.current_world = 2
		var w2: String = JobSystem.get_job_display_name(jid)
		assert_ne(w1, w2, "%s must read differently in W2 than W1" % jid)
		assert_ne(w2, "", "%s must never render as an empty label" % jid)


func test_unknown_job_never_renders_empty() -> void:
	_gs.current_world = 3
	assert_ne(JobSystem.get_job_display_name("zzz_not_a_job"), "", "unknown job must fall back, not blank")


func test_out_of_range_world_falls_back_to_the_base_name() -> void:
	_gs.current_world = 99
	assert_eq(JobSystem.get_job_display_name("fighter"), "Fighter", "no theme for world 99 — base name")
