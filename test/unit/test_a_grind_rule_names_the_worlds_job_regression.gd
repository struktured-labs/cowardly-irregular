extends GutTest

## cowir-story's canon (21964): from W2 a party member's job reads as THAT world's name everywhere a player reads it. A grind rule's
## member key is a stored job id or character name, and the console grids capitalized it raw, so a W2 rule read "Cleric casts …"
## where the field said School Nurse. Every console site now goes through AutogrindSystem.member_display_name, which names a job id
## through Combatant.job_display_name_for_id (cowir-battle's one helper) and passes anything else through.

const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]

var _world_was: int = 1


func before_each() -> void:
	_world_was = int(GameState.current_world)


func after_each() -> void:
	GameState.current_world = _world_was


func test_in_world_two_a_job_member_reads_that_worlds_name() -> void:
	GameState.current_world = 2
	var differs := 0
	for jid in STARTERS:
		var want: String = JobSystem.get_job_display_name(jid)
		assert_eq(AutogrindSystem.member_display_name(jid), want, "in world 2 a rule's %s reads that world's name" % jid)
		if want != str(JobSystem.get_job(jid).get("name", "")):
			differs += 1
	assert_gt(differs, 0, "CONTROL: in world 2 some starter's name must differ from its base name, or this arm proves nothing")


func test_world_one_keeps_the_base_name() -> void:
	GameState.current_world = 1
	for jid in STARTERS:
		assert_eq(AutogrindSystem.member_display_name(jid), str(JobSystem.get_job(jid).get("name", "")), "W1 is byte-identical for %s" % jid)


func test_a_character_name_and_any_pass_through() -> void:
	GameState.current_world = 2
	assert_eq(AutogrindSystem.member_display_name(""), "Any", "an unscoped rule still reads Any")
	assert_eq(AutogrindSystem.member_display_name("mira"), "Mira", "a character name is not a job and passes through")


func test_the_console_cells_use_it() -> void:
	GameState.current_world = 2
	var ui: Node = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(ui)
	var nurse: String = JobSystem.get_job_display_name("cleric")
	assert_string_contains(ui._format_action({"type": "member_ability", "member": "cleric", "ability": "cure"}), nurse,
		"the console's casts cell names the world's job")
	assert_string_contains(ui._member_label({"type": "member_hp", "member": "cleric"}), nurse, "and so does a member-scoped condition")
	var ed: Node = load("res://src/ui/autogrind/AutogrindGridEditor.gd").new()
	add_child_autofree(ed)
	assert_string_contains(ed._format_action({"type": "member_ability", "member": "cleric", "ability": "cure"}), nurse,
		"the grind's rule editor too")


## Found on the same sweep: the Summary's "did nothing" rows print member_ability's skip reason, which named the ability by its
## ID ("Mira does not know cure") where the menu says its data name. A renamed ability must read as the menu shows it.
func test_a_skip_reason_names_the_ability_as_the_menu_does() -> void:
	var renamed := ""
	for aid in ["cure", "raise", "protect", "fire"]:
		if not JobSystem.get_ability(aid).is_empty() and AbilityIcons.name_of(aid).to_lower() != aid.replace("_", " "):
			renamed = aid
			break
	assert_ne(renamed, "", "CONTROL: some candidate ability shows a name that is not its id, or this arm proves nothing")
	var mage := Combatant.new()
	add_child_autofree(mage)
	mage.initialize({"name": "Mira", "max_hp": 100, "max_mp": 50})
	var info: Dictionary = AutogrindSystem._member_ability_apply(mage, renamed, "")
	var reason := str(info.get("reason", ""))
	assert_false(info.get("ok", true), "CONTROL: Mira cannot cast %s here (%s)" % [renamed, reason])
	assert_string_contains(reason, AbilityIcons.name_of(renamed), "the reason names the ability as the menu shows it")
	assert_false(reason.to_lower().contains(renamed), "and never by its bare id: '%s'" % reason)
