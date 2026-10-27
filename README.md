# PL/SQL → dbt : transparisation en euros d'un fonds réel

[![dbt build](https://github.com/dahibmarouan/plsql-to-dbt/actions/workflows/dbt_build.yml/badge.svg)](https://github.com/dahibmarouan/plsql-to-dbt/actions/workflows/dbt_build.yml)

**Le site : [dahibmarouan.github.io/plsql-to-dbt](https://dahibmarouan.github.io/plsql-to-dbt/)**, régénéré à chaque modification à partir des vrais résultats de dbt.

Migration d'un package PL/SQL Oracle vers dbt, sur les **données publiques réelles** d'un fonds :
les déclarations trimestrielles N-PORT d'*Oakmark International Small Cap Fund* publiées par la SEC,
et les taux de change de référence de la BCE.

> **Transparence.** Le package PL/SQL (`legacy/`) a été écrit pour l'exercice, dans le style des traitements
> que l'on rencontre en banque, avec des défauts typiques. Les données, elles, sont réelles :
> les effets chiffrés ci-dessous sont ceux qu'auraient ces défauts sur le vrai fonds.

## Le cas

Une banque luxembourgeoise distribue ce fonds américain à ses clients européens. Chaque trimestre, elle produit
sa **transparisation en euros** : chaque position valorisée en EUR avec son pays de risque, et une synthèse
(actif net, titres, liquidités, flux de souscriptions et rachats).

## Le résultat

| | |
|---|---|
| Vieux code | 1 package PL/SQL de 172 lignes |
| Projet dbt | 9 modèles SQL, 58 tests, deux réconciliations automatiques avec le vieux code |
| Positions | **492 sur 508 identiques au centime** au vieux code |
| Écarts | **16**, tous expliqués par un défaut corrigé, **0 inexpliqué** (garanti par un test) |

**Les défauts du vieux code, et leur effet sur les vraies données :**

1. **Une devise non cotée par la BCE (le peso chilien) est perdue en silence** (`WHEN OTHERS THEN RETURN NULL`) :
   8 à 17 M€ d'actions présentés comme des liquidités chaque trimestre. Corrigé par un cours croisé via le dollar.
2. **Les lignes sans ISIN sont écartées** : les pensions livrées (17 à 48 M$) disparaissent de la liste des positions.
   Gardées et marquées comme équivalents de liquidités.
3. **Une règle pays codée en dur** (`KY → HK`, `JE → GB`) s'applique par pays et non par émetteur.
   Conservée à l'identique, mais sortie dans une table de référence documentée, à faire valider par le métier.
4. **Les dividendes réinvestis sont oubliés dans les flux nets.** Au 31/12/2025, le vieux code annonce
   **−36,8 M€** de sorties nettes ; une fois corrigés, les flux sont de **+9,1 M€**.

## Structure

```
data/raw/            fichiers téléchargés : 8 déclarations N-PORT (XML) et l'historique BCE (ZIP)
scripts/             extract_sources.py : XML / ZIP → seeds/raw_*.csv
legacy/              le package PL/SQL, ses tables Oracle, et legacy_port.py qui produit sa sortie de référence
seeds/               raw_* (sources), legacy_* (sortie du vieux code), ref_* (règles métier)
models/staging/      une vue par source : noms, types, drapeaux
models/intermediate/ le taux BCE à chaque fin de trimestre
models/marts/        positions et synthèse en euros, et les deux réconciliations avec le vieux code
tests/               tests génériques et singuliers (aucun écart inexpliqué, aucun taux trop ancien)
site/                build_site.py + template.html : le site, construit depuis les résultats de dbt
REVIEW.md            fiche de relecture : choix, limites, résultats détaillés
```

## Lancer le projet

```bash
python -m venv .venv
.venv\Scripts\activate              # Windows   (macOS / Linux : source .venv/bin/activate)
pip install -r requirements.txt
$env:DBT_PROFILES_DIR = "."         # PowerShell (macOS / Linux : export DBT_PROFILES_DIR=.)
dbt build
```

Base locale DuckDB, rien d'autre à installer. Pour générer le site en local : `python site/build_site.py`, puis ouvrir `docs/index.html`.

À chaque modification, GitHub Actions relance `dbt build`, reconstruit le site à partir des résultats et le publie sur GitHub Pages. Si un seul test échoue, le site n'est pas mis à jour.

## Limites

- Le vieux code est simulé ; sa sortie est produite par un portage ligne à ligne en Python (`legacy/legacy_port.py`), faute d'Oracle.
- Positions disponibles seulement en fin de trimestre (règle de publication de la SEC).
- Le projet tourne sur DuckDB uniquement.
- Le détail des choix et des points ouverts est dans [`REVIEW.md`](REVIEW.md).

## Données

- SEC, [Form N-PORT](https://www.sec.gov/data-research/sec-markets-data/form-n-port-data-sets), Oakmark International Small Cap Fund (série S000002763), du 30/09/2024 au 30/06/2026.
- BCE, [taux de change de référence de l'euro](https://www.ecb.europa.eu/stats/eurofxref).
