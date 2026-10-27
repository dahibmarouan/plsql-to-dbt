-- Oracle 19c tables read and written by PKG_LOOKTHROUGH_EUR (schema REPORTING).
-- The CSV files in /seeds named raw_* are exports of the four source tables.

-- Sources -------------------------------------------------------------------

CREATE TABLE nport_fund (            -- seeds/raw_nport_fund.csv
  report_date   DATE PRIMARY KEY,
  series_id     VARCHAR2(10),
  series_name   VARCHAR2(150),
  tot_assets    NUMBER,
  tot_liabs     NUMBER,
  net_assets    NUMBER               -- USD
);

CREATE TABLE nport_flows (           -- seeds/raw_nport_flows.csv
  report_date   DATE,
  month_no      NUMBER(1),           -- 1, 2, 3 = months of the quarter
  sales         NUMBER,              -- subscriptions, USD
  reinvestment  NUMBER,              -- dividends reinvested in new shares, USD
  redemption    NUMBER               -- USD
);

CREATE TABLE nport_holdings (        -- seeds/raw_nport_holdings.csv
  report_date   DATE,
  line_no       NUMBER,
  issuer_name   VARCHAR2(150),
  isin          VARCHAR2(12),        -- empty for some technical lines
  other_id      VARCHAR2(30),
  balance       NUMBER,
  units         VARCHAR2(2),         -- NS = number of shares, PA = principal amount
  cur_cd        VARCHAR2(3),
  exchange_rt   NUMBER,              -- units of cur_cd per 1 USD, empty when cur_cd = USD
  val_usd       NUMBER,
  pct_val       NUMBER,
  asset_cat     VARCHAR2(3),         -- EC = equity, EP = preferred equity, RA = repurchase agreement
  inv_country   VARCHAR2(2)
);

-- External table over the ECB file eurofxref-hist.csv: one column per currency,
-- 'N/A' when the ECB does not quote it that day.     seeds/raw_ecb_fx_hist.csv
CREATE TABLE ecb_fx_hist (
  rate_date DATE, usd VARCHAR2(30), jpy VARCHAR2(30), gbp VARCHAR2(30), chf VARCHAR2(30)
  /* ... one VARCHAR2 column per currency, 41 in total ... */
)
ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY ecb_dir
  ACCESS PARAMETERS (RECORDS DELIMITED BY NEWLINE SKIP 1 FIELDS TERMINATED BY ',')
  LOCATION ('eurofxref-hist.csv'));

-- Outputs -------------------------------------------------------------------

CREATE TABLE rpt_position_eur (      -- seeds/legacy_rpt_position_eur.csv
  report_date   DATE,
  line_no       NUMBER,
  isin          VARCHAR2(12),
  issuer_name   VARCHAR2(150),
  asset_cat     VARCHAR2(3),
  cur_cd        VARCHAR2(3),
  risk_country  VARCHAR2(2),
  val_local     NUMBER,
  ecb_rate      NUMBER,
  val_eur       NUMBER,
  created_at    DATE
);

CREATE TABLE rpt_fund_eur (          -- seeds/legacy_rpt_fund_eur.csv
  report_date         DATE PRIMARY KEY,
  nb_positions        NUMBER,
  net_assets_usd      NUMBER,
  eurusd_rate         NUMBER,
  net_assets_eur      NUMBER,
  securities_eur      NUMBER,
  cash_and_other_eur  NUMBER,
  net_flows_eur       NUMBER,
  created_at          DATE
);

CREATE TABLE batch_log (
  proc_name   VARCHAR2(60),
  msg         VARCHAR2(4000),
  created_at  DATE
);
