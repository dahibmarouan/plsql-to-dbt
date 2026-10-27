-- 1) par trimestre : nombre de lignes et total des titres en euros (hors liquidités)
WITH positions AS (
    SELECT
        report_date,
        COUNT(*) AS nb_positions,
        CAST(SUM(CASE WHEN NOT is_cash_equivalent THEN val_eur ELSE 0 END) AS DECIMAL(38, 2)) AS securities_eur
    FROM {{ ref('fct_positions_eur') }}
    GROUP BY report_date
),

-- 2) par trimestre : les flux nets du trimestre, en dollars
flows AS (
    SELECT
        report_date,
        SUM (subscriptions_usd + reinvestments_usd - redemptions_usd ) AS net_flows_usd
    FROM {{ ref('stg_nport__flows') }}
    GROUP BY report_date
),

-- 3) par trimestre : le taux BCE du dollar
usd AS (
    SELECT report_date, units_per_eur AS eurusd_rate
    FROM {{ ref('int_fx_rates_at_report_date') }}
    WHERE currency = 'USD'
)

-- 4) on assemble, une ligne par trimestre
SELECT
    f.report_date,
    p.nb_positions,
    f.net_assets_usd,
    u.eurusd_rate,
    CAST(ROUND(f.net_assets_usd / u.eurusd_rate, 2) AS DECIMAL(38, 2))                    AS net_assets_eur,
    p.securities_eur,
    CAST(ROUND(f.net_assets_usd / u.eurusd_rate, 2) AS DECIMAL(38, 2)) - p.securities_eur AS cash_and_other_eur,
    CAST(ROUND(fl.net_flows_usd / u.eurusd_rate, 2) AS DECIMAL(38, 2))                    AS net_flows_eur
FROM {{ ref('stg_nport__fund') }} AS f
JOIN positions AS p  ON p.report_date  = f.report_date
JOIN flows     AS fl ON fl.report_date = f.report_date
JOIN usd       AS u  ON u.report_date  = f.report_date