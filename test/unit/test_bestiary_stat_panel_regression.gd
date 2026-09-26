extends GutTest

## Two shipped defects in the Bestiary detail panel, both player-visible.
##
## 1. THE STAT LINE CLIPPED AT LARGE TEXT SIZES.
##    Every y in the detail column was a literal (stats at +86 in a 48px
##    box, weak at +140, resist at +164 …), which silently assumes each
##    label is exactly one line tall. Two changes broke that: the x10 stat
##    rescale pushed max_hp to 16500, making the stat string long enough
##    to wrap; and TextScale multiplies every font by a PLAYER-CHOSEN
##    accessibility factor while the boxes stayed fixed.
##
##    Measured on the shipped build, worst-case stat line, box height 48:
##      scale 1.00   1 line    29px    fits
##      scale 1.50   2 lines   88px    40px cut off
##      scale 2.00   2 lines  116px    68px cut off
##
##    The players who enlarged the text — the ones who most need to read
##    it — lost half of every monster's stats, and the overflow ran under
##    Weak and Resist.
##
## 2. M.DEF WAS NEVER DISPLAYED. magic_defense became load-bearing when
##    magic damage started dividing by it (the is_magical branch of
##    Combatant.take_damage) and Protect stopped mitigating magic.
##    All 98 monsters carry an explicit value;
##    the panel that exists to show a monster's stats just never listed
##    it, so DEF alone told a player nothing about how a caster would land.
##
## Both are guarded behaviourally — this drives the real menu and reads
## rendered geometry, because "does it fit" is not answerable from source.

const GuardSubject := preload("res://test/unit/helpers/guard_subject.gd")
const WORST_CASE := "HP 16500   MP 999   ATK 750   DEF 550   MAG 780   M.DEF 270   SPD 30"


var _prior_text_scale: float = 1.0


func before_each() -> void:
	_prior_text_scale = GameState.text_size_scale


func after_each() -> void:
	# Restore what was there, not an assumed 1.0 — text_size_scale is a shared
	# autoload field and hardcoding the default leaks this test's opinion of it.
	GameState.text_size_scale = _prior_text_scale


func _build_menu() -> Node:
	var menu = load("res://src/ui/BestiaryMenu.gd").new()
	add_child_autofree(menu)
	await wait_frames(3)
	return menu


func test_detail_column_labels_never_overlap_at_any_text_size() -> void:
	# ASSERTS OVERLAP, NOT CLIPPING, and the distinction is the whole
	# finding. My first version of this guard measured "does the text
	# exceed its box" and passed two mutations that broke the fix
	# outright, because Godot AUTO-GROWS a Label's size.y to fit its
	# content (48 -> 91 at 1.5x). The box can never be too small, so that
	# assertion could not fail — a tautology dressed as a measurement.
	#
	# What actually goes wrong: the stat text expands to two lines and
	# runs UNDERNEATH Weak and Resist, which sat at fixed y offsets. The
	# player sees stats overprinted by other stats, not truncated.
	#
	# The real invariant is that consecutive labels in the column don't
	# collide, at every text size a player can select.
	var presets := [0.8, 1.0, 1.25, 1.5, 2.0]
	var collisions: Array = []
	for scale in presets:
		GameState.text_size_scale = scale
		var menu = await _build_menu()
		var stats = menu.get("_detail_stats")
		assert_ne(stats, null, "detail stat label must exist at scale %s" % scale)
		if stats == null:
			continue
		stats.text = WORST_CASE
		await wait_frames(2)
		menu.call("_reflow_detail_column")
		await wait_frames(1)
		var column := [
			["stats", stats], ["weak", menu.get("_detail_weak")],
			["immune", menu.get("_detail_immune")],
			["resist", menu.get("_detail_resist")], ["rewards", menu.get("_detail_rewards")],
			["drops", menu.get("_detail_drops")],
		]
		for i in range(column.size() - 1):
			var a = column[i][1]
			var b = column[i + 1][1]
			if a == null or b == null:
				continue
			var a_bottom: float = a.position.y + a.size.y
			if a_bottom > b.position.y:
				collisions.append("scale %s: %s ends at %d but %s starts at %d (%dpx overlap)"
					% [scale, column[i][0], a_bottom, column[i + 1][0], b.position.y,
					   a_bottom - b.position.y])
	assert_eq(collisions, [],
		"detail column labels must never overlap at any selectable text size — overlapping rows print stats on top of each other for the players who enlarged the text: %s" % [collisions])


func test_detail_column_stays_inside_the_panel_at_max_text_size() -> void:
	# Reflowing pushes labels down; make sure the cure isn't an overflow.
	# 2.0 is the largest preset, so it is the binding case.
	GameState.text_size_scale = 2.0
	var menu = await _build_menu()
	var stats = menu.get("_detail_stats")
	var drops = menu.get("_detail_drops")
	assert_ne(stats, null, "detail labels must exist")
	if stats == null or drops == null:
		return
	stats.text = WORST_CASE
	await wait_frames(2)
	menu.call("_reflow_detail_column")
	await wait_frames(1)
	var panel = stats.get_parent()
	var bottom: float = drops.position.y + drops.size.y
	assert_lte(bottom, panel.size.y,
		"the reflowed detail column must stay inside the panel at 2.0x text — column ends at %d, panel is %d tall" % [bottom, panel.size.y])


func test_magic_defense_is_shown_and_matches_what_combat_uses() -> void:
	# The value displayed must be the value magic damage actually divides
	# by, including Combatant's int(defense * 0.5) fallback — a bestiary
	# that advertises a number combat does not use is worse than one that
	# shows nothing.
	var raw := FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "monsters.json must parse")
	if not (parsed is Dictionary):
		return
	var mons = parsed.get("monsters", parsed)
	assert_gt(mons.size(), 50,
		"sanity: expected the full roster, got %d — a short parse would make the check below vacuous" % mons.size())

	var src := FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	assert_true(src.contains("M.DEF"),
		"the bestiary stat line must list M.DEF — magic damage divides by magic_defense, not defense, and Protect no longer mitigates magic")

	# Behavioural half: render a real entry and read what lands on screen.
	GameState.text_size_scale = 1.0
	var menu = await _build_menu()
	var stats_label = menu.get("_detail_stats")
	if stats_label == null:
		return
	var id: String = mons.keys()[0]
	var st: Dictionary = mons[id].get("stats", {})
	var expected: int = int(st.get("magic_defense", int(st.get("defense", 0) * 0.5)))
	menu.set("_entries", [{
		"id": id, "name": mons[id].get("name", id), "level": mons[id].get("level", 1),
		"epithet": "", "stats": st, "flavor": "", "defeated": true,
		"weaknesses": [], "resistances": [], "drops": [], "pools": [],
	}])
	menu.set("_selected", 0)
	menu.call("_refresh_detail")
	await wait_frames(2)
	assert_true(stats_label.text.contains("M.DEF %d" % expected),
		"rendered stat line must show M.DEF %d for %s (the value Combatant divides magic damage by) — got '%s'" % [expected, id, stats_label.text])


func test_intel_column_does_not_print_on_top_of_the_flavor() -> void:
	# Immune, the kill tally, and the one-shot hint were added under the stat
	# column while flavor stayed pinned under the sprite at a fixed y, full
	# width. At the default text size that puts Resist, EXP/Gold, the drop
	# rates, and the one-shot tactic on top of the paragraph — the rows a
	# player opens the bestiary to read.
	GameState.text_size_scale = 1.0
	var menu = await _build_menu()
	menu.set("_entries", [{
		"id": "slime", "name": "Slime", "level": 1, "epithet": "Wobbling Nuisance",
		"stats": {"max_hp": 680, "max_mp": 20, "attack": 210, "defense": 80, "magic": 120, "magic_defense": 40, "speed": 8},
		"weaknesses": ["fire"], "resistances": ["physical"], "immunities": [],
		"flavor": "The first thing you fight in every JRPG ever made, updated with 21 percent more gelatin. Bouncing serves no evolutionary purpose.",
		"defeated": true,
		"drops": [{"item": "potion", "chance": 0.3}, {"item": "ether", "chance": 0.15}, {"item": "hi_potion", "chance": 0.05}],
		"one_shot_reward": "boss_trophy",
		"one_shot_hint": "Stack attack buffs, defer for max AP, then unleash all at once.",
		"pools": ["Cave Floor 1", "Overworld Plains"],
		"last_location": "Cave Floor 1",
		"exp_reward": 15, "gold_reward": 10, "defeat_count": 3,
	}])
	menu.set("_selected", 0)
	menu.call("_refresh_detail")
	await wait_frames(2)
	var flavor = menu.get("_detail_flavor")
	var drops = menu.get("_detail_drops")
	var tactic = menu.get("_detail_tactic")
	assert_ne(flavor, null, "flavor label must exist")
	assert_ne(drops, null, "drops label must exist")
	assert_ne(tactic, null, "one-shot tactic label must exist")
	if flavor == null or drops == null or tactic == null:
		return
	var flavor_rect := Rect2(flavor.position, flavor.size)
	var collisions: Array = []
	for pair in [
		["resist", menu.get("_detail_resist")],
		["rewards", menu.get("_detail_rewards")],
		["drops", drops],
		["tactic", tactic],
	]:
		var lab = pair[1]
		if lab == null or str(lab.text) == "":
			continue
		var rect := Rect2(lab.position, lab.size)
		if rect.intersects(flavor_rect):
			collisions.append("%s overlaps the flavor paragraph (%s vs %s)" % [pair[0], rect, flavor_rect])
	assert_gt(flavor.size.y, 40.0,
		"the flavor paragraph must keep a readable block under the intel column — hiding it is not a fix (height %s)" % flavor.size.y)
	assert_eq(collisions, [],
		"bestiary intel must stay readable — the flavor paragraph was painting over Resist, rewards, drops, and the one-shot hint: %s" % [collisions])
	assert_gte(tactic.position.y, drops.position.y + drops.size.y,
		"the one-shot hint must sit below the drop line, not on top of it (tactic y=%s, drops end at %s)" % [tactic.position.y, drops.position.y + drops.size.y])


## ⛔ THE SILENT-PASS FLOOR. This guard drives its subject BY NAME; rename the member and every
## cardinal stays clean — see test/unit/helpers/guard_subject.gd for the four measurements and why
## run_tests.sh's exit 4 cannot see this rung. Names are DERIVED from this file's own text, so a
## new `.call("...")` is floored the day it is written rather than the day someone remembers.
func test_every_member_this_guard_drives_by_name_exists() -> void:
	var subject: Object = load("res://src/ui/BestiaryMenu.gd").new()
	add_child_autofree(subject)
	var calls: Dictionary = GuardSubject.audit_calls("res://test/unit/test_bestiary_stat_panel_regression.gd", subject)
	var props: Dictionary = GuardSubject.audit_properties("res://test/unit/test_bestiary_stat_panel_regression.gd", subject)
	assert_eq((str(calls["why"]) + " " + str(props["why"])).strip_edges(), "",
		("the COMMENT STRIP failed, so the derived member list is prose or empty — that is the "
		+ "INSTRUMENT, not the subject: %s %s") % [calls["why"], props["why"]])
	assert_gt(int(calls["found"]) + int(props["found"]), 0,
		"VOID: no `.call(\"name\")` or `.get(\"_name\")` found in this file's own text — the extraction is broken, not the subject")
	assert_eq(calls["missing"], [],
		("this guard drives those methods BY NAME and the subject no longer has them, so its arms "
		+ "would ABORT INTO A SILENT PASS — EC=0, nothing failing, nothing risky: %s") % [calls["missing"]])
	assert_eq(props["missing"], [],
		"this guard reads those private properties by name and the subject no longer has them: %s" % [props["missing"]])
