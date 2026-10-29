#!/usr/bin/env python3
"""Build the portable client; never read the owner's server or account directories."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--modpack', type=Path, required=True, help='Aeronautics-2.3.zip from the previous client release')
    parser.add_argument('--hmcl', type=Path, required=True, help='Official HMCL-3.16.4.jar; checksum is verified')
    args = parser.parse_args()
    metadata = json.loads((ROOT / 'release.json').read_text())
    if hashlib.sha256(args.hmcl.read_bytes()).hexdigest() != metadata['hmcl']['sha256']:
        raise SystemExit('HMCL checksum does not match release.json')
    java_home = os.environ.get('JAVA_HOME')
    javac = str(Path(java_home) / 'bin/javac') if java_home else 'javac'
    jar = str(Path(java_home) / 'bin/jar') if java_home else 'jar'
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='aeronautics-build-') as temp:
        stage = Path(temp) / 'Aeronautics-Friends'
        stage.mkdir()
        for name in ['Play-macOS.command', 'Play-Windows.cmd', 'Play-Windows.ps1',
                     'AeronauticsSetup.java', 'START-HERE.txt', 'GPL-3.0.txt',
                     'MIT-NO-Singleplayer.txt', 'LICENSE', 'SOURCES.txt', 'release.json']:
            shutil.copy2(ROOT / name, stage / name)
        (stage / 'server-address.txt').write_text('')
        shutil.copy2(args.hmcl, stage / 'HMCL.jar')
        classes = Path(temp) / 'classes'
        classes.mkdir()
        subprocess.run([javac, '--release', '17', '-encoding', 'UTF-8', '-cp',
                        str(args.hmcl.resolve()), '-d', str(classes),
                        str(ROOT / 'AeronauticsSetup.java')], check=True)
        subprocess.run([jar, '--create', '--file', str(stage / 'AeronauticsSetup.jar'),
                        '-C', str(classes), '.'], check=True)
        allowed = {'options.txt', 'configureddefaults', 'config', 'fancymenu_data',
                   'mods', 'shaderpacks', 'resourcepacks', 'defaultconfigs'}
        mods = []
        with zipfile.ZipFile(args.modpack) as source, zipfile.ZipFile(
                stage / 'Aeronautics-2.3.zip', 'w', zipfile.ZIP_DEFLATED, compresslevel=3) as target:
            for item in source.infolist():
                parts = PurePosixPath(item.filename).parts
                if not parts or '..' in parts or item.filename.startswith('/'):
                    raise ValueError('Unsafe archive path')
                if any(p.startswith('._') or p in {'.DS_Store', '__MACOSX'} for p in parts):
                    continue
                if item.is_dir():
                    continue
                if item.filename not in {'instance.cfg', 'mmc-pack.json'}:
                    if len(parts) < 2 or parts[0] != '.minecraft' or parts[1] not in allowed:
                        continue
                data = source.read(item)
                if item.filename == 'instance.cfg':
                    data = ('\n'.join(line for line in data.decode().splitlines()
                                      if not line.startswith('uuid=')) + '\n').encode()
                target.writestr(item.filename, data)
                if len(parts) == 3 and parts[1] == 'mods' and item.filename.endswith('.jar'):
                    mods.append({'file': parts[2], 'sha256': hashlib.sha256(data).hexdigest()})
            # Empty, uncompressed NBT list: no obsolete or third-party server address.
            target.writestr('.minecraft/servers.dat', bytes.fromhex('0a0000090007736572766572730a0000000000'))
        if len(mods) != metadata['client_mods']:
            raise ValueError(f'Unexpected client mod count: {len(mods)}')
        (stage / 'MODS.json').write_text(json.dumps(mods, ensure_ascii=False, indent=2) + '\n')
        archive = dist / f'Aeronautics-Launcher-{metadata["version"]}-Windows-macOS.zip'
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=3) as target:
            for file in sorted(stage.iterdir()):
                target.write(file, 'Aeronautics-Friends/' + file.name)
        with zipfile.ZipFile(archive) as verify:
            if verify.testzip() is not None:
                raise ValueError('Invalid release ZIP')
        checksum = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest()
        archive.with_suffix('.sha256').write_text(checksum + '  ' + archive.name + '\n')
        print(json.dumps({'archive': str(archive), 'sha256': checksum,
                          'mods': len(mods), 'bytes': archive.stat().st_size}))


if __name__ == '__main__':
    main()
