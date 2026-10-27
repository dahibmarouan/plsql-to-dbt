SELECT
    report_date,
    month_no,
    sales as subscriptions_usd,
    reinvestment as reinvestments_usd,
    redemption as redemptions_usd
FROM {{ref ('raw_nport_flows') }}