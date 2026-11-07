@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
echo Building Ekk0h.exe and Ekk0h.scr ...
echo.

set "CSC=%windir%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%windir%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo Could not find the .NET Framework C# compiler. Install/enable .NET Framework 4.x and try again.
    pause
    exit /b 1
)

for %%i in ("%CSC%") do set "WPFDIR=%%~dpiWPF"
set "SMA="
for /f "delims=" %%i in ('dir /b /s "%windir%\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\System.Management.Automation.dll" 2^>nul') do set "SMA=%%i"
if not defined SMA for /f "delims=" %%i in ('dir /b /s "%windir%\assembly\GAC_MSIL\System.Management.Automation\System.Management.Automation.dll" 2^>nul') do set "SMA=%%i"
if not defined SMA if exist "%ProgramFiles(x86)%\Reference Assemblies\Microsoft\WindowsPowerShell\3.0\System.Management.Automation.dll" set "SMA=%ProgramFiles(x86)%\Reference Assemblies\Microsoft\WindowsPowerShell\3.0\System.Management.Automation.dll"
if not defined SMA (
    echo Could not find System.Management.Automation.dll ^(Windows PowerShell 5.1 is required^).
    pause
    exit /b 1
)

set "ICON="
if exist "ControlCenter.ico" set "ICON=/win32icon:ControlCenter.ico"

"%CSC%" /nologo /target:winexe /platform:anycpu /optimize+ /out:Ekk0h.scr %ICON% /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /lib:"%WPFDIR%" /reference:System.Web.Extensions.dll /reference:WindowsFormsIntegration.dll /reference:PresentationCore.dll /reference:PresentationFramework.dll /reference:WindowsBase.dll /reference:System.Xaml.dll ScreenSaver.cs ThemeSaver.cs WpfView.cs
if errorlevel 1 (
    echo.
    echo The screen saver failed to build. See the messages above.
    pause
    exit /b 1
)

set "RES="
if /i "%~1"=="embed" set "RES=/resource:Ekk0h.ps1,Ekk0h.ps1 /resource:Ekk0h.scr,Ekk0h.scr"
"%CSC%" /nologo /target:winexe /platform:anycpu /optimize+ /out:Ekk0h.exe %ICON% %RES% /reference:"%SMA%" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll Launcher.cs
if errorlevel 1 (
    echo.
    echo Build failed. See the messages above.
    pause
    exit /b 1
)

echo.
if defined RES (echo Done: Ekk0h.exe is ready. It is the whole program, with the script and screen saver built in.) else (echo Done: Ekk0h.exe is ready. It loads Ekk0h.ps1 from its own folder.)
echo Close the old Ekk0h first (tray icon, then Exit), then double-click Ekk0h.exe.
echo Its packs, settings and tools are kept in the folder it runs from.
pause
