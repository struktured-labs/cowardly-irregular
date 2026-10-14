extends GutTest

## AbilitiesMenu is a NEVER-CONVERTED surface: zero `TextScale` references and 29 raw font sites,
## so the Text Size setting does nothing to it at any preset. That makes its story different from
## JobMenu's, which was HALF converted — there, scaled fonts met literal pitches and the lines
## landed on each other from 125%. Here nothing moves, so this file's first question is whether the
## literals collide AS SHIPPED, at 100%, before any scaling is added.
##
## 🛑 THE ARMS ARE THE SHAPE THAT SURVIVED SIX INSTRUMENT ERRORS IN JobMenu TODAY, reused rather
## than re-derived:
##   - ONE overlap arm: all ordered pairs, GLOBAL rects, DRAWN extents, `Rect2.intersects`.
##     Replaces per-parent/per-row/cross-container axis arms, every one of which had a grouping or
##     adjacency hole. Two rectangles either intersect or they do not.
##   - a CONTAINMENT arm, because the overlap arm passes on contents that have grown out through a
##     panel's bottom edge together.
##   - a font arm matched BY TEXT, because a scrolling list shows FEWER rows at a larger font and
##     an equal-length multiset precondition reds on correct behaviour.
##   - the TAB is a sweep dimension. AbilitiesMenu builds the abilities panel OR the passives panel,
##     never both, so a guard that never sets `current_tab` measures half the screen. That exact
##     omission on JobMenu left a whole panel unbuilt and a pitch mutation INERT.

const AbilitiesMenuScript = preload("res://src/ui/AbilitiesMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

const TEXT_SCALES := [0.8, 1.0, 1.25, 1.5, 2.0]

## ⚠️ REAL MAGNITUDES, not the @export defaults. A bare Combatant reports attack 10 and max_hp 100,
## so every readout is ~43px wide and a literal column pitch looks sound at every preset — which is
## how a JobMenu column-width mutation passed this morning. struktured's save_98 party carries
## these.
const LIVE_STATS := {
	"attack": 634, "defense": 628, "magic": 1041, "magic_defense": 163,
	"speed": 75, "max_hp": 4523, "max_mp": 240,
}

var _saved_scale: float = 1.0


## ⚠️ SAVE AND RESTORE, never a hardcoded 1.0. A literal restore asserts what the default SHOULD be
## and silently corrects an earlier file's leak, which looks identical to a clean run from outside.
func before_each() -> void:
	if GameState:
		_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	if GameState:
		GameState.text_size_scale = _saved_scale


## Every preset x every TAB, flattened so an arm body stays at one indent level.
## ⛔ DERIVED FROM THE ENUM, not written as [0, 1]. A literal tab list is the same partition
## hazard as a hand-written preset ladder, one noun over: a third tab would be swept by nothing
## while the file still read as covering every screen.
##
## ⚠ A DERIVED list needs a FLOOR and a PINNED const does not. TEXT_SCALES is a literal and can
## never be empty, so an emptied SettingsMenu ladder fails the pin's equality; `_tabs()` reads the
## enum at runtime, so an empty return would make every sweep loop iterate zero times and every
## arm pass vacuously.
func _tabs() -> Array:
	var tabs: Array = AbilitiesMenuScript.Tab.values()
	assert_gt(tabs.size(), 1,
		"AbilitiesMenu.Tab yields %d entries — a sweep over it cannot tell the two screens apart"
		% tabs.size())
	return tabs


func _sweep() -> Array:
	var out: Array = []
	for scale in TEXT_SCALES:
		for tab in _tabs():
			out.append([scale, tab])
	return out


func _menu_for(scale: float, tab: int) -> Control:
	if GameState:
		GameState.text_size_scale = scale
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	pc.job = JobSystem.get_job("fighter")
	for stat in LIVE_STATS:
		pc.set(stat, LIVE_STATS[stat])
	pc.current_hp = int(LIVE_STATS["max_hp"])
	pc.current_mp = int(LIVE_STATS["max_mp"])
	add_child_autofree(pc)
	var m = AbilitiesMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	## The tab is set BEFORE setup, because setup defers _build_ui — so the deferred build reads it
	## and there is no second build to await.
	m.current_tab = tab
	m.setup(pc)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func test_the_sweep_matches_the_shipped_presets() -> void:
	var settings := load("res://src/ui/SettingsMenu.gd")
	assert_eq(TEXT_SCALES, settings.TEXT_SIZE_PRESETS as Array,
		"this file sweeps %s but SettingsMenu offers %s"
		% [str(TEXT_SCALES), str(settings.TEXT_SIZE_PRESETS)])


func test_both_tabs_build_their_rows() -> void:
	var abil := 0
	var pass_ := 0
	for combo in _sweep():
		var m = await _menu_for(combo[0], combo[1])
		abil += m._ability_labels.size()
		pass_ += m._passive_labels.size()
	assert_gt(abil, 0, "PRECONDITION: the ABILITIES tab must build rows")
	assert_gt(pass_, 0, "PRECONDITION: the PASSIVES tab must build rows — otherwise every arm "
		+ "below measures one of this screen's two halves")


func test_no_two_labels_overlap() -> void:
	var bad: Array[String] = []
	var measured := 0
	for combo in _sweep():
		var scale: float = combo[0]
		var m = await _menu_for(scale, combo[1])
		var ls := _labels(m)
		for i in range(ls.size()):
			for j in range(i + 1, ls.size()):
				var a: Label = ls[i]
				var b: Label = ls[j]
				measured += 1
				if _drawn_rect(a).intersects(_drawn_rect(b)):
					bad.append("%.2fx tab %d: '%s' %s overlaps '%s' %s"
						% [scale, combo[1], str(a.text).substr(0, 14), str(_drawn_rect(a)),
						   str(b.text).substr(0, 14), str(_drawn_rect(b))])
	assert_gt(measured, 100,
		"CONTROL: label pairs must have been compared — only %d" % measured)
	assert_eq(bad, [] as Array[String],
		"AbilitiesMenu draws two labels over each other: %s" % [", ".join(bad)])


func test_every_panel_contains_what_it_draws() -> void:
	var bad: Array[String] = []
	var measured := 0
	for combo in _sweep():
		var m = await _menu_for(combo[0], combo[1])
		for l in _labels(m):
			var panel: Control = (l as Label).get_parent() as Control
			if panel == null or panel.size.y <= 0.0:
				continue
			measured += 1
			var box := Rect2(Vector2.ZERO, panel.size)
			var drawn := Rect2(l.position, Vector2(_drawn_w(l), _drawn_h(l)))
			if not box.encloses(drawn):
				bad.append("%.2fx tab %d %s: '%s' draws %s in a %s box"
					% [combo[0], combo[1], panel.name, str(l.text).substr(0, 14),
					   str(drawn), str(panel.size)])
	assert_gt(measured, 20,
		"CONTROL: labels must have been measured against their panels — only %d" % measured)
	assert_eq(bad, [] as Array[String],
		"AbilitiesMenu draws outside its own panels: %s" % [", ".join(bad)])


## ⛔ EXPECTED TO RED ON THE SHIPPED FILE, and that is the finding rather than a broken arm:
## AbilitiesMenu has 29 font sites and not one goes through TextScale, so the setting moves nothing.
## Matched BY TEXT and comparing only labels present at both presets, because the ability and
## passive lists scroll.
func test_every_font_grows_with_the_setting() -> void:
	var at := {}
	for combo in _sweep():
		var m = await _menu_for(combo[0], combo[1])
		var per_text := {}
		for l in _labels(m):
			var key: String = str(l.text)
			if not per_text.has(key):
				per_text[key] = []
			per_text[key].append(l.get_theme_font_size("font_size"))
		for key in per_text:
			per_text[key].sort()
		at["%s/%s" % [combo[0], combo[1]]] = per_text
	var compared := 0
	var stuck: Array[String] = []
	for tab in _tabs():
		var base: Dictionary = at["%s/%s" % [1.0, tab]]
		## ⛔ NOT a second hardcoded list. TEXT_SCALES is pinned to SettingsMenu by the sweep arm;
		## a literal subset here would survive a preset being added and silently never visit the new
		## rung, while every other arm swept it — @cowir-battle's partition hazard, which reads as
		## exhaustive instead of merely incomplete.
		for scale in TEXT_SCALES:
			if is_equal_approx(float(scale), 1.0):
				continue  # the baseline every other preset is compared against
			var other: Dictionary = at["%s/%s" % [scale, tab]]
			for key in base:
				if not other.has(key) or other[key].size() != base[key].size():
					continue
				for i in range(base[key].size()):
					compared += 1
					var up: bool = (other[key][i] > base[key][i]) if scale > 1.0 \
						else (other[key][i] < base[key][i])
					if not up:
						stuck.append("%.2fx '%s' stayed at %d"
							% [scale, key.substr(0, 16), base[key][i]])
	assert_gt(compared, 100,
		"CONTROL: font sites must have been matched across presets — only %d" % compared)
	assert_eq(stuck, [] as Array[String],
		"%d font sites ignore Text Size: %s" % [stuck.size(), ", ".join(stuck)])


func _labels(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		var l := child as Label
		if l != null and str(l.text).strip_edges() != "":
			out.append(l)
		_labels(child, out)
	return out


## A label's painted rectangle in GLOBAL space. `get_global_rect()` gives the BOX; the drawn text is
## what collides, and the two differ in both directions.
func _drawn_rect(l: Label) -> Rect2:
	return Rect2(l.get_global_rect().position, Vector2(_drawn_w(l), _drawn_h(l)))


func _drawn_w(l: Label) -> float:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.clip_text:
		return l.size.x
	return maxf(l.size.x, l.get_combined_minimum_size().x)


## Not `size.y` (a request, clamped up to the minimum as it stood at assignment) and not a font
## query (three break flags to keep in step).
func _drawn_h(l: Label) -> float:
	return float(maxi(1, l.get_visible_line_count())) * float(l.get_line_height())
