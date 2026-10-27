# PL/SQL → dbt : transparisation en EUR d'un fonds réel

Migration d'un package PL/SQL (Oracle) vers dbt, sur données publiques réelles :

- les déclarations trimestrielles **N-PORT** du fonds *Oakmark International Small Cap Fund*, publiées par la SEC (le gendarme boursier américain) ;
- les **taux de change de référence de la BCE** (Banque Centrale Européenne).

> Le package PL/SQL (`legacy/`) a été écrit pour l'exercice, dans le style des traitements que l'on trouve en banque. Les données sont réelles.

## Structure

```
data/raw/        fichiers téléchargés (8 déclarations N-PORT en XML, historique BCE)
scripts/         extract_sources.py : XML/ZIP → seeds/raw_*.csv (= les tables Oracle sources)
legacy/          le package PL/SQL, ses tables, et legacy_port.py qui produit sa sortie de référence
seeds/           raw_* (sources) et legacy_* (ce que produit le vieux code)
models/          le projet dbt (en cours)
```

## Lancer

```bash
python -m venv .venv
.venv\Scripts\activate            # Windows  (macOS/Linux : source .venv/bin/activate)
pip install -r requirements.txt
set DBT_PROFILES_DIR=.            # Windows  (macOS/Linux : export DBT_PROFILES_DIR=.)
dbt build
```

Pour régénérer les sources et la sortie de référence :
`python scripts/extract_sources.py && python legacy/legacy_port.py`
