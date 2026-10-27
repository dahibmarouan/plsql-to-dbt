SELECT *
FROM {{ ref ('rpt_reconciliation_fund') }}
WHERE status = 'UNEXPLAINED'