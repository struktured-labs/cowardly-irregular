extends GutTest

## struktured, 2026-09-23: "I enter the overworld menu… and get stuck in it", and to cowir-deploy
## "B is not back… wait it sometimes works". The menu-level cause (the pad button that opened the
## menu did not close it) is fixed and pinned in test_the_dash_button_does_not_open_the_overworld_menu.
## This sweeps the other place a player gets stuck: every SCREEN the overworld menu opens.
##
## Rows are DERIVED from the live menu, and each row's kind is observed, not listed: it opens a screen
## (_submenu_open), hands off to GameLoop (the menu closes itself), or emits menu_action. A new row is
## covered the day it is added, and one that does none of those three is a dead row.
##
## Measured on main @ 01d614ee7 before this file existed: all 19 screens close on ONE real Back and
## leave the menu open behind them. A ratchet, not a repair — it exists so a twentieth screen that
## forgets its Back path cannot ship.


func _real_party() -> Array:
	var out := []
	for j in ["fighter", "cleric"]:
		var c := Combatant.new()
		c.combatant_name = j.capitalize()
		add_child_autofree(c)
		JobSystem.assign_job(c, j)
		out.append(c)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## WAITS for the fade-in rather than forcing modulate.a: the menu ignores input while fading, and
## the running tween overwrote a forced 1.0 — measured a=0.32 when Back arrived, which silently
## disarmed the double-close arm below (it passed a mutation that really does double-close).
func _open_menu(party: Array) -> OverworldMenu:
	var m := OverworldMenu.new()
	add_child(m)
	m.setup(party)
	var waited := 0
	while m.modulate.a < 1.0 and waited < 180:
		await get_tree().process_frame
		waited += 1
	assert_eq(m.modulate.a, 1.0, "PRECONDITION: the menu finished fading in, so it takes input")
	return m


func _alive(m) -> bool:
	return is_instance_valid(m) and not m.is_queued_for_deletion()


## A REAL press through Input, so whichever node owns input receives it — not a direct _input call.
func _press_back() -> void:
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := InputEventAction.new()
	r.action = "ui_cancel"
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(3)


func after_each() -> void:
	Input.action_release("ui_cancel")


func test_every_screen_the_menu_opens_closes_on_one_back() -> void:
	var party := _real_party()
	var probe := await _open_menu(party)
	var ids := []
	for o in probe._menu_options:
		ids.append(str(o["id"]))
	probe.queue_free()
	await _frames(1)
	assert_gt(ids.size(), 0, "PRECONDITION: the menu offers rows")

	var screens := 0
	var stuck := []
	var double_close := []
	var dead := []
	for id in ids:
		var menu := await _open_menu(party)
		var emitted := [false]
		menu.menu_action.connect(func(_a, _t): emitted[0] = true)
		menu._handle_menu_action(id)
		await get_tree().create_timer(0.25).timeout   # past every screen's slide-in
		if not _alive(menu):
			continue   # hand-off to GameLoop: the menu closed itself on purpose
		if not menu._submenu_open:
			if not emitted[0]:
				dead.append(id)
			menu.queue_free()
			await _frames(1)
			continue
		screens += 1
		await _press_back()
		if not _alive(menu):
			double_close.append(id)
		elif menu._submenu_open:
			stuck.append(id)
		if _alive(menu):
			menu.queue_free()
		await _frames(2)

	assert_gt(screens, 0,
		"CONTROL: no row opened a screen, so the Back sweep below checked nothing")
	assert_eq(stuck, [],
		"these screens do not close on Back — a pad player is stuck in them: %s" % [stuck])
	assert_eq(double_close, [],
		"one Back closed these screens AND the overworld menu behind them: %s" % [double_close])
	assert_eq(dead, [],
		"these rows opened no screen, closed nothing and emitted nothing — pressing them does nothing: %s" % [dead])


## ⛔ AN ARM WITH NO ROW IS DEAD DISPATCH CODE, AND THE RUNTIME ARM ABOVE CANNOT SEE IT — it walks
## `_menu_options`, so it only ever asks about rows that EXIST. That direction is what this adds.
##
## ⚠️ I BUILT THIS FOR THE OTHER DIRECTION AND MEASURED THAT IT WAS ALREADY COVERED. Adding a row
## with no arm reds `test_every_screen_the_menu_opens_closes_on_one_back` too — its `dead` list
## catches exactly that, at runtime, on the real menu:
##     MUTATION: a "journal" row with no arm -> BOTH arms red
## So the dead-row half of this guard is redundant, said plainly rather than left for a reader to
## discover. It is kept because it comes free from the same two derived sets, it names the cause
## without instantiating a menu or waiting 0.25s per row, and it is deterministic.
##
## 🔑 DERIVED FROM BOTH DECLARATION SITES, NOT A HAND LIST. The defect is someone adding a row and
## not an arm — and they would add it to a hand list in the same edit. Rows are any dict literal
## carrying BOTH "id" and "label", which covers the BASE_MENU_OPTIONS const AND the dynamic
## `teleport` append at :179, and a third site nobody has written yet. Measured: 21 = 21.
##
## 📌 This is a RELATION between two sets in one text, not a spelling pin: a rename moves both sides
## and it stays green, which is why reading source is legitimate here. It is NOT a liveness check —
## gut the arms' bodies and it still passes. The runtime arm above is that half of the pair.
## ⛔ THE EXTRACTOR IS THE HALF WITH NO ARM ON IT. @cowir-deploy measured this in another lane's
## derivation and @cowir-ai generalised it: a derived-relation guard has TWO failure modes — the
## RELATION it asserts, and the DERIVATION nobody points a test at. Mine had both directions wrong
## and one was silent. Measured by feeding the extractors shapes they could meet:
##     {"id": row_id, "label": "Computed"}   -> SILENTLY DROPPED, that row is never compared
##     "save", "load":   (a legal multi-arm) -> dropped -> a FALSE red naming them dead rows
## 🔑 "I cannot parse this" and "there is nothing here" must not share a return value. Both helpers
## now REPORT what they could not read, and the arm below requires that report to be empty — so an
## unparseable shape is loud instead of quietly shrinking the comparison.
func _rows_in(text: String) -> Dictionary:
	var rx := RegEx.new()
	rx.compile('"id"\\s*:\\s*"([A-Za-z0-9_]+)"')
	var found: Array[String] = []
	var unreadable: Array[String] = []
	for line in text.split("\n"):
		if not (line.contains('"id"') and line.contains('"label"')):
			continue
		var m := rx.search(line)
		if m:
			found.append(m.get_string(1))
		else:
			unreadable.append(line.strip_edges())
	return {"found": found, "unreadable": unreadable}


func _arms_in(text: String) -> Dictionary:
	var rx := RegEx.new()
	rx.compile('^\\t\\t"([A-Za-z0-9_]+)":\\s*$')
	var found: Array[String] = []
	var unreadable: Array[String] = []
	var inside := false
	for line in text.split("\n"):
		if line.strip_edges() == "match action_id:":
			inside = true
			continue
		if not inside:
			continue
		if line.strip_edges() != "" and not line.begins_with("\t\t"):
			break
		var m := rx.search(line)
		if m:
			found.append(m.get_string(1))
		elif line.begins_with("\t\t") and not line.begins_with("\t\t\t") \
				and line.strip_edges().ends_with(":") and line.strip_edges() != "_:":
			## An arm shape this cannot read — a multi-pattern arm, or a constant. Reported,
			## never dropped: dropping it invents a dead row that is actually handled.
			unreadable.append(line.strip_edges())
	return {"found": found, "unreadable": unreadable}


## THE REFUSAL NEEDS ITS OWN ARM, or it is an untested branch in the instrument everything else
## rests on. Driven against synthetic text rather than the live file, because the live file is
## (correctly) all literals and so cannot exercise it.
func test_the_extractors_report_what_they_cannot_read() -> void:
	var computed := '\t{"id": row_id, "label": "Computed", "enabled": true},'
	var r: Dictionary = _rows_in(computed)
	assert_eq((r["found"] as Array).size(), 0, "CONTROL: a computed id yields no literal")
	assert_eq((r["unreadable"] as Array).size(), 1,
		"a row whose id is not a literal must be REPORTED, not silently dropped from the comparison")

	var multi := "match action_id:\n\t\t\"save\", \"load\":\n\t\t\tpass\n"
	var a: Dictionary = _arms_in(multi)
	assert_eq((a["found"] as Array).size(), 0, "CONTROL: a multi-pattern arm yields no single literal")
	assert_eq((a["unreadable"] as Array).size(), 1,
		"a multi-pattern arm must be REPORTED — dropping it invents a dead row that is handled")

	## And the readable shapes still read, or the arm above passes by breaking the extractor.
	var ok: Dictionary = _rows_in('\t{"id": "journal", "label": "Journal"},')
	assert_eq(ok["found"], ["journal"] as Array[String], "CONTROL: a literal row still parses")

	## ⛔ AND THE REFUSAL MUST NOT FIRE ON A SHAPE IT EXISTS TO ALLOW. The class was [a-z_]+, so a
	## perfectly ordinary literal id carrying a DIGIT — `world2_map`, in a codebase that names things
	## world2_/world3_ everywhere — would have been reported as unreadable. @cowir-overworld hit the
	## same false positive one level down (their `[a-z_]+` rejected a legitimate `return ""`), which
	## is the distinction the refusal is about, missed inside the refusal.
	var numbered: Dictionary = _rows_in('\t{"id": "world2_map", "label": "W2 Map"},')
	assert_eq(numbered["found"], ["world2_map"] as Array[String],
		"a literal id with a digit is READABLE — the refusal must not fire on what it exists to allow")
	assert_eq(numbered["unreadable"], [] as Array[String], "...and must not be reported as unreadable")


func test_every_menu_row_has_a_dispatch_arm() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_ne(src, "", "PRECONDITION: OverworldMenu source must be readable")
	var row_scan: Dictionary = _rows_in(src)
	var arm_scan: Dictionary = _arms_in(src)
	var rows: Array[String] = row_scan["found"]
	var arms: Array[String] = arm_scan["found"]

	## THE DERIVATION'S OWN FAILURE MODE, asserted before the relation it feeds: a shape neither
	## helper can read must stop this arm, not quietly shrink the sets it compares.
	assert_eq(row_scan["unreadable"], [] as Array[String],
		"row shapes this guard cannot read — it would compare a SMALLER set and still pass: %s" % str(row_scan["unreadable"]))
	assert_eq(arm_scan["unreadable"], [] as Array[String],
		"arm shapes this guard cannot read — it would invent dead rows that are handled: %s" % str(arm_scan["unreadable"]))

	## POSITIVE CONTROLS: an empty derivation on either side reports perfect agreement about nothing,
	## which is the shape of every guard aimed at a pattern that stopped matching.
	assert_gt(rows.size(), 15, "CONTROL: must find the authored menu rows, got %d" % rows.size())
	assert_gt(arms.size(), 15, "CONTROL: must find the dispatch arms, got %d" % arms.size())

	var dead_rows: Array[String] = []
	for r in rows:
		if not arms.has(r):
			dead_rows.append(r)
	assert_eq(dead_rows, [] as Array[String],
		"these menu rows have NO arm in _handle_menu_action — selecting them does nothing: %s" % str(dead_rows))

	var orphan_arms: Array[String] = []
	for a in arms:
		if not rows.has(a):
			orphan_arms.append(a)
	assert_eq(orphan_arms, [] as Array[String],
		"these dispatch arms answer no authored row — dead code, or a row that was renamed: %s" % str(orphan_arms))
