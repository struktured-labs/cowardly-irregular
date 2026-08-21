extends GutTest

## The cast tell must stay fire-and-forget and tier-gated.
##
## An `await` inside it would put it INSIDE the action pipeline and shift the execution
## watchdog's cadence — the watchdog is armed start↔end_battle on wall-clock, so anything that
## lengthens a turn by an unbounded amount is a stall risk rather than a cosmetic change.

const SCENE_PATH := "res://src/battle/BattleScene.gd"

var _src: String = ""


func before_all() -> void:
	_src = FileAccess.get_file_as_string(SCENE_PATH)


## Extract a function body by its STRUCTURE, and refuse if the terminator was never reached —
## a fixed-line window returns real code from an incomplete region and nothing says it was cut.
func _body_of(fn: String) -> String:
	var i: int = _src.find("func %s(" % fn)
	if i == -1:
		return ""
	var j: int = _src.find("\nfunc ", i + 1)
	return _src.substr(i, j - i) if j > i else ""


func test_the_extractor_reached_its_terminator() -> void:
	var body := _body_of("_spawn_cast_anticipation")
	assert_ne(body, "", "CONTROL: the function must be found AND its closing boundary reached")
	assert_true(body.begins_with("func _spawn_cast_anticipation("),
		"CONTROL: the extracted block must start at the opener")
	assert_eq(_body_of("_zzz_not_a_real_function"), "",
		"CONTROL: a fabricated name must yield nothing, or extraction means nothing")


func test_cast_anticipation_contains_no_await() -> void:
	var body := _body_of("_spawn_cast_anticipation")
	assert_gt(body.length(), 80, "guard is vacuous on an empty body")
	assert_false(body.contains("await"),
		"an await here enters the action pipeline and moves the execution watchdog's cadence")


func test_it_is_gated_on_the_shared_tier_and_does_not_re_derive_it() -> void:
	var body := _body_of("_spawn_cast_anticipation")
	assert_true(body.contains("_tier()"),
		"the tell must consult BattleScene's shared _tier() helper, not its own speed check")
	assert_false(body.contains("turbo_mode") or body.contains("autogrind_console_mode"),
		"and must NOT re-derive the three-flag triple — _tier() owns it, and a second copy is how gates drift")
	assert_true(body.contains("Tier.FULL") and body.contains("Tier.REDUCED"),
		"FULL and REDUCED are the tiers that show it; MINIMAL and OFF must not")


func test_the_tier_gate_actually_excludes_fast_play() -> void:
	## Behavioural, not textual — the source pin above cannot tell you the tiers are right.
	assert_eq(BattleJuice.presentation_tier(0.25, false, false), BattleJuice.Tier.FULL,
		"1x play (engine 0.25) is FULL — the tell shows")
	assert_eq(BattleJuice.presentation_tier(4.0, false, false), BattleJuice.Tier.OFF,
		"4x is OFF — no tell")
	assert_eq(BattleJuice.presentation_tier(0.25, true, false), BattleJuice.Tier.OFF,
		"turbo is OFF regardless of speed")
	assert_eq(BattleJuice.presentation_tier(0.25, false, true), BattleJuice.Tier.OFF,
		"autogrind console is OFF regardless of speed")


func test_it_fires_only_on_the_non_full_render_branch() -> void:
	## Full Render stages its own caster beat; a second tell there would double up.
	var fr := _body_of("_play_ability_full_render")
	assert_ne(fr, "", "CONTROL: the Full Render function must exist for this comparison")
	assert_false(fr.contains("_spawn_cast_anticipation"),
		"Full Render must not also fire the quick-path tell")
	assert_eq(_src.count("_spawn_cast_anticipation(attacker_sprite"), 1,
		"exactly one call site — the non-Full-Render ability branch")


func test_it_survives_a_freed_or_null_caster() -> void:
	## Sprites are freed on death and on scene teardown; the tell must not abort its caller.
	var scene: Node = load(SCENE_PATH).new()
	add_child_autofree(scene)
	var survived := 0
	scene._spawn_cast_anticipation(null, {"id": "fire"})
	survived += 1
	var doomed := Node2D.new()
	add_child(doomed)
	doomed.free()
	scene._spawn_cast_anticipation(doomed, {"id": "fire"})
	survived += 1
	assert_eq(survived, 2, "both the null AND the freed caster returned; a typed param aborts the second at the call boundary, before the guard")
