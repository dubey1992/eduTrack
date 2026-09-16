# Starts the local PostgreSQL dev server for eduTrack.
#
# Like MySQL in this environment, PostgreSQL is not registered as a Windows
# service (no admin rights), so it must be started manually per session.
# Installed as plain binaries rather than through the EDB installer for the
# same reason.
#
# Port 5433, not the default 5432, so a stock PostgreSQL installed later
# cannot collide with this one - the same reasoning that puts MySQL on 3307.
#
# Usage:  powershell -File scripts\start-postgres.ps1

$bin   = "C:\devtools\pgsql\bin"
$pgCtl = "$bin\pg_ctl.exe"
$data  = "C:\devtools\pgsql-data"
$log   = "C:\devtools\pgsql-data\server.log"

if (Get-NetTCPConnection -LocalPort 5433 -ErrorAction SilentlyContinue) {
    Write-Output "PostgreSQL already listening on port 5433."
    exit 0
}

# The bin directory must be on PATH, not merely referenced by full path. This
# is a plain binaries install with no installer to register anything, and the
# postmaster spawns a fresh process per connection; without this those
# children cannot resolve the OpenSSL and ICU DLLs beside them and die with
# 0xC0000142 (STATUS_DLL_INIT_FAILED) the moment anything connects. The server
# itself starts fine, which makes it look like a client problem.
$env:Path = "$bin;$env:Path"

# Start-Process rather than pg_ctl, matching start-mysql.ps1. pg_ctl holds on
# to the console it was launched from, so the server dies with whatever shell
# started it - fine interactively, not fine when that shell is a script or a
# background task.
Start-Process -FilePath "$bin\postgres.exe" `
              -ArgumentList "-D", "`"$data`"" `
              -RedirectStandardError $log `
              -WindowStyle Hidden
Start-Sleep -Seconds 5

if (Get-NetTCPConnection -LocalPort 5433 -ErrorAction SilentlyContinue) {
    Write-Output "PostgreSQL started on 127.0.0.1:5433."
} else {
    Write-Output "PostgreSQL did not start - check $log for details."
}
