WITH unpivoted AS (
    UNPIVOT {{ ref('raw_ecb_fx_hist') }}
    ON COLUMNS(* EXCLUDE ("Date"))
    INTO
        NAME currency
        VALUE rate_txt

)

SELECT 
    "Date" as rate_date,
    currency,
    CAST (rate_txt AS DECIMAL (18, 8)) as units_per_eur
FROM unpivoted
WHERE rate_txt <> 'N/A'
