# Innovation Session — 2026-03-13

## What I Found

Audited git log (recent: sprite scaling fixes, cleric SDXL integration) and prior reports.
Group Attack system is fully implemented (backend + menu UI). Ran full test suite: 41/41
battle calculations, 6/21 battle state (15 pending — BattleManager autoload unavailable
headless, known/expected).

## Bug Found: All-Out Attack Charged Wrong AP Cost

### Root Cause
`_execute_group_action()` in `BattleManager.gd` (line 1177) checked:
```gdscript
var ap_cost: int = 1 if group_type == "all_out" else 4
```

But `player_group_attack()` and `BattleCommandMenu` both pass `"all_out_attack"` (not `"all_out"`).

**Result**: Every All-Out Attack triggered from the menu silently charged 4 AP (Limit Break rate) instead of 1. Players would be unable to use All-Out Attack without first accumulating 4 AP on every party member — the same requirement as Limit Break. The "disabled" check in the menu used the correct logic, so the button would be enabled at 1 AP, but execution would drain 4 AP and potentially crash members into deep AP debt.

### Fix
Changed the condition to use positive matching on the known value:
```gdscript
var ap_cost: int = 4 if group_type == "limit_break" else 1
```
This is robust to any future group type additions. Also:
- Normalized `_execute_group_action` default fallback: `"all_out"` → `"all_out_attack"`
- Updated `player_group_attack()` docstring

### Regression Tests Added
3 new tests in `test_battle_calculations.gd` (now 41/41):
- `test_group_attack_ap_cost_all_out_attack` — confirms 1 AP cost
- `test_group_attack_ap_cost_limit_break` — confirms 4 AP cost  
- `test_group_attack_ap_cost_old_name_would_be_wrong` — documents the string mismatch that caused the bug

### Validation
- `godot --headless --import`: clean, no errors
- `test_battle_calculations.gd`: 41/41 passed (was 38/38 before new tests)

### Commit
`71ef3ca` — fix: group All-Out Attack charged 4 AP instead of 1

### Files Changed
- `src/battle/BattleManager.gd` — 3 lines changed
- `test/unit/test_battle_calculations.gd` — 21 lines added

## Next Steps
- Test group attack end-to-end in gameplay (need live Godot session)
- Add Limit Break visual flash effect (screen-wide orange/gold pulse on execution)
- Consider adding `group_attack_executing` signal handler in BattleScene for simultaneous party animations
