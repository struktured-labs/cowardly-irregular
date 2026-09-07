extends GutTest

## Every archetype/job a cutscene puppets must have a sheet on disk.
##
## WHY THIS IS NOT COVERED BY ANYTHING ELSE: CutsceneActor.build falls back to
## _build_placeholder() when the sheet is missing, and the placeholder fills
## the SAME `_frames` dictionary a real load does. So a missing sheet is
## invisible to every cheap probe — the actor exists, has 16 frames, spawns,
## walks, faces, and emotes. It is a flat coloured box wearing the character's
## name, and the scene plays out around it without complaint.
##
## Measured, 2026-07-26: rendering the folded chancellor_mordaine puppet came
## back a purple rectangle while (1) the PNG was on disk at exactly the
## required 128x128, (2) the overworld_npc_sheets manifest entry was complete
## and correct, and (3) `_frames.size()` read 16. Three independent checks,
## all accurate, all agreeing, and the thing on screen was still wrong. The
## honest signal is whether the frames are AtlasTextures (real sheet) or not
## (placeholder) — and nothing was asserting it.
##
## This matters right now because @cowir-story is authoring antagonist beats
## for W2-W6 whose sheets @cowir-sprites has not drawn yet. A beat naming
## `archetype: "the_director"` before that sheet lands would ship green.
##
## Direction: references -> disk. The reverse (a sheet nobody puppets) is NOT
## a defect — cowir-sprites deliberately ships ahead of the beats, and the
## overworld_npc_sheets ledger already tracks unused art.

const CUTSCENE_DIR := "res://data/cutscenes"
const NPC_SHEET := "res://assets/sprites/npcs/%s/overworld.png"
const JOB_SHEET := "res://assets/sprites/jobs/%s/overworld.png"


func _spawn_steps() -> Array:
	var out: Array = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir, "cutscene dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if not (parsed is Dictionary):
			continue
		var idx := 0
		for s in parsed.get("steps", []):
			if s is Dictionary and s.get("type") == "spawn_actor":
				out.append({"file": f, "step": idx, "spec": s})
			idx += 1
	return out


## Mirrors CutsceneActor.build's own path selection — same branch, same defaults.
func _sheet_path_for(spec: Dictionary) -> String:
	if str(spec.get("kind", "npc")) == "party":
		return JOB_SHEET % str(spec.get("job", "fighter"))
	return NPC_SHEET % str(spec.get("archetype", "young_man"))


func test_the_sweep_actually_finds_spawn_steps() -> void:
	# Positive control. A sweep that silently iterated nothing would make
	# every assertion below vacuously true, which is the failure mode
	# @cowir-overworld pinned in their transition ratchet for the same reason.
	var steps := _spawn_steps()
	assert_gt(steps.size(), 10,
		"the audit must actually be finding spawn_actor steps — 0 found would make this file green and meaningless")


func test_every_puppeted_archetype_has_a_sheet_on_disk() -> void:
	var offenders: Array = []
	for entry in _spawn_steps():
		var path := _sheet_path_for(entry["spec"])
		if not ResourceLoader.exists(path):
			offenders.append("%s[step %d] id='%s' -> %s" % [
				entry["file"], entry["step"], str(entry["spec"].get("id", "")), path])
	assert_eq(offenders.size(), 0,
		"these cutscene actors have no sheet — each renders a PLACEHOLDER BOX, and nothing else in the suite notices:\n  %s" % "\n  ".join(offenders))


func test_a_real_sheet_loads_as_atlas_frames_not_a_placeholder() -> void:
	# The distinguishing signal itself. If this ever stops holding, the
	# audit above still passes while every puppet silently degrades — so
	# pin the property the audit depends on, not just the file's existence.
	var a = CutsceneActor.build("probe", {"kind": "npc", "archetype": "chancellor_mordaine"})
	add_child_autofree(a)
	assert_gt(a._frames.size(), 0, "a real sheet must produce frames")
	assert_true(a._frames.get("0_0") is AtlasTexture,
		"real-sheet frames are AtlasTextures; the placeholder fills the same dict with something else — this is the ONLY honest load/fallback signal")


func test_a_missing_sheet_is_indistinguishable_by_frame_count() -> void:
	# Documents WHY the audit exists, by demonstrating the trap. The
	# placeholder is not broken — it is a deliberate headless-safe fallback.
	# The defect is that it is SILENT, which is what the push_warning in
	# build() and this audit together fix.
	var a = CutsceneActor.build("probe", {"kind": "npc", "archetype": "definitely_not_a_real_archetype"})
	add_child_autofree(a)
	assert_false(a._frames.is_empty(),
		"the placeholder populates _frames too — which is exactly why 'did it load' cannot be answered by counting frames")
	assert_false(a._frames.get("0_0") is AtlasTexture,
		"…and this is how you tell them apart")


func test_build_warns_when_it_falls_back() -> void:
	# A silent fallback is the defect; the warning is the fix. Pin it so a
	# later tidy-up doesn't quietly restore the silence.
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneActor.gd")
	var fn := src.find("static func build(")
	assert_gt(fn, -1, "build() must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var warn := body.find("push_warning")
	var fallback := body.find("_build_placeholder()")
	assert_gt(warn, -1, "build() must warn before falling back to a placeholder")
	assert_true(warn < fallback,
		"the warning must precede the fallback call so the log names the actor that degraded")
