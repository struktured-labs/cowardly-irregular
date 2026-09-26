extends GutTest

## A primary job change copies the new job's max HP into current HP.
## heal() already does nothing while an ally is down, and revive() refuses
## permakilled, so that fill leaves a corpse with a full bar. is_alive and
## the marker stay. from_dict then decides standing from HP > 0, so a save
## of that corpse comes back on its feet. Continue writes the saved bool
## back afterwards, which puts them down again and leaves the filled bar.
## An ordinary KO is the same fill: the inn raises those, a job change must
## not. A living ally still takes the raw-cap fill. A secondary change never
## wrote current HP.

const GAME_LOOP := "res://src/GameLoop.gd"

var _gl: Node = null
var _saved_party: Array = []
var _saved_pool: Dictionary = {}
var _saved_map: String = ""
var _saved_pending: Vector2 = Vector2.INF


func before_each() -> void:
	assert_not_null(JobSystem, "JobSystem autoload required")
	_saved_party = GameState.player_party.duplicate(true)
	_saved_pool = GameState.equipment_pool.duplicate(true)
	_saved_map = str(MapSystem.current_map_id) if MapSystem != null else ""
	_saved_pending = SaveSystem.pending_player_position


func after_each() -> void:
	if _gl != null and is_instance_valid(_gl):
		_gl.free()
		_gl = null
	GameState.player_party.clear()
	for entry in _saved_party:
		if entry is Dictionary:
			GameState.player_party.append(entry)
	GameState.equipment_pool = _saved_pool.duplicate(true)
	if MapSystem != null and _saved_map != "":
		MapSystem.current_map_id = _saved_map
	SaveSystem.pending_player_position = _saved_pending


func test_a_primary_job_change_keeps_a_permakilled_ally_at_zero_hp() -> void:
	var dead := _ally("fighter")
	var live := _ally("fighter")
	_permakill(dead)
	dead.current_hp = dead.max_hp
	dead.job_level = 6
	live.job_level = 6
	live.current_hp = 3
	var raw_hp := int(_raw("mage")["max_hp"])
	assert_gt(raw_hp, 3)
	assert_true(JobSystem.assign_job(dead, "mage"), "the job change itself must still succeed")
	assert_true(JobSystem.assign_job(live, "mage"))
	assert_eq(str(dead.job.get("id", "")), "mage", "the primary job must change")
	assert_false(dead.is_alive, "permakilled stays down")
	assert_eq(dead.current_hp, 0, "the bar stays empty — a job change is not a raise")
	assert_true(dead.has_status("permakilled"), "the permadeath marker stays")
	assert_eq(dead.max_hp, live.max_hp, "the new job's max HP is still applied")
	assert_eq(dead.attack, live.attack, "the rest of the job's stats are still copied")
	assert_eq(dead.magic, live.magic)
	assert_true(live.is_alive)
	assert_eq(live.current_hp, raw_hp, "a living ally still takes the raw-cap fill")
	dead.recalculate_stats()
	live.recalculate_stats()
	assert_eq(dead.current_hp, 0, "the menu's recalc clamps; it must not refill a corpse")
	assert_eq(dead.max_hp, live.max_hp, "recalc still matches a living ally")
	assert_gt(dead.max_hp, raw_hp, "level scale still recalculates max HP")
	assert_eq(live.current_hp, raw_hp, "recalc must not top the living fill up to the scaled max")
	assert_false(dead.is_alive)
	assert_true(dead.has_status("permakilled"))


func test_an_ordinary_ko_stays_at_zero_hp_on_a_primary_job_change() -> void:
	var dead := _ally("fighter")
	var live := _ally("fighter")
	dead.die()
	assert_false(dead.is_alive)
	assert_eq(dead.current_hp, 0)
	assert_false(dead.has_status("permakilled"))
	dead.job_level = 6
	live.job_level = 6
	var raw_hp := int(_raw("cleric")["max_hp"])
	assert_true(JobSystem.assign_job(dead, "cleric"))
	assert_true(JobSystem.assign_job(live, "cleric"))
	assert_false(dead.is_alive, "an ordinary KO is not raised by a job change")
	assert_eq(dead.current_hp, 0, "heal() does nothing while they are down, so the bar stays empty")
	assert_false(dead.has_status("permakilled"))
	assert_eq(dead.max_hp, live.max_hp, "their new max is still the cleric line")
	assert_eq(dead.attack, live.attack)
	assert_eq(live.current_hp, raw_hp)
	assert_true(live.is_alive)
	dead.recalculate_stats()
	live.recalculate_stats()
	assert_eq(dead.current_hp, 0, "recalc must not refill a KO")
	assert_eq(dead.max_hp, live.max_hp, "level scale still runs for the KO")
	assert_gt(dead.max_hp, raw_hp)
	assert_false(dead.is_alive)


func test_a_living_ally_still_refills_to_the_raw_job_cap() -> void:
	var c := _ally("fighter")
	c.job_level = 6
	c.current_hp = 3
	c.recalculate_stats()
	assert_true(c.is_alive)
	assert_lt(c.current_hp, c.max_hp)
	var raw_hp := int(_raw("mage")["max_hp"])
	assert_true(JobSystem.assign_job(c, "mage"))
	assert_true(c.is_alive)
	assert_eq(c.current_hp, raw_hp,
		"a living ally still takes today's raw-cap fill, not the scaled max")
	c.recalculate_stats()
	assert_eq(c.current_hp, raw_hp,
		"recalc clamps and must not top the fill up to the scaled max")
	assert_gt(c.max_hp, c.current_hp)
	assert_true(c.is_alive)


func test_a_secondary_job_change_does_not_fill_a_permakilled_ally() -> void:
	var c := _ally("fighter")
	_permakill(c)
	var max_before: int = c.max_hp
	assert_true(JobSystem.assign_secondary_job(c, "mage"))
	assert_eq(c.secondary_job_id, "mage")
	assert_false(c.is_alive)
	assert_eq(c.current_hp, 0, "a secondary change never wrote current HP")
	assert_true(c.has_status("permakilled"))
	assert_ne(c.max_hp, max_before, "the lent stats still recalculate")


func test_from_dict_keeps_a_permakilled_corpse_down_when_the_bar_was_full() -> void:
	var c := Combatant.new()
	add_child_autofree(c)
	c.from_dict({
		"name": "Bard",
		"max_hp": 100,
		"current_hp": 100,
		"is_alive": false,
		"status_effects": ["permakilled"],
	})
	assert_true(c.has_status("permakilled"), "the marker must load")
	assert_false(c.is_alive, "HP > 0 must not stand a permakilled ally up")
	assert_eq(c.current_hp, 0, "the loaded bar is empty")


func test_from_dict_still_trusts_positive_hp_when_the_ally_is_not_permakilled() -> void:
	var c := Combatant.new()
	add_child_autofree(c)
	c.from_dict({
		"max_hp": 100,
		"current_hp": 40,
		"is_alive": false,
	})
	assert_true(c.is_alive, "without the marker, a positive bar still means standing")
	assert_eq(c.current_hp, 40)


func test_a_save_after_the_job_change_does_not_revive_on_continue() -> void:
	var c := _ally("fighter")
	c.combatant_name = "Bard"
	_permakill(c)
	assert_true(JobSystem.assign_job(c, "mage"))
	var data: Dictionary = c.to_dict()
	assert_true(data.has("status_effects"))
	assert_true("permakilled" in data["status_effects"])
	assert_eq(int(data["current_hp"]), 0, "the save must record an empty bar")
	assert_false(bool(data["is_alive"]))

	var direct := Combatant.new()
	add_child_autofree(direct)
	direct.from_dict(data)
	assert_false(direct.is_alive, "from_dict must not stand them up off the saved bar")
	assert_eq(direct.current_hp, 0)
	assert_true(direct.has_status("permakilled"))

	var loaded := _continue_one(data)
	assert_eq(str(loaded.job.get("id", "")), "mage", "Continue still rebuilds the job")
	assert_false(loaded.is_alive, "Continue must not stand a permakilled ally up")
	assert_eq(loaded.current_hp, 0, "Continue must not put the filled bar back")
	assert_true(loaded.has_status("permakilled"))
	assert_gt(loaded.max_hp, 0, "stats still come back")


func test_continue_of_an_already_poisoned_save_keeps_the_corpse_down() -> void:
	# A save written before the job-change fix: full bar, is_alive false, marker set.
	var corpse := {
		"name": "Mira",
		"job_id": "mage",
		"max_hp": 100,
		"current_hp": 100,
		"current_mp": 10,
		"is_alive": false,
		"status_effects": ["permakilled"],
		"job_level": 4,
		"equipped_weapon": "",
		"equipped_armor": "",
		"equipped_accessory": "",
	}
	var living := {
		"name": "Fighter",
		"job_id": "fighter",
		"max_hp": 200,
		"current_hp": 40,
		"current_mp": 5,
		"is_alive": true,
		"status_effects": [],
		"job_level": 4,
		"equipped_weapon": "",
		"equipped_armor": "",
		"equipped_accessory": "",
	}
	_stage([corpse, living])
	_gl = load(GAME_LOOP).new()
	assert_true(_gl._restore_party_from_save_data(), "restore must rebuild the saved party")
	assert_eq(_gl.party.size(), 2)

	var down: Combatant = _gl.party[0]
	var up: Combatant = _gl.party[1]
	assert_eq(down.combatant_name, "Mira")
	assert_true(down.has_status("permakilled"))
	assert_false(down.is_alive, "a poisoned save must not stand the corpse up")
	assert_eq(down.current_hp, 0, "the saved full bar must not come back under the KO")
	assert_eq(str(down.job.get("id", "")), "mage")
	assert_gt(down.max_hp, 0)
	assert_true(up.is_alive, "a living ally in the same save still stands")
	assert_eq(up.current_hp, 40, "their saved HP is restored, not zeroed with the corpse")
	assert_false(up.has_status("permakilled"))


func _ally(job_id: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Ally"
	assert_true(JobSystem.assign_job(c, job_id), "setup assign %s failed" % job_id)
	c.recalculate_stats()
	return c


func _permakill(c: Combatant) -> void:
	c.die()
	c.add_status("permakilled", -1)
	assert_false(c.is_alive, "setup: die() leaves them down")
	assert_eq(c.current_hp, 0, "setup: die() empties the bar")
	assert_true(c.has_status("permakilled"), "setup: the marker is on")


func _raw(job_id: String) -> Dictionary:
	var mods: Variant = JobSystem.get_job(job_id).get("stat_modifiers", {})
	assert_true(mods is Dictionary and not (mods as Dictionary).is_empty(),
		"%s must publish stat_modifiers" % job_id)
	return mods


func _continue_one(data: Dictionary) -> Combatant:
	_stage([data])
	_gl = load(GAME_LOOP).new()
	assert_true(_gl._restore_party_from_save_data(), "restore must rebuild the saved party")
	assert_eq(_gl.party.size(), 1)
	return _gl.party[0]


func _stage(entries: Array) -> void:
	GameState.player_party.clear()
	for entry in entries:
		GameState.player_party.append(entry)
	GameState.equipment_pool = {"weapons": [], "armors": [], "accessories": []}
