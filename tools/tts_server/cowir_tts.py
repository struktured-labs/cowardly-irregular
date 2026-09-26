#!/usr/bin/env python3
"""Install, start, stop and check the supported local voice server for Cowardly Irregular.

The supported server is devnen/Chatterbox-TTS-Server pinned to DEVNEN_COMMIT with cowir.patch applied.
Stock devnen is wrong for us three ways (hard-clips theatrical takes, defaults to the Turbo model, binds
0.0.0.0) and exposes an unauthenticated web API to any page in the player's browser; the patch fixes all
four. This script is what the first-run setup wizard calls, so it never prompts.

    uv run tools/tts_server/cowir_tts.py install [--device cuda|cpu] [--dir DIR] [--allow-weak-host]
    uv run tools/tts_server/cowir_tts.py start   [--port 8004] [--dir DIR] [--timeout 600]
    uv run tools/tts_server/cowir_tts.py stop    [--dir DIR]
    uv run tools/tts_server/cowir_tts.py check   [--port 8004] [--dir DIR]      -> one JSON object on stdout

Exit codes (stable; the wizard branches on them):
    0  success / healthy
    2  bad usage
    3  not installed                      (start, check)
    4  install failed (network, git, uv, patch)
    5  server failed to start, or is installed but not answering
    6  a prerequisite is missing: git or uv not on PATH
    7  --device cuda requested but no NVIDIA GPU is visible
    8  this machine cannot host the server (no NVIDIA GPU, or too little free RAM); pass
       --allow-weak-host to install anyway, or run the server on another machine and tunnel it

`python3 cowir_tts.py --selftest` checks the host verdict against fixed inputs: no file opened,
no subprocess, no network, nothing written.
"""
import argparse, json, os, platform, shutil, signal, subprocess, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEVNEN_URL = "https://github.com/devnen/Chatterbox-TTS-Server.git"
DEVNEN_COMMIT = "915ae289340e10c6047f27f47e22eae9bf350c32"
CHATTERBOX_PKG = "git+https://github.com/devnen/chatterbox-v2.git@cc0357396d9c73fc1e6c544ee40bb596020edd09"
PATCH = os.path.join(HERE, "cowir.patch")
TUNING = os.path.join(HERE, "voice_tuning.json")
VOICE_REFS = os.path.join(REPO, "voice_refs")

EXIT_OK, EXIT_USAGE, EXIT_NOT_INSTALLED, EXIT_INSTALL, EXIT_START, EXIT_PREREQ, EXIT_NO_GPU = 0, 2, 3, 4, 5, 6, 7
EXIT_WEAK_HOST = 8

# Measured 2026-09-25: on an RTX 3090 box the server holds 2.2 GB of system RAM; on an 8-core Iris Xe laptop
# (CPU only, 7.6 GB) it held 3.6 GB, filled swap, and a 2.6 s line had not finished after 120 s.
MIN_FREE_RAM_GB = 4.0
TUNNEL_RECIPE = ("run the server on a machine with an NVIDIA GPU and forward it to this one as loopback:\n"
                 "    ssh -N -o ExitOnForwardFailure=yes -R 127.0.0.1:8004:127.0.0.1:8004 <this machine>\n"
                 "(run that on the GPU machine; the game's default Live Voice URL then needs no change)")


def default_dir() -> str:
    if platform.system() == "Windows":
        base = os.environ.get("LOCALAPPDATA", os.path.expanduser("~\\AppData\\Local"))
    elif platform.system() == "Darwin":
        base = os.path.expanduser("~/Library/Application Support")
    else:
        base = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return os.path.join(base, "cowardly-irregular", "tts-server")


def venv_python(d: str) -> str:
    return os.path.join(d, ".venv", "Scripts" if platform.system() == "Windows" else "bin",
                        "python.exe" if platform.system() == "Windows" else "python")


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)   # stdout is reserved for check's JSON


def run(cmd: list, cwd: str = None) -> None:
    log("$ " + " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def has_nvidia() -> bool:
    return shutil.which("nvidia-smi") is not None and \
        subprocess.run(["nvidia-smi", "-L"], capture_output=True).returncode == 0


def free_ram_gb():
    """Available RAM in GB, or None where it cannot be read without extra packages."""
    if platform.system() == "Linux":
        try:
            for line in open("/proc/meminfo"):
                if line.startswith("MemAvailable:"):
                    return int(line.split()[1]) / (1024 * 1024)
        except (OSError, ValueError):
            return None
    elif platform.system() == "Windows":
        import ctypes
        class MEMORYSTATUSEX(ctypes.Structure):
            _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                        ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                        ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                        ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                        ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
        m = MEMORYSTATUSEX()
        m.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m)):
            return m.ullAvailPhys / (1024 ** 3)
    return None


def host_verdict(gpu: bool, device: str, ram_gb):
    """Reasons this machine cannot host the server; empty means it can. Pure, so --selftest can pin it."""
    reasons = []
    if not gpu or device == "cpu":
        why = "no NVIDIA GPU is visible" if not gpu else "--device cpu was requested"
        reasons.append(f"{why}; on CPU alone a 2.6 s line took over 120 s on an 8-core Iris Xe laptop "
                       f"(the game gives up after 8 s)")
    if ram_gb is not None and ram_gb < MIN_FREE_RAM_GB:
        reasons.append(f"only {ram_gb:.1f} GB of RAM is free; the server holds 2.2 GB even on a GPU and needs "
                       f"{MIN_FREE_RAM_GB:.0f} GB free to leave room for the game")
    return reasons


def selftest() -> int:
    cases = [
        ((True, "cuda", 90.0), 0, "3090 box"),
        ((True, "cuda", None), 0, "RAM unreadable is not a refusal"),
        ((False, "cpu", 5.0), 1, "no GPU"),
        ((True, "cpu", 90.0), 1, "GPU present but cpu forced"),
        ((True, "cuda", 3.9), 1, "GPU but too little RAM"),
        ((False, "cpu", 2.0), 2, "the moonshot shape: both"),
    ]
    bad = 0
    for args, want, label in cases:
        got = host_verdict(*args)
        ok = len(got) == want
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {label}: {len(got)} reason(s), want {want}")
    moon = " ".join(host_verdict(False, "cpu", 2.0))
    for fact in ("no NVIDIA GPU", "120 s", "2.0 GB"):
        ok = fact in moon
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'} refusal names the measured fact {fact!r}")
    return EXIT_OK if bad == 0 else 1


def voices_wanted() -> dict:
    with open(TUNING, encoding="utf-8") as f:
        return json.load(f).get("voices", {})


def install(a) -> int:
    for tool in ("git", "uv"):
        if shutil.which(tool) is None:
            log(f"missing prerequisite: {tool}")
            return EXIT_PREREQ
    device = a.device or ("cuda" if has_nvidia() else "cpu")
    if device == "cuda" and not has_nvidia():
        log("--device cuda requested but nvidia-smi sees no GPU")
        return EXIT_NO_GPU
    weak = host_verdict(has_nvidia(), device, free_ram_gb())
    if weak and not a.allow_weak_host:
        log("this machine cannot host the voice server:")
        for r in weak:
            log(f"  - {r}")
        log(TUNNEL_RECIPE)
        log("to install here anyway, pass --allow-weak-host")
        return EXIT_WEAK_HOST
    if weak:
        log("installing on a weak host because --allow-weak-host was passed: " + "; ".join(weak))
    d = a.dir
    try:
        if not os.path.isdir(os.path.join(d, ".git")):
            os.makedirs(os.path.dirname(d), exist_ok=True)
            run(["git", "clone", "--quiet", DEVNEN_URL, d])
        run(["git", "fetch", "--quiet", "origin"], cwd=d)
        # A reinstall must converge on the SAME tree: discard any previous patch and anything the server
        # rewrote at runtime (devnen saves device/ui_state back into config.yaml).
        run(["git", "checkout", "--quiet", "--force", DEVNEN_COMMIT], cwd=d)
        run(["git", "clean", "--quiet", "-fdx", "-e", ".venv", "-e", "model_cache"], cwd=d)
        run(["git", "apply", PATCH], cwd=d)
        run(["uv", "venv", "--quiet", "--allow-existing", "--python", "3.11", ".venv"], cwd=d)
        py = venv_python(d)
        req = "requirements-nvidia.txt" if device == "cuda" else "requirements.txt"
        run(["uv", "pip", "install", "--quiet", "--python", py, "-r", req], cwd=d)
        run(["uv", "pip", "install", "--quiet", "--python", py, "--no-deps",
             CHATTERBOX_PKG, "s3tokenizer==0.3.0", "onnx==1.16.0"], cwd=d)
        # descript-audiotools pins protobuf<3.20 but onnx 1.16 needs >=3.20.2; devnen's start.py does the same.
        run(["uv", "pip", "install", "--quiet", "--python", py, "--no-deps", "--reinstall", "protobuf>=4.25.0"], cwd=d)
    except (subprocess.CalledProcessError, OSError) as e:
        log(f"install failed: {e}")
        return EXIT_INSTALL
    shutil.copy(TUNING, os.path.join(d, "voice_tuning.json"))
    missing = []
    for name in voices_wanted():
        src = os.path.join(VOICE_REFS, name)
        if os.path.isfile(src):
            shutil.copy(src, os.path.join(d, "voices", name))
        else:
            missing.append(name)
    with open(os.path.join(d, ".cowir_install.json"), "w", encoding="utf-8") as f:
        json.dump({"devnen_commit": DEVNEN_COMMIT, "device": device, "installed_at": int(time.time())}, f)
    if missing:
        log(f"installed, but these tuned voices have no reference in voice_refs/: {missing}")
    log(f"installed at {d} (device {device})")
    return EXIT_OK


def installed(d: str) -> bool:
    return os.path.isfile(os.path.join(d, ".cowir_install.json")) and os.path.isfile(venv_python(d))


def pid_file(d: str) -> str:
    return os.path.join(d, ".cowir_server.pid")


def is_our_server(pid: int, d: str):
    """True if pid is this install's server.py, False if it is some other process, None if unknowable.

    A pid file outlives a crash, and the OS reuses pids, so a live pid proves nothing about WHAT it is.
    """
    proc = f"/proc/{pid}"
    if not os.path.isdir("/proc/self"):
        return None                            # no /proc (Windows, macOS): identity cannot be verified here
    try:
        cmd = open(f"{proc}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace")
        cwd = os.path.realpath(os.readlink(f"{proc}/cwd"))
    except OSError:
        return False
    return "server.py" in cmd and cwd == os.path.realpath(d)


def read_pid(d: str):
    """The pid in the pid file, only if it is alive AND verifiably this install's server."""
    try:
        pid = int(open(pid_file(d)).read().strip())
    except (OSError, ValueError):
        return None
    try:
        os.kill(pid, 0)
    except OSError:
        return None
    return pid if is_our_server(pid, d) else None


def voices_listed(port: int):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/audio/voices", timeout=5) as r:
            data = json.load(r)
    except Exception:
        return None
    items = data.get("voices", data) if isinstance(data, dict) else data
    return [v.get("id", v) if isinstance(v, dict) else v for v in items]


def start(a) -> int:
    d = a.dir
    if not installed(d):
        return EXIT_NOT_INSTALLED
    if voices_listed(a.port) is not None:
        log(f"already answering on :{a.port}")
        return EXIT_OK
    env = dict(os.environ)
    env.pop("COWIR_TTS_DEV", None)            # the full API is never opened for a player's server
    subprocess.run([venv_python(d), "-c",     # port lives in config.yaml; write it before starting
                    "import yaml,sys;p='config.yaml';c=yaml.safe_load(open(p));c['server']['port']=int(sys.argv[1]);"
                    "yaml.safe_dump(c,open(p,'w'),sort_keys=False)", str(a.port)], cwd=d, check=True)
    logf = open(os.path.join(d, "cowir_server.log"), "ab")
    kw = {"creationflags": 0x00000008 | 0x00000200} if platform.system() == "Windows" else {"start_new_session": True}
    p = subprocess.Popen([venv_python(d), "server.py"], cwd=d, env=env, stdout=logf, stderr=logf, stdin=subprocess.DEVNULL, **kw)
    open(pid_file(d), "w").write(str(p.pid))
    deadline = time.time() + a.timeout        # the first start downloads the model (several GB)
    while time.time() < deadline:
        if p.poll() is not None:
            log(f"server exited with code {p.returncode}; see {os.path.join(d, 'cowir_server.log')}")
            return EXIT_START
        if voices_listed(a.port) is not None:
            log(f"answering on http://127.0.0.1:{a.port} (pid {p.pid})")
            return EXIT_OK
        time.sleep(2)
    log(f"no answer on :{a.port} after {a.timeout}s")
    return EXIT_START


def stop(a) -> int:
    try:
        raw = int(open(pid_file(a.dir)).read().strip())
    except (OSError, ValueError):
        log("not running")
        return EXIT_OK
    who = is_our_server(raw, a.dir)
    if who is None:
        log(f"cannot verify pid {raw} is this server on this platform; not signalling it. Stop it by hand.")
        return EXIT_START
    pid = read_pid(a.dir)
    if pid is None:                            # dead, or the pid now belongs to an unrelated process
        log(f"pid file names {raw}, which is not this server (exited, or pid reused); not signalling it")
        try:
            os.remove(pid_file(a.dir))
        except OSError:
            pass
        return EXIT_OK
    os.kill(pid, signal.SIGTERM)
    for _ in range(30):
        if read_pid(a.dir) is None:
            break
        time.sleep(0.5)
    try:
        os.remove(pid_file(a.dir))
    except OSError:
        pass
    log(f"stopped pid {pid}")
    return EXIT_OK


def check(a) -> int:
    d = a.dir
    meta = {}
    if installed(d):
        meta = json.load(open(os.path.join(d, ".cowir_install.json"), encoding="utf-8"))
    listed = voices_listed(a.port)
    wanted = list(voices_wanted())
    report = {
        "installed": installed(d),
        "dir": d,
        "devnen_commit": meta.get("devnen_commit"),
        "supported_commit": meta.get("devnen_commit") == DEVNEN_COMMIT,
        "device": meta.get("device"),
        "gpu_visible": has_nvidia(),
        "free_ram_gb": None if free_ram_gb() is None else round(free_ram_gb(), 1),
        "host_problems": host_verdict(has_nvidia(), meta.get("device") or "cuda", free_ram_gb()),
        "pid": read_pid(d),
        "url": f"http://127.0.0.1:{a.port}",
        "healthy": listed is not None,
        "voices_wanted": wanted,
        "voices_missing": [v for v in wanted if listed is not None and v not in listed],
    }
    print(json.dumps(report))
    if not report["installed"]:
        return EXIT_NOT_INSTALLED
    return EXIT_OK if report["healthy"] and not report["voices_missing"] else EXIT_START


def main() -> int:
    if sys.argv[1:] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("command", choices=["install", "start", "stop", "check"])
    ap.add_argument("--dir", default=default_dir())
    ap.add_argument("--port", type=int, default=8004)
    ap.add_argument("--device", choices=["cuda", "cpu"])
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--allow-weak-host", action="store_true", help="install even where host_verdict refuses")
    try:
        a = ap.parse_args()
    except SystemExit as e:                   # --help exits 0; only a genuine usage error is EXIT_USAGE
        return EXIT_OK if e.code == 0 else EXIT_USAGE
    return {"install": install, "start": start, "stop": stop, "check": check}[a.command](a)


if __name__ == "__main__":
    sys.exit(main())
