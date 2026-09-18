extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")
## Loads a village scene, pins a day phase, renders a few frames and writes tmp/screens/<village>_<phase>.png. Needs a real renderer (xvfb-run).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var village := "harmonia"
	var phase := 0.3
	for a in args:
		if a.begins_with("--village="):
			village = a.get_slice("=", 1)
		elif a.begins_with("--phase="):
			phase = float(a.get_slice("=", 1))
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
	print("[SCREEN] wrote %s (%dx%d) phase_applied=%s"
		% [out, img.get_width(), img.get_height(), str(phase_applied)])
	quit(0)

