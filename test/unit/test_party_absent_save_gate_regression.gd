extends GutTest

## The timed autosave fired with nothing loaded and wrote a 2.5KB shell, which then outranked
## real saves on recency (struktured's slot 98, 2026-08-06 .. 2026-08-22).
## 7ef5dae9 scoped itself to a WIPE — `_party_is_wiped` returns false on an empty party by
## design — so never-loaded was never gated. This pins the separate predicate AND pins that the
## shared one was NOT widened: doing that would block manual saving and tell the player
## "the whole party is down" about a party that never existed.

var _saved_party: Array[Dictionary] = []
var _had_party: bool = false


func before_each() -> void:
	_had_party = GameState != null and "player_party" in GameState
	if _had_party:
		_saved_party = []
		for e in GameState.player_party:
			_saved_party.append((e as Dictionary).duplicate(true))


func after_each() -> void:
	## Restore from after_each, not inline — an assert or crash mid-test must not leak a
	## mutated autoload into every later test file.
	if _had_party:
		var restored: Array[Dictionary] = []
		for e in _saved_party:
			restored.append(e as Dictionary)
		GameState.player_party = restored


## Array[Dictionary] is TYPED — assigning a bare Array fails AND aborts the caller, which made
## three of these tests pass vacuously on the first run. Build the typed array explicitly.
func _set_party(entries: Array) -> void:
	var typed: Array[Dictionary] = []
	for e in entries:
		typed.append(e as Dictionary)
	GameState.player_party = typed


func test_absent_predicate_fires_on_an_empty_party() -> void:
	if not _had_party:
		fail_test("GameState.player_party unavailable — this file cannot test what it claims")
		return
	_set_party([])
	assert_true(SaveSystem._party_is_absent(), "an empty party must read as ABSENT")


func test_absent_predicate_is_false_when_a_party_exists() -> void:
	# ARM+. Without this the predicate could return true unconditionally and every other
	# assertion here would still pass.
	if not _had_party:
		fail_test("GameState.player_party unavailable")
		return
	_set_party([{"name": "Fighter", "is_alive": true, "current_hp": 100}])
	assert_false(SaveSystem._party_is_absent(), "a populated party must NOT read as absent")


func test_the_wiped_predicate_was_not_widened() -> void:
	# The trap: _party_is_wiped gates manual save AND its block message. Making it true for an
	# empty party would refuse manual saves and lie about why.
	if not _had_party:
		fail_test("GameState.player_party unavailable")
		return
	_set_party([])
	assert_false(SaveSystem._party_is_wiped(),
		"_party_is_wiped must still return false for an ABSENT party — it is a shared predicate")


func test_wiped_still_detects_an_actual_wipe() -> void:
	# ARM+ for the sibling: proves the above false is scoped, not a broken predicate.
	if not _had_party:
		fail_test("GameState.player_party unavailable")
		return
	_set_party([{"name": "Fighter", "is_alive": false, "current_hp": 0}])
	assert_true(SaveSystem._party_is_wiped(), "a present-but-all-down party is still a wipe")


func test_the_block_reason_does_not_blame_a_wipe_for_an_absent_party() -> void:
	if not _had_party:
		fail_test("GameState.player_party unavailable")
		return
	_set_party([])
	var reason: String = SaveSystem._save_block_reason()
	assert_ne(reason, "Cannot save with the whole party down",
		"an absent party must not be reported as a wipe — that message is a lie about this state")
	assert_ne(reason, "", "an absent party must block saving with SOME reason")
