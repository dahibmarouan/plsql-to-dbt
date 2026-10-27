"""
Turns the raw downloads in data/raw/ into the CSV files that play the role of the
Oracle source tables (seeds/raw_*.csv).

  - nport_YYYY-MM-DD.xml  : SEC Form N-PORT filings of Oakmark International Small Cap Fund
  - eurofxref-hist.zip    : ECB euro foreign exchange reference rates (full history)

The output keeps the data as raw as possible, on purpose: cleaning it is the job of
the dbt staging models. Only two technical changes are made:
  - XML is flattened to one row per holding / per fund / per month;
  - the ECB file is cut to 2024 onwards and its empty trailing column is dropped.

    python scripts/extract_sources.py
"""
from __future__ import annotations

import csv
import io
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
SEEDS = ROOT / "seeds"
ECB_FROM = "2024-01-01"


def load_xml(path: Path) -> ET.Element:
    root = ET.parse(path).getroot()
    for el in root.iter():  # drop XML namespaces, they only get in the way here
        el.tag = el.tag.split("}")[-1]
        el.attrib = {k.split("}")[-1]: v for k, v in el.attrib.items()}
    return root


def write(name: str, header: list[str], rows: list[list]) -> None:
    with open(SEEDS / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print(f"{name:<22} {len(rows):>6} rows")


holdings, funds, flows = [], [], []
for path in sorted(RAW.glob("nport_*.xml")):
    root = load_xml(path)
    report_date = root.findtext(".//repPdDate")
    info = root.find(".//fundInfo")

    funds.append([
        report_date,
        root.findtext(".//seriesId"),
        root.findtext(".//seriesName"),
        info.findtext("totAssets"),
        info.findtext("totLiabs"),
        info.findtext("netAssets"),
    ])

    for month_no in (1, 2, 3):
        m = info.find(f"mon{month_no}Flow")
        flows.append([report_date, month_no, m.get("sales"), m.get("reinvestment"), m.get("redemption")])

    for line_no, h in enumerate(root.findall(".//invstOrSec"), start=1):
        cc = h.find("currencyConditional")
        isin = h.find("identifiers/isin")
        other = h.find("identifiers/other")
        holdings.append([
            report_date,
            line_no,
            h.findtext("name"),
            isin.get("value") if isin is not None else "",
            other.get("value") if other is not None else "",
            h.findtext("balance"),
            h.findtext("units"),
            cc.get("curCd") if cc is not None else h.findtext("curCd"),
            cc.get("exchangeRt") if cc is not None else "",   # empty when the holding is in USD
            h.findtext("valUSD"),
            h.findtext("pctVal"),
            h.findtext("assetCat"),
            h.findtext("invCountry"),
        ])

write("raw_nport_fund",
      ["report_date", "series_id", "series_name", "tot_assets", "tot_liabs", "net_assets"], funds)
write("raw_nport_flows",
      ["report_date", "month_no", "sales", "reinvestment", "redemption"], flows)
write("raw_nport_holdings",
      ["report_date", "line_no", "issuer_name", "isin", "other_id", "balance", "units",
       "cur_cd", "exchange_rt", "val_usd", "pct_val", "asset_cat", "inv_country"], holdings)

# ECB: one column per currency, 'N/A' when not quoted, most recent date first (as published)
with zipfile.ZipFile(RAW / "eurofxref-hist.zip") as z:
    text = z.read("eurofxref-hist.csv").decode("utf-8")
reader = csv.reader(io.StringIO(text))
header = [c for c in next(reader) if c.strip()]
rows = [r[: len(header)] for r in reader if r and r[0] >= ECB_FROM]
write("raw_ecb_fx_hist", header, rows)
