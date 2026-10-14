extends GutTest

## Text Size, 2026-10-14: four raw font sites, so the panel where a player decides whether to let the
## AI change the game's constants ignored the setting. Every box here is hand-laid, so the fonts alone
## are half of it -- and the body had `scroll_active = false` while the model's `reason` reaches it
## UNCAPPED (RebalanceDaemon:240 validates type, not length), so a long proposal was silently cut at
## the box edge at EVERY font size. There is no producer cap to sit on, so the arm for that pins
## REACHABILITY rather than a length.

const PanelScript := preload("res://src/ui/RebalanceReviewPanel.gd")
## DERIVED from the list the player actually drives, never copied. @cowir-controller measured a copy
## going stale the day a preset is added: the arm written to catch "it broke at 125%" then never
## visits the new rung. Reached through the class_name, so a rename is a PARSE error (EC=3, nothing
## ran) rather than an abort -- and deliberately WITHOUT a fallback default, because a fallback would
## pass every arm against a ladder nobody can select, which is worse than the copy it replaces.
const PRESETS: Array = SettingsMenu.TEXT_SIZE_PRESETS

## DERIVED, not typed out. My first version was a 1,100-character literal and a screen showed it
## FITS the body box at 0.8x and 1.0x (~217px of text in a 360px box) -- so the control that asserts
## it overflows would have red, and so would the reachability arm, at the two presets that matter
## most. A guessed worst case is the error my own record names; this one grows until it exceeds the
## LARGEST box any preset produces, measured at the SMALLEST font, so it overflows everywhere.
const REASON_SENTENCES: Array = [
	"The player has lost four consecutive encounters in the Whispering Cave against the same goblin pack.",
	"Each fight ended within six rounds, with the party entering at an average of 38 percent health.",
	"That is a pacing failure rather than a difficulty one: the cave's save point sits behind the encounter.",
	"So rather than reducing goblin damage outright I propose a smaller reduction with a lower encounter rate.",
	"The confidence is moderate because four encounters is a small sample for a claim about the whole region.",
	"The player may simply be experimenting with an under-levelled party, which the autobattle logs cannot separate.",
	"If the next three encounters resolve favourably, revert the damage reduction first and keep the rate.",
	"The latter addresses the save-point geometry; the former only masks what the geometry is doing.",
]

## The widest body box any preset produces, at the smallest body font: the bar the reason must clear.
func _long_reason() -> String:
	var font: Font = ThemeDB.fallback_font
	var w: float = float(_panel_rect(null).size.x) - PanelScript.BODY_INSET * 2.0
	var px: int = int(round(float(PanelScript.BODY_FONT) * 0.8))
	var target: float = _panel_rect(null).size.y * 2.0
	var out: String = ""
	var i: int = 0
	while i < 400:
		out += str(REASON_SENTENCES[i % REASON_SENTENCES.size()]) + " "
		i += 1
		if font.get_multiline_string_size(out, HORIZONTAL_ALIGNMENT_LEFT, w, px, -1,
				TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y > target:
			break
	return out.strip_edges()


var _orig_scale: float = 1.0
var _orig_daemon = null


func before_each() -> void:
	# Snapshot FIRST, so nothing below can skip it, and the daemon before the scale.
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null:
		if "rebalance_daemon" in gs:
			_orig_daemon = gs.rebalance_daemon
		if "text_size_scale" in gs:
			_orig_scale = float(gs.text_size_scale)


func after_each() -> void:
	# Restore the shared field LAST-in / FIRST-out: the daemon reference is the one another file reads.
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null:
		if "rebalance_daemon" in gs:
			gs.rebalance_daemon = _orig_daemon
		if "text_size_scale" in gs:
			gs.text_size_scale = _orig_scale


func _set_scale(scale: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale


func _settle() -> void:
	for _i in 3:
		await get_tree().process_frame


## A LOCAL daemon swapped into the one shared field, rather than mutating the live one's pending[].
## `_install(false)` installs an EMPTY one -- installing then clearing would reach into whatever
## daemon is actually there, which is the shared-object mutation this whole class is about.
func _install_proposal(reason: String, with_proposal: bool = true) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	assert_not_null(gs, "FIXTURE: GameState is absent, so the panel can never find a daemon")
	if gs == null or not ("rebalance_daemon" in gs):
		return
	var d := RebalanceDaemon.new()
	if not with_proposal:
		gs.rebalance_daemon = d
		return
	d.pending.append({
		"status": "needs_review",
		"verdict": "reduce_difficulty",
		"confidence": 0.62,
		"trigger": "repeated_defeat",
		"reason": reason,
		"deltas": [
			{"constant": "goblin_attack_multiplier", "multiplier": 0.9, "reason": "four losses in six rounds"},
			{"constant": "whispering_cave_encounter_rate", "multiplier": 0.85, "reason": "the save point sits behind the fight"},
		],
	})
	gs.rebalance_daemon = d


## Built AT the live scale: every derived box reads TextScale at call time.
func _panel(scale: float, reason: String = ""):
	if reason == "":
		reason = _long_reason()
	_install_proposal(reason)
	_set_scale(scale)
	var p = PanelScript.new()
	add_child_autofree(p)
	await _settle()
	return p


func _panel_rect(_p) -> Rect2:
	# The authored panel box, derived the same way the build path derives it -- NOT a node rect, which
	# would clamp up to its own content and move with the thing being contained.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = min(720.0, vp.x - 80)
	var h: float = min(480.0, vp.y - 80)
	return Rect2(Vector2((vp.x - w) / 2.0, (vp.y - h) / 2.0), Vector2(w, h))


# ---------------------------------------------------------------- the control


func test_the_fixture_really_puts_a_proposal_on_screen() -> void:
	var p = await _panel(1.0)
	assert_true(p._proposal_label.visible, "CONTROL: the proposal body is hidden, so every body arm measures nothing")
	assert_false(p._empty_label.visible, "CONTROL: the panel is showing its empty state, not a proposal")
	assert_string_contains(p._proposal_label.text, "reduce_difficulty", "CONTROL: the body must carry the real formatted proposal")
	assert_string_contains(p._proposal_label.text, "save point", "CONTROL: the long reason must reach the body")
	var font: Font = ThemeDB.fallback_font
	var px: int = p._proposal_label.get_theme_font_size("normal_font_size")
	# WORD_SMART's own flags: a RichTextLabel DEFAULTS to it and never sets autowrap_mode here, so
	# the default break flags would measure a wrap the node does not draw.
	var needed: float = font.get_multiline_string_size(p._proposal_label.get_parsed_text(),
			HORIZONTAL_ALIGNMENT_LEFT, p._proposal_label.size.x, px, -1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	assert_gt(needed, p._proposal_label.size.y,
		"CONTROL: the reason must exceed the body box at 100%% (%.0f vs %.0f), or the reachability arm proves nothing"
			% [needed, p._proposal_label.size.y])


# ---------------------------------------------------------------- the font grew


func test_all_four_text_sizes_follow_the_setting() -> void:
	var seen: Dictionary = {}
	for scale in PRESETS:
		var p = await _panel(scale)
		var row: Dictionary = {
			"header": p._header_label.get_theme_font_size("font_size"),
			"body": p._proposal_label.get_theme_font_size("normal_font_size"),
			"empty": p._empty_label.get_theme_font_size("font_size"),
			"hint": p._hint_label.get_theme_font_size("font_size"),
		}
		seen[scale] = row
		gut.p("scale %.2f  %s" % [scale, str(row)])
	var authored: Dictionary = {
		"header": PanelScript.HEADER_FONT, "body": PanelScript.BODY_FONT,
		"empty": PanelScript.EMPTY_FONT, "hint": PanelScript.HINT_FONT,
	}
	for key in authored.keys():
		assert_eq(int(seen[1.0][key]), int(authored[key]), "100%% must draw the authored %s size" % key)
		assert_gt(int(seen[2.0][key]), int(seen[1.0][key]),
			"the %s does not grow with Text Size (200%% gives %d, 100%% gives %d)" % [key, int(seen[2.0][key]), int(seen[1.0][key])])
		assert_lt(int(seen[0.8][key]), int(seen[1.0][key]), "the %s does not shrink with Text Size" % key)
		var prev: int = 0
		for scale in PRESETS:
			assert_gte(int(seen[scale][key]), prev, "the %s went backwards up the ladder at %.2fx" % [key, scale])
			prev = int(seen[scale][key])


## ONE-DIRECTIONAL, per cowir-main's final Text Size rule and @cowir-controller's 17966: an EQUALITY
## on the 100% look DEFENDS a default-setting defect -- theirs asserted "100% renders the authored 44
## exactly" while real content drew 56 in that cell at the shipped default. So a derived BOX may never
## fall BELOW what shipped (a smaller box clips text, which is the dangerous direction) and may never
## shrink as the setting rises; whether it is EXACTLY the shipped number is left to the content arms
## below, which measure overlap at every preset including 1.0x.
func test_no_derived_box_falls_below_what_shipped() -> void:
	var prev: Dictionary = {}
	for scale in PRESETS:
		var p = await _panel(scale)
		var r: Rect2 = _panel_rect(p)
		var got: Dictionary = {
			"header h": p._header_label.size.y,
			"body h": p._proposal_label.size.y,
			"hint h": p._hint_label.size.y,
		}
		var authored: Dictionary = {"header h": 28.0, "body h": r.size.y - 124.0, "hint h": 20.0}
		var checked: Array = []
		for key in got.keys():
			if key == "body h":
				# The body is the slack absorber: the fixed rows grow and it legitimately SHRINKS.
				# Its floor is its own arm (the reachability one); only the fixed rows are pinned here.
				continue
			assert_gte(float(got[key]), float(authored[key]) - 0.5,
				"at %.2fx %s is %.0f, BELOW the shipped %.0f -- a box under its authored size clips"
					% [scale, str(key), float(got[key]), float(authored[key])])
			if prev.has(key):
				assert_gte(float(got[key]), float(prev[key]) - 0.5,
					"at %.2fx %s SHRANK to %.0f from %.0f while the text got bigger"
						% [scale, str(key), float(got[key]), float(prev[key])])
			checked.append(str(key))
		# The loop can go EMPTY and still pass: rename either fixed row and it iterates over the one
		# exempted key, skips it, and asserts nothing. @cowir-adhoc's hollow-arm shape, so the
		# denominator is named rather than counted.
		for must in ["header h", "hint h"]:
			assert_true(checked.has(must),
				"at %.2fx the arm never examined %s — it checked only %s" % [scale, must, str(checked)])
		prev = got


## And the 100% POSITIONS, which are a different claim from the sizes: the panel must still open where
## it shipped. Positions cannot "legitimately grow", so these stay equalities.
func test_the_panel_opens_where_it_shipped_at_100_percent() -> void:
	var p = await _panel(1.0)
	var r: Rect2 = _panel_rect(p)
	for row in [
		["header y", p._header_label.position.y, r.position.y + 16.0],
		["body y", p._proposal_label.position.y, r.position.y + 56.0],
	]:
		assert_almost_eq(float(row[1]), float(row[2]), 0.5,
			"%s is %.0f at 100%% where the shipped literal gives %.0f" % [str(row[0]), float(row[1]), float(row[2])])


# ---------------------------------------------------------------- the text fits


func test_every_row_stays_inside_the_panel_at_every_preset() -> void:
	var screen: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for scale in PRESETS:
		var p = await _panel(scale)
		var r: Rect2 = _panel_rect(p)
		for pair in [["header", p._header_label], ["body", p._proposal_label], ["hint", p._hint_label]]:
			var n := pair[1] as Control
			gut.p("    %.2fx  %-7s y %.0f h %.0f  (panel %.0f..%.0f)" % [scale, str(pair[0]), n.position.y, n.size.y, r.position.y, r.end.y])
			assert_gte(n.position.y, r.position.y - 0.5,
				"at %.2fx the %s starts at %.0f, above the panel top at %.0f" % [scale, str(pair[0]), n.position.y, r.position.y])
			assert_lte(n.position.y + n.size.y, r.end.y + 0.5,
				"at %.2fx the %s ends at %.0f and the panel ends at %.0f" % [scale, str(pair[0]), n.position.y + n.size.y, r.end.y])
			assert_lte(n.position.y + n.size.y, screen.end.y + 0.5,
				"at %.2fx the %s ends at %.0f, off a %.0fpx screen" % [scale, str(pair[0]), n.position.y + n.size.y, screen.size.y])
		assert_lte(p._header_label.position.y + p._header_label.size.y, p._proposal_label.position.y + 0.5,
			"at %.2fx the header overlaps the proposal body" % scale)
		assert_lte(p._proposal_label.position.y + p._proposal_label.size.y, p._hint_label.position.y + 0.5,
			"at %.2fx the proposal body overlaps the control hint" % scale)


func test_the_empty_state_is_centred_on_its_own_height() -> void:
	for scale in PRESETS:
		_install_proposal("", false)
		_set_scale(scale)
		var p = PanelScript.new()
		add_child_autofree(p)
		await _settle()
		assert_true(p._empty_label.visible, "with no pending proposal the empty line must show")
		var r: Rect2 = _panel_rect(p)
		var centre: float = r.position.y + r.size.y / 2.0
		var box_mid: float = p._empty_label.position.y + p._empty_label.size.y / 2.0
		assert_almost_eq(box_mid, centre, 1.0,
			"at %.2fx the empty line's box centre is %.0f where the panel's is %.0f" % [scale, box_mid, centre])


# ---------------------------------------------------------------- reachability


## The real defect, and the arm cannot be a FIT arm: the model's reason is uncapped, so no box can be
## guaranteed to hold it. What a player is owed is that the whole proposal can be READ.
func test_an_uncapped_proposal_is_reachable_rather_than_cut() -> void:
	for scale in PRESETS:
		var p = await _panel(scale)
		var rtl: RichTextLabel = p._proposal_label
		assert_true(rtl.scroll_active,
			"at %.2fx the body cannot scroll, so everything past its box is silently unreadable" % scale)
		var bar := rtl.get_v_scroll_bar()
		assert_not_null(bar, "the body has no vertical scrollbar to reach the rest of the proposal")
		var reachable: float = bar.max_value
		gut.p("    %.2fx  body box %.0f  content %.0f  lines %d" % [scale, rtl.size.y, reachable, rtl.get_line_count()])
		assert_gt(reachable, rtl.size.y - 0.5,
			"at %.2fx the scroll range (%.0f) does not exceed the box (%.0f), so the long reason was never laid out"
				% [scale, reachable, rtl.size.y])


# ---------------------------------------------------------------- the floor


## Every member this file drives. _row_box and the four font consts have no other consumer.
func test_the_panel_still_has_what_this_file_drives() -> void:
	var p = PanelScript.new()
	add_child_autofree(p)
	for v in ["_header_label", "_proposal_label", "_empty_label", "_hint_label"]:
		assert_true(v in p, "RebalanceReviewPanel has no %s, so this file's fixture is stale" % v)
	assert_true(p.has_method("_build_ui"), "RebalanceReviewPanel has no _build_ui()")
	assert_gt(PanelScript._row_box(18, 28.0), 0.0, "_row_box() is gone")
	# An INSTANCE method of Script: on the class it is a parse error, so the file never loads.
	var consts: Dictionary = p.get_script().get_script_constant_map()
	for c in ["HEADER_FONT", "BODY_FONT", "EMPTY_FONT", "HINT_FONT", "BODY_HINT_GAP"]:
		assert_true(consts.has(c),
			"RebalanceReviewPanel no longer declares %s, which this file's expectations are built from" % c)

## The derivation's own floor: an EMPTY ladder makes every preset loop above iterate zero times and
## pass. Named rather than counted (a `size() > 3` control is @cowir-adhoc's hollow shape).
func test_the_preset_ladder_is_the_players_own() -> void:
	assert_false(PRESETS.is_empty(), "the ladder derived empty — every preset loop in this file would pass vacuously")
	assert_true(PRESETS.has(1.0), "the shipped default must be a rung the player can select: %s" % str(PRESETS))
	# ASCENDING matters here specifically: this file's growth arms walk the ladder asserting each
	# value is >= the one before, so an unsorted ladder would silently change what they assert rather
	# than break them (@cowir-overworld, who hit the same monotonic shape).
	var prev: float = -1.0
	for scale in PRESETS:
		assert_gt(float(scale), prev, "the ladder is not ascending at %s: %s" % [str(scale), str(PRESETS)])
		prev = float(scale)
	# NOT an equality against SettingsMenu: PRESETS IS that const, so comparing them is a tautology --
	# "an agreement check proves nothing when one side is derived from the other", my own banked note,
	# written into this file one message after reading @cowir-adhoc's derive-vs-pin distinction. The
	# two asserts above are the whole check: a derived ladder needs a FLOOR, not an agreement.
