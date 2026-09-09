extends GutTest

## BEHAVIOURAL, deliberately. I replaced a dead has_method guard in _resolve_job_for_character
## with a live GameState.player_party lookup, and pinned it with SOURCE-TEXT assertions — which
## prove the new code EXISTS, not that it RESOLVES. cowir-main 2026-09-09, on a Mode-7 detector
## whose replacement carried the same defect for ten weeks: "a fix that swaps one dead lookup for
## another is indistinguishable from a fix." These call it and check the value.

var _saved_party: Array = []
var _saved_persist: bool = false

func before_each() -> void:
	## Autobattle tests MUST disable persistence — fixture characters leaked into struktured's real
	## profiles.json twice on 2026-09-06. This test never calls a setter, but the guard is cheap
	## and the ratchet that enforces it does not read intent.
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_party = GameState.player_party.duplicate(true)

func after_each() -> void:
	GameState.player_party = _saved_party.duplicate(true)
	AutobattleSystem._test_disable_persistence = _saved_persist

## Shaped exactly like Combatant.to_dict(): "name" plus "job_id".
func _party_entry(display_name: String, job_id: String) -> Dictionary:
	return {"name": display_name, "job_id": job_id}

func test_the_live_lookup_returns_the_party_job() -> void:
	GameState.player_party = [_party_entry("Mira", "guardian")]
	assert_eq(AutobattleSystem._resolve_job_for_character("mira"), "guardian",
		"the live party job must win — this is the call that proves the replacement is not dead")

func test_it_beats_the_static_starter_map() -> void:
	## CHARACTER_JOB_IDS says mira->cleric. If precedence regressed, this returns "cleric" and the
	## whole fix is inert for every character the map names, which is all five starters.
	GameState.player_party = [_party_entry("Mira", "guardian")]
	assert_ne(AutobattleSystem._resolve_job_for_character("mira"), "cleric",
		"a job change must not still read as the starting job")

func test_the_static_map_still_answers_when_the_party_is_empty() -> void:
	## The fallback has to survive: a character can be validated while not in the party.
	GameState.player_party = []
	assert_eq(AutobattleSystem._resolve_job_for_character("mira"), "cleric",
		"with no live entry the starter map is still the answer")

func test_an_entry_without_a_job_id_falls_through() -> void:
	## Combatant.to_dict() only writes job_id `if job and job is Dictionary`, so an entry can
	## legitimately lack it. That must not resolve to "" and poison the caller.
	GameState.player_party = [{"name": "Mira"}]
	assert_eq(AutobattleSystem._resolve_job_for_character("mira"), "cleric",
		"a party entry with no job_id must fall through, not return empty")

func test_an_unknown_character_still_returns_its_own_id() -> void:
	GameState.player_party = []
	assert_eq(AutobattleSystem._resolve_job_for_character("bard"), "bard",
		"CONTROL: the job-named fallback survives — and proves the resolver ran rather than erroring")

func test_the_name_derivation_matches_get_character_id() -> void:
	## The join the lookup depends on: party entries store a DISPLAY name, callers pass an id.
	## If these two derivations ever diverge the lookup silently never matches — dead again.
	GameState.player_party = [_party_entry("The Bard", "bard")]
	assert_eq(AutobattleSystem._resolve_job_for_character("the_bard"), "bard",
		"spaces lower-cased to underscores, same rule as _get_character_id")
