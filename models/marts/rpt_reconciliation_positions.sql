WITH modern AS (
    SELECT * FROM {{ ref('fct_positions_eur') }}
),

legacy AS (
    SELECT * FROM {{ ref('legacy_rpt_position_eur') }}
)

SELECT
    COALESCE(m.report_date, l.report_date) AS report_date,
    COALESCE(m.line_no, l.line_no)         AS line_no,
    COALESCE(m.issuer_name, l.issuer_name) AS issuer_name,
    m.currency,
    l.val_eur                              AS legacy_val_eur,
    m.val_eur                              AS modern_val_eur,
    CASE
        WHEN l.line_no IS NULL AND m.is_cash_equivalent
            THEN 'fixed: line without ISIN dropped by the legacy'
        WHEN l.val_eur IS NULL AND m.fx_method = 'USD_CROSS'
            THEN 'fixed: currency not quoted by the ECB'
        WHEN l.val_local    = m.val_local
         AND l.val_eur      = m.val_eur
         AND l.risk_country = m.risk_country
            THEN 'identical'
        ELSE 'UNEXPLAINED'
    END AS status
FROM modern AS m
FULL OUTER JOIN legacy AS l
    ON  l.report_date = m.report_date
    AND l.line_no     = m.line_no