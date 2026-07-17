extends GutTest

## BattleScene connects ~28 BattleManager signals in _ready but only
## disconnected 23 in _exit_tree before this fix. Five were missed:
##   boss_jailbreak_landed
##   boss_taunt
##   meta_autobattle_editor_requested
##   trust_interrupt_window_opened
##   trust_interrupt_window_closed
##
## Godot's auto-disconnect-on-Object-free covers the leak in practice —
## BattleScene is a Node, so when it queue_frees the callables attached
## to `self` clear from BattleManager (autoload, persists across battles).
## But the existing _exit_tree block wires 23 disconnects explicitly with
## `is_connected` guards, which is a defensive discipline the 5 missing
## signals broke. This test pins the symmetry so a future signal added
## to _ready gets a matching disconnect too.

const BS_PATH: String = "res://src/battle/BattleScene.gd"


func _read_source() -> String:
	return FileAccess.get_file_as_string(BS_PATH)


func _extract_signal_names(pattern: String) -> Array:
	# Grep the source for lines matching `BattleManager.<signal>.<pattern>(`
	# and extract the <signal> substring. Deduped.
	var src: String = _read_source()
	var lines: PackedStringArray = src.split("\n")
	var found: Dictionary = {}
	var needle: String = ".%s(" % pattern
	for line in lines:
		var trimmed: String = line.strip_edges()
		var head_needle: String = "BattleManager."
		var head_idx: int = trimmed.find(head_needle)
		if head_idx < 0:
			continue
		var after_head: String = trimmed.substr(head_idx + head_needle.length())
		var end_needle: int = after_head.find(needle)
		if end_needle <= 0:
			continue
		# after_head starts with "<signal_name>.<pattern>(...)"
		# grab up to the first "."
		var dot_idx: int = after_head.find(".")
		if dot_idx <= 0:
			continue
		var sig_name: String = after_head.substr(0, dot_idx)
		# Guard: must be a plain identifier (no spaces, no operators).
		if sig_name.length() == 0 or sig_name.contains(" ") or sig_name.contains("("):
			continue
		found[sig_name] = true
	return found.keys()


## ── Every connected signal has a matching disconnect ──────────────────

func test_every_connected_signal_has_matching_disconnect() -> void:
	# The point of the fix: symmetry between connects (in _ready) and
	# disconnects (in _exit_tree). Any signal in the connect set that's
	# missing from the disconnect set is a discipline break.
	var connects: Array = _extract_signal_names("connect")
	var disconnects: Array = _extract_signal_names("disconnect")
	assert_gt(connects.size(), 10, "sanity: found at least 10 connected signals (got %d)" % connects.size())
	assert_gt(disconnects.size(), 10, "sanity: found at least 10 disconnected signals (got %d)" % disconnects.size())

	var missing: Array = []
	for sig in connects:
		if not (sig in disconnects):
			missing.append(sig)

	assert_eq(missing.size(), 0,
		"the following BattleManager signals are .connect'd in _ready but never .disconnect'd in _exit_tree — auto-cleanup on Node free covers the leak, but explicit disconnects match the discipline of the surrounding block: %s" % str(missing))


## ── Specifically pin the 5 signals this fix added ─────────────────────

func test_missing_five_signals_are_now_disconnected() -> void:
	# Guard against future revert: name the exact 5 signals that were
	# missed pre-fix so a bisect catches the regression clearly.
	var src: String = _read_source()
	var exit_idx: int = src.find("func _exit_tree() -> void:")
	assert_gt(exit_idx, -1)
	var next: int = src.find("\nfunc ", exit_idx + 1)
	var body: String = src.substr(exit_idx, (next - exit_idx) if next > -1 else 4000)
	var required: Array = [
		"trust_interrupt_window_opened.disconnect",
		"trust_interrupt_window_closed.disconnect",
		"meta_autobattle_editor_requested.disconnect",
		"boss_taunt.disconnect",
		"boss_jailbreak_landed.disconnect",
	]
	for needle in required:
		assert_string_contains(body, needle,
			"_exit_tree must .disconnect the %s signal (fix cycle 6, msg 2608 batch follow-up)" % needle)


## ── Guarded with has_signal to survive BattleManager API drift ────────

func test_five_new_disconnects_use_has_signal_guard() -> void:
	# The connect sites (BS:339-364) all gate on BattleManager.has_signal("X").
	# The disconnect side must match — if a signal is removed from
	# BattleManager, an unguarded .disconnect would push_error at scene
	# teardown even though the connect was skipped.
	var src: String = _read_source()
	var exit_idx: int = src.find("func _exit_tree() -> void:")
	var next: int = src.find("\nfunc ", exit_idx + 1)
	var body: String = src.substr(exit_idx, (next - exit_idx) if next > -1 else 4000)
	var guarded: Array = [
		"has_signal(\"trust_interrupt_window_opened\")",
		"has_signal(\"trust_interrupt_window_closed\")",
		"has_signal(\"meta_autobattle_editor_requested\")",
		"has_signal(\"boss_taunt\")",
		"has_signal(\"boss_jailbreak_landed\")",
	]
	for needle in guarded:
		assert_string_contains(body, needle,
			"disconnect for signal %s must be has_signal-guarded so BM API drift doesn't push_error at teardown" % needle)
