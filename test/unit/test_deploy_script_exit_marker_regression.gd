extends GutTest

## 2026-07-13: deploy_web.sh under `| tee` swallowed the script's `exit 5` at
## web-smoke-BLOCKED because tee always exits 0. Two ambiguous deploys this
## session claimed LIVE while itch was actually on the prior version. Fix:
## exit-code marker files (tmp/.deploy_success on completion, .deploy_failure
## on any abnormal exit via trap). Callers check the marker, not $?. Pin the
## marker discipline as a source contract.


const DEPLOY_PATH := "res://tools/deploy_web.sh"


func _read() -> String:
	return FileAccess.get_file_as_string(DEPLOY_PATH)


func test_deploy_script_writes_success_marker_on_completion() -> void:
	var src := _read()
	assert_true("touch tmp/.deploy_success" in src,
		"deploy_web.sh must touch tmp/.deploy_success at the end so callers can verify actual completion (not just `| tee`'s exit 0)")
	# Success marker must appear AFTER the LIVE line — else a mid-script exit
	# could still leave a stale success marker from a prior run.
	var live_i := src.find("[deploy] LIVE:")
	var success_i := src.find("touch tmp/.deploy_success")
	assert_gt(live_i, -1, "LIVE line must exist")
	assert_gt(success_i, live_i,
		"success marker must be written AFTER the LIVE echo — writing it earlier lets a mid-gate exit leave a false-success marker")


func test_deploy_script_traps_exit_for_failure_marker() -> void:
	var src := _read()
	assert_true("trap" in src and ".deploy_failure" in src,
		"deploy_web.sh must trap EXIT to write tmp/.deploy_failure on any abnormal exit path — else a script-side `exit 5` silently vanishes under `| tee`")
	assert_true("_DEPLOY_OK" in src,
		"trap must gate on a sentinel variable set only on the success path — else the failure marker fires even when the deploy succeeds")


func test_deploy_script_clears_markers_at_start() -> void:
	# A stale marker from a prior run would give a false positive on a fresh
	# invocation that fails before the trap fires. Both markers must be
	# cleared at start.
	var src := _read()
	var start_i := src.find("cd \"$(cd \"$(dirname \"$0\")/..")
	assert_gt(start_i, -1)
	var head := src.substr(start_i, 800)
	assert_true("rm -f tmp/.deploy_success tmp/.deploy_failure" in head,
		"deploy_web.sh must clear stale markers early so a prior run can't leak a false success signal")
