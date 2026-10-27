SELECT *
FROM {{ ref ('rpt_reconciliation_positions') }}
WHERE status = 'UNEXPLAINED'