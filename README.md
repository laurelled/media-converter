# Media Converter / Compressor
Comprime le dimensioni di file video e immagini, lasciando la struttura delle directory intatta e copiando gli altri file. Le date di ultima modifica dei file rimangono le stesse dei file di origine.
Script per comprimere le dimensioni dei media (immagine e video) periodicamente. È pensato per funzionare in due modi:

- **CLASSICO**: La classica conversione partendo da una cartella sorgente a una di destinazione per i task una tantum

- **WATCH**: Eseguirlo periodicamente, in modo tale che se dei media vengono aggiunti nella cartella che viene osservata, vengono compressi alla prossima esecuzione.

È possibile selezionare la modalità specificando il parametro -Watch. Se è specificato (ovviamente) lo script funzionerà in modalità WATCH

## Requisiti per usare lo script
- `ffmpeg` >= 8.0.1-essentials_build
- `HandbrakeCLI` >= 1.10.2
- Powershell 5+

Entrambi devono essere presenti in $PATH

## Run
Per eseguire in modalità CLASSICA
> `.\convert.ps1 -Src path/to/src -Dest path/to/dest`

Ho preferito tenere i nomi parametrici per mie gusti personali, così c'è meno modo di confondersi

In modalità **WATCH**

> `.\convert.ps1 -Src path/to/src -Watch`

### La modalità WATCH
In questa modalità, verrà creato un file `.conversion_snapshot` nella cartella specificata come source che memorizza tutte le cartelle che sono già state scansionate per file da convertire. Nel file vengono salvati i path assoluti di tutte le cartelle. Prima di partire, lo script filtrerà quindi tutte le cartelle che non sono già presenti nello snapshot, e si occuperà di convertire solo i file al loro interno.

