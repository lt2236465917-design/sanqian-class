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
APPROVED_SHA256 = 'd0cc8538b590b58a6b22c276477d248eb192fbca06578ecec04b70cdbb7a65be'


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

        android_res = ROOT / 'android/app/src/main/res'
        android_icons = {
            'mipmap-ldpi': 36,
            'mipmap-mdpi': 48,
            'mipmap-hdpi': 72,
            'mipmap-xhdpi': 96,
            'mipmap-xxhdpi': 144,
            'mipmap-xxxhdpi': 192,
        }
        for folder, size in android_icons.items():
            icon.resize((size, size), Image.Resampling.LANCZOS).save(
                android_res / folder / 'ic_launcher.png'
            )
        icon.resize((512, 512), Image.Resampling.LANCZOS).save(android_res / 'ic_launcher.png')
        print(
            f'Updated {len(contents["images"])} iOS app icons, the launch mark, '
            f'and {len(android_icons)} Android launcher densities.'
        )


if __name__ == '__main__':
    main()
