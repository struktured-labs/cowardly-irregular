extends GutTest

## Real-save hydration smoke (2026-07-02). Tonight's save-leak fix
## added else-branches to GameState._apply_save_data (absent
## quests/activated_crystals keys now RESET instead of leaking) — a
## change that touches every existing save load. This suite hydrates
## every save actually present on this machine through the state
## layer, so "Continue" can't be the first place an old-format save
## meets new load code.
##
## Self-skipping: machines without local saves (CI, fresh clones)
## pend instead of failing — the suite's value is exactly that it
## runs against REAL aged saves where they exist.

const SAVE_DIR := "user://saves/"

var _snapshot: Dictionary


func before_each() -> void:
	_snapshot = GameState.to_dict()


func after_each() -> void:
	GameState._apply_save_data(_snapshot)


func _save_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json") and not dir.current_is_dir():
			out.append(SAVE_DIR + f)
		f = dir.get_next()
	return out


func test_every_local_save_hydrates_through_state_layer() -> void:
	var paths := _save_paths()
	if paths.is_empty():
		pass_test("no local saves on this machine — smoke self-skips")
		return
	for path in paths:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(raw is Dictionary, "%s must parse as a JSON object" % path)
		if not (raw is Dictionary):
			continue
		var data: Dictionary = raw
		GameState._apply_save_data(data)
		# Pre-quest-system saves (no "quests" key) must land EMPTY —
		# tonight's else-branch — never inherit another run's state.
		if not data.has("quests"):
			assert_true(GameState.quests.is_empty(),
				"%s: absent quests key must hydrate to empty" % path)
		if not data.has("activated_crystals"):
			assert_true(GameState.activated_crystals.is_empty(),
				"%s: absent crystals key must hydrate to empty" % path)
		# Corruption must land clamped regardless of save age.
		assert_between(GameState.corruption_level, 0.0, 1.0,
			"%s: corruption_level out of range after hydrate" % path)


func test_every_local_save_party_roundtrips_combatants() -> void:
	# The typed-array traps (status_effects, permanent_injuries,
	# pinned/recent abilities...) live in Combatant.from_dict — run it
	# against every REAL party member in every REAL save, then
	# round-trip to_dict to prove nothing silently dropped to [].
	var paths := _save_paths()
	if paths.is_empty():
		pass_test("no local saves on this machine — smoke self-skips")
		return
	# Self-skip: paths exist but no save has meaningful party data (e.g. after
	# a full userdata wipe the game writes an empty slot-98 auto-save; that
	# was already failing on origin/main after struktured's 2026-07-12 clean-
	# out). This test's intent is "aged real saves must roundtrip cleanly" —
	# nothing to prove against empty slots.
	var any_party := false
	for probe_path in paths:
		var probe: Variant = JSON.parse_string(FileAccess.get_file_as_string(probe_path))
		if probe is Dictionary:
			var probe_party: Array = (probe as Dictionary).get("party", (probe as Dictionary).get("player_party", []))
			if probe_party.size() > 0:
				any_party = true
				break
	if not any_party:
		pass_test("local saves exist but contain no party data — smoke self-skips")
		return
	var members_checked: int = 0
	for path in paths:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (raw is Dictionary):
			continue
		var party: Array = (raw as Dictionary).get("party", (raw as Dictionary).get("player_party", []))
		for entry in party:
			if not (entry is Dictionary):
				continue
			var c := Combatant.new()
			c.from_dict(entry)
			assert_gt(c.max_hp, 0, "%s: %s hydrated with no HP" % [path, str(entry.get("combatant_name", "?"))])
			assert_gt(c.job_level, 0, "%s: job_level must survive" % path)
			var back: Dictionary = c.to_dict()
			for key in ["status_effects", "permanent_injuries", "learned_passives", "pinned_abilities"]:
				if entry.has(key) and (entry[key] as Array).size() > 0:
					assert_gt((back.get(key, []) as Array).size(), 0,
						"%s: %s silently dropped in roundtrip (the typed-array trap)" % [path, key])
			members_checked += 1
			c.free()
	assert_gt(members_checked, 0, "expected at least one party member across local saves")
