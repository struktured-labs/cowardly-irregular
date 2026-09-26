extends GutTest

## Magic Defense is a real combat stat (Combatant.magic_defense, the divisor for
## magical hits) and every job authors one. Equipment comparison and the job-change
## delta already print it. The pause-menu status screen and the party-status strip
## listed Attack/Defense/Magic/Speed and left Magic Defense out, so a character
## whose magic defense differed from defense showed no such number anywhere on
## those screens.
##
## The number on screen has to be magic_defense, not defense, and the status row
## has to show the same base-plus-bonus breakdown the other core stats use.

const SM := preload("res://src/ui/StatusMenu.gd")
const PARTY := preload("res://src/ui/PartyStatusScreen.gd")
const JOB := preload("res://src/ui/JobMenu.gd")
const EDITOR := preload("res://src/ui/autobattle/AutobattleGridEditor.gd")
const CombatantScript := preload("res://src/battle/Combatant.gd")


func _member(name_str: String, defense: int, magic_defense: int) -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = name_str
	c.job = {"id": "mage", "name": "Mage", "abilities": ["fire"]}
	c.job_level = 12
	c.base_attack = 18
	c.attack = 24
	c.base_defense = 10
	c.defense = defense
	c.base_magic = 22
	c.magic = 30
	c.base_magic_defense = 8
	c.magic_defense = magic_defense
	c.base_speed = 11
	c.speed = 14
	c.base_max_hp = 80
	c.max_hp = 120
	c.current_hp = 90
	c.base_max_mp = 40
	c.max_mp = 60
	c.current_mp = 45
	add_child_autofree(c)
	return c


func _labels(root: Node) -> Array:
	var found: Array = []
	_collect(root, found)
	return found


func _collect(n: Node, found: Array) -> void:
	if n is Label:
		found.append(n as Label)
	for child in n.get_children():
		_collect(child, found)


func _label_named(labels: Array, text: String) -> Label:
	for lbl in labels:
		if (lbl as Label).text == text:
			return lbl as Label
	return null


func _text_width(lbl: Label, text: String) -> float:
	var font := lbl.get_theme_font("font")
	var fs: int = lbl.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func test_status_screen_lists_magic_defense_not_a_copy_of_defense() -> void:
	var c := _member("Mira", 16, 77)
	var menu: StatusMenu = SM.new()
	add_child_autofree(menu)
	menu.character = c
	var panel: Control = menu._create_stats_panel(Vector2(320, 480))
	add_child_autofree(panel)
	var labels := _labels(panel)
	var name_lbl := _label_named(labels, "Magic Defense")
	assert_not_null(name_lbl, "status STATS must name Magic Defense — defense alone is not the magic-hit divisor")
	if name_lbl == null:
		return
	var value_lbl := _label_named(labels, "77")
	assert_not_null(value_lbl, "the Magic Defense row must show 77, the combatant's magic_defense, not defense 16")
	if value_lbl == null:
		return
	assert_eq(value_lbl.get_parent(), name_lbl.get_parent(),
		"77 must sit on the Magic Defense row, not on some other stat")
	var defense_value := _label_named(labels, "16")
	assert_not_null(defense_value, "Defense 16 must still be listed — adding Magic Defense must not replace it")
	# Breakdown uses base_magic_defense (8) and the signed delta, same shape as Attack/Defense.
	var breakdown := _label_named(labels, "(8 +69)")
	assert_not_null(breakdown, "Magic Defense must show the base-plus-bonus breakdown (8 +69), got %s" % _texts(labels))
	var name_w := _text_width(name_lbl, name_lbl.text)
	assert_gt(name_w, 40.0, "the Magic Defense label must actually measure — a 0 width would make the overlap check vacuous")
	assert_lte(name_lbl.position.x + name_w + 8.0, value_lbl.position.x,
		"Magic Defense (%.0fpx) must end before its number at x=%.0f, or the two draw on top of each other" % [name_lbl.position.x + name_w, value_lbl.position.x])
	# The number and the "(8 +69)" note must also stay inside the panel.
	var note_w := _text_width(breakdown, breakdown.text) if breakdown != null else 0.0
	if breakdown != null:
		assert_lte(breakdown.position.x + note_w, panel.size.x - 4.0,
			"the Magic Defense breakdown must stay inside the stats panel")


func test_party_strip_shows_magic_defense_inside_the_card() -> void:
	var party: Array = []
	for i in 5:
		party.append(_member("M%d" % i, 10 + i, 70 + i))
	# The focused card carries a 4-digit magic defense so a line that only fits
	# 3-digit stats still fails on a real endgame number.
	party[0].magic_defense = 9999
	party[0].defense = 16
	party[0].magic = 30
	party[0].attack = 24
	party[0].speed = 14
	var screen = PARTY.new()
	add_child_autofree(screen)
	screen.party = party
	screen.focused_index = 0
	screen._build_ui()
	var card: Control = screen._cards[0]
	var stats: Label = null
	for lbl in _labels(card):
		if str((lbl as Label).text).begins_with("ATK"):
			stats = lbl
			break
	assert_not_null(stats, "the party card must still render its stat block")
	if stats == null:
		return
	assert_string_contains(stats.text, "MDF 9999",
		"the party strip must show magic defense — got %s" % stats.text)
	assert_string_contains(stats.text, "DEF 16",
		"defense must remain, and must stay 16 so MDF 9999 cannot be a relabelled defense")
	assert_string_contains(stats.text, "MAG 30")
	assert_string_contains(stats.text, "SPD 14")
	assert_eq(stats.text.split("\n").size(), 2,
		"MDF has to share the existing two lines — a third line runs out of the 184px card into the detail panel")
	var widest := 0.0
	for line in stats.text.split("\n"):
		widest = maxf(widest, _text_width(stats, line))
	assert_gt(widest, 20.0, "stat text must measure, or the fit check passes on a zero width")
	assert_lte(widest, stats.size.x,
		"party-strip stat line is %.0fpx in a %.0fpx card — it would draw into the next member" % [widest, stats.size.x])
	var line_h := stats.get_theme_font("font").get_height(stats.get_theme_font_size("font_size"))
	var bottom := stats.position.y + line_h * float(stats.text.split("\n").size())
	assert_lte(bottom, card.size.y - 4.0,
		"stat glyphs end at y=%.0f, past the %.0fpx card" % [bottom, card.size.y])


func test_job_menu_stat_panel_shows_magic_defense_total() -> void:
	# The job-change comparison already prints an MDF delta. The STATS panel beside
	# it listed ATK/DEF/MAG/SPD/HP/MP and not the total, so the delta referred to a
	# stat the panel did not show.
	var c := _member("Mira", 16, 77)
	var menu = JOB.new()
	add_child_autofree(menu)
	menu.character = c
	var panel: Control = menu._create_stats_panel(Vector2(480, 640))
	add_child_autofree(panel)
	var labels := _labels(panel)
	assert_not_null(_label_named(labels, "MDF: 77"),
		"job STATS must show the magic defense total (MDF: 77), not only a comparison delta — got %s" % _texts(labels))
	assert_not_null(_label_named(labels, "MAG: 30"),
		"magic must stay MAG so an MDF row is not the magic row renamed")
	assert_not_null(_label_named(labels, "DEF: 16"),
		"defense must stay listed")
	var mdf := _label_named(labels, "MDF: 77")
	var abilities := _label_named(labels, "Job Abilities:")
	assert_not_null(abilities, "job abilities header must still render under the stats")
	if mdf != null and abilities != null:
		var mdf_bottom := mdf.position.y + mdf.get_theme_font("font").get_height(mdf.get_theme_font_size("font_size"))
		assert_gt(abilities.position.y, mdf_bottom,
			"Job Abilities at y=%.0f overlaps the MDF row which ends at y=%.0f" % [abilities.position.y, mdf_bottom])


func test_autobattle_character_panel_shows_magic_defense() -> void:
	var c := _member("Mira", 16, 77)
	var editor = EDITOR.new()
	editor.combatant = c
	editor.character_name = "Mira"
	editor._build_stats_panel()
	add_child_autofree(editor)
	var labels := _labels(editor)
	assert_not_null(_label_named(labels, "MDF: 77"),
		"the autobattle character panel lists ATK/DEF/MAG/SPD and omitted magic defense — got %s" % _texts(labels))
	var mdf := _label_named(labels, "MDF: 77")
	if mdf == null:
		return
	var panel: Control = editor._stats_panel
	var w := _text_width(mdf, mdf.text)
	assert_lte(mdf.position.x + w, panel.size.x,
		"MDF readout is %.0fpx wide starting at x=%.0f in a %.0fpx panel" % [w, mdf.position.x, panel.size.x])
	var bottom := mdf.position.y + mdf.get_theme_font("font").get_height(mdf.get_theme_font_size("font_size"))
	assert_lte(bottom, panel.size.y,
		"MDF readout ends at y=%.0f, below the %.0fpx panel" % [bottom, panel.size.y])


func _texts(labels: Array) -> String:
	var parts: PackedStringArray = []
	for lbl in labels:
		parts.append((lbl as Label).text)
	return " | ".join(parts)
