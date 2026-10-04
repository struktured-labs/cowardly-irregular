extends GutTest
## tools/store_shot_storm.gd renders the store's lead battle image. It waits for the Mage to be
## the active selector before queueing thundaga, and it used to recognise the Mage by searching
## str(combatant.job) for the substring "mage". The Fighter's job Dictionary contains "damage",
## so the wait ended at 0.0s on the Fighter, who refused the cast ("Fighter cannot use Fulmen
## Maximum"), and the frame caught the Mage's own tier-1 Fulmen. Measured at v3.33.549 and .555.
## These arms use the REAL job data, because the real data is what defeated the substring test.

const StormShot := preload("res://tools/store_shot_storm.gd")


func _job(id: String) -> Dictionary:
	var f := FileAccess.open("res://data/jobs.json", FileAccess.READ)
	assert_not_null(f, "data/jobs.json must be readable")
	var parsed = JSON.parse_string(f.get_as_text())
	var jobs = parsed.get("jobs", parsed) if parsed is Dictionary else {}
	assert_true(jobs is Dictionary and jobs.has(id), "jobs.json has no '%s' entry" % id)
	return jobs[id]


func _combatant(job) -> Combatant:
	var c := Combatant.new()
	c.job = job
	autofree(c)
	return c


func test_the_fighter_is_not_the_mage_though_his_job_says_damage() -> void:
	var fighter := _job("fighter")
	# The precondition that made the old test lie, pinned so the arm cannot pass vacuously.
	assert_true(JSON.stringify(fighter).to_lower().find("mage") >= 0,
		"the Fighter's job data no longer contains the substring 'mage'; this arm needs a new decoy")
	assert_false(StormShot.is_mage(_combatant(fighter)), "the Fighter matched as the Mage")


func test_the_mage_is_the_mage() -> void:
	assert_true(StormShot.is_mage(_combatant(_job("mage"))), "the real Mage job did not match")


func test_no_combatant_and_no_job_are_not_the_mage() -> void:
	assert_false(StormShot.is_mage(null), "null matched as the Mage")
	assert_false(StormShot.is_mage(_combatant(null)), "a combatant with no job matched as the Mage")
