#!/usr/bin/env python3
"""소스 이미지 한 장으로 iOS 앱 아이콘 세트를 만든다.

    scripts/make-ios-appicon.py <소스이미지> [appiconset 경로]

Contents.json 에 적힌 크기들을 그대로 읽어서 필요한 png 를 전부 만든다.
크기 목록이 Contents.json 한 곳에만 있으므로 둘이 어긋날 일이 없다.

왜 크기별로 다 만드는가:
    Xcode 14 부터 1024 한 장만 넣는 "단일 크기" 방식을 지원하지만, 그렇게 하면
    컴파일된 Assets.car 에 1024 렌디션만 들어간다. App Store 업로드 검증은
    120x120 / 152x152 / 167x167 이 실제로 있는지 보므로 통과하지 못한다
    (HANDOVER.md §15.1).
"""
import json
import os
import sys

from PIL import Image


def build(src_path, appiconset):
    contents = os.path.join(appiconset, "Contents.json")
    with open(contents, encoding="utf-8") as f:
        spec = json.load(f)

    src = Image.open(src_path).convert("RGBA")
    if src.width != src.height:
        # 정사각형이 아니면 짧은 쪽에 맞춰 가운데를 잘라낸다. 늘리면 그림이 일그러진다.
        side = min(src.width, src.height)
        left = (src.width - side) // 2
        top = (src.height - side) // 2
        src = src.crop((left, top, left + side, top + side))

    # App Store 는 알파 채널이 있는 앱 아이콘을 거부한다. 흰 배경에 합성해서 없앤다.
    flat = Image.new("RGB", src.size, (255, 255, 255))
    flat.paste(src, mask=src.split()[-1])

    made = {}
    for entry in spec["images"]:
        filename = entry["filename"]
        if filename in made:
            continue
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        px = int(round(base * scale))
        out = os.path.join(appiconset, filename)
        flat.resize((px, px), Image.LANCZOS).save(out, "PNG")
        made[filename] = px

    return made


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    src_path = sys.argv[1]
    if len(sys.argv) > 2:
        appiconset = sys.argv[2]
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        appiconset = os.path.join(
            here, "..", "Engine", "VisNovel", "frameworks", "runtime-src",
            "proj.ios_mac", "ios", "Images.xcassets", "AppIcon.appiconset")
    appiconset = os.path.normpath(appiconset)

    if not os.path.isfile(src_path):
        print("소스 이미지가 없다: %s" % src_path, file=sys.stderr)
        return 1
    if not os.path.isdir(appiconset):
        print("appiconset 을 찾을 수 없다: %s" % appiconset, file=sys.stderr)
        return 1

    made = build(src_path, appiconset)
    print("아이콘 %d개 생성: %s" % (len(made), " ".join(
        str(v) for v in sorted(set(made.values())))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
