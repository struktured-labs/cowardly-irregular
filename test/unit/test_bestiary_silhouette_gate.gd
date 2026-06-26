extends GutTest

## tick 194: bestiary visual gate matches the text intel gate.
##
## Tick 147's docstring promised "Player sees the SILHOUETTE +
## name + level (gleaned from sighting)" for seen-but-not-defeated
## entries. Stats / weaknesses / resistances / rewards / drops
## were correctly gated to "???" until defeat. But the SPRITE
## shipped full-color — the visual reveal happened the moment
## the monster was encountered.
##
## Fix: modulate the detail sprite to a dark blue-gray
## SILHOUETTE_COLOR when undefeated, full Color.WHITE on defeat.
## Classic Pokédex-style "you've seen it, now go kill one to
## see its true form".

const BESTIARY_MENU := "res://src/ui/BestiaryMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Silhouette constant ───────────────────────────────────────────────

func test_silhouette_color_constant_defined() -> void:
	var src := _read(BESTIARY_MENU)
	assert_true(src.contains("const SILHOUETTE_COLOR := Color(0.12, 0.14, 0.20, 1.0)"),
		"SILHOUETTE_COLOR const must be defined as dark blue-gray")


func test_silhouette_color_is_dark_enough() -> void:
	# Pin: silhouette must be dark — total RGB < 1.0 so the sprite
	# reads as a shadow, not just "slightly tinted".
	var src := _read(BESTIARY_MENU)
	# Extract the constant literal for precise reading.
	var const_idx: int = src.find("const SILHOUETTE_COLOR")
	assert_gt(const_idx, -1)
	var line_end: int = src.find("\n", const_idx)
	var line: String = src.substr(const_idx, line_end - const_idx)
	# Extract RGB triplet.
	var r_idx: int = line.find("Color(")
	assert_gt(r_idx, -1)
	# Crude parse: anything between "Color(" and ")" then split by ", "
	var args_str: String = line.substr(r_idx + 6).split(")")[0]
	var parts: PackedStringArray = args_str.split(", ")
	assert_eq(parts.size(), 4, "Color must be RGBA (4 components)")
	var r: float = float(parts[0])
	var g: float = float(parts[1])
	var b: float = float(parts[2])
	var a: float = float(parts[3])
	assert_lt(r + g + b, 1.0, "RGB sum must be < 1.0 (dark silhouette)")
	assert_eq(a, 1.0, "Alpha must be 1.0 (silhouette not transparent)")


# ── Wiring in _refresh_detail ─────────────────────────────────────────

func test_modulate_is_set_based_on_defeated() -> void:
	# Pin: _refresh_detail sets _detail_sprite.modulate using the
	# defeated bool. The ternary is the canonical shape.
	var src := _read(BESTIARY_MENU)
	assert_true(src.contains("_detail_sprite.modulate = Color.WHITE if defeated else SILHOUETTE_COLOR"),
		"sprite modulate must be Color.WHITE on defeat else SILHOUETTE_COLOR")


func test_modulate_set_after_load_sprite() -> void:
	# Pin: modulate is applied AFTER _load_sprite (else _load_sprite
	# could overwrite it). _load_sprite is asset-loading concern,
	# modulate is intel-gate concern — they should remain separated.
	var src := _read(BESTIARY_MENU)
	var fn_idx: int = src.find("func _refresh_detail")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	var load_idx: int = body.find("_load_sprite(entry.id)")
	var mod_idx: int = body.find("_detail_sprite.modulate")
	assert_gt(load_idx, -1, "_load_sprite call must exist")
	assert_gt(mod_idx, -1, "modulate assignment must exist")
	assert_gt(mod_idx, load_idx,
		"modulate must be set AFTER _load_sprite (intel gate runs after asset load)")


# ── Negative pin: _load_sprite stays pure ─────────────────────────────

func test_load_sprite_does_not_touch_modulate() -> void:
	# Negative pin: keep _load_sprite as a pure asset-loader.
	# Modulate logic belongs in _refresh_detail where defeated lives.
	var src := _read(BESTIARY_MENU)
	var fn_idx: int = src.find("func _load_sprite")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > -1 else src.substr(fn_idx)
	assert_false(body.contains("modulate"),
		"_load_sprite must not set modulate — separation of concerns")


# ── Cross-pin: text intel gate (tick 147) still in place ───────────────

func test_text_intel_gate_still_active() -> void:
	# Tick 147's "???" gate for stats/weaknesses/etc still active —
	# the silhouette change should be ADDITIVE, not a regression.
	var src := _read(BESTIARY_MENU)
	assert_true(src.contains("HP ???   MP ???   ATK ???   DEF ???   MAG ???   SPD ???"),
		"undefeated stats line preserved")
	assert_true(src.contains("Drops: ???   (defeat to unlock)"),
		"undefeated drops line preserved")


# ── Cross-pin: tick 193 flavor + locations preserved ──────────────────

func test_tick_193_flavor_pipeline_preserved() -> void:
	var src := _read(BESTIARY_MENU)
	assert_true(src.contains("_detail_flavor.text = \"\\n\\n\".join(blocks)"),
		"tick 193 flavor assignment preserved")
	assert_true(src.contains("\"Found in: %s\" % \", \".join(PackedStringArray(pools))"),
		"tick 193 location prefix preserved")


# ── Refresh on selection change keeps modulate fresh ───────────────────

func test_modulate_set_unconditionally_on_refresh() -> void:
	# Pin: the modulate is set inside the positive path of
	# _refresh_detail (not gated behind a condition). Otherwise
	# switching from a defeated entry to an undefeated one
	# would inherit the WHITE modulate.
	var src := _read(BESTIARY_MENU)
	var fn_idx: int = src.find("func _refresh_detail")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Find the modulate line, then check it's at the SAME indent
	# as _load_sprite (i.e., top-level of the positive path, not
	# inside a nested if).
	var mod_idx: int = body.find("_detail_sprite.modulate")
	assert_gt(mod_idx, -1)
	# Walk backward to the previous newline + check indent.
	var line_start: int = body.rfind("\n", mod_idx) + 1
	var indent_str: String = body.substr(line_start, mod_idx - line_start)
	# Indent should be a single tab (matches _load_sprite indent).
	var load_idx: int = body.find("_load_sprite(entry.id)")
	var load_line_start: int = body.rfind("\n", load_idx) + 1
	var load_indent: String = body.substr(load_line_start, load_idx - load_line_start)
	assert_eq(indent_str, load_indent,
		"modulate line must share _load_sprite's indent (same scope, not nested)")
