# Starts the local MySQL dev server for eduTrack.
# MySQL is not registered as a Windows service in this environment (no admin
# rights when it was set up), so it must be started manually per session.
#
# Usage:  powershell -File scripts\start-mysql.ps1

$mysqld = "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysqld.exe"
$config = "C:\devtools\mysql-config\my.ini"

if (Get-NetTCPConnection -LocalPort 3307 -ErrorAction SilentlyContinue) {
    Write-Output "MySQL already listening on port 3307."
    exit 0
}

Start-Process -FilePath $mysqld -ArgumentList "--defaults-file=`"$config`"" -WindowStyle Hidden
Start-Sleep -Seconds 5

if (Get-NetTCPConnection -LocalPort 3307 -ErrorAction SilentlyContinue) {
    Write-Output "MySQL started on 127.0.0.1:3307."
} else {
    Write-Output "MySQL did not start - check C:\devtools\mysql-data\*.err for details."
}
