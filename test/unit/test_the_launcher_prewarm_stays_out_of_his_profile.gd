extends GutTest

## `launch.sh` runs `godot --headless --import` to refresh the class cache before starting his
## game, and it ran UNSANDBOXED. `--import` is EDITOR-CLASS -- it carries the same E flag as
## --editor, and --headless means no window, NOT "not the editor" -- so it writes
## `.recovery_mode_lock` and a multi-MB editor shader cache into whichever profile is active, and
## spends a `user://logs/` rotation slot on a 71-byte banner-only stub. Unsandboxed, that is HIS
## profile, seconds before his game starts.
##
## 🔑 THE FLEET ALREADY ESTABLISHED THIS AND APPLIED IT EVERYWHERE ELSE. `tools/deploy_desktop.sh`,
## `deploy_web.sh` and `publish_all.sh` carry the identical prewarm behind
## `XDG_DATA_HOME="$PWD/tmp/prewarm_xdg"`, with the measurement in deploy_desktop.sh:170 -- a lock
## stamped 10:40 on his live profile, the minute that line ran during the .358 publish. The import
## CACHE lives in `res://.godot`, inside the project, so the redirect costs the prewarm nothing.
## launch.sh was the one caller never given the same treatment.
##
## ⛔ AND THE REASON IT SURVIVED IS A DECLARATION, NOT AN OVERSIGHT.
## `tools/check_user_data_sandboxed.py` exempts `launch.sh` by PATH, so it printed
## `20 sandboxed · 2 declared · 0 UNSANDBOXED · EC=0` -- all-clear -- while both imports ran
## against his profile. The exemption's stated reason is "the player's own launcher - running
## against the real profile is its purpose", which is true of the BARE `godot &` launch and false
## of an import prewarm. Measured: the two lines it declared were 40 and 45, BOTH IMPORTS, and it
## declared the launch at :50 not at all, because `godot &` has no `--` and never matches the
## detector's EDITOR_CLASS pattern. It was 0-for-2 on its own justification.
##
## ⚠️ STATED LIMIT, with its failure direction: "command position" does not match a WRAPPED
## invocation (`timeout 60 godot --import`, or the `./tools/bounded_godot.sh -- godot …` form the
## deploy scripts use). If launch.sh ever adopts a wrapper, this guard sees ZERO editor-class
## invocations and the vacuity assert in the import arm REDS -- loud, not silent. Verified against
## 12 probe strings including both wrapper forms, so the blind spot is known rather than assumed.
##
## ⚠️ THIS GUARD DEFENDS BOTH DIRECTIONS, because the opposite change is also a bug: exporting the
## redirect, or sandboxing the launch itself, would send HIS SAVES to a gitignored temp dir. That
## is the one documented case where sandboxing is wrong (CLAUDE.md: classify by INTENT, not by the
## flag), so the launch arm below asserts the ABSENCE of a redirect as firmly as the import arms
## assert its presence.

const LAUNCHER := "res://launch.sh"

## Every env var that relocates `user://` in this repo. A guard written for one name is blind to
## the others -- a lane grepped for XDG_DATA_HOME alone, found none on the battle smoke and
## reported it unsandboxed when HOME and WINEPREFIX were doing the job one line up. Kept identical
## to check_user_data_sandboxed.py's REDIRECTS so the two cannot disagree about one file.
const REDIRECTS := ["XDG_DATA_HOME=", "HOME=", "WINEPREFIX="]


func _logical_lines() -> Array:
	## Shell continuations joined, whole-line and trailing comments dropped -- a line that
	## MENTIONS an import is not a line that runs one, and this file's own header names
	## `--import` and `--editor` in prose.
	var raw: String = FileAccess.get_file_as_string(LAUNCHER)
	var out: Array = []
	var buf: String = ""
	var start: int = 0
	var n: int = 0
	for line in raw.split("\n"):
		n += 1
		var s: String = (line as String)
		if buf == "":
			start = n
		if s.ends_with("\\"):
			buf += s.substr(0, s.length() - 1) + " "
			continue
		buf += s
		var code: String = buf if not buf.strip_edges().begins_with("#") else ""
		var hash_at: int = code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		if code.strip_edges() != "":
			out.append([start, code])
		buf = ""
	return out


## COMMAND POSITION, not "the line contains godot". A line that MENTIONS the binary is not a line
## that runs it: `pgrep -x godot`, `readlink /proc/$p/exe` and `CACHE=".godot/..."` all contain the
## token and invoke nothing. Leading `VAR=value` assignments are skipped so a redirect PREFIX still
## leaves godot in command position -- which is the whole point, since the prefix is the fix.
const CMD_POSITION := "^\\s*(?:[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|\\S*)\\s+)*godot(?:\\s|$)"


func _invokes_godot(code: String) -> bool:
	var re := RegEx.new()
	re.compile(CMD_POSITION)
	return re.search(code) != null


func _is_editor_class(code: String) -> bool:
	## An invocation carrying a flag: --import, --headless, --check-only, -s. Same family as the
	## fleet checker's EDITOR_CLASS, but gated on command position so a mention cannot qualify.
	if not _invokes_godot(code):
		return false
	var re := RegEx.new()
	re.compile("(?<!\\w)godot\\s+-")
	return re.search(code) != null


func _is_the_players_launch(code: String) -> bool:
	## ⛔ DEFINED AS THE COMPLEMENT, NOT AS THE LITERAL `godot &`. My first version matched
	## `^\\s*godot\\s*&$`, and a redirect PREFIX breaks that anchor -- so caging the launch made the
	## line stop being recognised as a launch at all, the arm red on vacuity instead of on the
	## defect, and the `caged` clause became code that could never fire. A clause that cannot fail
	## returns the answer you were already holding. Caught by simulating the mutation, not by review.
	return _invokes_godot(code) and not _is_editor_class(code)


func _redirect_governs(code: String) -> bool:
	for r in REDIRECTS:
		if code.contains(r):
			return true
	return false


func test_the_launcher_is_readable_at_all() -> void:
	## VOID arm. Every other arm below is a claim about lines found in this file; if the read
	## fails, each of them passes over an EMPTY population and the file is green about nothing.
	var raw: String = FileAccess.get_file_as_string(LAUNCHER)
	assert_gt(raw.length(), 500,
		"VOID: could not read %s (%d chars) -- every arm in this file is then vacuous" % [LAUNCHER, raw.length()])
	var ll: Array = _logical_lines()
	assert_gt(ll.size(), 10,
		"VOID: %s yielded %d logical lines, so the comment strip ate the script" % [LAUNCHER, ll.size()])
	## THE PARTITION. Every command-position godot invocation must be exactly one of the two kinds
	## the arms below judge. If a future form is neither, no arm sees it and both stay green.
	var invocations: int = 0
	var classified: int = 0
	for entry in ll:
		var code: String = entry[1]
		if not _invokes_godot(code):
			continue
		invocations += 1
		if _is_editor_class(code) != _is_the_players_launch(code):
			classified += 1
	assert_gt(invocations, 0, "VOID: no godot invocation found in %s at all" % LAUNCHER)
	assert_eq(classified, invocations,
		"%d of %d godot invocations in %s are neither an editor-class run nor a launch, so no arm below judges them" % [invocations - classified, invocations, LAUNCHER])


func test_every_editor_class_invocation_is_sandboxed() -> void:
	var found: int = 0
	var naked: Array[String] = []
	for entry in _logical_lines():
		var code: String = entry[1]
		if not _is_editor_class(code):
			continue
		found += 1
		if not _redirect_governs(code):
			naked.append("%s:%d  %s" % [LAUNCHER, entry[0], code.strip_edges()])
	## Anti-vacuity: the arm is about a population, so prove the population is non-empty. NOT
	## pinned to 2 -- a legitimate third sandboxed prewarm must not red this.
	assert_gt(found, 0,
		"VOID: no editor-class godot invocation found in %s, so this arm measured nothing. Either the prewarm was removed or the predicate stopped matching" % LAUNCHER)
	assert_eq(naked, [],
		("these editor-class invocations run against whichever user:// is active -- unsandboxed that is "
		+ "struktured's REAL profile, writing .recovery_mode_lock and an editor shader cache and spending "
		+ "a logs/ rotation slot seconds before his game starts: %s") % [naked])


func test_the_players_own_launch_is_NOT_sandboxed() -> void:
	## ⛔ THE OPPOSITE DEFECT, and it is worse than the one above: his saves would go to a
	## gitignored temp dir that gets deleted. His `user://` IS the destination here.
	var launches: int = 0
	var caged: Array[String] = []
	for entry in _logical_lines():
		var code: String = entry[1]
		if not _is_the_players_launch(code):
			continue
		launches += 1
		if _redirect_governs(code):
			caged.append("%s:%d  %s" % [LAUNCHER, entry[0], code.strip_edges()])
	assert_gt(launches, 0,
		"VOID: found no bare `godot &` launch in %s -- the launcher no longer launches, or the Wayland-mandated bare form was changed" % LAUNCHER)
	assert_eq(caged, [],
		"the player's launch carries a user:// redirect, so his saves, settings and logs go to a gitignored temp dir instead of his profile: %s" % [caged])


func test_no_export_leaks_the_sandbox_into_the_launch() -> void:
	## A per-command prefix governs ONE command. An `export` governs everything after it, which
	## would silently cage the launch two arms above -- and that arm cannot see it, because the
	## redirect would not be on the launch's own line.
	var re := RegEx.new()
	re.compile("^\\s*export\\s+(XDG_DATA_HOME|HOME|WINEPREFIX)=")
	var hits: Array[String] = []
	for entry in _logical_lines():
		if re.search(entry[1]) != null:
			hits.append("%s:%d  %s" % [LAUNCHER, entry[0], (entry[1] as String).strip_edges()])
	assert_eq(hits, [],
		("%s exports a user:// redirect. An export outlives the command it was meant for, so the bare "
		+ "`godot &` launch inherits it and his saves land in a temp dir -- and the per-line arm above "
		+ "stays green, because the redirect is not on the launch's line: %s") % [LAUNCHER, hits])
