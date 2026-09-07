extends GutTest

## If an autoload fails to register, 358 tests SKIP and the suite stays green.
##
## Measured 2026-07-31: of 437 `pending()` sites in test/unit, 358 skip on an
## ambient environment condition — "BattleManager autoload required" (52),
## "GameState autoload missing" (46), and 103 other spellings of the same guard.
## Each one is individually reasonable. Together they are a trapdoor: the
## condition they test is not a property of the code under test, it is whether
## the harness brought the autoloads up.
##
## That failure mode is real and documented in this project, not hypothetical —
## running the suite as `godot -s script.gd` starts a SceneTree script in which
## autoloads never register at all. In that world every one of those 358 guards
## fires, `Failing` stays 0, `Tests` stays put, and the gate prints GREEN over a
## suite that verified almost nothing. `run_tests.sh` exits 3 when NOTHING ran;
## this is the finer-grained hole underneath — a third of the suite quietly
## opting out while the totals still look like a real run.
##
## So assert the precondition ONCE, loudly, instead of letting it be re-tested
## silently 358 times. One red test beats 358 invisible skips.
##
## The expected set is DERIVED from project.godot's [autoload] section, so a new
## autoload is covered on arrival and a removed one stops being demanded — no
## hand list to drift.

const PROJECT := "res://project.godot"


## Names declared in the [autoload] block. A leading "*" on the path means
## "singleton"; the name is the key regardless.
func _declared_autoloads() -> Array:
	var text: String = FileAccess.get_file_as_string(PROJECT)
	var out: Array = []
	var in_section := false
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("["):
			in_section = line == "[autoload]"
			continue
		if not in_section or line.is_empty() or line.begins_with(";"):
			continue
		var eq := line.find("=")
		if eq > 0:
			out.append(line.substr(0, eq).strip_edges())
	return out


func test_every_declared_autoload_is_actually_present() -> void:
	var declared := _declared_autoloads()
	# Vacuity floor: a parse that yields nothing would make the loop below pass
	# for free, which is the same shape of hole this file exists to close.
	assert_gt(declared.size(), 0,
		"parsed no autoloads from project.godot — the [autoload] section moved or the parse broke, so this guard is asserting nothing")

	var missing: Array = []
	for name in declared:
		if get_tree().root.get_node_or_null("/root/" + str(name)) == null:
			missing.append(str(name))

	assert_true(missing.is_empty(),
		"%d of %d declared autoload(s) are NOT registered: %s — in this environment every test guarded by \"<X> autoload required\" will pending() out and the suite will still report green" % [
			missing.size(), declared.size(), ", ".join(missing)])


## The control the check above cannot supply for itself: prove the lookup CAN
## return null, so "nothing missing" means the probe works rather than that the
## probe is broken.
func test_the_presence_probe_can_detect_an_absence() -> void:
	assert_null(get_tree().root.get_node_or_null("/root/ZzzDefinitelyNotAnAutoload"),
		"a name that was never declared must resolve to null — if this returns a node, the probe above cannot distinguish present from absent")
	var declared := _declared_autoloads()
	assert_gt(declared.size(), 0, "have a declared name to use as the positive half")
	assert_not_null(get_tree().root.get_node_or_null("/root/" + str(declared[0])),
		"a declared autoload (%s) resolves — the positive half of the control" % str(declared[0]))
