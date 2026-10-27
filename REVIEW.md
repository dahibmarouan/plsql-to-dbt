# Fiche de relecture : migration PL/SQL → dbt

Ce document est destiné à une personne ou une IA chargée de **relire et valider** ce projet.
Il explique le contexte, les choix faits, les résultats obtenus, et liste les points précis à vérifier.

---

## 1. Ce que je te demande

Valide ou conteste ce projet sur quatre plans :

1. **Fidélité** : le projet dbt reproduit-il bien le comportement du package PL/SQL, sauf là où un écart est volontaire et documenté ?
2. **Justesse métier** : les quatre corrections apportées au vieux code (section 5) sont-elles correctes du point de vue de l'administration de fonds ?
3. **Qualité dbt** : structure des couches, nommage, tests, lisibilité du SQL.
4. **Honnêteté de la présentation** : les chiffres annoncés (section 6) sont-ils exacts et présentés sans exagération ?

Réponds avec une liste de constats classés en trois niveaux : **bloquant** (faux ou trompeur), **à améliorer**, **remarque**. Pour chaque constat : le fichier, la ligne si possible, le problème, la correction proposée.

---

## 2. Comment relancer le projet

Prérequis : Python 3.10 ou plus récent.

```bash
python -m venv .venv
source .venv/bin/activate          # Windows : .venv\Scripts\activate
pip install -r requirements.txt
export DBT_PROFILES_DIR=.          # Windows PowerShell : $env:DBT_PROFILES_DIR = "."
dbt seed --full-refresh
dbt build
```

Résultat attendu : tout est vert (`ERROR=0`). La base DuckDB est créée dans `lookthrough.duckdb`.

Pour régénérer les sources et la sortie de référence du vieux code :

```bash
python scripts/extract_sources.py     # XML SEC + ZIP BCE  →  seeds/raw_*.csv
python legacy/legacy_port.py          # sortie du vieux code  →  seeds/legacy_*.csv
```

---

## 3. Le contexte

**Le scénario (fictif).** Une banque luxembourgeoise distribue à ses clients européens un fonds américain réel, *Oakmark International Small Cap Fund*. Chaque trimestre, elle doit produire la **transparisation** (*look-through*) du fonds en euros : chaque ligne du portefeuille valorisée en EUR avec son pays de risque, plus une synthèse (actif net, titres, liquidités, flux de souscriptions et rachats). Ce calcul tourne dans un package Oracle PL/SQL.

**Les données (réelles et publiques).**

| Source | Contenu | Période |
|---|---|---|
| SEC, formulaire N-PORT (`data/raw/nport_*.xml`) | Positions du fonds (ISIN, devise, valeur en USD, taux de change du fonds), actif net, flux mensuels | 8 fins de trimestre, du 30/09/2024 au 30/06/2026 |
| BCE, taux de référence (`data/raw/eurofxref-hist.zip`) | Taux de change quotidiens de l'euro contre 41 devises (format large, une colonne par devise, `N/A` si non cotée) | 2024-01-02 → 2026-10-20 |

Volume : 508 lignes de positions (62 à 65 par trimestre), 24 lignes de flux, 716 jours de taux.

**Le vieux code (fictif).** `legacy/pkg_lookthrough_eur.sql` a été écrit pour l'exercice, dans le style des traitements legacy bancaires. Il n'y a pas d'Oracle disponible : sa sortie de référence (`seeds/legacy_rpt_*.csv`) est produite par `legacy/legacy_port.py`, un portage ligne à ligne en Python (mêmes filtres, mêmes replis, arrondi Oracle « au plus proche, 0,5 vers le haut », mêmes erreurs avalées).

> **Point à vérifier en priorité : la fidélité de `legacy_port.py` au PL/SQL.** Toute la réconciliation repose dessus.

---

## 4. Carte du projet

```
data/raw/                 fichiers téléchargés, non modifiés
scripts/extract_sources.py  XML/ZIP → CSV, sans nettoyage (le nettoyage est fait en staging)
legacy/                   package PL/SQL, DDL Oracle, portage Python
seeds/raw_*.csv           les 4 tables sources Oracle
seeds/legacy_rpt_*.csv    les 2 tables produites par le vieux code
seeds/ref_risk_country_override.csv   règle métier sortie du code (voir piège 3)
models/staging/           1 modèle par source : renommage, types, drapeaux
models/intermediate/      int_fx_rates_at_report_date : taux BCE à chaque fin de trimestre
models/marts/             fct_positions_eur, fct_fund_quarter_eur, rpt_reconciliation_positions
tests/                    2 tests génériques + 1 test singulier (aucun écart inexpliqué)
macros/generate_schema_name.sql   schémas nommés staging / intermediate / marts tels quels
```

**Correspondance PL/SQL → dbt**

| Bloc PL/SQL (lignes) | Modèle dbt |
|---|---|
| Tables sources `NPORT_*`, `ECB_FX_HIST` | `stg_nport__holdings`, `stg_nport__fund`, `stg_nport__flows`, `stg_ecb__fx_rates` |
| `get_ecb_rate` (41-60) : SQL dynamique, dernier taux connu, `EUR` = 1 | `stg_ecb__fx_rates` (UNPIVOT) + `int_fx_rates_at_report_date` (jointure `<=`, `ROW_NUMBER`, `UNION ALL` pour l'euro) |
| `risk_country` (65-73) : `IF KY → HK, JE → GB` | seed `ref_risk_country_override` + `LEFT JOIN` + `COALESCE` dans `fct_positions_eur` |
| `load_positions` (78-108) : curseur, conversion, `INSERT` | `fct_positions_eur` |
| `load_summary` (113-147) : totaux, flux nets, `INSERT` | `fct_fund_quarter_eur` |
| `run` (152-169) : boucle sur les trimestres, `COMMIT`, `WHEN OTHERS` | le graphe dbt (`ref`) ; les erreurs deviennent des tests |

**Formules de valorisation (identiques au vieux code, sauf cas 1 ci-dessous)**

- `val_local = ROUND(val_usd × fund_fx_per_usd, 2)` (taux publié par le fonds, en unités de devise pour 1 USD ; 1 pour les lignes en USD)
- `val_eur = ROUND(val_local / ecb_rate, 2)` (taux BCE, en unités de devise pour 1 EUR, dernier publié au plus tard à la fin du trimestre)
- `net_assets_eur = ROUND(net_assets_usd / taux BCE du USD, 2)`
- `cash_and_other_eur = net_assets_eur − securities_eur`

---

## 5. Les quatre pièges du vieux code, et ce qui a été fait

| # | Dans le PL/SQL | Effet | Choix fait en dbt | À challenger |
|---|---|---|---|---|
| 1 | `get_ecb_rate` : la colonne `CLP` (peso chilien) n'existe pas dans le fichier BCE → erreur avalée par `WHEN OTHERS THEN RETURN NULL` (l. 58) | La position Embotelladora Andina (8 lignes, une par trimestre) a `val_eur` vide, disparaît du total des titres et se retrouve comptée dans les liquidités : 8,4 à 16,7 M€ selon le trimestre | **Cours croisé via le dollar** : `val_eur = ROUND(val_usd / taux BCE du USD, 2)`, colonne `fx_method = 'USD_CROSS'`, test `not_null` sur `val_eur` | Le cours croisé via le USD est-il acceptable, sachant que `val_usd` a été calculé par le fonds avec son propre taux CLP ? Faudrait-il plutôt une source de taux CLP/EUR ? |
| 2 | Curseur `c_hold` : `AND isin IS NOT NULL` (l. 85) | Les pensions livrées (*repo*, Fixed Income Clearing Corp, sans ISIN) disparaissent de la liste des positions : 16,8 à 42,9 M€ selon le trimestre. Elles restent comptées dans les liquidités par différence | Les 8 lignes sont **gardées**, avec `security_id = other_id` et `is_cash_equivalent = true`. Elles sont **exclues de `securities_eur`** et restent donc dans `cash_and_other_eur` | Une pension livrée doit-elle figurer dans une transparisation, en liquidités ? Le traitement est-il cohérent entre positions et synthèse ? |
| 3 | `risk_country` : règle codée en dur `KY → HK`, `JE → GB` (l. 65-73) | Règle appliquée **par pays et non par émetteur** : Sapiens International (logiciels, Israël) est classée HK, Birkenstock (Allemagne) est classée GB | **Comportement conservé à l'identique**, mais la règle est sortie dans une table de référence documentée (`ref_risk_country_override`, colonne `rule_source`) | Faut-il corriger la règle (par émetteur) ou seulement la rendre visible et la soumettre au métier, comme fait ici ? |
| 4 | `load_summary` : `SUM(sales) - SUM(redemption)` (l. 136) | Les dividendes réinvestis (colonne `reinvestment`) sont ignorés. Ils sont non nuls en décembre 2024 (69,8 M$) et décembre 2025 (53,9 M$) | `net_flows = souscriptions + dividendes réinvestis − rachats` | Inclure les dividendes réinvestis dans les flux nets est-il la bonne définition ? |

---

## 6. Résultats de la réconciliation

### Positions (`rpt_reconciliation_positions`)

Comparaison ligne à ligne (`FULL OUTER JOIN` sur `report_date`, `line_no`) de `val_local`, `val_eur` et `risk_country`.

| Statut | Lignes |
|---|---|
| `identical` (égalité exacte au centime) | 492 |
| `fixed: line without ISIN dropped by the legacy` (piège 2) | 8 |
| `fixed: currency not quoted by the ECB` (piège 1) | 8 |
| `UNEXPLAINED` | **0** (garanti par `tests/assert_no_unexplained_difference.sql`) |

### Synthèse par trimestre (EUR)

`net_assets_eur` est identique sur les 8 trimestres. Les écarts :

| Trimestre | Titres, vieux code | Titres, dbt | Liquidités et autres, vieux code | Liquidités et autres, dbt | Flux nets, vieux code | Flux nets, dbt |
|---|---:|---:|---:|---:|---:|---:|
| 2024-09-30 | 1 427 289 157,12 | 1 443 943 595,62 | 62 357 502,36 | 45 703 063,86 | −12 432 041,12 | −12 432 041,12 |
| 2024-12-31 | 1 170 051 847,56 | 1 185 999 622,49 | 38 163 119,35 | 22 215 344,42 | **−207 536 904,76** | **−140 348 360,27** |
| 2025-03-31 | 1 079 455 211,18 | 1 094 540 783,91 | 41 096 196,04 | 26 010 623,31 | −137 526 041,58 | −137 526 041,58 |
| 2025-06-30 | 1 117 942 207,44 | 1 126 699 315,26 | 52 647 997,54 | 43 890 889,72 | −35 309 274,73 | −35 309 274,73 |
| 2025-09-30 | 1 094 855 829,51 | 1 103 297 313,20 | 45 722 903,09 | 37 281 419,40 | −38 103 117,71 | −38 103 117,71 |
| 2025-12-31 | 1 061 324 119,18 | 1 070 800 962,07 | 44 818 110,11 | 35 341 267,22 | **−36 772 269,69** | **+9 087 074,66** |
| 2026-03-31 | 968 187 193,27 | 976 933 178,82 | 45 854 841,79 | 37 108 856,24 | −26 634 437,45 | −26 634 437,45 |
| 2026-06-30 | 995 028 309,09 | 1 005 413 251,12 | 46 346 150,99 | 35 961 208,96 | −32 460 047,12 | −32 460 047,12 |

- L'écart sur les titres et les liquidités est égal, au centime, à la valeur en euros de la position en peso chilien (piège 1).
- L'écart sur les flux nets n'apparaît qu'en décembre (piège 4). Au 31/12/2025, **le signe s'inverse** : le vieux code annonce des sorties nettes de 36,8 M€, alors que le fonds a reçu 9,1 M€ d'entrées nettes.

---

## 7. Limites connues et points ouverts

1. **Mélange de deux sources de taux.** `val_local` utilise le taux publié par le fonds (fixing de fin de journée), puis `val_eur` le taux BCE (fixing de 14 h 15). Pour une position en EUR, `val_eur` repose donc sur le taux EUR/USD du fonds, alors que `net_assets_eur` utilise le taux BCE du dollar. Le résidu se retrouve dans `cash_and_other_eur` : de −4,3 M€ à +5,5 M€ selon le trimestre (environ 0,4 % de l'actif au maximum). Ce choix reproduit le vieux code. **Est-il défendable, ou faut-il convertir toutes les lignes directement depuis `val_usd` ?**
2. **Données trimestrielles seulement.** Les positions détaillées N-PORT ne sont publiques que pour le dernier mois de chaque trimestre.
3. **Le vieux code est fictif** et sa sortie vient d'un portage Python, pas d'une exécution Oracle.
4. **Le projet tourne uniquement sur DuckDB.** `UNPIVOT … ON COLUMNS(* EXCLUDE ("Date"))` est une syntaxe propre à DuckDB. Un portage vers Snowflake demanderait la macro `dbt_utils.unpivot`, ou un `UNPIVOT` qui liste les colonnes une à une.
5. **Arrondis.** Sur DuckDB, la division de décimaux donne un nombre à virgule flottante. La parité au centime a été vérifiée sur les 492 lignes, mais elle n'est pas garantie par construction.
6. **Taux périmés.** La règle « dernier taux connu » n'a pas de limite d'ancienneté. Exemple : le lev bulgare (BGN) n'est plus coté depuis le passage de la Bulgarie à l'euro au 1er janvier 2026, et son dernier taux (31/12/2025) est réutilisé. Aucune position n'est concernée ici, mais aucun test ne le détecterait.

---

## 8. Questions précises pour le relecteur

1. `legacy/legacy_port.py` reproduit-il fidèlement `legacy/pkg_lookthrough_eur.sql`, y compris l'ordre des arrondis et le comportement de `WHEN OTHERS` ?
2. Les quatre corrections de la section 5 sont-elles justes du point de vue d'un administrateur de fonds luxembourgeois ?
3. Le point 1 de la section 7 (deux sources de taux) est-il un défaut à corriger ou un choix acceptable à documenter ?
4. Quels tests manque-t-il ? Par exemple : ancienneté maximale d'un taux, somme des poids, cohérence `net_assets_usd ≈ somme des val_usd + autres actifs − passifs`.
5. La structure dbt (staging / intermediate / marts, nommage, YAML) suit-elle les bonnes pratiques de dbt Labs ?
6. Hormis l'`UNPIVOT`, quelles autres syntaxes propres à DuckDB empêcheraient un portage vers Snowflake ou Oracle ?
7. Les chiffres et formulations de la section 6 peuvent-ils être publiés tels quels sur LinkedIn sans être trompeurs ?
