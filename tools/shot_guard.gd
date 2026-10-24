extends RefCounted
## ONE OWNER for "does this frame depict anything".
##
## WHY THIS EXISTS
## ---------------
## Measured 2026-09-17: in a worktree with no import cache, HarmoniaVillage.gd failed to parse
## ("Could not find base class BaseVillage"), the .tscn instantiated anyway, and
## village_screenshot.gd rendered the resulting EMPTY node, wrote a 5322-byte flat-grey PNG and
## printed "[SCREEN] wrote". Three day phases produced three BYTE-IDENTICAL files. The wrapper
## piped the output through grep and ended in `|| true`, so nothing saw a failure either.
##
## These frames feed the ITCH STORE PAGE. Nothing between the renderer and the store looks at
## the pixels, so a cold checkout could have replaced the gallery with 20 grey rectangles.
##
## THE FLOOR IS DERIVED, NOT GUESSED. Distinct colours on a 1-in-8 grid, measured against the
## 20 shots actually on the store:
##     min 325   ironhaven_village      (a flat daylit village, the least colourful real shot)
##     max 9054  title_screen
##     995       whispering_cave        (a DARK scene, to answer the obvious objection)
##     1         a blank frame
## 32 is ~10x below the lowest real shot and 32x above a blank. Nothing legitimate is near it.
##
## ⛔ NOT FOR SPRITE EXPORTERS. tools/export_sprites.gd writes sprite strips, where a small flat
## image is a correct output, not a failure. This floor is about SCREENSHOTS OF SCENES.

const CONTENT_FLOOR := 32

static var refused := 0


static func content_score(img: Image) -> int:
	## Distinct colours on a 1-in-8 grid. Cheap, resolution-independent, and it answers the only
	## question that matters -- is there anything in this picture -- without needing to know what
	## the scene was supposed to look like. That generality is the point: it catches a parse
	## failure, a missing texture, a camera pointed at nothing and causes nobody has hit yet.
	var seen := {}
	var w := img.get_width()
	var h := img.get_height()
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			seen[img.get_pixel(x, y).to_rgba32()] = true
			x += 8
		y += 8
	return seen.size()


static func save_or_refuse(img: Image, out: String) -> bool:
	## Writes `out` and returns true, or writes `<out>.REJECTED.png` and returns false.
	## The rejected frame is KEPT, under a name nothing can mistake for a deliverable, because
	## the picture is the diagnosis -- flat grey means an empty scene, a half-drawn frame means
	## something else entirely, and a caller that deleted it would leave the reader guessing.
	var score := content_score(img)
	if score < CONTENT_FLOOR:
		refused += 1
		img.save_png(out.trim_suffix(".png") + ".REJECTED.png")
		push_error("[shot-guard] REFUSED %s: %d distinct colour(s), floor %d. The frame depicts "
			% [out, score, CONTENT_FLOOR]
			+ "nothing -- most likely the scene did not load, so an empty node rendered. "
			+ "Kept as .REJECTED.png. NOT written as a shot.")
		return false
	img.save_png(out)
	print("[shot-guard] ok %s content=%d" % [out, score])
	return true


## ⛔ THE WEATHER WAS A DICE ROLL IN EVERY OUTDOOR STORE FRAME. GameState._process advances the
## clock and rolls weather from WEATHER_VOCAB (world 1: "clear" is 55 of 100), and _weather_world
## starts at 0, so the very first frame -- before any tool's setup -- already rolls. Measured
## 2026-10-24 at .710: two marketing_shots runs minutes apart differed on 45-97% of pixels in every
## outdoor frame and the battle (interiors 0.00%), and one battle frame read "~ RAIN ~" under a
## caption that says the weather is off. Pausing playtime stops both the clock and the re-roll;
## "clear" and the new-game phase (inside the untinted 0.10-0.50 band) are what a fresh player
## sees. Returns false, loudly, if GameState lacks the fields -- a pin that silently no-ops would
## ship a random frame labelled as pinned. Call again after anything that resets state.
static func pin_conditions(root: Node, where: String) -> bool:
	var gs = root.get_node_or_null("GameState")
	if gs == null or not ("weather_condition" in gs) or not ("playtime_paused" in gs):
		push_error("[SHOT] GameState has no weather/pause fields -- conditions cannot be pinned")
		return false
	var consts: Dictionary = gs.get_script().get_script_constant_map()
	if not consts.has("DAY_PHASE_NEW_GAME") or not ("day_phase" in gs):
		push_error("[SHOT] GameState.DAY_PHASE_NEW_GAME / day_phase absent -- the clock cannot be pinned")
		return false
	gs.playtime_paused = true
	gs.day_phase = float(consts["DAY_PHASE_NEW_GAME"])
	if gs.weather_condition != "clear":
		gs.weather_condition = "clear"
		if gs.has_signal("weather_changed"):
			gs.weather_changed.emit("clear")
	print("[SHOT] conditions (%s): weather=%s day_phase=%.2f paused=%s" % [where, gs.weather_condition, float(gs.day_phase), str(gs.playtime_paused)])
	return true
