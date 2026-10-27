SELECT
    report_date,
    series_id,
    series_name,
    tot_assets as tot_assets_usd,
    tot_liabs as tot_liabs_usd,
    net_assets as net_assets_usd
FROM {{ref ('raw_nport_fund') }}