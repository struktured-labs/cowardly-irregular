# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Is the WRAP a discontinuity, or just level-matched?

RMS level says the seam is not a hole. It does NOT say the seam is not a CLICK:
two segments can match in level and still jump in waveform, which is audible as
a tick every loop. Compare the one sample-to-sample step the wrap creates
(out[-1] -> out[0]) against the distribution of every OTHER step in the track.
No threshold to tune: the track's own dynamics set the scale.
"""
import subprocess, sys
import numpy as np
SR = 48000
def dec(p):
    raw = subprocess.run(["ffmpeg","-nostdin","-v","error","-i",p,"-f","f32le",
                          "-ac","1","-ar",str(SR),"-"],capture_output=True).stdout
    return np.frombuffer(raw,dtype="<f4").astype(np.float64)

print("%-24s %10s %10s %10s   %s" % ("track","wrap step","p99 step","max step","verdict"))
for k in sys.argv[1:]:
    y = dec(f"assets/audio/music/{k}.ogg")
    steps = np.abs(np.diff(y))
    wrap = abs(float(y[0] - y[-1]))
    p99 = float(np.percentile(steps, 99))
    mx = float(steps.max())
    # A click is a step far outside what the music itself already does.
    verdict = "continuous" if wrap <= p99 else ("audible CLICK" if wrap > mx else "elevated")
    print("%-24s %10.6f %10.6f %10.6f   %s" % (k, wrap, p99, mx, verdict))
