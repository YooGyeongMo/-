"""SQLAlchemy 모델이 contracts/db.dbml v1.0 과 1:1 인지 검사한다 (14번 §6, 계약 v1.0 수정 금지).

dbml 을 직접 파싱해서 테이블·컬럼(타입·NULL·기본값 유무·unique)·인덱스·FK 를 비교한다.
"""

import re
from pathlib import Path

import pytest
import sqlalchemy as sa

from app.all_models import metadata

DBML = Path(__file__).resolve().parents[3] / "contracts" / "db.dbml"


def _strip_comments(text: str) -> str:
    return re.sub(r"//[^\n]*", "", re.sub(r"'''.*?'''", "''", text, flags=re.S))


def parse_dbml() -> tuple[dict[str, dict[str, object]], set[tuple[str, str, str, str]]]:
    text = _strip_comments(DBML.read_text(encoding="utf-8"))
    tables: dict[str, dict[str, object]] = {}
    for m in re.finditer(r"^Table (\w+) \{(.*?)^\}", text, flags=re.S | re.M):
        name, body = m.group(1), m.group(2)
        body = re.sub(r"\bNote:\s*'[^']*'", "", body)
        idx_block = re.search(r"indexes \{(.*?)\}", body, flags=re.S)
        indexes = {}
        if idx_block:
            for line in idx_block.group(1).strip().splitlines():
                im = re.match(r"\s*\(?([\w, ]+?)\)?\s*\[(.*)\]", line)
                assert im, line
                cols = tuple(c.strip() for c in im.group(1).split(","))
                iname = re.search(r"name: '(\w+)'", im.group(2))
                assert iname, line
                indexes[iname.group(1)] = (cols, "unique" in im.group(2))
            body = body.replace(idx_block.group(0), "")
        columns = {}
        for line in body.strip().splitlines():
            cm = re.match(r"\s*(\w+)\s+([\w(),]+)\s*(?:\[(.*)\])?\s*$", line)
            if not cm:
                continue
            attrs = cm.group(3) or ""
            columns[cm.group(1)] = {
                "type": cm.group(2),
                "pk": "pk" in re.split(r"[,\s]+", attrs),
                "not_null": "not null" in attrs,
                "unique": re.search(r"(^|,)\s*unique", attrs) is not None,
                "default": "default:" in attrs,
            }
        tables[name] = {"columns": columns, "indexes": indexes}
    refs = set()
    for r in re.finditer(r"^Ref: (\w+)\.(\w+) [>\-] (\w+)\.(\w+)", text, flags=re.M):
        refs.add((r.group(1), r.group(2), r.group(3), r.group(4)))
    return tables, refs


def _type_ok(dbml_type: str, col: sa.Column[object]) -> bool:
    t = col.type
    if m := re.fullmatch(r"varchar\((\d+)\)", dbml_type):
        return isinstance(t, sa.String) and not isinstance(t, sa.Enum) and t.length == int(m[1])
    if m := re.fullmatch(r"decimal\((\d+),(\d+)\)", dbml_type):
        return isinstance(t, sa.Numeric) and (t.precision, t.scale) == (int(m[1]), int(m[2]))
    simple = {
        "bigint": sa.BigInteger,
        "int": sa.Integer,
        "boolean": sa.Boolean,
        "datetime": sa.DateTime,
        "date": sa.Date,
        "text": sa.Text,
        "json": sa.JSON,
    }
    if dbml_type in simple:
        return isinstance(t, simple[dbml_type])
    return isinstance(t, sa.Enum) and t.name == dbml_type


DBML_TABLES, DBML_REFS = parse_dbml()


def test_same_17_tables() -> None:
    assert len(DBML_TABLES) == 17
    assert set(metadata.tables) == set(DBML_TABLES)


@pytest.mark.parametrize("table", sorted(DBML_TABLES))
def test_columns_match(table: str) -> None:
    model = metadata.tables[table]
    spec = DBML_TABLES[table]["columns"]
    assert isinstance(spec, dict)
    assert [c.name for c in model.columns] == list(spec), "컬럼 이름·순서"
    for name, s in spec.items():
        col = model.columns[name]
        assert _type_ok(s["type"], col), f"{table}.{name} 타입 {s['type']} != {col.type!r}"
        assert col.primary_key == s["pk"], f"{table}.{name} pk"
        assert col.nullable == (not (s["not_null"] or s["pk"])), f"{table}.{name} nullable"
        assert (col.server_default is not None) == s["default"], f"{table}.{name} default"
        # dbml 은 같은 unique 를 컬럼과 이름 있는 인덱스에 두 번 적기도 한다(users.email).
        # 인덱스 하나면 충분하다.
        single_unique_index = any(
            i.unique and [c.name for c in i.columns] == [name] for i in model.indexes
        )
        if s["unique"]:
            assert col.unique or single_unique_index, f"{table}.{name} unique 없음"
        else:
            assert not col.unique, f"{table}.{name} 컬럼 unique 는 dbml 에 없음"


@pytest.mark.parametrize("table", sorted(DBML_TABLES))
def test_indexes_match(table: str) -> None:
    model = metadata.tables[table]
    got = {i.name: (tuple(c.name for c in i.columns), bool(i.unique)) for i in model.indexes}
    assert got == DBML_TABLES[table]["indexes"]


def test_foreign_keys_match() -> None:
    got = {
        (t.name, fk.parent.name, fk.column.table.name, fk.column.name)
        for t in metadata.tables.values()
        for fk in t.foreign_keys
    }
    assert got == DBML_REFS
