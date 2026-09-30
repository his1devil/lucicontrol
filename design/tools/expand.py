"""Expands the design canvas templates (sc-for / sc-if / {{ path }}) against a dict of values."""
import re

TAG = re.compile(r'<(sc-for|sc-if)\b([^>]*)>|</(sc-for|sc-if)>')
EXPR = re.compile(r'\{\{\s*(.*?)\s*\}\}')


def lookup(expr, ctx):
    e = expr.strip()
    if e == 'true':
        return True
    if e == 'false':
        return False
    if re.fullmatch(r'-?\d+(\.\d+)?', e):
        return float(e) if '.' in e else int(e)
    cur = ctx
    for part in e.split('.'):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def interp(text, ctx):
    def rep(m):
        v = lookup(m.group(1), ctx)
        if v is None:
            return ''
        if isinstance(v, bool):
            return 'true' if v else 'false'
        return str(v)
    return EXPR.sub(rep, text)


def attr(attrs, name):
    m = re.search(name + r'="([^"]*)"', attrs)
    return m.group(1) if m else None


def expand(tpl, ctx):
    out = []
    pos = 0
    while True:
        m = TAG.search(tpl, pos)
        if not m:
            out.append(interp(tpl[pos:], ctx))
            break
        out.append(interp(tpl[pos:m.start()], ctx))
        if not m.group(1):
            pos = m.end()
            continue
        depth, p, m2 = 1, m.end(), None
        while depth > 0:
            m2 = TAG.search(tpl, p)
            if not m2:
                break
            depth += 1 if m2.group(1) else -1
            p = m2.end()
        inner = tpl[m.end():m2.start()] if m2 else tpl[m.end():]
        tag, attrs = m.group(1), m.group(2)
        em = EXPR.fullmatch((attr(attrs, 'value' if tag == 'sc-if' else 'list') or '').strip())
        v = lookup(em.group(1), ctx) if em else None
        if tag == 'sc-if':
            if v:
                out.append(expand(inner, ctx))
        else:
            name = attr(attrs, 'as') or 'item'
            for item in (v or []):
                c = dict(ctx)
                c[name] = item
                out.append(expand(inner, c))
        pos = m2.end() if m2 else len(tpl)
    return ''.join(out)
