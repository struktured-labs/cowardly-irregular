Self-improvement loop for Cowardly Irregular codebase. Run one cycle per invocation — pick the highest-priority unfixed item, fix it, validate, and report what's left.

## Priority Queue (work top-down, skip items marked DONE)

### Tier 1: Critical Bugs
1. DONE — SaveSystem now finds OverworldPlayer via "player" group instead of nonexistent PlayerController. Player position actually saves now.
2. DONE — Escape emits battle_ended with `"escaped"` result directly instead of calling end_battle(false) defeat path.
3. DONE — `time_distortion` now stores original speed in `_base_speed` metadata on first mutation, reads from it each round instead of compounding.
4. DONE — Double `_get_alive_enemies()` call replaced with single local var.
5. `src/battle/BattleScene.gd:2495-2497` — Summoned enemy signal binds use stale index. Use enemy reference directly instead of array index.
6. `src/battle/BattleScene.gd:2306,2408` — `pivot_offset = label.size / 2` reads size before layout. Defer to next frame or use `resized` signal.

### Tier 2: Dead Code Removal
7. `src/GameLoop.gd` — Remove dead `_start_battle()` (sync version, line ~819), dead `_show_menu()`/`LoopState.MENU` (line ~886), dead `_load_battle_behind_transition()` (line ~1181), unused vars (`_autogrind_dashboard`, `_autogrind_overlay`, `_autogrind_overlay_layer`, `_controller_overlay`, `_controller_overlay_layer`, `_party_customizations`).
8. `src/autobattle/AutobattleSystem.gd` — Remove ~900 lines of dead legacy execution pipeline (`execute_autobattle`, `_evaluate_rule`, `_evaluate_condition`, `_compare`, `_rule_to_action`, `_action_type_to_string`, `_get_target_for_rule`, the `ConditionType`/`CompareOp`/`ActionType` enums, `saved_scripts`/`save_script`/`load_script`). Only `execute_grid_autobattle` is used.
9. `src/battle/BattleScene.gd` — Remove dead `_create_character_sprite` (~line 831) and `_create_enemy_sprite` (~line 870). Remove dead `_on_player_hp_changed`/`_on_player_ap_changed` legacy aliases (~line 2053).
10. Delete 3 dead files: `src/ui/VirtualGamepad.gd`, `src/battle/AdaptiveAI.gd`, `src/exploration/OverworldInteractable.gd`.
11. `src/exploration/OverworldPlayer.gd` — Remove dead `walk_frames` building code in `_try_load_artist_sprites` (frames are built but cache only uses idle_frames).
12. `src/maps/MapSystem.gd` — The entire transition system (`load_map`, `transition_to_map`, `unload_current_map`, `enter_location`, `exit_location`) is never called from GameLoop. Either wire it in or mark as future/remove.

### Tier 3: Architecture Improvements
13. Extract village base class — 10 village scripts share ~150 lines of identical boilerplate (`_setup_scene`, `_setup_camera`, `_setup_controller`, `_setup_transition_collision`, `spawn_player_at`, `resume`, `pause`, `set_player_job`, `set_player_appearance`). Create `BaseVillage.gd` and refactor.
14. Consolidate border constants — `BORDER_LIGHT`/`BORDER_SHADOW` duplicated in 10+ files. Move to `RetroPanel.gd` as class constants, reference from menus.
15. `src/ui/RetroFont.gd` — Remove dead `apply_retro_theme()` and `generate_bitmap_font_texture()`.
16. `src/battle/BattleScene.gd` — Move `JOB_DISPLAY_HEIGHTS` from function-level const to class-level const.
17. `src/GameState.gd` — Remove or gate dead Time Mage rewind infrastructure, dead `macro_volatility`, dead parallel save system (`save_game`/`load_game`/`get_save_list`/`delete_save`).

### Tier 4: Performance
18. `src/battle/BattleScene.gd` — `_check_danger_music()` runs every frame in `_process`. Move to event-driven (call from `_on_party_hp_changed` only).
19. `src/exploration/AreaTransition.gd` — 11+ instances all call `queue_redraw()` every frame. Use `set_process(false)` when off-screen or use a shared timer.
20. `src/battle/BattleScene.gd` — `_process_idle_animations` calls `is_instance_valid` on every sprite every frame. Cache valid sprite list, update only on spawn/death.
21. `src/ui/autogrind/AutogrindDashboard.gd:176-197` — CRT scanline overlay spawns ~120 ColorRect nodes. Replace with shader or single `_draw()` call.
22. `src/exploration/OverworldScene.gd` — `_update_encounter_zone` tile division runs every frame even when player is still. Add `_last_tile_pos` guard.

### Tier 5: Polish
23. `src/audio/SoundManager.gd:344` — `_generate_double_blip()` never pushes audio frames. Fix or remove.
24. `src/exploration/OverworldScene.gd` — Mode 7 overlay sprite position hardcoded `(640, 400)`. Make viewport-relative.
25. `src/ui/OverworldMenu.gd:639` — Settings menu uses `load()` instead of `preload()`. Change to preload.
26. `src/jobs/PassiveSystem.gd:341` — `can_equip_passive` restriction check never called. Wire into `equip_passive`.
27. `src/save/SaveSystem.gd:331` — `_serialize_inventory` is a stub. Implement or document as TODO.
28. Consolidate duplicate `_input` handlers in `AutogrindMonitor.gd` and `AutogrindDashboard.gd` into shared base/utility.
29. Delete redundant sprite gen scripts in `tools/` (keep only `gen_fighter_walk_release.py`, remove 6 others).

## Rules
- Fix ONE item per cycle (or a small related cluster)
- Validate with `godot --headless --import` after every change
- Run tests if touching battle/combat code: `godot --headless -s test/run_tests.gd`
- Add regression test for any bug fix
- Mark completed items as DONE in this file
- Report: what was fixed, what's next, total remaining count
