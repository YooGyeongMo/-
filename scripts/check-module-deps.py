#!/usr/bin/env python3
"""앱 모듈 의존 방향 검사 (ADR-0016).

Tuist는 순환만 막고 레이어 방향은 막지 않는다. 매니페스트 헬퍼(precondition)가 1차로 막지만
실패 메시지가 출력되지 않아, CI는 `tuist graph --format json` 결과를 이 스크립트로 다시 검사한다.

규칙은 apps/ios-macos/Tuist/ProjectDescriptionHelpers/Module.swift 의 표와 같아야 한다.

사용:
  python3 scripts/check-module-deps.py <graph.json>
  python3 scripts/check-module-deps.py --self-test
"""
import json
import sys

ALLOWED = {
    "Domain": set(),
    "DomainTesting": {"Domain"},
    "Platform": {"Domain"},
    "Data": {"Domain", "Platform", "MwonmalAPI"},
    "MwonmalUI": set(),
    "Routing": {"Domain"},
    "FeatureKit": {"Domain", "MwonmalUI", "Routing"},
}
FEATURE_ALLOWED = {"Domain", "DomainTesting", "MwonmalUI", "Routing", "FeatureKit"}
# 조립 루트·앱·테스트·예제는 검사하지 않는다(테스트는 대상 + DomainTesting만 두는 관례).
SKIP_SUFFIXES = ("Tests", "Example")
SKIP = {"Composition", "MwonmalIOS", "MwonmalMac", "MwonmalUICatalog"}


def dep_names(target):
    names = []
    for dep in target.get("dependencies", []):
        for kind in ("target", "package", "project"):
            if kind in dep:
                node = dep[kind]
                names.append(node.get("name") or node.get("product") or node.get("target"))
    return [n for n in names if n]


def violations(targets):
    found = []
    for name, target in sorted(targets.items()):
        if name in SKIP or name.endswith(SKIP_SUFFIXES):
            continue
        tags = (target.get("metadata") or {}).get("tags", [])
        deps = set(dep_names(target))
        if "layer:feature" in tags or name.endswith("Feature"):
            allowed = FEATURE_ALLOWED
        elif name in ALLOWED:
            allowed = ALLOWED[name]
        else:
            found.append(f"{name}: 규칙 표에 없는 모듈 — Module.swift와 이 스크립트에 추가하세요")
            continue
        for bad in sorted(deps - allowed):
            found.append(f"{name} → {bad} (허용: {sorted(allowed) or '없음'})")
    return found


def load_targets(path):
    graph = json.load(open(path, encoding="utf-8"))
    projects = graph["projects"]
    targets = {}
    # projects는 [경로, 프로젝트, 경로, 프로젝트, ...] 꼴이다.
    for item in projects:
        if isinstance(item, dict):
            targets.update(item.get("targets", {}))
    return targets


def self_test():
    ok = {
        "TranslateFeature": {"metadata": {"tags": ["layer:feature"]}, "dependencies": [{"target": {"name": "Routing"}}]},
        "Data": {"dependencies": [{"target": {"name": "Domain"}}, {"package": {"product": "MwonmalAPI"}}]},
    }
    bad = {
        "HomeFeature": {"metadata": {"tags": ["layer:feature"]}, "dependencies": [{"target": {"name": "Data"}}, {"target": {"name": "TranslateFeature"}}]},
        "Domain": {"dependencies": [{"target": {"name": "MwonmalUI"}}]},
        "Mystery": {"dependencies": []},
    }
    assert violations(ok) == [], violations(ok)
    found = violations(bad)
    assert len(found) == 4, found
    assert any("HomeFeature → TranslateFeature" in f for f in found)
    assert any("Domain → MwonmalUI" in f for f in found)
    print("self-test ok")


def main(argv):
    if argv[1:] == ["--self-test"]:
        self_test()
        return 0
    if len(argv) != 2:
        print(__doc__)
        return 2
    targets = load_targets(argv[1])
    found = violations(targets)
    if found:
        print("의존 규칙 위반 (ADR-0016):")
        for line in found:
            print(f"  - {line}")
        return 1
    print(f"모듈 의존 규칙 통과: {len(targets)}개 타깃")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
