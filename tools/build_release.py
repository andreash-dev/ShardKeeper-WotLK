#!/usr/bin/env python3
"""Build the installable addon ZIP from an explicit file list."""
from pathlib import Path
import re
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
toc = (root / 'ShardKeeper.toc').read_text()
version = re.search(r'^## Version: ([0-9]+\.[0-9]+\.[0-9]+)$', toc, re.M).group(1)
ET.parse(root / 'ShardKeeper.xml')
files = ['ShardKeeper.toc', 'ShardKeeper.xml', 'ShardKeeper.lua',
         'ShardKeeperUI.lua', 'Textures/Minimap-active.tga',
         'Textures/Minimap-paused.tga', 'LICENSE', 'CHANGELOG.md']
for name in files:
    assert (root / name).is_file(), name
out = root / 'dist' / f'ShardKeeper-{version}.zip'
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in files:
        archive.write(root / name, 'ShardKeeper/' + name)
with zipfile.ZipFile(out) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == {'ShardKeeper/' + name for name in files}
print(out)
