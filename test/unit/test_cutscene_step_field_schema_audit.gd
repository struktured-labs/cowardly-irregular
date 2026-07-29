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
	                  "optional": ["job", "archetype", "at", "facing", "replace_npc", "at_offset"]},
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
	# TWO legal forms, both dispatched by _step_branch and both in its own
	# docstring: condition+cases, OR flag+if_true/if_false. Required fields
	# are checked per-form below, so `optional` lists the union.
	"branch":       {"required": [], "optional": ["condition", "cases", "flag", "if_true", "if_false"]},
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
		_walk_steps(f, parsed.get("steps", []), "steps", callback)


## Recurses into branch sub-steps. Pre-2026-07-29 this walked ONLY the
## top-level array, so 70 nested steps across 14 files were never validated —
## every step inside a `branch`'s cases / if_true / if_false. All 70 happened
## to be well-formed, so the hole was latent, but @cowir-music had just added
## four nested play_music steps to the game's ending and nothing checked them.
## Partial-enum in my own guard: complete for the direction I was thinking in.
func _walk_steps(f: String, steps: Array, path: String, callback: Callable) -> void:
	var idx := 0
	for step in steps:
		if step is Dictionary:
			callback.call(f, idx, step)
			for case_steps in (step.get("cases", {}) as Dictionary).values():
				if case_steps is Array:
					_walk_steps(f, case_steps, "%s[%d].cases" % [path, idx], callback)
			for key in ["if_true", "if_false"]:
				if step.get(key) is Array:
					_walk_steps(f, step[key], "%s[%d].%s" % [path, idx, key], callback)
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
		# branch has two legal forms; require ONE of them rather than both.
		# Pre-2026-07-29 this demanded condition+cases unconditionally, so the
		# flag form — which _step_branch dispatches and documents — failed the
		# audit on BOTH counts (unknown fields AND missing required). Zero flag
		# branches exist in 193 files; the guard was forbidding them.
		if t == "branch":
			var has_cond: bool = step.has("condition") and step.has("cases")
			var has_flag: bool = step.has("flag")
			if not has_cond and not has_flag:
				var bkey := "branch.condition+cases_or_flag"
				if not offenders.has(bkey):
					offenders[bkey] = []
				if offenders[bkey].size() < 3:
					offenders[bkey].append("%s[step %d]" % [f, i])
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


func test_the_audit_actually_reaches_nested_branch_steps() -> void:
	# POSITIVE CONTROL for the recursion. Without it, a walker that silently
	# stopped at the top level would leave every assertion in this file green
	# while covering nothing nested — which is exactly the state this file was
	# in until 2026-07-29. An empty offender list must mean "clean", never
	# "the walk never got there".
	var nested := 0
	var seen_types: Dictionary = {}
	_iter_steps(func(_f: String, _i: int, step: Dictionary):
		var t := str(step.get("type", ""))
		if t != "":
			seen_types[t] = true
	)
	# Count nested steps directly, independent of the walker, so this can't
	# agree with a broken walk by construction.
	var dir = DirAccess.open("res://data/cutscenes")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s" % f))
		if not (parsed is Dictionary):
			continue
		for step in parsed.get("steps", []):
			if not (step is Dictionary):
				continue
			for case_steps in (step.get("cases", {}) as Dictionary).values():
				if case_steps is Array:
					nested += case_steps.size()
	assert_gt(nested, 20,
		"sanity: the corpus should contain many branch-nested steps to audit — got %d" % nested)
	assert_true(seen_types.has("play_music"),
		"the walker must reach nested play_music steps — the four W6 ending themes live inside branch cases, and they were unvalidated until the walk recursed")
