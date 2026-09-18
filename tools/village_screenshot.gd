extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")
## Loads a village scene, pins a day phase, renders a few frames and writes tmp/screens/<village>_<phase>.png. Needs a real renderer (xvfb-run).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var village := "harmonia"
	var phase := 0.3
	var weather := "clear"
	for a in args:
		if a.begins_with("--village="):
			village = a.get_slice("=", 1)
		elif a.begins_with("--phase="):
			phase = float(a.get_slice("=", 1))
		elif a.begins_with("--weather="):
			weather = a.get_slice("=", 1)
	# Autoloads are added AFTER the -s script's _init runs; compiling the village before then fails on SoundManager/GameState
	await process_frame
	await process_frame
	# Only Harmonia has a .tscn; every other village is a bare script, so try both.
	var stem := ""
	for part in village.split("_"):
		stem += part.capitalize()
	var scene: Node = null
	for path in ["res://src/maps/villages/%sVillage.tscn" % stem, "res://src/maps/villages/%s.tscn" % stem,
			"res://src/maps/villages/%sVillage.gd" % stem, "res://src/maps/villages/%s.gd" % stem,
			"res://src/maps/dungeons/%s.gd" % stem,
			"res://src/maps/interiors/%s.gd" % stem]:
		if not ResourceLoader.exists(path):
			continue
		var res = load(path)
		if res is PackedScene:
			scene = res.instantiate()
		elif res is GDScript:
			scene = res.new()
		if scene != null:
			print("SCREEN source ", path)
			break
	if scene == null:
		push_error("no village named %s" % village)
		quit(2)
		return
	root.add_child(scene)
	# ⛔ CAPTURES OF THE SAME SCENE WERE NOT REPRODUCIBLE, AND STORE SHOTS COME FROM HERE.
	# Measured 2026-09-18, two captures of one scene, one tree, one phase:
	#     frosthold  97.4% of sampled pixels differ   mean signed shift R+18.2 G+16.7 B+12.8
	#     ironhaven  91.8%                            mean signed shift R -9.3 G -6.9 B -3.4
	#     grimhollow 91.1%   sandrift 96.0%
	# NO pixel differed by more than 60 -- a uniform grade over the whole frame, not moved
	# props. harmonia, eldertree and the interiors were exactly 0.00 and never varied.
	#
	# Freezing GameState's weather CLOCK removes it. Isolated rather than assumed, because
	# this block also adds a frame and I first credited the wrong half:
	#     8 frames, no pin          97.4% differ
	#     + the extra frame, NO pin 95.0% differ   <- the frame is not the fix
	#     + the pin                  0.0% differ   <- it is
	# and the same pin takes ironhaven, grimhollow and sandrift to 0.0%.
	#
	# ⚠️ WHAT IS *NOT* ESTABLISHED, stated because the obvious reading is wrong: this is NOT
	# "the gallery captured random weather". A probe printing get_weather() at capture time
	# read `clear` on every run, and --weather=snow produced a frame IDENTICAL to clear
	# (0.0% differing). So the condition is not what varies and this flag has not been shown
	# to select anything. What set_weather() also does is set weather_timer and
	# _weather_world, which stops _advance_weather() re-rolling mid-capture -- freezing the
	# CLOCK is the part that is doing the work here. The remaining drift is GameState's
	# day_phase, which advances with wall-clock time (0.150379 / 0.150317 / 0.150300 across
	# three runs) and which phase_override does not hold.
	#
	# Pinned AFTER _ready, because _advance_weather re-rolls whenever current_world changes
	# and the scene sets that on entry -- pinning first would be overwritten.
	await process_frame
	var weather_applied := false
	var gs = root.get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("set_weather"):
		gs.set_weather(weather, 1.0e9)
		weather_applied = true
	else:
		print("[SCREEN] note: GameState unavailable; weather NOT pinned and the tint will vary")
	var phase_applied := false
	if "lighting" in scene and scene.lighting != null:
		scene.lighting.phase_override = phase
		phase_applied = true
	else:
		# NOT fatal -- interiors and dungeons legitimately have no day cycle -- but it is the
		# reason three phases can come back identical, and it used to be silent.
		print("[SCREEN] note: %s has no lighting node; --phase=%s had no effect" % [village, str(phase)])
	for i in range(8):
		await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	var out := "res://tmp/screens/%s_%.2f.png" % [village, phase]

	# ⛔ A FRAME THAT DEPICTS NOTHING USED TO BE WRITTEN AND ANNOUNCED AS A SUCCESS.
	# Measured 2026-09-17 in a worktree with no import cache: HarmoniaVillage.gd failed to
	# parse ("Could not find base class BaseVillage"), the .tscn still instantiated, so the
	# `scene == null` check above passed on an empty node -- and this wrote three 5322-byte
	# flat-grey PNGs at three different day phases, byte-identical, printing "[SCREEN] wrote"
	# each time. These feed the ITCH STORE PAGE. Nothing downstream looks at the pixels.
	# The floor and the refusal live in ShotGuard because nine other tools write shots the
	# same way; see tools/shot_guard.gd for how the floor was derived from the real shot set.
	if not ShotGuard.save_or_refuse(img, out):
		quit(3)
		return
	print("[SCREEN] wrote %s (%dx%d) phase_applied=%s weather=%s pinned=%s"
		% [out, img.get_width(), img.get_height(), str(phase_applied), weather,
			str(weather_applied)])
	quit(0)

