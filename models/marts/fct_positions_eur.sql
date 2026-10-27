SELECT
    h.report_date,
    h.line_no,
    h.security_id,
    h.isin,
    h.issuer_name,
    h.asset_cat,
    h.is_cash_equivalent,
    h.currency,
    h.inv_country,
    COALESCE ( o.risk_country, h.inv_country ) AS risk_country,
    h.val_usd,
    ROUND(h.val_usd * h.fund_fx_per_usd, 2) AS val_local,
    fx.units_per_eur                        AS ecb_rate,

    -- 1) le calcul habituel avec le taux BCE de la devise
    -- 2) s'il est vide (peso chilien) : la valeur en dollars ÷ le taux BCE du dollar
    COALESCE(
        ROUND(ROUND(h.val_usd * h.fund_fx_per_usd, 2) / fx.units_per_eur, 2),
        ROUND(h.val_usd / usd.units_per_eur, 2)
    ) AS val_eur,

    -- traçabilité : comment la ligne a été calculée
    CASE
        WHEN fx.units_per_eur IS NULL THEN 'USD_CROSS'
        ELSE 'ECB'
    END AS fx_method

FROM {{ ref('stg_nport__holdings') }} AS h

-- le taux BCE de la devise du titre
LEFT JOIN {{ ref('int_fx_rates_at_report_date') }} AS fx
    ON  fx.report_date = h.report_date
    AND fx.currency    = h.currency

-- le taux BCE du dollar, pour le cas de secours
LEFT JOIN {{ ref('int_fx_rates_at_report_date') }} AS usd
    ON  usd.report_date = h.report_date
    AND usd.currency    = 'USD'

LEFT JOIN {{ref ('ref_risk_country_override')}} AS o
    ON o.inv_country = h.inv_country