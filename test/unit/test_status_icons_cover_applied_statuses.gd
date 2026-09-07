extends GutTest

## Applied statuses with no icon entry render a grey 3-letter truncation (2026-07-31).
##
## `BattleScene._refresh_status_icons` draws a badge for EVERY entry in
## `combatant.status_effects`, with exactly one documented exclusion
## (`taunted_*`, "internal targeting, not visual"). Anything without a
## `STATUS_ICON_CONFIG` entry falls to:
##
##     {"label": status.substr(0, 3).to_upper(), "color": Color(0.7, 0.7, 0.7)}
##
## So `cannot_act` rendered as grey "CAN" — which reads as its own opposite —
## and 9 statuses were indistinguishable grey badges.
##
## This is Tick 129's defect reopened. That comment records the same class being
## fixed for 25+ statuses ("vague ATT for both attack_up AND attack_down"), and
## nine more accumulated behind it because nothing checked.
##
## ⚠️ One of the nine was MINE, introduced the same day. The burn fix aliases the
## authored effect "burn" to "burning" (what the DoT ticks on), but the config
## key was "burn" — so making burn deal damage turned its orange badge grey. The
## burn regression test asserted the DAMAGE and never the icon, so nothing caught
## it. That is why this guard derives from add_status() rather than listing names.

const SCENE_SRC := "res://src/battle/BattleScene.gd"
const SEARCH_DIRS: Array[String] = ["res://src/battle", "res://src/autogrind", "res://src/jobs"]


func _config_keys() -> Array[String]:
	var src := FileAccess.get_file_as_string(SCENE_SRC)
	var start := src.find("const STATUS_ICON_CONFIG")
	assert_gt(start, -1, "STATUS_ICON_CONFIG must exist or every assertion here is vacuous")
	var body := src.substr(start, src.find("\n}", start) - start)
	var out: Array[String] = []
	var re := RegEx.create_from_string('"([a-z_0-9]+)"\\s*:\\s*\\{')
	for m in re.search_all(body):
		out.append(m.get_string(1))
	return out


## Every status the engine applies via a literal add_status("..."), derived from
## source rather than named here — a hand-list is what let nine accumulate.
##
## ⚠️ LIMITATION, measured not assumed: this sees LITERALS only. `burning` is
## applied as `add_status(status_to_add)` — a variable — so this sweep is blind
## to it, proven by removing the "burning" key and watching only the dedicated
## test below go red while this one stayed green. Any status applied through a
## variable or constant needs its own pin, exactly as `burning` has one. Same
## blind spot as a `foo(` grep missing `.connect(foo)`.
func _applied_statuses() -> Array[String]:
	var found: Array[String] = []
	var re := RegEx.create_from_string('add_status\\(\\s*"([a-z_0-9]+)"')
	for dir_path in SEARCH_DIRS:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".gd"):
				var src := FileAccess.get_file_as_string("%s/%s" % [dir_path, f])
				for m in re.search_all(src):
					var s := m.get_string(1)
					if not found.has(s):
						found.append(s)
			f = d.get_next()
		d.list_dir_end()
	return found


func test_the_sweep_resolves_something() -> void:
	# COUNT control is not enough on its own, so a NAMED member follows.
	var applied := _applied_statuses()
	assert_gt(applied.size(), 5, "the add_status sweep must find real call sites; found %s" % str(applied))
	assert_true(applied.has("stun"),
		"NAMED-MEMBER control: `stun` is applied by the freeze alias and must be visible to this sweep, or a zero below proves nothing")


func test_config_parses() -> void:
	var keys := _config_keys()
	assert_gt(keys.size(), 20, "must parse the real table; got %d keys" % keys.size())
	assert_true(keys.has("poison"), "NAMED-MEMBER control: poison is configured and must parse out")


func test_every_applied_status_has_an_icon_entry() -> void:
	# The defect: a displayed status with no entry becomes a grey truncation.
	var keys := _config_keys()
	var missing: Array[String] = []
	for s in _applied_statuses():
		if s.begins_with("taunted_"):
			continue  # the one documented exclusion in _refresh_status_icons
		if not keys.has(s):
			missing.append(s)
	assert_eq(missing, [] as Array[String],
		"these statuses are applied and DISPLAYED but have no STATUS_ICON_CONFIG entry, so each renders as a grey 3-letter truncation of its own name: %s" % str(missing))


func test_burning_specifically_is_configured() -> void:
	# Pinned on its own because it is the coupling that bit: the burn fix changed
	# which status name lands, and the icon table was keyed on the old one.
	var keys := _config_keys()
	assert_true(keys.has("burning"),
		"BattleManager aliases burn->burning and Combatant ticks 'burning'; without this key the fire DoT shows a grey 'BUR' badge")


func test_the_renderer_still_reads_this_table() -> void:
	# Every other test here proves the TABLE has entries. None proves the DISPLAY
	# uses it — they would all stay green if _refresh_status_icons stopped
	# consuming STATUS_ICON_CONFIG entirely. That is the consumer-blind shape
	# cowir-cutscenes hit the same day (5 tests calling a resolver directly,
	# green with the call site reverted). This pins the consumer.
	#
	# ⚠️ HONEST LIMIT: a source pin, not a painted badge. Driving the real
	# _refresh_status_icons needs a populated _status_icon_containers from full
	# scene setup; a rendered-output test would be strictly better and is not
	# here. This catches "the table stopped being read", not "the badge drew wrong".
	var src := FileAccess.get_file_as_string(SCENE_SRC)
	assert_ne(src, "", "the file must be readable or this assertion is vacuous")
	assert_true(src.contains("STATUS_ICON_CONFIG.get(status,"),
		"_refresh_status_icons must still resolve each badge through STATUS_ICON_CONFIG — if this moved, every entry above defends nothing")
	assert_true(src.contains("if status.begins_with(\"taunted_\")"),
		"the ONE documented display exclusion must still be the only one; a second silent skip would make this guard over-report")


func test_the_alias_and_the_icon_key_still_agree() -> void:
	# If the alias is ever removed or renamed, this says so rather than letting
	# the icon silently drift again.
	var bm := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_ne(bm, "", "BattleManager must be readable or this assertion is vacuous")
	var aliased: bool = bm.contains("status_to_add = \"burning\"")
	assert_eq(aliased, _config_keys().has("burning"),
		"the aliased status name and the icon key must stay in step — one without the other is the grey-badge bug in either direction")
