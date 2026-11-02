#!/usr/bin/env python3
"""Check catalog coverage and format arguments; optionally check compiler extraction."""
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
argument = re.compile(r'%(?:\d+\$)?(?:\.\d+)?(?:lld|ld|d|f|@|%)')
strings = {}
count = 0
for path in sorted((root / 'EchoVoice').glob('*.xcstrings')):
    catalog = json.loads(path.read_text())
    for key, entry in catalog['strings'].items():
        localized = entry['localizations']
        assert 'es' in localized, f'{path.name}: missing Spanish: {key}'
        source = localized.get('en', {}).get('stringUnit', {}).get('value', key)
        target = localized['es']['stringUnit']['value']
        assert target, f'{path.name}: empty Spanish: {key}'
        formats = lambda text: sorted(x for x in argument.findall(text) if x != '%%')
        assert formats(source) == formats(target), f'{path.name}: format arguments differ: {key}'
        for token in re.findall(r'\$\{[^}]+\}', source):
            assert token in target, f'{path.name}: missing parameter: {key}'
        count += 1
    strings[path.stem] = catalog['strings']
if len(sys.argv) > 1:
    for path in Path(sys.argv[1]).glob('*.stringsdata'):
        for table, entries in json.loads(path.read_text()).get('tables', {}).items():
            for entry in entries:
                assert entry['key'] in strings.get(table, {}), f'{path.name}: missing catalog entry: {entry["key"]}'
print(f'{count} localized catalog entries checked')
