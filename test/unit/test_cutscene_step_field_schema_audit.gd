extends GutTest

## Regression: cadence #8 scout 2026-07-16 — audit found the `hop` step
## silently ignoring the `duration` field. CutsceneActor.hop(times: int)
## read only `times`, but 2 of 3 hop uses in data/cutscenes passed
## `duration` instead. Author intent lost, timing wrong. Same silent-drop
## class as unregistered themes/portraits/backdrops/music-tracks.
##
## The fix extended hop() to accept both fields; this ratchet enumerates
## the known-good schema per step type and fails when a JSON step has
## unknown fields (silent-ignore drift), or is missing a required field.
##
## Adding a new step type: extend STEP_SCHEMA below. Adding a new optional
## field to an existing step type: add it to the `optional` set.

const KNOWN_ONLY_SEMANTIC := "type"

## step_type → { required: Set[String], optional: Set[String] }
const STEP_SCHEMA := {
	# Actor-lifecycle
	"spawn_actor":   {"required": ["id", "kind"],
	                  "optional": ["job", "archetype", "at", "facing", "replace_npc"]},
	"despawn_actor": {"required": ["id"], "optional": []},
	"move_actor":    {"required": ["id", "to"], "optional": ["speed"]},
	"face_actor":    {"required": ["id"], "optional": ["dir", "toward"]},
	"emote":         {"required": ["id", "emote"], "optional": ["duration"]},
	"hop":           {"required": ["id"], "optional": ["times", "duration"]},

	# Camera
	"camera_focus":  {"required": ["target"], "optional": ["duration"]},
	"camera_restore":{"required": [], "optional": ["duration"]},

	# Dialogue / narration
	"dialogue":      {"required": ["lines"], "optional": []},
	"narration":     {"required": [], "optional": ["text", "lines"]},  # text OR lines
	"chapter_title": {"required": ["title"], "optional": ["subtitle"]},
	"boss_intro":    {"required": ["name"], "optional": ["title"]},
	"roll_credits":  {"required": ["world"], "optional": ["music"]},

	# Screen fx
	"fade_to_black":  {"required": [], "optional": ["duration"]},
	"fade_from_black":{"required": [], "optional": ["duration"]},
	"letterbox_in":   {"required": [], "optional": ["duration"]},
	"letterbox_out":  {"required": [], "optional": ["duration"]},
	"screen_shake":   {"required": [], "optional": ["duration", "intensity"]},
	"screen_flash":   {"required": [], "optional": ["duration"]},
	"set_background": {"required": [], "optional": ["color", "top", "bottom"]},

	# Time / flags / items
	"wait":         {"required": ["duration"], "optional": []},
	"set_flag":     {"required": ["flag"], "optional": ["value"]},
	"grant_item":   {"required": ["item"], "optional": ["name", "description"]},
	"give_item":    {"required": ["item"], "optional": ["quantity"]},
	"update_item":  {"required": ["item", "new_id"], "optional": []},
	"start_timer":  {"required": ["duration"], "optional": ["flag"]},
	"stop_timer":   {"required": [], "optional": ["flag"]},

	# Audio
	"play_music":   {"required": ["track"], "optional": []},
	"stop_music":   {"required": [], "optional": []},
	"play_sfx":     {"required": ["sfx"], "optional": []},

	# Control flow
	"branch":       {"required": ["condition", "cases"], "optional": []},
	"choice":       {"required": ["prompt", "options"], "optional": []},
	"battle":       {"required": ["combatants", "enemies"], "optional": ["on_defeat", "music", "background", "win_condition"]},
}


func _iter_steps(callback: Callable) -> void:
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path = "res://data/cutscenes/%s" % f
		var text = FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary):
			continue
		var idx := 0
		for step in parsed.get("steps", []):
			if step is Dictionary:
				callback.call(f, idx, step)
			idx += 1


func test_every_step_type_used_has_a_schema_entry() -> void:
	# Adding a new step type should also add a schema entry — otherwise a
	# typo'd step type slips past this audit forever.
	var used: Dictionary = {}
	_iter_steps(func(_f: String, _i: int, step: Dictionary):
		var t := str(step.get("type", ""))
		if t != "":
			used[t] = true
	)
	var missing: Array = []
	for t in used:
		if not STEP_SCHEMA.has(t):
			missing.append(t)
	assert_eq(missing.size(), 0,
		"cutscene JSON uses step types with no STEP_SCHEMA entry: %s (add them here or fix typos)" % str(missing))


func test_no_unknown_fields_on_known_step_types() -> void:
	# Silent-ignore drift catcher: hop had `duration` passed but code read
	# `times` (cadence-8 finding). Ratchet forces every field to be
	# declared required or optional per step type.
	var offenders: Dictionary = {}  # (step_type, field) -> [example paths]
	_iter_steps(func(f: String, i: int, step: Dictionary):
		var t := str(step.get("type", ""))
		if not STEP_SCHEMA.has(t):
			return
		var schema = STEP_SCHEMA[t]
		var known: Dictionary = {KNOWN_ONLY_SEMANTIC: true}
		for k in schema["required"]:
			known[k] = true
		for k in schema["optional"]:
			known[k] = true
		for k in step:
			if known.has(k):
				continue
			var key: String = "%s.%s" % [t, k]
			if not offenders.has(key):
				offenders[key] = []
			if offenders[key].size() < 3:
				offenders[key].append("%s[step %d]" % [f, i])
	)
	if offenders.is_empty():
		assert_true(true)
		return
	var reports: Array = []
	for k in offenders:
		reports.append("%s (e.g. in %s)" % [k, ", ".join(offenders[k])])
	assert_true(false,
		"cutscene JSON has unknown fields on known step types (silent-ignore drift — the code isn't reading them):\n  %s" % "\n  ".join(reports))


func test_required_fields_present_on_every_step() -> void:
	# Missing a required field means the handler skips or hits its
	# push_warning path. Catch author omissions at test time.
	var offenders: Dictionary = {}  # (step_type, missing_field) -> [example paths]
	_iter_steps(func(f: String, i: int, step: Dictionary):
		var t := str(step.get("type", ""))
		if not STEP_SCHEMA.has(t):
			return
		# narration is `text` OR `lines` (either satisfies the required contract).
		if t == "narration":
			if not step.has("text") and not step.has("lines"):
				var key = "narration.text_or_lines"
				if not offenders.has(key):
					offenders[key] = []
				if offenders[key].size() < 3:
					offenders[key].append("%s[step %d]" % [f, i])
			return
		for req in STEP_SCHEMA[t]["required"]:
			if not step.has(req):
				var key: String = "%s.%s" % [t, req]
				if not offenders.has(key):
					offenders[key] = []
				if offenders[key].size() < 3:
					offenders[key].append("%s[step %d]" % [f, i])
	)
	if offenders.is_empty():
		assert_true(true)
		return
	var reports: Array = []
	for k in offenders:
		reports.append("missing %s (e.g. in %s)" % [k, ", ".join(offenders[k])])
	assert_true(false,
		"cutscene JSON steps missing required fields (handler will push_warning or skip):\n  %s" % "\n  ".join(reports))


func test_hop_step_accepts_duration_field() -> void:
	# Source pin on the cadence-8 fix: hop() must accept BOTH times and
	# duration parameters. Before this, world1_harmonia_after_cave's two
	# hop steps with duration:0.3 were silently ignored (child hop played
	# at default 0.2s cycle instead of 0.3s).
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneActor.gd")
	assert_ne(src, "", "CutsceneActor.gd must be readable")
	var idx := src.find("func hop(")
	assert_gt(idx, -1, "CutsceneActor.hop must exist")
	# Signature must have both parameters — the exact form is (times, duration)
	# per the cadence-8 fix.
	var signature := src.substr(idx, 100)
	assert_true(signature.contains("times") and signature.contains("duration"),
		"CutsceneActor.hop signature must accept both `times` and `duration` params — dropping duration was the drift")

	var director := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var step_idx := director.find("func _step_hop(")
	assert_gt(step_idx, -1, "_step_hop must exist")
	var step_body := director.substr(step_idx, 400)
	assert_true(step_body.contains('step.get("duration"'),
		"_step_hop must forward the duration field to CutsceneActor.hop — otherwise the fix is orphaned")
