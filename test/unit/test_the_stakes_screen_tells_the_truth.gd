extends GutTest

## The Tier-1 dashboard told the player permadeath staking pays "3x EXP". It does not, and the
## player is opting into a disk-persisted permanent character death on the strength of it.
##
## What staking actually does: efficiency_growth_rate 0.1 -> 0.15, read per battle by
## _increase_efficiency on the live path. `permadeath_multiplier = 3.0` has three sites — its own
## declaration, a print, and _simulate_battle:1030, whose only caller `_run_automated_battle` has
## ZERO callers. So the 3x lives exclusively in dead code.
##
## ⛔ AND THE SUFFIX WAS OUTSIDE THE CONDITIONAL: `"PERMADEATH: %s (3x EXP)" % (...)` rendered
## "PERMADEATH: OFF (3x EXP)" too — a reward claim attached to the disabled state.
##
## The confirm dialog has always been right ("Rewards grow 50% faster"). Three surfaces quoted the
## same trade and one contradicted the other two, so all three now derive from one function.

const SYS := "res://src/autogrind/AutogrindSystem.gd"
const DASH := "res://src/ui/autogrind/AutogrindDashboard.gd"
const UI := "res://src/ui/autogrind/AutogrindUI.gd"


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindSystem.enable_permadeath_staking(false)
	AutogrindSystem._test_disable_persistence = false


## The number every caption quotes must be the one the grind uses — derived, not typed.
func test_the_advertised_bonus_is_the_one_the_grind_applies() -> void:
	var pct: int = AutogrindSystem.staking_growth_bonus_percent()
	assert_gt(pct, 0, "CONTROL: the bonus must be a real, positive percentage — got %d" % pct)

	AutogrindSystem.enable_permadeath_staking(false)
	var off: float = AutogrindSystem.efficiency_growth_rate
	AutogrindSystem.enable_permadeath_staking(true)
	var on: float = AutogrindSystem.efficiency_growth_rate
	assert_gt(on, off, "PRECONDITION: staking must actually raise the growth rate (%.3f vs %.3f)" % [on, off])
	assert_eq(int(round((on / off - 1.0) * 100.0)), pct,
		("the percentage the captions print is not the one enable_permadeath_staking applies — a " +
		"player reading the stakes screen is being quoted a number the grind does not use"))


## No surface may advertise a multiplier nothing applies.
func test_no_caption_promises_the_unwired_multiplier() -> void:
	## ⛔ Comments stripped: the first run of this arm flagged AutogrindDashboard because MY OWN
	## comment explaining the fix quotes the banned string. A guard about what a PLAYER sees must not
	## read prose — third time this session a guard of mine was satisfied (or here, tripped) by its
	## own explanation.
	var offenders: Array = []
	for path in [DASH, UI]:
		var src := _code_only(FileAccess.get_file_as_string(path), "func _ready(")
		assert_gt(src.length(), 500, "CONTROL: %s must have been read" % path)
		for bad in ["3x EXP", "3.0x", "triple EXP"]:
			if src.contains(bad):
				offenders.append("%s advertises '%s'" % [path.get_file(), bad])
	assert_eq(offenders, [],
		("a player-facing surface promises a reward multiplier. permadeath_multiplier is applied " +
		"ONLY in _simulate_battle, whose caller _run_automated_battle has no callers — so nothing " +
		"delivers it. Quote staking_growth_bonus_percent(), or wire the multiplier first: %s") % [offenders])


## The OFF state must not carry a reward claim. This is the half that rendered on every dashboard.
func test_the_disabled_state_advertises_nothing() -> void:
	## ⛔ Two failed attempts before this one, both source-parsing. The first anchored on
	## find("PERMADEATH: OFF") and matched an innocent initial-state assignment 250 lines above the
	## refresh label. The second exempted lines containing "if staking" so it would not flag the
	## CORRECT conditional — and the broken version contains "if staking" too, so the exemption
	## swallowed the defect. Both passed a mutation that restored the bug. RENDER it instead.
	var DashClass = load(DASH)
	var off: String = DashClass.permadeath_label_text(false)
	var on: String = DashClass.permadeath_label_text(true)
	gut.p("  OFF -> %s | ON -> %s" % [off, on])
	assert_true(on.contains("ON"), "CONTROL: the enabled state must render something")
	for bad in ["EXP", "3x", "growth", "%", "("]:
		assert_false(off.contains(bad),
			("the DISABLED permadeath label carries a reward claim ('%s'): %s. The suffix used to sit " +
			"outside the conditional, so every dashboard read 'PERMADEATH: OFF (3x EXP)'") % [bad, off])
	assert_true(on.contains(str(AutogrindSystem.staking_growth_bonus_percent())),
		"the enabled label must quote the DERIVED bonus, not a typed number: %s" % on)


## If the multiplier ever gains a live consumer, this arm says so — at which point the captions
## should quote it again and this file is the thing that must change.
func test_the_multiplier_is_still_unwired() -> void:
	var sys := _code_only(FileAccess.get_file_as_string(SYS), "func stop_autogrind(")
	var at := sys.find("func _run_automated_battle")
	assert_gt(at, -1, "PRECONDITION: the dead simulation path must still exist to be checked")
	var callers := 0
	var from := 0
	while true:
		var i := sys.find("_run_automated_battle(", from)
		if i < 0:
			break
		if not sys.substr(maxi(0, i - 5), 5).contains("func "):
			callers += 1
		from = i + 1
	assert_eq(callers, 0,
		("_run_automated_battle has a caller now, so _simulate_battle's permadeath_multiplier may be " +
		"live. Re-measure whether staking pays 3x, and if it does, the captions should say so"))


## BOTH halves (@cowir-overworld): `#` comments are line-addressable, `"""` regions are not — a
## docstring carries no `#`, so a line pass cannot see it, which is the .325 defect. Demonstrated
## live: the .338 guard scored 4/4 with a real connect deleted and a docstring claiming it. Region
## half is a parity split — stateless, nothing to desync. `must_survive` is REQUIRED so no call site
## can omit the positive control; over-stripping and correct stripping are otherwise the same green.
func _code_only(src: String, must_survive: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	var parts := "\n".join(out).split("\"\"\"")
	var kept: PackedStringArray = []
	for i in parts.size():
		if i % 2 == 0:
			kept.append(parts[i])
	var stripped := "".join(kept)
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed a known CODE site (%s) — every assert below measures nothing" % must_survive)
	return stripped
