extends GutTest
## Two overflows shipped from this lane in two days and no guard caught either:
##   .672  the Summary's stop advice ran 31px past a 520px panel (corruption_limit, 101 chars)
##   .683  the Dashboard's stats strip ran 126px past its 296px column ("Region Crack:" cut mid-word)
## Both were found by walking every Label on a screen against the thing that bounds it. This is that
## walk, standing, over all four autogrind surfaces.
##
## ⛔ IT MEASURES THE POPULATED STATE. Every earlier probe of mine read the DEFAULT one -- "0.000",
## "Lv.0", "no battle in progress" -- which is the same "shortest case you happen to render" that let
## the .672 overflow survive a screenshot I had looked at.
##
## ⛔ AND IT FAILS ON AN UNMEASURED LABEL. My first run silently skipped 13 of 189 whose parent was
## 0-wide; a zero from 176-of-189 and a zero from 189-of-189 print identically. The cause was the
## harness never sizing the screens, so they are sized here and any skip is a RED, not a gap.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

const SCREEN_W := 1280.0
const SCREEN_H := 720.0

const SCREENS := {
	"Dashboard": "res://src/ui/autogrind/AutogrindDashboard.gd",
	"Monitor": "res://src/ui/autogrind/AutogrindMonitor.gd",
	"Console": "res://src/ui/autogrind/AutogrindUI.gd",
}

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


## DERIVED, not typed: a longer monster added later is covered without editing this file.
func _longest_monster_name() -> String:
	var txt := FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(txt)
	var best: String = ""
	if parsed is Dictionary:
		for k in (parsed as Dictionary):
			var v: Variant = (parsed as Dictionary)[k]
			if v is Dictionary:
				var n: String = str((v as Dictionary).get("name", ""))
				if n.length() > best.length():
					best = n
	return best


func _party() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for nm in ["Fighter", "Cleric", "Mage", "Rogue", "Bard"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": nm, "max_hp": 999, "max_mp": 999})
		out.append(c)
	return out


func _labels(n: Node, acc: Array) -> Array:
	if n is Label:
		acc.append(n)
	for c in n.get_children():
		_labels(c, acc)
	return acc


## The bound a label is actually drawn inside: the first ancestor with a real width, carrying offsets.
func _bound_for(lbl: Label) -> Dictionary:
	var off: float = lbl.position.x
	var anc: Node = lbl.get_parent()
	while anc != null:
		if anc is Control and (anc as Control).size.x > 0.0:
			return {"bound": (anc as Control).size.x, "off": off, "by": anc.get_class()}
		if anc is Control:
			off += (anc as Control).position.x
		anc = anc.get_parent()
	return {}


func _check(tag: String, screen: Node) -> void:
	var all: Array = _labels(screen, [])
	assert_gt(all.size(), 0, "FLOOR: %s rendered no Labels at all -- the harness did not build it" % tag)
	var measured: int = 0
	for lbl in all:
		var b: Dictionary = _bound_for(lbl)
		## An UNMEASURED label is a hole, not a pass. 176-of-189 and 189-of-189 print the same zero.
		assert_false(b.is_empty(),
			"%s: '%s' has no sized ancestor, so nothing bounds it and this walk cannot judge it" % [
				tag, str(lbl.text).substr(0, 30)])
		if b.is_empty():
			continue
		measured += 1
		var right: float = float(b["off"]) + lbl.size.x
		assert_lte(right, float(b["bound"]) + 0.5,
			"%s: Label '%s' (%d chars) runs %dpx past its %dpx %s -- it draws over the screen behind it" % [
				tag, str(lbl.text).substr(0, 40), str(lbl.text).length(),
				int(right - float(b["bound"])), int(float(b["bound"])), str(b["by"])])
	assert_eq(measured, all.size(), "FLOOR: %s measured %d of %d Labels" % [tag, measured, all.size()])


func test_the_summary_fits_its_panel_with_a_long_session() -> void:
	AutogrindSystem.last_interrupt_rule = "corruption_limit"
	var s: Node = load("res://src/ui/autogrind/AutogrindSummary.gd").new()
	s.size = Vector2(SCREEN_W, SCREEN_H)
	add_child_autofree(s)
	s.setup({"battles_won": 9999, "total_exp": 1234567, "total_gold": 987654,
		"elapsed_seconds": 35999.0, "consecutive_wins": 999, "efficiency": 12.75,
		"corruption": 4.49, "corruption_threshold": 4.5, "rules_authored": 12,
		"rules_that_fired": 11, "rule_checks": 99999, "meta_bosses_spawned": 9,
		"meta_bosses_defeated": 9, "collapse_count": 7},
		"Defeated by %s" % _longest_monster_name())
	await wait_frames(3)
	_check("Summary", s)


func test_the_live_screens_fit_their_panels_with_a_long_session() -> void:
	AutogrindSystem.total_exp_gained = 1234567
	AutogrindSystem.battles_completed = 9999
	AutogrindSystem.meta_corruption_level = 4.49
	AutogrindSystem.efficiency_multiplier = 12.75
	AutogrindSystem.monster_adaptation_level = 3.5
	var boss: String = _longest_monster_name()
	assert_gt(boss.length(), 20,
		"FLOOR: the longest monster name must be derived and long, or this measures the easy case")
	for tag in SCREENS:
		var s: Node = load(SCREENS[tag]).new()
		s.size = Vector2(SCREEN_W, SCREEN_H)
		add_child_autofree(s)
		if s.has_method("setup"):
			s.setup(_party())
		await wait_frames(3)
		if s.has_method("add_highlight"):
			s.add_highlight("%s appeared!" % boss, "danger")
		if s.has_method("_log_message"):
			s._log_message("INTERRUPT: Fighter fell to %s at 0%% HP" % boss)
		await wait_frames(3)
		_check(tag, s)
