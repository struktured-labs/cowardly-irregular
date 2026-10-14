extends Control
class_name AutogrindSummary

signal dismissed()

const BG_COLOR = Color(0.05, 0.04, 0.08, 0.92)
const PANEL_BG = Color(0.06, 0.05, 0.10)
const BORDER_LIGHT = Color(0.5, 0.4, 0.6)
const BORDER_SHADOW = Color(0.2, 0.15, 0.25)
const TEXT_COLOR = Color(0.9, 0.9, 0.9)
const HEADER_COLOR = Color(1.0, 1.0, 0.4)
const LABEL_COLOR = Color(0.6, 0.6, 0.7)
## Same blue the console uses for advice, so the two surfaces read as one voice.
const ADVICE_COLOR = Color(0.624, 0.827, 1.0)
## One source for the size the header RESERVES and the label DRAWS at -- two numbers drifted here before.
const ADVICE_FONT_SIZE := 11
const VALUE_COLOR = Color(0.4, 0.9, 0.4)
const BAD_COLOR = Color(0.9, 0.3, 0.3)
const BADGE_NEW_COLOR = Color(1.0, 0.85, 0.2)
const BADGE_EARNED_COLOR = Color(0.55, 0.55, 0.65)
const BADGE_BG_NEW = Color(0.15, 0.13, 0.06)
const BADGE_BG_EARNED = Color(0.08, 0.08, 0.12)

const AutogrindAchievementsScript = preload("res://src/autogrind/AutogrindAchievements.gd")

var _stats: Dictionary = {}
var _reason: String = ""


## Heartbeat the "autogrind_summary" input lock GameLoop pushes for us. This is a modal the player
## READS, so it routinely outlives InputLockManager's 10s stale expiry — which would reap the lock
## and hand movement back with the summary still on screen, exactly the 2026-07-14 playtest bug the
## lock was added to prevent. CutsceneDirector and OverworldController already heartbeat for the same
## reason; this holder was added after both and never got one. Re-pushing refreshes the timestamp.
func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	var ilm = get_tree().root.get_node_or_null("InputLockManager")
	if ilm:
		ilm.push_lock("autogrind_summary")


## Releasing here as well as on `dismissed` — a heartbeated lock can no longer be reaped by the stale
## timeout, so if this node is freed by anything other than a dismiss (scene change, teardown) the
## lock would be held forever and the player would be frozen with no modal to explain it.
func _exit_tree() -> void:
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm:
		ilm.pop_lock("autogrind_summary")


func setup(stats: Dictionary, reason: String) -> void:
	_stats = stats
	_reason = reason
	call_deferred("_build_ui")


## Standalone wording, NOT the start refusal's clauses -- those follow a situation sentence and do not read alone.
func _interrupt_advice(rule: String) -> String:
	match rule:
		"hp_threshold":
			return "Heal before grinding again, or lower \"Stop at HP\" in Options."
		"party_death":
			return "Revive them, or turn \"Stop on Death\" off in Options."
		"item_depleted":
			return "Restock healing items, or turn \"Stop when Out of Items\" off in Options."
		"max_battles":
			return "Raise \"Stop after\" in Options to grind longer."
		"corruption_limit":
			return "No Options row changes this one -- it guards system collapse. Corruption clears with a fresh session."
	return ""


## A text size GROWS a box and must never shrink one below the authored layout: at 0.8x the glyphs do
## not shrink in proportion, so a scaled-down box clips text the shipped layout fits.
func _grew(base: float) -> float:
	return maxf(base, float(TextScale.scaled(int(round(base)))))


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	mouse_filter = Control.MOUSE_FILTER_STOP

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Build stats data first to compute panel height
	var elapsed = _stats.get("elapsed_seconds", 0.0)
	var dur_min = int(elapsed) / 60
	var dur_sec = int(elapsed) % 60
	## Shared floor — see AutogrindSystem.MIN_RATE_WINDOW_MINUTES.
	var bpm = _stats.get("battles_won", 0) / maxf(elapsed / 60.0, AutogrindSystem.MIN_RATE_WINDOW_MINUTES)

	var stats_data = [
		{"label": "Battles Won", "value": str(_stats.get("battles_won", 0)), "color": VALUE_COLOR},
		{"label": "Total EXP", "value": str(_stats.get("total_exp", 0)), "color": VALUE_COLOR},
		{"label": "Total Gold", "value": str(_stats.get("total_gold", 0)), "color": VALUE_COLOR},
		{"label": "Time Elapsed", "value": "%d:%02d" % [dur_min, dur_sec], "color": VALUE_COLOR},
		{"label": "Battles/Min", "value": "%.1f" % bpm, "color": VALUE_COLOR},
		{"label": "Consecutive Wins", "value": str(_stats.get("consecutive_wins", 0)), "color": VALUE_COLOR},
		{"label": "Efficiency", "value": "%.1fx" % _stats.get("efficiency", 1.0), "color": VALUE_COLOR},
		{"label": "Corruption", "value": "%.2f / %.1f" % [_stats.get("corruption", 0.0), _stats.get("corruption_threshold", AutogrindSystem.DEFAULT_CORRUPTION_THRESHOLD)], "color": BAD_COLOR if _stats.get("corruption", 0.0) > 2.0 else VALUE_COLOR},
		{"label": "Save Corruption", "value": _format_save_corruption(_stats), "color": _save_corruption_color(_stats)},
		{"label": "Adaptation", "value": "%.2f" % _stats.get("adaptation", 0.0), "color": LABEL_COLOR},
		{"label": "Collapses", "value": str(_stats.get("collapse_count", 0)), "color": BAD_COLOR if _stats.get("collapse_count", 0) > 0 else VALUE_COLOR},
		## A meta boss was reported ONLY by the console, so one spawned during a headless grind with
		## the console closed was invisible at the moment AND at session end. The Summary is the
		## surface that always runs.
		## The console shows which rules fired, and the console is exactly what is NOT open during a
		## grind — the same gap that hid a dead stop rule, an unseen collapse and an unseen meta
		## boss. The Summary always runs, so a player whose rules did nothing learns it here.
		{"label": "Your Rules", "value": _rules_summary(), "color": BAD_COLOR if _rules_did_nothing() else VALUE_COLOR},
		{"label": "Meta-Bosses", "value": "%d beaten / %d met" % [_stats.get("meta_bosses_defeated", 0), _stats.get("meta_bosses_spawned", 0)], "color": VALUE_COLOR},
	]

	var rules_at: int = 0
	for i in stats_data.size():
		if stats_data[i]["label"] == "Your Rules":
			rules_at = i + 1
	for row in _rule_noop_rows():
		stats_data.insert(rules_at, row)
		rules_at += 1

	# Per-character EXP breakdown
	var char_exp = _stats.get("per_character_exp", {})
	if not char_exp.is_empty():
		for char_name in char_exp:
			stats_data.append({"label": "  %s EXP" % char_name, "value": "+%d" % char_exp[char_name], "color": Color(0.5, 0.8, 1.0)})

	# Items consumed breakdown
	## ONE formatter. This was the fourth copy of "<Name> x<N>, ..." in the lane; .301 extracted
	## AutogrindSystem.format_items_consumed after a third copy shipped RAW IDS to the History screen,
	## and this one survived because it happened to agree. Verified identical on five cases before
	## converting — empty, one, many, JSON floats, unknown id — so this changes no output.
	stats_data.append({
		"label": "Items Used",
		"value": AutogrindSystem.format_items_consumed(_stats.get("items_consumed", {})),
		## Fitted against the real font once the row's box width is known; a 5-item session needed 438 px in a 170-px box.
		"fit_items": _stats.get("items_consumed", {}),
		"color": LABEL_COLOR,
	})

	stats_data.append({"label": "Fatigue Events", "value": str(_stats.get("fatigue_events_triggered", 0)), "color": LABEL_COLOR})
	var time_mult = _stats.get("time_multiplier", 1.0)
	stats_data.append({"label": "Time Bonus", "value": "%.1fx" % time_mult, "color": VALUE_COLOR})

	var grade = _compute_grade()
	stats_data.append({"label": "SESSION GRADE", "value": grade["letter"], "color": grade["color"]})

	var permadead = _stats.get("permadead", [])
	if permadead.size() > 0:
		stats_data.append({"label": "PERMADEAD", "value": ", ".join(permadead), "color": BAD_COLOR})

	# newly earned this run render gold; already-unlocked render dim.
	var gs := _get_game_state()
	var split := AutogrindAchievementsScript.check_and_award(_stats, gs)
	## check_and_award above still runs as a backstop (a threshold crossed on the final battle,
	## or a grind that ended before any battle hook ran).
	var tiers := split_session_new(split, _stats.get("achievements_earned_this_session", []))
	var newly: Array = tiers[0]
	var previously: Array = tiers[1]
	var all_badges: Array = newly + previously

	# Compute panel height from row count
	var row_h = _grew(26.0)
	## The panel holds the text, so it widens with it -- clamped to the viewport, and floored at the
	## authored 520 so 0.8x and 1.0x are unchanged.
	var panel_w = minf(_grew(520.0), vp_size.x - 40.0)
	# Pre-compute badge wrap so the panel grows to fit — the old flat 40px
	# assumption silently dropped chips past panel_w-40 (a full catalog earned
	# in one session would truncate to ~4 badges on a 520 panel).
	var badge_layout: Array = _layout_badges(all_badges, panel_w)
	var badge_rows: int = 0
	if badge_layout.size() > 0:
		badge_rows = int(badge_layout[badge_layout.size() - 1]["row"]) + 1
	var badge_row_h: float = _grew(40.0) * badge_rows
	var badge_header_h := _grew(20.0) if all_badges.size() > 0 else 0.0
	var advice: String = _interrupt_advice(str(AutogrindSystem.last_interrupt_rule))
	## Header is 68 px bare, 86 with the advice line; every stats offset derives from it so the panel cannot overflow.
	## Derived from the WRAPPED height, against the NARROW panel width -- 520 is the worst case and
	## panel_w only ever widens below, so over-reserving is the safe direction and overlap is not.
	var advice_h: float = 0.0
	if advice != "":
		## ⛔ THE SIZE AND THE BREAK FLAGS BOTH HAVE TO MATCH THE LABEL THIS RESERVES FOR. It is
		## AUTOWRAP_WORD_SMART, whose rule is MANDATORY|WORD_BOUND|ADAPTIVE, and its font is scaled
		## below. A raw size here was consistent only while the label's was raw too, and the default
		## flags were inert only while no token exceeded the width -- measured elsewhere today, a
		## mismatched pair derived a 120px box for 140px of text, and it bit at 125%, not just at 2.0x.
		advice_h = ThemeDB.fallback_font.get_multiline_string_size(
			advice, HORIZONTAL_ALIGNMENT_LEFT, panel_w - 40.0, TextScale.scaled(ADVICE_FONT_SIZE),
			-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	var head_h: float = _grew(68.0) if advice == "" else _grew(56.0) + maxf(advice_h, float(TextScale.scaled(ADVICE_FONT_SIZE))) + _grew(14.0)
	var rows_per_col: int = stats_data.size()
	var panel_h = head_h + rows_per_col * row_h + badge_header_h + badge_row_h + 50.0
	## A long session (full party, rule notes, permadeath, badges) stacked past 720 px and hid the grade and the achievements.
	var max_h: float = vp_size.y - 40
	if panel_h > max_h:
		## ⛔ NEVER NARROWER than the width the advice was measured against: the comment above says
		## "panel_w only ever widens below", and scaling the initial 520 would have broken that --
		## at 2.0x the scaled start (1040) exceeds this branch's old 1000, so the advice would have
		## been reserved for a wider panel than the label then got, and wrapped past its reservation.
		panel_w = maxf(panel_w, minf(vp_size.x - 80, _grew(1000.0)))
		## ⛔ TWO COLUMNS ONLY IF A COLUMN CAN HOLD A ROW. At 2.0x a 510px column cannot: the value box
		## starts before the label ends and "Battles Won" draws over "148" (measured). One tall column
		## is worse vertically and the row cap below handles that; an overlapping row is unreadable.
		if (panel_w - 20.0) / 2.0 >= _grew(VALUE_BOX_LEFT) + _grew(170.0) + _grew(30.0):
			rows_per_col = int(ceil(stats_data.size() / 2.0))
		badge_layout = _layout_badges(all_badges, panel_w)
		badge_rows = int(badge_layout[badge_layout.size() - 1]["row"]) + 1 if badge_layout.size() > 0 else 0
		badge_row_h = _grew(40.0) * badge_rows
		panel_h = head_h + rows_per_col * row_h + badge_header_h + badge_row_h + 50.0
		if panel_h > max_h:
			row_h = maxf(18.0, (max_h - head_h - badge_header_h - badge_row_h - 50.0) / maxf(rows_per_col, 1))
			panel_h = head_h + rows_per_col * row_h + badge_header_h + badge_row_h + 50.0
	panel_h = min(panel_h, max_h)
	var col_w: float = panel_w if rows_per_col >= stats_data.size() else (panel_w - 20.0) / 2.0
	## ⛔ THE ROW FONT FOLLOWS THE ROW. row_h shrinks (floor 18) when a long session will not fit the
	## screen, and a scaled font in a shrunken row overlaps the row below. Capped here, so the setting
	## is honoured up to the point the panel can take and every row stays readable past it -- the
	## boundary is pinned by the guard rather than left to be discovered.
	var stats_px: int = clampi(int(row_h) - 6, 8, TextScale.scaled(13))

	var panel = Control.new()
	panel.position = Vector2((vp_size.x - panel_w) / 2, (vp_size.y - panel_h) / 2)
	panel.size = Vector2(panel_w, panel_h)
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel.size
	panel.add_child(panel_bg)
	_add_border(panel, panel.size)

	var title = Label.new()
	title.text = "AUTOGRIND COMPLETE"
	title.position = Vector2(_grew(20.0), _grew(12.0))
	title.add_theme_font_size_override("font_size", TextScale.scaled(18))
	title.add_theme_color_override("font_color", HEADER_COLOR)
	panel.add_child(title)

	var reason_lbl = Label.new()
	reason_lbl.text = "Stopped: %s" % _reason
	reason_lbl.position = Vector2(_grew(20.0), _grew(38.0))
	reason_lbl.add_theme_font_size_override("font_size", TextScale.scaled(12))
	reason_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	panel.add_child(reason_lbl)

	if advice != "":
		var advice_lbl = Label.new()
		## WRAP, not clip: this sentence is the remedy, and half of it is no remedy. autowrap, text
		## and the font override all precede `size`, and `size` precedes add_child -- a wrapping Label
		## that enters the tree at width 0 caches a minimum the assignment can no longer get under.
		advice_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		advice_lbl.text = advice
		advice_lbl.add_theme_font_size_override("font_size", TextScale.scaled(ADVICE_FONT_SIZE))
		advice_lbl.add_theme_color_override("font_color", ADVICE_COLOR)
		advice_lbl.position = Vector2(_grew(20.0), _grew(56.0))
		advice_lbl.size = Vector2(panel_w - _grew(40.0), maxf(advice_h, float(TextScale.scaled(ADVICE_FONT_SIZE))))
		panel.add_child(advice_lbl)

	var sep = ColorRect.new()
	sep.color = BORDER_LIGHT
	sep.position = Vector2(16, head_h - _grew(10.0))
	sep.size = Vector2(panel_w - _grew(32.0), 1)
	panel.add_child(sep)

	var y = head_h
	for i in stats_data.size():
		var s: Dictionary = stats_data[i]
		var col: int = i / maxi(rows_per_col, 1)
		var x0: float = col * col_w
		y = head_h + (i % maxi(rows_per_col, 1)) * row_h
		var lbl = Label.new()
		lbl.text = s["label"]
		lbl.position = Vector2(x0 + _grew(30.0), y)
		lbl.add_theme_font_size_override("font_size", stats_px)
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		panel.add_child(lbl)

		var val = Label.new()
		## Set BEFORE the text: an unclipped Label's minimum width is its whole string, and a size assigned
		## under that minimum is silently clamped UP — which is how a 310-px box became a 540-px one off-panel.
		val.clip_text = true
		val.add_theme_font_size_override("font_size", stats_px)
		val.add_theme_color_override("font_color", s["color"])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.text = s["value"]
		## The box used to be a fixed 170 px while the panel offers far more, so a long value ran off the SCREEN.
		var box_w: float = maxf(_grew(170.0), col_w - _grew(VALUE_BOX_LEFT) - _grew(30.0))
		val.position = Vector2(x0 + col_w - _grew(30.0) - box_w, y)
		val.size = Vector2(box_w, _grew(20.0))
		panel.add_child(val)
		if s.has("fit_items"):
			val.text = _fit_items(val, s["fit_items"], box_w)
			val.size = Vector2(box_w, _grew(20.0))

	y = head_h + rows_per_col * row_h

	if all_badges.size() > 0:
		## ⛔ MEASURED AT 2.0x: a 22-row session needs 737px of content in a panel the screen caps at
		## 680, with row_h already at its 18px floor -- so the chips had nowhere to go and drew over
		## "Press X or Z to continue", the one control the player needs. Rows that fit are drawn; the
		## rest are COUNTED IN THE HEADER, which costs no vertical space and loses no information.
		var chip_h := _grew(30.0)
		var room: float = panel.size.y - _grew(40.0) - (y + badge_header_h)
		var rows_fit: int = maxi(0, int(floorf(room / _grew(40.0))))
		var shown: int = 0
		for placement in badge_layout:
			if int(placement["row"]) < rows_fit:
				shown += 1
		var not_shown: int = all_badges.size() - shown
		var badge_header = Label.new()
		badge_header.text = "ACHIEVEMENTS  (%d new)" % newly.size() if newly.size() > 0 else "ACHIEVEMENTS"
		if not_shown > 0:
			badge_header.text += "  (+%d not shown)" % not_shown
		badge_header.position = Vector2(_grew(20.0), y)
		badge_header.add_theme_font_size_override("font_size", TextScale.scaled(12))
		badge_header.add_theme_color_override("font_color", BADGE_NEW_COLOR if newly.size() > 0 else LABEL_COLOR)
		panel.add_child(badge_header)
		y += badge_header_h

		for placement in badge_layout:
			if int(placement["row"]) >= rows_fit:
				continue
			var a: Dictionary = placement["badge"]
			var chip_x: float = placement["x"]
			var chip_y: float = y + float(placement["row"]) * _grew(40.0)
			var chip_w: float = placement["w"]
			var is_new: bool = a in newly
			var chip_bg = ColorRect.new()
			chip_bg.color = BADGE_BG_NEW if is_new else BADGE_BG_EARNED
			chip_bg.position = Vector2(chip_x, chip_y)
			chip_bg.size = Vector2(chip_w, chip_h)
			panel.add_child(chip_bg)

			var chip_lbl = Label.new()
			chip_lbl.text = "%s %s" % [a.get("icon", "*"), a.get("name", a.get("id", "?"))]
			chip_lbl.position = Vector2(chip_x + _grew(6.0), chip_y + _grew(6.0))
			chip_lbl.add_theme_font_size_override("font_size", TextScale.scaled(CHIP_FONT_SIZE))
			chip_lbl.add_theme_color_override("font_color", BADGE_NEW_COLOR if is_new else BADGE_EARNED_COLOR)
			chip_lbl.tooltip_text = a.get("description", "")
			panel.add_child(chip_lbl)



	var footer_sep = ColorRect.new()
	footer_sep.color = BORDER_LIGHT
	footer_sep.position = Vector2(16, panel_h - _grew(40.0))
	footer_sep.size = Vector2(panel_w - _grew(32.0), 1)
	panel.add_child(footer_sep)

	var dismiss_lbl = Label.new()
	## Derived, not frozen: this screen accepts ui_accept OR ui_cancel (see _input), and "A"/"B"
	## name buttons no PlayStation or Xbox pad carries. Guarded because test bootstrap can reach
	## here before the autoload exists; the fallback letters are only seen in that window.
	var g_ok: String = "Z"
	var g_no: String = "X"
	if InputProfileManager:
		g_ok = InputProfileManager.hint_for_action("ui_accept")
		g_no = InputProfileManager.hint_for_action("ui_cancel")
	dismiss_lbl.text = "Press %s or %s to continue" % [g_ok, g_no]
	dismiss_lbl.position = Vector2(0, panel_h - _grew(30.0))
	dismiss_lbl.size = Vector2(panel_w, _grew(20.0))
	dismiss_lbl.add_theme_font_size_override("font_size", TextScale.scaled(12))
	dismiss_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	dismiss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(dismiss_lbl)


## Tick 135: thin wrapper around ItemNameResolver.
	# Right-click dismisses, matching the convention on 29 other screens.
	MenuMouseHelper.add_right_click_cancel(self, func() -> void:
		dismissed.emit())


## Authored rules vs how many ever won a check. "0 of 4" after hundreds of checks is a player
## whose grind ran on the built-in interrupts alone, which is worth knowing and is invisible
## anywhere else once the console is closed.
func _rules_summary() -> String:
	var authored: int = int(_stats.get("rules_authored", 0))
	var fired: int = int(_stats.get("rules_that_fired", 0))
	var checks: int = int(_stats.get("rule_checks", 0))
	if authored <= 0:
		return "none authored"
	if checks <= 0:
		return "%d authored, never evaluated" % authored
	return "%d of %d fired (%d checks)" % [fired, authored, checks]


## Where a value box may start, measured from the column's left edge: clear of the longest authored row label.
const VALUE_BOX_LEFT := 150.0

## The chip font, named once: _measure_badge_width and the chip Label must not drift apart.
const CHIP_FONT_SIZE := 12


## Drops trailing entries until the list fits `max_w` in the label's OWN font, so the cap follows the font rather than a guess.
func _fit_items(val: Label, items: Dictionary, max_w: float) -> String:
	var parts: Array = AutogrindSystem.items_consumed_parts(items)
	if parts.is_empty():
		return "None"
	var font: Font = val.get_theme_font("font")
	var size: int = val.get_theme_font_size("font_size")
	if font == null:
		return AutogrindSystem.format_items_consumed(items)
	for keep in range(parts.size(), 0, -1):
		var text: String = AutogrindSystem.format_items_consumed(items, 0 if keep == parts.size() else keep)
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			return text
	return "%d items" % parts.size()


const RULE_NOOP_ROWS_MAX := 3
const RULE_NOOP_REASON_CHARS := 36


## A rule that fired and changed nothing (no potions, a silenced healer) counted as fired above; these rows say what stopped it.
func _rule_noop_rows() -> Array:
	var noops: Dictionary = _stats.get("rule_noops", {})
	var reasons: Array = noops.keys()
	reasons.sort_custom(func(a, b): return int(noops[a]) > int(noops[b]))
	var rows: Array = []
	for reason in reasons.slice(0, RULE_NOOP_ROWS_MAX):
		var text: String = str(reason)
		if text.length() > RULE_NOOP_REASON_CHARS:
			text = text.substr(0, RULE_NOOP_REASON_CHARS - 1) + "…"
		rows.append({"label": "  " + text, "value": "did nothing ×%d" % int(noops[reason]), "color": BAD_COLOR})
	return rows


## Only flag the case that is actually a problem: rules exist, they were evaluated many times, and
## not one of them ever won. Zero checks is "not measured", not "broken" — the same denominator
## rule the console readout uses.
func _rules_did_nothing() -> bool:
	return int(_stats.get("rules_authored", 0)) > 0 \
		and int(_stats.get("rule_checks", 0)) > 0 \
		and int(_stats.get("rules_that_fired", 0)) == 0


func _format_save_corruption(stats: Dictionary) -> String:
	var current: float = float(stats.get("save_corruption", 0.0))
	var delta: float = float(stats.get("save_corruption_delta", 0.0))
	if delta > 0.0001:
		return "%.3f (+%.3f this session)" % [current, delta]
	return "%.3f" % current


func _save_corruption_color(stats: Dictionary) -> Color:
	var current: float = float(stats.get("save_corruption", 0.0))
	# GameState.corruption_level is clamped 0.0-1.0; >0.6 is the "save at risk" band.
	if current > 0.6:
		return BAD_COLOR
	if current > 0.3:
		return Color(1.0, 0.85, 0.2)
	return VALUE_COLOR


func _get_game_state() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("GameState")
	return null


## Returns [newly, previously]. "New" means earned THIS session, NOT "unflagged until now":
## the per-battle award has already written every flag by the time this screen builds, so the
## flag test alone would render a freshly-earned badge dim. session_ids comes from the stats dict.
static func split_session_new(split: Array, session_ids: Array) -> Array:
	var newly: Array = split[0].duplicate()
	var previously: Array = []
	for a in split[1]:
		if str(a.get("id", "")) in session_ids:
			newly.append(a)
		else:
			previously.append(a)
	return [newly, previously]


## ⛔ MEASURED, NOT ESTIMATED. This was `text.length() * 6.5`, an em-per-char guess at a fixed font
## 12: blind to the setting, so scaled chips kept their old width and drew over each other from
## 1.25x -- and blind to the glyphs, so a wide name could already overlap at the shipped size. Three
## lanes were corrected today for exactly this instrument; `len()` is a proxy for width, not width.
func _measure_badge_width(a: Dictionary) -> float:
	var text := "%s %s" % [a.get("icon", "*"), a.get("name", a.get("id", "?"))]
	var px: int = TextScale.scaled(CHIP_FONT_SIZE)
	var w: float = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	return maxf(_grew(72.0), w + _grew(16.0))


## Precompute wrap positions so panel_h can grow to fit all chips.
## Returns [{badge, row, x, w}] — one entry per input badge, never fewer.
func _layout_badges(all_badges: Array, panel_w: float) -> Array:
	var chip_pad := _grew(8.0)
	var start_x := _grew(20.0)
	var wrap_x := panel_w - _grew(20.0)
	var out: Array = []
	var row := 0
	var x := start_x
	for a in all_badges:
		var w: float = _measure_badge_width(a)
		# Only wrap when there's already content on this row — a very wide chip
		# always occupies its own row starting at start_x rather than getting dropped.
		if x + w > wrap_x and x > start_x:
			row += 1
			x = start_x
		out.append({"badge": a, "row": row, "x": x, "w": w})
		x += w + chip_pad
	return out


func _compute_grade() -> Dictionary:
	var battles = _stats.get("battles_won", 0)
	var collapses = _stats.get("collapse_count", 0)
	if battles >= 50 and collapses == 0:
		return {"letter": "S", "color": Color(1.0, 0.85, 0.0)}  # Gold
	elif battles >= 30 and collapses <= 1:
		return {"letter": "A", "color": Color(0.4, 0.9, 0.4)}  # Green
	elif battles >= 15:
		return {"letter": "B", "color": Color(0.4, 0.7, 1.0)}  # Blue
	elif battles > 0:
		return {"letter": "C", "color": Color(0.7, 0.7, 0.7)}  # Gray
	else:
		return {"letter": "F", "color": Color(0.9, 0.3, 0.3)}  # Red


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		dismissed.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_Z, KEY_X, KEY_ENTER, KEY_ESCAPE]:
			dismissed.emit()
			get_viewport().set_input_as_handled()


func _add_border(parent: Control, panel_size: Vector2) -> void:
	var top = ColorRect.new()
	top.color = BORDER_LIGHT
	top.size = Vector2(panel_size.x, 2)
	parent.add_child(top)

	var left_b = ColorRect.new()
	left_b.color = BORDER_LIGHT
	left_b.size = Vector2(2, panel_size.y)
	parent.add_child(left_b)

	var bottom = ColorRect.new()
	bottom.color = BORDER_SHADOW
	bottom.position = Vector2(0, panel_size.y - 2)
	bottom.size = Vector2(panel_size.x, 2)
	parent.add_child(bottom)

	var right_b = ColorRect.new()
	right_b.color = BORDER_SHADOW
	right_b.position = Vector2(panel_size.x - 2, 0)
	right_b.size = Vector2(2, panel_size.y)
	parent.add_child(right_b)
