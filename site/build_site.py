"""
Builds docs/index.html, the public site, from the real results of the project:
the dbt manifest (models, SQL, lineage), the run results (tests), the DuckDB
database (positions, summary, reconciliations) and the legacy PL/SQL file.

Nothing on the site is typed by hand: run it after `dbt build` and it stays true.

    dbt build && python site/build_site.py
"""
from __future__ import annotations

import json
import os
from collections import Counter
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "target"
PROJECT = "oakmark_lookthrough"

# Blocks of the legacy package, located by text, and the dbt models that replace them.
BLOCKS = [
    ("fx", "FUNCTION get_ecb_rate", "END get_ecb_rate;",
     ["stg_ecb__fx_rates", "int_fx_rates_at_report_date"]),
    ("country", "FUNCTION risk_country", "END risk_country;",
     ["fct_positions_eur"]),
    ("positions", "PROCEDURE load_positions", "END load_positions;",
     ["stg_nport__holdings", "fct_positions_eur"]),
    ("summary", "PROCEDURE load_summary", "END load_summary;",
     ["stg_nport__fund", "stg_nport__flows", "fct_fund_quarter_eur"]),
    ("run", "PROCEDURE run (p_from IN DATE, p_to IN DATE) IS", "END run;",
     ["rpt_reconciliation_positions", "rpt_reconciliation_fund"]),
]


def line_range(src: str, start: str, end: str) -> tuple[int, int]:
    i = src.index(start)
    j = src.index(end, i)
    return src.count("\n", 0, i) + 1, src.count("\n", 0, j) + 1


def dbt_graph(manifest: dict) -> list[dict]:
    models = {}
    for uid, n in manifest["nodes"].items():
        if n["package_name"] != PROJECT or n["resource_type"] != "model":
            continue
        models[uid] = {
            "name": n["name"],
            "layer": n["path"].split("/")[0],
            "description": " ".join(n.get("description", "").split()),
            "sql": n.get("raw_code", "").strip(),
            "deps": [],
            "seeds": [],
        }
    for uid, m in models.items():
        for dep in manifest["nodes"][uid]["depends_on"]["nodes"]:
            if dep in models:
                m["deps"].append(models[dep]["name"])
            elif dep.startswith("seed."):
                m["seeds"].append(dep.split(".")[-1])
    return list(models.values())


def tests_summary(manifest: dict, run_results: dict) -> dict:
    status = Counter(r["status"] for r in run_results["results"]
                     if r["unique_id"].split(".")[0] in ("test", "unit_test"))
    singular = [n["name"] for n in manifest["nodes"].values()
                if n["resource_type"] == "test" and n["package_name"] == PROJECT
                and not n.get("test_metadata")]
    return {"status": dict(status), "total": sum(status.values()), "singular": sorted(singular),
            "generated_at": run_results["metadata"]["generated_at"]}


def rows(con, sql: str) -> list[list]:
    out = []
    for r in con.execute(sql).fetchall():
        out.append([float(v) if hasattr(v, "as_tuple") else (v.isoformat() if hasattr(v, "isoformat") else v)
                    for v in r])
    return out


def warehouse(con) -> dict:
    return {
        "fund": rows(con, """
            select f.report_date, f.net_assets_eur, f.securities_eur, f.cash_and_other_eur, f.net_flows_eur,
                   l.securities_eur, l.cash_and_other_eur, l.net_flows_eur, f.nb_positions, l.nb_positions,
                   r.status
            from marts.fct_fund_quarter_eur f
            join legacy.legacy_rpt_fund_eur l using (report_date)
            join marts.rpt_reconciliation_fund r using (report_date)
            order by 1"""),
        "recon": rows(con, """
            select r.report_date, r.line_no, r.issuer_name, r.currency, r.legacy_val_eur, r.modern_val_eur, r.status,
                   p.risk_country
            from marts.rpt_reconciliation_positions r
            left join marts.fct_positions_eur p using (report_date, line_no)
            order by r.report_date, r.modern_val_eur desc nulls last"""),
        "by_currency": rows(con, """
            select report_date, currency, sum(val_eur), count(*)
            from marts.fct_positions_eur
            group by 1, 2 order by 1, 3 desc"""),
        "by_country": rows(con, """
            select report_date, risk_country, sum(val_eur)
            from marts.fct_positions_eur where not is_cash_equivalent
            group by 1, 2 order by 1, 3 desc"""),
        "clp": rows(con, """
            select report_date, issuer_name, val_usd, val_eur
            from marts.fct_positions_eur where fx_method = 'USD_CROSS' order by 1"""),
        "repo": rows(con, """
            select report_date, val_eur from marts.fct_positions_eur where is_cash_equivalent order by 1"""),
        "country_rule": rows(con, """
            select distinct issuer_name, inv_country, risk_country
            from marts.fct_positions_eur where inv_country in ('KY', 'JE') order by 2, 1"""),
        "reinvest": rows(con, """
            select f.report_date, sum(f.reinvestments_usd), max(u.units_per_eur)
            from staging.stg_nport__flows f
            join intermediate.int_fx_rates_at_report_date u
              on u.report_date = f.report_date and u.currency = 'USD'
            group by 1 order by 1"""),
        "counts": {
            "holdings": con.execute("select count(*) from marts.fct_positions_eur").fetchone()[0],
            "currencies": con.execute("select count(distinct currency) from marts.fct_positions_eur").fetchone()[0],
            "ecb_days": con.execute("select count(*) from raw.raw_ecb_fx_hist").fetchone()[0],
        },
    }


def main() -> None:
    manifest = json.loads((TARGET / "manifest.json").read_text(encoding="utf-8"))
    run_results = json.loads((TARGET / "run_results.json").read_text(encoding="utf-8"))
    plsql = (ROOT / "legacy" / "pkg_lookthrough_eur.sql").read_text(encoding="utf-8")
    con = duckdb.connect(str(ROOT / os.environ.get("DUCKDB_PATH", "lookthrough.duckdb")), read_only=True)

    data = {
        "plsql": plsql,
        "blocks": [dict(id=b, lines=line_range(plsql, s, e), models=m) for b, s, e, m in BLOCKS],
        "graph": dbt_graph(manifest),
        "tests": tests_summary(manifest, run_results),
        "repo": os.environ.get("GITHUB_REPOSITORY", "dahibmarouan/plsql-to-dbt"),
        **warehouse(con),
    }
    template = (ROOT / "site" / "template.html").read_text(encoding="utf-8")
    payload = json.dumps(data, ensure_ascii=False, default=str).replace("</", "<\\/")
    html = template.replace("/*__DATA__*/null", payload)
    out = ROOT / "docs" / "index.html"
    out.parent.mkdir(exist_ok=True)
    out.write_text(html, encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT)} ({len(html) // 1024} KB)")


if __name__ == "__main__":
    main()
