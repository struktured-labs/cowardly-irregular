extends GutTest

## W5 and W6 — the last mute landmarks. Four terminals and racks in the Vigil, three void crystals
## in the abstract, drawn and answering nothing. With these wired, **all six worlds answer**, which
## was the point of the anti-feature W1 closed: a player who presses scenery and gets silence stops
## pressing, and every readable placed afterwards inherits that.
##
## 🔑 ONE FILE, TWO WORLDS, AND THE MODE 7 FLAG IS THE REASON IT IS PARAMETERISED RATHER THAN
## COPIED. W5 runs Mode 7; **W6 deliberately does not** (CLAUDE.md pins that, and the fleet's Mode 7
## guards exclude W6 on purpose). The press reach differs 2x between them — `PROBE_REACH_MODE7` 80
## vs `PROBE_REACH_FLAT` 40 — so a guard that assumed either would measure a press the player cannot
## make in one world or miss one they can in the other. `press_census` now mirrors
## `OverworldController:237` instead of hardcoding the Mode 7 value, which it did until this change;
## that was correct for W2/W3/W4 and silently wrong for anything flat, including every village.
##
## ⚠️ NO PREDICTION ABOUT TIES HERE, on purpose. For W4 I read the chest list, predicted that a
## chest two cells from The Overrun would take three of its cells, wrote "predicted and confirmed"
## into the header BEFORE running it, and the census refuted it — the 2-cell collinear spacing that
## makes W2's Timetable and W3's Standing Gauge yield makes a tie POSSIBLE, not certain, because the
## facing probe's reach and the competitor's zone geometry decide it. Read the census, never the
## chest list.

const WORLDS := {
	"w5": {
		"script": "res://src/exploration/FuturisticOverworld.gd",
		"lore": "res://src/exploration/W5Landmarks.gd",
		"mode7": true,
	},
	"w6": {
		"script": "res://src/exploration/AbstractOverworld.gd",
		"lore": "res://src/exploration/W6Landmarks.gd",
		"mode7": false,
	},
}

const Census := preload("res://test/unit/helpers/press_census.gd")

var _census: RefCounted = null


func _build(world: String) -> Node2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var w = load(str(WORLDS[world]["script"])).new()
	vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	## ⛔ ASSERT THE MODE HERE, IN THE BUILDER, NOT ONLY IN ITS OWN ARM. `Mode7Overlay.is_active` is a
	## GLOBAL autoload flag and the census reads it to choose its probe reach (80 vs 40). A separate
	## arm checking the flag does not protect the arms that MEASURE with it: if a neighbouring test
	## left it stale, every census arm would pass while having measured the wrong world's geometry,
	## and nothing in the numbers would say so. @cowir-deploy's .661 block is this exact shape one
	## layer out — their fixture's LOCATION decided which branch the arm measured, and it passed
	## either way. The environment belongs in the setup every measurement inherits.
	## Measured: the W6-declares-Mode-7 mutation red 2 arms before this change and 5 after.
	assert_eq(Mode7Overlay.is_active, bool(WORLDS[world]["mode7"]),
		"[%s] built with Mode 7 = %s, expected %s — every press number below would be measured at the wrong reach" % [
			world, str(Mode7Overlay.is_active), str(WORLDS[world]["mode7"])])
	_census = Census.new()
	_census.setup(vp, float(int(w.MAP_SCALE) * int(w.TILE_SIZE)))
	return w


func _lore(world: String) -> RefCounted:
	return load(str(WORLDS[world]["lore"])).new()


func _readables(w: Node) -> Dictionary:
	var out: Dictionary = {}
	for c in w.get_children():
		if c is ReadableProp:
			out[str(c.name)] = c
	return out


func _landmark_positions(w: Node) -> Array:
	var out: Array = []
	for c in w.get_children():
		if c is Landmark:
			out.append((c as Landmark).position)
	return out


func test_every_landmark_has_a_readable_on_its_own_cell() -> void:
	for world in WORLDS.keys():
		var w = await _build(str(world))
		var rows: Array = _lore(str(world)).table()
		assert_gt(rows.size(), 0, "CONTROL [%s]: the table is empty, so every [] below is free" % world)
		var props := _readables(w)
		var marks := _landmark_positions(w)
		var answering: Array = []
		for row in rows:
			if str(row.get("fn", "")) != "":
				answering.append(row)
		assert_eq(props.size(), answering.size(), "[%s] one readable per ANSWERING table row" % world)
		assert_eq(marks.size(), rows.size(), "[%s] every row still DRAWS, mute or not" % world)
		var adrift: Array = []
		for row in answering:
			var key: String = "Lore_" + str(row["fn"])
			if not props.has(key):
				adrift.append("%s built no readable" % key)
				continue
			var want: Vector2 = w._cell_center(row["cell"])
			if props[key].position.distance_to(want) > 1.0:
				adrift.append("%s at %s, table says %s" % [key, str(props[key].position), str(want)])
			if not marks.any(func(p): return p.distance_to(want) <= 1.0):
				adrift.append("%s has no landmark drawn on its cell %s" % [key, str(row["cell"])])
		assert_eq(adrift, [], "[%s] a readable does not stand on its own landmark: %s" % [world, ", ".join(adrift)])


## A row that draws without answering must NAME WHY. The reason is the deliverable: it cannot be
## silenced green, only explained green, and the explanation is what a later reader needs in order
## to know whether the trade still holds.
func test_a_mute_row_states_its_reason() -> void:
	var unexplained: Array = []
	var mute := 0
	for world in WORLDS.keys():
		for row in _lore(str(world)).table():
			if str(row.get("fn", "")) != "":
				continue
			mute += 1
			if str(row.get("mute_reason", "")).length() < 20:
				unexplained.append("%s/%s" % [world, str(row.get("name", "?"))])
	gut.p("  rows that draw without answering: %d" % mute)
	assert_eq(unexplained, [],
		"a landmark draws and answers nothing with no reason recorded; the next reader cannot tell " +
		"a decision from an oversight: %s" % ", ".join(unexplained))


func test_every_provider_returns_pages() -> void:
	for world in WORLDS.keys():
		var lore := _lore(str(world))
		var rows: Array = lore.table()
		assert_gt(rows.size(), 0, "CONTROL [%s]: no rows to call" % world)
		var broken: Array = []
		for row in rows:
			var fn: String = str(row["fn"])
			if fn == "":
				continue
			if not lore.has_method(fn):
				broken.append("%s names no method" % fn)
				continue
			var pages = Callable(lore, fn).call()
			if not (pages is Array) or (pages as Array).is_empty():
				broken.append("%s returned no pages" % fn)
				continue
			for e in pages as Array:
				if e is Dictionary:
					if str(e.get("body", "")) == "":
						broken.append("%s has a headed page with no body" % fn)
				elif not (e is String) or str(e) == "":
					broken.append("%s has a page that is neither text nor a {heading,body}" % fn)
		assert_eq(broken, [], "[%s] a landmark would open an empty panel: %s" % [world, ", ".join(broken)])


## W3's collar shipped `return []` on the no-GameState path for one draft; this is the ratchet.
func test_no_provider_goes_empty_without_game_state() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null:
		gs.name = "GameStateHidden"
	var empty: Array = []
	for world in WORLDS.keys():
		var lore := _lore(str(world))
		for row in lore.table():
			if str(row.get("fn", "")) == "":
				continue
			var pages = Callable(lore, str(row["fn"])).call()
			if not (pages is Array) or (pages as Array).is_empty():
				empty.append("%s/%s" % [world, str(row["fn"])])
	if gs != null:
		gs.name = "GameState"
	assert_eq(empty, [],
		"with no GameState these providers return nothing, so the prop opens a blank panel: %s" % ", ".join(empty))


## The Mode 7 flag per world, pinned because the press reach depends on it and W6's absence is a
## design decision rather than an oversight.
func test_each_world_runs_the_mode_it_is_documented_to_run() -> void:
	for world in WORLDS.keys():
		var _w = await _build(str(world))
		assert_eq(Mode7Overlay.is_active, bool(WORLDS[world]["mode7"]),
			"[%s] Mode 7 active should be %s; the census reach (80 vs 40) follows this flag, so a " % [world, str(WORLDS[world]["mode7"])] +
			"change here silently changes what every press measurement in this world means")


func test_every_landmark_readable_can_actually_be_pressed() -> void:
	for world in WORLDS.keys():
		var w = await _build(str(world))
		var props: Array = _readables(w).values()
		assert_gt(props.size(), 0, "CONTROL [%s]: no lore props found, so [] below is free" % world)
		var unreachable: Array = []
		for p in props:
			var n: int = _census.presses_for(p)
			var split: Dictionary = _census.face_split(p)
			gut.p("  [%s] %-24s %3d presses   stolen %s   yielded %s" % [
				world, str(p.name), n, str(split["bad"]), str(split["yielded"])])
			if n <= 0:
				unreachable.append("%s (%s) — no standable cell within two opens it from any facing" % [str(p.name), str(p.display_name)])
			elif not bool(WORLDS[world]["mode7"]):
				## ⛔ THE 8-RING IS A MODE 7 PROPERTY, NOT A UNIVERSAL ONE, and asserting it here would
				## have forced correct content to move. Flat: reach 40, `READABLE_BOX_FLAT` 28 (pinned
				## narrow so Phil's notebook cannot steal Phil's press), on W6's 64px grid — so the
				## facing probe from an adjacent cell lands 24px short of a 14px half-extent and the
				## prop is reachable only by STANDING ON IT. Measured: all three W6 crystals score
				## exactly 4 presses, one per facing from their own cell, and 7 ring cells reach
				## nothing. That is the flat geometry working, not a placement defect.
				pass
			elif not (split["bad"] as Array).is_empty():
				unreachable.append("%s (%s) — %s" % [str(p.name), str(p.display_name), ", ".join(split["bad"])])
		unreachable.sort()
		assert_eq(unreachable, [],
			"[%s] a landmark now carries a label promising a press it cannot answer: %s" % [world, ", ".join(unreachable)])


## The load-bearing arm, same as the other three worlds: the new zones may MOVE presses but may not
## take a neighbour's own face-it-and-press.
func test_no_landmark_readable_takes_a_neighbours_press() -> void:
	for world in WORLDS.keys():
		var w = await _build(str(world))
		var lore_names: Dictionary = _readables(w)
		var others: Array = []
		_census.scene_interactables(w, others)
		var neighbours: Array = []
		for n in others:
			if not lore_names.has(str(n.name)):
				neighbours.append(n)
		assert_gt(neighbours.size(), 3,
			"CONTROL [%s]: only %d non-lore interactables — with nothing to rob, [] is free" % [world, neighbours.size()])
		var with_lore: Dictionary = {}
		for n in neighbours:
			var s1: Dictionary = _census.face_split(n)
			with_lore[n] = (s1["bad"] as Array) + (s1["yielded"] as Array)
		for key in lore_names.keys():
			(lore_names[key] as Node).free()
		await get_tree().physics_frame
		var robbed: Array = []
		for n in neighbours:
			if not is_instance_valid(n):
				continue
			var s2: Dictionary = _census.face_split(n)
			var without: Array = (s2["bad"] as Array) + (s2["yielded"] as Array)
			for cell in with_lore[n]:
				if not without.has(cell):
					robbed.append("%s loses the press at %s" % [_census.label(n), str(cell)])
		robbed.sort()
		assert_eq(robbed, [], "[%s] a landmark readable took a neighbour's press: %s" % [world, ", ".join(robbed)])


func test_a_landmark_readable_actually_opens() -> void:
	for world in WORLDS.keys():
		var w = await _build(str(world))
		var rows: Array = _lore(str(world)).table()
		var props := _readables(w)
		var key: String = "Lore_" + str(rows[0]["fn"])
		assert_true(props.has(key), "SCOPE [%s]: %s must exist to be pressed" % [world, key])
		if not props.has(key):
			continue
		var prop = props[key]
		assert_false(prop.is_open(), "CONTROL [%s]: closed before the press" % world)
		prop.interact(null)
		assert_true(prop.is_open(), "[%s] pressing %s opened nothing" % [world, key])
		prop._close_panel()
		assert_false(prop.is_open(), "[%s] the panel must close, releasing the input lock" % world)


## All six worlds, derived from disk rather than listed: a seventh overworld with mute landmarks
## should cost one deliberate edit, not pass unnoticed the way these five did.
func test_every_overworld_with_landmarks_has_a_lore_table() -> void:
	var dir := DirAccess.open("res://src/exploration")
	assert_not_null(dir, "CONTROL: src/exploration must be readable")
	var mute: Array = []
	var checked := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		if not (f.ends_with("Overworld.gd") or f == "OverworldScene.gd"):
			continue
		var src := FileAccess.get_file_as_string("res://src/exploration/" + f)
		if not src.contains("Landmark.new()"):
			continue
		checked += 1
		if not src.contains("_place_landmark_lore"):
			mute.append(str(f))
	assert_gte(checked, 6, "CONTROL: only %d overworlds draw landmarks — the scan is broken" % checked)
	mute.sort()
	assert_eq(mute, [],
		"an overworld draws landmarks and wires no lore table, so its scenery teaches the player to " +
		"stop pressing: %s" % ", ".join(mute))


## ⛔ THE MUTE REASON MUST STILL BE TRUE, OR IT EXPIRES. @cowir-story's roster contract applied to my
## own table: their declarations shrink when a pack gets wired and a BASELINE's excuse dies with its
## comparing guard, so the roster cannot become a list of excuses. My `mute_reason` was free text
## checked only for length — **if the condition that justified it ever stopped holding, the row would
## stay mute forever with a stale explanation and nothing would red.** A reason that cannot expire is
## a list of excuses with extra steps.
##
## The claim is measurable, so it is measured: place a probe readable on the muted row's cell and
## verify it STILL takes the entrance's presses. If it stops — the entrance moves, the probe reach
## changes, `READABLE_BOX_FLAT` is retuned — this reds and says to un-mute the row.
##
## ⚠️ Scoped to rows that carry a reason NAMING a victim. A future mute for some other cause would
## need its own check, and the arm says so rather than silently passing it.
func test_a_mute_reason_is_still_true() -> void:
	var lore := _lore("w5")
	var muted: Array = []
	for row in lore.table():
		if str(row.get("fn", "")) == "":
			muted.append(row)
	if muted.is_empty():
		pass_test("no muted rows in W5 — nothing to re-justify")
		return

	var w = await _build("w5")
	var others: Array = []
	_census.scene_interactables(w, others)

	var unjustified: Array = []
	for row in muted:
		var reason: String = str(row.get("mute_reason", ""))
		var victim: Node2D = null
		for o in others:
			if reason.contains(str(o.name)):
				victim = o
				break
		if victim == null:
			unjustified.append("%s names no interactable this scene contains, so its reason cannot be re-checked: '%s'" % [
				str(row.get("name", "?")), reason])
			continue

		## The entrance's presses BEFORE a readable exists on the muted cell.
		var before: Dictionary = _census.face_split(victim)
		var baseline: Array = (before["bad"] as Array) + (before["yielded"] as Array)

		var probe := ReadableProp.new()
		probe.name = "MuteProbe"
		probe.position = w._cell_center(row["cell"])
		probe.setup("probe", func(): return ["probe"])
		w.add_child(probe)
		await get_tree().physics_frame
		await get_tree().physics_frame

		var after: Dictionary = _census.face_split(victim)
		var taken: Array = []
		for cell in ((after["bad"] as Array) + (after["yielded"] as Array)):
			if not baseline.has(cell) and str(cell).contains("MuteProbe"):
				taken.append(str(cell))
		probe.free()
		await get_tree().physics_frame

		gut.p("  mute re-check: %s -> probe takes %d of %s's cells %s" % [
			str(row.get("name", "?")), taken.size(), str(victim.name), str(taken)])
		if taken.is_empty():
			unjustified.append("%s is muted because a readable there would take %s's presses — it NO LONGER DOES. Un-mute the row, or replace the reason with one that is true" % [
				str(row.get("name", "?")), str(victim.name)])
	assert_eq(unjustified, [],
		"a mute reason has expired; a row that draws without answering must be justified by a " +
		"condition that still holds: %s" % ", ".join(unjustified))

