extends GutTest

## The composer asked for "short (3-6 words)", about 40 characters, while each system cuts a profile name at its own cap.
## So the model wrote titles that were always cut. The prompt now names the cap of the system it installs into.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const AB := preload("res://src/autobattle/AutobattleSystem.gd")
const AG := preload("res://src/autogrind/AutogrindSystem.gd")


func _asks(domain: String) -> String:
	return DP.build_rule_composition(domain, "keep everyone alive", [], {})


func test_each_domain_asks_for_its_own_systems_cap() -> void:
	assert_ne(AB.PROFILE_NAME_MAX, AG.PROFILE_NAME_MAX, "CONTROL: the two caps differ, so a crossed domain is visible")
	for pair in [["autobattle", AB.PROFILE_NAME_MAX], ["autogrind", AG.PROFILE_NAME_MAX]]:
		var p: String = _asks(pair[0])
		assert_string_contains(p, "name: at most %d characters" % pair[1], "%s asks for a name that fits its own cap" % pair[0])


func test_the_prompt_no_longer_asks_for_more_than_fits() -> void:
	for domain in ["autobattle", "autogrind"]:
		var p: String = _asks(domain)
		assert_string_contains(p, "description:", "CONTROL: the %s output spec rendered" % domain)
		assert_false(p.contains("3-6 words"), "%s: six words is longer than either cap" % domain)
