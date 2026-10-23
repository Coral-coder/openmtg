#!/usr/bin/env python3
"""Cuts named cards out of a built cards.json into a small test fixture.

    tools/make_fixture.py build/data/cards.json packages/rules/test/fixtures/extra.json "Name" ...
    (or --names-file names.txt)
"""
import json, sys

src, out, *names = sys.argv[1:]
if names and names[0] == '--names-file':
    names = [l.strip() for l in open(names[1]) if l.strip() and not l.startswith('#')]
d = json.load(open(src))
want = set(names)
cards = [c for c in d['cards'] if c[0] in want]
missing = want - {c[0] for c in cards}
if missing:
    sys.exit(f'not found: {sorted(missing)}')
json.dump({**d, 'sets': [], 'cards': sorted(cards, key=lambda c: c[0])}, open(out, 'w'), separators=(',', ':'))
print(f'{len(cards)} cards -> {out}')
