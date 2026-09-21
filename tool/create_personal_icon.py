"""Derive iOS assets from the approved border collie PNG without redrawing it.

Requires Pillow. The approved 1024px original is kept byte-for-byte in
res/personal-icon.png and is also used by the Flutter About page.
"""
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'res/personal-icon.png'
APPROVED_SHA256 = '9369a373a814361e636690631d2545b333ee82b6f0e6cc4ad427e29ab5d49663'


def main():
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != APPROVED_SHA256:
        raise ValueError('Source does not match the approved border collie PNG')

    with Image.open(SOURCE) as icon:
        if icon.size != (1024, 1024) or icon.mode != 'RGB':
            raise ValueError('The approved icon must be an opaque 1024x1024 RGB PNG')

        assets = ROOT / 'ios/Runner/Assets.xcassets'
        appicon = assets / 'PersonalAppIcon.appiconset'
        contents = json.loads((appicon / 'Contents.json').read_text())
        for entry in contents['images']:
            size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
            destination = appicon / entry['filename']
            if size == 1024:
                shutil.copyfile(SOURCE, destination)
            else:
                icon.resize((size, size), Image.Resampling.LANCZOS).save(destination)

        shutil.copyfile(SOURCE, assets / 'PersonalBranding.imageset/mark.png')
        print(f'Updated {len(contents["images"])} app icons and the launch mark.')


if __name__ == '__main__':
    main()
