extends GutTest

## _resolve_job_for_character had a GameState arm gated on has_method("get_character_job_id") —
## a method declared NOWHERE in src/, so the guard was permanently false and the branch dead.
## That left CHARACTER_JOB_IDS, a STATIC 5-entry map, as the only answer for the starters. Jobs
## are changeable (JobSystem.job_changed), so a character who switched read as their old job in
## rule validation, _combatant_has_learned, and which preset templates they were offered.

const SRC := "res://src/autobattle/AutobattleSystem.gd"

func _src() -> String:
	var s := FileAccess.get_file_as_string(SRC)
	assert_gt(s.length(), 1000, "CONTROL: read AutobattleSystem")
	return s

func test_the_dead_guard_is_gone() -> void:
	assert_false(_src().contains("has_method(\"get_character_job_id\")"),
		"that method exists nowhere in src/, so the guard was permanently false")

func test_the_guarded_method_really_is_absent_everywhere() -> void:
	## The premise, measured rather than asserted — if someone adds the method later, this test
	## should be revisited, not silently satisfied by the old shape.
	var files := ["res://src/meta/GameState.gd", "res://src/autobattle/AutobattleSystem.gd"]
	var found := 0
	for f in files:
		if FileAccess.get_file_as_string(f).contains("func get_character_job_id"):
			found += 1
	assert_eq(found, 0, "get_character_job_id is still undeclared — the dead-guard premise holds")
	assert_true(FileAccess.get_file_as_string("res://src/meta/GameState.gd").contains("func "),
		"CONTROL: GameState is readable and does declare functions")

func test_the_live_party_is_consulted_before_the_static_map() -> void:
	## Precedence IS the bug. A live lookup placed AFTER the static map would still return the
	## stale job for all five named starters, which is every character the map covers.
	var s := _src()
	var i := s.find("func _resolve_job_for_character(")
	assert_gt(i, -1, "CONTROL: located the resolver")
	var j := s.find("\nfunc ", i + 10)
	var body := s.substr(i, j - i)
	var live := body.find("_live_job_id_for(")
	var static_map := body.find("CHARACTER_JOB_IDS.has(")
	assert_gt(live, -1, "the resolver must consult the live party")
	assert_gt(static_map, -1, "CONTROL: the static map is still the fallback, not deleted")
	assert_true(live < static_map,
		"the live job must be checked FIRST — after the map it is unreachable for every character the map names")

func test_the_live_lookup_reads_the_job_the_character_actually_has() -> void:
	var s := _src()
	var i := s.find("func _live_job_id_for(")
	assert_gt(i, -1, "the live lookup must exist")
	var body := s.substr(i, 700)
	assert_true(body.contains("player_party"), "it must read the live party")
	assert_true(body.contains("job_id"), "party entries are Combatant.to_dict(), which carries job_id")

## SUPERSEDED ON PURPOSE. This asserted that _combatant_has_learned reads combatant.job.get("id")
## — correct when written, and now wrong: the function delegates to Combatant.knows_ability, which
## resolves the job itself and additionally covers learned/purchased/secondary sources this file's
## fix could not. Deleting a stale pin rather than loosening it; the replacement lives in
## test_autobattle_upgrades_use_knows_ability.
func test_has_learned_delegates_to_the_canonical_predicate() -> void:
	var s := _src()
	var i := s.find("func _combatant_has_learned(")
	assert_gt(i, -1, "CONTROL: located the predicate")
	var j := s.find("\nfunc ", i + 10)
	var body := s.substr(i, j - i)
	assert_true(body.contains("combatant.knows_ability("),
		"it must delegate to the one predicate rather than resolve a job itself")

func test_the_static_map_still_covers_the_named_starters() -> void:
	## Guards the fallback: the fix must not have deleted the map, which is the only answer for a
	## character being validated while not in the party.
	var s := _src()
	assert_true(s.contains("\"mira\": \"cleric\""), "CONTROL: the starter map survives as a fallback")
