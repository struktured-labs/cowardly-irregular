extends GutTest

## The BYOK log line is one token away from writing a player's API key to disk.
##
## `GameState.llm_custom_api_key` is marked **SENSITIVE — never log, never print**
## (GameState:93). BYOK is desktop-only and the key persists in settings.json; the
## one place it could escape into a *log* is the config line LLMService emits when
## a custom endpoint is applied:
##
##     "[LLMService] BYOK applied: format=%s url=%s model=%s key=%s"
##
## Today that last field is `"<set>"` or `"<empty>"` — presence, never value. That
## is correct and it was correct before this file existed. **Nothing enforced it.**
##
## ⚠️ NO CURRENT DEFECT. Measured across the whole lane:
##     api_key readers in src/llm/     1 — the Authorization header (HTTPBackend:289)
##     prints/warnings carrying it     0
##     api_key or base_url in a prompt 0
##     CONTROL  the same scan finds 11 push_warning sites in LLMService
##
## This is a ratchet on an IRREVERSIBLE failure, which is the case for pinning a
## property that is already true. `user://logs/godot.log` persists on disk; a key
## written there is leaked for as long as the file exists, and no later fix
## un-writes it. The tempting edit is swapping `"<set>"` for the masked helper
## "just for debugging" — and a masked key still leaks length and both ends.
##
## Asserted on the RENDERED LINE rather than the source: a leak can arrive as a
## format change, a new field, a different helper, or a second log site, and only
## the text catches all four.

const LS := preload("res://src/llm/LLMService.gd")

## Distinctive enough that a substring search cannot match it by accident, and
## long enough that a masked form (first 4 + last 4) is also distinctive.
const FAKE_KEY := "sk-zzqq1234ABCDEFGHIJKLMNOP9876wxyz"


func _backend_with_key(key: String) -> LLMBackend:
	var be := HTTPBackend.new()
	add_child_autofree(be)
	be.api_format = "openai"
	be.base_url = "https://example.invalid/v1"
	be.model = "some-model"
	be.api_key = key
	return be


# ── the property ──────────────────────────────────────────────────────────────

func test_the_line_never_contains_the_key() -> void:
	## THE ARM.
	var line: String = LS.byok_log_line(_backend_with_key(FAKE_KEY))
	assert_eq(line.find(FAKE_KEY), -1,
		("the BYOK log line carries the raw api_key: %s. Fix in LLMService.byok_log_line — "
		+ "report PRESENCE only ('<set>' / '<empty>'). user://logs/godot.log persists on disk "
		+ "and no later change un-writes a key already logged.") % line)


func test_not_even_a_masked_key() -> void:
	## The stronger half, and the one a future edit reaches for: a masked key is
	## still the key's length and both of its ends.
	var line: String = LS.byok_log_line(_backend_with_key(FAKE_KEY))
	var head: String = FAKE_KEY.substr(0, 4)
	var tail: String = FAKE_KEY.substr(FAKE_KEY.length() - 4)
	assert_eq(line.find(head), -1,
		("the line carries the key's first 4 characters (%s) — a masked key is still key "
		+ "material. Report presence only: %s") % [head, line])
	assert_eq(line.find(tail), -1,
		"the line carries the key's last 4 characters (%s): %s" % [tail, line])


func test_presence_is_reported_both_ways() -> void:
	## CORRECT-WORK: the field must still say something useful, or the next reader
	## deletes it and loses the one signal that BYOK took effect at all.
	assert_true(LS.byok_log_line(_backend_with_key(FAKE_KEY)).find("key=<set>") != -1,
		"a configured key must report as <set>")
	assert_true(LS.byok_log_line(_backend_with_key("")).find("key=<empty>") != -1,
		"an absent key must report as <empty>")


func test_the_line_still_names_the_config_it_is_for() -> void:
	## CONTROL: a line that reported nothing would pass every arm above. The
	## non-secret fields are the reason the log exists.
	var line: String = LS.byok_log_line(_backend_with_key(FAKE_KEY))
	for expected in ["openai", "https://example.invalid/v1", "some-model", "BYOK applied"]:
		assert_true(line.find(expected) != -1,
			"the log line no longer names %s — it reports nothing and should not exist: %s"
				% [expected, line])


# ── nothing else in the lane may log it either ────────────────────────────────

func test_no_other_log_site_in_the_lane_interpolates_the_key() -> void:
	## A second log site is the other way this leaks, and it would not touch the
	## function above. Scans every print/warning in src/llm/ for the field name.
	var offenders: Array[String] = []
	for path in _lane_files():
		var src: String = FileAccess.get_file_as_string(path)
		var lineno: int = 0
		for raw in src.split("\n"):
			lineno += 1
			var line: String = raw
			var hash_at: int = line.find("#")
			if hash_at != -1:
				line = line.substr(0, hash_at)
			var logs: bool = line.find("print(") != -1 or line.find("push_warning(") != -1 \
				or line.find("push_error(") != -1 or line.find("printerr(") != -1
			if logs and line.find("api_key") != -1:
				offenders.append("%s:%d" % [path.get_file(), lineno])
	assert_eq(offenders, ([] as Array[String]),
		("these log sites interpolate api_key: %s. Fix: report presence ('<set>'/'<empty>') "
		+ "or drop the field. GameState:93 marks it SENSITIVE — never log, never print.")
			% ", ".join(offenders))


func test_the_log_site_scan_can_find_a_log_site() -> void:
	## POSITIVE CONTROL: the zero above is worth nothing unless the same scan
	## reports hits on the log calls that really are there.
	var found: int = 0
	for path in _lane_files():
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			if raw.find("push_warning(") != -1:
				found += 1
	assert_gt(found, 5,
		"the scan finds almost no push_warning in src/llm/ — it is broken, not the lane")


func _lane_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open("res://src/llm")
	## The control is AFTER the null branch on purpose. A `return out` there skips
	## it in exactly the case it exists for — an unopenable directory yields an
	## empty corpus, and the offender arm then passes having scanned nothing.
	## Found by a mutation arm under-predicting: blinding the scan redded the
	## positive control and NOT this, because this assert was unreachable.
	if d != null:
		d.list_dir_begin()
		var n: String = d.get_next()
		while n != "":
			if n.ends_with(".gd"):
				out.append("res://src/llm/%s" % n)
			n = d.get_next()
		d.list_dir_end()
	assert_gt(out.size(), 5,
		"CONTROL: the lane scan found %d files — the scan is broken, not the lane" % out.size())
	return out


# ── the key leaves this lane, and the scan above does not ─────────────────────
#
## ⛔ EVERY ARM ABOVE IS SCOPED TO `_lane_files()` = `res://src/llm`, AND THE KEY DOES NOT LIVE
## THERE. `GameState.llm_custom_api_key` is read by FOUR files and THREE are outside that scope:
## `src/ui/BYOKConfigPanel.gd` (holds it raw, in a LineEdit and in a Dictionary),
## `src/save/SaveSystem.gd` (writes it to settings.json), `src/ui/SettingsMenu.gd` (masked).
##
## Measured 2026-09-18, BEFORE writing this: a `print("[BYOK] config: %s" % [cfg])` planted at
## `BYOKConfigPanel:303` left the guard at **6 passing / 13 asserts, byte-identical to baseline**,
## and all TWELVE tests naming the key or the panel green at 80 passing / 276 asserts. A raw key
## reaching `user://logs/godot.log` — the irreversible leak this file's header is about — was
## invisible to every guard in the suite. The scope was narrower than the name.
##
## 🔑 AND WIDENING THE SCOPE ALONE WOULD NOT HAVE CAUGHT IT. `_typed_config()` puts the key into a
## DICTIONARY under the literal key `"api_key"`, so the leak site reads `print(... % [cfg])` and
## names `api_key` NOWHERE. A symbol scan over `src/ui` is still blind to it. The container is the
## hazard — handing out a dict that holds the key is handing out the key.
##
## So two instruments, because one subject is a NAME and the other is a CONTAINER.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

const KEY_FIELD := "llm_custom_api_key"

## The walk's roots, in ONE place. `_all_gd()` and the roots floor both read THIS — an earlier
## version of that floor carried its own copy of the list, so removing `res://tools` from the walk
## left the floor green (measured: 13 passing, EC=0, with the root gone). A floor that restates its
## subject instead of reading it proves the ENGINE can walk there, not that THIS guard does.
const WALK_ROOTS: Array[String] = ["res://src", "res://tools"]


## Every .gd under res://src that names the key field — the key's real blast radius, DERIVED by a
## recursive walk rather than a directory list, so a new holder in any subsystem enters by itself.
func _key_holder_files() -> Array[String]:
	var out: Array[String] = []
	for p in _all_gd():
		if FileAccess.get_file_as_string(p).find(KEY_FIELD) != -1:
			out.append(p)
	out.sort()
	return out


## Every .gd under WALK_ROOTS. Separated from the filter above so the roots floor can assert on
## what the walk REACHED rather than on a restatement of where it was told to look.
##
## ⚠️ `res://tools` is in scope and was the same defect one directory over: a tool runs in this
## engine and its `print` persists to the same log. `tools/probes/autoload_leak_probe.gd`
## enumerated GameState's properties and wrote the key to disk (cowir-battle, 2026-09-18, fixed).
## No tool holds the key today, so that root is a RATCHET, proven by an ARRIVAL mutation rather
## than by a current offender.
## `res://test` is deliberately OUT: fixtures hold fake keys by design, and a guard that reds on
## its own FAKE_KEY earns an allowlist within a week.
func _all_gd() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = WALK_ROOTS.duplicate()
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append("%s/%s" % [dir_path, sub])
		for f in d.get_files():
			if f.ends_with(".gd"):
				out.append("%s/%s" % [dir_path, f])
	return out


## Source with comments stripped, so a comment naming the key is never an offender.
##
## ⛔ THIS WAS A PRIVATE `raw.find("#")` AND IT WAS A FALSE-NEGATIVE PATH IN A SECURITY GUARD.
## A `#` inside a STRING LITERAL truncated the line at that point, so anything after it was
## invisible to every arm here. Produced, not predicted — planting a real container leak,
## `print("byok note # dump: %s" % [cfg])`, left this file at 13 passing / EC=0 with the leak in
## the tree, because the alias sits after the `#`.
##
## `GdSource` is quote-aware AND escape-aware, bounded against the spin its own header records,
## and has 175 consumers. A private copy does not inherit a fix (cowir-controller, 2026-09-18,
## who found twelve other re-derivations).
##
## ⛔ AND `strip_comments` IS THE WRONG HALF — it removes `#` AND NOTHING ELSE. I named it as the
## delegation target in channel and it left this scan FALSE-REDDING on prose: a docstring merely
## DESCRIBING a leak — `"""Never do this: print("[BYOK] %s" % GameState.llm_custom_api_key)"""` —
## was reported as an offender at a line that logs nothing. Conservative direction, and exactly
## the prose a security guard attracts; this file's own header is full of it.
## `split()["code"]` is the half that drops `"""` regions too (cowir-battle, 2026-09-18).
func _code_lines(src: String) -> PackedStringArray:
	return (GdSource.split(src)["code"] as String).split("\n")


## [[line_no, code_text], …] — code lines paired with their TRUE index in the ORIGINAL file.
##
## ⛔ NEEDED BECAUSE `split()` DELETES DOCSTRING REGIONS RATHER THAN BLANKING THEM, so counting
## lines in the code half reports a number that does not exist in the file. Measured while making
## this change: the same planted leak was reported at `SaveSystem.gd:1030` where the real line is
## 1051 — 21 lines of docstring removed above it. An offender message that names the wrong line
## sends a reader to innocent code, and for THIS guard that reader is chasing a credential leak.
## Order is preserved by the split, so one forward cursor resolves duplicates correctly.
func _numbered_code(src: String) -> Array:
	var raw: PackedStringArray = src.split("\n")
	var out: Array = []
	var cursor: int = 0
	for c in _code_lines(src):
		var t: String = c.strip_edges()
		if t == "":
			continue
		while cursor < raw.size() and raw[cursor].find(t) == -1:
			cursor += 1
		if cursor >= raw.size():
			break
		out.append([cursor + 1, c])
		cursor += 1
	return out


func _is_log_site(line: String) -> bool:
	return line.find("print(") != -1 or line.find("push_warning(") != -1 \
		or line.find("push_error(") != -1 or line.find("printerr(") != -1


## Functions that RETURN a container built from key material. `_typed_config() -> Dictionary` with
## `"api_key":` in its body is the live one; its return value is the key wearing another name.
func _key_carriers(src: String) -> Array[String]:
	var out: Array[String] = []
	var current: String = ""
	var has_key: bool = false
	var container: bool = false
	for line in _code_lines(src):
		if line.begins_with("func "):
			if current != "" and has_key and container:
				out.append(current)
			has_key = false
			## ⚠️ TWO ways to be a container, because ONE was a hole. Recognising a carrier only by
			## its `-> Dictionary` annotation misses an UNTYPED `func _cfg():` that returns a dict
			## just the same — the arrival of a new FORM, which shrinks no named member and so reds
			## nothing. Found by @cowir-sfx's lens, not by my own mutations: renaming or deleting a
			## carrier proves the path works, never that the file notices a fourth form appearing.
			container = line.find("-> Dictionary") != -1 or line.find("-> Array") != -1
			current = line.substr(5, line.find("(") - 5).strip_edges()
		elif current != "":
			if line.find("api_key") != -1 or line.find(KEY_FIELD) != -1:
				has_key = true
			if line.find("return {") != -1 or line.find("return [") != -1:
				container = true
	if current != "" and has_key and container:
		out.append(current)
	return out


## Locals bound to a carrier's return value — `var cfg: Dictionary = _typed_config()`.
func _aliases_of(src: String, carriers: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for line in _code_lines(src):
		var t: String = line.strip_edges()
		if not t.begins_with("var "):
			continue
		var eq: int = t.find("=")
		if eq == -1:
			continue
		var rhs: String = t.substr(eq + 1)
		for c in carriers:
			if rhs.find(c + "(") != -1:
				var name: String = t.substr(4, eq - 4).strip_edges().split(":")[0].strip_edges()
				if name != "" and not out.has(name):
					out.append(name)
	return out


func test_no_log_site_anywhere_in_src_interpolates_the_key() -> void:
	## THE ARM the old scope could not reach: the same log-site scan, over every file that holds
	## the key rather than over one directory.
	var offenders: Array[String] = []
	for path in _key_holder_files():
		for pair in _numbered_code(FileAccess.get_file_as_string(path)):
			var line: String = str(pair[1])
			if _is_log_site(line) and (line.find("api_key") != -1 or line.find(KEY_FIELD) != -1):
				offenders.append("%s:%d" % [path.get_file(), int(pair[0])])
	assert_eq(offenders, ([] as Array[String]),
		("these log sites interpolate the API key: %s. Report presence ('<set>'/'<empty>') or drop "
		+ "the field — GameState:96 marks it SENSITIVE, and user://logs/godot.log persists on disk.")
			% ", ".join(offenders))


func test_no_log_site_prints_a_container_that_holds_the_key() -> void:
	## THE SECOND SUBJECT. A dict carrying the key names nothing sensitive at the log site, so the
	## arm above is structurally blind to it — this is the shape the planted leak actually had.
	var offenders: Array[String] = []
	for path in _key_holder_files():
		var src: String = FileAccess.get_file_as_string(path)
		var carriers: Array[String] = _key_carriers(src)
		if carriers.is_empty():
			continue
		var watched: Array[String] = carriers.duplicate()
		watched.append_array(_aliases_of(src, carriers))
		for pair in _numbered_code(src):
			var line: String = str(pair[1])
			if not _is_log_site(line):
				continue
			for w in watched:
				if line.find(w) != -1:
					offenders.append("%s:%d logs %s" % [path.get_file(), int(pair[0]), w])
					break
	assert_eq(offenders, ([] as Array[String]),
		("these log sites print a container holding the API key: %s. The container is the key — "
		+ "log the non-secret fields by name instead.") % ", ".join(offenders))


# ── controls: every zero above needs the same scan saying YES somewhere ───────

func test_the_holder_scan_reaches_outside_the_llm_lane() -> void:
	## FLOOR, and it is the whole point of this section: an empty or lane-only corpus makes both
	## arms above vacuous while they read as thorough. Pinned by MEMBERSHIP, not by count — a
	## count floor is satisfied by a survivor.
	var holders: Array[String] = _key_holder_files()
	assert_gt(holders.size(), 2, "the holder walk found %d files — the walk is broken" % holders.size())
	for must in ["res://src/meta/GameState.gd", "res://src/save/SaveSystem.gd",
			"res://src/ui/BYOKConfigPanel.gd"]:
		assert_true(holders.has(must),
			"%s holds the raw key and the scan does not reach it — got %s" % [must, holders])
	var outside: int = 0
	for p in holders:
		if not p.begins_with("res://src/llm/"):
			outside += 1
	assert_gt(outside, 0,
		"every holder is inside src/llm, so this section is the old scope wearing a new name")


func test_the_walk_reaches_every_root_it_declares() -> void:
	## FLOOR on the ROOTS. The reference is LITERAL and deliberately NOT `WALK_ROOTS` — two earlier
	## versions of this arm were decorative for opposite reasons, both measured:
	##   a private copy of the walk  -> proved the ENGINE can reach tools/, not that THIS guard does
	##   `for root in WALK_ROOTS`    -> the mutation SHRINKS that const, so dropping a root also
	##                                  drops its own check. 13 passing with the root gone.
	## A floor whose reference is the thing under test cannot see that thing shrink. So the roots
	## are named here, by hand, and this list going stale is the intended cost of that.
	var required: Array[String] = ["res://src", "res://tools"]
	var reached: Array[String] = _all_gd()
	assert_gt(reached.size(), 100, "the walk reached %d .gd files — it is broken" % reached.size())
	for root in required:
		assert_true(WALK_ROOTS.has(root),
			"WALK_ROOTS no longer declares %s — a log site there is invisible to every arm above" % root)
		var hit: bool = false
		for f in reached:
			if f.begins_with(root + "/"):
				hit = true
				break
		assert_true(hit, "the walk declares %s but reached no .gd under it" % root)


func test_the_carrier_scan_can_find_a_carrier() -> void:
	## POSITIVE CONTROL for the container instrument. `_typed_config` is the live carrier; if the
	## parser stops finding it, the container arm's zero means the scan died, not that we are safe.
	var panel: String = FileAccess.get_file_as_string("res://src/ui/BYOKConfigPanel.gd")
	assert_true(_key_carriers(panel).has("_typed_config"),
		"the carrier scan no longer finds _typed_config — got %s" % [_key_carriers(panel)])


func test_the_alias_scan_can_follow_a_carrier_into_a_local() -> void:
	## POSITIVE CONTROL for the second hop, on a synthetic source so it cannot go quiet when the
	## panel is refactored. This is the exact shape the planted leak had.
	var fake: String = "func _typed_config() -> Dictionary:\n\treturn {\"api_key\": x}\n" \
		+ "func _go() -> void:\n\tvar cfg: Dictionary = _typed_config()\n\tprint(\"%s\" % [cfg])\n"
	var carriers: Array[String] = _key_carriers(fake)
	assert_true(carriers.has("_typed_config"), "control: carrier not found in the synthetic source")
	assert_true(_aliases_of(fake, carriers).has("cfg"),
		"control: the alias scan cannot follow a carrier into a local — got %s"
			% [_aliases_of(fake, carriers)])


func test_the_split_keeps_code_and_drops_both_prose_forms() -> void:
	## THE OBLIGATION `GdSource.split`'s OWN HEADER PUTS ON EVERY CALLER: "over-stripping and a
	## correct strip are the same green", so a consumer must assert a known CODE SITE SURVIVES.
	## Floored on BOTH halves — an empty doc side passes by construction, which is the vacuous way
	## for this to look right.
	var fake: String = 'var keep := log_it("a")\n' \
		+ '# api_key in a comment\n' \
		+ '"""api_key in a docstring"""\n' \
		+ 'var also := log_it("b")\n'
	var halves: Dictionary = GdSource.split(fake)
	var code: String = str(halves.get("code", ""))
	var doc: String = str(halves.get("doc", ""))
	assert_true(code.find('log_it("a")') != -1,
		"MUST-SURVIVE: real code before the docstring was eaten by the split — every zero in this file is then vacuous")
	assert_true(code.find('log_it("b")') != -1,
		"MUST-SURVIVE: real code AFTER the docstring was eaten — a parity flip, the two-directional failure the helper warns about")
	assert_eq(code.find("api_key"), -1,
		"neither a comment nor a docstring naming the key may reach the code half — got %s" % code)
	assert_true(doc.find("api_key") != -1,
		"FLOOR on the doc side: it must actually contain the docstring, or the split returned nothing and the assert above is vacuous")


func test_a_comment_naming_the_key_is_not_an_offender() -> void:
	## NEGATIVE CONTROL. GameState:96 and this file's own header both name the field in prose; a
	## scan that flagged them would be silenced by an allowlist within a week.
	var commented: String = "\tprint(\"hello\")  # api_key is deliberately absent here\n"
	var lines: PackedStringArray = _code_lines(commented)
	assert_eq(lines[0].find("api_key"), -1, "control: the comment strip must remove the token")
	assert_true(_is_log_site(lines[0]), "control: the log site itself must survive the strip")
