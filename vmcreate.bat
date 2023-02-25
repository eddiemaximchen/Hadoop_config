@echo off

REM 設定 Cluster Name
for /f "tokens=1" %%y in ('dir /B ^| findstr "mactohost"') do (
  set CLUSTERNAME=%%y
)

for /f "tokens=3 delims= " %%z in ('type %CLUSTERNAME:~0,2%mactohost ^| more +11 ^| findstr "#"') do (
  set CN=%%z
)

Rem/||(
  判斷 Cluster Name 有沒有設定錯誤
    - %Variable:~0,2% 
      是取變數值的前兩個字
    - GOTO:eof 
      在不定義標籤的情況下將控制傳送到當前批次檔的末端，此時，批次檔會自行退出。
)
if NOT %CLUSTERNAME:~0,2% == %CN% (
  echo "Cluster Name Error !"
  GOTO:eof
)

REM 判斷在當前目錄下是否存在 %CN% (有可能是 d9 或 d8 或是 d*)目錄 
if exist %CN%\ (
  echo "%CN% Folder existed !"
  GOTO:eof
)

REM 設定 VM 可用記憶體範圍
powershell -Command "(Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).sum /8Mb" > max.txt
powershell -Command "(Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).sum /4Mb" > min.txt

set /P MAX=<max.txt
set /P MIN=<min.txt

set RSMMAX='memsize = \"2048\"', 'memsize = \"%MAX%\"'
set RSMMIN='memsize = \"2048\"', 'memsize = \"%MIN%\"'

REM 修改 VM 的 MAC Address 必要設定
set RSADR1='ethernet0.generatedAddressOffset = \"0\"'
set RSADR2='ethernet0.addressType = \"generated\"' , 'ethernet0.addressType = \"static\"'

REM 將 VM 網路模式設為 bridge 橋接模式
set RSTYPE='ethernet0.connectionType = \"nat\"' , 'ethernet0.connectionType = \"bridge\"'

REM 啟動 US2204 虛擬主機
"C:\Program Files (x86)\VMware\VMware Player\vmrun" start "C:\Users\%USERNAME%\CNT.2023.v4.6\US2204_01\US2204.vmx" > nul
timeout /t 60 > nul


Rem/||(
  抓 US2204 虛擬主機的 IP 位址，將命令執行結果重導到 admip.txt 這個檔案中
    - 透過 set /P 將 admip.txt 檔案中第一行的內容，設為 admip 變數的值
    - 檔案中的第二行以下，包含第二行的內容，都會被丟棄
)
"C:\Program Files (x86)\VMware\VMware Player\vmrun" getGuestIPAddress "C:\Users\%USERNAME%\CNT.2023.v4.6\US2204_01\US2204.vmx" > admip.txt
set /P admip=<admip.txt


Rem/||(
  上載 mactohosts 至 US2204 虛擬主機
    - 變數 ERRORLEVEL 為上一行命令執行完後回傳的值 ^(exit code^)，0 代表執行成功。
    - EQU ^(Equal To^)執行數字比較，如果需要字符串比較，使用 == 比較運算符。
    - USERPROFILE 變數為顯示當前使用者的家目錄，例如 : C:\Users\student
)
echo y | pscp -pwfile "passwd_us" ".\%CN%mactohost" bigred@%admip%:/home/bigred/bin/mactohost 2> nul > nul
if %ERRORLEVEL% EQU 0 echo "%CN%mactohost scp ok"

echo y | pscp -pwfile "passwd_us" bigred@%admip%:/home/bigred/.ssh/* C:\Users\%USERNAME%\.ssh\ 2> nul > nul
if %ERRORLEVEL% EQU 0 echo "%admip% .ssh/* scp ok"

del C:\Users\%USERNAME%\.ssh\known_hosts 2> nul
del C:\Users\%USERNAME%\.ssh\known_hosts.old 2> nul

ssh -o "ConnectTimeout=5" -o "StrictHostKeyChecking=no" bigred@%admip% "sudo apt update; sudo apt upgrade -y" > nul 2>nul
if %ERRORLEVEL% EQU 0 echo "System upgrade ok"

"C:\Program Files (x86)\VMware\VMware Player\vmrun" stop "C:\Users\%USERNAME%\CNT.2023.v4.6\US2204_01\US2204.vmx" > nul
timeout /t 60 > nul


Rem/||(
  建立所有 Hadoop Cluster 的 VM
    - SETLOCAL ENABLEDELAYEDEXPANSION 為 啟用變數延遲展開
      - 意思是 變數會在執行時才會展開變成它的值，而不是在解析時就變成值
      - 要延遲展開的變數格式由 %var% 更改為 !var!
    - gc 為 powershell 的命令，用來顯示檔案內容，-replace 參數主要是替換一個文字檔中的字串
    - Out-File 將輸出傳到一個檔案， -Encoding 參數將輸出轉換為指定格式
)
setlocal EnableDelayedExpansion
if exist %CN%mactohost (
  if not exist %CN%\ (
    mkdir %CN% > nul
    if %ERRORLEVEL% EQU 0 (
      for /f "tokens=1-6 delims= " %%a in ('findstr zip %CN%mactohost') do (
        set x=%%~nxe
        set RS='displayName = \"US2204\"', 'displayName = \"!x!\"'
        set y=%%a
        set RSMAC='ethernet0.generatedAddress = \"00:0c:29:.*\"' , 'ethernet0.address = \"00:50:56:ab:!y!\"'

        mkdir %CN%\!x! > nul
        xcopy /E /Y C:\Users\%USERNAME%\CNT.2023.v4.6\US2204_01 %CN%\!x!\ > nul
        powershell -Command "(gc %CN%\!x!\US2204.vmx) -replace "!RS!" -replace "!RSMAC!" -replace "%RSMMAX%" -replace "%RSTYPE%" -replace "%RSADR1%" -replace "%RSADR2%"  | Out-File -Encoding "UTF8" vm.temp"

        del /Q %CN%\!x!\US2204.vmx
        copy /Y vm.temp %CN%\!x!\US2204.vmx > nul
        if !ERRORLEVEL! EQU 0 echo "%CN%\!x!\ (%MAX%) ok"
      )
      del *.txt > nul
      del vm.temp > nul
    )
  )
)