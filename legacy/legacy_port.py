"""
Line-by-line Python port of legacy/pkg_lookthrough_eur.sql.

CI cannot run Oracle, but the migration needs a trusted "before" to reconcile
against. This port follows the PL/SQL procedurally (same filters, same fallbacks,
same Oracle half-up rounding, same swallowed errors) and writes what the tables
RPT_POSITION_EUR and RPT_FUND_EUR would contain.

On a real migration you would export those two tables from production instead.

    python legacy/legacy_port.py
"""
from __future__ import annotations

import csv
from decimal import Decimal, ROUND_HALF_UP, getcontext
from pathlib import Path

getcontext().prec = 38  # Oracle NUMBER precision
SEEDS = Path(__file__).resolve().parent.parent / "seeds"


def load(name):
    with open(SEEDS / f"{name}.csv", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def rnd(x: Decimal | None, n: int = 2) -> Decimal | None:   # Oracle ROUND
    return None if x is None else x.quantize(Decimal(1).scaleb(-n), rounding=ROUND_HALF_UP)


fund = load("raw_nport_fund")
flows = load("raw_nport_flows")
holdings = load("raw_nport_holdings")
ecb = load("raw_ecb_fx_hist")


def get_ecb_rate(ccy: str, date: str) -> Decimal | None:
    if ccy == "EUR":
        return Decimal(1)
    try:
        # EXECUTE IMMEDIATE 'SELECT ' || p_ccy || ' FROM ecb_fx_hist WHERE ...'
        quoted = [r for r in ecb if r["Date"] <= date and r[ccy] != "N/A"]  # KeyError = ORA-00904
        best = max(quoted, key=lambda r: r["Date"])
        return Decimal(best[ccy])
    except Exception:   # WHEN OTHERS THEN RETURN NULL
        return None


def risk_country(country: str) -> str:
    if country == "KY":
        return "HK"
    if country == "JE":
        return "GB"
    return country


positions, summaries = [], []
for q in sorted(fund, key=lambda r: r["report_date"]):
    d = q["report_date"]

    # load_positions
    pos_q = []
    for h in holdings:
        if h["report_date"] != d or not h["isin"]:          # AND isin IS NOT NULL
            continue
        local = rnd(Decimal(h["val_usd"]) * (Decimal(h["exchange_rt"]) if h["exchange_rt"] else Decimal(1)))
        fx = get_ecb_rate(h["cur_cd"], d)
        eur = rnd(local / fx) if fx is not None else None    # x / NULL = NULL
        pos_q.append(dict(report_date=d, line_no=h["line_no"], isin=h["isin"],
                          issuer_name=h["issuer_name"], asset_cat=h["asset_cat"],
                          cur_cd=h["cur_cd"], risk_country=risk_country(h["inv_country"]),
                          val_local=local, ecb_rate=fx, val_eur=eur))
    positions += pos_q

    # load_summary
    net_usd = Decimal(q["net_assets"])
    eurusd = get_ecb_rate("USD", d)
    net_eur = rnd(net_usd / eurusd)
    sec_eur = sum((p["val_eur"] for p in pos_q if p["val_eur"] is not None), Decimal(0))
    fq = [f for f in flows if f["report_date"] == d]
    flows_usd = sum(Decimal(f["sales"]) for f in fq) - sum(Decimal(f["redemption"]) for f in fq)
    summaries.append(dict(report_date=d, nb_positions=len(pos_q), net_assets_usd=net_usd,
                          eurusd_rate=eurusd, net_assets_eur=net_eur, securities_eur=sec_eur,
                          cash_and_other_eur=net_eur - sec_eur, net_flows_eur=rnd(flows_usd / eurusd)))


def dump(name, rows):
    with open(SEEDS / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow({k: ("" if v is None else v) for k, v in r.items()})
    print(f"{name:<26} {len(rows):>5} rows")


dump("legacy_rpt_position_eur", positions)
dump("legacy_rpt_fund_eur", summaries)
