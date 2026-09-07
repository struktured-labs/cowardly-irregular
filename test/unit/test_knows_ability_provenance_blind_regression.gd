extends GutTest

## struktured 2026-09-06, two live bugs one cause: the magic shop sold the Mage IGNIS (already in
## his starting kit) because "already known" read only the snapshot's learned list; and "Bard
## can't use Riff right now" because can_use_ability accepted only kit ∪ learned and Riff lives
## in free_move. His ruling: "just have a general guard on if u have the ability or not at all,
## provenance irrelevant." Combatant.knows_ability is that guard; both consumers use it.


func _mage() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Probe"
	c.job = {
		"id": "probe_job",
		"abilities": ["fire"],
		"free_move": {"type": "ability", "ability_id": "riff"},
		"abilities_at_level": {"4": ["discord"]},
	}
	c.job_level = 1
	c.current_mp = 100
	return c


func test_kit_counts() -> void:
	var c := _mage()
	assert_true(c.knows_ability("fire"), "starting-kit spell is KNOWN — the Ignis re-purchase")
	c.free()


func test_free_move_counts() -> void:
	var c := _mage()
	assert_true(c.knows_ability("riff"), "the job's free move is KNOWN — the Riff refusal")
	c.free()


func test_level_unlock_counts_only_once_reached() -> void:
	var c := _mage()
	assert_false(c.knows_ability("discord"), "a level-4 unlock is NOT known at level 1")
	c.job_level = 4
	assert_true(c.knows_ability("discord"), "and IS known once the threshold is reached")
	c.free()


func test_learned_and_purchased_count() -> void:
	var c := _mage()
	assert_false(c.knows_ability("cure"), "CONTROL: unrelated spell unknown")
	c.learn_ability("cure")
	assert_true(c.knows_ability("cure"), "learned counts")
	c.purchased_abilities.append("thunder")
	assert_true(c.knows_ability("thunder"), "purchased counts even before learn_ability mirrors it")
	assert_false(c.knows_ability(""), "empty id is never known")
	c.free()


func test_can_use_ability_routes_through_the_predicate() -> void:
	var c := _mage()
	assert_true(JobSystem.can_use_ability(c, "riff"), "Riff (free move, 0 MP) must be usable — pre-fix: 'can't use right now'")
	assert_true(JobSystem.can_use_ability(c, "fire"), "CONTROL: kit spell usable")
	assert_false(JobSystem.can_use_ability(c, "cure"), "CONTROL: an unknown spell stays refused")
	var src := FileAccess.get_file_as_string("res://src/jobs/JobSystem.gd")
	var i: int = src.find("func can_use_ability(")
	assert_true(src.substr(i, 900).contains("combatant.knows_ability(ability_id)"),
		"can_use_ability must delegate to the ONE predicate, not re-derive kit/learned")
	c.free()


func test_shop_uses_the_predicate_in_both_places() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")
	assert_true(src.contains("func _member_knows("), "the shop needs one helper for 'already has it'")
	var count := 0
	var idx := src.find("_member_knows(")
	while idx != -1:
		count += 1
		idx = src.find("_member_knows(", idx + 1)
	assert_gte(count, 3, "helper defined + used in the character list AND the confirm guard (found %d refs)" % count)
	var h: int = src.find("func _member_knows(")
	assert_true(src.substr(h, 600).contains("knows_ability"), "the helper must consult the LIVE combatant's knows_ability")
