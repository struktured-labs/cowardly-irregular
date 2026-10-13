extends GutTest

## struktured's 2026-10-12 play log: changing a Rogue with a full passive bar to Ninja logged
## "[PassiveSystem] equip_passive: Rogue slot full (5/5) — equip of '<id>' failed" once per roster
## passive. The state is expected — the passives are learned and wait in the menu — so the grant
## asks for a free slot first. An unknown id still reaches equip_passive and still warns.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _member(equipped: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Probe"
	var ids: Array = PassiveSystem.passives.keys()
	var i := 0
	while c.equipped_passives.size() < equipped and i < ids.size():
		c.learned_passives.append(str(ids[i]))
		c.equipped_passives.append(str(ids[i]))
		i += 1
	return c


func _fresh_ids(c: Combatant, n: int) -> Array:
	var out: Array = []
	for id in PassiveSystem.passives.keys():
		if not (str(id) in c.learned_passives):
			out.append(str(id))
		if out.size() == n:
			break
	return out


func test_floor_the_symbols_this_file_drives_exist() -> void:
	assert_true(JobSystem.has_method("_grant_roster_passives"), "the grant this file drives")
	assert_gt(PassiveSystem.passives.size(), 8, "enough passives to fill a bar and have more to grant")


func test_a_free_slot_still_equips_what_the_job_grants() -> void:
	var c := _member(0)
	var ids := _fresh_ids(c, 2)
	JobSystem._grant_roster_passives(c, {"passive_abilities": ids})
	for id in ids:
		assert_true(id in c.learned_passives, "CONTROL: %s is learned" % id)
		assert_true(id in c.equipped_passives, "CONTROL: with room on the bar, %s is equipped" % id)


func test_a_full_bar_learns_and_leaves_the_bar_alone() -> void:
	var c := _member(5)
	assert_eq(c.equipped_passives.size(), c.max_passive_slots, "SCOPE: the bar is full")
	var before: Array = c.equipped_passives.duplicate()
	var ids := _fresh_ids(c, 3)
	assert_eq(ids.size(), 3, "SCOPE: three passives the member has not learned")
	JobSystem._grant_roster_passives(c, {"passive_abilities": ids})
	for id in ids:
		assert_true(id in c.learned_passives, "%s is learned even though it could not be equipped" % id)
	assert_eq(c.equipped_passives, before, "the full bar is untouched")


func test_the_grant_asks_for_a_free_slot_before_equipping() -> void:
	var code: String = GdSource.code_of("res://src/jobs/JobSystem.gd")
	var at := code.find("func _grant_roster_passives")
	var end := code.find("\nfunc ", at + 1)
	assert_gt(at, -1, "the grant exists")
	assert_gt(end, at, "the grant ends at a next function")
	var body := code.substr(at, end - at)
	var guard := body.find("max_passive_slots")
	var equip := body.find("equip_passive(combatant")
	assert_gt(guard, -1, "the grant reads the slot limit")
	assert_gt(equip, guard, "and reads it BEFORE it asks PassiveSystem to equip, which warns on a full bar")


## The quiet half had a cost: a job taught passives and nothing said they were waiting in the menu.
func test_a_full_bar_records_what_it_could_not_fit() -> void:
	var c := _member(5)
	var ids := _fresh_ids(c, 3)
	JobSystem._grant_roster_passives(c, {"passive_abilities": ids})
	assert_eq(JobSystem.last_grant_left_unequipped.size(), 3, "all three were learned and none fitted")
	for id in ids:
		assert_true(id in JobSystem.last_grant_left_unequipped, "%s is named as waiting" % id)


func test_a_grant_that_fits_leaves_nothing_to_say() -> void:
	var full := _member(5)
	JobSystem._grant_roster_passives(full, {"passive_abilities": _fresh_ids(full, 2)})
	assert_eq(JobSystem.last_grant_left_unequipped.size(), 2, "SCOPE: the previous grant left two waiting")
	var c := _member(0)
	JobSystem._grant_roster_passives(c, {"passive_abilities": _fresh_ids(c, 2)})
	assert_eq(JobSystem.last_grant_left_unequipped.size(), 0, "a later grant that fits must not inherit the earlier count")


func test_the_notice_counts_and_names_where_to_go() -> void:
	assert_eq(JobMenu.unequipped_grant_notice(0), "", "nothing waiting, nothing said")
	var one: String = JobMenu.unequipped_grant_notice(1)
	var four: String = JobMenu.unequipped_grant_notice(4)
	assert_string_contains(one, "1 passive ", "one is singular")
	assert_string_contains(four, "4 passives", "several are counted")
	for text in [one, four]:
		assert_string_contains(text, "Abilities", "the notice names the menu that equips them")


func test_the_job_menu_shows_the_notice_after_a_job_change() -> void:
	var code: String = GdSource.code_of("res://src/ui/JobMenu.gd")
	var at := code.find("success = JobSystem.assign_job(character, job_id)")
	var end := code.find("\nfunc ", at + 1)
	assert_gt(at, -1, "the assign call this arm reads from")
	assert_gt(end, at, "bounded at the next function")
	var body := code.substr(at, end - at)
	var read := body.find("unequipped_grant_notice(JobSystem.last_grant_left_unequipped.size())")
	var swap := body.find("_adopt_job_profile(")
	var toast := body.find("Toast.show(self, waiting)")
	assert_gt(read, -1, "the menu reads what the grant could not fit")
	assert_gt(swap, read, "and reads it BEFORE the profile swap, which may run another grant")
	assert_gt(toast, body.find("_build_ui()", swap), "the toast goes up after the rebuild, or the rebuild would free it")
