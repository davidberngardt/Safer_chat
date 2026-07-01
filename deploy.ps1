# deploy-simple.ps1

$ServerIP = "46.17.43.55"
$ProjectPath = "/home/safer_chat"
$FrontendPath = "/var/www/saferchat"
$version = [System.Guid]::NewGuid().ToString().Substring(0, 8)

Write-Host "Deploying version: $version" -ForegroundColor Green

# Фронтенд (если есть)
if (Test-Path ".\build\web") {
    Write-Host "1. Deploying frontend..." -ForegroundColor Yellow
    ssh root@${ServerIP} "rm -rf ${FrontendPath}/*"
    scp -r ".\build\web\*" root@${ServerIP}:${FrontendPath}/
} elseif (Test-Path ".\web") {
    Write-Host "1. Deploying frontend..." -ForegroundColor Yellow
    ssh root@${ServerIP} "rm -rf ${FrontendPath}/*"
    scp -r ".\web\*" root@${ServerIP}:${FrontendPath}/
}

# Бэкенд (ваш оригинальный код с небольшими изменениями)
Write-Host "2. Copying files..." -ForegroundColor Yellow
scp -r .\lib\ root@${ServerIP}:${ProjectPath}/
scp .\pubspec.yaml root@${ServerIP}:${ProjectPath}/
scp .\server.js root@${ServerIP}:${ProjectPath}/

Write-Host "3. Fixing js.context error..." -ForegroundColor Yellow
ssh root@${ServerIP} "cd ${ProjectPath}/lib; sed -i 's/js.context.callMethod/\/\/ js.context.callMethod/g' auth_page.dart"

Write-Host "4. Cleaning cache..." -ForegroundColor Yellow
ssh root@${ServerIP} "cd ${ProjectPath}; rm -rf build/"

Write-Host "5. Installing dependencies..." -ForegroundColor Yellow
ssh root@${ServerIP} "cd ${ProjectPath}; rm -f pubspec.lock; dart pub get"

Write-Host "6. Restarting service..." -ForegroundColor Yellow
ssh root@${ServerIP} "cd ${ProjectPath}; echo '$version' > version.txt; pm2 restart saferchat"

Write-Host "`nDeployment completed! Version: $version" -ForegroundColor Green
Write-Host "Check: https://saferchat.me" -ForegroundColor Cyan