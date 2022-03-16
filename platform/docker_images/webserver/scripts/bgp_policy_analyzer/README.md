# Looking glass checker

Topology and looking glass information is stored in the database `as.db`.
`config` and `groups` folder are the ones from the `platform` folder in the
mini-internet repository.

There are three scripts to interact with the database:

 - `cfparse.py`: Collect topology information from the `config` folder and save
   it to `as.db`.
 - `lgparse.py`: Uses the information from the `groups` folder to fill the
   database with information from the looking glasses.
 - `lganalyze.db`: Analyzes the content from the database for configuration errors.

Typically `cfparse.py` only needs to be run once, and then `lgparse.py` to
parse the current looking glasses and `lganalyze.py` to analyze them.

If the looking glass files in the group folder are being updated when
`lgparse.py` is run, it doesn't update the information and prints a warning to
`stderr`.

To run the tests simply type:
```
$ bash tests/run.sh
```
