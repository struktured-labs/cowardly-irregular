extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const LIVE := "res://src/battle/BattleManager.gd"
const HEADLESS := "res://src/autogrind/HeadlessBattleResolver.gd"
const COMBATANT := "res://src/battle/Combatant.gd"

## ⛔ LUDICROUS SPEED MAKES THE PARTY IMMUNE TO PERMANENT INJURIES, AND NOTHING SAYS SO.
## `AutogrindUI` toggles `ludicrous_speed`, the controller turns that into `headless_mode`
## (AutogrindController:124), and the headless resolver replaces BattleManager for every battle.
## BattleManager.end_battle rolls 25% per KO'd member and calls apply_permanent_injury; the headless
## resolver never does — `apply_permanent_injury` has exactly ONE caller in all of src/.
##
##   normal grind     25% permanent injury per KO
##   LUDICROUS SPEED   0%
##
## So the FASTER, higher-throughput mode carries LESS risk than the slow one, against a stated
## pillar ("Real stakes: permanent injuries" / "Stakes must be real") and against this lane's own
## live/headless parity intent. The lane has fixed three gaps between these same two paths already
## (gold, per-character EXP, duplicate equipment drops); this one was never named.
##
## 🔑 THIS FILE DOES NOT DECIDE THE RULING — it converts an accident into a declaration.
## Whether ludicrous speed SHOULD injure is a stakes decision (it changes how a mode plays, and the
## game also says "exploitation is rewarded"), so it belongs to struktured. What is not a decision
## is the gap being invisible: `test_autogrind_parity_gap_is_named_regression` declares live-only
## ABILITY KEYS and injuries are not one, so no guard's corpus contained this.
##
## ⚠️ THE ARM BELOW REDS IN BOTH DIRECTIONS ON PURPOSE. Wire injuries into the headless path and it
## reds saying the declaration is stale; drop them from live and it reds saying the mechanic is
## gone. You cannot silence it green, only explain it green — and the explanation is the fix.

var _ag_state: Dictionary


func before_each() -> void:
	_ag_state = AutogrindState.snapshot_and_isolate()


func after_each() -> void:
	AutogrindState.restore(_ag_state)


## CONTROL: the mechanic exists live, so "headless lacks it" is discriminating rather than vacuous.
func test_the_live_engine_really_does_injure_on_a_ko() -> void:
	var live: String = GdSource.code_of(LIVE)
	assert_ne(live, "", "CONTROL: BattleManager source must survive the comment strip")
	assert_true(live.contains("apply_permanent_injury("),
		"live no longer applies permanent injuries at all — the mechanic is gone, and this whole file is about a gap that no longer has two sides")
	assert_true(live.contains("_ko_this_battle"),
		"CONTROL: the live roll must still iterate the battle's KOs, which is what makes it per-KO")


## CONTROL: one applier, so counting callers is a real census of who can injure.
func test_one_function_applies_a_permanent_injury() -> void:
	var c: String = GdSource.code_of(COMBATANT)
	assert_true(c.contains("func apply_permanent_injury("),
		"CONTROL: Combatant must still own the applier this file counts callers of")


## ⛔ THE DECLARATION. Headless does not injure. Reds if that changes in either direction.
func test_the_headless_resolver_still_cannot_injure() -> void:
	var hb: String = GdSource.code_of(HEADLESS)
	assert_ne(hb, "", "CONTROL: HeadlessBattleResolver source must survive the comment strip")
	assert_false(hb.contains("apply_permanent_injury("),
		"the headless resolver now applies permanent injuries — ludicrous speed and the normal grind " +
		"finally agree. DELETE THIS DECLARATION and the comment above it; the gap is closed.")

	## And the toggle that selects it is still player-reachable, or the gap is theoretical.
	var ctrl: String = GdSource.code_of("res://src/autogrind/AutogrindController.gd")
	assert_true(ctrl.contains("ludicrous_speed"),
		"CONTROL: ludicrous_speed no longer selects the headless engine — if the player cannot reach " +
		"the headless path, this gap stops being player-facing and this file needs revisiting")
