WITH all_rates AS (
SELECT
    f.report_date,
    r.currency,
    r.rate_date,
    r.units_per_eur,    
    ROW_NUMBER() OVER (
        PARTITION BY currency, report_date
        ORDER BY rate_date DESC) AS rn
FROM {{ref ('stg_nport__fund') }} AS f
JOIN {{ref ('stg_ecb__fx_rates') }} AS r
    ON f.report_date >= r.rate_date

)

SELECT 
    report_date,
    currency,
    rate_date,
    units_per_eur
FROM all_rates
WHERE rn = 1
UNION ALL
SELECT
    report_date,
    'EUR' AS currency,
    report_date AS rate_date,
    1 AS units_per_eur
FROM {{ ref('stg_nport__fund') }}