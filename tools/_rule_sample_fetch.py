"""Fetch N rule-composition samples from local Ollama for llm_prompt_preview.sh.

A separate file rather than an inline heredoc: the scoring block it sits inside is
itself shell, and a nested heredoc delimiter collides with the outer one.
"""
import json
import sys
import urllib.request

prompt, model, n = open(sys.argv[1]).read(), sys.argv[2], int(sys.argv[3])
for i in range(n):
    body = json.dumps({"model": model, "prompt": prompt, "stream": False,
                       "options": {"temperature": 0.7}}).encode()
    req = urllib.request.Request("http://localhost:11434/api/generate", body,
                                 {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            txt = json.load(r).get("response", "")
    except Exception as exc:
        txt = ""
        print("sample %d: ERROR %s" % (i, exc), file=sys.stderr)
    open("tmp/replies_live/%02d.txt" % i, "w").write(txt)
