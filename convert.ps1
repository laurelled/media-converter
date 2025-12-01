<#
.SYNOPSIS
    Script per comprimere le dimensioni dei media (immagine e video) periodicamente. È pensato per funzionare in due modi:
    - CLASSICO: La classica conversione partendo da una cartella sorgente a una di destinazione per i task una tantum
    - WATCH: Eseguirlo periodicamente, in modo tale che se dei media vengono aggiunti nella cartella che viene osservata, vengono compressi alla prossima esecuzione
    È possibile selezionare la modalità specificando il parametro -Watch
.PARAMETER Src
La cartella sorgente che contiene i media da comprimere.
.PARAMETER Dest
La cartella che conterrà gli output compressi. Se -Watch è specificato, questo parametro non verrà usato.
.PARAMETER Watch
Se specificato, lo script non richiederà due cartelle, bensì controllerà nel path specificato con -Source sono stati aggiunti dei file dall'ultima volta che lo script è stato eseguito, e in caso positivo li converte.
#>

[CmdletBinding(DefaultParameterSetName = 'None')] 
param(
    [Parameter(Mandatory)][string]$Src,
    [string]$Dest,
    [switch]$watch
)

# --- CONFIGURAZIONE ---
# Necessario avere nel PATH le cartelle dei bin di HandBrakeCLI e ffmpeg
$handbrakePath = "HandBrakeCLI"
$ffmpegPath = "ffmpeg"

# --- FILTRI ---
$estensioniImmagini = @(".jpg", ".jpeg", ".png", ".bmp", ".tiff")
$estensioniVideo = @(".mp4", ".mov", ".avi", ".mkv", ".m4v", ".wmv", ".flv", ".mts")
$handbrakePreset = "Fast 1080p30"

$lastSnapshotFile = Join-Path $Src "\.conversion_snapshot"
$lastFolderSnapshot = @()
$isWatchMode = $PSBoundParameters.ContainsKey('Watch')

# --- INIZIO ---
Clear-Host
Write-Host "--- SCRIPT: CONVERTI & COMPRIMI MEDIA ---" -ForegroundColor Cyan

function WriteSnapshotFile {
    if (!(Test-Path $lastSnapshotFile)) { New-Item -ItemType File $lastSnapshotFile | Out-Null }
    Set-ItemProperty -Path $lastSnapshotFile -Name IsReadOnly -Value $false
    Write-Output (Get-Item $lastSnapshotFile).Directory.FullName >> $lastSnapshotFile
    (Get-ChildItem -Path $Src -Recurse -Directory) | ForEach-Object { (Write-Output $_.FullName) >> $lastSnapshotFile }
    Set-ItemProperty -Path $lastSnapshotFile -Name IsReadOnly -Value $true 
}

# --- CHECK PARAMETRI ---
# Se il file di snapshot esiste già, ci sono delle cartelle che possiamo saltare che sono già state compresse.
if ($isWatchMode) {
    if ((Test-Path $lastSnapshotFile) -and ((Get-Item $lastSnapshotFile).Length -gt 0)) { 
        $lastFolderSnapshot = Get-Content -Path $lastSnapshotFile
    }
    else {
        Write-Host "È stata eseguita la modalità Watch, ma il file .conversion_snapshot non esiste! Creato il file, ora ogni cartella che viene aggiunta verrà convertita."
        WriteSnapshotFile
        exit
    }
}
if (!(Test-Path $Src)) { Write-Error "La cartella sorgente ($Src) non esiste!"; exit }
if (!(Test-Path $Dest) -and $PSBoundParameters.ContainsKey('Dest')) { New-Item -ItemType Directory -Path $Dest | Out-Null }
try { & $ffmpegPath -version | Out-Null } catch { Write-Error "FFmpeg non trovato!"; exit }
try { & $handbrakePath --version 2>1 | Out-Null } catch { Write-Error "HandBrakeCLI non trovato!"; exit }



$files = Get-ChildItem -Path $Src -Recurse -File

# Seleziono solo quei file che sono stati inseriti nella cartella dopo l'ultima esecuzione del file
if ($isWatchMode) {
    
    $files = $files | Where-Object { !($lastFolderSnapshot.Contains($_.Directory.FullName)) }
    if ($files.Length -eq 0) {
        Write-Host "Non ci sono file da comprimere!"
        Start-Sleep 5
        exit
    }
}

foreach ($file in $files) {
    # 1. Calcoli Percorsi
    $rootLength = (Get-Item $Src).FullName.Length + 1
    $percorsoRelativoCompleto = $file.FullName.Substring($rootLength)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $relativeDirPath = [System.IO.Path]::GetDirectoryName($percorsoRelativoCompleto)
    $targetDir = ""
    
    if (!$isWatchMode) {
        $targetDir = (Join-Path $Dest $relativeDirPath)
    }
    else {
        $targetDir = (Get-Item $file).Directory.FullName # ignoro la directory Dest se -Watch è stato attivato
    }
    
    $newExtension = $file.Extension
    $isImage = $false; $isVideo = $false

    if ($estensioniImmagini -contains $file.Extension.ToLower()) { $newExtension = ".jpg"; $isImage = $true } 
    elseif ($estensioniVideo -contains $file.Extension.ToLower()) { $newExtension = ".mp4"; $isVideo = $true }

    $fileDestinazione = Join-Path $targetDir ($baseName + $newExtension)
    $fileTemporaneo = $fileDestinazione + ".tmp"

    if (!(Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }

    $script:currentTempFile = $fileTemporaneo
    $outputPrefix = "$(Get-Date) ├── "


    if ($isImage -or $isVideo) {
        $conversionOutput = ""
        $cmdArgs = @(
            "-i", $file.FullName
        )

        Write-Host "$outputPrefix$percorsoRelativoCompleto..." -NoNewline

        if ($isImage) {
            $cmdArgs += @(
                "-f", "image2", 
                "-y", $fileTemporaneo
            )
            $conversionOutput = & $ffmpegPath $cmdArgs 2>&1
        }
        else {
            $cmdArgs += @(
                "--preset", $handbrakePreset,
                "-o", $fileTemporaneo
            )
            $conversionOutput = & $handbrakePath $cmdArgs 2>&1
        }
        # --- ESECUZIONE ---
        # Catturiamo l'output, ma la decisione la prendiamo sul FILE.
        $exitCode = $LASTEXITCODE
        


        # --- CONTROLLO ROBUSTO ---
        # Verifica se il file esiste ED è più grande di 0 byte.
        $fileCreatoCorrettamente = (Test-Path $fileTemporaneo) -and ((Get-Item $fileTemporaneo).Length -gt 0)

        if ($fileCreatoCorrettamente) {
            # CASO SUCCESSO: Il file c'è, quindi ha funzionato. Preserviamo la data di creazione dell'original
            Move-Item -Path $fileTemporaneo -Destination $fileDestinazione -Force
            (Get-Item $fileDestinazione).LastWriteTime = (Get-Item $file.FullName).LastWriteTime
            
            # Se l'exit code era strano, lo segnaliamo ma andiamo avanti lo stesso
            if ($exitCode -ne 0) {
                Write-Host " [OK (Con Warning: Code $exitCode)]" -ForegroundColor Green
            }
            else {
                Write-Host " [OK]" -ForegroundColor Green
            }
        }
        else {
            # CASO FALLIMENTO: Il file non c'è o è vuoto (0 byte)
            Write-Host " [ERRORE REALE]" -ForegroundColor Red
            Write-Host "    Codice Uscita: $exitCode" -ForegroundColor DarkRed
            Write-Host "    Media Converter Output:" -ForegroundColor DarkRed
            $conversionOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
            
            if (Test-Path $fileTemporaneo) { Remove-Item $fileTemporaneo -Force }
        }

    }
    elseif (!$isWatchMode) {
        # impedisce di fare operazioni inutili di copia se stiamo solo controllando la stessa cartella
        Copy-Item -Path $file.FullName -Destination $fileDestinazione -Force
        (Get-Item $fileDestinazione).LastWriteTime = (Get-Item $file.FullName).LastWriteTime
        Write-Host "$outputPrefix$percorsoRelativoCompleto -> [COPIA]" -ForegroundColor Gray
    }
    
    $script:currentTempFile = $null
}


# --- CREAZIONE DELLO SNAPSHOT DELLE CARTELLE ---
# Disattivo temporaneamente il readonly per andare a scrivere dentro tutte le cartelle presenti in questo momento.
# Se in futuro verranno aggiunte altre, non saranno presenti nel file (che non si può modificare) e verranno compresse.
if ($isWatchMode) {
    WriteSnapshotFile
}

# Cleanup finale
try { Unregister-Event -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -ErrorAction SilentlyContinue } catch {}
Write-Host "`n--- ELABORAZIONE COMPLETATA ---" -ForegroundColor Green