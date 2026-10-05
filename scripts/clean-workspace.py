#!/usr/bin/env python3
"""Remove only reproducible build caches. Default: preview; --apply: remove."""
import argparse
import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / '.build'
CACHE_NAMES = ('out', 'native-workbench', 'clang-module-cache', 'module-cache', 'swift-module-cache', 'brand-module-cache')

def disk_bytes(path):
    if not path.exists():
        return 0
    result = subprocess.run(['du', '-sk', str(path)], capture_output=True, text=True, check=True)
    return int(result.stdout.split()[0]) * 1024

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='Remove the listed caches; otherwise only show sizes.')
    args = parser.parse_args()
    if not (ROOT / 'Package.swift').is_file() or BUILD.is_symlink():
        raise SystemExit('Refusing cleanup: missing Swift package or symlinked .build directory.')
    # Never clean a running compiler/export process. Existing App may remain open.
    if args.apply:
        processes = subprocess.run(['ps', '-ww', '-axo', 'comm='], capture_output=True, text=True, check=True).stdout.splitlines()
        compiler_names = {'swift-build', 'swift-test', 'swift-frontend', 'swiftc', 'clang', 'produce-nine-live', 'produce-nine-live-mixed'}
        for command in processes:
            if Path(command.strip()).name in compiler_names:
                raise SystemExit('Refusing cleanup: a build, test or media production process is still running.')
    entries = []
    for name in CACHE_NAMES:
        path = BUILD / name
        if path.is_symlink():
            raise SystemExit(f'Refusing cleanup: cache path is a symlink: {path}')
        size = disk_bytes(path)
        entries.append({'path': str(path.relative_to(ROOT)), 'allocatedBytes': size})
        print(f'{size / 1024**2:8.1f} MiB  {path.relative_to(ROOT)}')
    total = sum(entry['allocatedBytes'] for entry in entries)
    print(f'Total rebuildable caches: {total / 1024**3:.2f} GiB')
    if not args.apply:
        print('Preview only. Run with --apply to clean. App, logs and media files are preserved.')
        return
    before = disk_bytes(ROOT)
    app = BUILD / 'MediaWorkbench.app/Contents/MacOS/media-workbench'
    import hashlib
    app_hash = hashlib.sha256(app.read_bytes()).hexdigest() if app.exists() else None
    for name in CACHE_NAMES:
        path = BUILD / name
        if path.exists():
            shutil.rmtree(path)
    # Remove only the aliases pointing to the now-removed product directories.
    for name in ('debug', 'release'):
        link = BUILD / name
        if link.is_symlink() and str(link.readlink()) in ('out/Products/Debug', 'out/Products/Release'):
            link.unlink()
    if app_hash and hashlib.sha256(app.read_bytes()).hexdigest() != app_hash:
        raise SystemExit('App integrity check failed.')
    after = disk_bytes(ROOT)
    report = {'completedAt': datetime.now().astimezone().isoformat(), 'workspace': str(ROOT),
              'beforeAllocatedBytes': before, 'afterAllocatedBytes': after,
              'reclaimedAllocatedBytes': before - after, 'removed': entries,
              'preserved': ['Sources', 'Tests', 'docs', 'assets', '_LLM-Wiki', 'media-tests',
                            '.build/MediaWorkbench.app', '.build/*.log', '.build media fixtures and helper tools'],
              'appSHA256': app_hash, 'appIntegrity': 'unchanged' if app_hash else 'not present'}
    (ROOT / 'docs/workspace-cleanup-latest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'Workspace: {before / 1024**3:.2f} → {after / 1024**3:.2f} GiB; reclaimed {(before-after)/1024**3:.2f} GiB')
    print('Next build/test will regenerate the required caches and take longer.')

if __name__ == '__main__':
    main()
