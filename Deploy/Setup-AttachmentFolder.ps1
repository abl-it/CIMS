<#
  Setup-AttachmentFolder.ps1  -  Membuat folder lampiran CIMS dan memberi hak akses ke application pool IIS.

  Folder = nilai FileStorage:RealizationAttachmentsPath di appsettings (default D:\APP_DATA\CIMSAttachments).
  Hak    : IIS AppPool\<AppPool> mendapat Modify (baca, tulis, hapus) pada folder, subfolder, dan file
           (OI)(CI), lewat inheritance. Hak lain yang sudah ada tidak diubah.

  Jalankan di SERVER IIS sebagai Administrator (PowerShell "Run as administrator"):
    powershell -ExecutionPolicy Bypass -File Setup-AttachmentFolder.ps1
    powershell -ExecutionPolicy Bypass -File Setup-AttachmentFolder.ps1 -Path "E:\APP_DATA\CIMSAttachments" -AppPool cims
    powershell -ExecutionPolicy Bypass -File Setup-AttachmentFolder.ps1 -DryRun   # hanya cek, tanpa perubahan

  Aman dijalankan ulang (folder yang sudah ada dipakai; hak yang sama tidak digandakan).
#>
param(
    [string]$Path    = "D:\APP_DATA\CIMSAttachments",
    [string]$AppPool = "cims",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$identity = "IIS AppPool\$AppPool"

function Write-Step([string]$msg) { Write-Host "[CIMS] $msg" }

# 1. Harus Administrator (kecuali DryRun)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $DryRun) {
    throw "Jalankan PowerShell sebagai Administrator."
}

# 2. Application pool harus ada (identitas IIS AppPool\<nama> hanya dikenal bila pool ada)
$appcmd = Join-Path $env:windir "System32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    if ($isAdmin) {
        $pool = & $appcmd list apppool "/name:$AppPool" 2>$null
        if (-not $pool) { throw "Application pool '$AppPool' tidak ditemukan di IIS. Buat dulu pool tersebut." }
        Write-Step "Application pool ditemukan: $pool"
    } else {
        Write-Step "Lewati cek application pool (bukan Administrator)."
    }
} else {
    throw "IIS (appcmd.exe) tidak ditemukan di server ini."
}

# 3. Folder
if (Test-Path -LiteralPath $Path -PathType Container) {
    Write-Step "Folder sudah ada: $Path"
} elseif ($DryRun) {
    Write-Step "[DryRun] Folder akan dibuat: $Path"
} else {
    New-Item -ItemType Directory -Path $Path | Out-Null
    Write-Step "Folder dibuat: $Path"
}

# 4. Hak akses Modify untuk identitas app pool
if ($DryRun) {
    Write-Step "[DryRun] Akan dijalankan: icacls `"$Path`" /grant `"${identity}:(OI)(CI)M`""
} else {
    & icacls $Path /grant "${identity}:(OI)(CI)M" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "icacls gagal (exit $LASTEXITCODE)." }
    Write-Step "Hak Modify diberikan ke $identity"
}

# 5. Tampilkan ACL akhir
if (Test-Path -LiteralPath $Path) {
    Write-Step "ACL saat ini:"
    & icacls $Path | Out-Host
}

# 6. Uji tulis sebagai identitas pool tidak bisa dari sini; uji lewat aplikasi (upload lampiran Actual Cost).
Write-Step "Selesai. Pastikan appsettings production: FileStorage:RealizationAttachmentsPath = $Path"
