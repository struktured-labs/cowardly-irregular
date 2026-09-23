"""Apply the shell's payload-source change to an already-EXPORTED index.html.
Replacement text is read out of web/shell.html so the page under test and the source agree.
Every step asserts: str.replace is a silent no-op when an anchor misses."""
import io, sys
shell = io.open(sys.argv[1], encoding='utf-8').read()
page  = io.open(sys.argv[2], encoding='utf-8').read()
def between(s, a, b):
    i = s.index(a); j = s.index(b, i) + len(b)
    assert j > i; return s[i:j]
def sub(page, anchor, new, what):
    assert page.count(anchor) == 1, f"anchor x{page.count(anchor)}: {what}"
    out = page.replace(anchor, new, 1); assert out != page, what
    return out
newfn = between(shell, '\t// ⛔ transferSize CANNOT SEE PAST A SERVICE WORKER', '\tasync function measurePayload() {')
page = sub(page, '''\t// transferSize is 0 for a same-origin response served out of the HTTP cache.
\t// Only the big payloads matter; the small files are noise either way.
\tfunction measurePayload() {''', newfn, 'measurePayload header + payloadSource')
newmap = between(shell, '\t\tconst files = [];', "const refetched = files.filter(function (f) { return !f.cached; });")
page = sub(page, '''\t\tconst files = big.map(function (e) {
\t\t\treturn {
\t\t\t\tname: e.name.split('/').pop(),
\t\t\t\tcached: e.transferSize === 0,
\t\t\t\tbytes: e.encodedBodySize,
\t\t\t};
\t\t});
\t\tconst refetched = files.filter(function (f) { return !f.cached; });''', newmap, 'files map')
page = sub(page, '''\t\t\tconst m = measurePayload();
\t\t\tif (m !== null) {''', between(shell, '\t\t\tlet m = null;', '\t\t\tif (m !== null) {'), 'call site')
page = sub(page, '\t\t}).then(() => {\n\t\t\tsetStatusMode(\'hidden\');', '\t\t}).then(async () => {\n\t\t\tsetStatusMode(\'hidden\');', 'async then')
page = sub(page, "return f.name + '=' + (f.cached ? 'cache' : 'network');", "return f.name + '=' + f.source;", 'print')
io.open(sys.argv[2], 'w', encoding='utf-8').write(page)
print(f"  injected into {sys.argv[2].split('/')[-2]}/index.html")
