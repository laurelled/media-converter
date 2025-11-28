<#
.SYNOPSIS
    Script "Basta che funzioni".
    - Ignora il codice di errore se il file viene comunque creato.
    - Logica: Se il file .tmp esiste ed è > 0 byte, è un successo.
#>

# --- CONFIGURAZIONE ---
$cartellaSorgente = ".\FILMATI MACCHINE PER ATTREZZAGGIOO"
$cartellaDestinazione = ".\prova"
# Necessario avere nel PATH le cartelle dei bin di HandBrakeCLI e ffmpeg
$handbrakePath = "HandBrakeCLI"
$ffmpegPath = "ffmpeg"

<#
# --- GESTIONE INTERRUZIONE (CTRL+C) ---
$script:currentTempFile = $null
[Console]::TreatControlCAsInput = $false
$action = {
    Write-Host "`n!!! INTERRUZIONE (CTRL+C) !!!" -ForegroundColor Red
    if ($script:currentTempFile -and (Test-Path $script:currentTempFile)) {
        Remove-Item $script:currentTempFile -Force -ErrorAction SilentlyContinue
        Write-Host "File parziale rimosso." -ForegroundColor Yellow
    }
    Exit
}
Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action $action | Out-Null
#>
<#
function WriteLog {
    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "$Stamp $LogString"
    Write-Host $LogMessage
    Add-content $LogFile -value $LogMessage -Encoding UTF8
}#>

# --- FILTRI ---
$estensioniImmagini = @(".jpg", ".jpeg", ".png", ".bmp", ".tiff")
$estensioniVideo = @(".mp4", ".mov", ".avi", ".mkv", ".m4v", ".wmv", ".flv", ".mts")
$handbrakePreset = "Fast 1080p30"

# --- INIZIO ---
Clear-Host
Write-Host "--- SCRIPT: VERIFICA BASATA SUL FILE REALE ---" -ForegroundColor Cyan
try { & $ffmpegPath -version | Out-Null } catch { Write-Error "FFmpeg non trovato!"; exit }
try { & $handbrakePath --version | Out-Null } catch { Write-Error "FFmpeg non trovato!"; exit }

if (!(Test-Path $cartellaDestinazione)) { New-Item -ItemType Directory -Path $cartellaDestinazione | Out-Null }
$files = Get-ChildItem -Path $cartellaSorgente -Recurse -File

foreach ($file in $files) {
    # 1. Calcoli Percorsi
    $rootLength = (Get-Item $cartellaSorgente).FullName.Length + 1
    $percorsoRelativoCompleto = $file.FullName.Substring($rootLength)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $relativeDirPath = [System.IO.Path]::GetDirectoryName($percorsoRelativoCompleto)
    $targetDir = Join-Path $cartellaDestinazione $relativeDirPath
    
    $newExtension = $file.Extension
    $isImage = $false; $isVideo = $false

    if ($estensioniImmagini -contains $file.Extension.ToLower()) { $newExtension = ".jpg"; $isImage = $true } 
    elseif ($estensioniVideo -contains $file.Extension.ToLower()) { $newExtension = ".mp4"; $isVideo = $true }

    $fileDestinazione = Join-Path $targetDir ($baseName + $newExtension)
    $fileTemporaneo = $fileDestinazione + ".tmp"

    if (!(Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }

    if (Test-Path $fileDestinazione) {
        Write-Host "$(Get-Date) ├── $percorsoRelativoCompleto -> [GIA' ESISTENTE, SKIPPATO]" -ForegroundColor DarkYellow
        continue
    }

    $script:currentTempFile = $fileTemporaneo
    $outputPrefix = "$(Get-Date) ├── "

   
    

    if ($isImage -or $isVideo) {
        $cmdArgs = ""
        $msgType = ""
        $execPath = ""

        if ($isImage) {
            $cmdArgs = @(
                "-i", $file.FullName, # Input File (il percorso con spazi viene quotato correttamente)
                "-f", "image2",
                "-y", $fileTemporaneo # Output File (il percorso con spazi viene quotato correttamente)
            )
            $msgType = "IMMAGINE"
            $execPath = $ffmpegPath
        }
        else {
            $cmdArgs = @(
                "-i", $file.FullName,
                "--preset", $handbrakePreset,
                "-o", $fileTemporaneo
            )
            $msgType = "VIDEO"
            $execPath = $handbrakePath
        }

        Write-Host "$outputPrefix$percorsoRelativoCompleto ($msgType)..." -NoNewline

        # --- ESECUZIONE ---
        # Catturiamo l'output, ma la decisione la prendiamo sul FILE.
        
        $conversionOutput = & $execPath $cmdArgs 2>&1
        $exitCode = $LASTEXITCODE

        # --- CONTROLLO ROBUSTO (FILE CHECK) ---
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
            Write-Host "    FFmpeg Output (ultime 5 righe):" -ForegroundColor DarkRed
            $conversionOutput | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
            
            if (Test-Path $fileTemporaneo) { Remove-Item $fileTemporaneo -Force }
        }

    }
    else {
        Copy-Item -Path $file.FullName -Destination $fileDestinazione -Force
        (Get-Item $fileDestinazione).LastWriteTime = (Get-Item $file.FullName).LastWriteTime
        Write-Host "$outputPrefix$percorsoRelativoCompleto -> [COPIA]" -ForegroundColor Gray
    }
    
    $script:currentTempFile = $null
}

# Cleanup finale
try { Unregister-Event -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -ErrorAction SilentlyContinue } catch {}
Write-Host "`n--- ELABORAZIONE COMPLETATA ---" -ForegroundColor Green