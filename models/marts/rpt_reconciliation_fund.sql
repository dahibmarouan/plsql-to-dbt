-- 1) les deux versions de la synthèse
WITH modern AS (
    SELECT * FROM {{ ref('fct_fund_quarter_eur') }}
),

legacy AS (
    SELECT * FROM {{ ref('legacy_rpt_fund_eur') }}
),

-- 2) piège 1 : la valeur en euros de la position que le vieux code avait perdue (peso chilien)
lost_positions AS (
    SELECT report_date, SUM(val_eur) AS lost_positions_eur
    FROM {{ ref('fct_positions_eur') }}
    WHERE fx_method = 'USD_CROSS'
    GROUP BY report_date
),

-- 3) piège 4 : les dividendes réinvestis que le vieux code ignorait
reinvestments AS (
    SELECT report_date, SUM(reinvestments_usd) AS reinvestments_usd
    FROM {{ ref('stg_nport__flows') }}
    GROUP BY report_date
)

-- 4) une ligne par trimestre : chaque écart, et ce qui l'explique
SELECT
    m.report_date,

    l.net_assets_eur                               AS legacy_net_assets_eur,
    m.net_assets_eur                               AS modern_net_assets_eur,

    l.securities_eur                               AS legacy_securities_eur,
    m.securities_eur                               AS modern_securities_eur,
    m.securities_eur - l.securities_eur            AS diff_securities_eur,
    COALESCE(p.lost_positions_eur, 0)              AS explained_by_lost_positions_eur,

    l.net_flows_eur                                AS legacy_net_flows_eur,
    m.net_flows_eur                                AS modern_net_flows_eur,
    m.net_flows_eur - l.net_flows_eur              AS diff_net_flows_eur,
    ROUND(r.reinvestments_usd / m.eurusd_rate, 2)  AS explained_by_reinvestments_eur,

    -- tolérance d'un centime : chaque montant a été arrondi séparément
    CASE
        WHEN m.net_assets_eur = l.net_assets_eur
         AND ABS((m.securities_eur - l.securities_eur) - COALESCE(p.lost_positions_eur, 0)) <= 0.01
         AND ABS((m.net_flows_eur - l.net_flows_eur) - ROUND(r.reinvestments_usd / m.eurusd_rate, 2)) <= 0.01
            THEN 'explained'
        ELSE 'UNEXPLAINED'
    END AS status

FROM modern AS m
JOIN legacy        AS l ON l.report_date = m.report_date
LEFT JOIN lost_positions AS p ON p.report_date = m.report_date
LEFT JOIN reinvestments  AS r ON r.report_date = m.report_date