# Tugas T0-1: Tabel konfigurasi CIMS (workflow approval, grup departemen, setting, kalender kerja)

Baca CLAUDE.md dan `docs/PRD.md` terlebih dahulu dan ikuti semua aturannya.
Referensi PRD: 3.7, 3.8, 3.9, 3.10, 8.1, BR-37, BR-38, BR-39, BR-50, BR-51, BR-52, BR-58, BR-63, BR-64, BR-65, CF-02, CF-05..CF-08, MD-10, MD-11.

## Ruang lingkup

- **Hanya SQL** (tabel, seed, function, stored procedure) di satu file `Database/Config.sql`.
- **Tidak ada** Model, Service, Controller, View, atau menu pada tahap ini. Tabel dibaca oleh modul T0-2 (otorisasi),
  T2 (Request), T5 (status), dan T7 (Emergency). Pengelolaan isi tabel di MVP lewat script SQL oleh administrator (BR-38).
- Jangan mengubah tabel/SP yang sudah ada (`Customer`, `HierarchyLevel`, `usp_Auth_*`).
- Idempotent: `IF OBJECT_ID(...) IS NULL` untuk tabel, `CREATE OR ALTER` untuk function/SP, seed dengan `MERGE`
  yang **hanya menambah** baris yang belum ada (tidak menimpa perubahan administrator; pola sama dengan `Role.sql`).
- Local time (`SYSDATETIME()`). Jangan menjalankan script SQL.
- Semua tabel punya `CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()`, `CreatedBy NVARCHAR(100) NULL`,
  `UpdatedAt DATETIME2(3) NULL`, `UpdatedBy NVARCHAR(100) NULL` (audit BR-38).

## Kode yang dipakai bersama

| Konsep | Nilai | Catatan |
|---|---|---|
| Company (`CoCode`) | `ABL`, `NKM` | Sama dengan `home..APP_Departments.CoCode` |
| Titik approval (`Point`) | `REQUEST`, `MGMT`, `BAPP` | PRD 3.9 |
| Kategori (`Category`) | `CAPEX`, `OPEX`, `LVE` | NULL = semua kategori |
| Lingkup approver (`Scope`) | `DEPT`, `GROUP`, `PLANT` | PRD 3.9 |
| Revise ke (`ReviseTo`) | `REQUESTER`, `CIVIL` | |
| Role | sesuai `dbo.HierarchyLevel.Role` | `kabag`, `mo`, `gm`, `director`, `fat` |

Gunakan `CHECK` constraint untuk kolom kode di atas.

## 1. dbo.DepartmentGroup dan dbo.DepartmentGroupMember (MD-10, CF-05, BR-51)

- `DepartmentGroup`: `Id INT IDENTITY PK`, `CoCode VARCHAR(10) NOT NULL`, `GroupCode VARCHAR(20) NOT NULL`,
  `GroupName NVARCHAR(100) NOT NULL`, `IsActive BIT NOT NULL DEFAULT 1`, audit. Unique (`CoCode`, `GroupCode`).
- `DepartmentGroupMember`: `GroupId INT NOT NULL` (FK ke DepartmentGroup), `DepartmentID INT NOT NULL`
  (mengacu `home..APP_Departments.DepartmentID`, **tanpa FK lintas database**), audit. PK (`GroupId`, `DepartmentID`).
- Seed (Keputusan PRD 3.9): grup `ABL` / `MILL` / "Mill (lingkup MO)" dengan anggota DepartmentID:
  `19` (C100 PAPER PRODUCTION), `20` (C200 PAPER FINISHING), `18` (D100 TISSUE PRODUCTION),
  `17` (D200 TISSUE CONVERTING), `600` (C600 MANAGER OPERATIONAL), `601` (D600 MANAGER OPERATIONAL).

## 2. dbo.WorkflowStep (PRD 3.9, BR-58)

Kolom: `Id INT IDENTITY PK`, `CoCode VARCHAR(10) NOT NULL`, `Point VARCHAR(10) NOT NULL`, `StepOrder INT NOT NULL`,
`RoleCode VARCHAR(50) NOT NULL`, `Scope VARCHAR(10) NOT NULL`, `Category VARCHAR(10) NULL`,
`DepartmentGroupCode VARCHAR(20) NULL` (NULL = semua departemen), `ReviseTo VARCHAR(10) NULL`
(NULL = tidak bisa Revise; BAPP: "No" = kembali ke Civil), `AllowReject BIT NOT NULL`, `IsActive BIT NOT NULL DEFAULT 1`, audit.
Unique (`CoCode`, `Point`, `StepOrder`).

Seed ABL (Keputusan):

| Point | StepOrder | RoleCode | Scope | Category | DepartmentGroupCode | ReviseTo | AllowReject |
|---|---|---|---|---|---|---|---|
| REQUEST | 1 | kabag | DEPT | NULL | NULL | REQUESTER | 1 |
| REQUEST | 2 | mo | GROUP | NULL | MILL | REQUESTER | 1 |
| MGMT | 1 | gm | PLANT | NULL | NULL | CIVIL | 1 |
| MGMT | 2 | director | PLANT | CAPEX | NULL | CIVIL | 1 |
| BAPP | 1 | kabag | DEPT | NULL | NULL | CIVIL | 0 |
| BAPP | 2 | fat | PLANT | NULL | NULL | CIVIL | 0 |
| BAPP | 3 | gm | PLANT | NULL | NULL | CIVIL | 0 |

Seed NKM (Keputusan):

| Point | StepOrder | RoleCode | Scope | Category | DepartmentGroupCode | ReviseTo | AllowReject |
|---|---|---|---|---|---|---|---|
| REQUEST | 1 | kabag | DEPT | NULL | NULL | REQUESTER | 1 |
| MGMT | 1 | director | PLANT | NULL | NULL | CIVIL | 1 |
| BAPP | 1 | kabag | DEPT | NULL | NULL | CIVIL | 0 |
| BAPP | 2 | fat | PLANT | NULL | NULL | CIVIL | 0 |
| BAPP | 3 | director | PLANT | NULL | NULL | CIVIL | 0 |

## 3. dbo.AppSetting (CF-02, CF-08)

Kolom: `CoCode VARCHAR(10) NOT NULL` (`'*'` = berlaku untuk semua Company), `SettingKey VARCHAR(50) NOT NULL`,
`SettingValue NVARCHAR(200) NOT NULL`, `ValueType VARCHAR(10) NOT NULL` (`INT`, `DECIMAL`, `STRING`),
`Description NVARCHAR(200) NULL`, audit. PK (`CoCode`, `SettingKey`).

Seed (`CoCode = '*'`, Keputusan):

| SettingKey | SettingValue | ValueType | Description |
|---|---|---|---|
| EMERGENCY_FOLLOWUP_WORKDAYS | 3 | INT | Batas approval susulan Emergency, hari kerja (BR-65) |
| SCHEDULE_ONTRACK_MIN_DEV | -5 | DECIMAL | Deviasi progress minimum On Track, poin % (BR-68) |
| SCHEDULE_SLIGHT_MIN_DEV | -15 | DECIMAL | Deviasi minimum Slightly Delay; di bawahnya Delay (BR-68) |
| COST_ONTRACK_MAX_PCT | 100 | DECIMAL | Rasio actual/estimasi maksimum On Track (BR-69) |
| COST_ATRISK_MAX_PCT | 110 | DECIMAL | Rasio maksimum At Risk; di atasnya Over Budget (BR-69) |

SP `dbo.usp_AppSetting_Get(@CoCode VARCHAR(10), @SettingKey VARCHAR(50))`: kembalikan baris Company tersebut;
bila tidak ada, baris `'*'`. 0 baris bila key tidak ada.

## 4. Kalender kerja (MD-11, CF-07, BR-64)

- `dbo.WorkCalendarWeekend`: `CoCode VARCHAR(10)`, `IsoDayOfWeek TINYINT` (1 = Senin ... 7 = Minggu), audit.
  PK (`CoCode`, `IsoDayOfWeek`). Seed: ABL dan NKM masing-masing 6 (Sabtu) dan 7 (Minggu).
- `dbo.WorkCalendarHoliday`: `CoCode VARCHAR(10)`, `HolidayDate DATE`, `Description NVARCHAR(100) NOT NULL`, audit.
  PK (`CoCode`, `HolidayDate`). **Tanpa seed** (tanggal libur diisi administrator per tahun; jangan mengarang tanggal).
- Function `dbo.fn_IsWorkingDay(@CoCode VARCHAR(10), @Date DATE) RETURNS BIT`.
- Function `dbo.fn_WorkingDaysBetween(@CoCode VARCHAR(10), @From DATETIME2, @To DATETIME2) RETURNS INT`:
  jumlah hari kerja **setelah** tanggal @From sampai dengan tanggal @To (tanggal @From tidak dihitung). 0 bila @To <= @From.
- Hitung hari ISO **tanpa bergantung `@@DATEFIRST`/`SET LANGUAGE`**: `(DATEDIFF(DAY, '19000101', @Date) % 7) + 1`
  (1900-01-01 adalah Senin). Hindari loop per hari yang panjang bila mudah dihindari, tetapi correctness lebih penting
  daripada optimasi (rentang realistis < 1 tahun).

## 5. dbo.usp_Workflow_GetSteps (dipakai T2; BR-37, BR-52)

Parameter: `@CoCode VARCHAR(10)`, `@Point VARCHAR(10)`, `@Category VARCHAR(10)`, `@DepartmentID INT`.
Kembalikan langkah aktif yang berlaku, urut `StepOrder`: `Id, StepOrder, RoleCode, Scope, Category,
DepartmentGroupCode, ReviseTo, AllowReject`.
- Kondisi kategori: `Category IS NULL OR Category = @Category`.
- Kondisi grup: `DepartmentGroupCode IS NULL` **atau** @DepartmentID anggota grup aktif dengan `GroupCode` tersebut pada `@CoCode` yang sama.
- Langkah yang kondisinya tidak terpenuhi tidak dikembalikan (BR-52). Snapshot ke request dikerjakan di T2, bukan di sini.

## Test (blok komentar di akhir script, jalankan manual blok per blok)

1. ABL, REQUEST, OPEX, DepartmentID 6 (C500 QC) → hanya `kabag`.
2. ABL, REQUEST, OPEX, DepartmentID 19 (C100) → `kabag`, lalu `mo`.
3. ABL, MGMT, OPEX → `gm` saja. ABL, MGMT, CAPEX → `gm`, lalu `director`.
4. NKM, MGMT, OPEX, DepartmentID 5003 → `director` saja.
5. ABL, BAPP → `kabag`, `fat`, `gm`. NKM, BAPP → `kabag`, `fat`, `director`.
6. `usp_AppSetting_Get 'ABL', 'EMERGENCY_FOLLOWUP_WORKDAYS'` → 3 (dari baris `'*'`).
7. `fn_WorkingDaysBetween('ABL', Jumat, Selasa berikutnya)` → 2 (Senin, Selasa). Tambah satu tanggal libur di hari Senin itu → 1.
8. `fn_IsWorkingDay` memberi hasil sama setelah `SET DATEFIRST 7` dan `SET DATEFIRST 1`.
9. Jalankan ulang seluruh script → tidak error, seed tidak dobel, nilai yang sudah diubah administrator tidak tertimpa.

## Cara kerja

1. Tampilkan rencana singkat (daftar objek SQL) dan tunggu persetujuan saya.
2. Tulis `Database/Config.sql` saja. Berhenti. Saya jalankan di database dev dan menjawab PASS.
3. Setelah PASS: tambahkan ke CLAUDE.md bagian baru **"Konfigurasi (tabel)"** maksimal 8 baris: daftar tabel,
   aturan "nilai bisnis yang bisa berubah wajib dari tabel, bukan hardcode", `usp_Workflow_GetSteps`,
   `fn_WorkingDaysBetween`, dan pengelolaan lewat script SQL oleh administrator.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result, lalu berhenti dan tunggu PASS.
