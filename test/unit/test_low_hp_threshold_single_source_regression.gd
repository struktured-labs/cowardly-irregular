extends GutTest

## The 25% low-HP beat lived as 2 constants + 2 bare literals across 2 files on 2 unit scales, held together by a comment.

const SCENE := "res://src/battle/BattleScene.gd"
const MANAGER := "res://src/battle/BattleManager.gd"

## Multi-band presentation ladders that share the VALUE but not the meaning — binding these
## couples an HP-bar colour stop to a music cue. Discriminator: lone threshold vs one stop.
const LADDER_FILES := [
	"res://src/battle/BattleUIManager.gd",
	"res://src/ui/AccessibilityPalette.gd",
	"res://src/ui/autogrind/AutogrindUI.gd",
]


func _src(p: String) -> String:
	var s := FileAccess.get_file_as_string(p)
	assert_gt(s.length(), 0, "%s must load" % p)
	return s


## The two dialogue triggers were bare 25.0 while the constant sat one screen above them.
func test_no_bare_low_hp_literal_survives_in_battle_scene() -> void:
	var s := _src(SCENE)
	assert_false("get_hp_percentage() < 25.0" in s,
		"a bare 25.0 low-HP gate is back — it will not move when DANGER_HP_THRESHOLD is tuned, " +
		"and the two are on different scales so the mismatch does not look like a mismatch")
	## Re-ruled 2026-09-03: this pinned the COUNT of constant-readers at 2 and went red when the
	## weak-sprite rest-state provider became a third, correct reader — the exact
	## coincidental-value ratchet CLAUDE.md warns about. The invariant is "every low-HP consumer
	## reads the constant on the right scale", which the bare-literal assert above already owns;
	## the reader count may only GROW.
	assert_gte(s.count("DANGER_HP_THRESHOLD * 100.0"), 3,
		"the dialogue triggers AND the weak rest-state must read the constant on the 0-100 scale")


## Scale is the silent failure: bind without *100.0 and the gate becomes "below 0.25%" — never fires.
func test_the_scale_conversion_is_present_not_a_raw_bind() -> void:
	var s := _src(SCENE)
	assert_false("get_hp_percentage() < DANGER_HP_THRESHOLD and" in s,
		"a raw bind reads 'below 0.25%' against a 0-100 value — the trigger stops firing and " +
		"a trigger that never fires is indistinguishable from a quiet battle")
	assert_true("const DANGER_HP_THRESHOLD: float = 0.25" in s,
		"the constant must stay on the 0-1 scale its music consumer expects")


## Two constants in two files, same beat. They cannot reference each other at parse time, so pin agreement.
func test_the_two_named_constants_still_agree() -> void:
	var scene_v := _const_value(_src(SCENE), "DANGER_HP_THRESHOLD")
	var mgr_v := _const_value(_src(MANAGER), "LOW_HP_PCT_THRESHOLD")
	assert_gt(scene_v, 0.0, "DANGER_HP_THRESHOLD must parse to a number")
	assert_gt(mgr_v, 0.0, "LOW_HP_PCT_THRESHOLD must parse to a number")
	assert_almost_eq(scene_v * 100.0, mgr_v, 0.001,
		"the 0-1 and 0-100 twins have diverged — the sprite/music/quip beat and the party voice cue " +
		"would fire at different HP, which reads as an audio bug nobody would trace to a threshold")


func _const_value(src: String, name: String) -> float:
	var re := RegEx.new()
	re.compile("const %s\\s*:\\s*float\\s*=\\s*(?<v>[0-9.]+)" % name)
	var m := re.search(src)
	return float(m.get_string("v")) if m != null else -1.0


## CANARY: the ladders must stay UNBOUND. If this ever reads them as bound, the sweep overreached.
func test_presentation_ladders_are_not_bound_to_the_beat() -> void:
	for p in LADDER_FILES:
		var s := _src(p)
		assert_false("DANGER_HP_THRESHOLD" in s,
			"%s is a multi-band health ladder, not the low-HP beat — binding its 0.25 stop to the " % p +
			"music constant makes the bar's bands go non-monotonic the first time anyone retunes it")


## CONTROL: the ladder files must actually CONTAIN a 0.25 stop, else the canary above guards nothing.
func test_ladder_canary_names_a_known_present_member() -> void:
	var found := 0
	for p in LADDER_FILES:
		if "0.25" in _src(p):
			found += 1
	assert_eq(found, LADDER_FILES.size(),
		"every ladder file must still hold a 0.25 stop — if one does not, the canary is passing " +
		"on a file with nothing to protect, which is the decorative-control mistake this guard exists to avoid")
