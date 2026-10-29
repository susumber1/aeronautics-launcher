$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$rootDir = $PSScriptRoot
$java = Join-Path $rootDir 'runtime\windows\bin\javaw.exe'
try {
  $addressFile = Join-Path $rootDir 'server-address.txt'
  if (-not (Test-Path -LiteralPath $addressFile) -or -not ([IO.File]::ReadAllText($addressFile)).Trim()) {
    $serverAddress = Read-Host 'Впиши актуальный адрес сервера от владельца (например, bore.pub:12345)'
    [IO.File]::WriteAllText($addressFile, $serverAddress.Trim() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
  }
  if (-not (Test-Path -LiteralPath $java)) {
    Write-Host 'Первый запуск: загрузка Java 21 (~50 МБ)...'
    $runtime = Join-Path $rootDir 'runtime'
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null
    $temp = Join-Path $runtime ('install-' + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
      $zip = Join-Path $temp 'java.zip'
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip' -OutFile $zip
      if ((Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant() -ne 'd35f31e712f0fcf6ac5a093edc90204fbff22f720ba3950bd09d331d5e621636') { throw 'Ошибка проверки Java; установка отменена.' }
      $unpacked = Join-Path $temp 'unpacked'
      Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
      $dir = Get-ChildItem -LiteralPath $unpacked -Directory | Select-Object -First 1
      if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'bin\javaw.exe'))) { throw 'Java не найдена в архиве.' }
      Move-Item -LiteralPath $dir.FullName -Destination (Join-Path $runtime 'windows')
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
  }
  $env:HMCL_USER_HOME = Join-Path $rootDir 'hmcl-home'
  $env:HMCL_LOCAL_HOME = Join-Path $rootDir '.hmcl'
  $consoleJava = Join-Path $rootDir 'runtime\windows\bin\java.exe'
  $setupClasspath = (Join-Path $rootDir 'AeronauticsSetup.jar') + ';' + (Join-Path $rootDir 'HMCL.jar')
  & $consoleJava -cp $setupClasspath AeronauticsSetup $rootDir
  if ($LASTEXITCODE -ne 0) { throw 'Не удалось настроить подключение. Проверьте server-address.txt.' }
  Start-Process -FilePath $java -WorkingDirectory $rootDir -ArgumentList @('-Dhmcl.offline.auth.restricted=false', '-jar', ('"' + (Join-Path $rootDir 'HMCL.jar') + '"'))
} catch { Write-Host $_ -ForegroundColor Red; Read-Host 'Нажмите Enter для выхода'; exit 1 }
