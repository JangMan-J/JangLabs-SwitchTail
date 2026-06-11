import json, sys
mode = sys.argv[1] if len(sys.argv) > 1 else 'list'
d = json.load(sys.stdin)
ws = [w for osw in d for t in osw['tabs'] for w in t['windows']]
if mode == 'list':
    for w in ws:
        print(f"  id={w['id']} title={w['title']!r} vars={w.get('user_vars', {})}")
    print('COUNT', len(ws))
elif mode == 'idof':           # idof <title> -> first window id with that title
    want = sys.argv[2]
    for w in ws:
        if w['title'] == want:
            print(w['id']); break
elif mode == 'hasid':          # hasid <id> -> YES/NO present
    print('YES' if any(str(w['id']) == sys.argv[2] for w in ws) else 'NO')
elif mode == 'count':
    print(len(ws))
