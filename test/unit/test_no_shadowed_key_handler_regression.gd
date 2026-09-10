extends GutTest

## A key handler placed AFTER a branch that already claims its key can never run, and no
## source-text guard can see it: the key IS compared, the handler IS present, any legend claim
## naming it DOES resolve. Only branch ORDER decides it.
##
## Found real defects 2026-09-09: Shift+R (Rename profile) sat below `is_action_pressed
## ("battle_advance")` in BOTH grid editors. battle_advance binds KEY_R, and Godot matches an
## action even when extra modifiers are held — so rename was unreachable in AutogrindGridEditor
## (that dead branch was its ONLY caller) and fired only on a key REPEAT in AutobattleGridEditor,
## which advertises "Sh+R:Rename" on screen.
##
## Reads InputMap at RUNTIME rather than re-parsing project.godot: the engine's loaded map is the
## consumer, the config file is a definer. Two structural exemptions, neither an allowlist:
##   same line          -> `is_action_pressed(x) or keycode == KEY_Y` is an OR, not a shadow
##   earlier has is_echo -> that branch declines echo repeats, so the later one is reachable for them

## ⚠️ SCOPE, WITH THE COVERAGE MEASURED 2026-09-10 rather than described:
##
##   input handlers written as elif CHAINS        11  ← this instrument fits
##   written as sequential `if … return`          22  ← OUTSIDE it, incl. GameLoop and BattleScene
##
## It models a chain as if/elif. A handler written as consecutive `if …: return` guards shadows the
## same way — whichever matches first exits — but every `if` here starts a FRESH chain and clears
## the claims, so two thirds of the corpus is unscanned. **THIS CHECKS 11 OF 33 HANDLERS.**
##
## It also does not see: action shadowed by action, keycode shadowed by keycode, or CROSS-NODE
## shadowing (another scene's _input consuming first) — which is how the R/L inversion survived.
##
## I tried widening it to variable-assigned claims (`var is_cancel_pressed = is_action_pressed(...)`
## then `if is_cancel_pressed:`) and the widening was INERT — mutation proved it twice. The first
## failure was my MUTATION (planted above the claim, where nothing shadows); the second was the
## instrument, and it exposed the chain model as the real limit. Reverted rather than shipped: a
## guard that looks wider and is not is worse than a narrow one that says so.
## See feedback_label_broader_than_predicate.

const SRC_DIRS := ["res://src"]


func _claims() -> Dictionary:
	var out := {}
	for a in InputMap.get_actions():
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and ev.keycode != 0:
				if not out.has(a):
					out[a] = []
				if not out[a].has(ev.keycode):
					out[a].append(ev.keycode)
	return out


func _keycode_of(token: String) -> int:
	# F-keys must not be capitalize()d — "F5" becomes "F 5", which resolves to 0
	if token.length() >= 2 and token[0] == "F" and token.substr(1).is_valid_int():
		return OS.find_keycode_from_string(token)
	return OS.find_keycode_from_string(token.capitalize())


func _gd_files(dir_path: String, acc: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_gd_files(full, acc)
		elif name.ends_with(".gd"):
			acc.append(full)
		name = d.get_next()
	d.list_dir_end()


## Returns [shadowed_reports, files_scanned, branches_seen]
func _sweep() -> Array:
	var claims := _claims()
	var files: Array = []
	for root in SRC_DIRS:
		_gd_files(root, files)
	var act_re := RegEx.new()
	act_re.compile('is_action_pressed\\("([a-z_0-9]+)"')
	var key_re := RegEx.new()
	key_re.compile("keycode\\s*==\\s*KEY_([A-Z0-9_]+)")
	var reports: Array = []
	var branches := 0
	for f in files:
		var lines := FileAccess.get_file_as_string(f).split("\n")
		var i := 0
		while i < lines.size():
			if lines[i].begins_with("func _input(") or lines[i].begins_with("func _unhandled_input("):
				# Claims are per INDENT LEVEL. Branches at different depths are not one chain: a
				# nested `if` only runs when its enclosing branch already matched, so it cannot be
				# shadowed by a sibling of that enclosing branch. A line-based version of this
				# reported 5 hits, all five different depths, all five false.
				var by_indent := {}        # indent -> {keycode: [line, action, declines_echo]}
				var j := i + 1
				while j < lines.size() and not lines[j].begins_with("func "):
					var raw: String = lines[j]
					var st := raw.strip_edges()
					if st.begins_with("if ") or st.begins_with("elif "):
						branches += 1
						var indent := raw.length() - raw.lstrip("\t").length()
						# leaving deeper blocks ends their chains
						for d in by_indent.keys():
							if int(d) > indent:
								by_indent.erase(d)
						# `if` STARTS a chain; `elif` continues the one already open
						if st.begins_with("if "):
							by_indent[indent] = {}
						if not by_indent.has(indent):
							by_indent[indent] = {}
						var claimed: Dictionary = by_indent[indent]
						var declines_echo := raw.contains("is_echo")
						for m in key_re.search_all(raw):
							var code := _keycode_of(m.get_string(1))
							if code != 0 and claimed.has(code):
								var who: Array = claimed[code]
								if who[0] != j and not who[2]:
									reports.append("%s:%d KEY_%s is handled here, but line %d already claims it via %s"
										% [f, j + 1, m.get_string(1), who[0] + 1, who[1]])
						for m in act_re.search_all(raw):
							var a := m.get_string(1)
							for code in claims.get(a, []):
								if not claimed.has(code):
									claimed[code] = [j, a, declines_echo]
					j += 1
				i = j
			else:
				i += 1
	return [reports, files.size(), branches]


## THE RATCHET.
func test_no_key_handler_sits_below_a_branch_that_claims_it() -> void:
	var r := _sweep()
	var reports: Array = r[0]
	assert_gt(int(r[1]), 100, "CONTROL: the sweep must actually walk src/, scanned %d files" % r[1])
	assert_gt(int(r[2]), 200, "CONTROL: it must see real branches, saw %d" % r[2])
	for line in reports:
		gut.p("  SHADOWED: %s" % line)
	assert_eq(reports.size(), 0,
		"%d key handler(s) can never run — an earlier branch in the same chain claims the key" % reports.size())


## CONTROL: the machinery this depends on must behave, or the arm above passes vacuously.
func test_the_instrument_resolves_keys_and_claims() -> void:
	assert_eq(_keycode_of("R"), OS.find_keycode_from_string("R"), "a letter resolves")
	assert_gt(_keycode_of("F5"), 0, "an F-key resolves — capitalize() would make it 'F 5' and fail")
	assert_eq(_keycode_of("ZZQ"), 0, "a fabricated token must resolve to 0 and be skipped")
	var claims := _claims()
	assert_true(claims.has("battle_advance"), "the runtime InputMap must expose the project's actions")
	assert_true((claims["battle_advance"] as Array).has(OS.find_keycode_from_string("R")),
		"battle_advance must still claim R — the defect this file was written for depends on it")
