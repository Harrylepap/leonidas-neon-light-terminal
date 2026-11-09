@echo off
rem Leonidas - Neon Light : installation en double-clic
rem Installe Starship, eza et la police Nerd Font (winget), puis le style complet.
rem Chaque fichier modifie est sauvegarde avant (.bak-<date>).
echo.
echo   Leonidas - Neon Light : installation du style de terminal
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -InstallTools
echo.
echo   Termine. Ouvrez un nouvel onglet Windows Terminal.
echo   Pensez a choisir la police "JetBrainsMono Nerd Font" dans les parametres de Windows Terminal.
echo.
pause
