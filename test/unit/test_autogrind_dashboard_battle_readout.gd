extends GutTest

## Cadence #26 — AutogrindDashboard's "BATTLE VIEW" panel shipped a SubViewport
## that renders nothing but background colour, so an autogrind user watching a
## tier-2 session stared at a labelled empty box.
##
## The proper fix (reparent a live BattleScene into the viewport) is PARKED by
## joint decision with cowir-battle (msg 2904): BattleScene now carries several
## one-per-battle latches — the _last_acting_combatant signal cache, the menu
## watchdog's retry-cap + terminal fallback, cowir-main's showcase damage-buffer
## flush, and the spotlight force_battle_teardown path. A second live instance
## would need every one of those correctly instance-scoped. That's an ownership
## refactor with a design owner, not a reparent.
##
## So this is a deliberate STOPGAP, greenlit by cowir-battle (msg 2904) and
## routed by cowir-main (msg 2917) under two guardrails: keep it genuinely
## minimal, and keep it obviously disposable — it must delete in one commit if
## the reparent ever happens. These tests pin BOTH the behaviour and the
## disposability.

const DashboardScript := preload("res://src/ui/autogrind/AutogrindDashboard.gd")


func _make_combatant(cname: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": max_hp, "max_mp": 10,
		"attack": 10, "defense": 5, "magic": 5, "speed": 10,
	})
	c.current_hp = hp
	add_child_autofree(c)
	return c


func _make_dashboard() -> Node:
	# Bare instance — _build_ui is call_deferred and needs a real viewport, so
	# these tests drive the readout state machine directly rather than through UI.
	var d = DashboardScript.new()
	add_child_autofree(d)
	return d


# ── Behaviour ────────────────────────────────────────────────────────────────

func test_idle_text_when_no_battle() -> void:
	var d := _make_dashboard()
	d._battle_readout = Label.new()
	add_child_autofree(d._battle_readout)
	d._refresh_battle_readout()
	assert_eq(d._battle_readout.text, d._BATTLE_READOUT_IDLE,
		"with no battle in progress the panel must say so explicitly — the pre-cadence-#26 bug was an UNLABELLED empty box, which reads as broken rather than idle")


func test_round_started_populates_readout() -> void:
	var d := _make_dashboard()
	d._battle_readout = Label.new()
	add_child_autofree(d._battle_readout)
	d._on_readout_round_started(3)
	assert_true(d._battle_readout.text.contains("Round 3"),
		"round_started must surface the round number — the single most useful 'is it progressing?' signal during a long grind")


func test_action_executing_uses_signal_arg_not_current_combatant() -> void:
	# THE important one. BattleManager.current_combatant is STALE mid-execution
	# (cowir-battle cycle 12). Polling it would name the wrong actor and give no
	# indication anything was wrong. The readout must take the actor from the
	# signal payload.
	var d := _make_dashboard()
	d._battle_readout = Label.new()
	add_child_autofree(d._battle_readout)
	var actor := _make_combatant("Mira", 100, 100)
	d._on_readout_round_started(1)
	d._on_readout_action_executing(actor, {"type": "attack"})
	assert_true(d._battle_readout.text.contains("Mira"),
		"the acting combatant must come from the action_executing signal args — reading BattleManager.current_combatant instead would name a stale actor mid-execution (cowir-battle cycle 12)")


func test_damage_dealt_reports_target_and_amount() -> void:
	var d := _make_dashboard()
	d._battle_readout = Label.new()
	add_child_autofree(d._battle_readout)
	var target := _make_combatant("Slime", 40, 100)
	d._on_readout_round_started(1)
	d._on_readout_damage_dealt(target, 37, false, "", 1.0)
	assert_true(d._battle_readout.text.contains("Slime") and d._battle_readout.text.contains("37"),
		"last-hit line must name target + amount")


func test_crit_and_weakness_are_distinguished() -> void:
	var d := _make_dashboard()
	d._battle_readout = Label.new()
	add_child_autofree(d._battle_readout)
	var target := _make_combatant("Bat", 10, 50)
	d._on_readout_round_started(1)

	d._on_readout_damage_dealt(target, 50, true, "", 1.0)
	assert_true(d._battle_readout.text.contains("CRIT"),
		"crits must be visibly tagged — a grind watcher wants to see the spikes")

	d._on_readout_damage_dealt(target, 60, false, "fire", 1.5)
	assert_true(d._battle_readout.text.contains("WEAK"),
		"elemental_mod > 1.0 must be tagged — it's the signal that the autobattle rules are picking correct elements, which is the whole point of tuning them")


func test_battle_ended_returns_to_idle() -> void:
	# Between battles the panel must not display a frozen last-frame, which would
	# read as a hung grind.
	var d := _make_dashboard()
	d._battle_readout = Label.new()
	add_child_autofree(d._battle_readout)
	d._on_readout_round_started(7)
	d._on_readout_action_executing(_make_combatant("Kael", 90, 90), {"type": "attack"})
	d._on_readout_battle_ended(true)
	assert_eq(d._battle_readout.text, d._BATTLE_READOUT_IDLE,
		"battle_ended must clear back to idle — a stale frozen readout between battles is indistinguishable from a wedged grind")


func test_refresh_is_safe_with_no_label() -> void:
	# _build_ui is deferred; signals can arrive before the Label exists.
	var d := _make_dashboard()
	d._battle_readout = null
	d._on_readout_round_started(2)
	d._on_readout_damage_dealt(_make_combatant("X", 1, 1), 5, false, "", 1.0)
	d._on_readout_battle_ended(false)
	assert_true(true, "readout handlers must no-op safely before _build_ui creates the Label (deferred build vs. live signals)")


func test_wire_is_safe_without_battlemanager() -> void:
	var d := _make_dashboard()
	d._wire_battle_readout()
	assert_true(true, "_wire_battle_readout must no-op when BattleManager is absent (bare-instance tests, main menu)")


# ── Disposability (cowir-main guardrail, msg 2917) ───────────────────────────

func test_stopgap_is_documented_as_removable() -> void:
	# The guardrail was "obviously disposable — deletes in one commit, not needing
	# unpicking." A future maintainer must be able to find every piece from the
	# code alone, without reading intercom history.
	var src: String = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	assert_true(src.contains("STOPGAP (cadence #26)"),
		"the stopgap must be labelled STOPGAP in-source so it's greppable as removable")
	assert_true(src.contains("_wire_battle_readout"),
		"the removal instructions must name the function to delete alongside the panel block")


func test_stopgap_did_not_remove_the_viewport() -> void:
	# The SubViewport stays. Deleting it would make the eventual reparent a bigger
	# job and would break get_battle_viewport()'s contract — the stopgap must not
	# make the real fix harder.
	var src: String = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	assert_true(src.contains("func get_battle_viewport() -> SubViewport"),
		"get_battle_viewport must survive the stopgap — the reparent path stays open")
	assert_true(src.contains("_battle_viewport = SubViewport.new()"),
		"the SubViewport itself must survive — the stopgap overlays it, it does not replace it")


func test_no_polling_no_process_loop() -> void:
	# Guardrail: "signal-driven, no state machine, no caching layer." A _process
	# hook reading battle state each frame is exactly what cowir-battle warned
	# against (races the execution phase, reads stale current_combatant).
	var src: String = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	var start: int = src.find("func _wire_battle_readout")
	assert_true(start >= 0, "setup: _wire_battle_readout must exist")
	var end: int = src.find("func _readout_enemy_line", start)
	var block: String = src.substr(start, end - start)
	assert_false(block.contains("func _process"),
		"the readout must be signal-driven — a per-frame poll would race the execution phase and read a stale current_combatant")
	assert_true(block.contains("CONNECT_REFERENCE_COUNTED"),
		"connections must be reference-counted so a dashboard rebuild cannot double-connect and double-count updates")
