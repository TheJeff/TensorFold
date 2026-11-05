# probe_audit.py TRACE: every file a built binary, or anything it spawned, opened while the tests ran.
import collections, os, re, subprocess, sys
ws = os.getcwd()
tracked = set(subprocess.run(['git', 'ls-files'], capture_output=True, text=True).stdout.split('\n'))
parent, roots, pending = {}, set(), {}
names = {}
opened, failed, execs = [], [], []
op = re.compile(r'(?:openat2?)\((?:AT_FDCWD|-?\d+)(?:<([^>]*)>)?, "((?:[^"\\]|\\.)*)"')
op2 = re.compile(r'(?:open|creat)\("((?:[^"\\]|\\.)*)"')
ex = re.compile(r'execve(?:at)?\((?:(?:AT_FDCWD|-?\d+)(?:<[^>]*>)?, )?"((?:[^"\\]|\\.)*)"')
for line in open(sys.argv[1], errors='replace'):
    m = re.match(r'^(\d+)\s+(.*)$', line.rstrip('\n'))
    if not m: continue
    pid, rest = int(m[1]), m[2]
    if rest.startswith('<...'):
        rest = pending.pop(pid, '') + rest.split('resumed>', 1)[-1]
    elif rest.endswith('<unfinished ...>'):
        pending[pid] = rest[:-len('<unfinished ...>')]
        continue
    ret = re.search(r'= (-?\d+)(?:<[^>]*>)?(?: [A-Z]+ .*)?$', rest)
    ok = ret is not None and int(ret[1]) >= 0
    if rest.startswith(('clone', 'fork', 'vfork')):
        if ok: parent[int(ret[1])] = pid
    elif rest.startswith('exec'):
        e = ex.match(rest)
        if e and ok:
            execs.append((pid, e[1]))
            if '.zig-cache/o/' in e[1] or 'zig-out/' in e[1]: roots.add(pid); names[pid] = os.path.basename(e[1])
    else:
        o = op.match(rest)
        if o: base, path = o[1] or ws, o[2]
        else:
            o = op2.match(rest)
            if not o: continue
            base, path = ws, o[1]
        full = os.path.normpath(os.path.join(base, path))
        (opened if ok else failed).append((pid, full))
def side(pid):
    seen = set()
    while pid in parent or pid in roots:
        if pid in roots: return True
        if pid in seen: return False
        seen.add(pid); pid = parent[pid]
    return False
def root_of(pid):
    seen = set()
    while pid not in seen:
        seen.add(pid)
        if pid in names: return names[pid]
        if pid not in parent: return None
        pid = parent[pid]
    return None
def rel(p): return p[len(ws) + 1:] if p.startswith(ws + '/') else p
def shape(p): return re.sub(r'[0-9a-f]{16,}', '<h>', re.sub(r'/tmp/[^/]+', '/tmp/<t>', p))
print('PROBE AUDIT test-side processes', len(roots), 'opens', len(opened), 'failed', len(failed), 'execs', len(execs))
def report(title, items):
    trk, dirs, out, cache, abs_ = collections.Counter(), collections.Counter(), collections.Counter(), collections.Counter(), collections.Counter()
    for pid, p in items:
        if not side(pid): continue
        r = rel(p)
        if r in tracked: trk[r] += 1
        elif not r.startswith('/') and os.path.isdir(r): dirs[r] += 1
        elif r.startswith(('.zig-cache', 'zig-out')): cache[shape(r)] += 1
        elif not r.startswith('/'): out[shape(r)] += 1
        else: abs_['/'.join(shape(r).split('/')[:3])] += 1
    print(f'PROBE AUDIT {title}: tracked files {len(trk)}')
    by = collections.Counter(os.path.splitext(k)[1] for k in trk)
    print('PROBE AUDIT   by extension', by.most_common())
    for k, v in sorted(trk.items()): print('PROBE TRACKED', title, v, k)
    for k, v in dirs.most_common(60): print('PROBE DIR', title, v, k)
    for k, v in out.most_common(60): print('PROBE UNTRACKED', title, v, k)
    for k, v in cache.most_common(60): print('PROBE CACHE', title, v, k)
    for k, v in abs_.most_common(40): print('PROBE OUTSIDE', title, v, k)
report('read', opened)
report('missing', failed)
c = collections.Counter(shape(p) for pid, p in execs if side(parent.get(pid, -1)))
for k, v in c.most_common(40): print('PROBE SPAWNED', v, k)

by = collections.defaultdict(set)
for pid, p in opened:
    r = rel(p)
    if r in tracked and side(pid): by[root_of(pid)].add(r)
sp = collections.defaultdict(collections.Counter)
for pid, e in execs:
    q = parent.get(pid, -1)
    if side(q): sp[root_of(q)][os.path.basename(e)] += 1
for k in sorted(by, key=lambda x: -len(by[x])):
    zigs = sorted(f for f in by[k] if f.endswith('.zig'))
    rest = sorted(f for f in by[k] if not f.endswith('.zig'))
    print('PROBE BYROOT', k, 'zig', len(zigs), 'other', len(rest), 'spawns', dict(sp[k].most_common(6)))
    for f in rest[:40]: print('PROBE OTHER', k, f)
    for f in zigs[:12]: print('PROBE ZIGREAD', k, f)
