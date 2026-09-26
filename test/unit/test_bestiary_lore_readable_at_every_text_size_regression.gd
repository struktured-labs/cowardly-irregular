extends GutTest

## The detail column measured each row as lines * line_height and clipped the
## lore to whatever pixels were left in the pane.
##
## Two consequences, both player-visible, both only at the text sizes above 100%:
##
##   * Line spacing is not in that product. Mordaine's one-shot hint wraps to
##     4 lines at 125%; the reserved box is 128px and the label's real minimum
##     is 137px, so the hint grows through the 6px gap and overlaps the lore.
##     The lore box left under it is 28px, shorter than one line, so it shows
##     0 lines. A second reflow does not heal it — the formula is stably short.
##   * Even with spacing included, at 150% half the defeated roster (50 of 106)
##     has fewer than 2 lore lines, and at 200% nearly every entry, defeated or
##     not, has 0. The column is taller than the pane. Clipping the paragraph
##     to the remainder is what made it 0.
##
## The lore's own box is now the height of its text, and the detail pane scrolls
## when that stack is taller than the screen. This drives every monster in
## monsters.json, defeated and not, at every Settings text-size preset.

const GuardSubject := preload("res://test/unit/helpers/guard_subject.gd")
const SCALES: Array = [0.8, 1.0, 1.25, 1.5, 2.0]


var _prior_text_scale: float = 1.0


func before_each() -> void:
	_prior_text_scale = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _prior_text_scale


func _build_menu() -> Node:
	var menu = load("res://src/ui/BestiaryMenu.gd").new()
	add_child_autofree(menu)
	await wait_frames(3)
	return menu


func _entry(id: String, defeated: bool) -> Dictionary:
	var data: Dictionary = BestiarySystem.get_monster_data(id)
	var hint := ""
	var reward = null
	var block = data.get("one_shot", null)
	if block is Dictionary:
		hint = str((block as Dictionary).get("setup_hint", ""))
		var item := str((block as Dictionary).get("reward_item", ""))
		if item != "":
			reward = item
	return {
		"id": id,
		"name": str(data.get("name", id)),
		"level": int(data.get("level", 1)),
		"epithet": BestiarySystem.get_epithet(id),
		"stats": data.get("stats", {}),
		"weaknesses": data.get("weaknesses", []),
		"resistances": data.get("resistances", []),
		"immunities": data.get("immunities", []),
		"flavor": BestiarySystem.get_flavor(id),
		"defeated": defeated,
		"drops": data.get("drop_table", []),
		"one_shot_reward": reward,
		"one_shot_hint": hint,
		"pools": BestiarySystem.get_pools_for_monster(id),
		"last_location": "Castle Harmonia",
		"exp_reward": int(data.get("exp_reward", 0)),
		"gold_reward": int(data.get("gold_reward", 0)),
		"defeat_count": 4 if defeated else 0,
	}


func _row_labels(menu: Node) -> Array:
	return [
		menu.get("_detail_name"), menu.get("_detail_epithet"), menu.get("_detail_level"),
		menu.get("_detail_stats"), menu.get("_detail_weak"), menu.get("_detail_immune"),
		menu.get("_detail_resist"), menu.get("_detail_rewards"), menu.get("_detail_drops"),
		menu.get("_detail_tactic"), menu.get("_detail_flavor"),
	]


func test_lore_is_readable_or_scrollable_for_every_monster_at_every_text_size() -> void:
	var raw := FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "monsters.json must parse")
	if not (parsed is Dictionary):
		return
	var ids: Array = (parsed as Dictionary).keys()
	assert_gt(ids.size(), 50, "the roster must be the live monster list, got %d" % ids.size())
	var mordaine: Dictionary = (parsed as Dictionary).get("chancellor_mordaine", {})
	var mordaine_hint := ""
	var block = mordaine.get("one_shot", null)
	if block is Dictionary:
		mordaine_hint = str((block as Dictionary).get("setup_hint", ""))
	assert_gt(mordaine_hint.length(), 80,
		"Mordaine's one-shot hint is the wrapping case this guard exists for — got %d chars" % mordaine_hint.length())

	var failures: Array = []
	var saw_mordaine_hint := false
	for scale in SCALES:
		GameState.text_size_scale = scale
		var menu = await _build_menu()
		var scroll = menu.get("_detail_scroll")
		var flavor_probe = menu.get("_detail_flavor")
		assert_ne(scroll, null, "detail scroll must exist at scale %s" % scale)
		assert_ne(flavor_probe, null, "flavor label must exist at scale %s" % scale)
		if scroll == null or flavor_probe == null:
			continue
		for defeated in [true, false]:
			for id in ids:
				if typeof((parsed as Dictionary)[id]) != TYPE_DICTIONARY:
					continue
				menu.set("_entries", [_entry(str(id), defeated)])
				menu.set("_selected", 0)
				menu.call("_refresh_detail")
				await wait_frames(1)
				var flavor: Label = menu.get("_detail_flavor")
				var tactic: Label = menu.get("_detail_tactic")
				var labels := _row_labels(menu)
				var where := "scale %s %s defeated=%s" % [scale, id, defeated]
				if str(id) == "chancellor_mordaine" and defeated and str(tactic.text).contains(mordaine_hint.substr(0, 24)):
					saw_mordaine_hint = true
				if flavor.position.y > 2500.0:
					failures.append("%s flavor y=%s — row height followed the temporary tall box" % [where, flavor.position.y])
				for i in range(labels.size()):
					var a: Label = labels[i]
					if a == null:
						continue
					if a.get_minimum_size().y > a.size.y + 1.0:
						failures.append("%s %s grew past its row (min %s > size %s)" % [where, a.name, a.get_minimum_size().y, a.size.y])
					var a_rect := Rect2(a.position, a.size)
					for j in range(i + 1, labels.size()):
						var b: Label = labels[j]
						if b == null:
							continue
						if a_rect.intersects(Rect2(b.position, b.size)):
							failures.append("%s overlap %s vs %s" % [where, a_rect, Rect2(b.position, b.size)])
				if flavor.text.strip_edges() == "":
					continue
				var lines: int = flavor.get_line_count()
				var want: int = mini(2, lines)
				var spacing := float(flavor.get_theme_constant("line_spacing"))
				var need_h := flavor.get_line_height() * float(want) + spacing * float(maxi(0, want - 1))
				if flavor.size.y + 1.0 < need_h or flavor.get_visible_line_count() < want:
					failures.append("%s lore shows %s/%s lines in a %spx box (need %s)" % [
						where, flavor.get_visible_line_count(), lines, flavor.size.y, need_h])
				var needed := maxf(0.0, flavor.position.y + need_h - scroll.size.y)
				if needed > 1.0:
					scroll.scroll_vertical = 1000000
					var max_offset := float(scroll.scroll_vertical)
					scroll.scroll_vertical = 0
					if max_offset + 1.0 < needed:
						failures.append("%s lore is not scrollable (need offset %s, scroll reaches %s)" % [where, needed, max_offset])
		menu.queue_free()
	assert_true(saw_mordaine_hint, "the sweep must render Mordaine's authored one-shot hint on the defeated entry")
	var shown: Array = failures.slice(0, 8)
	assert_eq(failures.size(), 0,
		"%d bestiary detail failures across every text size and monster (first %d): %s" % [failures.size(), shown.size(), shown])


## ⛔ THE SILENT-PASS FLOOR. Names are derived from this file's own text.
func test_every_member_this_guard_drives_by_name_exists() -> void:
	var subject: Object = load("res://src/ui/BestiaryMenu.gd").new()
	add_child_autofree(subject)
	var calls: Dictionary = GuardSubject.audit_calls("res://test/unit/test_bestiary_lore_readable_at_every_text_size_regression.gd", subject)
	var props: Dictionary = GuardSubject.audit_properties("res://test/unit/test_bestiary_lore_readable_at_every_text_size_regression.gd", subject)
	assert_eq((str(calls["why"]) + " " + str(props["why"])).strip_edges(), "",
		"the comment strip failed: %s %s" % [calls["why"], props["why"]])
	assert_gt(int(calls["found"]) + int(props["found"]), 0,
		"VOID: no .call or .get name found in this file")
	assert_eq(calls["missing"], [],
		"this guard drives those methods by name and the subject no longer has them: %s" % [calls["missing"]])
	assert_eq(props["missing"], [],
		"this guard reads those properties by name and the subject no longer has them: %s" % [props["missing"]])
