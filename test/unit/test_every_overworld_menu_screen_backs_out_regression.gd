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
func test_every_menu_row_has_a_dispatch_arm() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_ne(src, "", "PRECONDITION: OverworldMenu source must be readable")
	var id_rx := RegEx.new()
	id_rx.compile('"id"\\s*:\\s*"([a-z_]+)"')
	var rows: Array[String] = []
	var lines := src.split("\n")
	for line in lines:
		if not (line.contains('"id"') and line.contains('"label"')):
			continue
		var m := id_rx.search(line)
		if m:
			rows.append(m.get_string(1))

	var arm_rx := RegEx.new()
	arm_rx.compile('^\\t\\t"([a-z_]+)":\\s*$')
	var arms: Array[String] = []
	var inside := false
	for line in lines:
		if line.strip_edges() == "match action_id:":
			inside = true
			continue
		if inside:
			if line.strip_edges() != "" and not line.begins_with("\t\t"):
				break
			var a := arm_rx.search(line)
			if a:
				arms.append(a.get_string(1))

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
