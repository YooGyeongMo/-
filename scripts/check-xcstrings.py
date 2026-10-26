#!/usr/bin/env python3
"""String Catalog 검사 (ADR-0016 결정 7, #99).

apps/ios-macos 아래 모든 Localizable.xcstrings 에서 키마다 ko·en 이 'translated' 상태인지,
키가 `<영역>.<화면>.<요소>` 꼴(소문자·점 구분)인지 본다. 하나라도 어기면 실패한다.

사용: python3 scripts/check-xcstrings.py [루트=apps/ios-macos]
"""
import json
import pathlib
import re
import sys

LANGS = ("ko", "en")
KEY = re.compile(r"^[a-z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+){1,4}$")


def check(path):
    problems = []
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("sourceLanguage") != "ko":
        problems.append(f"{path}: sourceLanguage 는 ko 여야 합니다")
    for key, entry in sorted(data.get("strings", {}).items()):
        if not KEY.match(key):
            problems.append(f"{path}: 키 형식 위반 '{key}' (예: translate.result.plainTitle)")
        locs = entry.get("localizations", {})
        for lang in LANGS:
            unit = locs.get(lang, {}).get("stringUnit")
            variations = locs.get(lang, {}).get("variations")
            if variations:
                continue  # 복수형 등은 Xcode가 관리
            if not unit or unit.get("state") != "translated" or not unit.get("value", "").strip():
                problems.append(f"{path}: '{key}' 의 {lang} 번역 없음")
    return problems


def main(argv):
    root = pathlib.Path(argv[1] if len(argv) > 1 else "apps/ios-macos")
    files = [p for p in root.rglob("*.xcstrings") if ".build" not in p.parts and "Derived" not in p.parts]
    problems = [p for f in files for p in check(f)]
    if problems:
        print("String Catalog 검사 실패:")
        for line in problems:
            print(f"  - {line}")
        return 1
    print(f"String Catalog 통과: {len(files)}개 파일")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
