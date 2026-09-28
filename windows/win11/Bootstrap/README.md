**WIN11 LTSC Pre Setup**: 
- winget will not be available, but its needed for the bootstrap script. since the microsoft store is also
not available go to the official repo https://github.com/microsoft/winget-cli/releases
and get the latest Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle file. cd into your download folder
(or the folder its in) and run *Add-AppxPackage -Path ".\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"*.
restart shell and winget should be available now.
- the script will install tree-sitter which needs c++ buildtools on windows. you need to install it
manually because this is only possible through the gui.
run *winget install --id Microsoft.VisualStudio.BuildTools* start visual studio installer -> build tools ->
change. Under Desktop Development with c++ check all the checkboxes and select install. restart shell and
you should have buildtools available now.


**Normal Windows Pre Setup**:
- the script will install tree-sitter which needs c++ buildtools on windows. you need to install it
manually because this is only possible through the gui.
run *winget install --id Microsoft.VisualStudio.BuildTools* start visual studio installer -> build tools ->
change. Under Desktop Development with c++ check all the checkboxes and select install. restart shell and
you should have buildtools available now.


**Start**:
- open PowerShell **as Administrator** in this folder and run:
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Bootstrap.ps1
```
- logs are written to *logs/*. after the script finished, open a new terminal (a reboot is recommended, e.g. for Docker Desktop).
- the script sets the ExecutionPolicy for the current user to *RemoteSigned*, otherwise the PowerShell profile would not be loaded.
- manual step: import *mf-base/tabliss.json* in the Tabliss addon settings (path is shown at the end of the script).
