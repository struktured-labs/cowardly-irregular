extends GutTest

## FIVE parallel tables describe the same six pad bindings, kept in agreement BY HAND:
##   project.godot [input] · PROFILE_STANDARD · PROFILE_SN30 · PROFILE_ULTIMATE_PRO_2
##   plus REMAPPABLE_ACTIONS and ACTION_LABELS
##
## The agreement has broken SILENTLY TWICE, and both repairs are comments rather than guards —
## InputProfileManager's own source says so: "dropping 7 was a silent regression" and "the same
## silent loss already fixed in PROFILE_STANDARD". A third table was worse: PROFILE_ULTIMATE_PRO_2
## carried a defer/advance SWAP that was correct on 2026-07-18 hardware and became an INVERSION once
## ControllerMappings landed, so for eleven days anyone selecting that profile got Defer and Advance
## backwards against the hint bar. Nothing went red; a person read it.
##
## 🛑 WHY THE FILE IS PARSED INSTEAD OF READ FROM InputMap: InputProfileManager erases every
## InputEventJoypadButton at _ready and re-adds from the active profile, so at runtime the InputMap
## IS the profile for these six actions. Comparing them through InputMap would compare the profile
## with itself and pass unconditionally — the tautology this file exists to avoid. project.godot's
## pad section is only readable as text.
##
## ⚠️ DIVERGENCE IS ALLOWED — a profile for a nonconforming pad SHOULD differ. It must be DECLARED,
## because the Ultimate Pro 2 inversion proves an undeclared one is invisible. The declaration is the
## deliverable; you cannot silence this green, only explain it green.

const PROJECT := "res://project.godot"

## "PROFILE_X/action" -> why this profile deliberately differs from project.godot. Empty today: all
## three profiles currently agree with the file on all six actions (measured 2026-09-10).
const DECLARED_DIVERGENCE := {}

const PROFILES := ["PROFILE_STANDARD", "PROFILE_SN30", "PROFILE_ULTIMATE_PRO_2"]


## project.godot's pad buttons per action, from the TEXT — see the header for why not InputMap.
func _file_pad_bindings() -> Dictionary:
	var src := FileAccess.get_file_as_string(PROJECT)
	var start := src.find("[input]")
	assert_gt(start, -1, "project.godot must have an [input] section")
	var stop := src.find("\n[", start + 1)
	var body := src.substr(start, (stop - start) if stop > start else -1)
	var out := {}
	var block := RegEx.create_from_string("(?ms)^(\\w+)=\\{(.*?)^\\}")
	var btn := RegEx.create_from_string("InputEventJoypadButton[^)]*?\"button_index\":(\\d+)")
	for m in block.search_all(body):
		var name := m.get_string(1)
		var buttons: Array[int] = []
		for b in btn.search_all(m.get_string(2)):
			buttons.append(int(b.get_string(1)))
		buttons.sort()
		if not buttons.is_empty():
			out[name] = buttons
	return out


func _profile(name: String) -> Dictionary:
	return InputProfileManager.get(name)


func _sorted_ints(v) -> Array[int]:
	var out: Array[int] = []
	for x in v:
		out.append(int(x))
	out.sort()
	return out


## Every action any table names must be a REAL action. A phantom name is silently ignored by
## apply_profile — the binding simply never applies and nothing reports it.
func test_every_table_names_only_real_actions() -> void:
	var real := _file_pad_bindings()
	assert_gt(real.size(), 5, "PRECONDITION: project.godot must yield pad-bound actions")
	var bad: Array[String] = []
	for p in PROFILES:
		for action in _profile(p):
			if not InputMap.has_action(action):
				bad.append("%s/%s" % [p, action])
	for action in InputProfileManager.REMAPPABLE_ACTIONS:
		if not InputMap.has_action(action):
			bad.append("REMAPPABLE_ACTIONS/%s" % action)
	for action in InputProfileManager.ACTION_LABELS:
		if not InputMap.has_action(action):
			bad.append("ACTION_LABELS/%s" % action)
	assert_eq(bad, [] as Array[String],
		"a table names an action that does not exist — apply_profile ignores it silently: %s"
		% [", ".join(bad)])


## The five tables must cover the SAME action set. An action missing from one profile keeps whatever
## project.godot gave it, so the player gets a different binding on that profile with no warning;
## missing from ACTION_LABELS and the remap screen shows a raw action id.
func test_the_tables_cover_the_same_action_set() -> void:
	var expected := {}
	for a in _profile("PROFILE_STANDARD"):
		expected[a] = true
	var mismatches: Array[String] = []
	for p in PROFILES:
		var keys := {}
		for a in _profile(p):
			keys[a] = true
		if keys != expected:
			mismatches.append(p)
	var remap := {}
	for a in InputProfileManager.REMAPPABLE_ACTIONS:
		remap[a] = true
	if remap != expected:
		mismatches.append("REMAPPABLE_ACTIONS")
	for a in expected:
		if not InputProfileManager.ACTION_LABELS.has(a):
			mismatches.append("ACTION_LABELS missing %s" % a)
	assert_eq(mismatches, [] as Array[String],
		"the parallel tables disagree on WHICH actions they cover: %s" % [", ".join(mismatches)])


## THE RECORDED REGRESSION, twice: a profile quietly dropping a button project.godot declares.
## Divergence is legal and must be declared — an undeclared one inverted Defer/Advance for 11 days.
func test_profile_divergence_from_project_godot_is_declared() -> void:
	var file_bindings := _file_pad_bindings()
	var undeclared: Array[String] = []
	for p in PROFILES:
		var prof := _profile(p)
		for action in prof:
			if not file_bindings.has(action):
				continue
			var mine := _sorted_ints(prof[action])
			var theirs := _sorted_ints(file_bindings[action])
			if mine == theirs:
				continue
			var key := "%s/%s" % [p, action]
			if not DECLARED_DIVERGENCE.has(key):
				undeclared.append("%s (profile %s vs project.godot %s)" % [key, mine, theirs])
	assert_eq(undeclared, [] as Array[String],
		"a profile differs from project.godot with no declared reason — that is how ui_menu lost " +
		"button 7 twice and how the Ultimate Pro 2 profile inverted Defer/Advance: %s"
		% [", ".join(undeclared)])


## CONTROL: no DECLARED_DIVERGENCE entry may be inert — a stale allowlist line reads as coverage.
func test_no_declared_divergence_is_stale() -> void:
	var file_bindings := _file_pad_bindings()
	var inert: Array[String] = []
	for key in DECLARED_DIVERGENCE:
		var parts: PackedStringArray = str(key).split("/")
		var prof := _profile(parts[0])
		if not prof.has(parts[1]) or not file_bindings.has(parts[1]):
			inert.append(key)
			continue
		if _sorted_ints(prof[parts[1]]) == _sorted_ints(file_bindings[parts[1]]):
			inert.append(key)
	assert_eq(inert, [] as Array[String],
		"a declared divergence no longer diverges — delete it: %s" % [", ".join(inert)])


## CONTROL: the parser must actually read the file. Without this every arm above is vacuously green
## on an empty dictionary — the wrong-shape zero.
func test_the_file_parser_reads_real_bindings() -> void:
	var f := _file_pad_bindings()
	assert_true(f.has("battle_defer"), "CONTROL: project.godot binds battle_defer to a pad button")
	assert_eq(_sorted_ints(f["battle_defer"]), [9] as Array[int],
		"CONTROL: and it is button 9 — a known value, so a parser returning junk is caught")
	assert_false(f.has("zzq_not_an_action"), "CONTROL: the parser can report a name as ABSENT")
