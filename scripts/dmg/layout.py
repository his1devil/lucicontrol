#!/usr/bin/env python3
"""Store per-volume Finder layout. No global Finder preferences are changed."""
from pathlib import Path
import sys
from ds_store import DSStore
import ds_store.store

mount, alias_path, bookmark_path = map(Path, sys.argv[1:])
# Finder splits native bookmarks into 1500-byte records. Disable the library's
# automatic decoder because a first chunk is deliberately an incomplete bookmark.
ds_store.store.codecs.pop(b'pBBk', None)
bookmark = bookmark_path.read_bytes()
with DSStore.open(str(mount / '.DS_Store'), 'w+') as store:
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['.']['bwsp'] = {
        'WindowBounds': '{{300, 200}, {600, 380}}', 'ShowToolbar': False,
        'ShowStatusBar': False, 'ShowPathbar': False, 'ShowSidebar': False,
        'ContainerShowSidebar': False, 'ShowTabView': False,
        'PreviewPaneVisibility': False, 'SidebarWidth': 180,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundImageAlias': alias_path.read_bytes(),
        'backgroundColorRed': 1.0, 'backgroundColorGreen': 1.0, 'backgroundColorBlue': 1.0,
        'iconSize': 120.0, 'textSize': 13.0, 'gridSpacing': 100.0,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'arrangeBy': 'none',
        'showIconPreview': False, 'showItemInfo': False, 'labelOnBottom': True,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    }
    store['.']['pBBk'] = ('blob', bookmark[:1500])
    for index, start in enumerate(range(1500, len(bookmark), 1500)):
        assert index < 10, 'Unexpectedly large Finder bookmark'
        store['.'][f'pBB{index}'] = ('blob', bookmark[start:start + 1500])
    store['LuciControl.app']['Iloc'] = (150, 150)
    store['Applications']['Iloc'] = (450, 150)
    for index, name in enumerate(['.background', '.DS_Store', '.fseventsd', '.Trashes']):
        store[name]['Iloc'] = (2560 + 50 * index, 170)
