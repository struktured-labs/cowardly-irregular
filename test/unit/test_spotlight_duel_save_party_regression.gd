extends GutTest

## Playtest 2026-07-15: "the only member in my party after taking down
## lockward is rogue... after that it crashed after mage cutscene."
##
## Chain: a save fired while a spotlight duel was active → `party` was
## the transient [duelist] → GameState.player_party serialized 1 member →
## autosave slot poisoned → Continue loaded a 1-member roster → the Mage
## duel found no Mage. Log proof: "Game loaded from slot 98" listed only
## Rogue's equipment; "[PREWARM] 3 monsters, 1 party members" after the
## duel victory.
##
## Fix: _sync_party_to_game_state syncs from _spotlight_saved_party (the
## full roster) whenever _spotlight_duel_active — the duelist is the same
## Combatant instance in both arrays so live state still serializes.

const GAME_LOOP := "res://src/GameLoop.gd"


func test_sync_prefers_saved_roster_during_duel_source_pin() -> void:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	var i := src.find("func _sync_party_to_game_state")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1500)
	assert_true("_spotlight_duel_active" in body,
		"sync must consult _spotlight_duel_active — the transient [duelist] party must never serialize as the roster")
	assert_true("_spotlight_saved_party" in body,
		"sync must read the saved full roster during a duel")
	assert_true("roster = _spotlight_saved_party" in body,
		"the duel branch must swap the iteration source to the saved roster")


func test_sync_behavioral_full_roster_during_duel() -> void:
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	# Build a fake 3-member party of real Combatants (typed — gl.party is Array[Combatant]).
	var members: Array[Combatant] = []
	for n in ["A", "B", "C"]:
		var c := Combatant.new()
		c.combatant_name = n
		members.append(c)
	gl.party = members.duplicate()
	# Simulate duel: bench all but member B.
	gl._spotlight_saved_party = gl.party.duplicate()
	var solo: Array[Combatant] = [members[1]]
	gl.party = solo
	gl._spotlight_duel_active = true

	gl._sync_party_to_game_state()
	assert_eq(GameState.player_party.size(), 3,
		"during a duel, the SAVED roster (3) must serialize — not the transient [duelist] (1)")

	# After the duel ends, live party is the source again.
	gl.party = gl._spotlight_saved_party.duplicate()
	gl._spotlight_saved_party.clear()
	gl._spotlight_duel_active = false
	gl._sync_party_to_game_state()
	assert_eq(GameState.player_party.size(), 3,
		"post-duel sync uses the live (restored) party")
