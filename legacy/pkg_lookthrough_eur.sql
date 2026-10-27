/* ============================================================================
   PKG_LOOKTHROUGH_EUR  -  Transparisation trimestrielle en EUR d'un fonds tiers
   ----------------------------------------------------------------------------
   Contexte : la banque distribue a ses clients europeens le fonds americain
   "Oakmark International Small Cap Fund". Chaque trimestre, le portefeuille
   publie par le fonds (formulaire N-PORT de la SEC) est charge dans NPORT_*,
   puis ce package produit :
     - RPT_POSITION_EUR : chaque ligne du portefeuille valorisee en EUR
     - RPT_FUND_EUR     : la synthese du trimestre (titres, liquidites, flux)

   Schema : REPORTING        Base : Oracle 19c        Ordonnanceur : Control-M
   Appel  : BEGIN pkg_lookthrough_eur.run(DATE '2024-09-30', DATE '2026-06-30'); END;

   Historique
   2017-02-06  JPM   creation
   2017-03-14  JPM   lignes techniques sans ISIN ignorees (cf. mail JPM)
   2019-10-02  SKL   pays de risque pour les societes holding (demande Risk)
   2021-05-18  ext   taux BCE lus directement dans la table externe ECB_FX_HIST
   2022-11-07  ext   gestion des devises non cotees par la BCE

   NE PAS MODIFIER SANS PREVENIR L'EQUIPE REPORTING CLIENTS
   ============================================================================

   NOTE (projet portfolio) : ce package est ecrit pour l'exercice, dans le style
   des traitements legacy que l'on trouve en banque. Les donnees, elles, sont
   reelles : declarations publiques N-PORT (SEC) et taux de reference de la BCE.
   ========================================================================== */

CREATE OR REPLACE PACKAGE pkg_lookthrough_eur AS
  PROCEDURE run (p_from IN DATE, p_to IN DATE);
END pkg_lookthrough_eur;
/

CREATE OR REPLACE PACKAGE BODY pkg_lookthrough_eur AS

  ---------------------------------------------------------------------------
  -- Taux BCE : unites de devise pour 1 EUR, dernier taux publie <= p_date
  -- ECB_FX_HIST est une table externe sur le fichier eurofxref-hist.csv :
  -- une colonne par devise, valeur 'N/A' quand la devise n'est pas cotee.
  ---------------------------------------------------------------------------
  FUNCTION get_ecb_rate (p_ccy IN VARCHAR2, p_date IN DATE) RETURN NUMBER IS
    v_txt VARCHAR2(30);
  BEGIN
    IF p_ccy = 'EUR' THEN
      RETURN 1;
    END IF;

    EXECUTE IMMEDIATE
      'SELECT ' || p_ccy || ' FROM ecb_fx_hist'
      || ' WHERE rate_date = (SELECT MAX(rate_date) FROM ecb_fx_hist'
      || '                     WHERE rate_date <= :1'
      || '                       AND ' || p_ccy || ' <> ''N/A'')'
      INTO v_txt
      USING p_date;

    RETURN TO_NUMBER(v_txt, '9999999990D9999999', 'NLS_NUMERIC_CHARACTERS=''.,''');
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;   -- 2022-11-07 : devise non cotee, on ne bloque pas le batch
  END get_ecb_rate;

  ---------------------------------------------------------------------------
  -- Pays de risque : pays ou l'emetteur exerce reellement son activite
  ---------------------------------------------------------------------------
  FUNCTION risk_country (p_country IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_country = 'KY' THEN        -- holdings des iles Caimans : Asie
      RETURN 'HK';
    ELSIF p_country = 'JE' THEN     -- Jersey : Royaume-Uni
      RETURN 'GB';
    END IF;
    RETURN p_country;
  END risk_country;

  ---------------------------------------------------------------------------
  -- Positions d'un trimestre
  ---------------------------------------------------------------------------
  PROCEDURE load_positions (p_date IN DATE) IS

    CURSOR c_hold IS
      SELECT line_no, issuer_name, isin, cur_cd, exchange_rt,
             val_usd, asset_cat, inv_country
        FROM nport_holdings
       WHERE report_date = p_date
         AND isin IS NOT NULL;               -- 2017-03-14 JPM

    v_local NUMBER;
    v_fx    NUMBER;
    v_eur   NUMBER;
  BEGIN
    DELETE FROM rpt_position_eur WHERE report_date = p_date;

    FOR r IN c_hold LOOP
      -- valeur en devise locale : le fonds publie la valeur en USD
      -- et le taux utilise (unites de devise pour 1 USD)
      v_local := ROUND(r.val_usd * NVL(r.exchange_rt, 1), 2);

      v_fx  := get_ecb_rate(r.cur_cd, p_date);
      v_eur := ROUND(v_local / v_fx, 2);

      INSERT INTO rpt_position_eur
        (report_date, line_no, isin, issuer_name, asset_cat, cur_cd,
         risk_country, val_local, ecb_rate, val_eur, created_at)
      VALUES
        (p_date, r.line_no, r.isin, r.issuer_name, r.asset_cat, r.cur_cd,
         risk_country(r.inv_country), v_local, v_fx, v_eur, SYSDATE);
    END LOOP;
  END load_positions;

  ---------------------------------------------------------------------------
  -- Synthese d'un trimestre
  ---------------------------------------------------------------------------
  PROCEDURE load_summary (p_date IN DATE) IS
    v_net_usd    NUMBER;
    v_eurusd     NUMBER;
    v_net_eur    NUMBER;
    v_sec_eur    NUMBER;
    v_nb         NUMBER;
    v_flows_usd  NUMBER;
  BEGIN
    DELETE FROM rpt_fund_eur WHERE report_date = p_date;

    SELECT net_assets INTO v_net_usd
      FROM nport_fund
     WHERE report_date = p_date;

    v_eurusd  := get_ecb_rate('USD', p_date);
    v_net_eur := ROUND(v_net_usd / v_eurusd, 2);

    SELECT COUNT(*), NVL(SUM(val_eur), 0)
      INTO v_nb, v_sec_eur
      FROM rpt_position_eur
     WHERE report_date = p_date;

    -- flux nets du trimestre : souscriptions - rachats
    SELECT SUM(sales) - SUM(redemption)
      INTO v_flows_usd
      FROM nport_flows
     WHERE report_date = p_date;

    INSERT INTO rpt_fund_eur
      (report_date, nb_positions, net_assets_usd, eurusd_rate, net_assets_eur,
       securities_eur, cash_and_other_eur, net_flows_eur, created_at)
    VALUES
      (p_date, v_nb, v_net_usd, v_eurusd, v_net_eur,
       v_sec_eur, v_net_eur - v_sec_eur, ROUND(v_flows_usd / v_eurusd, 2), SYSDATE);
  END load_summary;

  ---------------------------------------------------------------------------
  -- Point d'entree
  ---------------------------------------------------------------------------
  PROCEDURE run (p_from IN DATE, p_to IN DATE) IS
  BEGIN
    FOR q IN (SELECT report_date
                FROM nport_fund
               WHERE report_date BETWEEN p_from AND p_to
               ORDER BY report_date)
    LOOP
      load_positions(q.report_date);
      load_summary(q.report_date);
      COMMIT;
    END LOOP;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      INSERT INTO batch_log (proc_name, msg, created_at)
      VALUES ('PKG_LOOKTHROUGH_EUR.RUN', SQLERRM, SYSDATE);
      COMMIT;
  END run;

END pkg_lookthrough_eur;
/
