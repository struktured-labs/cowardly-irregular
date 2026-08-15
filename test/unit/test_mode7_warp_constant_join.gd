extends GutTest

## ONE global constant compensates for a warp that is CONFIGURABLE PER WORLD. Nothing joined
## those two facts, so this file does.
##
## `InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX` is a single number (140.6) used to displace
## terrain collision on EVERY Mode 7 world. It is only correct because the vertical warp is
## identical everywhere -- and that is a property of the preset DATA, not of the code.
## `Mode7Overlay.apply_preset` reads "horizon", "near_scale" and "ground_y" from each preset
## and would apply them; today no preset supplies any of the three. The machinery is live and
## only the data abstains.
##
## SO THE FIRST PRESET THAT SETS ONE silently invalidates the constant for that world alone.
## There is no error: terrain collision simply sits somewhere other than where the ground is
## drawn, in one world, by an amount nobody computed. The author of that preset has no way to
## see it -- the constant lives in a different file and names none of these keys.
##
## SCOPE. This does NOT re-derive the displacement's magnitude; `test_mode7_terrain_displacement
## _regression` owns that, and a second derivation would inherit the same offset a fourth time.
## What is pinned here is the ASSUMPTION the magnitude rests on: one warp, all worlds.
##
## I expected this to already be broken -- per-world warp geometry was my hypothesis, and it
## was wrong. Recording it as a guard rather than a fix, because being right today is exactly
## what a ratchet is for.

const Mode7 := preload("res://src/exploration/Mode7Overlay.gd")
const Geometry := preload("res://src/exploration/InteractGeometry.gd")

const SHADER_PATH := "res://src/shaders/mode7.gdshader"
const OVERLAY_PATH := "res://src/exploration/Mode7Overlay.gd"

## The three uniforms the VERTICAL mapping reads. `curvature` is deliberately absent: it
## appears only in `sx` (`planet` scales the horizontal fan), so it may vary per world -- and
## it does, across all 5 presets. Listing it here would red a correct change.
const VERTICAL_WARP_UNIFORMS := ["horizon", "near_scale", "ground_y"]


func _shader_source() -> String:
	return FileAccess.get_file_as_string(SHADER_PATH)


## Structural extraction of WORLD_PRESETS: declaration to its MATCHING brace, never a line
## window. A truncated read returns real presets from an incomplete table and reports a clean
## zero for every world it never reached.
func _presets_block() -> String:
	var src := FileAccess.get_file_as_string(OVERLAY_PATH)
	const DECL := "const WORLD_PRESETS: Dictionary = {"
	var at := src.find(DECL)
	if at < 0:
		return ""
	var i := at + DECL.length() - 1
	var depth := 0
	var start := i
	while i < src.length():
		if src[i] == "{":
			depth += 1
		elif src[i] == "}":
			depth -= 1
			if depth == 0:
				return src.substr(start, i - start + 1)
		i += 1
	return ""  # never closed -- refuse rather than return a truncated table


func test_the_extraction_reached_the_whole_preset_table() -> void:
	var block := _presets_block()
	assert_gt(block.length(), 400, "extracted %d chars of WORLD_PRESETS -- the read was cut" % block.length())
	assert_true(block.ends_with("}"), "the extracted block must contain its own closing brace")
	# Matched as KEYS (name + colon), not as bare quoted words. `"abstract"` appears inside
	# the table as a COMMENT -- `# "abstract" intentionally omitted` -- so a bare-word check
	# reports W6 as present and reds a correct table. It did, on the first run.
	assert_true(block.contains("\"medieval\":"), "the first preset is present")
	assert_true(block.contains("\"digital\":"), "the LAST preset is present -- this is the truncation control")
	assert_false(block.contains("\"abstract\":"), "W6 has no preset, so membership means something")


## A SOURCE pin, and labelled as one: it shows the override lines EXIST, not that they run.
## A source pin cannot tell a live branch from one its own caller defeats -- proven on this
## very file, where mutating the line to `if false and preset.has(...)` left this assertion
## green. Its job is narrow: if apply_preset stops reading these keys, the guard below
## becomes over-strict (it would red a preset key that has no effect), and that is worth
## knowing. The claim that MATTERS is the runtime one underneath.
func test_the_override_lines_for_the_warp_uniforms_are_still_present() -> void:
	var src := FileAccess.get_file_as_string(OVERLAY_PATH)
	assert_gt(src.length(), 1000, "read %d bytes of Mode7Overlay.gd" % src.length())
	for key in VERTICAL_WARP_UNIFORMS:
		assert_true(src.contains("preset.has(\"%s\")" % key),
			"apply_preset no longer reads '%s'; this guard would now red a harmless preset key" % key)


## THE RUNTIME SUBJECT. Drives the real apply_preset over every shipped world rather than
## reading the table as text, so it cannot be fooled by a comment, a key spelled differently,
## or a preset defined somewhere the extractor never looked.
func test_applying_every_world_preset_leaves_the_vertical_warp_untouched() -> void:
	var worlds: Array = Mode7.WORLD_PRESETS.keys()
	assert_gt(worlds.size(), 3, "only %d presets -- the table read broke" % worlds.size())

	for world in worlds:
		var m7 = Mode7.new()
		add_child_autofree(m7)
		# sentinels no preset would plausibly contain
		m7.horizon = -7.25
		m7.near_scale = -7.5
		m7.ground_y = -7.75
		# curvature gets a sentinel too: comparing against its DEFAULT would fail spuriously
		# for any preset whose curvature happens to equal it, and pass for the wrong reason.
		m7.curvature = -7.0

		m7.apply_preset(str(world))

		# CONTROL: apply_preset must have actually run and read this world's entry. Without
		# it, a no-op apply_preset would satisfy every assertion below for free.
		assert_ne(m7.curvature, -7.0,
			"apply_preset('%s') changed nothing -- the sentinel checks below would be vacuous" % world)

		assert_almost_eq(m7.horizon, -7.25, 0.0001,
			"preset '%s' overrode `horizon`, which the vertical warp reads" % world)
		assert_almost_eq(m7.near_scale, -7.5, 0.0001,
			"preset '%s' overrode `near_scale`, which the vertical warp reads" % world)
		assert_almost_eq(m7.ground_y, -7.75, 0.0001,
			"preset '%s' overrode `ground_y`, which the vertical warp reads" % world)


func test_the_vertical_warp_reads_exactly_these_uniforms() -> void:
	var shader := _shader_source()
	assert_gt(shader.length(), 500, "read %d bytes of the shader" % shader.length())
	# the whole vertical mapping is one line; if it changes, this guard's premise must be rechecked
	assert_true(shader.contains("float sy = ground_y + near_scale * log("),
		"the vertical warp is no longer `ground_y + near_scale * log(h)` -- re-derive which uniforms it reads before trusting the per-world assumption below")
	# curvature must NOT reach sy, or it would belong in VERTICAL_WARP_UNIFORMS and 5 presets vary it
	assert_true(shader.contains("planet = 1.0 - curvature"),
		"curvature still forms `planet` (horizontal only)")
	assert_true(shader.contains("* x_width * planet"),
		"`planet` is applied to sx, not sy -- this is why curvature may vary per world and these three may not")


## THE SUBJECT. One displacement constant serves every Mode 7 world, so the vertical warp
## must be identical in every one of them.
func test_no_preset_overrides_a_uniform_the_shared_displacement_depends_on() -> void:
	var block := _presets_block()
	assert_gt(block.length(), 400, "preset table non-empty -- otherwise the scan below is vacuous")

	# CONTROL: a key that IS present, so a zero from the subject means absence not a broken scan
	assert_true(block.contains("\"curvature\""),
		"the scan can find preset keys at all (curvature is set by every preset)")

	var offenders: Array = []
	for key in VERTICAL_WARP_UNIFORMS:
		if block.contains("\"%s\"" % key):
			offenders.append(key)

	assert_true(offenders.is_empty(),
		("WORLD_PRESETS now overrides %s. The vertical warp is no longer the same in every " +
		"world, so InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX (%s, shared by all Mode 7 " +
		"worlds) cannot be correct for all of them. Make the displacement per-world, or drop " +
		"the override.") % [str(offenders), str(Geometry.MODE7_GROUND_DISPLACEMENT_PX)])


## The trigger offset is the displacement negated. Two constants, one number -- so pin the
## RELATIONSHIP, not either magnitude (the magnitude is playtested and owned elsewhere).
func test_the_trigger_offset_is_the_negated_displacement() -> void:
	assert_almost_eq(Geometry.MODE7_TRIGGER_Y_OFFSET, -Geometry.MODE7_GROUND_DISPLACEMENT_PX, 0.0001,
		"triggers shift north by exactly what terrain shifts south")
	assert_gt(Geometry.MODE7_GROUND_DISPLACEMENT_PX, 0.0,
		"the displacement is southward -- a sign flip would move terrain the wrong way and still satisfy the relation above")
