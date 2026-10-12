extends GutTest
## The three shipped autogrind rules targeted "hero" and "mira" — characters in NO party. A party id is
## derived from the member's NAME (`_party_character_ids`: combatant_name.to_lower()), so a SHIPPED
## default can never name one, and renaming the placeholders could not have fixed it.
## Two of the three rules were therefore inert: "switch everyone to defensive profiles" at HP<30 and
## "use standard profiles" always. Only the stop-at-2-alive rule did anything. An earlier fix guarded
## the SYMPTOM (an unknown id is skipped and logged instead of saving a phantom profile) and left the
## rules reaching nobody. "*" now means every current party member.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _ag: Dictionary
var _prof: Dictionary
var _party: Array = []


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	_prof = ABProfiles.snapshot(AutobattleSystem)
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	## grind_party is Array[Combatant]; assigning a plain Array raises and ABORTS before_each,
	## which left every arm measuring an empty party rather than failing honestly.
	var typed: Array[Combatant] = []
	for n in ["Rook", "Vesper"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": n, "max_hp": 100, "max_mp": 10})
		typed.append(c)
	_party = typed
	## _party_character_ids reads _party_bag(null), which reads grind_party — not a GameState field.
	AutogrindSystem.grind_party = typed


func after_each() -> void:
	AutogrindState.restore(_ag)
	ABProfiles.restore(AutobattleSystem, _prof)


func _ids() -> Array:
	return AutogrindSystem._party_character_ids()


func _apply(actions: Array) -> void:
	AutogrindSystem.apply_autogrind_actions(actions)


func _sentinel() -> String:
	return str(AutogrindSystem.ALL_PARTY) if "ALL_PARTY" in AutogrindSystem else "<no sentinel>"


func test_a_rule_can_target_every_party_member() -> void:
	assert_eq(_sentinel(), "*", "FLOOR: the all-party sentinel must exist")
	var ids: Array = _ids()
	assert_gt(ids.size(), 1, "FLOOR: the fixture party must have reached _party_character_ids")
	_apply([{"type": "switch_profile", "character_id": _sentinel(), "profile_index": 1}])
	for pid in ids:
		assert_eq(AutobattleSystem.get_active_profile_index(str(pid)), 1,
			"%s must have been switched -- a shipped default cannot name them individually" % pid)


## The sentinel must not be a blanket that ignores the index it was given. Driven BOTH ways on
## purpose: asserting index 0 alone passes on an unfixed tree, because 0 is also what a SKIPPED
## switch leaves behind -- the arm would have been green for the wrong reason.
func test_it_switches_to_the_profile_the_rule_named() -> void:
	var ids: Array = _ids()
	_apply([{"type": "switch_profile", "character_id": _sentinel(), "profile_index": 1}])
	for pid in ids:
		assert_eq(AutobattleSystem.get_active_profile_index(str(pid)), 1, "%s must follow the rule to profile 1" % pid)
	_apply([{"type": "switch_profile", "character_id": _sentinel(), "profile_index": 0}])
	for pid in ids:
		assert_eq(AutobattleSystem.get_active_profile_index(str(pid)), 0, "%s must follow the rule back to profile 0" % pid)


## CONTROL, and the behaviour the earlier symptom-fix added: a NAMED stranger is still refused.
func test_a_named_stranger_is_still_skipped_not_created() -> void:
	_apply([{"type": "switch_profile", "character_id": "hero", "profile_index": 1}])
	assert_false(_ids().has("hero"), "CONTROL: the stranger is genuinely not in the party")
	assert_eq(AutobattleSystem.get_active_profile_index("hero"), 0,
		"a rule naming nobody must not create and save a profile for them")


func test_a_named_real_member_still_works() -> void:
	var ids: Array = _ids()
	if ids.is_empty():
		assert_true(false, "FLOOR: need a party")
		return
	_apply([{"type": "switch_profile", "character_id": str(ids[0]), "profile_index": 1}])
	assert_eq(AutobattleSystem.get_active_profile_index(str(ids[0])), 1,
		"CONTROL: naming a real member by id must keep working")


## The defect was in the SHIPPED data, so pin the data as well as the mechanism.
func test_no_shipped_default_names_a_character_who_cannot_exist() -> void:
	var rulesets: Array = [AutogrindSystem._create_default_autogrind_rules(),
		AutogrindSystem._create_empty_autogrind_rules()]
	var targeted := 0
	for rules in rulesets:
		for rule in rules:
			for action in rule.get("actions", []):
				if str(action.get("type", "")) != "switch_profile":
					continue
				targeted += 1
				var cid: String = str(action.get("character_id", ""))
				assert_eq(cid, _sentinel(),
					"a shipped rule may only target the whole party; '%s' is a name no party can have" % cid)
	assert_gt(targeted, 0, "FLOOR: the shipped rulesets must contain switch_profile actions to check")
