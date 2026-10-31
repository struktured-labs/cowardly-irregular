extends GutTest

## struktured, 2026-10-30, after the Mage spotlight duel: the Prismatic Construct conceded with an
## LLM line calling the party "too lazy to even bother with actual strategy". He played it by hand —
## both SHOWCASE gates logged manual=true — with Autobattle set to Aggressive beforehand.
##
## The fight-derived fact was correct and was NOT sent: _track_manual_player_turn clears
## _full_autobattle. The cause was the victory situation text in _build_gloat_prompt, which said
## "Meta-aware: it may remark on the player automating their way to victory" to EVERY boss defeat.
## The model took the invitation. The same prompt carried no persona, so an examiner whose authored
## concession ends "Pass." came back as "Foolish heroes".
##
## THE TOGGLE IS THE DECOY IN BOTH DIRECTIONS: the manual arm turns autobattle ON, the control turns
## it OFF. Either arm passing by reading the setting rather than the turns would go red.

const PERSONA_ID := "mage_prismatic_construct"
const FACT := "never lifted a finger"
const INVITATION := "needle them for it"
const MANUAL_ACK := "chose every action in this fight by hand"

var _saved: Dictionary = {}
var _snapshot_ok: bool = false


func before_each() -> void:
	_snapshot_ok = false
	_saved = {
		"full": BattleManager._full_autobattle,
		"auto_turns": BattleManager._autobattle_player_turns,
		"manual_turns": BattleManager._manual_player_turns,
		"toggle": BattleManager.is_autobattle_enabled,
	}
	_snapshot_ok = true


func after_each() -> void:
	if not _snapshot_ok:
		return
	BattleManager._full_autobattle = bool(_saved["full"])
	BattleManager._autobattle_player_turns = int(_saved["auto_turns"])
	BattleManager._manual_player_turns = int(_saved["manual_turns"])
	BattleManager.is_autobattle_enabled = bool(_saved["toggle"])


## The counters as a fresh battle leaves them, which is what end_battle reads.
func _fresh_battle(toggle_on: bool) -> void:
	BattleManager._full_autobattle = true
	BattleManager._autobattle_player_turns = 0
	BattleManager._manual_player_turns = 0
	BattleManager.is_autobattle_enabled = toggle_on


func _prompt(victory: bool, sample: String = "") -> String:
	return BattleManager._build_gloat_prompt(PERSONA_ID, "The Prismatic Construct", victory, sample)


func test_preconditions_this_file_depends_on() -> void:
	## FLOOR: an autogrind-automated test process would make every arm below answer the wrong question.
	var grind: Node = get_node_or_null("/root/AutogrindSystem")
	if grind != null and grind.has_method("is_battle_automated"):
		assert_false(grind.is_battle_automated(), "AutogrindSystem reports an automated battle, so no arm here can test a manual one")
	var dlg: Node = get_node_or_null("/root/BossDialogue")
	assert_not_null(dlg, "BossDialogue autoload must exist")
	assert_gt(str(dlg.get_persona(PERSONA_ID)).length(), 40,
		"the persona under test must be authored, or the persona arm passes on an empty block")


func test_a_hand_played_win_with_autobattle_on_gets_no_automation_snark() -> void:
	## THE DEFECT, in his exact state: toggle ON, every turn chosen by hand.
	for victory in [true, false]:
		_fresh_battle(true)
		BattleManager._track_manual_player_turn()
		BattleManager._track_manual_player_turn()
		var p: String = _prompt(victory)
		assert_false(p.contains(FACT), "victory=%s: a hand-played fight must not carry the automation fact" % victory)
		assert_false(p.contains(INVITATION),
			"victory=%s: a hand-played fight must not invite automation snark — that invitation is what produced 'too lazy to even bother'" % victory)
		assert_false(p.to_lower().contains("automating their way"),
			"victory=%s: the old unconditional invitation is back" % victory)
		assert_true(p.contains(MANUAL_ACK),
			"victory=%s: a manual fight must be acknowledged as one, so the model has a fact to stand on instead of a guess" % victory)


func test_control_an_automated_win_carries_the_fact_and_the_invitation() -> void:
	## CONTROL, toggle OFF so it cannot pass by reading the setting. Without this, the arm above
	## passes on a builder that never mentions automation at all.
	for victory in [true, false]:
		_fresh_battle(false)
		BattleManager._autobattle_player_turns = 3
		var p: String = _prompt(victory)
		assert_true(p.contains(FACT), "victory=%s: an autobattled fight must carry the fact" % victory)
		assert_true(p.contains(INVITATION), "victory=%s: and the invitation, so the joke he liked still lands when it is earned" % victory)
		assert_false(p.contains(MANUAL_ACK), "victory=%s: and must not claim the fight was played by hand" % victory)


func test_one_manual_turn_is_enough_to_withhold_the_snark() -> void:
	## Mixed fight: autobattle acted, then the player took over once. A person chose, so no "lazy".
	_fresh_battle(true)
	BattleManager._autobattle_player_turns = 4
	BattleManager._track_manual_player_turn()
	var p: String = _prompt(true)
	assert_false(p.contains(INVITATION), "one hand-chosen turn means the player decided; the boss must not say otherwise")


func test_the_gloat_speaks_in_the_boss_persona() -> void:
	## PERSONA DRIFT: no persona reached this prompt, so the examiner came back as "Foolish heroes".
	_fresh_battle(false)
	var persona: String = str(get_node("/root/BossDialogue").get_persona(PERSONA_ID)).strip_edges()
	var sample := "You read every face and matched it. Pass."
	var p: String = _prompt(true, sample)
	assert_true(p.contains(persona), "the boss's authored persona must reach the gloat prompt")
	assert_true(p.contains(sample), "the boss's own line must reach the prompt as a voice sample")


func test_a_boss_with_no_section_gets_no_empty_persona_block() -> void:
	## Graceful: an unknown persona adds nothing, rather than a header over an empty line.
	_fresh_battle(false)
	var p: String = BattleManager._build_gloat_prompt("no_such_boss_persona_x", "Nobody", true, "")
	assert_false(p.contains("Persona —"), "an unknown persona must not print an empty persona block")
	assert_false(p.contains("match its voice"), "an empty sample must not print an empty sample block")
