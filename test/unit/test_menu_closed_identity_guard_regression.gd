extends GutTest

## msg 2503/2529: two-menus root cause NAMED via the diagnostic timeline
## shipped in ba65bb69. Repro sequence:
##
##   t=138685  path=actions_submitted   ← Rogue submits
##   t=138689  spawn combatant=Bard     ← +4ms Bard's menu is created (active=Bard)
##   t=138692  path=menu_closed_signal  ← +3ms Rogue's deferred force_close emits
##                                        menu_closed → old handler blindly nulled
##                                        active_win98_menu (which was Bard!) →
##                                        watchdog respawns on top → 2 menus
##
## Fix: bind the menu instance at connect time and identity-guard the
## null-write in _on_win98_menu_closed. Signature becomes
## _on_win98_menu_closed(closing_menu: Node = null); if the closing menu
## is not the currently-active one, the handler MUST early-return without
## nulling — the newer menu stays live and the watchdog stays reset.
##
## Backwards compat: default arg = null keeps the handler safe when
## invoked from any future emit path that doesn't route through the bind
## (falls back to unconditional null-write, same as pre-fix).

const BCM_PATH: String = "res://src/battle/BattleCommandMenu.gd"


## ── Source-pin: the bind + identity guard shape ───────────────────────

func test_connect_binds_menu_instance() -> void:
	# The connect site MUST bind the specific menu instance so the handler
	# has an identity to check against. Without bind, the handler receives
	# no arg (closing_menu=null default) and reverts to blind null-write.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	assert_string_contains(src, "menu_closed.connect(_on_win98_menu_closed.bind(_scene.active_win98_menu))",
		"connect site must bind the freshly-created menu instance so _on_win98_menu_closed knows WHICH menu is closing")


func test_handler_signature_takes_optional_closing_menu() -> void:
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	assert_string_contains(src, "func _on_win98_menu_closed(closing_menu: Node = null) -> void:",
		"handler must accept the bound menu instance (defaulted to null for backwards-compat with unbound emitters)")


func test_handler_early_returns_when_active_is_a_different_menu() -> void:
	# The core of the fix: if closing_menu != active_win98_menu, the newer
	# menu is live and we must not null it. If someone removes this guard
	# in a future refactor, the msg 2503 two-menus bug returns immediately.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	var idx: int = src.find("func _on_win98_menu_closed(closing_menu: Node = null) -> void:")
	assert_gt(idx, -1)
	# Docstring is long; scan the full function body until the next top-level func.
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 2500)
	assert_string_contains(body, "_scene.active_win98_menu != closing_menu",
		"handler must compare active against the emitting menu")
	assert_string_contains(body, "return",
		"the identity mismatch must cause an early return — otherwise the null-write orphans the newer menu")


func test_handler_still_nulls_when_active_is_the_closing_menu() -> void:
	# The other side: when they match, we DO null. Otherwise the ref stays
	# stale pointing at a queue_freed menu and downstream checks that
	# consult is_instance_valid() will start returning false unexpectedly.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	var idx: int = src.find("func _on_win98_menu_closed(closing_menu: Node = null) -> void:")
	# Docstring is long; scan the full function body until the next top-level func.
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 2500)
	assert_string_contains(body, "_scene.active_win98_menu = null",
		"when the guard passes, the ref must actually get nulled")


## ── Behavioral: the identity guard actually protects the newer menu ────

## Minimal stub for BattleScene — the handler only reaches _scene.active_win98_menu.
class _SceneStub extends Node:
	var active_win98_menu: Node = null


func _make_menu(name: String) -> Node:
	# A concrete Node stands in for a Win98Menu; the handler doesn't call
	# any menu API on the closing_menu arg, just uses it for identity.
	var n := Node.new()
	n.name = name
	add_child_autofree(n)
	return n


func _make_bcm() -> Object:
	# BCM extends RefCounted with a _scene field it reads from. Build a
	# stub scene and construct BCM against it.
	var scene := _SceneStub.new()
	add_child_autofree(scene)
	var BCMScript = load(BCM_PATH)
	var bcm = BCMScript.new(scene)
	return bcm


func test_identity_guard_preserves_newer_menu_when_stale_close_fires() -> void:
	# The exact msg 2529 timeline scenario. active is Bard's menu; Rogue's
	# stale menu_closed fires. Handler must NOT null active_win98_menu.
	var bcm = _make_bcm()
	var scene = bcm._scene
	var rogue_menu = _make_menu("RogueMenu")
	var bard_menu = _make_menu("BardMenu")
	# State at fire time: Bard's menu already spawned (active=Bard).
	scene.active_win98_menu = bard_menu
	# Rogue's stale menu_closed fires with the Rogue menu bound in.
	bcm._on_win98_menu_closed(rogue_menu)
	assert_eq(scene.active_win98_menu, bard_menu,
		"stale menu_closed from Rogue must NOT null active_win98_menu — Bard's menu stays live")


func test_identity_guard_still_nulls_when_active_is_the_closing_menu() -> void:
	# The normal path: menu_closed fires from the currently-active menu.
	# Handler nulls the ref as before.
	var bcm = _make_bcm()
	var scene = bcm._scene
	var only_menu = _make_menu("OnlyMenu")
	scene.active_win98_menu = only_menu
	bcm._on_win98_menu_closed(only_menu)
	assert_eq(scene.active_win98_menu, null,
		"normal path: emit menu matches active → null the ref as before")


func test_backwards_compat_unbound_call_nulls_the_ref() -> void:
	# The default closing_menu=null preserves pre-fix behavior for any
	# hypothetical emit path that doesn't use the bind. Calling with no
	# arg unconditionally nulls (same as pre-fix). This keeps the safety
	# net for future callers who might emit menu_closed without going
	# through the standard connect.
	var bcm = _make_bcm()
	var scene = bcm._scene
	var some_menu = _make_menu("SomeMenu")
	scene.active_win98_menu = some_menu
	bcm._on_win98_menu_closed()
	assert_eq(scene.active_win98_menu, null,
		"no-arg call (closing_menu=null default) preserves pre-fix null behavior")


func test_null_active_short_circuits_regardless_of_bound_menu() -> void:
	# When active is already null (e.g. a previous handler already nulled
	# it), a subsequent menu_closed emit shouldn't re-null and shouldn't
	# throw. The guard is null-safe on both sides.
	var bcm = _make_bcm()
	var scene = bcm._scene
	var stale_menu = _make_menu("StaleMenu")
	scene.active_win98_menu = null
	bcm._on_win98_menu_closed(stale_menu)
	assert_eq(scene.active_win98_menu, null,
		"already-null active stays null; no crash")
