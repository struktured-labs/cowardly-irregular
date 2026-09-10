extends GutTest

## A player can author a five-action rule, share it, re-import it, and have it fire. All four.
##
## Full Bank added a fifth action, and "the menu can do something scripts cannot" is the failure I
## was most worried about — autobattle is a design pillar, and a mechanic the grid cannot express is
## a mechanic the game's own thesis excludes. But the fifth slot crosses FOUR independent surfaces,
## each of which historically carried its own cap:
##
##   1. the grid editor      MAX_ACTIONS, raised 4 -> 5
##   2. rule validation      AutobattleSystem.validate_rule
##   3. the share codec      ScriptShareManager, COWIR1 export/import
##   4. execution            BattleManager._apply_full_bank_rule, and headless
##
## Any one of them silently trimming to four makes the other three pointless, and the symptom is a
## rule that just does one fewer thing than the player wrote — which reads as the AI being dumb, not
## as a cap. Measured across the chain rather than at any one link.

const Share = preload("res://src/autobattle/ScriptShareManager.gd")
const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const GridEditor = preload("res://src/ui/autobattle/AutobattleGridEditor.gd")

func before_each() -> void:
	## Autobattle tests MUST disable persistence — fixture characters leaked into struktured's real
	## profiles.json twice on 2026-09-06.
	AutobattleSystem._test_disable_persistence = true

func _five_action_rule() -> Dictionary:
	var actions: Array = []
	for i in 5:
		actions.append({"type": "attack"})
	return {"conditions": [{"type": "always"}], "actions": actions}

func test_the_grid_editor_offers_a_fifth_slot() -> void:
	assert_gte(GridEditor.MAX_ACTIONS, BattleManagerScript.FULL_BANK_ACTIONS,
		"the editor must be able to author what a full bank can spend — %d vs %d" % [GridEditor.MAX_ACTIONS, BattleManagerScript.FULL_BANK_ACTIONS])

func test_rule_validation_accepts_five_actions() -> void:
	var errors: Array = AutobattleSystem.validate_rule(_five_action_rule())
	assert_eq(errors.size(), 0, "a five-action rule must validate: " + str(errors))

func test_validation_is_not_simply_accepting_everything() -> void:
	## CONTROL. If validate_rule returned [] for any input, the test above would pass against a
	## validator that had stopped working — which is the shape that lets a broken gate read as a
	## permissive one.
	var junk: Dictionary = {"conditions": "not-an-array", "actions": [{"type": "attack"}]}
	assert_gt(AutobattleSystem.validate_rule(junk).size(), 0,
		"the validator must still reject a malformed rule, or the acceptance above proves nothing")

func test_the_share_codec_round_trips_all_five() -> void:
	## The pillar: scripts travel as COWIR1 codes between players. A codec that trims the fifth
	## action would degrade a shared build silently on the receiving side only.
	var script: Dictionary = {"rules": [_five_action_rule()]}
	var errors: Array = Share.validate_imported_script(script)
	assert_eq(errors.size(), 0, "a five-action script must import cleanly: " + str(errors))
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(script))
	assert_not_null(round_tripped, "CONTROL: the script survives a JSON round trip at all")
	var rules: Array = (round_tripped as Dictionary)["rules"]
	assert_eq(((rules[0] as Dictionary)["actions"] as Array).size(), 5,
		"and still carries five actions on the far side")

func test_execution_honours_the_fifth_only_at_a_full_bank() -> void:
	## The far end of the chain, and the one that must NOT be permissive: five authored actions
	## become five at +4 and four below it.
	var bm = BattleManagerScript.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mira"
	c.max_hp = 500; c.current_hp = 500
	var authored: Array = (_five_action_rule()["actions"] as Array)
	c.current_ap = BattleManagerScript.FULL_BANK_AP
	assert_eq((bm._apply_full_bank_rule(c, authored)["actions"] as Array).size(), 5,
		"at a full bank the authored fifth action fires")
	c.current_ap = BattleManagerScript.FULL_BANK_AP - 1
	assert_eq((bm._apply_full_bank_rule(c, authored)["actions"] as Array).size(), 4,
		"one short of a full bank it is trimmed, not refused — a trimmed rule still acts")

func test_headless_applies_the_same_bound() -> void:
	## Autogrind resolves fights the live game is supposed to be able to produce. A grid rule that
	## fires five live and four headless would make a grind an unfaithful simulation of the build.
	var src := FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_gt(src.length(), 1000, "CONTROL: read the resolver")
	assert_string_contains(src, "raw.size() > 4 and combatant.current_ap < 4",
		"headless must trim to four below a full bank, matching the live rule")
	assert_string_contains(src, "var ap_cost = raw.size() - 1",
		"CONTROL: and still charge size-1, which makes the fifth free there by construction")
