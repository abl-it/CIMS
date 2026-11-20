<#
  Build-Publish.ps1  -  Membuat script publish database CIMS ke production.

  Hasil (UTF-8 dengan BOM):
    Database/Deploy/CIMS-Publish.sql   (folder bukan "Publish": .gitignore VS mengabaikan publish/)
      Bagian 1  Skema  : seluruh Database/*.sql (tabel, function, stored procedure) dengan urutan run-order
                         (docs/dev/01-Flow-Diagram.md bagian 7; Task.sql dipindah setelah RequestSurvey.sql karena
                         fn_User_Tasks memakai fn_WeekStart dan fn_User_CanFillSurvey). Semua file idempotent.
      Bagian 2  Data   : isi master data + konfigurasi diambil dari DB sumber (DEV) saat script ini dijalankan:
                         HierarchyLevel, WorkflowStep, DepartmentGroup, DepartmentGroupMember, AppSetting,
                         WorkCalendarWeekend, WorkCalendarHoliday, Customer, Location, AttachmentType,
                         AssessmentQuestion, SurveyTemplateItem, SubCategory, Unit.
                         Vendor TIDAK disertakan (tabel dibuat kosong).
                         Isi tabel di target DIGANTI sama persis dengan sumber (Id dipertahankan) hanya bila
                         target belum punya transaksi (dbo.ProjectRequest kosong); bila sudah ada transaksi,
                         bagian data dilewati (PRINT) sehingga skema tetap aman dijalankan ulang.

  Pemakaian (di PC developer, akses baca ke DB DEV):
    powershell -ExecutionPolicy Bypass -File Database\Deploy\Build-Publish.ps1
    powershell -ExecutionPolicy Bypass -File Database\Deploy\Build-Publish.ps1 -Server "ABL-ITD\SQL_DEV" -Database CIMS

  Script ini hanya MEMBACA DB sumber. Script hasil dijalankan oleh DBA/administrator di production
  (SSMS atau sqlcmd), Claude Code tidak menjalankannya ke production.
#>
param(
    [string]$Server   = "ABL-ITD\SQL_DEV",
    [string]$Database = "CIMS",
    [string]$OutFile  = ""
)

$ErrorActionPreference = "Stop"
$dbDir   = Split-Path -Parent $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path $PSScriptRoot "CIMS-Publish.sql" }
$utf8Bom = New-Object System.Text.UTF8Encoding $true
$inv     = [System.Globalization.CultureInfo]::InvariantCulture

# Urutan file skema (docs/dev/01-Flow-Diagram.md bagian 7; Task.sql setelah RequestSurvey.sql: inline function
# fn_User_Tasks butuh fn_WeekStart dan fn_User_CanFillSurvey saat dibuat). FixTextEncoding.sql tidak disertakan
# (hanya perbaikan data lama di DEV).
$schemaFiles = @(
    "Role.sql", "Auth.sql", "Config.sql", "AppSetting.sql", "Scope.sql",
    "Customer.sql", "Location.sql", "AttachmentType.sql", "AssessmentQuestion.sql",
    "SurveyTemplateItem.sql", "SubCategory.sql", "Unit.sql", "Vendor.sql",
    "Request.sql", "RequestSubmit.sql", "RequestApproval.sql",
    "RequestFeasibility.sql", "RequestDocPrep.sql", "RequestExecution.sql",
    "RequestSchedule.sql", "RequestProgress.sql", "RequestActualCost.sql",
    "RequestActualUpload.sql", "RequestMigration.sql", "RequestAddendum.sql",
    "RequestBapp.sql", "RequestSurvey.sql", "Task.sql", "Dashboard.sql", "DashboardChart.sql"
)

# Tabel data: urutan insert (parent dulu). Hapus dengan urutan terbalik.
# Key = kolom identitas/kunci untuk ORDER BY agar hasil deterministik.
$dataTables = @(
    @{ Name = "HierarchyLevel";        Order = "HierarchyLevel, Role" },
    @{ Name = "DepartmentGroup";       Order = "Id" },
    @{ Name = "DepartmentGroupMember"; Order = "GroupId, DepartmentID" },
    @{ Name = "WorkflowStep";          Order = "Id" },
    @{ Name = "AppSetting";            Order = "CoCode, SettingKey" },
    @{ Name = "WorkCalendarWeekend";   Order = "CoCode, IsoDayOfWeek" },
    @{ Name = "WorkCalendarHoliday";   Order = "CoCode, HolidayDate" },
    @{ Name = "Customer";              Order = "Id" },
    @{ Name = "Location";              Order = "Id" },
    @{ Name = "AttachmentType";        Order = "Id" },
    @{ Name = "AssessmentQuestion";    Order = "Id" },
    @{ Name = "SurveyTemplateItem";    Order = "Id" },
    @{ Name = "SubCategory";           Order = "Id" },
    @{ Name = "Unit";                  Order = "Id" }
)

function Format-SqlLiteral($value, [string]$sqlType) {
    if ($null -eq $value -or $value -is [System.DBNull]) { return "NULL" }
    switch ($sqlType) {
        "bit"       { if ($value) { return "1" } else { return "0" } }
        "date"      { return "'" + ([datetime]$value).ToString("yyyy-MM-dd", $inv) + "'" }
        "datetime"  { return "'" + ([datetime]$value).ToString("yyyy-MM-ddTHH:mm:ss.fff", $inv) + "'" }
        "datetime2" { return "'" + ([datetime]$value).ToString("yyyy-MM-ddTHH:mm:ss.fffffff", $inv) + "'" }
        { $_ -in "int","bigint","smallint","tinyint","decimal","numeric","money","float","real" } {
            return ([System.IFormattable]$value).ToString($null, $inv)
        }
        { $_ -in "varchar","char" } { return "'" + ([string]$value).Replace("'", "''") + "'" }
        default     { return "N'" + ([string]$value).Replace("'", "''") + "'" }
    }
}

$conn = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True")
$conn.Open()

function Invoke-Query([string]$sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql
    $da  = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt  = New-Object System.Data.DataTable
    [void]$da.Fill($dt)
    return ,$dt
}

$sb = New-Object System.Text.StringBuilder
$now = (Get-Date).ToString("yyyy-MM-dd HH:mm", $inv)
$gitRev = ""
try { $gitRev = (git -C $dbDir rev-parse --short HEAD 2>$null) } catch { }

[void]$sb.AppendLine(@"
/* =====================================================================
   CIMS-Publish.sql  -  Publish database CIMS ke PRODUCTION (skema + master data + hierarchy + workflow)
   Dibuat  : $now oleh Database/Deploy/Build-Publish.ps1 (git $gitRev)
   Sumber  : skema dari file .sql di folder Database; data dari [$Server].[$Database]
   Target  : Microsoft SQL Server 2016 SP1+, compatibility level >= 130 (STRING_SPLIT, OPENJSON).

   PRASYARAT di server production:
     1. Database CIMS sudah dibuat (kosong) oleh DBA; jalankan script ini dengan database tersebut aktif
        (SSMS: pilih database di dropdown, atau sqlcmd -d <NamaDB>).
     2. Database [home] (portal: home..users, home..APP_Departments, home..APP_Holidays) ada di instance yang
        sama dan bisa dibaca oleh login aplikasi. DepartmentID di DepartmentGroupMember mengikuti
        home..APP_Departments production (cek sama dengan DEV).
     3. File ini UTF-8 dengan BOM. Jalankan apa adanya (jangan disimpan ulang sebagai ANSI).

   Cara menjalankan:
     sqlcmd -S <server\instance> -d <NamaDB> -E -C -b -i CIMS-Publish.sql -o CIMS-Publish.log
     atau buka di SSMS lalu Execute (F5). Periksa pesan: harus selesai dengan "CIMS publish: SELESAI".

   Isi:
     Bagian 1  Skema (idempotent)          - tabel, function, stored procedure, seed bawaan.
     Bagian 2  Data dari DEV               - isi tabel DIGANTI sama dengan DEV (Id dipertahankan), hanya bila
                                             dbo.ProjectRequest masih kosong. Vendor tidak disertakan.
     Aman dijalankan ulang: setelah ada transaksi, bagian data dilewati otomatis.
   ===================================================================== */
-- Opsi sesi seperti SSMS (sqlcmd default QUOTED_IDENTIFIER OFF; SP/index menyimpan opsi saat dibuat)
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
DECLARE @CurDb sysname = DB_NAME();
IF @CurDb IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    RAISERROR(N'CIMS publish: database aktif adalah database sistem (%s). Pilih database CIMS lalu jalankan ulang.', 16, 1, @CurDb) WITH NOWAIT;
    SET NOEXEC ON;
END
ELSE IF (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()) < 130
BEGIN
    RAISERROR(N'CIMS publish: compatibility level database harus >= 130.', 16, 1) WITH NOWAIT;
    SET NOEXEC ON;
END
ELSE IF DB_ID(N'home') IS NULL
BEGIN
    RAISERROR(N'CIMS publish: database [home] tidak ditemukan di instance ini.', 16, 1) WITH NOWAIT;
    SET NOEXEC ON;
END
GO
PRINT N'CIMS publish: mulai di database ' + DB_NAME() + N' (' + CONVERT(nvarchar(19), GETDATE(), 120) + N')';
GO
"@)

# ---------------- Bagian 1: skema ----------------
foreach ($pass in 1) { Write-Host "schema"
    [void]$sb.AppendLine("/* =====================================================================")
    [void]$sb.AppendLine("   BAGIAN 1 - SKEMA")
    [void]$sb.AppendLine("   ===================================================================== */")
    foreach ($f in $schemaFiles) {
        $path = Join-Path $dbDir $f
        if (-not (Test-Path $path)) { throw "File tidak ditemukan: $path" }
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        [void]$sb.AppendLine("/* ---------- begin $f ---------- */")
        [void]$sb.AppendLine("PRINT N'[skema] $f';")
        [void]$sb.AppendLine("GO")
        [void]$sb.AppendLine($text.TrimEnd())
        [void]$sb.AppendLine("GO")
        [void]$sb.AppendLine("/* ---------- end $f ---------- */")
    }
}

# ---------------- Bagian 2: data ----------------
[void]$sb.AppendLine(@"
/* =====================================================================
   BAGIAN 2 - DATA MASTER + HIERARCHY + WORKFLOW (sumber: [$Server].[$Database], $now)
   Satu batch, satu transaksi: gagal di tengah = rollback seluruh data.
   ===================================================================== */
SET XACT_ABORT ON;
IF EXISTS (SELECT 1 FROM dbo.ProjectRequest)
BEGIN
    PRINT N'CIMS publish: dbo.ProjectRequest sudah berisi transaksi, BAGIAN 2 (data) DILEWATI.';
END
ELSE
BEGIN
    BEGIN TRANSACTION;
"@)

# Hapus isi lama (seed bawaan) dengan urutan terbalik
for ($i = $dataTables.Count - 1; $i -ge 0; $i--) {
    [void]$sb.AppendLine("    DELETE FROM dbo.$($dataTables[$i].Name);")
}
[void]$sb.AppendLine("")

$warnings = @()
foreach ($t in $dataTables) {
    $name = $t.Name; Write-Host "data: $name"
    $cols = Invoke-Query @"
SELECT c.name AS ColName, ty.name AS TypeName, c.is_identity AS IsIdentity
FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'dbo.$name') AND c.is_computed = 0
ORDER BY c.column_id
"@
    if ($cols.Rows.Count -eq 0) { throw "Tabel dbo.$name tidak ditemukan di sumber." }
    $colList  = ($cols.Rows | ForEach-Object { "[" + $_.ColName + "]" }) -join ", "
    $hasIdent = @($cols.Rows | Where-Object { $_.IsIdentity }).Count -gt 0
    $rows     = Invoke-Query "SELECT $colList FROM dbo.[$name] ORDER BY $($t.Order)"

    [void]$sb.AppendLine("    -- dbo.$name ($($rows.Rows.Count) baris)")
    if ($rows.Rows.Count -gt 0) {
        if ($hasIdent) { [void]$sb.AppendLine("    SET IDENTITY_INSERT dbo.$name ON;") }
        [void]$sb.AppendLine("    INSERT INTO dbo.$name ($colList) VALUES")
        $lines = @()
        foreach ($r in $rows.Rows) {
            $vals = @()
            foreach ($c in $cols.Rows) {
                $v = $r[$c.ColName]
                if ($v -is [string] -and ($v.Contains([string][char]0xC2) -or $v.Contains([string][char]0xE2 + [char]0x20AC))) {
                    $warnings += "dbo.$name kolom $($c.ColName): teks kemungkinan rusak encoding -> '$v'"
                }
                $vals += Format-SqlLiteral $v $c.TypeName
            }
            $lines += "        (" + ($vals -join ", ") + ")"
        }
        [void]$sb.AppendLine(($lines -join ",`r`n") + ";")
        if ($hasIdent) {
            [void]$sb.AppendLine("    SET IDENTITY_INSERT dbo.$name OFF;")
        }
    }
    if ($hasIdent) {
        # Seed identitas: lanjut dari Id terbesar (atau mulai 1 bila kosong)
        [void]$sb.AppendLine("    IF EXISTS (SELECT 1 FROM dbo.$name) BEGIN DECLARE @Max_$name int = (SELECT MAX(Id) FROM dbo.$name); DBCC CHECKIDENT ('dbo.$name', RESEED, @Max_$name) WITH NO_INFOMSGS; END")
        [void]$sb.AppendLine("    ELSE DBCC CHECKIDENT ('dbo.$name', RESEED, 0) WITH NO_INFOMSGS;")
    }
    [void]$sb.AppendLine("")
}

[void]$sb.AppendLine(@"
    COMMIT TRANSACTION;
    PRINT N'CIMS publish: BAGIAN 2 (data) selesai.';
END
GO
PRINT N'CIMS publish: SELESAI (' + CONVERT(nvarchar(19), GETDATE(), 120) + N')';
GO
SET NOEXEC OFF;
GO
"@)

$conn.Close()

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), $utf8Bom)
Write-Host "Ditulis: $OutFile"
foreach ($w in $warnings) { Write-Warning $w }
