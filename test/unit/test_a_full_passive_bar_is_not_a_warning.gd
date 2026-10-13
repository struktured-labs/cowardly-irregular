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


func _labels_under(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append(c)
		_labels_under(c, out)


func _job_that_teaches(c: Combatant, menu: JobMenu) -> int:
	var jobs: Array = menu._get_available_jobs()
	for i in range(jobs.size()):
		var roster: Variant = JobSystem.jobs.get(str(jobs[i]), {}).get("passive_abilities", [])
		if not (roster is Array):
			continue
		for pid in roster:
			if not (str(pid) in c.learned_passives):
				return i
	return -1


## Driven, not read: the menu is built, a job is assigned onto a full bar, and the toast is looked for in the tree.
func test_the_job_menu_puts_the_notice_on_screen_and_a_rebuild_does_not_eat_it() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var c := _member(5)
	JobSystem.assign_job(c, "fighter")
	while c.equipped_passives.size() < c.max_passive_slots:
		for id in PassiveSystem.passives.keys():
			if not (str(id) in c.equipped_passives):
				c.learned_passives.append(str(id))
				c.equipped_passives.append(str(id))
				break
	var menu := JobMenu.new()
	host.add_child(menu)
	menu.setup(c)
	await get_tree().process_frame
	await get_tree().process_frame
	menu.selected_slot = 0
	var idx := _job_that_teaches(c, menu)
	assert_gt(idx, -1, "SCOPE: some available job teaches a passive this member has not learned")
	if idx < 0:
		return
	menu.selected_job_index = idx
	menu._assign_selected_job()
	assert_gt(JobSystem.last_grant_left_unequipped.size(), 0, "SCOPE: the grant left something waiting")
	menu._build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	var labels: Array = []
	_labels_under(host, labels)
	var seen := false
	for l in labels:
		if is_instance_valid(l) and not l.is_queued_for_deletion() and str(l.text).begins_with("Learned ") and str(l.text).contains("Abilities"):
			seen = true
	assert_true(seen, "the notice is a live label on screen after the job change AND after the menu rebuilds")
