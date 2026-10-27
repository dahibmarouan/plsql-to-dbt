SELECT *
FROM {{ ref ('int_fx_rates_at_report_date') }}
WHERE {{ dbt.datediff('rate_date', 'report_date', 'day') }} > 5
AND currency IN (SELECT currency FROM {{ref ('stg_nport__holdings') }})