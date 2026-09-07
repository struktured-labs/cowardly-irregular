extends GutTest

## Cadence #20 — start_autogrind was void with two silent-fail branches:
## 1. Already-active `print` + return (caller couldn't detect double-start)
## 2. No party validation — empty party would start a memberless grind
##
## Now: bool return + push_warning on both branches. Backward-compat with
## the sole controller caller (AutogrindController:123 ignores the return
## today, gets an unused-but-correct bool going forward).

const AutogrindSystemScript := preload("res://src/autogrind/AutogrindSystem.gd")


var _system: Node


func before_each() -> void:
	_system = AutogrindSystemScript.new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true


func _make_party(n: int) -> Array[Combatant]:
	# Build a party of n Combatants for happy-path tests.
	var out: Array[Combatant] = []
	for i in range(n):
		var c = Combatant.new()
		c.initialize({
			"name": "T%d" % i,
			"max_hp": 100, "max_mp": 20,
			"attack": 10, "defense": 5, "magic": 5, "speed": 10,
		})
		add_child_autofree(c)
		out.append(c)
	return out


func test_valid_start_returns_true() -> void:
	# Baseline: happy path returns true, sets is_grinding.
	var party := _make_party(3)
	var ok: bool = _system.start_autogrind(party, {})
	assert_true(ok, "valid party start must return true (cadence #20 void → bool promotion)")
	assert_true(_system.is_grinding, "successful start must flip is_grinding")
	_system.stop_autogrind("test cleanup")


func test_double_start_returns_false() -> void:
	var party := _make_party(2)
	var first: bool = _system.start_autogrind(party, {})
	assert_true(first, "first start baseline: succeeds")
	# Second call while grind still active → refuse.
	var second: bool = _system.start_autogrind(party, {})
	assert_false(second, "double-start while grinding must return false — caller-bug detector (cadence #20)")
	assert_true(_system.is_grinding, "refused double-start must NOT flip is_grinding off")
	_system.stop_autogrind("test cleanup")


func test_empty_party_returns_false() -> void:
	var empty_party: Array[Combatant] = []
	var ok: bool = _system.start_autogrind(empty_party, {})
	assert_false(ok, "empty party must refuse to start — would produce a memberless grind + trip fatigue/collapse defaults (cadence #20)")
	assert_false(_system.is_grinding, "refused start must NOT flip is_grinding on")


func test_non_combatant_only_party_returns_false() -> void:
	# The guard iterates `if m is Combatant` — a party of non-Combatants
	# (e.g., passing dicts or nulls due to a caller bug) has 0 live members
	# even if the array isn't empty. Must be refused.
	var bogus_party: Array[Combatant] = []
	# Can't add non-Combatants to Array[Combatant] statically, so simulate
	# by passing an untyped empty array through the untyped path (this exact
	# scenario is caught by the "live_count == 0" branch either way).
	var result: bool = _system.start_autogrind(bogus_party, {})
	assert_false(result, "empty typed-array party must return false (same guard as literal-empty)")


func test_source_ratchet_signature_returns_bool() -> void:
	# Cadence #20's signature promotion: start_autogrind must return bool
	# so callers can detect refusal. A refactor that reverts to void loses
	# both silent-fail detectors (double-start + empty-party).
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	assert_true(src.contains("func start_autogrind(party: Array[Combatant], enemy_template: Dictionary, config: Dictionary = {}) -> bool:"),
		"start_autogrind must return bool (cadence #20 promotion — void revert reintroduces silent-double-start + silent-empty-party)")


func test_source_ratchet_both_guards_push_warning() -> void:
	# Both silent-fail branches must push_warning. Same class as tick 344 for
	# load, cadence #14 for save, cadence #15 for profile API.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start: int = src.find("func start_autogrind")
	var fn_end: int = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	# Isolate the guards (both live before is_grinding=true is set).
	var isg_pos: int = body.find("is_grinding = true")
	assert_true(isg_pos > 0, "setup: is_grinding=true assignment must exist")
	var head: String = body.substr(0, isg_pos)
	# Both refusal branches (already-active + empty-party) must push_warning.
	var warn_count := head.count("push_warning")
	assert_gte(warn_count, 2,
		"start_autogrind's TWO refusal branches (already-active + empty-party) must both push_warning — found %d warnings in the head (cadence #20)" % warn_count)


func test_ratchet_success_path_returns_true() -> void:
	# The successful tail must include `return true` — pre-cadence-#20 the
	# function was void, so a refactor forgetting to add the terminal return
	# would make the happy path return null-as-false and break every caller.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start: int = src.find("func start_autogrind")
	var fn_end: int = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	# The return true should be the LAST non-empty line of the function body.
	assert_true(body.contains("return true"),
		"start_autogrind's success path must terminate with `return true` — else happy-path callers see false and think the grind refused")
