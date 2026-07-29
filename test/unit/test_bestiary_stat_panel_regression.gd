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
##    magic damage started dividing by it (Combatant.gd:277) and Protect
##    stopped mitigating magic. All 98 monsters carry an explicit value;
##    the panel that exists to show a monster's stats just never listed
##    it, so DEF alone told a player nothing about how a caster would land.
##
## Both are guarded behaviourally — this drives the real menu and reads
## rendered geometry, because "does it fit" is not answerable from source.

const WORST_CASE := "HP 16500   MP 999   ATK 750   DEF 550   MAG 780   M.DEF 270   SPD 30"


func after_each() -> void:
	GameState.text_size_scale = 1.0


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
