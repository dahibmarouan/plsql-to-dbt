SELECT 
    report_date,
    line_no,
    asset_cat,
    val_usd,
    pct_val,
    units,
    inv_country,
    balance,
    cur_cd as currency,
    other_id,
    isin,
    issuer_name,
    COALESCE (exchange_rt, 1) as fund_fx_per_usd,
    COALESCE (isin, other_id) as security_id,
    asset_cat = 'RA' as is_cash_equivalent
FROM {{ref ('raw_nport_holdings') }}