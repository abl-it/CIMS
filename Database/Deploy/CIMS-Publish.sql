/* =====================================================================
   CIMS-Publish.sql  -  Publish database CIMS ke PRODUCTION (skema + master data + hierarchy + workflow)
   Dibuat  : 2026-11-20 09:13 oleh Database/Deploy/Build-Publish.ps1 (git c5ef656)
   Sumber  : skema dari file .sql di folder Database; data dari [ABL-ITD\SQL_DEV].[CIMS]
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
/* =====================================================================
   BAGIAN 1 - SKEMA
   ===================================================================== */
/* ---------- begin Role.sql ---------- */
PRINT N'[skema] Role.sql';
GO
/* =====================================================================
   Role.sql  -  Role user CIMS: tabel hierarki + stored procedure pembaca role
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Prasyarat:
     1) STRING_SPLIT butuh compatibility level >= 130 pada database CIMS. Cek dulu:
          SELECT name, compatibility_level FROM sys.databases WHERE name = DB_NAME();
        Jika < 130, JANGAN ubah database; laporkan.
     2) Login database CIMS punya hak baca ke database [home] (sama seperti Auth.sql).
   Catatan :
     - Role user disimpan di home..users.[Role]: beberapa role dalam satu string, dipisah ';'.
     - HierarchyLevel: angka kecil = jabatan lebih tinggi (dipakai untuk urutan / "role tertinggi").
     - Seed di bawah SEMENTARA (daftar Training, Description NULL); disesuaikan setelah PRD.
       MERGE hanya MENAMBAH role yang belum ada. Baris yang sudah ada TIDAK diubah/dihapus, jadi
       Description atau level yang sudah Anda sesuaikan di tabel tidak tertimpa saat script
       dijalankan ulang. Mengubah role yang sudah ada: UPDATE langsung di dbo.HierarchyLevel.
     - Script ini hanya untuk TAMPILAN role; tidak ada keputusan akses yang memakainya.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.HierarchyLevel
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.HierarchyLevel', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.HierarchyLevel
    (
        [Role]          VARCHAR(50)   NOT NULL,
        HierarchyLevel  INT           NOT NULL,
        Description     NVARCHAR(100) NULL,
        CONSTRAINT PK_HierarchyLevel PRIMARY KEY CLUSTERED ([Role])
    );
END
GO

/* ---------------------------------------------------------------------
   2. SEED sementara (daftar Training). Hanya menambah yang belum ada.
   --------------------------------------------------------------------- */
MERGE dbo.HierarchyLevel AS t
USING (VALUES
        (N'administrator', 1),
        (N'komisaris',     2),
        (N'director',      3),
        (N'gm',            4),
        (N'civil',            5),
        (N'mo',            6),
        (N'kabag',         7),
        (N'plan',          8),
        (N'spv',           9),
        (N'adm',          10),
        (N'emp',          11),
        (N'creator',      12)
      ) AS s ([Role], HierarchyLevel)
   ON t.[Role] = s.[Role]
WHEN NOT MATCHED BY TARGET THEN
    INSERT ([Role], HierarchyLevel, Description)
    VALUES (s.[Role], s.HierarchyLevel, NULL);
GO

/* ---------------------------------------------------------------------
   2b. Role CIMS sesuai PRD 5.1 (T0-2): tambah fat (5) dan purchasing (6) bila belum ada,
       lalu isi Description 12 role CIMS HANYA bila masih NULL (tidak menimpa perubahan administrator).
       plan, spv, emp: role CIMS hanya-lihat (PRD RL-10..RL-12). komisaris dan creator tidak memberi akses CIMS.
   --------------------------------------------------------------------- */
-- dgo (5): Keputusan 18-11-2026, RL-13 (approval BAPP, lingkup sama dengan fat)
MERGE dbo.HierarchyLevel AS t
USING (VALUES (N'fat', 5), (N'purchasing', 6), (N'dgo', 5)) AS s ([Role], HierarchyLevel)
   ON t.[Role] = s.[Role]
WHEN NOT MATCHED BY TARGET THEN
    INSERT ([Role], HierarchyLevel, Description)
    VALUES (s.[Role], s.HierarchyLevel, NULL);
GO

UPDATE h
SET    h.Description = d.Description
FROM   dbo.HierarchyLevel h
       JOIN (VALUES (N'administrator', N'System Administrator'),
                    (N'director',      N'Director'),
                    (N'gm',            N'General Manager'),
                    (N'civil',         N'Civil Department'),
                    (N'fat',           N'Finance, Accounting & Tax'),
                    (N'dgo',           N'DGO'),
                    (N'mo',            N'Manager Operational'),
                    (N'purchasing',    N'Purchasing'),
                    (N'kabag',         N'Department Head'),
                    (N'adm',           N'Department Admin'),
                    (N'plan',          N'Planner'),
                    (N'spv',           N'Supervisor'),
                    (N'emp',           N'Employee')
            ) AS d ([Role], Description) ON d.[Role] = h.[Role]
WHERE  h.Description IS NULL;
GO

/* ---------------------------------------------------------------------
   3. usp_Auth_GetUserRoles
      Memecah home..users.[Role] per ';', trim, JOIN ke dbo.HierarchyLevel.
      Role yang tidak ada di tabel diabaikan; role ganda dihitung sekali.
      Urut HierarchyLevel naik (baris pertama = role tertinggi).
      0 baris = user tidak punya role terdaftar (atau user tidak ada).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetUserRoles
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  h.[Role],
            h.HierarchyLevel,
            h.Description
    FROM    (
                SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
                FROM   home..users u
                       CROSS APPLY STRING_SPLIT(u.[Role], N';') s
                WHERE  u.Username = @Username
                  AND  LTRIM(RTRIM(s.value)) <> N''
            ) x
            JOIN dbo.HierarchyLevel h ON h.[Role] = x.RoleCode
    ORDER BY h.HierarchyLevel, h.[Role];
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: harus 14 baris (12 + fat + purchasing); 12 role CIMS ber-Description; komisaris dan creator NULL
   SELECT [Role], HierarchyLevel, Description FROM dbo.HierarchyLevel ORDER BY HierarchyLevel;

   -- 2) Role user (ganti dengan username yang ada di home..users)
   --    Lihat string mentahnya:
   SELECT Username, [Role] FROM home..users WHERE Username = N'<username>';
   --    Hasil procedure: role terdaftar saja, urut level naik (baris pertama = tertinggi)
   EXEC dbo.usp_Auth_GetUserRoles @Username = N'<username>';

   -- 3) User tanpa role terdaftar / user tidak ada -> 0 baris
   EXEC dbo.usp_Auth_GetUserRoles @Username = N'tidak-ada-xyz';

   -- 4) Ubah tampilan tanpa ubah kode: isi Description satu role, lalu ulangi langkah 2
   --    UPDATE dbo.HierarchyLevel SET Description = N'General Manager' WHERE [Role] = 'gm';

   -- 5) Jalankan ulang script ini: Description pada langkah 4 TIDAK tertimpa (MERGE hanya INSERT).

   -- 6) Jika error "Invalid object name 'STRING_SPLIT'" / compatibility level < 130:
   --    laporkan; jangan ubah database tanpa persetujuan.

   -- 7) SEKALI JALAN (UI berbahasa Inggris, 03-11-2026): ganti Description lama berbahasa Indonesia.
   --    Hanya mengganti nilai seed lama; Description yang sudah diubah administrator ke nilai lain tidak disentuh.
   UPDATE h SET h.Description = d.NewText
   FROM   dbo.HierarchyLevel h
          JOIN (VALUES (N'administrator', N'Administrator Sistem', N'System Administrator'),
                       (N'kabag',         N'Kepala Bagian',        N'Section Head'),
                       (N'adm',           N'Admin Departemen',     N'Department Admin'),
                       (N'emp',           N'Karyawan',             N'Employee')
               ) AS d ([Role], OldText, NewText) ON d.[Role] = h.[Role] AND h.Description = d.OldText;
   ===================================================================== */
GO
/* ---------- end Role.sql ---------- */
/* ---------- begin Auth.sql ---------- */
PRINT N'[skema] Auth.sql';
GO
/* =====================================================================
   Auth.sql  -  Autentikasi SSO: data user dari database portal "home"
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Prasyarat: login database CIMS harus punya hak BACA (SELECT) ke database
              [home]: tabel users, app_employees, APP_Departments (cross-database).
              Script ini TIDAK mengubah hak akses.
   Catatan : PortalRole (home..users.Role) HANYA dimuat, TIDAK dipakai untuk keputusan akses
             apa pun (role CIMS ditentukan di Tahap B).
             Karyawan resign (home..app_employees.ResignDate terisi dan <= waktu lokal sekarang)
             ditolak: 0 baris (BR-31). Karyawan aktif: ResignDate = NULL.
   ===================================================================== */

/* ---------------------------------------------------------------------
   usp_Auth_GetUserByUsername
   Mengembalikan 0 atau 1 baris. 0 baris = user ada di portal tetapi belum
   terdaftar di home..users (aplikasi menampilkan halaman NotAuthorized).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetUserByUsername
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  u.Username,
            e.EmployeeCode,
            e.FullName,
            e.JobTitle,
            e.CoCode,
            e.DepartmentID,
            ad.CoCode AS DeptCoCode,
            ad.DeptName,
            ad.ABRV,
            u.[Role] AS PortalRole
    FROM    home..users u
            JOIN home..app_employees e ON u.EmployeeCode = e.EmployeeCode
            LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
    WHERE   u.Username = @Username
      AND   (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME());
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti username dengan yang ada di home..users)

   -- 1) User valid -> 1 baris
   EXEC dbo.usp_Auth_GetUserByUsername @Username = N'<username-valid>';

   -- 2) User tidak ada -> 0 baris
   EXEC dbo.usp_Auth_GetUserByUsername @Username = N'tidak-ada-xyz';

   -- 2b) Kolom baru: DepartmentID terisi; DeptCoCode sama dengan CoCode (bila berbeda, laporkan)
   --     Resign (uji di DB dev, lalu kembalikan ke NULL):
   --       UPDATE home..app_employees SET ResignDate = DATEADD(DAY, -1, GETDATE()) WHERE EmployeeCode = N'<kode>';
   --       EXEC dbo.usp_Auth_GetUserByUsername @Username = N'<username-karyawan-itu>';   -- 0 baris
   --       UPDATE home..app_employees SET ResignDate = DATEADD(DAY, 1, GETDATE())  WHERE EmployeeCode = N'<kode>';   -- masih 1 baris
   --       UPDATE home..app_employees SET ResignDate = NULL WHERE EmployeeCode = N'<kode>';

   -- 3) Jika error "The server principal ... is not able to access the database 'home'
   --    under the current security context" / permission denied:
   --    login CIMS belum punya hak baca ke database home -> minta DBA
   --    (script ini tidak mengubah hak akses).
   ===================================================================== */
GO
/* ---------- end Auth.sql ---------- */
/* ---------- begin Config.sql ---------- */
PRINT N'[skema] Config.sql';
GO
/* =====================================================================
   Config.sql  -  Tabel konfigurasi CIMS (T0-1)
                  Grup departemen, workflow approval, setting, kalender kerja
   PRD     : 3.7-3.10, 8.1, BR-37, BR-38, BR-39, BR-50..52, BR-58, BR-63..65,
             CF-02, CF-05..CF-08, MD-10, MD-11
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Catatan :
     - Seed memakai MERGE yang hanya MENAMBAH baris yang belum ada (pola Role.sql).
       Nilai yang sudah diubah administrator TIDAK tertimpa saat script dijalankan ulang.
       Mengubah isi: UPDATE/INSERT langsung ke tabel (BR-38, MVP lewat script SQL).
     - DepartmentID mengacu home..APP_Departments.DepartmentID tanpa FK lintas database.
     - Local time (SYSDATETIME()).
     - Hari ISO (1 = Senin ... 7 = Minggu) dihitung dari tanggal, tanpa
       bergantung pada @@DATEFIRST / SET LANGUAGE (1900-01-01 adalah Senin).
   ===================================================================== */

/* ---------------------------------------------------------------------
   1a. TABLE dbo.DepartmentGroup  (MD-10, CF-05, BR-51)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.DepartmentGroup', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DepartmentGroup
    (
        Id         INT IDENTITY(1,1) NOT NULL,
        CoCode     VARCHAR(10)   NOT NULL,
        GroupCode  VARCHAR(20)   NOT NULL,
        GroupName  NVARCHAR(100) NOT NULL,
        IsActive   BIT           NOT NULL CONSTRAINT DF_DepartmentGroup_IsActive  DEFAULT (1),
        CreatedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_DepartmentGroup_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy  NVARCHAR(100) NULL,
        UpdatedAt  DATETIME2(3)  NULL,
        UpdatedBy  NVARCHAR(100) NULL,
        CONSTRAINT PK_DepartmentGroup        PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_DepartmentGroup_Code   UNIQUE (CoCode, GroupCode),
        CONSTRAINT CK_DepartmentGroup_CoCode CHECK (CoCode IN ('ABL', 'NKM'))
    );
END
GO

/* ---------------------------------------------------------------------
   1b. TABLE dbo.DepartmentGroupMember
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.DepartmentGroupMember', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DepartmentGroupMember
    (
        GroupId       INT           NOT NULL,
        DepartmentID  INT           NOT NULL,   -- home..APP_Departments.DepartmentID (tanpa FK)
        CreatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_DepartmentGroupMember_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy     NVARCHAR(100) NULL,
        UpdatedAt     DATETIME2(3)  NULL,
        UpdatedBy     NVARCHAR(100) NULL,
        CONSTRAINT PK_DepartmentGroupMember PRIMARY KEY CLUSTERED (GroupId, DepartmentID),
        CONSTRAINT FK_DepartmentGroupMember_Group FOREIGN KEY (GroupId) REFERENCES dbo.DepartmentGroup (Id)
    );
END
GO

/* ---------------------------------------------------------------------
   2. TABLE dbo.WorkflowStep  (PRD 3.9, BR-58)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.WorkflowStep', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WorkflowStep
    (
        Id                   INT IDENTITY(1,1) NOT NULL,
        CoCode               VARCHAR(10)   NOT NULL,
        [Point]              VARCHAR(10)   NOT NULL,   -- REQUEST | MGMT | BAPP | ADDENDUM
        StepOrder            INT           NOT NULL,
        RoleCode             VARCHAR(50)   NOT NULL,   -- sesuai dbo.HierarchyLevel.Role
        Scope                VARCHAR(10)   NOT NULL,   -- DEPT | GROUP | PLANT
        Category             VARCHAR(10)   NULL,       -- NULL = semua kategori
        DepartmentGroupCode  VARCHAR(20)   NULL,       -- NULL = semua departemen
        ReviseTo             VARCHAR(10)   NULL,       -- NULL = tidak bisa Revise
        AllowReject          BIT           NOT NULL,
        IsActive             BIT           NOT NULL CONSTRAINT DF_WorkflowStep_IsActive  DEFAULT (1),
        CreatedAt            DATETIME2(3)  NOT NULL CONSTRAINT DF_WorkflowStep_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy            NVARCHAR(100) NULL,
        UpdatedAt            DATETIME2(3)  NULL,
        UpdatedBy            NVARCHAR(100) NULL,
        CONSTRAINT PK_WorkflowStep        PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_WorkflowStep_Order  UNIQUE (CoCode, [Point], StepOrder),
        CONSTRAINT CK_WorkflowStep_CoCode   CHECK (CoCode IN ('ABL', 'NKM')),
        CONSTRAINT CK_WorkflowStep_Point    CHECK ([Point] IN ('REQUEST', 'MGMT', 'BAPP', 'ADDENDUM')),   -- ADDENDUM: T4-4 (seed di RequestAddendum.sql)
        CONSTRAINT CK_WorkflowStep_Scope    CHECK (Scope IN ('DEPT', 'GROUP', 'PLANT')),
        CONSTRAINT CK_WorkflowStep_Category CHECK (Category IS NULL OR Category IN ('CAPEX', 'OPEX', 'LVE')),
        CONSTRAINT CK_WorkflowStep_ReviseTo CHECK (ReviseTo IS NULL OR ReviseTo IN ('REQUESTER', 'CIVIL'))
    );
END
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.AppSetting  (CF-02, CF-08)   CoCode '*' = semua Company
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.AppSetting', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AppSetting
    (
        CoCode        VARCHAR(10)   NOT NULL,
        SettingKey    VARCHAR(50)   NOT NULL,
        SettingValue  NVARCHAR(200) NOT NULL,
        ValueType     VARCHAR(10)   NOT NULL,
        Description   NVARCHAR(200) NULL,
        CreatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_AppSetting_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy     NVARCHAR(100) NULL,
        UpdatedAt     DATETIME2(3)  NULL,
        UpdatedBy     NVARCHAR(100) NULL,
        CONSTRAINT PK_AppSetting PRIMARY KEY CLUSTERED (CoCode, SettingKey),
        CONSTRAINT CK_AppSetting_CoCode    CHECK (CoCode IN ('*', 'ABL', 'NKM')),
        CONSTRAINT CK_AppSetting_ValueType CHECK (ValueType IN ('INT', 'DECIMAL', 'STRING'))
    );
END
GO

/* ---------------------------------------------------------------------
   4a. TABLE dbo.WorkCalendarWeekend  (MD-11, CF-07)  1 = Senin ... 7 = Minggu
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.WorkCalendarWeekend', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WorkCalendarWeekend
    (
        CoCode        VARCHAR(10)   NOT NULL,
        IsoDayOfWeek  TINYINT       NOT NULL,
        CreatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_WorkCalendarWeekend_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy     NVARCHAR(100) NULL,
        UpdatedAt     DATETIME2(3)  NULL,
        UpdatedBy     NVARCHAR(100) NULL,
        CONSTRAINT PK_WorkCalendarWeekend PRIMARY KEY CLUSTERED (CoCode, IsoDayOfWeek),
        CONSTRAINT CK_WorkCalendarWeekend_CoCode CHECK (CoCode IN ('ABL', 'NKM')),
        CONSTRAINT CK_WorkCalendarWeekend_Day    CHECK (IsoDayOfWeek BETWEEN 1 AND 7)
    );
END
GO

/* ---------------------------------------------------------------------
   4b. TABLE dbo.WorkCalendarHoliday  (MD-11, CF-07)  tanpa seed
       Libur TAMBAHAN per Company. Libur umum diambil dari home..APP_Holidays
       (milik portal, berlaku semua Company); keduanya digabung di fungsi hari kerja.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.WorkCalendarHoliday', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WorkCalendarHoliday
    (
        CoCode       VARCHAR(10)   NOT NULL,
        HolidayDate  DATE          NOT NULL,
        Description  NVARCHAR(100) NOT NULL,
        CreatedAt    DATETIME2(3)  NOT NULL CONSTRAINT DF_WorkCalendarHoliday_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy    NVARCHAR(100) NULL,
        UpdatedAt    DATETIME2(3)  NULL,
        UpdatedBy    NVARCHAR(100) NULL,
        CONSTRAINT PK_WorkCalendarHoliday PRIMARY KEY CLUSTERED (CoCode, HolidayDate),
        CONSTRAINT CK_WorkCalendarHoliday_CoCode CHECK (CoCode IN ('ABL', 'NKM'))
    );
END
GO

/* ---------------------------------------------------------------------
   5. SEED (hanya menambah yang belum ada)
   --------------------------------------------------------------------- */

-- 5a. Grup departemen: ABL / MILL (Keputusan PRD 3.9)
MERGE dbo.DepartmentGroup AS t
USING (VALUES ('ABL', 'MILL', N'Mill (lingkup MO)')) AS s (CoCode, GroupCode, GroupName)
   ON t.CoCode = s.CoCode AND t.GroupCode = s.GroupCode
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CoCode, GroupCode, GroupName, CreatedBy)
    VALUES (s.CoCode, s.GroupCode, s.GroupName, N'seed');
GO

-- 5b. Anggota MILL: C100=19, C200=20, D100=18, D200=17, C600=600, D600=601
MERGE dbo.DepartmentGroupMember AS t
USING (
        SELECT g.Id AS GroupId, v.DepartmentID
        FROM   dbo.DepartmentGroup g
               CROSS JOIN (VALUES (19), (20), (18), (17), (600), (601)) AS v (DepartmentID)
        WHERE  g.CoCode = 'ABL' AND g.GroupCode = 'MILL'
      ) AS s
   ON t.GroupId = s.GroupId AND t.DepartmentID = s.DepartmentID
WHEN NOT MATCHED BY TARGET THEN
    INSERT (GroupId, DepartmentID, CreatedBy)
    VALUES (s.GroupId, s.DepartmentID, N'seed');
GO

-- 5c. Workflow ABL + NKM (Keputusan PRD 3.9)
MERGE dbo.WorkflowStep AS t
USING (VALUES
        ('ABL', 'REQUEST', 1, 'kabag',    'DEPT',  NULL,    NULL,   'REQUESTER', 1),
        ('ABL', 'REQUEST', 2, 'mo',       'GROUP', NULL,    'MILL', 'REQUESTER', 1),
        ('ABL', 'MGMT',    1, 'gm',       'PLANT', NULL,    NULL,   'CIVIL',     1),
        ('ABL', 'MGMT',    2, 'director', 'PLANT', 'CAPEX', NULL,   'CIVIL',     1),
        ('ABL', 'BAPP',    1, 'kabag',    'DEPT',  NULL,    NULL,   'CIVIL',     0),
        ('ABL', 'BAPP',    2, 'fat',      'PLANT', NULL,    NULL,   'CIVIL',     0),
        ('ABL', 'BAPP',    3, 'gm',       'PLANT', NULL,    NULL,   'CIVIL',     0),
        ('NKM', 'REQUEST', 1, 'kabag',    'DEPT',  NULL,    NULL,   'REQUESTER', 1),
        ('NKM', 'MGMT',    1, 'director', 'PLANT', NULL,    NULL,   'CIVIL',     1),
        ('NKM', 'BAPP',    1, 'kabag',    'DEPT',  NULL,    NULL,   'CIVIL',     0),
        ('NKM', 'BAPP',    2, 'fat',      'PLANT', NULL,    NULL,   'CIVIL',     0),
        ('NKM', 'BAPP',    3, 'director', 'PLANT', NULL,    NULL,   'CIVIL',     0)
      ) AS s (CoCode, [Point], StepOrder, RoleCode, Scope, Category, DepartmentGroupCode, ReviseTo, AllowReject)
   ON t.CoCode = s.CoCode AND t.[Point] = s.[Point] AND t.StepOrder = s.StepOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CoCode, [Point], StepOrder, RoleCode, Scope, Category, DepartmentGroupCode, ReviseTo, AllowReject, CreatedBy)
    VALUES (s.CoCode, s.[Point], s.StepOrder, s.RoleCode, s.Scope, s.Category, s.DepartmentGroupCode, s.ReviseTo,
            CAST(s.AllowReject AS BIT), N'seed');
GO

-- 5d. AppSetting (CoCode '*')
MERGE dbo.AppSetting AS t
USING (VALUES
        ('*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'3',   'INT',     N'Emergency follow-up approval limit, working days'),
        ('*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'-5',  'DECIMAL', N'Minimum progress deviation for On Track, % points'),
        ('*', 'SCHEDULE_SLIGHT_MIN_DEV',     N'-15', 'DECIMAL', N'Minimum deviation for Slightly Delay; below it is Delay, % points'),
        ('*', 'COST_ONTRACK_MAX_PCT',        N'100', 'DECIMAL', N'Maximum actual/estimate ratio for On Track, %'),
        ('*', 'COST_ATRISK_MAX_PCT',         N'110', 'DECIMAL', N'Maximum ratio for At Risk; above it is Over Budget, %')
      ) AS s (CoCode, SettingKey, SettingValue, ValueType, Description)
   ON t.CoCode = s.CoCode AND t.SettingKey = s.SettingKey
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CoCode, SettingKey, SettingValue, ValueType, Description, CreatedBy)
    VALUES (s.CoCode, s.SettingKey, s.SettingValue, s.ValueType, s.Description, N'seed');
GO

-- 5e. Hari libur mingguan: hanya Minggu (7); Sabtu hari kerja (Keputusan 03-11-2026)
--     Bila DB dev sudah pernah menjalankan versi lama: DELETE FROM dbo.WorkCalendarWeekend WHERE IsoDayOfWeek = 6;
MERGE dbo.WorkCalendarWeekend AS t
USING (VALUES ('ABL', 7), ('NKM', 7)) AS s (CoCode, IsoDayOfWeek)
   ON t.CoCode = s.CoCode AND t.IsoDayOfWeek = s.IsoDayOfWeek
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CoCode, IsoDayOfWeek, CreatedBy)
    VALUES (s.CoCode, CAST(s.IsoDayOfWeek AS TINYINT), N'seed');
GO

/* ---------------------------------------------------------------------
   6. dbo.fn_IsWorkingDay
      1 = hari kerja; 0 = hari libur mingguan atau tanggal libur (per Company).
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_IsWorkingDay
(
    @CoCode VARCHAR(10),
    @Date   DATE
)
RETURNS BIT
AS
BEGIN
    DECLARE @Iso TINYINT = CAST((DATEDIFF(DAY, '19000101', @Date) % 7) + 1 AS TINYINT);

    IF EXISTS (SELECT 1 FROM dbo.WorkCalendarWeekend WHERE CoCode = @CoCode AND IsoDayOfWeek = @Iso)
        RETURN 0;
    IF EXISTS (SELECT 1 FROM dbo.WorkCalendarHoliday WHERE CoCode = @CoCode AND HolidayDate = @Date)
        RETURN 0;
    -- Libur portal (semua Company); HolidayDate DATETIME -> bandingkan per rentang hari
    IF EXISTS (SELECT 1 FROM home..APP_Holidays
               WHERE  HolidayDate >= @Date AND HolidayDate < DATEADD(DAY, 1, @Date))
        RETURN 0;

    RETURN 1;
END
GO

/* ---------------------------------------------------------------------
   7. dbo.fn_WorkingDaysBetween
      Jumlah hari kerja SETELAH tanggal @From sampai dengan tanggal @To
      (tanggal @From tidak dihitung). 0 bila tanggal @To <= tanggal @From.
      Tanpa loop: total hari - hari libur mingguan (rumus tertutup per hari ISO)
      - tanggal libur yang bukan hari libur mingguan.
      n = jumlah hari sejak 1900-01-01 (Senin = n % 7 = 0); rentang n = [a, b].
      Jumlah n dengan n % 7 = k di [a, b] = (b-k+7)/7 - (a-1-k+7)/7 (pembagian integer).
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_WorkingDaysBetween
(
    @CoCode VARCHAR(10),
    @From   DATETIME2,
    @To     DATETIME2
)
RETURNS INT
AS
BEGIN
    DECLARE @F DATE = CAST(@From AS DATE);
    DECLARE @T DATE = CAST(@To   AS DATE);

    IF @T <= @F RETURN 0;

    DECLARE @a INT = DATEDIFF(DAY, '19000101', @F) + 1;   -- hari pertama (setelah @From)
    DECLARE @b INT = DATEDIFF(DAY, '19000101', @T);       -- hari terakhir
    DECLARE @Total INT = @b - @a + 1;

    DECLARE @Weekend INT =
    (
        SELECT ISNULL(SUM(((@b - (w.IsoDayOfWeek - 1) + 7) / 7) - ((@a - 1 - (w.IsoDayOfWeek - 1) + 7) / 7)), 0)
        FROM   dbo.WorkCalendarWeekend w
        WHERE  w.CoCode = @CoCode
    );

    -- Tanggal libur = gabungan (UNION, tanpa duplikat) libur portal home..APP_Holidays (semua Company)
    -- dan libur tambahan per Company dbo.WorkCalendarHoliday; yang jatuh di hari libur mingguan tidak dihitung lagi.
    DECLARE @Holiday INT =
    (
        SELECT COUNT(*)
        FROM   (
                   SELECT CAST(p.HolidayDate AS DATE) AS HolidayDate
                   FROM   home..APP_Holidays p
                   WHERE  p.HolidayDate >= DATEADD(DAY, 1, @F) AND p.HolidayDate < DATEADD(DAY, 1, @T)
                   UNION
                   SELECT c.HolidayDate
                   FROM   dbo.WorkCalendarHoliday c
                   WHERE  c.CoCode = @CoCode
                     AND  c.HolidayDate > @F AND c.HolidayDate <= @T
               ) h
        WHERE  NOT EXISTS (SELECT 1
                           FROM   dbo.WorkCalendarWeekend w
                           WHERE  w.CoCode = @CoCode
                             AND  w.IsoDayOfWeek = (DATEDIFF(DAY, '19000101', h.HolidayDate) % 7) + 1)
    );

    RETURN @Total - @Weekend - @Holiday;
END
GO

/* ---------------------------------------------------------------------
   8. dbo.usp_AppSetting_Get
      Baris Company tersebut; bila tidak ada, baris '*'. 0 baris bila key tidak ada.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AppSetting_Get
    @CoCode      VARCHAR(10),
    @SettingKey  VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
            CoCode, SettingKey, SettingValue, ValueType, Description
    FROM    dbo.AppSetting
    WHERE   SettingKey = @SettingKey
      AND   CoCode IN (@CoCode, '*')
    ORDER BY CASE WHEN CoCode = @CoCode THEN 0 ELSE 1 END;
END
GO

/* ---------------------------------------------------------------------
   9. dbo.usp_Workflow_GetSteps  (dipakai T2; BR-37, BR-52)
      Langkah aktif yang berlaku, urut StepOrder. Langkah yang kondisinya tidak
      terpenuhi tidak dikembalikan. Snapshot ke request dikerjakan di T2.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Workflow_GetSteps
    @CoCode        VARCHAR(10),
    @Point         VARCHAR(10),
    @Category      VARCHAR(10),
    @DepartmentID  INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  w.Id, w.StepOrder, w.RoleCode, w.Scope, w.Category,
            w.DepartmentGroupCode, w.ReviseTo, w.AllowReject
    FROM    dbo.WorkflowStep w
    WHERE   w.CoCode  = @CoCode
      AND   w.[Point] = @Point
      AND   w.IsActive = 1
      AND   (w.Category IS NULL OR w.Category = @Category)
      AND   (
                w.DepartmentGroupCode IS NULL
                OR EXISTS (SELECT 1
                           FROM   dbo.DepartmentGroup g
                                  JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                           WHERE  g.CoCode    = w.CoCode
                             AND  g.GroupCode = w.DepartmentGroupCode
                             AND  g.IsActive  = 1
                             AND  m.DepartmentID = @DepartmentID)
            )
    ORDER BY w.StepOrder;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 0) Seed: DepartmentGroup 1, Member 6, WorkflowStep 12, AppSetting 5, Weekend 2 (hanya hari 7), Holiday 0
   SELECT * FROM dbo.DepartmentGroup;
   SELECT * FROM dbo.DepartmentGroupMember;
   SELECT * FROM dbo.WorkflowStep ORDER BY CoCode, [Point], StepOrder;
   SELECT * FROM dbo.AppSetting;
   SELECT * FROM dbo.WorkCalendarWeekend;
   SELECT * FROM dbo.WorkCalendarHoliday;

   -- 1) ABL, REQUEST, OPEX, DepartmentID 6 (C500 QC) -> hanya kabag
   EXEC dbo.usp_Workflow_GetSteps 'ABL', 'REQUEST', 'OPEX', 6;

   -- 2) ABL, REQUEST, OPEX, DepartmentID 19 (C100) -> kabag, lalu mo
   EXEC dbo.usp_Workflow_GetSteps 'ABL', 'REQUEST', 'OPEX', 19;

   -- 3) ABL, MGMT, OPEX -> gm saja; ABL, MGMT, CAPEX -> gm, lalu director
   EXEC dbo.usp_Workflow_GetSteps 'ABL', 'MGMT', 'OPEX',  6;
   EXEC dbo.usp_Workflow_GetSteps 'ABL', 'MGMT', 'CAPEX', 6;

   -- 4) NKM, MGMT, OPEX, DepartmentID 5003 -> director saja
   EXEC dbo.usp_Workflow_GetSteps 'NKM', 'MGMT', 'OPEX', 5003;

   -- 5) BAPP: ABL -> kabag, fat, gm ; NKM -> kabag, fat, director
   EXEC dbo.usp_Workflow_GetSteps 'ABL', 'BAPP', 'OPEX', 6;
   EXEC dbo.usp_Workflow_GetSteps 'NKM', 'BAPP', 'OPEX', 5003;

   -- 6) Setting: harus 3 (dari baris '*')
   EXEC dbo.usp_AppSetting_Get 'ABL', 'EMERGENCY_FOLLOWUP_WORKDAYS';
   EXEC dbo.usp_AppSetting_Get 'ABL', 'TIDAK_ADA';   -- 0 baris

   -- 7) Jumat 2026-11-06 -> Selasa 2026-11-10 = 3 (Sabtu, Senin, Selasa; Minggu libur)
   --    Hasil berkurang bila home..APP_Holidays berisi tanggal 07/09/10-11-2026; cek dulu:
   SELECT * FROM home..APP_Holidays WHERE HolidayDate >= '2026-11-07' AND HolidayDate < '2026-11-11';
   SELECT dbo.fn_WorkingDaysBetween('ABL', '2026-11-06', '2026-11-10') AS Hasil;   -- 3
   INSERT dbo.WorkCalendarHoliday (CoCode, HolidayDate, Description) VALUES ('ABL', '2026-11-09', N'Uji');
   SELECT dbo.fn_WorkingDaysBetween('ABL', '2026-11-06', '2026-11-10') AS Hasil;   -- 2
   SELECT dbo.fn_WorkingDaysBetween('NKM', '2026-11-06', '2026-11-10') AS Hasil;   -- 3 (libur ABL saja)
   SELECT dbo.fn_WorkingDaysBetween('ABL', '2026-11-10', '2026-11-06') AS Hasil;   -- 0
   DELETE dbo.WorkCalendarHoliday WHERE CoCode = 'ABL' AND HolidayDate = '2026-11-09';

   -- 8) fn_IsWorkingDay sama pada DATEFIRST berbeda (Jumat=1, Sabtu=1, Senin=1; Minggu 2026-11-08 = 0)
   SET DATEFIRST 7;
   SELECT dbo.fn_IsWorkingDay('ABL', '2026-11-06') AS Jum, dbo.fn_IsWorkingDay('ABL', '2026-11-07') AS Sab,
          dbo.fn_IsWorkingDay('ABL', '2026-11-09') AS Sen;
   SET DATEFIRST 1;
   SELECT dbo.fn_IsWorkingDay('ABL', '2026-11-06') AS Jum, dbo.fn_IsWorkingDay('ABL', '2026-11-07') AS Sab,
          dbo.fn_IsWorkingDay('ABL', '2026-11-09') AS Sen;

   -- 9) Idempotensi: ubah nilai, jalankan ulang seluruh script, nilai TIDAK tertimpa dan jumlah baris sama
   UPDATE dbo.AppSetting SET SettingValue = N'5' WHERE CoCode = '*' AND SettingKey = 'EMERGENCY_FOLLOWUP_WORKDAYS';
   --   (jalankan ulang Config.sql)
   EXEC dbo.usp_AppSetting_Get 'ABL', 'EMERGENCY_FOLLOWUP_WORKDAYS';   -- masih 5
   UPDATE dbo.AppSetting SET SettingValue = N'3' WHERE CoCode = '*' AND SettingKey = 'EMERGENCY_FOLLOWUP_WORKDAYS';   -- kembalikan

   -- 10) Libur portal (home..APP_Holidays, semua Company) + gabungan tanpa duplikat
   --     Ambil satu tanggal libur portal di hari kerja (Senin-Sabtu), mis. @H:
   DECLARE @H DATE = (SELECT TOP (1) CAST(HolidayDate AS DATE) FROM home..APP_Holidays
                      WHERE (DATEDIFF(DAY, '19000101', HolidayDate) % 7) + 1 <> 7 ORDER BY HolidayDate DESC);
   SELECT @H AS LiburPortal,
          dbo.fn_IsWorkingDay('ABL', @H) AS ABL, dbo.fn_IsWorkingDay('NKM', @H) AS NKM;          -- 0, 0
   SELECT dbo.fn_WorkingDaysBetween('ABL', DATEADD(DAY, -1, @H), @H) AS Hasil;                     -- 0
   INSERT dbo.WorkCalendarHoliday (CoCode, HolidayDate, Description) VALUES ('ABL', @H, N'Duplicate test');
   SELECT dbo.fn_WorkingDaysBetween('ABL', DATEADD(DAY, -1, @H), @H) AS Hasil;                     -- tetap 0 (tidak dobel)
   DELETE dbo.WorkCalendarHoliday WHERE CoCode = 'ABL' AND HolidayDate = @H;
   ===================================================================== */
GO
/* ---------- end Config.sql ---------- */
/* ---------- begin AppSetting.sql ---------- */
PRINT N'[skema] AppSetting.sql';
GO
/* =====================================================================
   AppSetting.sql  -  Halaman Settings: ubah NILAI dbo.AppSetting (T1; PRD CF-02, CF-08, BR-65, BR-68, BR-69)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Config.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Tabel dbo.AppSetting dan seed 5 key ada di Config.sql (T0-1). Script ini tidak mengubah struktur tabel.
     - Halaman hanya mengubah SettingValue baris yang sudah ada (oleh administrator, tercatat UpdatedBy/UpdatedAt).
       Menambah/menghapus key atau baris override per Company tetap lewat script SQL (BR-38).
     - Validasi nilai per ValueType (INT / DECIMAL maks. 2 desimal / STRING) dan rentang per key.
       Pasangan ambang diperiksa terhadap nilai efektif pasangannya pada Company yang sama
       (baris Company, fallback '*'):
         SCHEDULE_SLIGHT_MIN_DEV < SCHEDULE_ONTRACK_MIN_DEV
         COST_ONTRACK_MAX_PCT    < COST_ATRISK_MAX_PCT
   Error   : 50052 = Nilai kosong / tidak valid / di luar rentang
             50053 = Setting tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Deskripsi seed lama (bahasa Indonesia) -> bahasa Inggris (UI wajib Inggris).
      Hanya baris yang deskripsinya masih teks seed lama; deskripsi lain tidak disentuh.
   --------------------------------------------------------------------- */
UPDATE t
SET    t.Description = s.NewText
FROM   dbo.AppSetting t
       JOIN (VALUES
            ('EMERGENCY_FOLLOWUP_WORKDAYS', N'Batas approval susulan Emergency, hari kerja (BR-65)',
                                            N'Emergency follow-up approval limit, working days'),
            ('SCHEDULE_ONTRACK_MIN_DEV',    N'Deviasi progress minimum On Track, poin % (BR-68)',
                                            N'Minimum progress deviation for On Track, % points'),
            ('SCHEDULE_SLIGHT_MIN_DEV',     N'Deviasi minimum Slightly Delay; di bawahnya Delay (BR-68)',
                                            N'Minimum deviation for Slightly Delay; below it is Delay, % points'),
            ('COST_ONTRACK_MAX_PCT',        N'Rasio actual/estimasi maksimum On Track (BR-69)',
                                            N'Maximum actual/estimate ratio for On Track, %'),
            ('COST_ATRISK_MAX_PCT',         N'Rasio maksimum At Risk; di atasnya Over Budget (BR-69)',
                                            N'Maximum ratio for At Risk; above it is Over Budget, %')
            ) AS s (SettingKey, OldText, NewText)
         ON t.SettingKey = s.SettingKey AND t.Description = s.OldText;
GO

/* ---------------------------------------------------------------------
   2. usp_AppSetting_List
      Semua baris (jumlah kecil, tanpa paging). Filter Company opsional ('*', ABL, NKM).
      Urutan: key menurut urutan bisnis (batas waktu, jadwal, biaya), lalu '*' sebelum Company.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AppSetting_List
    @CoCode  VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode = NULLIF(LTRIM(RTRIM(@CoCode)), '');

    SELECT  CoCode, SettingKey, SettingValue, ValueType, Description,
            CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM    dbo.AppSetting
    WHERE   (@CoCode IS NULL OR CoCode = @CoCode)
    ORDER BY
            CASE CHARINDEX(',' + SettingKey + ',',
                           ',EMERGENCY_FOLLOWUP_WORKDAYS,SCHEDULE_ONTRACK_MIN_DEV,SCHEDULE_SLIGHT_MIN_DEV,COST_ONTRACK_MAX_PCT,COST_ATRISK_MAX_PCT,')
                 WHEN 0 THEN 9999
                 ELSE CHARINDEX(',' + SettingKey + ',',
                           ',EMERGENCY_FOLLOWUP_WORKDAYS,SCHEDULE_ONTRACK_MIN_DEV,SCHEDULE_SLIGHT_MIN_DEV,COST_ONTRACK_MAX_PCT,COST_ATRISK_MAX_PCT,')
            END,
            SettingKey,
            CASE WHEN CoCode = '*' THEN 0 ELSE 1 END,
            CoCode;
END
GO

/* ---------------------------------------------------------------------
   3. usp_AppSetting_GetByKey  (baris persis, TANPA fallback; untuk halaman Edit)
      Nilai efektif dengan fallback '*' tetap lewat usp_AppSetting_Get (Config.sql).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AppSetting_GetByKey
    @CoCode      VARCHAR(10),
    @SettingKey  VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  CoCode, SettingKey, SettingValue, ValueType, Description,
            CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM    dbo.AppSetting
    WHERE   CoCode = @CoCode AND SettingKey = @SettingKey;
END
GO

/* ---------------------------------------------------------------------
   4. usp_AppSetting_UpdateValue
      Hanya SettingValue (+ audit). ValueType, Description, key tidak berubah.
      Nilai disimpan dalam bentuk normal (INT tanpa nol depan; DECIMAL tanpa nol belakang).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AppSetting_UpdateValue
    @CoCode        VARCHAR(10),
    @SettingKey    VARCHAR(50),
    @SettingValue  NVARCHAR(200),
    @ActionBy      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ValueType VARCHAR(10);
    DECLARE @Num       DECIMAL(18, 6);
    DECLARE @Text      NVARCHAR(200) = LTRIM(RTRIM(@SettingValue));

    SELECT @ValueType = ValueType
    FROM   dbo.AppSetting
    WHERE  CoCode = @CoCode AND SettingKey = @SettingKey;

    IF @ValueType IS NULL
        THROW 50053, N'Setting not found.', 1;

    IF ISNULL(@Text, N'') = N''
        THROW 50052, N'Value is required.', 1;

    /* -- Tipe nilai -- */
    IF @ValueType = 'INT'
    BEGIN
        IF TRY_CONVERT(INT, @Text) IS NULL
            THROW 50052, N'Value must be a whole number.', 1;
        SET @Num  = TRY_CONVERT(INT, @Text);
        SET @Text = CONVERT(NVARCHAR(200), TRY_CONVERT(INT, @Text));
    END
    ELSE IF @ValueType = 'DECIMAL'
    BEGIN
        SET @Num = TRY_CONVERT(DECIMAL(18, 6), @Text);
        IF @Num IS NULL
            THROW 50052, N'Value must be a number.', 1;
        IF @Num <> ROUND(@Num, 2)
            THROW 50052, N'Value can have at most 2 decimal places.', 1;

        -- '-5.50' -> '-5.5', '-5.00' -> '-5'
        SET @Text = CONVERT(NVARCHAR(200), CAST(@Num AS DECIMAL(18, 2)));
        SET @Text = REVERSE(SUBSTRING(REVERSE(@Text), PATINDEX(N'%[^0]%', REVERSE(@Text)), 200));
        IF RIGHT(@Text, 1) = N'.' SET @Text = LEFT(@Text, LEN(@Text) - 1);
        IF @Text = N'-0' SET @Text = N'0';
    END

    /* -- Rentang per key -- */
    IF @SettingKey = 'EMERGENCY_FOLLOWUP_WORKDAYS' AND @Num NOT BETWEEN 1 AND 30
        THROW 50052, N'Emergency follow-up limit must be between 1 and 30 working days.', 1;
    IF @SettingKey IN ('SCHEDULE_ONTRACK_MIN_DEV', 'SCHEDULE_SLIGHT_MIN_DEV') AND @Num NOT BETWEEN -100 AND 0
        THROW 50052, N'Schedule deviation must be between -100 and 0 % points.', 1;
    IF @SettingKey IN ('COST_ONTRACK_MAX_PCT', 'COST_ATRISK_MAX_PCT') AND @Num NOT BETWEEN 1 AND 1000
        THROW 50052, N'Cost ratio must be between 1 and 1000 %.', 1;

    /* -- Konsistensi pasangan ambang (nilai efektif pasangan pada Company yang sama) -- */
    DECLARE @PairKey VARCHAR(50) =
        CASE @SettingKey
            WHEN 'SCHEDULE_ONTRACK_MIN_DEV' THEN 'SCHEDULE_SLIGHT_MIN_DEV'
            WHEN 'SCHEDULE_SLIGHT_MIN_DEV'  THEN 'SCHEDULE_ONTRACK_MIN_DEV'
            WHEN 'COST_ONTRACK_MAX_PCT'     THEN 'COST_ATRISK_MAX_PCT'
            WHEN 'COST_ATRISK_MAX_PCT'      THEN 'COST_ONTRACK_MAX_PCT'
        END;

    IF @PairKey IS NOT NULL
    BEGIN
        DECLARE @Pair DECIMAL(18, 6) =
        (
            SELECT TOP (1) TRY_CONVERT(DECIMAL(18, 6), SettingValue)
            FROM   dbo.AppSetting
            WHERE  SettingKey = @PairKey AND CoCode IN (@CoCode, '*')
            ORDER BY CASE WHEN CoCode = @CoCode THEN 0 ELSE 1 END
        );

        IF @Pair IS NOT NULL
        BEGIN
            IF @SettingKey = 'SCHEDULE_ONTRACK_MIN_DEV' AND @Num <= @Pair
                THROW 50052, N'On Track minimum deviation must be greater than the Slightly Delay minimum.', 1;
            IF @SettingKey = 'SCHEDULE_SLIGHT_MIN_DEV'  AND @Num >= @Pair
                THROW 50052, N'Slightly Delay minimum deviation must be less than the On Track minimum.', 1;
            IF @SettingKey = 'COST_ONTRACK_MAX_PCT'     AND @Num >= @Pair
                THROW 50052, N'On Track maximum ratio must be less than the At Risk maximum.', 1;
            IF @SettingKey = 'COST_ATRISK_MAX_PCT'      AND @Num <= @Pair
                THROW 50052, N'At Risk maximum ratio must be greater than the On Track maximum.', 1;
        END
    END

    UPDATE dbo.AppSetting
    SET    SettingValue = @Text,
           UpdatedAt    = SYSDATETIME(),
           UpdatedBy    = @ActionBy
    WHERE  CoCode = @CoCode AND SettingKey = @SettingKey;

    IF @@ROWCOUNT = 0
        THROW 50053, N'Setting not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) List: 5 baris '*', urut EMERGENCY, SCHEDULE_ONTRACK, SCHEDULE_SLIGHT, COST_ONTRACK, COST_ATRISK;
   --    Description sudah bahasa Inggris
   EXEC dbo.usp_AppSetting_List;
   EXEC dbo.usp_AppSetting_List @CoCode = 'ABL';                                         -- 0 baris (belum ada override)
   EXEC dbo.usp_AppSetting_GetByKey '*', 'EMERGENCY_FOLLOWUP_WORKDAYS';                   -- 1 baris

   -- 2) Update valid + normalisasi
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N' 05 ', N'uji';
   EXEC dbo.usp_AppSetting_Get 'ABL', 'EMERGENCY_FOLLOWUP_WORKDAYS';                      -- 5 (fallback '*'), UpdatedBy uji
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV', N'-5.50', N'uji';
   EXEC dbo.usp_AppSetting_GetByKey '*', 'SCHEDULE_ONTRACK_MIN_DEV';                      -- -5.5

   -- 3) Validasi -> 50052
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'';          -- kosong
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'2.5';       -- bukan bilangan bulat
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'0';         -- di luar 1..30
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'abc';       -- bukan angka
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'-5.555';    -- > 2 desimal
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'5';         -- di luar -100..0
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'-20';       -- <= Slightly Delay (-15)
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'COST_ATRISK_MAX_PCT',         N'100';       -- <= On Track (100)

   -- 4) Tidak ditemukan -> 50053
   EXEC dbo.usp_AppSetting_UpdateValue 'ABL', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'3';       -- baris ABL belum ada
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'TIDAK_ADA', N'3';

   -- 5) Kembalikan nilai uji
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'3',  N'uji';
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'-5', N'uji';
   ===================================================================== */
GO
/* ---------- end AppSetting.sql ---------- */
/* ---------- begin Scope.sql ---------- */
PRINT N'[skema] Scope.sql';
GO
/* =====================================================================
   Scope.sql  -  Lingkup data departemen per user (T0-2; PRD BR-24, BR-28, BR-29, BR-56, BR-57)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Prasyarat: Role.sql dan Config.sql sudah dijalankan; STRING_SPLIT (compat level >= 130);
              hak baca ke database [home] (users, app_employees, APP_Departments).
   Catatan :
     - Lingkup ini HANYA untuk MELIHAT data. Hak approve ditentukan langkah workflow (T2);
       approver hanya untuk request dengan CoCode sama dengan CoCode karyawannya (BR-63).
     - Setiap SP list/detail transaksi wajib membatasi data lewat function ini.
   ===================================================================== */

/* ---------------------------------------------------------------------
   dbo.fn_User_AllowedDepartments(@Username)
   DepartmentID + CoCode (APP_Departments, Disabled = 0) yang boleh dilihat user,
   gabungan semua role CIMS user (any-of):
     administrator, civil, purchasing, director, gm -> semua departemen ABL dan NKM
     fat, dgo                                       -> semua departemen pada CoCode karyawan
     kabag, adm, plan, spv, emp                     -> ABRV dan CoCode sama dengan departemen karyawan
     mo                                             -> anggota grup aktif MILL pada CoCode karyawan
   Tanpa role CIMS / user tidak ada -> 0 baris.
   Kolom FatOnlyScope (Keputusan 18-11-2026) = 1 bila departemen ini terlihat HANYA karena role fat / dgo; data
   departemen tsb dibatasi ke project In Progress ke atas (dbo.fn_Request_VisibleToUser, Request.sql).
   Contoh 'kabag;fat': departemen sendiri FatOnlyScope = 0 (semua status), departemen lain FatOnlyScope = 1.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_AllowedDepartments
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    WITH me AS
    (
        SELECT  e.CoCode, ad.ABRV
        FROM    home..users u
                JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
                LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
        WHERE   u.Username = @Username
    ),
    r AS
    (
        SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
        FROM   home..users u
               CROSS APPLY STRING_SPLIT(u.[Role], N';') s
        WHERE  u.Username = @Username
          AND  LTRIM(RTRIM(s.value)) <> N''
    )
    SELECT  d.DepartmentID, d.CoCode,
            CAST(CASE WHEN x.ViaOther = 0 THEN 1 ELSE 0 END AS BIT) AS FatOnlyScope
    FROM    home..APP_Departments d
            CROSS JOIN me
            CROSS APPLY
            (
                SELECT
                    -- fat / dgo (RL-13, 18-11-2026): Company karyawan
                    CASE WHEN EXISTS (SELECT 1 FROM r WHERE r.RoleCode IN (N'fat', N'dgo')) AND d.CoCode = me.CoCode
                         THEN 1 ELSE 0 END AS ViaFat,
                    CASE WHEN
                            -- semua departemen ABL dan NKM
                            (EXISTS (SELECT 1 FROM r WHERE r.RoleCode IN (N'administrator', N'civil', N'purchasing', N'director', N'gm'))
                             AND d.CoCode IN (N'ABL', N'NKM'))
                            -- kabag / adm / plan / spv / emp: ABRV + Company yang sama
                         OR (EXISTS (SELECT 1 FROM r WHERE r.RoleCode IN (N'kabag', N'adm', N'plan', N'spv', N'emp'))
                             AND d.ABRV = me.ABRV AND d.CoCode = me.CoCode)
                            -- mo: anggota grup MILL pada Company karyawan
                         OR (EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'mo')
                             AND d.CoCode = me.CoCode
                             AND EXISTS (SELECT 1
                                         FROM   dbo.DepartmentGroup g
                                                JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                                         WHERE  g.CoCode = me.CoCode AND g.GroupCode = N'MILL' AND g.IsActive = 1
                                           AND  m.DepartmentID = d.DepartmentID))
                         THEN 1 ELSE 0 END AS ViaOther
            ) x
    WHERE   ISNULL(d.Disabled, 0) = 0
      AND   (x.ViaFat = 1 OR x.ViaOther = 1)
);
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok; ganti <...> dengan username nyata)

   -- Cari contoh user per role (role portal ada di home..users.[Role]):
   SELECT u.Username, u.[Role], e.CoCode, ad.ABRV, ad.DepartmentID
   FROM   home..users u
          JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
          LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
   ORDER BY u.[Role];

   -- 1) Satu user per role: lihat jumlah dan isi
   SELECT COUNT(*) AS Jumlah FROM dbo.fn_User_AllowedDepartments(N'<user-administrator/civil/gm/director/purchasing>');   -- semua ABL + NKM (Disabled = 0)
   SELECT COUNT(*) AS Jumlah FROM dbo.fn_User_AllowedDepartments(N'<user-fat>');    -- hanya CoCode karyawan
   SELECT * FROM dbo.fn_User_AllowedDepartments(N'<user-kabag-atau-adm>');          -- ABRV + CoCode yang sama

   -- 2) User QC (C500): harus mengembalikan C500 dan D500 (DepartmentID keduanya)
   SELECT f.DepartmentID, f.CoCode, ad.DeptName, ad.ABRV
   FROM   dbo.fn_User_AllowedDepartments(N'<user-kabag-QC>') f
          JOIN home..APP_Departments ad ON ad.DepartmentID = f.DepartmentID;

   -- 3) User mo: tepat 6 departemen MILL (17, 18, 19, 20, 600, 601)
   SELECT * FROM dbo.fn_User_AllowedDepartments(N'<user-mo>') ORDER BY DepartmentID;

   -- 4) User dengan 'kabag;civil' (gabungan): sama dengan lingkup civil (semua)
   SELECT COUNT(*) FROM dbo.fn_User_AllowedDepartments(N'<user-kabag-civil>');

   -- 5) User emp / spv / plan: sama dengan adm (ABRV + Company; QC -> C500 dan D500)
   SELECT * FROM dbo.fn_User_AllowedDepartments(N'<user-emp>');
   -- User tanpa role CIMS (mis. hanya komisaris/creator) atau tidak ada: 0 baris
   SELECT * FROM dbo.fn_User_AllowedDepartments(N'tidak-ada-xyz');

   -- 5b) User 'kabag;fat': departemen sendiri FatOnlyScope = 0, departemen lain di Company yang sama = 1
   SELECT f.DepartmentID, ad.ABRV, f.FatOnlyScope FROM dbo.fn_User_AllowedDepartments(N'<user-kabag-fat>') f
          JOIN home..APP_Departments ad ON ad.DepartmentID = f.DepartmentID ORDER BY f.FatOnlyScope, ad.ABRV;

   -- 6) Jika error "Invalid column name 'Disabled'" / konversi tipe: laporkan tipe kolom
   --    home..APP_Departments.Disabled (diasumsikan bit/int, NULL dianggap aktif).
   ===================================================================== */
GO
/* ---------- end Scope.sql ---------- */
/* ---------- begin Customer.sql ---------- */
PRINT N'[skema] Customer.sql';
GO
/* =====================================================================
   Customer.sql  -  Modul pilot: Customer (master data CRUD)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Error   : 50001 = Kode duplikat
             50002 = Input wajib kosong
             50003 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Customer', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Customer
    (
        Id          INT IDENTITY(1,1)  NOT NULL,
        Code        NVARCHAR(20)       NOT NULL,
        Name        NVARCHAR(100)      NOT NULL,
        Phone       NVARCHAR(20)       NULL,
        Email       NVARCHAR(100)      NULL,
        Address     NVARCHAR(250)      NULL,
        IsActive    BIT                NOT NULL CONSTRAINT DF_Customer_IsActive  DEFAULT (1),
        CreatedAt   DATETIME2(3)       NOT NULL CONSTRAINT DF_Customer_CreatedAt DEFAULT (SYSDATETIME()),
        UpdatedAt   DATETIME2(3)       NULL,
        CONSTRAINT PK_Customer PRIMARY KEY CLUSTERED (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_Customer_Code' AND object_id = OBJECT_ID(N'dbo.Customer'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Customer_Code ON dbo.Customer (Code);
END
GO

/* ---------------------------------------------------------------------
   2. usp_Customer_GetPaged
      Search (Code/Name), filter status, sorting whitelist, paging.
      @SortBy  : Code | Name | CreatedAt   (default Code)
      @SortDir : ASC | DESC                (default ASC)
      @TotalCount = total baris setelah filter (OUTPUT)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_GetPaged
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Code',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy  IN (N'Code', N'Name', N'CreatedAt') THEN @SortBy  ELSE N'Code' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.Customer
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%'
                             OR Name LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Code, Name, Phone, Email, Address, IsActive, CreatedAt, UpdatedAt
    FROM dbo.Customer
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%'
                             OR Name LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'ASC'  THEN Code      END ASC,
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'DESC' THEN Code      END DESC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   3. usp_Customer_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, Name, Phone, Email, Address, IsActive, CreatedAt, UpdatedAt
    FROM dbo.Customer
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Customer_Insert
      @NewId = Id baru (OUTPUT)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_Insert
    @Code      NVARCHAR(20),
    @Name      NVARCHAR(100),
    @Phone     NVARCHAR(20)  = NULL,
    @Email     NVARCHAR(100) = NULL,
    @Address   NVARCHAR(250) = NULL,
    @IsActive  BIT           = 1,
    @NewId     INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code    = LTRIM(RTRIM(@Code));
    SET @Name    = LTRIM(RTRIM(@Name));
    SET @Phone   = NULLIF(LTRIM(RTRIM(@Phone)),   N'');
    SET @Email   = NULLIF(LTRIM(RTRIM(@Email)),   N'');
    SET @Address = NULLIF(LTRIM(RTRIM(@Address)), N'');

    IF ISNULL(@Code, N'') = N'' THROW 50002, N'Customer code is required.', 1;
    IF ISNULL(@Name, N'') = N'' THROW 50002, N'Customer name is required.', 1;

    BEGIN TRY
        INSERT INTO dbo.Customer (Code, Name, Phone, Email, Address, IsActive)
        VALUES (@Code, @Name, @Phone, @Email, @Address, ISNULL(@IsActive, 1));

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50001, N'Customer code is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   5. usp_Customer_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_Update
    @Id        INT,
    @Code      NVARCHAR(20),
    @Name      NVARCHAR(100),
    @Phone     NVARCHAR(20)  = NULL,
    @Email     NVARCHAR(100) = NULL,
    @Address   NVARCHAR(250) = NULL,
    @IsActive  BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code    = LTRIM(RTRIM(@Code));
    SET @Name    = LTRIM(RTRIM(@Name));
    SET @Phone   = NULLIF(LTRIM(RTRIM(@Phone)),   N'');
    SET @Email   = NULLIF(LTRIM(RTRIM(@Email)),   N'');
    SET @Address = NULLIF(LTRIM(RTRIM(@Address)), N'');

    IF ISNULL(@Code, N'') = N'' THROW 50002, N'Customer code is required.', 1;
    IF ISNULL(@Name, N'') = N'' THROW 50002, N'Customer name is required.', 1;

    BEGIN TRY
        UPDATE dbo.Customer
        SET Code      = @Code,
            Name      = @Name,
            Phone     = @Phone,
            Email     = @Email,
            Address   = @Address,
            IsActive  = ISNULL(@IsActive, IsActive),
            UpdatedAt = SYSDATETIME()
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50003, N'Customer not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50001, N'Customer code is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   6. usp_Customer_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_SetActive
    @Id        INT,
    @IsActive  BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Customer
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME()
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50003, N'Customer not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Insert
   DECLARE @NewId INT;
   EXEC dbo.usp_Customer_Insert @Code = N'CUST001', @Name = N'PT Contoh Satu',
        @Phone = N'0721-123456', @Email = N'a@contoh.co.id', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;

   -- 2) Duplikat -> harus error 50001
   EXEC dbo.usp_Customer_Insert @Code = N'cust001', @Name = N'Duplikat';

   -- 3) List + paging
   DECLARE @Total INT;
   EXEC dbo.usp_Customer_GetPaged @Search = N'contoh', @IsActive = 1,
        @SortBy = N'Name', @SortDir = N'DESC', @PageNumber = 1, @PageSize = 10,
        @TotalCount = @Total OUTPUT;
   SELECT @Total AS TotalCount;

   -- 4) Update, soft delete, get by id
   EXEC dbo.usp_Customer_Update @Id = 1, @Code = N'CUST001', @Name = N'PT Contoh Satu (Rev)';
   EXEC dbo.usp_Customer_SetActive @Id = 1, @IsActive = 0;
   EXEC dbo.usp_Customer_GetById @Id = 1;

   -- 5) Id tidak ada -> harus error 50003
   EXEC dbo.usp_Customer_SetActive @Id = 999999, @IsActive = 0;
   ===================================================================== */
GO
/* ---------- end Customer.sql ---------- */
/* ---------- begin Location.sql ---------- */
PRINT N'[skema] Location.sql';
GO
/* =====================================================================
   Location.sql  -  Master data Lokasi / Area (T1; PRD MD-02, BR-61)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan : Lokasi per Company (CoCode). Tanpa kode; nama unik per Company.
             Seed MERGE hanya MENAMBAH nama yang belum ada (tidak menimpa perubahan).
             Soft delete lewat SetActive (tanpa Delete).
   Error   : 50011 = Nama lokasi duplikat (pada Company yang sama)
             50012 = Input wajib kosong / tidak valid
             50013 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Location', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Location
    (
        Id         INT IDENTITY(1,1) NOT NULL,
        CoCode     VARCHAR(10)   NOT NULL,
        Name       NVARCHAR(100) NOT NULL,
        IsActive   BIT           NOT NULL CONSTRAINT DF_Location_IsActive  DEFAULT (1),
        CreatedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_Location_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy  NVARCHAR(100) NULL,
        UpdatedAt  DATETIME2(3)  NULL,
        UpdatedBy  NVARCHAR(100) NULL,
        CONSTRAINT PK_Location PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_Location_CoCode CHECK (CoCode IN ('ABL', 'NKM'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_Location_CoCode_Name' AND object_id = OBJECT_ID(N'dbo.Location'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Location_CoCode_Name ON dbo.Location (CoCode, Name);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (Company ABL; hanya menambah yang belum ada)
   --------------------------------------------------------------------- */
MERGE dbo.Location AS t
USING (VALUES
        (N'Main Office 1st floor'), (N'Main Office 2nd floor'), (N'HRGA'), (N'Interco Meeting Room'),
        (N'Pos 1 Security'), (N'Pos 2 Security'), (N'Pos 3 Security'), (N'Pos 4 Security'), (N'Pos 5 Security'),
        (N'Paper Raw Material'), (N'Purchasing Office'), (N'Warehouse & Logistic Office'),
        (N'Paper Finished Goods'), (N'Tissue Finished Goods'), (N'Canteen & Hall'), (N'Mess'),
        (N'Multi Purpose Hall'), (N'MO Office'), (N'Finishing Office'), (N'TPM Office'),
        (N'Converting Office'), (N'Cassie Meeting Room'), (N'Fabrication Area'), (N'Engineering Office'),
        (N'Heavy Equipment'), (N'Workshop'), (N'Elektrical Office'), (N'Parking Lot'),
        (N'Boiler'), (N'Reverse Osmosis'), (N'Utility Office'), (N'Fiber Storage'),
        (N'Tissue Raw Material'), (N'TPM Mill'), (N'PM Mill'), (N'Finishing Mill'),
        (N'Converting Mill'), (N'Water Treatment'), (N'Waste Pond'), (N'PM 3 Mill')
      ) AS s (Name)
   ON t.CoCode = 'ABL' AND t.Name = s.Name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CoCode, Name, CreatedBy)
    VALUES ('ABL', s.Name, N'seed');
GO

/* ---------------------------------------------------------------------
   3. usp_Location_GetPaged
      Search (Name), filter Company dan status, sorting whitelist, paging.
      @SortBy  : Name | CoCode | CreatedAt   (default Name)
      @SortDir : ASC | DESC                  (default ASC)
      @TotalCount = total baris setelah filter (OUTPUT)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_GetPaged
    @CoCode      VARCHAR(10)   = NULL,
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Name',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode     = NULLIF(LTRIM(RTRIM(@CoCode)), N'');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Name', N'CoCode', N'CreatedAt') THEN @SortBy ELSE N'Name' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.Location
    WHERE (@CoCode   IS NULL OR CoCode = @CoCode)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Name LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, CoCode, Name, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Location
    WHERE (@CoCode   IS NULL OR CoCode = @CoCode)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Name LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        CASE WHEN @SortBy = N'CoCode'    AND @SortDir = N'ASC'  THEN CoCode    END ASC,
        CASE WHEN @SortBy = N'CoCode'    AND @SortDir = N'DESC' THEN CoCode    END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Name ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   4. usp_Location_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, CoCode, Name, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Location
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Location_Insert
      @NewId = Id baru (OUTPUT); @ActionBy = username pelaku (audit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_Insert
    @CoCode    VARCHAR(10),
    @Name      NVARCHAR(100),
    @IsActive  BIT           = 1,
    @ActionBy  NVARCHAR(100) = NULL,
    @NewId     INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @CoCode = UPPER(LTRIM(RTRIM(@CoCode)));
    SET @Name   = LTRIM(RTRIM(@Name));

    IF ISNULL(@CoCode, '') NOT IN ('ABL', 'NKM') THROW 50012, N'Company is required (ABL or NKM).', 1;
    IF ISNULL(@Name, N'') = N''                  THROW 50012, N'Location name is required.', 1;

    BEGIN TRY
        INSERT INTO dbo.Location (CoCode, Name, IsActive, CreatedBy)
        VALUES (@CoCode, @Name, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50011, N'Location name is already in use for this company.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   6. usp_Location_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_Update
    @Id        INT,
    @CoCode    VARCHAR(10),
    @Name      NVARCHAR(100),
    @IsActive  BIT           = 1,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @CoCode = UPPER(LTRIM(RTRIM(@CoCode)));
    SET @Name   = LTRIM(RTRIM(@Name));

    IF ISNULL(@CoCode, '') NOT IN ('ABL', 'NKM') THROW 50012, N'Company is required (ABL or NKM).', 1;
    IF ISNULL(@Name, N'') = N''                  THROW 50012, N'Location name is required.', 1;

    BEGIN TRY
        UPDATE dbo.Location
        SET CoCode    = @CoCode,
            Name      = @Name,
            IsActive  = ISNULL(@IsActive, IsActive),
            UpdatedAt = SYSDATETIME(),
            UpdatedBy = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50013, N'Location not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50011, N'Location name is already in use for this company.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_Location_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Location
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50013, N'Location not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: 40 baris Company ABL, semua aktif, CreatedBy = 'seed'
   SELECT COUNT(*) AS Jumlah FROM dbo.Location WHERE CoCode = 'ABL';   -- 40
   SELECT * FROM dbo.Location ORDER BY Name;

   -- 2) Insert (Company NKM) lalu duplikat -> error 50011
   DECLARE @NewId INT;
   EXEC dbo.usp_Location_Insert @CoCode = 'NKM', @Name = N'Gudang Uji', @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;
   EXEC dbo.usp_Location_Insert @CoCode = 'NKM', @Name = N'gudang uji';        -- 50011 (tidak peka huruf besar/kecil)
   EXEC dbo.usp_Location_Insert @CoCode = 'ABL', @Name = N'Gudang Uji';        -- boleh (Company berbeda)

   -- 3) Validasi -> error 50012
   EXEC dbo.usp_Location_Insert @CoCode = 'XYZ', @Name = N'A';
   EXEC dbo.usp_Location_Insert @CoCode = 'ABL', @Name = N'   ';

   -- 4) List: search, filter Company/status, sort, paging
   DECLARE @Total INT;
   EXEC dbo.usp_Location_GetPaged @CoCode = 'ABL', @Search = N'mill', @IsActive = 1,
        @SortBy = N'Name', @SortDir = N'DESC', @PageNumber = 1, @PageSize = 10, @TotalCount = @Total OUTPUT;
   SELECT @Total AS TotalCount;   -- 5 (TPM, PM, Finishing, Converting, PM 3 Mill)

   -- 5) Update, soft delete, get by id (UpdatedAt/UpdatedBy terisi)
   EXEC dbo.usp_Location_Update @Id = 1, @CoCode = 'ABL', @Name = N'Main Office 1st floor', @ActionBy = N'uji';
   EXEC dbo.usp_Location_SetActive @Id = 1, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_Location_GetById @Id = 1;
   EXEC dbo.usp_Location_SetActive @Id = 1, @IsActive = 1, @ActionBy = N'uji';   -- kembalikan

   -- 6) Update nama menjadi nama lokasi lain pada Company sama -> 50011; Id tidak ada -> 50013
   EXEC dbo.usp_Location_Update @Id = 1, @CoCode = 'ABL', @Name = N'HRGA';
   EXEC dbo.usp_Location_SetActive @Id = 999999, @IsActive = 0;

   -- 7) Idempotensi: ubah satu nama seed, jalankan ulang script ini -> tidak ada baris dobel;
   --    nama lama yang diubah akan ditambah kembali sebagai baris baru (MERGE hanya menambah).
   --    Bersihkan data uji:
   --    DELETE dbo.Location WHERE Name = N'Gudang Uji';
   ===================================================================== */
GO
/* ---------- end Location.sql ---------- */
/* ---------- begin AttachmentType.sql ---------- */
PRINT N'[skema] AttachmentType.sql';
GO
/* =====================================================================
   AttachmentType.sql  -  Master data Jenis Lampiran (T1; PRD MD-09, BR-45, BR-05, BR-42, BR-43, 6.5)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Code unik dan TIDAK bisa diubah setelah dibuat (dipakai modul lain sebagai kunci).
     - Stage = tahap proses tempat lampiran diunggah:
         REQUEST (business case), DOCUMENT (Document Preparation Civil), PROCUREMENT (TOR),
         CONTRACT (input Purchasing), BAPP, COST (upload actual cost),
         ADDENDUM (dokumen addendum kontrak / BOQ revisi; T4-4, seed + migrasi constraint di RequestAddendum.sql).
     - IsMandatoryCapex/Opex/Lve = wajib diunggah pada tahap tersebut untuk kategori itu.
       Contoh: TOR dan Contract hanya untuk outsource -> tidak ditandai wajib per kategori; alur
       outsource yang mewajibkannya (BR-11).
     - AllowedExtensions: huruf kecil tanpa titik, dipisah koma (mis. 'pdf,jpg,png'). MaxSizeMB 1..100.
     - Seed MERGE hanya MENAMBAH Code yang belum ada (tidak menimpa perubahan).
     - Soft delete lewat SetActive (tanpa Delete).
   Error   : 50021 = Code duplikat
             50022 = Input wajib kosong / tidak valid
             50023 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.AttachmentType', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AttachmentType
    (
        Id                 INT IDENTITY(1,1) NOT NULL,
        Code               VARCHAR(30)   NOT NULL,
        Name               NVARCHAR(100) NOT NULL,
        Stage              VARCHAR(20)   NOT NULL,
        AllowedExtensions  VARCHAR(200)  NOT NULL,
        MaxSizeMB          INT           NOT NULL,
        IsMandatoryCapex   BIT           NOT NULL CONSTRAINT DF_AttachmentType_MandCapex DEFAULT (0),
        IsMandatoryOpex    BIT           NOT NULL CONSTRAINT DF_AttachmentType_MandOpex  DEFAULT (0),
        IsMandatoryLve     BIT           NOT NULL CONSTRAINT DF_AttachmentType_MandLve   DEFAULT (0),
        IsActive           BIT           NOT NULL CONSTRAINT DF_AttachmentType_IsActive  DEFAULT (1),
        CreatedAt          DATETIME2(3)  NOT NULL CONSTRAINT DF_AttachmentType_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy          NVARCHAR(100) NULL,
        UpdatedAt          DATETIME2(3)  NULL,
        UpdatedBy          NVARCHAR(100) NULL,
        CONSTRAINT PK_AttachmentType PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_AttachmentType_Code    CHECK (Code NOT LIKE '%[^A-Z0-9_]%' COLLATE Latin1_General_BIN),
        CONSTRAINT CK_AttachmentType_Stage   CHECK (Stage IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP', 'COST', 'ADDENDUM')),
        CONSTRAINT CK_AttachmentType_Ext     CHECK (AllowedExtensions <> '' AND AllowedExtensions NOT LIKE '%[^a-z0-9,]%' COLLATE Latin1_General_BIN),
        CONSTRAINT CK_AttachmentType_MaxSize CHECK (MaxSizeMB BETWEEN 1 AND 100)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_AttachmentType_Code' AND object_id = OBJECT_ID(N'dbo.AttachmentType'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_AttachmentType_Code ON dbo.AttachmentType (Code);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (PRD 6.5; wajib: BR-42 ROI CAPEX, BR-43 foto area, BR-05 BOQ semua / Drawing CAPEX)
   --------------------------------------------------------------------- */
MERGE dbo.AttachmentType AS t
USING (VALUES
        ('ROI',         N'ROI Calculation',     'REQUEST',     'pdf,jpg,png',  5, 1, 0, 0),
        ('AREA_PHOTO',  N'Area Photo',          'REQUEST',     'pdf,jpg,png',  5, 1, 1, 1),
        ('BOQ',         N'Bill of Quantities',  'DOCUMENT',    'pdf,xlsx,dwg', 20, 1, 1, 1),
        ('DRAWING',     N'Drawing',             'DOCUMENT',    'pdf,xlsx,dwg', 20, 1, 0, 0),
        ('TOR',         N'Terms of Reference',  'PROCUREMENT', 'pdf,xlsx,dwg', 20, 0, 0, 0),
        ('CONTRACT',    N'Contract',            'CONTRACT',    'pdf,xlsx,dwg', 20, 0, 0, 0),
        ('BAPP',        N'BAPP',                'BAPP',        'pdf,xlsx,dwg', 20, 1, 1, 1),
        ('ACTUAL_COST', N'Actual Cost Upload',  'COST',        'xlsx',          5, 0, 0, 0)
      ) AS s (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve)
   ON t.Code = s.Code
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, CreatedBy)
    VALUES (s.Code, s.Name, s.Stage, s.AllowedExtensions, s.MaxSizeMB,
            CAST(s.IsMandatoryCapex AS BIT), CAST(s.IsMandatoryOpex AS BIT), CAST(s.IsMandatoryLve AS BIT), N'seed');
GO

/* ---------------------------------------------------------------------
   3. dbo.fn_AttachmentType_NormalizeExt
      'PDF, .Jpg,,png ' -> 'pdf,jpg,png' (huruf kecil, tanpa spasi/titik, tanpa koma ganda/di ujung).
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_AttachmentType_NormalizeExt (@Ext NVARCHAR(400))
RETURNS VARCHAR(200)
AS
BEGIN
    DECLARE @s NVARCHAR(400) = LOWER(REPLACE(REPLACE(REPLACE(ISNULL(@Ext, N''), N' ', N''), N'.', N''), CHAR(9), N''));
    WHILE CHARINDEX(N',,', @s) > 0 SET @s = REPLACE(@s, N',,', N',');
    IF LEFT(@s, 1) = N','  SET @s = STUFF(@s, 1, 1, N'');
    IF RIGHT(@s, 1) = N',' SET @s = LEFT(@s, LEN(@s) - 1);
    RETURN CAST(@s AS VARCHAR(200));
END
GO

/* ---------------------------------------------------------------------
   4. usp_AttachmentType_GetPaged
      Search (Code/Name), filter Stage dan status, sorting whitelist, paging.
      @SortBy  : Code | Name | Stage | CreatedAt   (default Stage)
      @SortDir : ASC | DESC                        (default ASC)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_GetPaged
    @Stage       VARCHAR(20)   = NULL,
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Stage',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Stage      = NULLIF(LTRIM(RTRIM(@Stage)), '');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Code', N'Name', N'Stage', N'CreatedAt') THEN @SortBy ELSE N'Stage' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.AttachmentType
    WHERE (@Stage    IS NULL OR Stage = @Stage)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Code, Name, Stage, AllowedExtensions, MaxSizeMB,
           IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, IsActive,
           CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.AttachmentType
    WHERE (@Stage    IS NULL OR Stage = @Stage)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'ASC'  THEN Code      END ASC,
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'DESC' THEN Code      END DESC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        -- Stage diurutkan sesuai alur proses, bukan alfabet.
        CASE WHEN @SortBy = N'Stage'     AND @SortDir = N'ASC'  THEN
             CHARINDEX(',' + Stage + ',', ',REQUEST,DOCUMENT,PROCUREMENT,CONTRACT,BAPP,COST,ADDENDUM,') END ASC,
        CASE WHEN @SortBy = N'Stage'     AND @SortDir = N'DESC' THEN
             CHARINDEX(',' + Stage + ',', ',REQUEST,DOCUMENT,PROCUREMENT,CONTRACT,BAPP,COST,ADDENDUM,') END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Code ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   5. usp_AttachmentType_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, Name, Stage, AllowedExtensions, MaxSizeMB,
           IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, IsActive,
           CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.AttachmentType
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   6. usp_AttachmentType_Insert
      @NewId = Id baru (OUTPUT); @ActionBy = username pelaku (audit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_Insert
    @Code               VARCHAR(30),
    @Name               NVARCHAR(100),
    @Stage              VARCHAR(20),
    @AllowedExtensions  NVARCHAR(400),
    @MaxSizeMB          INT,
    @IsMandatoryCapex   BIT           = 0,
    @IsMandatoryOpex    BIT           = 0,
    @IsMandatoryLve     BIT           = 0,
    @IsActive           BIT           = 1,
    @ActionBy           NVARCHAR(100) = NULL,
    @NewId              INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code  = UPPER(LTRIM(RTRIM(@Code)));
    SET @Name  = LTRIM(RTRIM(@Name));
    SET @Stage = UPPER(LTRIM(RTRIM(@Stage)));
    DECLARE @Ext VARCHAR(200) = dbo.fn_AttachmentType_NormalizeExt(@AllowedExtensions);

    IF ISNULL(@Code, '') = ''                                  THROW 50022, N'Code is required.', 1;
    IF @Code LIKE '%[^A-Z0-9_]%' COLLATE Latin1_General_BIN    THROW 50022, N'Code may only contain letters, numbers, and underscores.', 1;
    IF ISNULL(@Name, N'') = N''                                THROW 50022, N'Name is required.', 1;
    IF ISNULL(@Stage, '') NOT IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP', 'COST', 'ADDENDUM')
                                                               THROW 50022, N'Stage is invalid.', 1;
    IF @Ext = '' OR @Ext LIKE '%[^a-z0-9,]%' COLLATE Latin1_General_BIN
                                                               THROW 50022, N'Allowed extensions are invalid (example: pdf,jpg,png).', 1;
    IF @MaxSizeMB IS NULL OR @MaxSizeMB NOT BETWEEN 1 AND 100  THROW 50022, N'Max size must be between 1 and 100 MB.', 1;

    BEGIN TRY
        INSERT INTO dbo.AttachmentType
            (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, IsActive, CreatedBy)
        VALUES
            (@Code, @Name, @Stage, @Ext, @MaxSizeMB, ISNULL(@IsMandatoryCapex, 0), ISNULL(@IsMandatoryOpex, 0),
             ISNULL(@IsMandatoryLve, 0), ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50021, N'Code is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_AttachmentType_Update  (Code tidak bisa diubah)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_Update
    @Id                 INT,
    @Name               NVARCHAR(100),
    @Stage              VARCHAR(20),
    @AllowedExtensions  NVARCHAR(400),
    @MaxSizeMB          INT,
    @IsMandatoryCapex   BIT           = 0,
    @IsMandatoryOpex    BIT           = 0,
    @IsMandatoryLve     BIT           = 0,
    @IsActive           BIT           = 1,
    @ActionBy           NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name  = LTRIM(RTRIM(@Name));
    SET @Stage = UPPER(LTRIM(RTRIM(@Stage)));
    DECLARE @Ext VARCHAR(200) = dbo.fn_AttachmentType_NormalizeExt(@AllowedExtensions);

    IF ISNULL(@Name, N'') = N''                                THROW 50022, N'Name is required.', 1;
    IF ISNULL(@Stage, '') NOT IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP', 'COST', 'ADDENDUM')
                                                               THROW 50022, N'Stage is invalid.', 1;
    IF @Ext = '' OR @Ext LIKE '%[^a-z0-9,]%' COLLATE Latin1_General_BIN
                                                               THROW 50022, N'Allowed extensions are invalid (example: pdf,jpg,png).', 1;
    IF @MaxSizeMB IS NULL OR @MaxSizeMB NOT BETWEEN 1 AND 100  THROW 50022, N'Max size must be between 1 and 100 MB.', 1;

    UPDATE dbo.AttachmentType
    SET Name              = @Name,
        Stage             = @Stage,
        AllowedExtensions = @Ext,
        MaxSizeMB         = @MaxSizeMB,
        IsMandatoryCapex  = ISNULL(@IsMandatoryCapex, 0),
        IsMandatoryOpex   = ISNULL(@IsMandatoryOpex, 0),
        IsMandatoryLve    = ISNULL(@IsMandatoryLve, 0),
        IsActive          = ISNULL(@IsActive, IsActive),
        UpdatedAt         = SYSDATETIME(),
        UpdatedBy         = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50023, N'Attachment type not found.', 1;
END
GO

/* ---------------------------------------------------------------------
   8. usp_AttachmentType_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AttachmentType
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50023, N'Attachment type not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: 8 baris; wajib sesuai PRD (ROI & Drawing CAPEX; Area Photo, BOQ, BAPP semua kategori)
   SELECT Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve
   FROM dbo.AttachmentType ORDER BY Id;

   -- 2) Insert jenis baru + normalisasi ekstensi -> AllowedExtensions = 'pdf,jpg,png', Code = 'SITE_REPORT'
   DECLARE @NewId INT;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'site_report', @Name = N'Site Report', @Stage = 'DOCUMENT',
        @AllowedExtensions = N' PDF, .Jpg,,png, ', @MaxSizeMB = 10, @IsMandatoryOpex = 1,
        @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   EXEC dbo.usp_AttachmentType_GetById @Id = @NewId;

   -- 3) Code duplikat -> 50021 ; Code tidak valid / Stage salah / ekstensi kosong / ukuran 0 -> 50022
   EXEC dbo.usp_AttachmentType_Insert @Code = 'BOQ', @Name = N'X', @Stage = 'DOCUMENT', @AllowedExtensions = N'pdf', @MaxSizeMB = 5;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'A-B', @Name = N'X', @Stage = 'DOCUMENT', @AllowedExtensions = N'pdf', @MaxSizeMB = 5;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'X1',  @Name = N'X', @Stage = 'OTHER',    @AllowedExtensions = N'pdf', @MaxSizeMB = 5;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'X2',  @Name = N'X', @Stage = 'DOCUMENT', @AllowedExtensions = N' , ', @MaxSizeMB = 5;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'X3',  @Name = N'X', @Stage = 'DOCUMENT', @AllowedExtensions = N'pdf', @MaxSizeMB = 0;

   -- 4) List: filter Stage DOCUMENT, sort Stage (urutan alur), paging
   DECLARE @Total INT;
   EXEC dbo.usp_AttachmentType_GetPaged @Stage = 'DOCUMENT', @TotalCount = @Total OUTPUT;   -- BOQ, DRAWING, SITE_REPORT
   SELECT @Total AS TotalCount;
   EXEC dbo.usp_AttachmentType_GetPaged @TotalCount = @Total OUTPUT;                       -- REQUEST dulu, COST terakhir

   -- 5) Update (Code tetap), soft delete; Id tidak ada -> 50023
   DECLARE @NewId INT = (SELECT Id FROM dbo.AttachmentType WHERE Code = 'SITE_REPORT');
   EXEC dbo.usp_AttachmentType_Update @Id = @NewId, @Name = N'Site Report (Rev)', @Stage = 'BAPP',
        @AllowedExtensions = N'pdf', @MaxSizeMB = 15, @IsMandatoryCapex = 1, @ActionBy = N'uji';
   EXEC dbo.usp_AttachmentType_SetActive @Id = @NewId, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_AttachmentType_GetById @Id = @NewId;
   EXEC dbo.usp_AttachmentType_SetActive @Id = 999999, @IsActive = 0;

   -- 6) Jalankan ulang script -> tidak ada baris dobel; perubahan pada langkah 5 tidak tertimpa.
   --    Bersihkan data uji:
   --    DELETE dbo.AttachmentType WHERE Code = 'SITE_REPORT';
   ===================================================================== */
GO
/* ---------- end AttachmentType.sql ---------- */
/* ---------- begin AssessmentQuestion.sql ---------- */
PRINT N'[skema] AssessmentQuestion.sql';
GO
/* =====================================================================
   AssessmentQuestion.sql  -  Master pertanyaan Environment Assessment (T1; PRD MD-08, 6.1 (iii))
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Satu daftar untuk semua kategori (12 pertanyaan sama di form Capex, Opex, LVE).
     - Jawaban Yes/No; pertanyaan aktif di-snapshot ke request saat Submit (dikerjakan di T2).
     - SortOrder = urutan tampil di form (boleh sama; urutan kedua = Id).
     - Seed MERGE hanya MENAMBAH pertanyaan yang belum ada (tidak menimpa perubahan).
     - Soft delete lewat SetActive (tanpa Delete).
   Error   : 50031 = Pertanyaan duplikat
             50032 = Input wajib kosong / tidak valid
             50033 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.AssessmentQuestion', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AssessmentQuestion
    (
        Id            INT IDENTITY(1,1) NOT NULL,
        SortOrder     INT           NOT NULL,
        QuestionText  NVARCHAR(300) NOT NULL,
        IsActive      BIT           NOT NULL CONSTRAINT DF_AssessmentQuestion_IsActive  DEFAULT (1),
        CreatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_AssessmentQuestion_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy     NVARCHAR(100) NULL,
        UpdatedAt     DATETIME2(3)  NULL,
        UpdatedBy     NVARCHAR(100) NULL,
        CONSTRAINT PK_AssessmentQuestion PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_AssessmentQuestion_SortOrder CHECK (SortOrder BETWEEN 1 AND 999)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_AssessmentQuestion_Text' AND object_id = OBJECT_ID(N'dbo.AssessmentQuestion'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_AssessmentQuestion_Text ON dbo.AssessmentQuestion (QuestionText);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (12 pertanyaan dari form Capex/Opex/LVE Requisition, bagian (iii))
   --------------------------------------------------------------------- */
MERGE dbo.AssessmentQuestion AS t
USING (VALUES
        ( 1, N'Is the proposed area suitable and ready for the project?'),
        ( 2, N'Is the proposed location available for construction?'),
        ( 3, N'Has the existing site condition been assessed?'),
        ( 4, N'Is a layout drawing available?'),
        ( 5, N'Is the required scope of work clearly defined?'),
        ( 6, N'Is the project required to meet safety or regulatory requirements?'),
        ( 7, N'Will the project affect existing operations?'),
        ( 8, N'Is there any alternative location or solution?'),
        ( 9, N'Is the proposed completion date critical to operations?'),
        (10, N'Is the estimated budget available?'),
        (11, N'Are any utilities or supporting facilities required?'),
        (12, N'Are there any special restrictions or requirements?')
      ) AS s (SortOrder, QuestionText)
   ON t.QuestionText = s.QuestionText
WHEN NOT MATCHED BY TARGET THEN
    INSERT (SortOrder, QuestionText, CreatedBy)
    VALUES (s.SortOrder, s.QuestionText, N'seed');
GO

/* ---------------------------------------------------------------------
   3. usp_AssessmentQuestion_GetPaged
      Search (QuestionText), filter status, sorting whitelist, paging.
      @SortBy  : SortOrder | QuestionText | CreatedAt   (default SortOrder)
      @SortDir : ASC | DESC                             (default ASC)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AssessmentQuestion_GetPaged
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'SortOrder',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'SortOrder', N'QuestionText', N'CreatedAt') THEN @SortBy ELSE N'SortOrder' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.AssessmentQuestion
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR QuestionText LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, SortOrder, QuestionText, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.AssessmentQuestion
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR QuestionText LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'SortOrder'    AND @SortDir = N'ASC'  THEN SortOrder    END ASC,
        CASE WHEN @SortBy = N'SortOrder'    AND @SortDir = N'DESC' THEN SortOrder    END DESC,
        CASE WHEN @SortBy = N'QuestionText' AND @SortDir = N'ASC'  THEN QuestionText END ASC,
        CASE WHEN @SortBy = N'QuestionText' AND @SortDir = N'DESC' THEN QuestionText END DESC,
        CASE WHEN @SortBy = N'CreatedAt'    AND @SortDir = N'ASC'  THEN CreatedAt    END ASC,
        CASE WHEN @SortBy = N'CreatedAt'    AND @SortDir = N'DESC' THEN CreatedAt    END DESC,
        SortOrder ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   4. usp_AssessmentQuestion_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AssessmentQuestion_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, SortOrder, QuestionText, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.AssessmentQuestion
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_AssessmentQuestion_Insert
      @NewId = Id baru (OUTPUT); @ActionBy = username pelaku (audit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AssessmentQuestion_Insert
    @SortOrder     INT,
    @QuestionText  NVARCHAR(300),
    @IsActive      BIT           = 1,
    @ActionBy      NVARCHAR(100) = NULL,
    @NewId         INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @QuestionText = LTRIM(RTRIM(@QuestionText));

    IF ISNULL(@QuestionText, N'') = N''                       THROW 50032, N'Question is required.', 1;
    IF @SortOrder IS NULL OR @SortOrder NOT BETWEEN 1 AND 999 THROW 50032, N'Sort order must be between 1 and 999.', 1;

    BEGIN TRY
        INSERT INTO dbo.AssessmentQuestion (SortOrder, QuestionText, IsActive, CreatedBy)
        VALUES (@SortOrder, @QuestionText, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50031, N'This question already exists.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   6. usp_AssessmentQuestion_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AssessmentQuestion_Update
    @Id            INT,
    @SortOrder     INT,
    @QuestionText  NVARCHAR(300),
    @IsActive      BIT           = 1,
    @ActionBy      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @QuestionText = LTRIM(RTRIM(@QuestionText));

    IF ISNULL(@QuestionText, N'') = N''                       THROW 50032, N'Question is required.', 1;
    IF @SortOrder IS NULL OR @SortOrder NOT BETWEEN 1 AND 999 THROW 50032, N'Sort order must be between 1 and 999.', 1;

    BEGIN TRY
        UPDATE dbo.AssessmentQuestion
        SET SortOrder    = @SortOrder,
            QuestionText = @QuestionText,
            IsActive     = ISNULL(@IsActive, IsActive),
            UpdatedAt    = SYSDATETIME(),
            UpdatedBy    = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50033, N'Question not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50031, N'This question already exists.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_AssessmentQuestion_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AssessmentQuestion_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AssessmentQuestion
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50033, N'Question not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: 12 pertanyaan, SortOrder 1..12, semua aktif
   SELECT SortOrder, QuestionText, IsActive FROM dbo.AssessmentQuestion ORDER BY SortOrder;

   -- 2) Insert lalu duplikat -> 50031 (tidak peka huruf besar/kecil)
   DECLARE @NewId INT;
   EXEC dbo.usp_AssessmentQuestion_Insert @SortOrder = 13, @QuestionText = N'Is a test question needed?',
        @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;
   EXEC dbo.usp_AssessmentQuestion_Insert @SortOrder = 14, @QuestionText = N'is a TEST question needed?';

   -- 3) Validasi -> 50032
   EXEC dbo.usp_AssessmentQuestion_Insert @SortOrder = 1, @QuestionText = N'   ';
   EXEC dbo.usp_AssessmentQuestion_Insert @SortOrder = 0, @QuestionText = N'X?';

   -- 4) List: search, sort, paging (12 + 1 baris uji -> 2 halaman pada PageSize 10)
   DECLARE @Total INT;
   EXEC dbo.usp_AssessmentQuestion_GetPaged @Search = N'budget', @TotalCount = @Total OUTPUT;   -- 1 baris
   SELECT @Total AS TotalCount;
   EXEC dbo.usp_AssessmentQuestion_GetPaged @PageNumber = 2, @TotalCount = @Total OUTPUT;       -- 3 baris

   -- 5) Update, soft delete; Id tidak ada -> 50033
   DECLARE @Id INT = (SELECT Id FROM dbo.AssessmentQuestion WHERE QuestionText = N'Is a test question needed?');
   EXEC dbo.usp_AssessmentQuestion_Update @Id = @Id, @SortOrder = 5, @QuestionText = N'Is a test question needed (rev)?', @ActionBy = N'uji';
   EXEC dbo.usp_AssessmentQuestion_SetActive @Id = @Id, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_AssessmentQuestion_GetById @Id = @Id;
   EXEC dbo.usp_AssessmentQuestion_SetActive @Id = 999999, @IsActive = 0;

   -- 6) Jalankan ulang script -> tetap 12 pertanyaan seed (tidak dobel).
   --    Bersihkan data uji:
   --    DELETE dbo.AssessmentQuestion WHERE QuestionText LIKE N'Is a test question needed%';
   ===================================================================== */
GO
/* ---------- end AssessmentQuestion.sql ---------- */
/* ---------- begin SurveyTemplateItem.sql ---------- */
PRINT N'[skema] SurveyTemplateItem.sql';
GO
/* =====================================================================
   SurveyTemplateItem.sql  -  Master item template survei kepuasan (T1; PRD MD-07, BR-47, 6.6)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Template per kategori (CAPEX, OPEX, LVE); isi awal ketiganya sama (BR-47).
     - Item dinilai skala 1-10 oleh Kabag; skor item = nilai / 10 (6.6). Item aktif di-snapshot
       ke survei saat dikirim (BR-48, dikerjakan di T6). "Note for Civil" adalah field teks tetap
       di survei, BUKAN item template.
     - SortOrder = urutan tampil di form survei (urutan kedua = Id).
     - Seed MERGE hanya MENAMBAH item yang belum ada (tidak menimpa perubahan).
     - Soft delete lewat SetActive (tanpa Delete).
   Error   : 50041 = Item duplikat pada kategori yang sama
             50042 = Input wajib kosong / tidak valid
             50043 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.SurveyTemplateItem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SurveyTemplateItem
    (
        Id         INT IDENTITY(1,1) NOT NULL,
        Category   VARCHAR(10)   NOT NULL,
        SortOrder  INT           NOT NULL,
        ItemText   NVARCHAR(200) NOT NULL,
        IsActive   BIT           NOT NULL CONSTRAINT DF_SurveyTemplateItem_IsActive  DEFAULT (1),
        CreatedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_SurveyTemplateItem_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy  NVARCHAR(100) NULL,
        UpdatedAt  DATETIME2(3)  NULL,
        UpdatedBy  NVARCHAR(100) NULL,
        CONSTRAINT PK_SurveyTemplateItem PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_SurveyTemplateItem_Category  CHECK (Category IN ('CAPEX', 'OPEX', 'LVE')),
        CONSTRAINT CK_SurveyTemplateItem_SortOrder CHECK (SortOrder BETWEEN 1 AND 999)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_SurveyTemplateItem_Category_Text' AND object_id = OBJECT_ID(N'dbo.SurveyTemplateItem'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_SurveyTemplateItem_Category_Text ON dbo.SurveyTemplateItem (Category, ItemText);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (5 item x 3 kategori, dari form "7. User Satisfaction (feedback after completion)")
   --------------------------------------------------------------------- */
MERGE dbo.SurveyTemplateItem AS t
USING (
        SELECT c.Category, i.SortOrder, i.ItemText
        FROM (VALUES ('CAPEX'), ('OPEX'), ('LVE')) AS c (Category)
             CROSS JOIN (VALUES
                (1, N'Compliance with user requirements'),
                (2, N'Work quality'),
                (3, N'Timeliness of completion'),
                (4, N'Communication and coordination'),
                (5, N'Site cleanliness and housekeeping')
             ) AS i (SortOrder, ItemText)
      ) AS s
   ON t.Category = s.Category AND t.ItemText = s.ItemText
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Category, SortOrder, ItemText, CreatedBy)
    VALUES (s.Category, s.SortOrder, s.ItemText, N'seed');
GO

/* ---------------------------------------------------------------------
   3. usp_SurveyTemplateItem_GetPaged
      Search (ItemText), filter kategori dan status, sorting whitelist, paging.
      @SortBy  : Category | SortOrder | ItemText | CreatedAt   (default Category = kategori lalu urutan)
      @SortDir : ASC | DESC                                    (default ASC)
      Kategori diurutkan sesuai PRD: CAPEX, OPEX, LVE (bukan alfabet).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SurveyTemplateItem_GetPaged
    @Category    VARCHAR(10)   = NULL,
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Category',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Category   = NULLIF(LTRIM(RTRIM(@Category)), '');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Category', N'SortOrder', N'ItemText', N'CreatedAt') THEN @SortBy ELSE N'Category' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.SurveyTemplateItem
    WHERE (@Category IS NULL OR Category = @Category)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR ItemText LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Category, SortOrder, ItemText, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.SurveyTemplateItem
    WHERE (@Category IS NULL OR Category = @Category)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR ItemText LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'ASC'  THEN CHARINDEX(',' + Category + ',', ',CAPEX,OPEX,LVE,') END ASC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'DESC' THEN CHARINDEX(',' + Category + ',', ',CAPEX,OPEX,LVE,') END DESC,
        CASE WHEN @SortBy = N'SortOrder' AND @SortDir = N'ASC'  THEN SortOrder END ASC,
        CASE WHEN @SortBy = N'SortOrder' AND @SortDir = N'DESC' THEN SortOrder END DESC,
        CASE WHEN @SortBy = N'ItemText'  AND @SortDir = N'ASC'  THEN ItemText  END ASC,
        CASE WHEN @SortBy = N'ItemText'  AND @SortDir = N'DESC' THEN ItemText  END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        CHARINDEX(',' + Category + ',', ',CAPEX,OPEX,LVE,') ASC, SortOrder ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   4. usp_SurveyTemplateItem_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SurveyTemplateItem_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Category, SortOrder, ItemText, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.SurveyTemplateItem
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_SurveyTemplateItem_Insert
      @NewId = Id baru (OUTPUT); @ActionBy = username pelaku (audit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SurveyTemplateItem_Insert
    @Category   VARCHAR(10),
    @SortOrder  INT,
    @ItemText   NVARCHAR(200),
    @IsActive   BIT           = 1,
    @ActionBy   NVARCHAR(100) = NULL,
    @NewId      INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Category = UPPER(LTRIM(RTRIM(@Category)));
    SET @ItemText = LTRIM(RTRIM(@ItemText));

    IF ISNULL(@Category, '') NOT IN ('CAPEX', 'OPEX', 'LVE')    THROW 50042, N'Category is required (CAPEX, OPEX, or LVE).', 1;
    IF ISNULL(@ItemText, N'') = N''                             THROW 50042, N'Item is required.', 1;
    IF @SortOrder IS NULL OR @SortOrder NOT BETWEEN 1 AND 999   THROW 50042, N'Sort order must be between 1 and 999.', 1;

    BEGIN TRY
        INSERT INTO dbo.SurveyTemplateItem (Category, SortOrder, ItemText, IsActive, CreatedBy)
        VALUES (@Category, @SortOrder, @ItemText, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50041, N'This item already exists for the selected category.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   6. usp_SurveyTemplateItem_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SurveyTemplateItem_Update
    @Id         INT,
    @Category   VARCHAR(10),
    @SortOrder  INT,
    @ItemText   NVARCHAR(200),
    @IsActive   BIT           = 1,
    @ActionBy   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Category = UPPER(LTRIM(RTRIM(@Category)));
    SET @ItemText = LTRIM(RTRIM(@ItemText));

    IF ISNULL(@Category, '') NOT IN ('CAPEX', 'OPEX', 'LVE')    THROW 50042, N'Category is required (CAPEX, OPEX, or LVE).', 1;
    IF ISNULL(@ItemText, N'') = N''                             THROW 50042, N'Item is required.', 1;
    IF @SortOrder IS NULL OR @SortOrder NOT BETWEEN 1 AND 999   THROW 50042, N'Sort order must be between 1 and 999.', 1;

    BEGIN TRY
        UPDATE dbo.SurveyTemplateItem
        SET Category  = @Category,
            SortOrder = @SortOrder,
            ItemText  = @ItemText,
            IsActive  = ISNULL(@IsActive, IsActive),
            UpdatedAt = SYSDATETIME(),
            UpdatedBy = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50043, N'Survey item not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50041, N'This item already exists for the selected category.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_SurveyTemplateItem_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SurveyTemplateItem_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.SurveyTemplateItem
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50043, N'Survey item not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: 15 baris (5 item x CAPEX, OPEX, LVE), semua aktif
   SELECT Category, COUNT(*) AS Jumlah FROM dbo.SurveyTemplateItem GROUP BY Category;
   SELECT Category, SortOrder, ItemText FROM dbo.SurveyTemplateItem
   ORDER BY CHARINDEX(',' + Category + ',', ',CAPEX,OPEX,LVE,'), SortOrder;

   -- 2) Insert item khusus CAPEX; teks sama di OPEX boleh; duplikat di CAPEX -> 50041
   DECLARE @NewId INT;
   EXEC dbo.usp_SurveyTemplateItem_Insert @Category = 'capex', @SortOrder = 6, @ItemText = N'Safety compliance',
        @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   EXEC dbo.usp_SurveyTemplateItem_GetById @Id = @NewId;          -- Category = CAPEX
   EXEC dbo.usp_SurveyTemplateItem_Insert @Category = 'OPEX',  @SortOrder = 6, @ItemText = N'Safety compliance';   -- boleh
   EXEC dbo.usp_SurveyTemplateItem_Insert @Category = 'CAPEX', @SortOrder = 7, @ItemText = N'safety COMPLIANCE';   -- 50041

   -- 3) Validasi -> 50042
   EXEC dbo.usp_SurveyTemplateItem_Insert @Category = 'XYZ', @SortOrder = 1, @ItemText = N'A';
   EXEC dbo.usp_SurveyTemplateItem_Insert @Category = 'LVE', @SortOrder = 1, @ItemText = N'  ';
   EXEC dbo.usp_SurveyTemplateItem_Insert @Category = 'LVE', @SortOrder = 0, @ItemText = N'A';

   -- 4) List: filter kategori, default urut CAPEX -> OPEX -> LVE lalu SortOrder
   DECLARE @Total INT;
   EXEC dbo.usp_SurveyTemplateItem_GetPaged @Category = 'CAPEX', @TotalCount = @Total OUTPUT;   -- 6 baris
   SELECT @Total AS TotalCount;
   EXEC dbo.usp_SurveyTemplateItem_GetPaged @TotalCount = @Total OUTPUT;                        -- halaman 1: CAPEX (6) + OPEX (4)

   -- 5) Update, soft delete; Id tidak ada -> 50043
   DECLARE @Id INT = (SELECT Id FROM dbo.SurveyTemplateItem WHERE Category = 'CAPEX' AND ItemText = N'Safety compliance');
   EXEC dbo.usp_SurveyTemplateItem_Update @Id = @Id, @Category = 'CAPEX', @SortOrder = 3, @ItemText = N'Safety compliance (rev)', @ActionBy = N'uji';
   EXEC dbo.usp_SurveyTemplateItem_SetActive @Id = @Id, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_SurveyTemplateItem_GetById @Id = @Id;
   EXEC dbo.usp_SurveyTemplateItem_SetActive @Id = 999999, @IsActive = 0;

   -- 6) Jalankan ulang script -> tetap 15 item seed (tidak dobel).
   --    Bersihkan data uji:
   --    DELETE dbo.SurveyTemplateItem WHERE ItemText LIKE N'Safety compliance%';
   ===================================================================== */
GO
/* ---------- end SurveyTemplateItem.sql ---------- */
/* ---------- begin SubCategory.sql ---------- */
PRINT N'[skema] SubCategory.sql';
GO
/* =====================================================================
   SubCategory.sql  -  Master sub-kategori pekerjaan per kategori (T1; PRD MD-01, BR-02, BR-61, 1.1, 6.1)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Dipakai bersama semua Company (BR-61), tanpa CoCode.
     - Requester memilih sub-kategori secara cascade dari kategori (6.1); list aktif per kategori
       lewat usp_SubCategory_GetActiveByCategory (dipakai T2).
     - Code dan Category TIDAK bisa diubah setelah dibuat: Code dipakai modul lain sebagai kunci
       (mis. EMERGENCY_MAINT / PREVENTIVE_MAINT untuk jalur T7), Category menjaga konsistensi request
       yang sudah memakai sub-kategori tersebut.
     - Name unik per kategori; SortOrder = urutan di dropdown (urutan kedua = Id).
     - Seed MERGE hanya MENAMBAH Code yang belum ada (tidak menimpa perubahan).
     - Soft delete lewat SetActive (tanpa Delete).
   Error   : 50061 = Code duplikat
             50062 = Input wajib kosong / tidak valid
             50063 = Data tidak ditemukan
             50064 = Name duplikat pada kategori yang sama
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.SubCategory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SubCategory
    (
        Id         INT IDENTITY(1,1) NOT NULL,
        Category   VARCHAR(10)   NOT NULL,
        Code       VARCHAR(30)   NOT NULL,
        Name       NVARCHAR(100) NOT NULL,
        SortOrder  INT           NOT NULL,
        IsActive   BIT           NOT NULL CONSTRAINT DF_SubCategory_IsActive  DEFAULT (1),
        CreatedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_SubCategory_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy  NVARCHAR(100) NULL,
        UpdatedAt  DATETIME2(3)  NULL,
        UpdatedBy  NVARCHAR(100) NULL,
        CONSTRAINT PK_SubCategory PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_SubCategory_Category  CHECK (Category IN ('CAPEX', 'OPEX', 'LVE')),
        CONSTRAINT CK_SubCategory_Code      CHECK (Code NOT LIKE '%[^A-Z0-9_]%' COLLATE Latin1_General_BIN),
        CONSTRAINT CK_SubCategory_SortOrder CHECK (SortOrder BETWEEN 1 AND 999)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_SubCategory_Code' AND object_id = OBJECT_ID(N'dbo.SubCategory'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_SubCategory_Code ON dbo.SubCategory (Code);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_SubCategory_Category_Name' AND object_id = OBJECT_ID(N'dbo.SubCategory'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_SubCategory_Category_Name ON dbo.SubCategory (Category, Name);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (11 baris dari appendix form, PRD 1.1)
   --------------------------------------------------------------------- */
MERGE dbo.SubCategory AS t
USING (VALUES
        ('CAPEX', 'CONSTRUCTION_PROJECT', N'Construction project',        1),
        ('CAPEX', 'FACILITY_EXPANSION',   N'Facility expansion',          2),
        ('CAPEX', 'MAJOR_RENOVATION',     N'Major renovation',            3),
        ('CAPEX', 'ASSET_UPGRADE',        N'Asset upgrade',               4),
        ('OPEX',  'PREVENTIVE_MAINT',     N'Preventive maintenance',      1),
        ('OPEX',  'CORRECTIVE_MAINT',     N'Corrective maintenance',      2),
        ('OPEX',  'EMERGENCY_MAINT',      N'Emergency maintenance',       3),
        ('OPEX',  'CIVIL_IMPROVEMENT',    N'Civil improvement',           4),
        ('LVE',   'MINOR_CIVIL_WORKS',    N'Minor civil works',           1),
        ('LVE',   'JDI_REQUISITION',      N'JDI requisition',             2),
        ('LVE',   'NON_VALUE_ADDED',      N'Non value-added requisition', 3)
      ) AS s (Category, Code, Name, SortOrder)
   ON t.Code = s.Code
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Category, Code, Name, SortOrder, CreatedBy)
    VALUES (s.Category, s.Code, s.Name, s.SortOrder, N'seed');
GO

/* ---------------------------------------------------------------------
   3. usp_SubCategory_GetPaged
      Search (Code/Name), filter kategori dan status, sorting whitelist, paging.
      @SortBy  : Category | SortOrder | Code | Name | CreatedAt   (default Category = kategori lalu urutan)
      @SortDir : ASC | DESC                                       (default ASC)
      Kategori diurutkan sesuai PRD: CAPEX, OPEX, LVE (bukan alfabet).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SubCategory_GetPaged
    @Category    VARCHAR(10)   = NULL,
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Category',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Category   = NULLIF(LTRIM(RTRIM(@Category)), '');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Category', N'SortOrder', N'Code', N'Name', N'CreatedAt') THEN @SortBy ELSE N'Category' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.SubCategory
    WHERE (@Category IS NULL OR Category = @Category)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Category, Code, Name, SortOrder, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.SubCategory
    WHERE (@Category IS NULL OR Category = @Category)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'ASC'  THEN CHARINDEX(',' + Category + ',', ',CAPEX,OPEX,LVE,') END ASC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'DESC' THEN CHARINDEX(',' + Category + ',', ',CAPEX,OPEX,LVE,') END DESC,
        CASE WHEN @SortBy = N'SortOrder' AND @SortDir = N'ASC'  THEN SortOrder END ASC,
        CASE WHEN @SortBy = N'SortOrder' AND @SortDir = N'DESC' THEN SortOrder END DESC,
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'ASC'  THEN Code      END ASC,
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'DESC' THEN Code      END DESC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        CHARINDEX(',' + Category + ',', ',CAPEX,OPEX,LVE,') ASC, SortOrder ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   4. usp_SubCategory_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SubCategory_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Category, Code, Name, SortOrder, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.SubCategory
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_SubCategory_GetActiveByCategory  (dropdown cascade di form request, T2)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SubCategory_GetActiveByCategory
    @Category VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Category, Code, Name, SortOrder
    FROM dbo.SubCategory
    WHERE Category = UPPER(LTRIM(RTRIM(@Category)))
      AND IsActive = 1
    ORDER BY SortOrder, Id;
END
GO

/* ---------------------------------------------------------------------
   6. usp_SubCategory_Insert
      @NewId = Id baru (OUTPUT); @ActionBy = username pelaku (audit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SubCategory_Insert
    @Category   VARCHAR(10),
    @Code       VARCHAR(30),
    @Name       NVARCHAR(100),
    @SortOrder  INT,
    @IsActive   BIT           = 1,
    @ActionBy   NVARCHAR(100) = NULL,
    @NewId      INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Category = UPPER(LTRIM(RTRIM(@Category)));
    SET @Code     = UPPER(LTRIM(RTRIM(@Code)));
    SET @Name     = LTRIM(RTRIM(@Name));

    IF ISNULL(@Category, '') NOT IN ('CAPEX', 'OPEX', 'LVE')    THROW 50062, N'Category is required (CAPEX, OPEX, or LVE).', 1;
    IF ISNULL(@Code, '') = ''                                   THROW 50062, N'Code is required.', 1;
    IF @Code LIKE '%[^A-Z0-9_]%' COLLATE Latin1_General_BIN     THROW 50062, N'Code may only contain letters, numbers, and underscores.', 1;
    IF ISNULL(@Name, N'') = N''                                 THROW 50062, N'Name is required.', 1;
    IF @SortOrder IS NULL OR @SortOrder NOT BETWEEN 1 AND 999   THROW 50062, N'Sort order must be between 1 and 999.', 1;

    BEGIN TRY
        INSERT INTO dbo.SubCategory (Category, Code, Name, SortOrder, IsActive, CreatedBy)
        VALUES (@Category, @Code, @Name, @SortOrder, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627) AND ERROR_MESSAGE() LIKE N'%UX_SubCategory_Code%'
            THROW 50061, N'Code is already in use.', 1;
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50064, N'This sub-category already exists for the selected category.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_SubCategory_Update  (Code dan Category tidak bisa diubah)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SubCategory_Update
    @Id         INT,
    @Name       NVARCHAR(100),
    @SortOrder  INT,
    @IsActive   BIT           = 1,
    @ActionBy   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name = LTRIM(RTRIM(@Name));

    IF ISNULL(@Name, N'') = N''                                 THROW 50062, N'Name is required.', 1;
    IF @SortOrder IS NULL OR @SortOrder NOT BETWEEN 1 AND 999   THROW 50062, N'Sort order must be between 1 and 999.', 1;

    BEGIN TRY
        UPDATE dbo.SubCategory
        SET Name      = @Name,
            SortOrder = @SortOrder,
            IsActive  = ISNULL(@IsActive, IsActive),
            UpdatedAt = SYSDATETIME(),
            UpdatedBy = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50063, N'Sub-category not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50064, N'This sub-category already exists for the selected category.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   8. usp_SubCategory_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SubCategory_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.SubCategory
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50063, N'Sub-category not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: CAPEX 4, OPEX 4, LVE 3 = 11 baris, semua aktif
   SELECT Category, COUNT(*) AS Jumlah FROM dbo.SubCategory GROUP BY Category;
   SELECT Category, SortOrder, Code, Name FROM dbo.SubCategory
   ORDER BY CHARINDEX(',' + Category + ',', ',CAPEX,OPEX,LVE,'), SortOrder;

   -- 2) Insert + normalisasi (Category/Code jadi huruf besar)
   DECLARE @NewId INT;
   EXEC dbo.usp_SubCategory_Insert @Category = 'capex', @Code = 'road_works', @Name = N'Road works', @SortOrder = 5,
        @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   EXEC dbo.usp_SubCategory_GetById @Id = @NewId;                  -- CAPEX, ROAD_WORKS

   -- 3) Duplikat
   EXEC dbo.usp_SubCategory_Insert @Category = 'OPEX',  @Code = 'ROAD_WORKS', @Name = N'Road works', @SortOrder = 5;   -- 50061 (Code)
   EXEC dbo.usp_SubCategory_Insert @Category = 'CAPEX', @Code = 'ROAD_2',     @Name = N'road WORKS', @SortOrder = 6;   -- 50064 (Name)
   EXEC dbo.usp_SubCategory_Insert @Category = 'OPEX',  @Code = 'ROAD_OPEX',  @Name = N'Road works', @SortOrder = 5;   -- boleh (kategori lain)

   -- 4) Validasi -> 50062
   EXEC dbo.usp_SubCategory_Insert @Category = 'XYZ', @Code = 'A', @Name = N'A', @SortOrder = 1;
   EXEC dbo.usp_SubCategory_Insert @Category = 'LVE', @Code = 'A-B', @Name = N'A', @SortOrder = 1;
   EXEC dbo.usp_SubCategory_Insert @Category = 'LVE', @Code = 'AB', @Name = N'  ', @SortOrder = 1;
   EXEC dbo.usp_SubCategory_Insert @Category = 'LVE', @Code = 'AB', @Name = N'A', @SortOrder = 0;

   -- 5) List dan dropdown cascade
   DECLARE @Total INT;
   EXEC dbo.usp_SubCategory_GetPaged @Category = 'CAPEX', @TotalCount = @Total OUTPUT;   -- 5 baris
   SELECT @Total AS TotalCount;
   EXEC dbo.usp_SubCategory_GetPaged @Search = N'maint', @TotalCount = @Total OUTPUT;    -- 3 baris OPEX
   EXEC dbo.usp_SubCategory_GetActiveByCategory 'opex';                                  -- 5 baris aktif, urut SortOrder

   -- 6) Update (Name ke nama yang sudah ada di kategori sama -> 50064), soft delete, tidak ditemukan -> 50063
   DECLARE @Id INT = (SELECT Id FROM dbo.SubCategory WHERE Code = 'ROAD_WORKS');
   EXEC dbo.usp_SubCategory_Update @Id = @Id, @Name = N'Asset upgrade', @SortOrder = 5;                     -- 50064
   EXEC dbo.usp_SubCategory_Update @Id = @Id, @Name = N'Road works (rev)', @SortOrder = 9, @ActionBy = N'uji';
   EXEC dbo.usp_SubCategory_SetActive @Id = @Id, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_SubCategory_GetActiveByCategory 'CAPEX';                                 -- 4 baris (ROAD_WORKS tidak muncul)
   EXEC dbo.usp_SubCategory_SetActive @Id = 999999, @IsActive = 0;                       -- 50063

   -- 7) Jalankan ulang script -> tetap 11 baris seed (tidak dobel).
   --    Bersihkan data uji:
   --    DELETE dbo.SubCategory WHERE Code IN ('ROAD_WORKS', 'ROAD_OPEX');
   ===================================================================== */
GO
/* ---------- end SubCategory.sql ---------- */
/* ---------- begin Unit.sql ---------- */
PRINT N'[skema] Unit.sql';
GO
/* =====================================================================
   Unit.sql  -  Master data Satuan (T5-2; PRD MD-04, BR-61)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan : Dipakai bersama ABL dan NKM (BR-61). Pengelola: civil, administrator (hak di Controller).
             Satuan item actual cost diketik bebas; master ini hanya daftar saran (Keputusan 16-11-2026).
             Nama unik (tidak peka huruf besar/kecil sesuai collation DB). Soft delete lewat SetActive.
             Seed MERGE hanya MENAMBAH nama yang belum ada (tidak menimpa perubahan).
   Error   : 50091 = Nama satuan duplikat
             50092 = Input wajib kosong / tidak valid
             50093 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Unit', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Unit
    (
        Id           INT IDENTITY(1,1) NOT NULL,
        Name         NVARCHAR(30)  NOT NULL,
        Description  NVARCHAR(100) NULL,
        IsActive     BIT           NOT NULL CONSTRAINT DF_Unit_IsActive  DEFAULT (1),
        CreatedAt    DATETIME2(3)  NOT NULL CONSTRAINT DF_Unit_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy    NVARCHAR(100) NULL,
        UpdatedAt    DATETIME2(3)  NULL,
        UpdatedBy    NVARCHAR(100) NULL,
        CONSTRAINT PK_Unit PRIMARY KEY CLUSTERED (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Unit_Name' AND object_id = OBJECT_ID(N'dbo.Unit'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Unit_Name ON dbo.Unit (Name);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (MD-04; hanya menambah yang belum ada)
   --------------------------------------------------------------------- */
MERGE dbo.Unit AS t
USING (VALUES
        (N'm',    N'Meter'),
        (N'm²',   N'Square meter'),
        (N'm³',   N'Cubic meter'),
        (N'kg',   N'Kilogram'),
        (N'ton',  N'Ton'),
        (N'unit', N'Unit'),
        (N'set',  N'Set'),
        (N'lot',  N'Lot'),
        (N'ls',   N'Lump sum'),
        (N'hari', N'Day'),
        (N'jam',  N'Hour')
      ) AS s (Name, Description)
   ON t.Name = s.Name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Name, Description, CreatedBy)
    VALUES (s.Name, s.Description, N'seed');
GO

/* ---------------------------------------------------------------------
   3. usp_Unit_GetPaged
      @SortBy  : Name | CreatedAt   (default Name) · @SortDir : ASC | DESC (default ASC)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_GetPaged
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Name',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Name', N'CreatedAt') THEN @SortBy ELSE N'Name' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.Unit
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Name LIKE N'%' + @Search + N'%' OR Description LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Name, Description, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Unit
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Name LIKE N'%' + @Search + N'%' OR Description LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Name ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   4. usp_Unit_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Name, Description, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Unit
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Unit_GetActive  (daftar saran satuan pada form actual cost)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_GetActive
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Name, Description
    FROM dbo.Unit
    WHERE IsActive = 1
    ORDER BY Name, Id;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Unit_Insert  (@NewId OUTPUT; @ActionBy = username pelaku)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_Insert
    @Name         NVARCHAR(30),
    @Description  NVARCHAR(100) = NULL,
    @IsActive     BIT           = 1,
    @ActionBy     NVARCHAR(100) = NULL,
    @NewId        INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name        = LTRIM(RTRIM(@Name));
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');

    IF ISNULL(@Name, N'') = N'' THROW 50092, N'Unit name is required.', 1;

    BEGIN TRY
        INSERT INTO dbo.Unit (Name, Description, IsActive, CreatedBy)
        VALUES (@Name, @Description, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50091, N'Unit name is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_Unit_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_Update
    @Id           INT,
    @Name         NVARCHAR(30),
    @Description  NVARCHAR(100) = NULL,
    @IsActive     BIT           = 1,
    @ActionBy     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name        = LTRIM(RTRIM(@Name));
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');

    IF ISNULL(@Name, N'') = N'' THROW 50092, N'Unit name is required.', 1;

    BEGIN TRY
        UPDATE dbo.Unit
        SET Name        = @Name,
            Description = @Description,
            IsActive    = ISNULL(@IsActive, IsActive),
            UpdatedAt   = SYSDATETIME(),
            UpdatedBy   = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50093, N'Unit not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50091, N'Unit name is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   8. usp_Unit_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Unit
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50093, N'Unit not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; baris error dijalankan sendiri-sendiri)

   -- 1) Seed: 11 satuan aktif (MD-04)
   SELECT * FROM dbo.Unit ORDER BY Name;
   EXEC dbo.usp_Unit_GetActive;

   -- 2) Insert lalu duplikat (beda huruf besar/kecil) -> 50091; kosong -> 50092
   DECLARE @NewId INT;
   EXEC dbo.usp_Unit_Insert @Name = N'roll', @Description = N'Roll', @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;
   EXEC dbo.usp_Unit_Insert @Name = N'ROLL';                                  -- 50091
   EXEC dbo.usp_Unit_Insert @Name = N'  ';                                    -- 50092

   -- 3) List, update, nonaktif (hilang dari GetActive), Id tidak ada -> 50093
   DECLARE @Total INT; EXEC dbo.usp_Unit_GetPaged @Search = N'm', @TotalCount = @Total OUTPUT; SELECT @Total AS TotalCount;
   EXEC dbo.usp_Unit_Update @Id = @NewId, @Name = N'roll', @Description = N'Roll (paper)', @ActionBy = N'uji';
   EXEC dbo.usp_Unit_SetActive @Id = @NewId, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_Unit_SetActive @Id = 999999, @IsActive = 0;                  -- 50093
   ===================================================================== */
GO
/* ---------- end Unit.sql ---------- */
/* ---------- begin Vendor.sql ---------- */
PRINT N'[skema] Vendor.sql';
GO
/* =====================================================================
   Vendor.sql  -  Master data Vendor (T4-1; PRD MD-03, BR-11)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan : Vendor dipakai bersama ABL dan NKM (Purchasing melayani keduanya). Isi awal kosong (MD-03).
             Pengelola: purchasing, civil, administrator (hak di Controller).
             Code unik (tidak peka huruf besar/kecil sesuai collation DB). Soft delete lewat SetActive.
   Error   : 50081 = Code duplikat
             50082 = Input wajib kosong / tidak valid
             50083 = Data tidak ditemukan
             50084 = Nomor vendor ERP duplikat
             ErpVendorNo = nomor vendor di ERP; opsional, unik bila diisi (disimpan huruf besar).
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Vendor', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Vendor
    (
        Id             INT IDENTITY(1,1) NOT NULL,
        Code           VARCHAR(20)    NOT NULL,
        ErpVendorNo    VARCHAR(30)    NULL,       -- nomor vendor di ERP (opsional, unik bila diisi)
        Name           NVARCHAR(150)  NOT NULL,
        ContactPerson  NVARCHAR(100)  NULL,
        Phone          VARCHAR(30)    NULL,
        Email          VARCHAR(100)   NULL,
        Address        NVARCHAR(300)  NULL,
        IsActive       BIT            NOT NULL CONSTRAINT DF_Vendor_IsActive  DEFAULT (1),
        CreatedAt      DATETIME2(3)   NOT NULL CONSTRAINT DF_Vendor_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy      NVARCHAR(100)  NULL,
        UpdatedAt      DATETIME2(3)   NULL,
        UpdatedBy      NVARCHAR(100)  NULL,
        CONSTRAINT PK_Vendor PRIMARY KEY CLUSTERED (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Vendor_Code' AND object_id = OBJECT_ID(N'dbo.Vendor'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Vendor_Code ON dbo.Vendor (Code);
END
GO

-- Migrasi: tabel yang sudah dibuat sebelum kolom ErpVendorNo ada
IF COL_LENGTH(N'dbo.Vendor', N'ErpVendorNo') IS NULL
BEGIN
    ALTER TABLE dbo.Vendor ADD ErpVendorNo VARCHAR(30) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Vendor_ErpVendorNo' AND object_id = OBJECT_ID(N'dbo.Vendor'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Vendor_ErpVendorNo ON dbo.Vendor (ErpVendorNo) WHERE ErpVendorNo IS NOT NULL;
END
GO

/* ---------------------------------------------------------------------
   2. usp_Vendor_GetPaged
      Search (Code, Name, ContactPerson), filter status, sorting whitelist, paging.
      @SortBy  : Code | Name | CreatedAt   (default Name)
      @SortDir : ASC | DESC                (default ASC)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_GetPaged
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Name',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Code', N'Name', N'CreatedAt') THEN @SortBy ELSE N'Name' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.Vendor
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%'
                             OR ErpVendorNo LIKE N'%' + @Search + N'%' OR ContactPerson LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Code, ErpVendorNo, Name, ContactPerson, Phone, Email, Address, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Vendor
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%'
                             OR ErpVendorNo LIKE N'%' + @Search + N'%' OR ContactPerson LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'ASC'  THEN Code      END ASC,
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'DESC' THEN Code      END DESC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Name ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   3. usp_Vendor_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, ErpVendorNo, Name, ContactPerson, Phone, Email, Address, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Vendor
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Vendor_GetActive  (pilihan dropdown kontrak; @IncludeId = vendor terpilih walau nonaktif)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_GetActive
    @IncludeId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, ErpVendorNo, Name
    FROM dbo.Vendor
    WHERE IsActive = 1 OR Id = @IncludeId
    ORDER BY Name, Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Vendor_Insert  (@NewId OUTPUT; @ActionBy = username pelaku)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_Insert
    @Code           VARCHAR(20),
    @Name           NVARCHAR(150),
    @ErpVendorNo    VARCHAR(30)   = NULL,
    @ContactPerson  NVARCHAR(100) = NULL,
    @Phone          VARCHAR(30)   = NULL,
    @Email          VARCHAR(100)  = NULL,
    @Address        NVARCHAR(300) = NULL,
    @IsActive       BIT           = 1,
    @ActionBy       NVARCHAR(100) = NULL,
    @NewId          INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code          = UPPER(LTRIM(RTRIM(@Code)));
    SET @Name          = LTRIM(RTRIM(@Name));
    SET @ContactPerson = NULLIF(LTRIM(RTRIM(@ContactPerson)), N'');
    SET @Phone         = NULLIF(LTRIM(RTRIM(@Phone)), '');
    SET @Email         = NULLIF(LTRIM(RTRIM(@Email)), '');
    SET @Address       = NULLIF(LTRIM(RTRIM(@Address)), N'');
    SET @ErpVendorNo   = NULLIF(UPPER(LTRIM(RTRIM(@ErpVendorNo))), '');

    IF ISNULL(@Code, '') = ''   THROW 50082, N'Vendor code is required.', 1;
    IF ISNULL(@Name, N'') = N'' THROW 50082, N'Vendor name is required.', 1;
    IF @Email IS NOT NULL AND @Email NOT LIKE '%_@_%._%'
        THROW 50082, N'Email is invalid.', 1;

    BEGIN TRY
        INSERT INTO dbo.Vendor (Code, ErpVendorNo, Name, ContactPerson, Phone, Email, Address, IsActive, CreatedBy)
        VALUES (@Code, @ErpVendorNo, @Name, @ContactPerson, @Phone, @Email, @Address, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627) AND ERROR_MESSAGE() LIKE N'%UX_Vendor_ErpVendorNo%'
            THROW 50084, N'ERP vendor number is already in use.', 1;
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50081, N'Vendor code is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   6. usp_Vendor_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_Update
    @Id             INT,
    @Code           VARCHAR(20),
    @Name           NVARCHAR(150),
    @ErpVendorNo    VARCHAR(30)   = NULL,
    @ContactPerson  NVARCHAR(100) = NULL,
    @Phone          VARCHAR(30)   = NULL,
    @Email          VARCHAR(100)  = NULL,
    @Address        NVARCHAR(300) = NULL,
    @IsActive       BIT           = 1,
    @ActionBy       NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code          = UPPER(LTRIM(RTRIM(@Code)));
    SET @Name          = LTRIM(RTRIM(@Name));
    SET @ContactPerson = NULLIF(LTRIM(RTRIM(@ContactPerson)), N'');
    SET @Phone         = NULLIF(LTRIM(RTRIM(@Phone)), '');
    SET @Email         = NULLIF(LTRIM(RTRIM(@Email)), '');
    SET @Address       = NULLIF(LTRIM(RTRIM(@Address)), N'');
    SET @ErpVendorNo   = NULLIF(UPPER(LTRIM(RTRIM(@ErpVendorNo))), '');

    IF ISNULL(@Code, '') = ''   THROW 50082, N'Vendor code is required.', 1;
    IF ISNULL(@Name, N'') = N'' THROW 50082, N'Vendor name is required.', 1;
    IF @Email IS NOT NULL AND @Email NOT LIKE '%_@_%._%'
        THROW 50082, N'Email is invalid.', 1;

    BEGIN TRY
        UPDATE dbo.Vendor
        SET Code          = @Code,
            ErpVendorNo   = @ErpVendorNo,
            Name          = @Name,
            ContactPerson = @ContactPerson,
            Phone         = @Phone,
            Email         = @Email,
            Address       = @Address,
            IsActive      = ISNULL(@IsActive, IsActive),
            UpdatedAt     = SYSDATETIME(),
            UpdatedBy     = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50083, N'Vendor not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627) AND ERROR_MESSAGE() LIKE N'%UX_Vendor_ErpVendorNo%'
            THROW 50084, N'ERP vendor number is already in use.', 1;
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50081, N'Vendor code is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_Vendor_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Vendor
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50083, N'Vendor not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok; baris error dijalankan sendiri-sendiri)

   -- 1) Insert, lalu duplikat (beda huruf besar/kecil) -> 50081
   DECLARE @NewId INT;
   EXEC dbo.usp_Vendor_Insert @Code = 'v-001', @Name = N'PT Uji Konstruksi', @ContactPerson = N'Budi',
        @Phone = '0811', @Email = 'budi@uji.co.id', @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;                                                  -- Code tersimpan 'V-001'
   EXEC dbo.usp_Vendor_Insert @Code = 'V-001', @Name = N'Lain';              -- 50081

   -- 1b) Nomor vendor ERP: opsional; diisi -> unik (50084); dua vendor tanpa nomor ERP -> boleh
   EXEC dbo.usp_Vendor_Insert @Code = 'V-010', @Name = N'PT ERP Satu', @ErpVendorNo = 'erp-1001';   -- tersimpan 'ERP-1001'
   EXEC dbo.usp_Vendor_Insert @Code = 'V-011', @Name = N'PT ERP Dua',  @ErpVendorNo = 'ERP-1001';   -- 50084
   EXEC dbo.usp_Vendor_Insert @Code = 'V-012', @Name = N'PT Tanpa ERP';                             -- boleh
   DECLARE @T INT; EXEC dbo.usp_Vendor_GetPaged @Search = N'1001', @TotalCount = @T OUTPUT;           -- V-010 muncul

   -- 2) Validasi -> 50082
   EXEC dbo.usp_Vendor_Insert @Code = ' ', @Name = N'A';
   EXEC dbo.usp_Vendor_Insert @Code = 'V-002', @Name = N'A', @Email = 'bukan-email';

   -- 3) List + lookup aktif
   DECLARE @Total INT;
   EXEC dbo.usp_Vendor_GetPaged @Search = N'uji', @IsActive = 1, @TotalCount = @Total OUTPUT;
   SELECT @Total AS TotalCount;
   EXEC dbo.usp_Vendor_GetActive;

   -- 4) Update, nonaktifkan (hilang dari GetActive kecuali @IncludeId), Id tidak ada -> 50083
   EXEC dbo.usp_Vendor_Update @Id = 1, @Code = 'V-001', @Name = N'PT Uji Konstruksi (Rev)', @ActionBy = N'uji';
   EXEC dbo.usp_Vendor_SetActive @Id = 1, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_Vendor_GetActive @IncludeId = 1;                             -- tetap muncul
   EXEC dbo.usp_Vendor_SetActive @Id = 1, @IsActive = 1, @ActionBy = N'uji';
   EXEC dbo.usp_Vendor_SetActive @Id = 999999, @IsActive = 0;                -- 50083
   ===================================================================== */
GO
/* ---------- end Vendor.sql ---------- */
/* ---------- begin Request.sql ---------- */
PRINT N'[skema] Request.sql';
GO
/* =====================================================================
   Request.sql  -  Request / Business Case: DRAFT (T2-1; PRD 3.1, 6.1, 6.5, BR-01, BR-02, BR-28, BR-40,
                   BR-42..BR-46, BR-55, BR-56, BR-61, ST-01, ST-03)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Prasyarat: Config.sql, Scope.sql, SubCategory.sql, Location.sql, AssessmentQuestion.sql,
              AttachmentType.sql; hak baca ke database [home] (users, app_employees,
              APP_Departments, APP_SubDepartments).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - T2-1 hanya Draft: buat/ubah draft, jawaban Environment Assessment, lampiran tahap REQUEST,
       list dan detail. Submit (nomor, snapshot approval) = T2-2; approval = T2-3.
     - Save Draft minimal: wajib Title + Category; field lain boleh kosong, tetapi bila diisi
       divalidasi. Kelengkapan penuh (field wajib, assessment, ROI CAPEX, foto area) dicek saat Submit.
     - CoCode dan DepartmentID request diambil dari data karyawan requester (BR-40, BR-56) dan
       tidak berubah saat draft diubah. Cost center = APP_SubDepartments milik DepartmentID itu
       (Disabled = 0). PIC = karyawan aktif (ResignDate) pada DepartmentID itu; kunci EmployeeCode.
     - Lingkup data: semua SP baca/ubah membatasi lewat dbo.fn_User_AllowedDepartments(@Username).
       Hak per role (siapa boleh buat/ubah) di Controller (RoleAuthorize).
     - Relasi, folder lampiran, dan URL memakai Id internal, bukan nomor request (BR-55).
     - Lampiran tidak dihapus fisik; hanya dinonaktifkan (BR-46).
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request / lampiran tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.ProjectRequest
      Status (ST): DRAFT (ST-01), WAITING_APPROVAL (ST-02), RETURNED (ST-03), FEASIBILITY (ST-04),
      DOC_PREPARATION (ST-05), MGMT_APPROVAL (ST-06), PLANNING (ST-08), PROCUREMENT (ST-09),
      SCHEDULING (ST-10), IN_PROGRESS (ST-11), BAPP_REVIEW (ST-12), CLOSED (ST-13),
      SURVEY_COMPLETED (ST-14), REJECTED (ST-15), CANCELLED (ST-16).
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectRequest', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectRequest
    (
        Id                     INT IDENTITY(1,1) NOT NULL,
        CoCode                 VARCHAR(10)    NOT NULL,
        DepartmentID           INT            NOT NULL,   -- home..APP_Departments (tanpa FK)
        RequestNo              VARCHAR(40)    NULL,       -- diisi saat Submit (T2-2)
        Status                 VARCHAR(20)    NOT NULL CONSTRAINT DF_ProjectRequest_Status DEFAULT ('DRAFT'),
        RequesterUsername      NVARCHAR(100)  NOT NULL,
        RequesterEmployeeCode  VARCHAR(30)    NOT NULL,
        PicEmployeeCode        VARCHAR(30)    NULL,
        Title                  NVARCHAR(200)  NOT NULL,
        Category               VARCHAR(10)    NOT NULL,
        SubCategoryId          INT            NULL,
        BudgetRemarks          VARCHAR(12)    NULL,
        SubDepartmentID        INT            NULL,       -- cost center, home..APP_SubDepartments (tanpa FK)
        LocationId             INT            NULL,
        TargetCompletionDate   DATE           NULL,
        AreaLength             DECIMAL(10, 2) NULL,
        AreaWidth              DECIMAL(10, 2) NULL,
        AreaSize               AS CAST(AreaLength * AreaWidth AS DECIMAL(18, 2)) PERSISTED,
        BudgetExpectation      DECIMAL(18, 2) NULL,
        Background             NVARCHAR(2000) NULL,
        Objective              NVARCHAR(2000) NULL,
        OperationalImpact      NVARCHAR(2000) NULL,
        RiskIfNotApproved      NVARCHAR(2000) NULL,
        ExpectedBenefits       NVARCHAR(2000) NULL,
        Alternatives           NVARCHAR(2000) NULL,
        SpecialNote            NVARCHAR(2000) NULL,
        ExpectedRoiPercent     DECIMAL(9, 2)  NULL,
        RoiExplanation         NVARCHAR(2000) NULL,
        AdditionalInfo         NVARCHAR(2000) NULL,
        SubmittedAt            DATETIME2(3)   NULL,       -- Submit pertama (T2-2)
        CreatedAt              DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectRequest_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy              NVARCHAR(100)  NULL,
        UpdatedAt              DATETIME2(3)   NULL,
        UpdatedBy              NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectRequest PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ProjectRequest_SubCategory FOREIGN KEY (SubCategoryId) REFERENCES dbo.SubCategory (Id),
        CONSTRAINT FK_ProjectRequest_Location    FOREIGN KEY (LocationId)    REFERENCES dbo.Location (Id),
        CONSTRAINT CK_ProjectRequest_CoCode   CHECK (CoCode IN ('ABL', 'NKM')),
        CONSTRAINT CK_ProjectRequest_Category CHECK (Category IN ('CAPEX', 'OPEX', 'LVE')),
        CONSTRAINT CK_ProjectRequest_Budget   CHECK (BudgetRemarks IS NULL OR BudgetRemarks IN ('BUDGETED', 'UNBUDGETED')),
        CONSTRAINT CK_ProjectRequest_Status   CHECK (Status IN ('DRAFT', 'WAITING_APPROVAL', 'RETURNED', 'FEASIBILITY',
                                                             'DOC_PREPARATION', 'MGMT_APPROVAL', 'PLANNING', 'PROCUREMENT',
                                                             'SCHEDULING', 'IN_PROGRESS', 'BAPP_REVIEW', 'CLOSED',
                                                             'SURVEY_COMPLETED', 'REJECTED', 'CANCELLED')),
        CONSTRAINT CK_ProjectRequest_Area     CHECK ((AreaLength IS NULL OR AreaLength > 0) AND (AreaWidth IS NULL OR AreaWidth > 0)),
        CONSTRAINT CK_ProjectRequest_Amount   CHECK (BudgetExpectation IS NULL OR BudgetExpectation >= 0)
    );
END
GO

/* MIGRASI T3-2 (Keputusan 13-11-2026, BR-05, BR-12): nilai BOQ total (IDR) diisi Civil di Document Preparation,
   wajib sebelum dikirim ke management. Hanya menambah kolom nullable; data lama tidak berubah. */
IF COL_LENGTH(N'dbo.ProjectRequest', N'BoqTotal') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        BoqTotal  DECIMAL(18, 2) NULL
            CONSTRAINT CK_ProjectRequest_BoqTotal CHECK (BoqTotal IS NULL OR BoqTotal > 0);
END
GO

/* MIGRASI T4-1 (PRD 3.3, BR-11, BR-12, BR-15): cara eksekusi, plan cost, awal periode Preparation.
   Hanya menambah kolom nullable; data lama tidak berubah. */
IF COL_LENGTH(N'dbo.ProjectRequest', N'ExecutionType') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        ExecutionType       VARCHAR(10)    NULL
            CONSTRAINT CK_ProjectRequest_ExecutionType CHECK (ExecutionType IS NULL OR ExecutionType IN ('INHOUSE', 'OUTSOURCE')),
        PlanCost            DECIMAL(18, 2) NULL
            CONSTRAINT CK_ProjectRequest_PlanCost CHECK (PlanCost IS NULL OR PlanCost > 0),
        PreparationStartAt  DATETIME2(3)   NULL;
END
GO

/* MIGRASI T4-3 (FR-03, BR-77): penanda project berjalan yang diinput Civil saat go-live (data migrasi).
   Kolom NOT NULL dengan default 0; baris lama otomatis 0. */
IF COL_LENGTH(N'dbo.ProjectRequest', N'IsMigrated') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        IsMigrated  BIT  NOT NULL CONSTRAINT DF_ProjectRequest_IsMigrated DEFAULT (0);
END
GO

/* ---------------------------------------------------------------------
   1a. dbo.fn_User_OutsourceOnly(@Username)  (RL-06: purchasing hanya melihat project outsource)
       1 baris = user hanya memegang role purchasing (tanpa role CIMS lain yang melihat request);
       SP list/detail request menambah syarat ExecutionType = 'OUTSOURCE' untuk user ini.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_OutsourceOnly
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT 1 AS OutsourceOnly
    FROM   home..users u
    WHERE  u.Username = @Username
      AND  EXISTS (SELECT 1 FROM STRING_SPLIT(u.[Role], N';') s WHERE LTRIM(RTRIM(s.value)) = N'purchasing')
      AND  NOT EXISTS (SELECT 1 FROM STRING_SPLIT(u.[Role], N';') s
                       WHERE LTRIM(RTRIM(s.value)) IN (N'administrator', N'director', N'gm', N'civil', N'kabag', N'mo',
                                                       N'adm', N'plan', N'spv', N'emp'))
);
GO

/* ---------------------------------------------------------------------
   1a-2. dbo.fn_Request_VisibleToUser(@Status, @DepartmentID, @Username)  (RL-05 FAT; Keputusan 18-11-2026)
       1 baris = request boleh dilihat menurut aturan FAT. Departemen yang terlihat HANYA karena role fat
       (fn_User_AllowedDepartments.FatOnlyScope = 1) dibatasi ke In Progress, BAPP Review, Closed, Survey Completed;
       departemen yang terlihat lewat role lain (mis. 'kabag;fat' -> departemen sendiri) tetap semua status.
       Lingkup departemen tetap dicek pemanggil (fn_User_AllowedDepartments).
   --------------------------------------------------------------------- */
DROP FUNCTION IF EXISTS dbo.fn_User_FatOnly;   -- versi awal (FAT-only per user) diganti aturan per departemen
GO

CREATE OR ALTER FUNCTION dbo.fn_Request_VisibleToUser
(
    @Status       VARCHAR(20),
    @DepartmentID INT,
    @Username     NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT 1 AS Visible
    WHERE  @Status IN ('IN_PROGRESS', 'BAPP_REVIEW', 'CLOSED', 'SURVEY_COMPLETED')
       OR  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f
                   WHERE f.DepartmentID = @DepartmentID AND f.FatOnlyScope = 0)
);
GO

/* ---------------------------------------------------------------------
   1a-3. dbo.fn_User_CanSeeBapp(@Username)  (matriks 5.2 baris BAPP; T6-1, Keputusan 18-11-2026)
       1 baris = boleh melihat BAPP (data, langkah, lampiran tahap BAPP): kabag, mo, civil, fat, gm, director,
       administrator. adm / plan / spv / emp / purchasing tidak.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanSeeBapp
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    FROM   home..users u
           CROSS APPLY STRING_SPLIT(u.[Role], N';') s
    WHERE  u.Username = @Username
      AND  LTRIM(RTRIM(s.value)) IN (N'kabag', N'mo', N'civil', N'fat', N'dgo', N'gm', N'director', N'administrator')
);
GO

/* ---------------------------------------------------------------------
   1b. dbo.fn_User_CanChangeAttachment(@Stage, @Status, @Username)  (satu tempat aturan lampiran)
       1 baris = user boleh upload/hapus lampiran jenis tahap @Stage pada request berstatus @Status:
         REQUEST     : DRAFT / RETURNED (requester; role dicek di aplikasi), FEASIBILITY oleh civil (T3-1)
         DOCUMENT    : DOC_PREPARATION oleh civil (BOQ, Drawing; T3-2)
         PROCUREMENT : PLANNING oleh civil (TOR; T4-1, BR-11)
         CONTRACT    : PROCUREMENT oleh purchasing (lampiran kontrak; T4-1, BR-11)
         BAPP        : IN_PROGRESS oleh civil (foto dokumentasi / dokumen pendukung BAPP; T6-1, BR-88)
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanChangeAttachment
(
    @Stage    VARCHAR(20),
    @Status   VARCHAR(20),
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    WITH r AS
    (
        SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
        FROM   home..users u
               CROSS APPLY STRING_SPLIT(u.[Role], N';') s
        WHERE  u.Username = @Username
    )
    SELECT 1 AS Allowed
    WHERE  (@Stage = 'REQUEST' AND @Status IN ('DRAFT', 'RETURNED'))
       OR  (@Stage = 'REQUEST'     AND @Status = 'FEASIBILITY'     AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'civil'))
       OR  (@Stage = 'DOCUMENT'    AND @Status = 'DOC_PREPARATION' AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'civil'))
       OR  (@Stage = 'PROCUREMENT' AND @Status = 'PLANNING'        AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'civil'))
       OR  (@Stage = 'CONTRACT'    AND @Status = 'PROCUREMENT'     AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'purchasing'))
       OR  (@Stage = 'BAPP'        AND @Status = 'IN_PROGRESS'     AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'civil'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_ProjectRequest_RequestNo' AND object_id = OBJECT_ID(N'dbo.ProjectRequest'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_ProjectRequest_RequestNo ON dbo.ProjectRequest (RequestNo) WHERE RequestNo IS NOT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_ProjectRequest_Dept_Status' AND object_id = OBJECT_ID(N'dbo.ProjectRequest'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectRequest_Dept_Status ON dbo.ProjectRequest (DepartmentID, Status) INCLUDE (CoCode, CreatedAt);
END
GO

/* ---------------------------------------------------------------------
   2. TABLE dbo.RequestAssessmentAnswer  (MD-08; teks pertanyaan disimpan = snapshot)
      Draft: baris hanya untuk pertanyaan yang sudah dijawab. Saat Submit (T2-2) dilengkapi/dikunci.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestAssessmentAnswer', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestAssessmentAnswer
    (
        Id            INT IDENTITY(1,1) NOT NULL,
        RequestId     INT           NOT NULL,
        QuestionId    INT           NOT NULL,
        SortOrder     INT           NOT NULL,
        QuestionText  NVARCHAR(300) NOT NULL,
        Answer        BIT           NOT NULL,
        CreatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_RequestAssessmentAnswer_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy     NVARCHAR(100) NULL,
        CONSTRAINT PK_RequestAssessmentAnswer PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_RequestAssessmentAnswer_Request  FOREIGN KEY (RequestId)  REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_RequestAssessmentAnswer_Question FOREIGN KEY (QuestionId) REFERENCES dbo.AssessmentQuestion (Id),
        CONSTRAINT UQ_RequestAssessmentAnswer UNIQUE (RequestId, QuestionId)
    );
END
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.RequestAttachment  (BR-44..BR-46; entitas "Attachment" PRD 6.7)
      RelativePath relatif terhadap FileStorage:RealizationAttachmentsPath, mis. 2026\15\<guid>.pdf
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestAttachment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestAttachment
    (
        Id                INT IDENTITY(1,1) NOT NULL,
        RequestId         INT           NOT NULL,
        AttachmentTypeId  INT           NOT NULL,
        OriginalFileName  NVARCHAR(260) NOT NULL,
        RelativePath      NVARCHAR(400) NOT NULL,
        ContentType       VARCHAR(100)  NOT NULL,
        FileSizeBytes     BIGINT        NOT NULL,
        IsActive          BIT           NOT NULL CONSTRAINT DF_RequestAttachment_IsActive  DEFAULT (1),
        CreatedAt         DATETIME2(3)  NOT NULL CONSTRAINT DF_RequestAttachment_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy         NVARCHAR(100) NULL,
        UpdatedAt         DATETIME2(3)  NULL,
        UpdatedBy         NVARCHAR(100) NULL,
        CONSTRAINT PK_RequestAttachment PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_RequestAttachment_Request FOREIGN KEY (RequestId)        REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_RequestAttachment_Type    FOREIGN KEY (AttachmentTypeId) REFERENCES dbo.AttachmentType (Id),
        CONSTRAINT CK_RequestAttachment_Size    CHECK (FileSizeBytes > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_RequestAttachment_Request' AND object_id = OBJECT_ID(N'dbo.RequestAttachment'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_RequestAttachment_Request ON dbo.RequestAttachment (RequestId, IsActive);
END
GO

/* =====================================================================
   LOOKUP untuk form request
   ===================================================================== */

/* ---------------------------------------------------------------------
   4. usp_Lookup_CostCenters  (BR-40: sub-department milik department requester, Disabled = 0)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_CostCenters
    @DepartmentID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  s.SubDepartmentID, s.SubDepartmentCode, s.SubDepartmentName
    FROM    home..APP_SubDepartments s
    WHERE   s.DepartmentID = @DepartmentID
      AND   s.Disabled = 0
    ORDER BY s.DispIndex, s.SubDepartmentCode;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Lookup_ActiveEmployees  (PIC: karyawan aktif pada department requester)
      Aktif = ResignDate NULL atau masih di masa depan (sama dengan aturan login, BR-31).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_ActiveEmployees
    @DepartmentID INT,
    @Search       NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');

    SELECT TOP (200)
            e.EmployeeCode, e.FullName, e.JobTitle
    FROM    home..app_employees e
    WHERE   e.DepartmentID = @DepartmentID
      AND   (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME())
      AND   (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%' OR e.EmployeeCode LIKE N'%' + @Search + N'%')
    ORDER BY e.FullName, e.EmployeeCode;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Lookup_Locations  (MD-02 aktif per Company; BR-61)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_Locations
    @CoCode VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Name
    FROM   dbo.Location
    WHERE  CoCode = @CoCode AND IsActive = 1
    ORDER BY Name, Id;
END
GO

/* ---------------------------------------------------------------------
   7. usp_Lookup_AssessmentQuestions  (MD-08 aktif, urut SortOrder)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_AssessmentQuestions
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, SortOrder, QuestionText
    FROM   dbo.AssessmentQuestion
    WHERE  IsActive = 1
    ORDER BY SortOrder, Id;
END
GO

/* ---------------------------------------------------------------------
   8. usp_Lookup_AttachmentTypesByStage  (MD-09 aktif per tahap; validasi upload di aplikasi)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_AttachmentTypesByStage
    @Stage VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, Name, Stage, AllowedExtensions, MaxSizeMB,
           IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve
    FROM   dbo.AttachmentType
    WHERE  Stage = @Stage AND IsActive = 1
    ORDER BY Name, Id;
END
GO

/* =====================================================================
   REQUEST
   ===================================================================== */

/* ---------------------------------------------------------------------
   9. usp_Request_SaveDraft
      @Id NULL = buat draft baru; @Id terisi = ubah draft (status DRAFT atau RETURNED).
      @AssessmentJson: '[{"q":1,"a":true},{"q":2,"a":false}]' (q = AssessmentQuestion.Id);
                       NULL = jawaban tidak diubah; '[]' = hapus semua jawaban.
      Teks panjang diterima NVARCHAR(MAX) lalu dicek panjangnya (tanpa pemotongan diam-diam).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveDraft
    @Id                    INT            = NULL,
    @Username              NVARCHAR(100),
    @Title                 NVARCHAR(MAX),
    @Category              VARCHAR(10),
    @SubCategoryId         INT            = NULL,
    @BudgetRemarks         VARCHAR(12)    = NULL,
    @SubDepartmentID       INT            = NULL,
    @LocationId            INT            = NULL,
    @PicEmployeeCode       VARCHAR(30)    = NULL,
    @TargetCompletionDate  DATE           = NULL,
    @AreaLength            DECIMAL(10, 2) = NULL,
    @AreaWidth             DECIMAL(10, 2) = NULL,
    @BudgetExpectation     DECIMAL(18, 2) = NULL,
    @Background            NVARCHAR(MAX)  = NULL,
    @Objective             NVARCHAR(MAX)  = NULL,
    @OperationalImpact     NVARCHAR(MAX)  = NULL,
    @RiskIfNotApproved     NVARCHAR(MAX)  = NULL,
    @ExpectedBenefits      NVARCHAR(MAX)  = NULL,
    @Alternatives          NVARCHAR(MAX)  = NULL,
    @SpecialNote           NVARCHAR(MAX)  = NULL,
    @ExpectedRoiPercent    DECIMAL(9, 2)  = NULL,
    @RoiExplanation        NVARCHAR(MAX)  = NULL,
    @AdditionalInfo        NVARCHAR(MAX)  = NULL,
    @AssessmentJson        NVARCHAR(MAX)  = NULL,
    @SavedId               INT            = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EmpCode VARCHAR(30), @CoCode VARCHAR(10), @DeptId INT, @Status VARCHAR(20);

    /* -- Requester (karyawan aktif) -- */
    SELECT  @EmpCode = e.EmployeeCode, @CoCode = e.CoCode, @DeptId = e.DepartmentID
    FROM    home..users u
            JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
    WHERE   u.Username = @Username
      AND   (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME());

    IF @EmpCode IS NULL
        THROW 50072, N'Your employee data was not found.', 1;

    IF @Id IS NULL
    BEGIN
        -- Draft baru: Company dan department dari requester (BR-40, BR-56)
        IF @DeptId IS NULL OR ISNULL(@CoCode, '') NOT IN ('ABL', 'NKM')
            THROW 50072, N'Your department or company is not set in the employee data.', 1;
        IF NOT EXISTS (SELECT 1 FROM home..APP_Departments d WHERE d.DepartmentID = @DeptId AND ISNULL(d.Disabled, 0) = 0)
            THROW 50072, N'Your department is disabled.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = @DeptId)
            THROW 50072, N'Your department is outside your data scope.', 1;
    END
    ELSE
    BEGIN
        -- Ubah draft: Company dan department tetap milik request
        SELECT @Status = r.Status, @CoCode = r.CoCode, @DeptId = r.DepartmentID
        FROM   dbo.ProjectRequest r
        WHERE  r.Id = @Id
          AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

        IF @Status IS NULL
            THROW 50073, N'Request not found.', 1;
        IF @Status NOT IN ('DRAFT', 'RETURNED')
            THROW 50074, N'Only draft or returned requests can be edited.', 1;
    END

    /* -- Normalisasi -- */
    SET @Title             = NULLIF(LTRIM(RTRIM(@Title)), N'');
    SET @Category          = UPPER(LTRIM(RTRIM(@Category)));
    SET @BudgetRemarks     = NULLIF(UPPER(LTRIM(RTRIM(@BudgetRemarks))), '');
    SET @PicEmployeeCode   = NULLIF(LTRIM(RTRIM(@PicEmployeeCode)), '');
    SET @Background        = NULLIF(LTRIM(RTRIM(@Background)), N'');
    SET @Objective         = NULLIF(LTRIM(RTRIM(@Objective)), N'');
    SET @OperationalImpact = NULLIF(LTRIM(RTRIM(@OperationalImpact)), N'');
    SET @RiskIfNotApproved = NULLIF(LTRIM(RTRIM(@RiskIfNotApproved)), N'');
    SET @ExpectedBenefits  = NULLIF(LTRIM(RTRIM(@ExpectedBenefits)), N'');
    SET @Alternatives      = NULLIF(LTRIM(RTRIM(@Alternatives)), N'');
    SET @SpecialNote       = NULLIF(LTRIM(RTRIM(@SpecialNote)), N'');
    SET @RoiExplanation    = NULLIF(LTRIM(RTRIM(@RoiExplanation)), N'');
    SET @AdditionalInfo    = NULLIF(LTRIM(RTRIM(@AdditionalInfo)), N'');

    /* -- Wajib saat Draft -- */
    IF @Title IS NULL                                           THROW 50072, N'Request title is required.', 1;
    IF LEN(@Title) > 200                                        THROW 50072, N'Request title must be at most 200 characters.', 1;
    IF ISNULL(@Category, '') NOT IN ('CAPEX', 'OPEX', 'LVE')    THROW 50072, N'Budget classification is required (CAPEX, OPEX, or LVE).', 1;

    /* -- Opsional saat Draft, divalidasi bila diisi -- */
    IF @SubCategoryId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.SubCategory WHERE Id = @SubCategoryId AND Category = @Category AND IsActive = 1)
        THROW 50072, N'Sub-category is invalid for the selected budget classification.', 1;

    IF @BudgetRemarks IS NOT NULL AND @BudgetRemarks NOT IN ('BUDGETED', 'UNBUDGETED')
        THROW 50072, N'Budget remarks must be Budgeted or Unbudgeted.', 1;

    IF @SubDepartmentID IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM home..APP_SubDepartments s
                       WHERE s.SubDepartmentID = @SubDepartmentID AND s.DepartmentID = @DeptId AND s.Disabled = 0)
        THROW 50072, N'Cost center is invalid for the requesting department.', 1;

    IF @LocationId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.Location WHERE Id = @LocationId AND CoCode = @CoCode AND IsActive = 1)
        THROW 50072, N'Location is invalid for the request company.', 1;

    IF @PicEmployeeCode IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM home..app_employees e
                       WHERE e.EmployeeCode = @PicEmployeeCode AND e.DepartmentID = @DeptId
                         AND (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME()))
        THROW 50072, N'PIC must be an active employee of the requesting department.', 1;

    IF @TargetCompletionDate IS NOT NULL AND @TargetCompletionDate < CAST(SYSDATETIME() AS DATE)
        THROW 50072, N'Target completion cannot be in the past.', 1;
    IF @AreaLength IS NOT NULL AND @AreaLength <= 0             THROW 50072, N'Area length must be greater than 0.', 1;
    IF @AreaWidth  IS NOT NULL AND @AreaWidth  <= 0             THROW 50072, N'Area width must be greater than 0.', 1;
    IF @BudgetExpectation IS NOT NULL AND @BudgetExpectation < 0
        THROW 50072, N'Budget expectation cannot be negative.', 1;
    IF @ExpectedRoiPercent IS NOT NULL AND @ExpectedRoiPercent NOT BETWEEN -100 AND 10000
        THROW 50072, N'Expected ROI must be between -100 and 10000 %.', 1;

    IF LEN(@Background) > 2000 OR LEN(@Objective) > 2000 OR LEN(@OperationalImpact) > 2000
       OR LEN(@RiskIfNotApproved) > 2000 OR LEN(@ExpectedBenefits) > 2000 OR LEN(@Alternatives) > 2000
       OR LEN(@SpecialNote) > 2000 OR LEN(@RoiExplanation) > 2000 OR LEN(@AdditionalInfo) > 2000
        THROW 50072, N'Each text field must be at most 2000 characters.', 1;

    /* -- Jawaban assessment -- */
    DECLARE @Answers TABLE (QuestionId INT PRIMARY KEY, Answer BIT NOT NULL);

    IF @AssessmentJson IS NOT NULL
    BEGIN
        IF ISJSON(@AssessmentJson) = 0
            THROW 50072, N'Environment assessment answers are invalid.', 1;

        BEGIN TRY
            INSERT INTO @Answers (QuestionId, Answer)
            SELECT j.q, j.a
            FROM   OPENJSON(@AssessmentJson) WITH (q INT '$.q', a BIT '$.a') j
            WHERE  j.q IS NOT NULL AND j.a IS NOT NULL;
        END TRY
        BEGIN CATCH
            THROW 50072, N'Environment assessment answers are invalid.', 1;
        END CATCH

        IF EXISTS (SELECT 1 FROM @Answers a
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.AssessmentQuestion q WHERE q.Id = a.QuestionId AND q.IsActive = 1))
            THROW 50072, N'Environment assessment contains an unknown or inactive question.', 1;
    END

    /* -- Simpan -- */
    BEGIN TRANSACTION;

    IF @Id IS NULL
    BEGIN
        INSERT INTO dbo.ProjectRequest
            (CoCode, DepartmentID, Status, RequesterUsername, RequesterEmployeeCode, PicEmployeeCode,
             Title, Category, SubCategoryId, BudgetRemarks, SubDepartmentID, LocationId, TargetCompletionDate,
             AreaLength, AreaWidth, BudgetExpectation, Background, Objective, OperationalImpact,
             RiskIfNotApproved, ExpectedBenefits, Alternatives, SpecialNote, ExpectedRoiPercent,
             RoiExplanation, AdditionalInfo, CreatedBy)
        VALUES
            (@CoCode, @DeptId, 'DRAFT', @Username, @EmpCode, @PicEmployeeCode,
             @Title, @Category, @SubCategoryId, @BudgetRemarks, @SubDepartmentID, @LocationId, @TargetCompletionDate,
             @AreaLength, @AreaWidth, @BudgetExpectation, @Background, @Objective, @OperationalImpact,
             @RiskIfNotApproved, @ExpectedBenefits, @Alternatives, @SpecialNote, @ExpectedRoiPercent,
             @RoiExplanation, @AdditionalInfo, @Username);

        SET @SavedId = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.ProjectRequest
        SET    PicEmployeeCode      = @PicEmployeeCode,
               Title                = @Title,
               Category             = @Category,
               SubCategoryId        = @SubCategoryId,
               BudgetRemarks        = @BudgetRemarks,
               SubDepartmentID      = @SubDepartmentID,
               LocationId           = @LocationId,
               TargetCompletionDate = @TargetCompletionDate,
               AreaLength           = @AreaLength,
               AreaWidth            = @AreaWidth,
               BudgetExpectation    = @BudgetExpectation,
               Background           = @Background,
               Objective            = @Objective,
               OperationalImpact    = @OperationalImpact,
               RiskIfNotApproved    = @RiskIfNotApproved,
               ExpectedBenefits     = @ExpectedBenefits,
               Alternatives         = @Alternatives,
               SpecialNote          = @SpecialNote,
               ExpectedRoiPercent   = @ExpectedRoiPercent,
               RoiExplanation       = @RoiExplanation,
               AdditionalInfo       = @AdditionalInfo,
               UpdatedAt            = SYSDATETIME(),
               UpdatedBy            = @Username
        WHERE  Id = @Id AND Status IN ('DRAFT', 'RETURNED');

        IF @@ROWCOUNT = 0
            THROW 50074, N'Only draft or returned requests can be edited.', 1;

        SET @SavedId = @Id;
    END

    IF @AssessmentJson IS NOT NULL
    BEGIN
        DELETE FROM dbo.RequestAssessmentAnswer WHERE RequestId = @SavedId;

        INSERT INTO dbo.RequestAssessmentAnswer (RequestId, QuestionId, SortOrder, QuestionText, Answer, CreatedBy)
        SELECT @SavedId, q.Id, q.SortOrder, q.QuestionText, a.Answer, @Username
        FROM   @Answers a
               JOIN dbo.AssessmentQuestion q ON q.Id = a.QuestionId;
    END

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   10. usp_Request_GetById  (detail + nama tampilan; 0 baris = tidak ada / di luar lingkup)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetById
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  r.Id, r.CoCode, r.DepartmentID, d.DeptName, d.ABRV, r.RequestNo, r.Status,
            r.RequesterUsername, r.RequesterEmployeeCode, req.FullName AS RequesterName,
            r.PicEmployeeCode, pic.FullName AS PicName,
            r.Title, r.Category, r.SubCategoryId, sc.Name AS SubCategoryName,
            r.BudgetRemarks, r.SubDepartmentID, sd.SubDepartmentCode AS CostCenterCode, sd.SubDepartmentName AS CostCenterName,
            r.LocationId, l.Name AS LocationName, r.TargetCompletionDate,
            r.AreaLength, r.AreaWidth, r.AreaSize, r.BudgetExpectation,
            r.Background, r.Objective, r.OperationalImpact, r.RiskIfNotApproved, r.ExpectedBenefits,
            r.Alternatives, r.SpecialNote, r.ExpectedRoiPercent, r.RoiExplanation, r.AdditionalInfo,
            r.BoqTotal, r.ExecutionType, r.PlanCost, r.PreparationStartAt, r.IsMigrated,
            r.SubmittedAt, r.CreatedAt, r.CreatedBy, r.UpdatedAt, r.UpdatedBy
    FROM    dbo.ProjectRequest r
            LEFT JOIN home..APP_Departments d     ON d.DepartmentID = r.DepartmentID
            LEFT JOIN home..app_employees req     ON req.EmployeeCode = r.RequesterEmployeeCode
            LEFT JOIN home..app_employees pic     ON pic.EmployeeCode = r.PicEmployeeCode
            LEFT JOIN home..APP_SubDepartments sd ON sd.SubDepartmentID = r.SubDepartmentID
            LEFT JOIN dbo.SubCategory sc          ON sc.Id = r.SubCategoryId
            LEFT JOIN dbo.Location l              ON l.Id = r.LocationId
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      -- RL-06: purchasing (tanpa role lain) hanya project outsource
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)))
      -- RL-05: departemen yang terlihat hanya karena role fat -> In Progress ke atas (18-11-2026)
      AND   EXISTS (SELECT 1 FROM dbo.fn_Request_VisibleToUser(r.Status, r.DepartmentID, @Username));
END
GO

/* ---------------------------------------------------------------------
   11. usp_Request_GetAssessment
       DRAFT / RETURNED : pertanyaan aktif + jawaban yang sudah ada (Answer NULL = belum dijawab)
       status lain      : jawaban tersimpan (snapshot saat Submit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetAssessment
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status VARCHAR(20) =
    (
        SELECT r.Status FROM dbo.ProjectRequest r
        WHERE  r.Id = @RequestId
          AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
    );

    IF @Status IS NULL
        RETURN;

    IF @Status IN ('DRAFT', 'RETURNED')
        SELECT  q.Id AS QuestionId, q.SortOrder, q.QuestionText, a.Answer
        FROM    dbo.AssessmentQuestion q
                LEFT JOIN dbo.RequestAssessmentAnswer a ON a.QuestionId = q.Id AND a.RequestId = @RequestId
        WHERE   q.IsActive = 1
        ORDER BY q.SortOrder, q.Id;
    ELSE
        SELECT  a.QuestionId, a.SortOrder, a.QuestionText, CAST(a.Answer AS BIT) AS Answer
        FROM    dbo.RequestAssessmentAnswer a
        WHERE   a.RequestId = @RequestId
        ORDER BY a.SortOrder, a.QuestionId;
END
GO

/* ---------------------------------------------------------------------
   12. usp_Request_GetPaged  (list dalam lingkup user; filter Company untuk role lintas Company, BR-57;
       filter departemen @DepartmentID, tetap dibatasi lingkup user)
       @SortBy  : CreatedAt | RequestNo | Title | Category | Status   (default CreatedAt)
       @SortDir : ASC | DESC                                          (default DESC)
       T4-4 (Keputusan 18-11-2026): kolom OpenAddendumStatus / OpenAddendumCode = addendum yang masih terbuka
       (PENDING_APPROVAL / FINAL_CONTRACT / ADJUSTMENT) untuk tanda follow up; @AddendumOpen = 1 -> hanya project dengan addendum
       terbuka. Hak lihat BR-86: addendum outsource hanya untuk civil, purchasing, fat, gm, director, administrator
       (sama dengan fn_User_CanSeeAddendum; ditulis inline agar script ini tidak bergantung pada RequestAddendum.sql).
       Tabel ProjectAddendum dibaca saat dijalankan: jalankan RequestAddendum.sql sebelum memakai list.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetPaged
    @Username    NVARCHAR(100),
    @CoCode      VARCHAR(10)   = NULL,
    @DepartmentID INT          = NULL,
    @Search      NVARCHAR(100) = NULL,
    @Category    VARCHAR(10)   = NULL,
    @Status      VARCHAR(20)   = NULL,
    @AddendumOpen BIT          = NULL,
    @SortBy      NVARCHAR(20)  = N'CreatedAt',
    @SortDir     NVARCHAR(4)   = N'DESC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode     = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @Category   = NULLIF(LTRIM(RTRIM(@Category)), '');
    SET @Status     = NULLIF(LTRIM(RTRIM(@Status)), '');
    SET @SortBy     = CASE WHEN @SortBy IN (N'CreatedAt', N'RequestNo', N'Title', N'Category', N'Status') THEN @SortBy ELSE N'CreatedAt' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'ASC' THEN N'ASC' ELSE N'DESC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    -- Batas 5000 untuk export Excel (FR-04); tampilan list tetap dibatasi Controller (10 baris)
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 5000 THEN 5000
                           ELSE @PageSize END;

    -- FatOnlyScope = 1: departemen terlihat hanya karena role fat -> In Progress ke atas (RL-05, Keputusan 18-11-2026)
    DECLARE @Scope TABLE (DepartmentID INT PRIMARY KEY, FatOnlyScope BIT NOT NULL);
    INSERT INTO @Scope (DepartmentID, FatOnlyScope)
    SELECT f.DepartmentID, MIN(CAST(f.FatOnlyScope AS INT)) FROM dbo.fn_User_AllowedDepartments(@Username) f GROUP BY f.DepartmentID;

    -- RL-06: purchasing (tanpa role lain) hanya project outsource
    DECLARE @OutsourceOnly BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)) THEN 1 ELSE 0 END;

    -- BR-86: boleh melihat addendum outsource (baris Kontrak matriks 5.2); in-house = semua yang melihat request
    DECLARE @SeeOutsourceAddendum BIT =
        CASE WHEN EXISTS (SELECT 1 FROM home..users u CROSS APPLY STRING_SPLIT(u.[Role], N';') x
                          WHERE u.Username = @Username
                            AND LTRIM(RTRIM(x.value)) IN (N'civil', N'purchasing', N'fat', N'dgo', N'gm', N'director', N'administrator'))
             THEN 1 ELSE 0 END;
    SET @AddendumOpen = CASE WHEN @AddendumOpen = 1 THEN 1 ELSE NULL END;

    SELECT @TotalCount = COUNT(*)
    FROM   dbo.ProjectRequest r
           JOIN @Scope s ON s.DepartmentID = r.DepartmentID
    WHERE  (@OutsourceOnly = 0 OR r.ExecutionType = 'OUTSOURCE')
      AND  (s.FatOnlyScope = 0 OR r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW', 'CLOSED', 'SURVEY_COMPLETED'))
      AND  (@CoCode   IS NULL OR r.CoCode   = @CoCode)
      AND  (@DepartmentID IS NULL OR r.DepartmentID = @DepartmentID)
      AND  (@Category IS NULL OR r.Category = @Category)
      AND  (@Status   IS NULL OR r.Status   = @Status)
      AND  (@Search   IS NULL OR r.Title LIKE N'%' + @Search + N'%' OR r.RequestNo LIKE '%' + @Search + '%'
            -- BR-54: nomor lama (sebelum ganti kategori) tetap bisa dicari
            OR EXISTS (SELECT 1 FROM dbo.RequestNoHistory nh WHERE nh.RequestId = r.Id AND nh.RequestNo LIKE '%' + @Search + '%'))
      AND  (@AddendumOpen IS NULL
            OR EXISTS (SELECT 1 FROM dbo.ProjectAddendum ad
                       WHERE ad.RequestId = r.Id AND ad.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT')
                         AND (ad.ExecutionType = 'INHOUSE' OR @SeeOutsourceAddendum = 1)))
    OPTION (RECOMPILE);

    SELECT  r.Id, r.CoCode, r.RequestNo, r.Title, r.Category, sc.Name AS SubCategoryName, r.Status,
            r.DepartmentID, d.DeptName, d.ABRV, req.FullName AS RequesterName,
            r.TargetCompletionDate, r.BudgetExpectation, r.SubmittedAt, r.CreatedAt, r.UpdatedAt,
            oa.Status AS OpenAddendumStatus, oa.AddendumCode AS OpenAddendumCode
    FROM    dbo.ProjectRequest r
            JOIN @Scope s ON s.DepartmentID = r.DepartmentID
            LEFT JOIN dbo.SubCategory sc      ON sc.Id = r.SubCategoryId
            LEFT JOIN home..APP_Departments d ON d.DepartmentID = r.DepartmentID
            LEFT JOIN home..app_employees req ON req.EmployeeCode = r.RequesterEmployeeCode
            OUTER APPLY (SELECT TOP (1) ad.Status, ad.AddendumCode
                         FROM   dbo.ProjectAddendum ad
                         WHERE  ad.RequestId = r.Id AND ad.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT')
                           AND  (ad.ExecutionType = 'INHOUSE' OR @SeeOutsourceAddendum = 1)) oa
    WHERE   (@OutsourceOnly = 0 OR r.ExecutionType = 'OUTSOURCE')
      AND   (s.FatOnlyScope = 0 OR r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW', 'CLOSED', 'SURVEY_COMPLETED'))
      AND   (@CoCode   IS NULL OR r.CoCode   = @CoCode)
      AND   (@DepartmentID IS NULL OR r.DepartmentID = @DepartmentID)
      AND   (@Category IS NULL OR r.Category = @Category)
      AND   (@Status   IS NULL OR r.Status   = @Status)
      AND   (@Search   IS NULL OR r.Title LIKE N'%' + @Search + N'%' OR r.RequestNo LIKE '%' + @Search + '%'
             OR EXISTS (SELECT 1 FROM dbo.RequestNoHistory nh WHERE nh.RequestId = r.Id AND nh.RequestNo LIKE '%' + @Search + '%'))
      AND   (@AddendumOpen IS NULL OR oa.Status IS NOT NULL)
    ORDER BY
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN r.CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN r.CreatedAt END DESC,
        CASE WHEN @SortBy = N'RequestNo' AND @SortDir = N'ASC'  THEN r.RequestNo END ASC,
        CASE WHEN @SortBy = N'RequestNo' AND @SortDir = N'DESC' THEN r.RequestNo END DESC,
        CASE WHEN @SortBy = N'Title'     AND @SortDir = N'ASC'  THEN r.Title     END ASC,
        CASE WHEN @SortBy = N'Title'     AND @SortDir = N'DESC' THEN r.Title     END DESC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'ASC'  THEN CHARINDEX(',' + r.Category + ',', ',CAPEX,OPEX,LVE,') END ASC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'DESC' THEN CHARINDEX(',' + r.Category + ',', ',CAPEX,OPEX,LVE,') END DESC,
        CASE WHEN @SortBy = N'Status'    AND @SortDir = N'ASC'  THEN r.Status    END ASC,
        CASE WHEN @SortBy = N'Status'    AND @SortDir = N'DESC' THEN r.Status    END DESC,
        r.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* =====================================================================
   LAMPIRAN
   ===================================================================== */

/* ---------------------------------------------------------------------
   13. usp_RequestAttachment_Insert
       File sudah ditulis aplikasi ke disk; SP memvalidasi ulang (lingkup, status, jenis,
       ekstensi, ukuran) lalu mencatat metadata. Bila SP gagal, aplikasi menghapus file yang baru ditulis.
       Jenis tahap REQUEST: status DRAFT / RETURNED (requester; T2), atau FEASIBILITY oleh role civil
       (mis. lampiran ROI setelah Civil mengubah kategori ke CAPEX; T3-1, BR-42).
       Jenis tahap DOCUMENT (BOQ, Drawing; BR-05): status DOC_PREPARATION oleh role civil (T3-2).
       Jenis tahap PROCUREMENT (TOR): PLANNING oleh civil · CONTRACT: PROCUREMENT oleh purchasing (T4-1, BR-11).
       Aturan lengkap: dbo.fn_User_CanChangeAttachment.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RequestAttachment_Insert
    @RequestId         INT,
    @Username          NVARCHAR(100),
    @AttachmentTypeId  INT,
    @OriginalFileName  NVARCHAR(260),
    @RelativePath      NVARCHAR(400),
    @ContentType       VARCHAR(100),
    @FileSizeBytes     BIGINT,
    @NewId             INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status VARCHAR(20), @Stage VARCHAR(20), @Ext VARCHAR(200), @MaxMB INT, @FileExt VARCHAR(20);

    SELECT @Status = r.Status
    FROM   dbo.ProjectRequest r
    WHERE  r.Id = @RequestId
      AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;

    SELECT @Stage = t.Stage, @Ext = t.AllowedExtensions, @MaxMB = t.MaxSizeMB
    FROM   dbo.AttachmentType t
    WHERE  t.Id = @AttachmentTypeId AND t.IsActive = 1;

    IF @Stage IS NULL
        THROW 50072, N'Attachment type is invalid.', 1;
    IF @Stage NOT IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP')
        THROW 50072, N'This attachment type cannot be uploaded at this stage.', 1;

    -- Aturan tahap x status x role: dbo.fn_User_CanChangeAttachment (T2, T3-1, T3-2, T4-1)
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_CanChangeAttachment(@Stage, @Status, @Username))
        THROW 50074, N'Attachments cannot be changed at the current request status.', 1;

    SET @OriginalFileName = LTRIM(RTRIM(@OriginalFileName));
    IF ISNULL(@OriginalFileName, N'') = N'' OR ISNULL(@RelativePath, N'') = N''
        THROW 50072, N'File name is required.', 1;

    -- Ekstensi = teks setelah titik terakhir, huruf kecil
    SET @FileExt = CASE WHEN CHARINDEX('.', @OriginalFileName) = 0 THEN ''
                        ELSE LOWER(RIGHT(@OriginalFileName, CHARINDEX('.', REVERSE(@OriginalFileName)) - 1)) END;

    IF @FileExt = '' OR CHARINDEX(',' + @FileExt + ',', ',' + @Ext + ',') = 0
        THROW 50072, N'File type is not allowed for this attachment type.', 1;
    IF @FileSizeBytes IS NULL OR @FileSizeBytes <= 0 OR @FileSizeBytes > CAST(@MaxMB AS BIGINT) * 1048576
        THROW 50072, N'File size exceeds the maximum for this attachment type.', 1;

    INSERT INTO dbo.RequestAttachment
        (RequestId, AttachmentTypeId, OriginalFileName, RelativePath, ContentType, FileSizeBytes, CreatedBy)
    VALUES
        (@RequestId, @AttachmentTypeId, @OriginalFileName, @RelativePath, ISNULL(NULLIF(@ContentType, ''), 'application/octet-stream'),
         @FileSizeBytes, @Username);

    SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
END
GO

/* ---------------------------------------------------------------------
   14. usp_RequestAttachment_ListByRequest  (aktif saja; urut jenis lalu waktu upload)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RequestAttachment_ListByRequest
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  a.Id, a.RequestId, a.AttachmentTypeId, t.Code AS AttachmentTypeCode, t.Name AS AttachmentTypeName, t.Stage,
            a.OriginalFileName, a.ContentType, a.FileSizeBytes, a.CreatedAt, a.CreatedBy
    FROM    dbo.RequestAttachment a
            JOIN dbo.AttachmentType t  ON t.Id = a.AttachmentTypeId
            JOIN dbo.ProjectRequest r  ON r.Id = a.RequestId
    WHERE   a.RequestId = @RequestId
      AND   a.IsActive = 1
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)))
      AND   EXISTS (SELECT 1 FROM dbo.fn_Request_VisibleToUser(r.Status, r.DepartmentID, @Username))   -- RL-05 FAT
      AND   (t.Stage <> 'BAPP' OR EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeBapp(@Username)))   -- 5.2 BAPP (T6-1)
    ORDER BY t.Name, a.CreatedAt, a.Id;
END
GO

/* ---------------------------------------------------------------------
   15. usp_RequestAttachment_GetById  (untuk download; aktif + dalam lingkup user)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RequestAttachment_GetById
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  a.Id, a.RequestId, a.AttachmentTypeId, t.Code AS AttachmentTypeCode, t.Name AS AttachmentTypeName, t.Stage,
            a.OriginalFileName, a.RelativePath, a.ContentType, a.FileSizeBytes, a.CreatedAt, a.CreatedBy
    FROM    dbo.RequestAttachment a
            JOIN dbo.AttachmentType t  ON t.Id = a.AttachmentTypeId
            JOIN dbo.ProjectRequest r  ON r.Id = a.RequestId
    WHERE   a.Id = @Id
      AND   a.IsActive = 1
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)))
      AND   EXISTS (SELECT 1 FROM dbo.fn_Request_VisibleToUser(r.Status, r.DepartmentID, @Username))   -- RL-05 FAT
      AND   (t.Stage <> 'BAPP' OR EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeBapp(@Username)));   -- 5.2 BAPP (T6-1)
END
GO

/* ---------------------------------------------------------------------
   16. usp_RequestAttachment_Deactivate  (BR-46: tidak dihapus fisik)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RequestAttachment_Deactivate
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status VARCHAR(20), @Stage VARCHAR(20);

    SELECT  @Status = r.Status, @Stage = t.Stage
    FROM    dbo.RequestAttachment a
            JOIN dbo.AttachmentType t ON t.Id = a.AttachmentTypeId
            JOIN dbo.ProjectRequest r ON r.Id = a.RequestId
    WHERE   a.Id = @Id
      AND   a.IsActive = 1
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Attachment not found.', 1;
    -- Aturan sama dengan Insert (dbo.fn_User_CanChangeAttachment)
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_CanChangeAttachment(@Stage, @Status, @Username))
        THROW 50074, N'Attachments cannot be changed at the current request status.', 1;

    UPDATE dbo.RequestAttachment
    SET    IsActive  = 0,
           UpdatedAt = SYSDATETIME(),
           UpdatedBy = @Username
    WHERE  Id = @Id;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel (@U, @Id, ...) hanya hidup dalam satu eksekusi: blok yang berisi baris error (3, 5, 7, 8)
   jalankan per baris bersama DECLARE yang dibutuhkan, atau set @Id ke Id draft uji.

   -- 0) Siapkan: user requester (adm/plan/spv) dan departemennya
   SELECT u.Username, u.[Role], e.EmployeeCode, e.CoCode, e.DepartmentID, ad.ABRV
   FROM   home..users u JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
          LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
   WHERE  u.[Role] LIKE N'%adm%';
   DECLARE @U NVARCHAR(100) = N'<user-adm>', @Dept INT = <DepartmentID-user>;

   -- 1) Lookup
   EXEC dbo.usp_Lookup_CostCenters @DepartmentID = @Dept;                  -- sub-department Disabled = 0
   EXEC dbo.usp_Lookup_ActiveEmployees @DepartmentID = @Dept;              -- karyawan aktif
   EXEC dbo.usp_Lookup_Locations @CoCode = 'ABL';                          -- 40 lokasi aktif ABL
   EXEC dbo.usp_Lookup_AssessmentQuestions;                                -- 12 pertanyaan
   EXEC dbo.usp_Lookup_AttachmentTypesByStage @Stage = 'REQUEST';          -- ROI, AREA_PHOTO

   -- 2) Draft minimal (hanya Title + Category) -> berhasil; CoCode/DepartmentID dari karyawan
   DECLARE @Id INT;
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'  Repair road  ', @Category = 'opex', @SavedId = @Id OUTPUT;
   EXEC dbo.usp_Request_GetById @Id = @Id, @Username = @U;                -- Status DRAFT, Title 'Repair road', OPEX

   -- 3) Validasi -> 50072
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'', @Category = 'OPEX';
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'XYZ';
   DECLARE @ScCapex INT = (SELECT Id FROM dbo.SubCategory WHERE Code = 'CONSTRUCTION_PROJECT');
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @SubCategoryId = @ScCapex;   -- sub-kategori CAPEX
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @SubDepartmentID = -1;
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @PicEmployeeCode = 'TIDAK_ADA';
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @TargetCompletionDate = '2020-01-01';
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @AreaLength = 0;
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @AssessmentJson = N'[{"q":999999,"a":true}]';

   -- 4) Ubah draft lengkap + jawaban assessment; luas = panjang x lebar
   DECLARE @Q1 INT = (SELECT MIN(Id) FROM dbo.AssessmentQuestion WHERE IsActive = 1);
   DECLARE @Json NVARCHAR(MAX) = N'[{"q":' + CAST(@Q1 AS NVARCHAR(10)) + N',"a":true}]';
   DECLARE @ScOpex INT = (SELECT Id FROM dbo.SubCategory WHERE Code = 'CORRECTIVE_MAINT');
   EXEC dbo.usp_Request_SaveDraft @Id = @Id, @Username = @U, @Title = N'Repair road B', @Category = 'OPEX',
        @SubCategoryId = @ScOpex,
        @BudgetRemarks = 'budgeted', @AreaLength = 12.5, @AreaWidth = 4, @BudgetExpectation = 15000000,
        @TargetCompletionDate = '2026-12-31', @AssessmentJson = @Json, @SavedId = @Id OUTPUT;
   EXEC dbo.usp_Request_GetById @Id = @Id, @Username = @U;                -- AreaSize 50.00, BUDGETED
   EXEC dbo.usp_Request_GetAssessment @RequestId = @Id, @Username = @U;   -- 12 baris, 1 terjawab (1), sisanya NULL

   -- 5) Lingkup: user departemen lain (adm ABRV lain) -> 0 baris; ubah -> 50073
   EXEC dbo.usp_Request_GetById @Id = @Id, @Username = N'<user-adm-dept-lain>';
   EXEC dbo.usp_Request_SaveDraft @Id = @Id, @Username = N'<user-adm-dept-lain>', @Title = N'X', @Category = 'OPEX';

   -- 6) List dalam lingkup
   DECLARE @Total INT;
   EXEC dbo.usp_Request_GetPaged @Username = @U, @TotalCount = @Total OUTPUT;   SELECT @Total;
   EXEC dbo.usp_Request_GetPaged @Username = @U, @Search = N'road', @Status = 'DRAFT', @TotalCount = @Total OUTPUT;

   -- 7) Lampiran (metadata saja; file dibuat aplikasi)
   DECLARE @T INT = (SELECT Id FROM dbo.AttachmentType WHERE Code = 'AREA_PHOTO'), @A INT;
   EXEC dbo.usp_RequestAttachment_Insert @RequestId = @Id, @Username = @U, @AttachmentTypeId = @T,
        @OriginalFileName = N'area.JPG', @RelativePath = N'2026\1\test.jpg', @ContentType = 'image/jpeg',
        @FileSizeBytes = 1000, @NewId = @A OUTPUT;                                       -- berhasil (ekstensi jpg)
   EXEC dbo.usp_RequestAttachment_Insert @RequestId = @Id, @Username = @U, @AttachmentTypeId = @T,
        @OriginalFileName = N'area.exe', @RelativePath = N'x', @ContentType = 'x', @FileSizeBytes = 1000;     -- 50072 ekstensi
   EXEC dbo.usp_RequestAttachment_Insert @RequestId = @Id, @Username = @U, @AttachmentTypeId = @T,
        @OriginalFileName = N'big.pdf', @RelativePath = N'x', @ContentType = 'x', @FileSizeBytes = 6000000;   -- 50072 ukuran (> 5 MB)
   DECLARE @Boq INT = (SELECT Id FROM dbo.AttachmentType WHERE Code = 'BOQ');
   EXEC dbo.usp_RequestAttachment_Insert @RequestId = @Id, @Username = @U, @AttachmentTypeId = @Boq,
        @OriginalFileName = N'boq.pdf', @RelativePath = N'x', @ContentType = 'x', @FileSizeBytes = 1000;      -- 50072 tahap
   EXEC dbo.usp_RequestAttachment_ListByRequest @RequestId = @Id, @Username = @U;   -- 1 baris
   EXEC dbo.usp_RequestAttachment_Deactivate @Id = @A, @Username = @U;
   EXEC dbo.usp_RequestAttachment_ListByRequest @RequestId = @Id, @Username = @U;   -- 0 baris (data tetap ada, IsActive = 0)

   -- 8) Status bukan draft -> 50074 (simulasi; kembalikan setelahnya)
   UPDATE dbo.ProjectRequest SET Status = 'WAITING_APPROVAL' WHERE Id = @Id;
   EXEC dbo.usp_Request_SaveDraft @Id = @Id, @Username = @U, @Title = N'X', @Category = 'OPEX';      -- 50074
   UPDATE dbo.ProjectRequest SET Status = 'DRAFT' WHERE Id = @Id;

   -- 9) Bersihkan data uji (dev saja):
   --    DELETE dbo.RequestAttachment       WHERE RequestId = @Id;
   --    DELETE dbo.RequestAssessmentAnswer WHERE RequestId = @Id;
   --    DELETE dbo.ProjectRequest          WHERE Id = @Id;
   ===================================================================== */
GO
/* ---------- end Request.sql ---------- */
/* ---------- begin RequestSubmit.sql ---------- */
PRINT N'[skema] RequestSubmit.sql';
GO
/* =====================================================================
   RequestSubmit.sql  -  Request: Submit / Resubmit / Cancel (T2-2; PRD 3.1, 3.9, 6.1, BR-04, BR-09, BR-10,
                         BR-37, BR-41, BR-42, BR-43, BR-52, BR-55, BR-62, ST-02, ST-04, ST-16)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Request.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Submit memeriksa kelengkapan penuh (6.1): field wajib, sub-kategori/cost center/lokasi/PIC valid,
       semua pertanyaan assessment aktif terjawab, ROI untuk CAPEX (BR-42), dan lampiran wajib tahap
       REQUEST per kategori dari tabel jenis lampiran (BR-43, BR-45). Semua kekurangan disebut sekaligus.
     - Nomor (BR-41/BR-62) dibuat pada Submit PERTAMA: {ABRV}-{CPX|OPX|LVE}-{MM}-{YY}-{NNN};
       NKM: NKM-{ABRV tanpa " - NKM"}-...; urutan NNN per Company + ABRV + kategori + bulan + tahun.
       Resubmit setelah Revise: nomor tetap (Keputusan 04-11-2026).
     - Snapshot langkah approval titik REQUEST dari dbo.WorkflowStep (BR-37, BR-52) ke dbo.ApprovalStep
       setiap Submit/Resubmit sebagai ronde baru; semua langkah mulai lagi (BR-04). Tanpa langkah
       yang berlaku -> langsung FEASIBILITY.
     - Snapshot assessment: teks/urutan pertanyaan disegarkan saat Submit; jawaban pertanyaan yang
       sudah nonaktif dibuang.
     - Cancel (BR-09): requester, sebelum ada langkah management approval yang disetujui; alasan wajib.
     - Semua aksi tercatat di dbo.ApprovalHistory (BR-10). Hak per role di Controller (RoleAuthorize);
       lingkup data lewat dbo.fn_User_AllowedDepartments.
   Error   : 50072 = Input wajib kosong / tidak valid / data belum lengkap
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.RequestNoSequence  (BR-41: urutan NNN)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestNoSequence', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestNoSequence
    (
        CoCode     VARCHAR(10)  NOT NULL,
        Abrv       VARCHAR(30)  NOT NULL,
        Category   VARCHAR(10)  NOT NULL,
        SeqYear    SMALLINT     NOT NULL,
        SeqMonth   TINYINT      NOT NULL,
        LastNo     INT          NOT NULL,
        UpdatedAt  DATETIME2(3) NOT NULL CONSTRAINT DF_RequestNoSequence_UpdatedAt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_RequestNoSequence PRIMARY KEY CLUSTERED (CoCode, Abrv, Category, SeqYear, SeqMonth)
    );
END
GO

/* ---------------------------------------------------------------------
   2. TABLE dbo.RequestNoHistory  (BR-54: nomor lama tetap tercatat dan bisa dicari)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestNoHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestNoHistory
    (
        Id         INT IDENTITY(1,1) NOT NULL,
        RequestId  INT           NOT NULL,
        RequestNo  VARCHAR(40)   NOT NULL,
        Reason     VARCHAR(20)   NOT NULL,   -- SUBMIT | CATEGORY_CHANGE (T3)
        CreatedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_RequestNoHistory_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy  NVARCHAR(100) NULL,
        CONSTRAINT PK_RequestNoHistory PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_RequestNoHistory_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT CK_RequestNoHistory_Reason  CHECK (Reason IN ('SUBMIT', 'CATEGORY_CHANGE'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_RequestNoHistory_RequestNo' AND object_id = OBJECT_ID(N'dbo.RequestNoHistory'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_RequestNoHistory_RequestNo ON dbo.RequestNoHistory (RequestNo) INCLUDE (RequestId);
END
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.ApprovalStep  (snapshot langkah approval per request; BR-37)
      Round  = ronde Submit (1, 2, ...) per titik; langkah aktif = PENDING dengan StepOrder terkecil
               pada ronde terakhir. StartedAt diisi saat langkah menjadi aktif.
      Status : PENDING | APPROVED | REVISED | REJECTED | VOID (ronde dibatalkan / ditutup)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ApprovalStep', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ApprovalStep
    (
        Id                   INT IDENTITY(1,1) NOT NULL,
        RequestId            INT            NOT NULL,
        [Point]              VARCHAR(10)    NOT NULL,
        Round                INT            NOT NULL,
        StepOrder            INT            NOT NULL,
        WorkflowStepId       INT            NULL,      -- asal definisi (informasi saja)
        RoleCode             VARCHAR(50)    NOT NULL,
        Scope                VARCHAR(10)    NOT NULL,
        DepartmentGroupCode  VARCHAR(20)    NULL,
        ReviseTo             VARCHAR(10)    NULL,
        AllowReject          BIT            NOT NULL,
        Status               VARCHAR(10)    NOT NULL CONSTRAINT DF_ApprovalStep_Status DEFAULT ('PENDING'),
        StartedAt            DATETIME2(3)   NULL,
        ActedAt              DATETIME2(3)   NULL,
        ActedBy              NVARCHAR(100)  NULL,
        Remarks              NVARCHAR(1000) NULL,
        CreatedAt            DATETIME2(3)   NOT NULL CONSTRAINT DF_ApprovalStep_CreatedAt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_ApprovalStep PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ApprovalStep_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT UQ_ApprovalStep UNIQUE (RequestId, [Point], Round, StepOrder),
        CONSTRAINT CK_ApprovalStep_Point  CHECK ([Point] IN ('REQUEST', 'MGMT', 'BAPP', 'ADDENDUM')),   -- ADDENDUM: T4-4
        CONSTRAINT CK_ApprovalStep_Scope  CHECK (Scope IN ('DEPT', 'GROUP', 'PLANT')),
        CONSTRAINT CK_ApprovalStep_Status CHECK (Status IN ('PENDING', 'APPROVED', 'REVISED', 'REJECTED', 'VOID'))
    );
END
GO

/* ---------------------------------------------------------------------
   4. TABLE dbo.ApprovalHistory  (jejak semua aksi; BR-10)
      Action: SUBMIT | RESUBMIT | CANCEL (T2-2) · APPROVE | REVISE | REJECT (T2-3) · lainnya menyusul.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ApprovalHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ApprovalHistory
    (
        Id              INT IDENTITY(1,1) NOT NULL,
        RequestId       INT            NOT NULL,
        ApprovalStepId  INT            NULL,
        Action          VARCHAR(20)    NOT NULL,
        FromStatus      VARCHAR(20)    NULL,
        ToStatus        VARCHAR(20)    NULL,
        Remarks         NVARCHAR(1000) NULL,
        ActionBy        NVARCHAR(100)  NOT NULL,
        ActionAt        DATETIME2(3)   NOT NULL CONSTRAINT DF_ApprovalHistory_ActionAt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_ApprovalHistory PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ApprovalHistory_Request FOREIGN KEY (RequestId)      REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_ApprovalHistory_Step    FOREIGN KEY (ApprovalStepId) REFERENCES dbo.ApprovalStep (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_ApprovalHistory_Request' AND object_id = OBJECT_ID(N'dbo.ApprovalHistory'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ApprovalHistory_Request ON dbo.ApprovalHistory (RequestId, ActionAt);
END
GO

/* ---------------------------------------------------------------------
   5. usp_Request_Submit  (Submit pertama dan Resubmit setelah Revise)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_Submit
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);

    BEGIN TRANSACTION;

    DECLARE @Status VARCHAR(20), @CoCode VARCHAR(10), @DeptId INT, @Category VARCHAR(10),
            @RequestNo VARCHAR(40), @SubmittedAt DATETIME2(3);

    -- Kunci baris request (cegah submit ganda bersamaan)
    SELECT  @Status = r.Status, @CoCode = r.CoCode, @DeptId = r.DepartmentID, @Category = r.Category,
            @RequestNo = r.RequestNo, @SubmittedAt = r.SubmittedAt
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status NOT IN ('DRAFT', 'RETURNED')
        THROW 50074, N'Only draft or returned requests can be submitted.', 1;

    /* -- Kelengkapan (6.1) -- */
    DECLARE @Missing NVARCHAR(MAX) = N'';

    SELECT @Missing =
             CASE WHEN r.PicEmployeeCode IS NULL
                    OR NOT EXISTS (SELECT 1 FROM home..app_employees e
                                   WHERE e.EmployeeCode = r.PicEmployeeCode AND e.DepartmentID = r.DepartmentID
                                     AND (e.ResignDate IS NULL OR e.ResignDate > @Now))
                  THEN N', PIC of project (active employee)' ELSE N'' END
           + CASE WHEN r.SubCategoryId IS NULL
                    OR NOT EXISTS (SELECT 1 FROM dbo.SubCategory s
                                   WHERE s.Id = r.SubCategoryId AND s.Category = r.Category AND s.IsActive = 1)
                  THEN N', Sub-category' ELSE N'' END
           + CASE WHEN r.BudgetRemarks IS NULL THEN N', Budget remarks' ELSE N'' END
           + CASE WHEN r.SubDepartmentID IS NULL
                    OR NOT EXISTS (SELECT 1 FROM home..APP_SubDepartments sd
                                   WHERE sd.SubDepartmentID = r.SubDepartmentID AND sd.DepartmentID = r.DepartmentID
                                     AND sd.Disabled = 0)
                  THEN N', Cost center' ELSE N'' END
           + CASE WHEN r.LocationId IS NULL
                    OR NOT EXISTS (SELECT 1 FROM dbo.Location l WHERE l.Id = r.LocationId AND l.CoCode = r.CoCode AND l.IsActive = 1)
                  THEN N', Location' ELSE N'' END
           + CASE WHEN r.TargetCompletionDate IS NULL OR r.TargetCompletionDate < @Today
                  THEN N', Target completion (today or later)' ELSE N'' END
           + CASE WHEN r.AreaLength IS NULL OR r.AreaWidth IS NULL THEN N', Section area (length and width)' ELSE N'' END
           + CASE WHEN r.BudgetExpectation IS NULL OR r.BudgetExpectation <= 0 THEN N', Budget expectation' ELSE N'' END
           + CASE WHEN r.Background        IS NULL THEN N', Background'            ELSE N'' END
           + CASE WHEN r.Objective         IS NULL THEN N', Objective'             ELSE N'' END
           + CASE WHEN r.OperationalImpact IS NULL THEN N', Impact to operational' ELSE N'' END
           + CASE WHEN r.RiskIfNotApproved IS NULL THEN N', Risk if not approved'  ELSE N'' END
           + CASE WHEN r.ExpectedBenefits  IS NULL THEN N', Expected benefits'     ELSE N'' END
           + CASE WHEN r.Alternatives      IS NULL THEN N', Alternatives'          ELSE N'' END
           + CASE WHEN r.Category = 'CAPEX' AND r.ExpectedRoiPercent IS NULL AND r.RoiExplanation IS NULL
                  THEN N', Expected ROI (% or explanation)' ELSE N'' END
    FROM   dbo.ProjectRequest r
    WHERE  r.Id = @Id;

    IF EXISTS (SELECT 1 FROM dbo.AssessmentQuestion q
               WHERE q.IsActive = 1
                 AND NOT EXISTS (SELECT 1 FROM dbo.RequestAssessmentAnswer a WHERE a.RequestId = @Id AND a.QuestionId = q.Id))
        SET @Missing += N', Environment assessment (all questions)';

    SELECT @Missing += N', ' + t.Name + N' attachment'
    FROM   dbo.AttachmentType t
    WHERE  t.Stage = 'REQUEST' AND t.IsActive = 1
      AND  1 = CASE @Category WHEN 'CAPEX' THEN CAST(t.IsMandatoryCapex AS INT)
                              WHEN 'OPEX'  THEN CAST(t.IsMandatoryOpex  AS INT)
                              WHEN 'LVE'   THEN CAST(t.IsMandatoryLve   AS INT) END
      AND  NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a
                       WHERE a.RequestId = @Id AND a.AttachmentTypeId = t.Id AND a.IsActive = 1)
    ORDER BY t.Name;

    IF @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(2048) = LEFT(N'Please complete before submitting: ' + STUFF(@Missing, 1, 2, N'') + N'.', 2048);
        THROW 50072, @Msg, 1;
    END

    /* -- Nomor request: hanya Submit pertama (BR-41, BR-62) -- */
    DECLARE @IsResubmit BIT = CASE WHEN @RequestNo IS NULL THEN 0 ELSE 1 END;

    IF @RequestNo IS NULL
    BEGIN
        DECLARE @Abrv VARCHAR(30) =
        (
            SELECT LTRIM(RTRIM(REPLACE(d.ABRV, ' - NKM', '')))
            FROM   home..APP_Departments d
            WHERE  d.DepartmentID = @DeptId
        );
        IF ISNULL(@Abrv, '') = ''
            THROW 50072, N'The requesting department has no abbreviation (ABRV); request number cannot be generated.', 1;

        DECLARE @NumDate DATETIME2(3) = ISNULL(@SubmittedAt, @Now);
        DECLARE @Yr SMALLINT = YEAR(@NumDate), @Mon TINYINT = MONTH(@NumDate), @Next INT;

        UPDATE dbo.RequestNoSequence WITH (UPDLOCK, HOLDLOCK)
        SET    @Next = LastNo = LastNo + 1,
               UpdatedAt = @Now
        WHERE  CoCode = @CoCode AND Abrv = @Abrv AND Category = @Category AND SeqYear = @Yr AND SeqMonth = @Mon;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @Next = 1;
            INSERT INTO dbo.RequestNoSequence (CoCode, Abrv, Category, SeqYear, SeqMonth, LastNo)
            VALUES (@CoCode, @Abrv, @Category, @Yr, @Mon, @Next);
        END

        SET @RequestNo = CASE WHEN @CoCode = 'NKM' THEN 'NKM-' ELSE '' END
                       + @Abrv + '-'
                       + CASE @Category WHEN 'CAPEX' THEN 'CPX' WHEN 'OPEX' THEN 'OPX' ELSE 'LVE' END + '-'
                       + RIGHT('0' + CAST(@Mon AS VARCHAR(2)), 2) + '-'
                       + RIGHT(CAST(@Yr AS VARCHAR(4)), 2) + '-'
                       + RIGHT('00' + CAST(@Next AS VARCHAR(10)), CASE WHEN @Next > 999 THEN LEN(CAST(@Next AS VARCHAR(10))) ELSE 3 END);

        INSERT INTO dbo.RequestNoHistory (RequestId, RequestNo, Reason, CreatedBy)
        VALUES (@Id, @RequestNo, 'SUBMIT', @Username);
    END

    /* -- Snapshot assessment: segarkan teks/urutan, buang jawaban pertanyaan nonaktif -- */
    DELETE a
    FROM   dbo.RequestAssessmentAnswer a
    WHERE  a.RequestId = @Id
      AND  NOT EXISTS (SELECT 1 FROM dbo.AssessmentQuestion q WHERE q.Id = a.QuestionId AND q.IsActive = 1);

    UPDATE a
    SET    a.QuestionText = q.QuestionText,
           a.SortOrder    = q.SortOrder
    FROM   dbo.RequestAssessmentAnswer a
           JOIN dbo.AssessmentQuestion q ON q.Id = a.QuestionId
    WHERE  a.RequestId = @Id;

    /* -- Snapshot langkah approval REQUEST: ronde baru (BR-37, BR-52, BR-04) -- */
    DECLARE @Round INT = ISNULL((SELECT MAX(Round) FROM dbo.ApprovalStep WHERE RequestId = @Id AND [Point] = 'REQUEST'), 0) + 1;

    -- Sisa langkah ronde lama (mis. setelah Revise) ditutup
    UPDATE dbo.ApprovalStep SET Status = 'VOID'
    WHERE  RequestId = @Id AND [Point] = 'REQUEST' AND Status = 'PENDING';

    INSERT INTO dbo.ApprovalStep
        (RequestId, [Point], Round, StepOrder, WorkflowStepId, RoleCode, Scope, DepartmentGroupCode, ReviseTo, AllowReject)
    SELECT  @Id, 'REQUEST', @Round, w.StepOrder, w.Id, w.RoleCode, w.Scope, w.DepartmentGroupCode, w.ReviseTo, w.AllowReject
    FROM    dbo.WorkflowStep w
    WHERE   w.CoCode = @CoCode
      AND   w.[Point] = 'REQUEST'
      AND   w.IsActive = 1
      AND   (w.Category IS NULL OR w.Category = @Category)
      AND   (
                w.DepartmentGroupCode IS NULL
                OR EXISTS (SELECT 1
                           FROM   dbo.DepartmentGroup g
                                  JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                           WHERE  g.CoCode = w.CoCode AND g.GroupCode = w.DepartmentGroupCode AND g.IsActive = 1
                             AND  m.DepartmentID = @DeptId)
            );

    DECLARE @StepCount INT = @@ROWCOUNT;   -- ambil segera, sebelum statement lain mengubah @@ROWCOUNT
    DECLARE @NewStatus VARCHAR(20) = 'FEASIBILITY';

    IF @StepCount > 0
    BEGIN
        SET @NewStatus = 'WAITING_APPROVAL';
        -- Langkah pertama menjadi aktif
        UPDATE dbo.ApprovalStep SET StartedAt = @Now
        WHERE  RequestId = @Id AND [Point] = 'REQUEST' AND Round = @Round
          AND  StepOrder = (SELECT MIN(StepOrder) FROM dbo.ApprovalStep
                            WHERE RequestId = @Id AND [Point] = 'REQUEST' AND Round = @Round);
    END

    /* -- Status request + jejak -- */
    UPDATE dbo.ProjectRequest
    SET    Status      = @NewStatus,
           RequestNo   = @RequestNo,
           SubmittedAt = ISNULL(SubmittedAt, @Now),
           UpdatedAt   = @Now,
           UpdatedBy   = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, ActionBy, ActionAt)
    VALUES (@Id, CASE WHEN @IsResubmit = 1 THEN 'RESUBMIT' ELSE 'SUBMIT' END, @Status, @NewStatus, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @RequestNo AS RequestNo, @NewStatus AS Status;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Request_Cancel  (BR-09, ST-16)
      Boleh pada DRAFT, WAITING_APPROVAL, RETURNED, FEASIBILITY, DOC_PREPARATION, MGMT_APPROVAL,
      selama belum ada langkah MGMT yang APPROVED pada ronde terakhir. Alasan wajib.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_Cancel
    @Id        INT,
    @Username  NVARCHAR(100),
    @Reason    NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    IF @Reason IS NULL           THROW 50072, N'Cancellation reason is required.', 1;
    IF LEN(@Reason) > 1000       THROW 50072, N'Cancellation reason must be at most 1000 characters.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME(), @Status VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT @Status = r.Status
    FROM   dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE  r.Id = @Id
      AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status NOT IN ('DRAFT', 'WAITING_APPROVAL', 'RETURNED', 'FEASIBILITY', 'DOC_PREPARATION', 'MGMT_APPROVAL')
        THROW 50074, N'This request can no longer be cancelled.', 1;
    IF EXISTS (SELECT 1 FROM dbo.ApprovalStep s
               WHERE s.RequestId = @Id AND s.[Point] = 'MGMT' AND s.Status = 'APPROVED'
                 AND s.Round = (SELECT MAX(Round) FROM dbo.ApprovalStep WHERE RequestId = @Id AND [Point] = 'MGMT'))
        THROW 50074, N'This request can no longer be cancelled after management approval has started.', 1;

    UPDATE dbo.ApprovalStep SET Status = 'VOID'
    WHERE  RequestId = @Id AND Status = 'PENDING';

    UPDATE dbo.ProjectRequest
    SET    Status = 'CANCELLED', UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'CANCEL', @Status, 'CANCELLED', @Reason, @Username, @Now);

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   7. usp_Request_GetApprovalSteps  (ronde terakhir per titik, untuk Details)
      IsCurrent = langkah aktif (PENDING dengan StepOrder terkecil pada ronde terakhir).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetApprovalSteps
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                   WHERE r.Id = @RequestId
                     AND EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
        RETURN;

    ;WITH lastRound AS
    (
        SELECT [Point], MAX(Round) AS Round
        FROM   dbo.ApprovalStep
        WHERE  RequestId = @RequestId
        GROUP BY [Point]
    )
    SELECT  s.Id, s.[Point], s.Round, s.StepOrder, s.RoleCode, h.Description AS RoleName, s.Scope,
            s.DepartmentGroupCode, s.ReviseTo, s.AllowReject, s.Status, s.StartedAt, s.ActedAt, s.ActedBy, s.Remarks,
            CAST(CASE WHEN s.Status = 'PENDING' AND s.StartedAt IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsCurrent
    FROM    dbo.ApprovalStep s
            JOIN lastRound lr ON lr.[Point] = s.[Point] AND lr.Round = s.Round
            LEFT JOIN dbo.HierarchyLevel h ON h.[Role] = s.RoleCode
    WHERE   s.RequestId = @RequestId
      AND   s.[Point] <> 'ADDENDUM'          -- T4-4: langkah addendum tampil di kartu Addendum (usp_Addendum_GetByRequest)
    ORDER BY CHARINDEX(',' + s.[Point] + ',', ',REQUEST,MGMT,BAPP,'), s.StepOrder;
END
GO

/* ---------------------------------------------------------------------
   8. usp_Request_GetHistory  (jejak aksi, terbaru di atas)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetHistory
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  h.Id, h.Action, h.FromStatus, h.ToStatus, h.Remarks, h.ActionBy, e.FullName AS ActionByName, h.ActionAt,
            s.[Point], s.StepOrder, s.RoleCode
    FROM    dbo.ApprovalHistory h
            JOIN dbo.ProjectRequest r       ON r.Id = h.RequestId
            LEFT JOIN dbo.ApprovalStep s    ON s.Id = h.ApprovalStepId
            LEFT JOIN home..users u         ON u.Username = h.ActionBy
            LEFT JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
    WHERE   h.RequestId = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
    ORDER BY h.ActionAt DESC, h.Id DESC;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel hanya hidup dalam satu eksekusi: jalankan blok bersama DECLARE-nya.

   DECLARE @U NVARCHAR(100) = N'asimbolon', @Id INT = 1;

   -- 1) Draft belum lengkap -> 50072 dengan daftar kekurangan (field, assessment, Area Photo, ROI bila CAPEX)
   --EXEC dbo.usp_Request_Submit @Id = @Id, @Username = @U;

   -- 2) Lengkapi lewat aplikasi (semua field, 12 jawaban, upload Area Photo; CAPEX: ROI + lampiran ROI), lalu:
   --EXEC dbo.usp_Request_Submit @Id = @Id, @Username = @U;     -- RequestNo mis. QC-OPX-11-26-001, Status WAITING_APPROVAL
   --SELECT * FROM dbo.RequestNoSequence;
   --SELECT * FROM dbo.RequestNoHistory WHERE RequestId = 1;
   EXEC dbo.usp_Request_GetApprovalSteps @RequestId = 1, @Username = @U;
   --    Departemen non-MILL ABL: 1 langkah kabag (IsCurrent = 1)
   --    Departemen MILL (C100/C200/D100/D200/C600/D600): kabag (aktif) lalu mo
   --    NKM: 1 langkah kabag
   EXEC dbo.usp_Request_GetHistory @RequestId = 1, @Username = @U;   -- SUBMIT, DRAFT -> WAITING_APPROVAL

   -- 3) Submit lagi -> 50074; ubah draft -> 50074 (bukan DRAFT/RETURNED)
   EXEC dbo.usp_Request_Submit @Id =1, @Username = @U;

   -- 4) Simulasi Revise (T2-3 belum ada): kembalikan ke RETURNED, lalu Resubmit
   UPDATE dbo.ProjectRequest SET Status = 'RETURNED' WHERE Id = 1;
   UPDATE dbo.ApprovalStep SET Status = 'REVISED', ActedAt = SYSDATETIME(), ActedBy = N'uji'
   WHERE  RequestId = 1 AND [Point] = 'REQUEST' AND Status = 'PENDING' AND StartedAt IS NOT NULL;
   EXEC dbo.usp_Request_Submit @Id = 1, @Username = 'asimbolon';     -- nomor SAMA, ronde 2, Action RESUBMIT
   SELECT RequestId, [Point], Round, StepOrder, RoleCode, Status, StartedAt FROM dbo.ApprovalStep WHERE RequestId = 1 ORDER BY Round, StepOrder;

   -- 5) Nomor berikutnya (Company + ABRV + kategori + bulan sama) -> NNN + 1; kategori lain -> mulai 001
   --    (submit draft kedua yang lengkap)

   -- 6) Cancel: alasan kosong -> 50072; berhasil -> CANCELLED, langkah PENDING -> VOID; cancel lagi -> 50074
   EXEC dbo.usp_Request_Cancel @Id = 1, @Username = 'asimbolon', @Reason = N'';
   EXEC dbo.usp_Request_Cancel @Id = 1, @Username = 'asimbolon', @Reason = N'Budget moved to next year';
   EXEC dbo.usp_Request_Cancel @Id = 1, @Username = 'asimbolon', @Reason = N'again';

   -- 7) Lingkup: user departemen lain -> 50073; GetApprovalSteps/GetHistory -> 0 baris
   EXEC dbo.usp_Request_Submit @Id = 1, @Username = N'adpurba';
   ===================================================================== */
GO
/* ---------- end RequestSubmit.sql ---------- */
/* ---------- begin RequestApproval.sql ---------- */
PRINT N'[skema] RequestApproval.sql';
GO
/* =====================================================================
   RequestApproval.sql  -  Approval request sebelum Civil (T2-3; PRD 3.9, 5.2, BR-03, BR-08, BR-10, BR-24,
                           BR-28, BR-30, BR-39, BR-50, BR-63, ST-02, ST-03, ST-04, ST-15)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestSubmit.sql.
   Waktu   : Local time (SYSDATETIME / GETDATE), bukan UTC.
   Catatan :
     - Hak aksi per langkah dari snapshot dbo.ApprovalStep (BR-37), bukan hardcode role:
         * user memegang RoleCode langkah (home..users.[Role], dipisah ';'), karyawan belum resign;
         * CoCode karyawan = CoCode request (BR-63);
         * lingkup: DEPT = ABRV departemen karyawan sama dengan ABRV departemen request (BR-24);
                    GROUP = departemen request anggota grup langkah (mis. MILL) pada Company request (BR-50);
                    PLANT = cukup Company sama;
         * bukan requester request tersebut (BR-30).
     - Langkah aktif = PENDING + StartedAt terisi pada ronde terakhir titiknya, dan status request sesuai
       titik (REQUEST -> WAITING_APPROVAL, MGMT -> MGMT_APPROVAL, BAPP -> BAPP_REVIEW,
       ADDENDUM -> SCHEDULING / IN_PROGRESS; aksinya lewat usp_Addendum_ApprovalAct, RequestAddendum.sql).
     - BR-39 (yang pertama berlaku): baris request dikunci (UPDLOCK) dan aksi wajib menyebut @StepId yang
       dilihat user; bila langkah itu sudah diproses orang lain -> 50074.
     - Titik REQUEST (T2-3), MGMT (T3-3: GM, lalu Director untuk CAPEX; NKM: Director), BAPP (T6-1: APPROVE terakhir
       -> CLOSED; REVISE (No) -> IN_PROGRESS, RequestBapp.sql).
     - Aksi:
         APPROVE -> langkah berikut aktif; tanpa langkah berikut -> REQUEST: FEASIBILITY (ST-04),
                    MGMT: PLANNING (ST-08)
         REVISE  -> sesuai ReviseTo langkah: REQUESTER -> RETURNED (ST-03); CIVIL -> FEASIBILITY (BR-06, BR-07;
                    Civil menilai ulang, lalu Document Preparation dan kirim ulang = ronde MGMT baru, BR-53);
                    catatan wajib
         REJECT  -> REJECTED (ST-15), hanya bila AllowReject = 1; alasan wajib (BR-08)
       REVISE/REJECT menutup (VOID) sisa langkah PENDING ronde tersebut. Semua aksi tercatat (BR-10).
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request / langkah tidak ditemukan atau di luar lingkup user
             50074 = Status request / langkah tidak mengizinkan aksi ini (termasuk sudah diproses approver lain)
             50075 = User tidak berhak memproses langkah ini (role, lingkup, Company, atau request sendiri)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Index langkah PENDING (dipakai function di bawah dan Tugas Saya T2-4)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_ApprovalStep_Pending' AND object_id = OBJECT_ID(N'dbo.ApprovalStep'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ApprovalStep_Pending
        ON dbo.ApprovalStep (RequestId, [Point], Round)
        INCLUDE (StepOrder, RoleCode, Scope, DepartmentGroupCode, StartedAt)
        WHERE Status = 'PENDING';
END
GO

/* ---------------------------------------------------------------------
   2. dbo.fn_User_ActionableSteps(@Username)
      Langkah approval AKTIF yang boleh diproses user (semua titik). 0 baris = tidak ada tugas.
      Dipakai: usp_Request_ApprovalAct (validasi), usp_Request_GetActionableStep (tombol Details),
      Tugas Saya / badge header (T2-4).
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_ActionableSteps
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    WITH me AS
    (
        SELECT  e.CoCode, ad.ABRV
        FROM    home..users u
                JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
                LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
        WHERE   u.Username = @Username
          AND   (e.ResignDate IS NULL OR e.ResignDate > GETDATE())
    ),
    r AS
    (
        SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
        FROM   home..users u
               CROSS APPLY STRING_SPLIT(u.[Role], N';') s
        WHERE  u.Username = @Username
          AND  LTRIM(RTRIM(s.value)) <> N''
    )
    SELECT  s.Id AS ApprovalStepId, s.RequestId, s.[Point], s.Round, s.StepOrder, s.RoleCode, s.StartedAt
    FROM    dbo.ApprovalStep s
            JOIN dbo.ProjectRequest pr       ON pr.Id = s.RequestId
            JOIN home..APP_Departments rd    ON rd.DepartmentID = pr.DepartmentID
            CROSS JOIN me
    WHERE   s.Status = 'PENDING'
      AND   s.StartedAt IS NOT NULL
      AND   s.Round = (SELECT MAX(x.Round) FROM dbo.ApprovalStep x WHERE x.RequestId = s.RequestId AND x.[Point] = s.[Point])
      AND   (pr.Status = CASE s.[Point] WHEN 'REQUEST' THEN 'WAITING_APPROVAL'
                                        WHEN 'MGMT'    THEN 'MGMT_APPROVAL'
                                        WHEN 'BAPP'    THEN 'BAPP_REVIEW' END
             -- T4-4: approval addendum berjalan tanpa mengubah status request (BR-80)
             OR (s.[Point] = 'ADDENDUM' AND pr.Status IN ('SCHEDULING', 'IN_PROGRESS')))
      AND   pr.CoCode = me.CoCode                                   -- BR-63
      AND   pr.RequesterUsername <> @Username                       -- BR-30
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = s.RoleCode)  -- BR-39: satu langkah = satu role
      AND   (
                s.Scope = 'PLANT'
             OR (s.Scope = 'DEPT' AND rd.ABRV = me.ABRV)            -- BR-24
             OR (s.Scope = 'GROUP'
                 AND EXISTS (SELECT 1
                             FROM   dbo.DepartmentGroup g
                                    JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                             WHERE  g.CoCode = pr.CoCode AND g.GroupCode = s.DepartmentGroupCode AND g.IsActive = 1
                               AND  m.DepartmentID = pr.DepartmentID))
            )
);
GO

/* ---------------------------------------------------------------------
   3. usp_Request_GetActionableStep  (Details: tampilkan tombol Approve/Revise/Reject)
      0 baris = user tidak bisa memproses request ini sekarang.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetActionableStep
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
            s.Id, s.[Point], s.Round, s.StepOrder, s.RoleCode, h.Description AS RoleName, s.Scope,
            s.DepartmentGroupCode, s.ReviseTo, s.AllowReject, s.Status, s.StartedAt, s.ActedAt, s.ActedBy, s.Remarks,
            CAST(1 AS BIT) AS IsCurrent
    FROM    dbo.fn_User_ActionableSteps(@Username) a
            JOIN dbo.ApprovalStep s          ON s.Id = a.ApprovalStepId
            LEFT JOIN dbo.HierarchyLevel h   ON h.[Role] = s.RoleCode
    WHERE   a.RequestId = @RequestId
    ORDER BY s.StepOrder;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Request_ApprovalAct  (Approve / Revise / Reject langkah titik REQUEST, MGMT, dan BAPP (T6-1: Revise = No))
      @StepId  = langkah yang ditampilkan ke user (BR-39: cegah aksi ganda).
      @Action  = APPROVE | REVISE | REJECT
      @Remarks = opsional untuk APPROVE; wajib untuk REVISE dan REJECT (maks. 1000 karakter).
      Hasil    : SELECT Status (status request yang baru).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_ApprovalAct
    @Id        INT,
    @StepId    INT,
    @Username  NVARCHAR(100),
    @Action    VARCHAR(10),
    @Remarks   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Action  = UPPER(LTRIM(RTRIM(@Action)));
    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF @Action IS NULL OR @Action NOT IN ('APPROVE', 'REVISE', 'REJECT')
        THROW 50072, N'Invalid approval action.', 1;
    IF @Action = 'REVISE' AND @Remarks IS NULL
        THROW 50072, N'Revision notes are required.', 1;
    IF @Action = 'REJECT' AND @Remarks IS NULL
        THROW 50072, N'Rejection reason is required.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @Requester NVARCHAR(100);

    BEGIN TRANSACTION;

    -- Kunci baris request: aksi bersamaan pada request yang sama diproses berurutan (BR-39)
    SELECT  @Status = r.Status, @Requester = r.RequesterUsername
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;

    DECLARE @Point VARCHAR(10), @Round INT, @StepOrder INT, @StepStatus VARCHAR(10), @StartedAt DATETIME2(3),
            @ReviseTo VARCHAR(10), @AllowReject BIT;

    SELECT  @Point = s.[Point], @Round = s.Round, @StepOrder = s.StepOrder, @StepStatus = s.Status,
            @StartedAt = s.StartedAt, @ReviseTo = s.ReviseTo, @AllowReject = s.AllowReject
    FROM    dbo.ApprovalStep s
    WHERE   s.Id = @StepId AND s.RequestId = @Id;

    IF @Point IS NULL
        THROW 50073, N'Approval step not found.', 1;
    -- T2-3: REQUEST · T3-3: MGMT (GM / Director) · T6-1: BAPP (Kabag -> FAT -> GM/Director). ADDENDUM: usp_Addendum_ApprovalAct.
    IF @Point NOT IN ('REQUEST', 'MGMT', 'BAPP')
        THROW 50074, N'This approval step cannot be processed here.', 1;
    -- BAPP online (18-11-2026): isian form per langkah divalidasi usp_Bapp_ApprovalAct (RequestBapp.sql)
    IF @Point = 'BAPP' AND SESSION_CONTEXT(N'BappAct') IS NULL
        THROW 50074, N'Please use the BAPP approval form.', 1;

    DECLARE @PointStatus VARCHAR(20) = CASE @Point WHEN 'REQUEST' THEN 'WAITING_APPROVAL'
                                                   WHEN 'MGMT'    THEN 'MGMT_APPROVAL'
                                                   ELSE 'BAPP_REVIEW' END;

    IF @Status <> @PointStatus
       OR @StepStatus <> 'PENDING'
       OR @StartedAt IS NULL
       OR @Round <> (SELECT MAX(Round) FROM dbo.ApprovalStep WHERE RequestId = @Id AND [Point] = @Point)
        THROW 50074, N'This approval step has already been processed.', 1;

    IF @Requester = @Username
        THROW 50075, N'You cannot approve your own request.', 1;                         -- BR-30
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_ActionableSteps(@Username) a WHERE a.ApprovalStepId = @StepId)
        THROW 50075, N'You are not authorized to process this approval step.', 1;

    -- Tujuan Revise dari snapshot langkah: REQUESTER -> RETURNED, CIVIL -> FEASIBILITY (BR-06, BR-07)
    IF @Action = 'REVISE' AND ISNULL(@ReviseTo, '') NOT IN ('REQUESTER', 'CIVIL')
        THROW 50074, N'Revision is not allowed at this approval step.', 1;
    IF @Action = 'REJECT' AND @AllowReject = 0
        THROW 50074, N'Rejection is not allowed at this approval step.', 1;

    DECLARE @NewStatus VARCHAR(20);

    UPDATE dbo.ApprovalStep
    SET    Status   = CASE @Action WHEN 'APPROVE' THEN 'APPROVED' WHEN 'REVISE' THEN 'REVISED' ELSE 'REJECTED' END,
           ActedAt  = @Now,
           ActedBy  = @Username,
           Remarks  = @Remarks
    WHERE  Id = @StepId;

    IF @Action = 'APPROVE'
    BEGIN
        DECLARE @NextOrder INT =
        (
            SELECT MIN(StepOrder) FROM dbo.ApprovalStep
            WHERE  RequestId = @Id AND [Point] = @Point AND Round = @Round
              AND  Status = 'PENDING' AND StepOrder > @StepOrder
        );

        IF @NextOrder IS NOT NULL
        BEGIN
            SET @NewStatus = @PointStatus;
            UPDATE dbo.ApprovalStep SET StartedAt = @Now
            WHERE  RequestId = @Id AND [Point] = @Point AND Round = @Round AND StepOrder = @NextOrder;
        END
        ELSE
            -- Langkah terakhir: REQUEST -> FEASIBILITY (ST-04), MGMT -> PLANNING (ST-08), BAPP -> CLOSED (ST-13, BR-21)
            SET @NewStatus = CASE @Point WHEN 'REQUEST' THEN 'FEASIBILITY' WHEN 'MGMT' THEN 'PLANNING' ELSE 'CLOSED' END;
    END
    ELSE
    BEGIN
        -- ST-03 / ST-04 (Revise ke Civil) / ST-15; BAPP No -> kembali IN_PROGRESS (BR-89)
        SET @NewStatus = CASE WHEN @Action = 'REJECT'                    THEN 'REJECTED'
                              WHEN @Point = 'BAPP'                       THEN 'IN_PROGRESS'
                              WHEN @ReviseTo = 'CIVIL'                   THEN 'FEASIBILITY'
                              ELSE 'RETURNED' END;

        UPDATE dbo.ApprovalStep SET Status = 'VOID'
        WHERE  RequestId = @Id AND [Point] = @Point AND Round = @Round AND Status = 'PENDING';
    END

    UPDATE dbo.ProjectRequest
    SET    Status = @NewStatus, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    -- T6-1: status BAPP ronde ini (RequestBapp.sql); RETURNED saat No, ACCEPTED saat Closed
    IF @Point = 'BAPP' AND @NewStatus IN ('IN_PROGRESS', 'CLOSED') AND OBJECT_ID(N'dbo.ProjectBapp', N'U') IS NOT NULL
        UPDATE dbo.ProjectBapp
        SET    Status = CASE WHEN @NewStatus = 'CLOSED' THEN 'ACCEPTED' ELSE 'RETURNED' END,
               ClosedAt = @Now, ClosedBy = @Username
        WHERE  RequestId = @Id AND Round = @Round;

    INSERT INTO dbo.ApprovalHistory (RequestId, ApprovalStepId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, @StepId, @Action, @Status, @NewStatus, @Remarks, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel hanya hidup dalam satu eksekusi: jalankan blok bersama DECLARE-nya.

   -- 0) Siapkan request WAITING_APPROVAL (Submit lewat aplikasi), lalu cari user per role:
   SELECT u.Username, u.[Role], e.CoCode, ad.ABRV, ad.DepartmentID
   FROM   home..users u
          JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
          LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
   WHERE  u.[Role] LIKE N'%kabag%' OR u.[Role] LIKE N'%mo%';

   DECLARE @Id INT = 3, @Kabag NVARCHAR(100) = N'marisi', @KabagLain NVARCHAR(100) = N'hdahlia',
           @Mo NVARCHAR(100) = N'maamanullang', @Requester NVARCHAR(100) = N'asimbolon';

   -- 1) Tugas: kabag ABRV sama -> 1 baris; kabag ABRV lain / requester / mo (sebelum kabag approve) -> 0 baris
   SELECT * FROM dbo.fn_User_ActionableSteps(@Kabag)     WHERE RequestId = @Id;
   SELECT * FROM dbo.fn_User_ActionableSteps(@KabagLain) WHERE RequestId = @Id;
   SELECT * FROM dbo.fn_User_ActionableSteps(@Mo)        WHERE RequestId = @Id;
   EXEC dbo.usp_Request_GetActionableStep @RequestId = @Id, @Username = @Kabag;

DECLARE @Id INT = 3, @Kabag NVARCHAR(100) = N'marisi', @KabagLain NVARCHAR(100) = N'hdahlia',
           @Mo NVARCHAR(100) = N'maamanullang', @Requester NVARCHAR(100) = N'asimbolon';
   -- 2) Validasi input: aksi salah / Revise tanpa catatan / Reject tanpa alasan -> 50072
   DECLARE @Step INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Kabag) WHERE RequestId = @Id);
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @Kabag, @Action = 'XYZ';
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @Kabag, @Action = 'REVISE';
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @Kabag, @Action = 'REJECT', @Remarks = N'  ';

   -- 3) Tidak berhak: kabag ABRV lain -> 50073 (di luar lingkup lihat) atau 50075; requester (bila juga kabag) -> 50075
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @KabagLain, @Action = 'APPROVE';

DECLARE @Id INT = 3, @Kabag NVARCHAR(100) = N'marisi', @KabagLain NVARCHAR(100) = N'hdahlia',
           @Mo NVARCHAR(100) = N'maamanullang', @Requester NVARCHAR(100) = N'asimbolon';
    DECLARE @Step INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Kabag) WHERE RequestId = @Id);
   -- 4) Approve oleh kabag:
   --    non-MILL -> Status FEASIBILITY;  MILL -> WAITING_APPROVAL, langkah mo aktif (StartedAt terisi)
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @Kabag, @Action = 'APPROVE', @Remarks = N'OK';
   EXEC dbo.usp_Request_GetApprovalSteps @RequestId = @Id, @Username = @Kabag;
   EXEC dbo.usp_Request_GetHistory @RequestId = @Id, @Username = @Kabag;           -- APPROVE + remarks

   -- 5) Approve ulang dengan @StepId yang sama (BR-39, approver kedua) -> 50074 "already processed"
   EXEC dbo.usp_Request_ApprovalAct @Id =3, @StepId = 6, @Username = 'marisi', @Action = 'APPROVE';

   -- 6) MILL: mo Revise -> RETURNED; langkah lain ronde ini VOID; requester bisa edit dan Resubmit (ronde baru)
   DECLARE @Id INT = 3, @Kabag NVARCHAR(100) = N'marisi', @KabagLain NVARCHAR(100) = N'hdahlia',
           @Mo NVARCHAR(100) = N'maamanullang', @Requester NVARCHAR(100) = N'asimbolon';

   DECLARE @MoStep INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Mo) WHERE RequestId = @Id);
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @MoStep, @Username = @Mo, @Action = 'REVISE', @Remarks = N'Please add drawing';

   -- 7) Reject (request lain yang WAITING_APPROVAL) -> REJECTED; Submit/Cancel berikutnya -> 50074
   --EXEC dbo.usp_Request_ApprovalAct @Id = 3, @StepId = 6, @Username = 'marisi', @Action = 'REJECT', @Remarks = N'Not a priority';

   -- 8) BR-63: user role kabag dari Company lain (NKM vs ABL) -> 0 baris di fn_User_ActionableSteps
   ===================================================================== */

/* =====================================================================
   TEST T3-3 MANAGEMENT APPROVAL (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (baris TestCase / ErrNo / ErrMsg).
   CATCH wajib ROLLBACK: error di dalam transaksi SP (XACT_ABORT ON) membuat transaksi "doomed";
   tanpa ROLLBACK, statement berikutnya gagal dengan error 3998/3930.
   Prasyarat: request MGMT_APPROVAL (mis. Id 3, ABL CAPEX setelah Send to Management di T3-2).

   -- 0) Cari user gm / director ABL
   SELECT u.Username, u.[Role], e.CoCode FROM home..users u JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
   WHERE  u.[Role] LIKE N'%gm%' OR u.[Role] LIKE N'%director%';

   DECLARE @Id INT = 3, @Gm NVARCHAR(100) = N'<user gm>', @Dir NVARCHAR(100) = N'<user director>';

   -- 1) Langkah aktif: GM -> 1 baris; Director (sebelum GM approve) -> 0 baris
   EXEC dbo.usp_Request_GetActionableStep @RequestId = @Id, @Username = @Gm;
   EXEC dbo.usp_Request_GetActionableStep @RequestId = @Id, @Username = @Dir;

   -- 2) Director memakai StepId GM -> 50075; GM Revise tanpa catatan -> 50072
   DECLARE @GmStep INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Gm) WHERE RequestId = @Id AND [Point] = 'MGMT');
   BEGIN TRY EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @GmStep, @Username = @Dir, @Action = 'APPROVE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '2a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @GmStep, @Username = @Gm, @Action = 'REVISE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '2b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 3) GM Approve -> tetap MGMT_APPROVAL (CAPEX), langkah Director aktif; OPEX -> PLANNING
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @GmStep, @Username = @Gm, @Action = 'APPROVE', @Remarks = N'OK';
   EXEC dbo.usp_Request_GetApprovalSteps @RequestId = @Id, @Username = @Gm;

   -- 4a) Director Revise -> FEASIBILITY (kembali ke Civil); langkah MGMT sisa VOID; tugas FEASIBILITY Civil muncul
   DECLARE @DirStep INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Dir) WHERE RequestId = @Id AND [Point] = 'MGMT');
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @DirStep, @Username = @Dir, @Action = 'REVISE', @Remarks = N'Please revise BOQ';
   --    lalu Civil: Feasible -> Document Preparation -> Send to Management -> ronde MGMT 2 (GM lagi)
   -- 4b) atau Director Approve -> PLANNING; tugas PLANNING Civil muncul
   --EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @DirStep, @Username = @Dir, @Action = 'APPROVE';
   -- 4c) atau Reject (alasan wajib) -> REJECTED
   --EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @DirStep, @Username = @Dir, @Action = 'REJECT', @Remarks = N'Budget not available';

   -- 5) Setelah ada langkah MGMT APPROVED, requester Cancel -> 50074 (BR-09)
   ===================================================================== */
GO
/* ---------- end RequestApproval.sql ---------- */
/* ---------- begin RequestFeasibility.sql ---------- */
PRINT N'[skema] RequestFeasibility.sql';
GO
/* =====================================================================
   RequestFeasibility.sql  -  Feasibility oleh Civil (T3-1; PRD 3.1 langkah 4, BR-02, BR-04, BR-08, BR-10,
                              BR-41, BR-42, BR-54, BR-55, BR-62, ST-03, ST-04, ST-05, ST-15)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Task.sql
             (dan jalankan ulang Request.sql: pencarian nomor lama + lampiran Civil saat Feasibility).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Hanya role civil (matriks 5.2: Feasibility, ubah kategori = C/A civil), status FEASIBILITY.
       Lingkup lihat Civil = ABL dan NKM (fn_User_AllowedDepartments).
     - Ubah kategori / sub-kategori (BR-02): alasan wajib; dicatat di dbo.RequestCategoryChange
       (lama, baru, oleh, waktu, alasan) dan di riwayat (ApprovalHistory action CATEGORY_CHANGE).
       Kategori berubah -> nomor ikut berubah (BR-54): bulan/tahun tetap dari Submit awal (SubmittedAt),
       kode kategori diganti, NNN dari urutan kategori baru. Nomor baru dicatat di RequestNoHistory
       (CATEGORY_CHANGE); nomor lama tetap bisa dicari di list (usp_Request_GetPaged).
       Langkah MGMT disusun saat dikirim ke management (T3-2, BR-53), jadi tidak ada yang perlu diubah di sini.
     - Keputusan Feasibility (PRD 3.1 langkah 4):
         FEASIBLE -> DOC_PREPARATION (ST-05). Lampiran wajib tahap REQUEST untuk kategori SAAT INI harus
                     lengkap (mis. ROI bila Civil mengubah ke CAPEX; Civil boleh mengunggahnya, Keputusan 13-11-2026).
         REVISE   -> RETURNED (ST-03), catatan wajib; Resubmit melewati Kabag (dan MO) lagi (BR-04).
         REJECT   -> REJECTED (ST-15), alasan wajib (BR-08).
   Error   : 50072 = Input wajib kosong / tidak valid / data belum lengkap
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = User bukan Civil
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.RequestCategoryChange  (log BR-02)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestCategoryChange', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestCategoryChange
    (
        Id                INT IDENTITY(1,1) NOT NULL,
        RequestId         INT            NOT NULL,
        OldCategory       VARCHAR(10)    NOT NULL,
        NewCategory       VARCHAR(10)    NOT NULL,
        OldSubCategoryId  INT            NULL,
        NewSubCategoryId  INT            NOT NULL,
        OldRequestNo      VARCHAR(40)    NULL,
        NewRequestNo      VARCHAR(40)    NULL,
        Reason            NVARCHAR(1000) NOT NULL,
        ChangedBy         NVARCHAR(100)  NOT NULL,
        ChangedAt         DATETIME2(3)   NOT NULL CONSTRAINT DF_RequestCategoryChange_ChangedAt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_RequestCategoryChange PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_RequestCategoryChange_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_RequestCategoryChange_Request' AND object_id = OBJECT_ID(N'dbo.RequestCategoryChange'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_RequestCategoryChange_Request ON dbo.RequestCategoryChange (RequestId, ChangedAt);
END
GO

/* ---------------------------------------------------------------------
   2. dbo.fn_User_Roles(@Username)  (role user dari home..users.[Role], dipisah ';')
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_Roles
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
    FROM   home..users u
           CROSS APPLY STRING_SPLIT(u.[Role], N';') s
    WHERE  u.Username = @Username
      AND  LTRIM(RTRIM(s.value)) <> N''
);
GO

/* ---------------------------------------------------------------------
   3. usp_Request_ChangeCategory  (BR-02, BR-54)
      Kategori sama + sub-kategori berbeda -> tanpa renumber.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_ChangeCategory
    @Id             INT,
    @Username       NVARCHAR(100),
    @Category       VARCHAR(10),
    @SubCategoryId  INT,
    @Reason         NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Category = UPPER(LTRIM(RTRIM(@Category)));
    SET @Reason   = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    IF ISNULL(@Category, '') NOT IN ('CAPEX', 'OPEX', 'LVE')
        THROW 50072, N'Budget classification is invalid.', 1;
    IF @SubCategoryId IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.SubCategory s WHERE s.Id = @SubCategoryId AND s.Category = @Category AND s.IsActive = 1)
        THROW 50072, N'Sub-category is invalid for the selected budget classification.', 1;
    IF @Reason IS NULL
        THROW 50072, N'Reason for the change is required.', 1;
    IF LEN(@Reason) > 1000
        THROW 50072, N'Reason must be at most 1000 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can change the budget classification.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @CoCode VARCHAR(10), @DeptId INT, @OldCategory VARCHAR(10), @OldSub INT,
            @OldNo VARCHAR(40), @SubmittedAt DATETIME2(3);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @CoCode = r.CoCode, @DeptId = r.DepartmentID, @OldCategory = r.Category,
            @OldSub = r.SubCategoryId, @OldNo = r.RequestNo, @SubmittedAt = r.SubmittedAt
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'FEASIBILITY'
        THROW 50074, N'The budget classification can only be changed during feasibility.', 1;
    IF @Category = @OldCategory AND @SubCategoryId = ISNULL(@OldSub, 0)
        THROW 50072, N'No changes to the budget classification or sub-category.', 1;

    DECLARE @NewNo VARCHAR(40) = @OldNo;

    /* -- Renumber bila kategori berubah (BR-54; format BR-41 / BR-62) -- */
    IF @Category <> @OldCategory AND @OldNo IS NOT NULL
    BEGIN
        DECLARE @Abrv VARCHAR(30) =
        (
            SELECT LTRIM(RTRIM(REPLACE(d.ABRV, ' - NKM', '')))
            FROM   home..APP_Departments d
            WHERE  d.DepartmentID = @DeptId
        );
        IF ISNULL(@Abrv, '') = ''
            THROW 50072, N'The requesting department has no abbreviation (ABRV); request number cannot be generated.', 1;

        -- Bulan/tahun tetap dari Submit awal
        DECLARE @Yr SMALLINT = YEAR(@SubmittedAt), @Mon TINYINT = MONTH(@SubmittedAt), @Next INT;

        UPDATE dbo.RequestNoSequence WITH (UPDLOCK, HOLDLOCK)
        SET    @Next = LastNo = LastNo + 1,
               UpdatedAt = @Now
        WHERE  CoCode = @CoCode AND Abrv = @Abrv AND Category = @Category AND SeqYear = @Yr AND SeqMonth = @Mon;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @Next = 1;
            INSERT INTO dbo.RequestNoSequence (CoCode, Abrv, Category, SeqYear, SeqMonth, LastNo)
            VALUES (@CoCode, @Abrv, @Category, @Yr, @Mon, @Next);
        END

        SET @NewNo = CASE WHEN @CoCode = 'NKM' THEN 'NKM-' ELSE '' END
                   + @Abrv + '-'
                   + CASE @Category WHEN 'CAPEX' THEN 'CPX' WHEN 'OPEX' THEN 'OPX' ELSE 'LVE' END + '-'
                   + RIGHT('0' + CAST(@Mon AS VARCHAR(2)), 2) + '-'
                   + RIGHT(CAST(@Yr AS VARCHAR(4)), 2) + '-'
                   + RIGHT('00' + CAST(@Next AS VARCHAR(10)), CASE WHEN @Next > 999 THEN LEN(CAST(@Next AS VARCHAR(10))) ELSE 3 END);

        INSERT INTO dbo.RequestNoHistory (RequestId, RequestNo, Reason, CreatedBy)
        VALUES (@Id, @NewNo, 'CATEGORY_CHANGE', @Username);
    END

    UPDATE dbo.ProjectRequest
    SET    Category      = @Category,
           SubCategoryId = @SubCategoryId,
           RequestNo     = @NewNo,
           -- ROI hanya untuk CAPEX (BR-42): kosongkan bila bukan CAPEX lagi
           ExpectedRoiPercent = CASE WHEN @Category = 'CAPEX' THEN ExpectedRoiPercent END,
           RoiExplanation     = CASE WHEN @Category = 'CAPEX' THEN RoiExplanation END,
           UpdatedAt     = @Now,
           UpdatedBy     = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.RequestCategoryChange
        (RequestId, OldCategory, NewCategory, OldSubCategoryId, NewSubCategoryId, OldRequestNo, NewRequestNo, Reason, ChangedBy, ChangedAt)
    VALUES
        (@Id, @OldCategory, @Category, @OldSub, @SubCategoryId, @OldNo, @NewNo, @Reason, @Username, @Now);

    -- Riwayat: status tidak berubah; catatan memuat perubahan + alasan
    DECLARE @OldSubName NVARCHAR(100) = (SELECT Name FROM dbo.SubCategory WHERE Id = @OldSub),
            @NewSubName NVARCHAR(100) = (SELECT Name FROM dbo.SubCategory WHERE Id = @SubCategoryId);
    DECLARE @Note NVARCHAR(1000) = LEFT(
              @OldCategory + N' / ' + ISNULL(@OldSubName, N'-') + N' → ' + @Category + N' / ' + ISNULL(@NewSubName, N'-')
            + CASE WHEN ISNULL(@NewNo, '') <> ISNULL(@OldNo, '') THEN N' (no. ' + @OldNo + N' → ' + @NewNo + N')' ELSE N'' END
            + N'. ' + @Reason, 1000);

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'CATEGORY_CHANGE', @Status, @Status, @Note, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewNo AS RequestNo;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Request_FeasibilityDecide  (PRD 3.1 langkah 4)
      @Decision = FEASIBLE | REVISE | REJECT ; @Remarks wajib untuk REVISE / REJECT.
      Hasil: SELECT Status (status request yang baru).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_FeasibilityDecide
    @Id        INT,
    @Username  NVARCHAR(100),
    @Decision  VARCHAR(10),
    @Remarks   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Decision = UPPER(LTRIM(RTRIM(@Decision)));
    SET @Remarks  = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF ISNULL(@Decision, '') NOT IN ('FEASIBLE', 'REVISE', 'REJECT')
        THROW 50072, N'Invalid feasibility decision.', 1;
    IF @Decision = 'REVISE' AND @Remarks IS NULL
        THROW 50072, N'Revision notes are required.', 1;
    IF @Decision = 'REJECT' AND @Remarks IS NULL
        THROW 50072, N'Rejection reason is required.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can decide feasibility.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @Category VARCHAR(10);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @Category = r.Category
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'FEASIBILITY'
        THROW 50074, N'This request is not in feasibility.', 1;

    IF @Decision = 'FEASIBLE'
    BEGIN
        -- Lampiran wajib tahap REQUEST untuk kategori saat ini (mis. ROI setelah diubah ke CAPEX)
        DECLARE @Missing NVARCHAR(MAX) = N'';

        SELECT @Missing += N', ' + t.Name
        FROM   dbo.AttachmentType t
        WHERE  t.Stage = 'REQUEST' AND t.IsActive = 1
          AND  1 = CASE @Category WHEN 'CAPEX' THEN CAST(t.IsMandatoryCapex AS INT)
                                  WHEN 'OPEX'  THEN CAST(t.IsMandatoryOpex  AS INT)
                                  WHEN 'LVE'   THEN CAST(t.IsMandatoryLve   AS INT) END
          AND  NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a
                           WHERE a.RequestId = @Id AND a.AttachmentTypeId = t.Id AND a.IsActive = 1)
        ORDER BY t.Name;

        IF @Missing <> N''
        BEGIN
            DECLARE @Msg NVARCHAR(2048) = LEFT(N'Please upload the required attachments first: ' + STUFF(@Missing, 1, 2, N'') + N'.', 2048);
            THROW 50072, @Msg, 1;
        END
    END

    DECLARE @NewStatus VARCHAR(20) = CASE @Decision WHEN 'FEASIBLE' THEN 'DOC_PREPARATION'
                                                    WHEN 'REVISE'   THEN 'RETURNED'
                                                    ELSE 'REJECTED' END;

    UPDATE dbo.ProjectRequest
    SET    Status = @NewStatus, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, @Decision, @Status, @NewStatus, @Remarks, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Request_GetCategoryChanges  (log perubahan kategori untuk Details; terbaru di atas)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetCategoryChanges
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  c.Id, c.OldCategory, c.NewCategory, os.Name AS OldSubCategoryName, ns.Name AS NewSubCategoryName,
            c.OldRequestNo, c.NewRequestNo, c.Reason, c.ChangedBy, e.FullName AS ChangedByName, c.ChangedAt
    FROM    dbo.RequestCategoryChange c
            JOIN dbo.ProjectRequest r       ON r.Id = c.RequestId
            LEFT JOIN dbo.SubCategory os    ON os.Id = c.OldSubCategoryId
            LEFT JOIN dbo.SubCategory ns    ON ns.Id = c.NewSubCategoryId
            LEFT JOIN home..users u         ON u.Username = c.ChangedBy
            LEFT JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
    WHERE   c.RequestId = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
    ORDER BY c.ChangedAt DESC, c.Id DESC;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel hanya hidup dalam satu eksekusi: jalankan blok bersama DECLARE-nya.
   THROW tanpa TRY/CATCH menghentikan seluruh batch, jadi kasus yang memang
   diharapkan error dibungkus TRY/CATCH (hasilnya tampil sebagai baris ErrNo/ErrMsg).
   Prasyarat: Request.sql sudah dijalankan ulang; ada request berstatus FEASIBILITY
   (mis. Id 3 PM-OPX-11-26-002) dan user civil.

   DECLARE @Id INT = 3, @Civil NVARCHAR(100) = N'users1', @Bukan NVARCHAR(100) = N'marisi';

   -- 1) Bukan civil -> 50075; alasan kosong / sub-kategori tidak cocok kategori -> 50072
   DECLARE @Sub INT = (SELECT TOP (1) Id FROM dbo.SubCategory WHERE Category = 'CAPEX' AND IsActive = 1 ORDER BY SortOrder);
   DECLARE @SubOpex INT = (SELECT TOP (1) Id FROM dbo.SubCategory WHERE Category = 'OPEX' AND IsActive = 1 ORDER BY SortOrder);
   BEGIN TRY EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Bukan, @Category = 'CAPEX', @SubCategoryId = @Sub, @Reason = N'x';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Civil, @Category = 'CAPEX', @SubCategoryId = @Sub, @Reason = N' ';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Civil, @Category = 'CAPEX', @SubCategoryId = @SubOpex, @Reason = N'x';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) OPEX -> CAPEX: nomor baru PM-CPX-11-26-NNN (bulan/tahun sama), log + riwayat CATEGORY_CHANGE
   EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Civil, @Category = 'CAPEX', @SubCategoryId = @Sub,
        @Reason = N'Scope includes new structure';
   SELECT Id, RequestNo, Category, SubCategoryId, Status FROM dbo.ProjectRequest WHERE Id = @Id;
   SELECT * FROM dbo.RequestNoHistory WHERE RequestId = @Id ORDER BY Id;            -- SUBMIT (lama) + CATEGORY_CHANGE (baru)
   EXEC dbo.usp_Request_GetCategoryChanges @RequestId = @Id, @Username = @Civil;
   EXEC dbo.usp_Request_GetHistory @RequestId = @Id, @Username = @Civil;            -- CATEGORY_CHANGE di atas

   -- 3) Nomor lama tetap bisa dicari (BR-54)
   DECLARE @Total INT;
   EXEC dbo.usp_Request_GetPaged @Username = @Civil, @Search = N'PM-OPX-11-26-002', @TotalCount = @Total OUTPUT;   -- request Id 3 muncul

   -- 4) Sub-kategori saja berubah (kategori sama) -> nomor tetap; tanpa perubahan apa pun -> 50072
   DECLARE @Sub2 INT = (SELECT TOP (1) Id FROM dbo.SubCategory WHERE Category = 'CAPEX' AND IsActive = 1 AND Id <> @Sub ORDER BY SortOrder);
   EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Civil, @Category = 'CAPEX', @SubCategoryId = @Sub2, @Reason = N'Better fit';
   BEGIN TRY EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Civil, @Category = 'CAPEX', @SubCategoryId = @Sub2, @Reason = N'Same';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 5) FEASIBLE tanpa lampiran ROI (CAPEX) -> 50072 menyebut ROI; upload ROI lewat aplikasi sebagai civil, lalu
   --    jalankan lagi tanpa TRY/CATCH -> DOC_PREPARATION
   BEGIN TRY EXEC dbo.usp_Request_FeasibilityDecide @Id = @Id, @Username = @Civil, @Decision = 'FEASIBLE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '5 expect 50072 (ROI)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   --    berhasil -> DOC_PREPARATION; ubah kategori lagi -> 50074; tugas FEASIBILITY civil hilang
   SELECT * FROM dbo.fn_User_Tasks(@Civil) WHERE RequestId = @Id;

   -- 6) Request FEASIBILITY lain: REVISE tanpa catatan -> 50072; REVISE -> RETURNED (requester Resubmit -> Kabag lagi);
   --    REJECT dengan alasan -> REJECTED
   --EXEC dbo.usp_Request_FeasibilityDecide @Id = <id>, @Username = @Civil, @Decision = 'REVISE', @Remarks = N'Please add drawing reference';
   --EXEC dbo.usp_Request_FeasibilityDecide @Id = <id>, @Username = @Civil, @Decision = 'REJECT', @Remarks = N'Not feasible on this site';
   ===================================================================== */
GO
/* ---------- end RequestFeasibility.sql ---------- */
/* ---------- begin RequestDocPrep.sql ---------- */
PRINT N'[skema] RequestDocPrep.sql';
GO
/* =====================================================================
   RequestDocPrep.sql  -  Document Preparation + kirim ke management (T3-2; PRD 3.1 langkah 5-6,
                          BR-05, BR-06, BR-07, BR-12, BR-37, BR-52, BR-53, ST-05, ST-06)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestFeasibility.sql
             (dan jalankan ulang Request.sql: kolom BoqTotal + lampiran DOCUMENT oleh Civil; serta Task.sql:
             tugas DOC_PREPARATION untuk Civil).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Hanya role civil (matriks 5.2: BOQ, Drawing = C/A civil), status DOC_PREPARATION.
     - Lampiran BOQ dan Drawing = jenis lampiran tahap DOCUMENT (AttachmentType); wajib per kategori diambil
       dari tabel (BOQ semua kategori, Drawing CAPEX; BR-05), bukan hardcode.
     - BOQ total (IDR) wajib > 0 sebelum dikirim (Keputusan 13-11-2026; dasar plan cost in-house BR-12).
       Setiap perubahan dicatat di riwayat (action BOQ_TOTAL).
     - Kirim ke management (BR-53): langkah titik MGMT disusun dari dbo.WorkflowStep SAAT INI (kategori saat ini,
       mis. Director ikut bila sudah menjadi CAPEX) sebagai ronde baru; sisa langkah MGMT ronde lama di-VOID.
       Tanpa langkah MGMT yang cocok -> langsung PLANNING (ST-08). Approval MGMT diproses di T3-3.
   Error   : 50072 = Input wajib kosong / tidak valid / data belum lengkap
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = User bukan Civil
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_Request_SetBoqTotal  (BR-05, BR-12)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SetBoqTotal
    @Id        INT,
    @Username  NVARCHAR(100),
    @BoqTotal  DECIMAL(18, 2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @BoqTotal IS NULL OR @BoqTotal <= 0
        THROW 50072, N'BOQ total must be greater than 0.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can set the BOQ total.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @Old DECIMAL(18, 2);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @Old = r.BoqTotal
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'DOC_PREPARATION'
        THROW 50074, N'The BOQ total can only be changed during document preparation.', 1;

    IF @Old IS NULL OR @Old <> @BoqTotal
    BEGIN
        UPDATE dbo.ProjectRequest
        SET    BoqTotal = @BoqTotal, UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  Id = @Id;

        -- Riwayat: status tidak berubah; catatan memuat nilai lama -> baru
        INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
        VALUES (@Id, 'BOQ_TOTAL', @Status, @Status,
                N'BOQ total: ' + ISNULL(N'IDR ' + FORMAT(@Old, N'#,0.##', 'en-US') + N' → ', N'')
                               + N'IDR ' + FORMAT(@BoqTotal, N'#,0.##', 'en-US'),
                @Username, @Now);
    END

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   2. usp_Request_SendToManagement  (BR-06, BR-07, BR-37, BR-52, BR-53)
      Hasil: SELECT Status (MGMT_APPROVAL, atau PLANNING bila tidak ada langkah MGMT).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SendToManagement
    @Id        INT,
    @Username  NVARCHAR(100),
    @Remarks   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can send a request to management.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @CoCode VARCHAR(10), @DeptId INT, @Category VARCHAR(10), @BoqTotal DECIMAL(18, 2);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @CoCode = r.CoCode, @DeptId = r.DepartmentID, @Category = r.Category,
            @BoqTotal = r.BoqTotal
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'DOC_PREPARATION'
        THROW 50074, N'Only requests in document preparation can be sent to management.', 1;

    /* -- Kelengkapan: BOQ total + lampiran wajib tahap DOCUMENT untuk kategori saat ini (BR-05) -- */
    DECLARE @Missing NVARCHAR(MAX) = CASE WHEN @BoqTotal IS NULL OR @BoqTotal <= 0 THEN N', BOQ total' ELSE N'' END;

    SELECT @Missing += N', ' + t.Name + N' attachment'
    FROM   dbo.AttachmentType t
    WHERE  t.Stage = 'DOCUMENT' AND t.IsActive = 1
      AND  1 = CASE @Category WHEN 'CAPEX' THEN CAST(t.IsMandatoryCapex AS INT)
                              WHEN 'OPEX'  THEN CAST(t.IsMandatoryOpex  AS INT)
                              WHEN 'LVE'   THEN CAST(t.IsMandatoryLve   AS INT) END
      AND  NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a
                       WHERE a.RequestId = @Id AND a.AttachmentTypeId = t.Id AND a.IsActive = 1)
    ORDER BY t.Name;

    IF @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(2048) = LEFT(N'Please complete before sending to management: ' + STUFF(@Missing, 1, 2, N'') + N'.', 2048);
        THROW 50072, @Msg, 1;
    END

    /* -- Snapshot langkah MGMT: ronde baru dari tabel saat ini (BR-37, BR-53) -- */
    DECLARE @Round INT = ISNULL((SELECT MAX(Round) FROM dbo.ApprovalStep WHERE RequestId = @Id AND [Point] = 'MGMT'), 0) + 1;

    UPDATE dbo.ApprovalStep SET Status = 'VOID'
    WHERE  RequestId = @Id AND [Point] = 'MGMT' AND Status = 'PENDING';

    INSERT INTO dbo.ApprovalStep
        (RequestId, [Point], Round, StepOrder, WorkflowStepId, RoleCode, Scope, DepartmentGroupCode, ReviseTo, AllowReject)
    SELECT  @Id, 'MGMT', @Round, w.StepOrder, w.Id, w.RoleCode, w.Scope, w.DepartmentGroupCode, w.ReviseTo, w.AllowReject
    FROM    dbo.WorkflowStep w
    WHERE   w.CoCode = @CoCode
      AND   w.[Point] = 'MGMT'
      AND   w.IsActive = 1
      AND   (w.Category IS NULL OR w.Category = @Category)
      AND   (
                w.DepartmentGroupCode IS NULL
                OR EXISTS (SELECT 1
                           FROM   dbo.DepartmentGroup g
                                  JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                           WHERE  g.CoCode = w.CoCode AND g.GroupCode = w.DepartmentGroupCode AND g.IsActive = 1
                             AND  m.DepartmentID = @DeptId)
            );

    DECLARE @StepCount INT = @@ROWCOUNT;
    DECLARE @NewStatus VARCHAR(20) = 'PLANNING';

    IF @StepCount > 0
    BEGIN
        SET @NewStatus = 'MGMT_APPROVAL';
        UPDATE dbo.ApprovalStep SET StartedAt = @Now
        WHERE  RequestId = @Id AND [Point] = 'MGMT' AND Round = @Round
          AND  StepOrder = (SELECT MIN(StepOrder) FROM dbo.ApprovalStep
                            WHERE RequestId = @Id AND [Point] = 'MGMT' AND Round = @Round);
    END

    UPDATE dbo.ProjectRequest
    SET    Status = @NewStatus, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'SEND_TO_MGMT', @Status, @NewStatus, @Remarks, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel hanya hidup dalam satu eksekusi: jalankan blok bersama DECLARE-nya.
   Kasus yang diharapkan error dibungkus TRY/CATCH (baris TestCase / ErrNo / ErrMsg).
   Prasyarat: Request.sql dan Task.sql sudah dijalankan ulang; ada request DOC_PREPARATION
   (mis. Id 3 setelah Feasible di T3-1, CAPEX) dan user civil.

   DECLARE @Id INT = 3, @Civil NVARCHAR(100) = N'users1', @Bukan NVARCHAR(100) = N'marisi';

   -- 0) Kolom baru + tugas Civil DOC_PREPARATION
   SELECT Id, RequestNo, Category, Status, BoqTotal FROM dbo.ProjectRequest WHERE Id = @Id;
   SELECT * FROM dbo.fn_User_Tasks(@Civil) WHERE RequestId = @Id;                          -- TaskType DOC_PREPARATION
   EXEC dbo.usp_Lookup_AttachmentTypesByStage @Stage = 'DOCUMENT';                         -- BOQ, Drawing, ...

   -- 1) Bukan civil -> 50075; BOQ total 0 -> 50072; kirim tanpa BOQ/Drawing -> 50072 (menyebut yang kurang)
   BEGIN TRY EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Bukan, @BoqTotal = 1000;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 0;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SendToManagement @Id = @Id, @Username = @Civil;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (BOQ total, BOQ, Drawing)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Isi BOQ total dua kali -> riwayat BOQ_TOTAL (kedua: lama -> baru); nilai sama -> tidak ada riwayat baru
   EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 4500000;
   EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 4750000;
   EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 4750000;
   SELECT TOP (3) Action, Remarks, ActionAt FROM dbo.ApprovalHistory WHERE RequestId = @Id ORDER BY Id DESC;

   -- 3) Upload BOQ (dan Drawing untuk CAPEX) lewat aplikasi sebagai civil (Tahap C), lalu:
   --    kirim -> MGMT_APPROVAL; langkah MGMT ronde baru: ABL OPEX = GM, ABL CAPEX = GM + Director; NKM = Director
   --EXEC dbo.usp_Request_SendToManagement @Id = @Id, @Username = @Civil, @Remarks = N'BOQ and drawing attached';
   --EXEC dbo.usp_Request_GetApprovalSteps @RequestId = @Id, @Username = @Civil;          -- MGMT step 1 IsCurrent
   --SELECT * FROM dbo.fn_User_Tasks(N'<user gm>') WHERE RequestId = @Id;                 -- APPROVAL (diproses di T3-3)

   -- 4) Setelah dikirim: ubah BOQ total / kirim ulang -> 50074
   --BEGIN TRY EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 1;
   --END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4 expect 50074' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   ===================================================================== */
GO
/* ---------- end RequestDocPrep.sql ---------- */
/* ---------- begin RequestExecution.sql ---------- */
PRINT N'[skema] RequestExecution.sql';
GO
/* =====================================================================
   RequestExecution.sql  -  In-house / Outsource, TOR, kontrak Purchasing (T4-1; PRD 3.3 langkah 1-2,
                            BR-11, BR-12, BR-15, ST-08, ST-09, ST-10, RL-06)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Vendor.sql dan RequestDocPrep.sql
             (dan jalankan ulang Request.sql: kolom ExecutionType/PlanCost/PreparationStartAt, aturan lampiran,
             lingkup purchasing; serta Task.sql: tugas PROCUREMENT untuk purchasing).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Alur    :
     PLANNING (civil)
       - In-house  -> SCHEDULING. Plan cost = BOQ total (BR-12). Awal periode Preparation = selesainya
                      management approval (BR-15, in-house).
       - Outsource -> PROCUREMENT (ST-09). Wajib lampiran TOR (jenis tahap PROCUREMENT) (BR-11).
     PROCUREMENT (purchasing)
       - Simpan kontrak: vendor aktif, nomor, tanggal, nilai > 0 (boleh disimpan berkali-kali).
       - Selesaikan procurement -> SCHEDULING. Wajib data kontrak + lampiran kontrak (jenis tahap CONTRACT).
         Plan cost = nilai kontrak (BR-12). Awal periode Preparation = saat ini (kontrak diinput; BR-15).
       - Kembalikan TOR ke Civil (Keputusan 14-11-2026) -> PLANNING, alasan wajib; cara eksekusi dikosongkan
         sehingga Civil bisa memperbaiki TOR atau memilih In-house.
     Semua aksi tercatat di riwayat: INHOUSE, SEND_TOR, RETURN_TOR, CONTRACT.
   Error   : 50072 = Input wajib kosong / tidak valid / data belum lengkap
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai (civil / purchasing)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.ProjectContract  (satu kontrak per request outsource; BR-11)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectContract', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectContract
    (
        Id             INT IDENTITY(1,1) NOT NULL,
        RequestId      INT            NOT NULL,
        VendorId       INT            NOT NULL,
        ContractNo     NVARCHAR(50)   NOT NULL,
        ContractDate   DATE           NOT NULL,
        ContractValue  DECIMAL(18, 2) NOT NULL,
        Remarks        NVARCHAR(1000) NULL,
        CreatedAt      DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectContract_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy      NVARCHAR(100)  NOT NULL,
        UpdatedAt      DATETIME2(3)   NULL,
        UpdatedBy      NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectContract PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectContract_Request UNIQUE (RequestId),
        CONSTRAINT FK_ProjectContract_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_ProjectContract_Vendor  FOREIGN KEY (VendorId)  REFERENCES dbo.Vendor (Id),
        CONSTRAINT CK_ProjectContract_Value   CHECK (ContractValue > 0)
    );
END
GO

/* ---------------------------------------------------------------------
   2. usp_Request_ChooseExecution  (civil, PLANNING; @ExecutionType = INHOUSE | OUTSOURCE)
      Hasil: SELECT Status (SCHEDULING / PROCUREMENT).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_ChooseExecution
    @Id             INT,
    @Username       NVARCHAR(100),
    @ExecutionType  VARCHAR(10),
    @Remarks        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @ExecutionType = UPPER(LTRIM(RTRIM(@ExecutionType)));
    SET @Remarks       = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF ISNULL(@ExecutionType, '') NOT IN ('INHOUSE', 'OUTSOURCE')
        THROW 50072, N'Please choose in-house or outsource.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can choose the execution method.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @BoqTotal DECIMAL(18, 2);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @BoqTotal = r.BoqTotal
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'PLANNING'
        THROW 50074, N'The execution method can only be chosen during planning.', 1;

    DECLARE @NewStatus VARCHAR(20);

    IF @ExecutionType = 'INHOUSE'
    BEGIN
        IF @BoqTotal IS NULL OR @BoqTotal <= 0
            THROW 50072, N'BOQ total is required for in-house execution.', 1;

        -- Awal Preparation in-house = selesainya management approval (masuk PLANNING terakhir; BR-15)
        DECLARE @MgmtDone DATETIME2(3) =
        (
            SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h
            WHERE  h.RequestId = @Id AND h.ToStatus = 'PLANNING' AND h.FromStatus = 'MGMT_APPROVAL'
        );

        SET @NewStatus = 'SCHEDULING';

        UPDATE dbo.ProjectRequest
        SET    Status = @NewStatus, ExecutionType = 'INHOUSE', PlanCost = @BoqTotal,
               PreparationStartAt = ISNULL(@MgmtDone, @Now), UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  Id = @Id;
    END
    ELSE
    BEGIN
        -- BR-11: outsource wajib TOR (minimal satu lampiran jenis tahap PROCUREMENT)
        IF NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a JOIN dbo.AttachmentType t ON t.Id = a.AttachmentTypeId
                       WHERE a.RequestId = @Id AND a.IsActive = 1 AND t.Stage = 'PROCUREMENT')
            THROW 50072, N'Please upload the TOR before sending to Purchasing.', 1;

        SET @NewStatus = 'PROCUREMENT';

        UPDATE dbo.ProjectRequest
        SET    Status = @NewStatus, ExecutionType = 'OUTSOURCE', PlanCost = NULL, PreparationStartAt = NULL,
               UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  Id = @Id;
    END

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, CASE @ExecutionType WHEN 'INHOUSE' THEN 'INHOUSE' ELSE 'SEND_TOR' END, @Status, @NewStatus, @Remarks, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* ---------------------------------------------------------------------
   3. usp_Request_SaveContract  (purchasing, PROCUREMENT; simpan / ubah data kontrak)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveContract
    @Id             INT,
    @Username       NVARCHAR(100),
    @VendorId       INT,
    @ContractNo     NVARCHAR(50),
    @ContractDate   DATE,
    @ContractValue  DECIMAL(18, 2),
    @Remarks        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @ContractNo = NULLIF(LTRIM(RTRIM(@ContractNo)), N'');
    SET @Remarks    = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'purchasing')
        THROW 50075, N'Only Purchasing can enter the contract.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'PROCUREMENT'
        THROW 50074, N'The contract can only be entered during procurement.', 1;

    -- Validasi isi (setelah cek status agar pesan status lebih dulu)
    DECLARE @Missing NVARCHAR(500) =
          CASE WHEN @VendorId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Vendor v WHERE v.Id = @VendorId AND v.IsActive = 1)
               THEN N', Vendor (active)' ELSE N'' END
        + CASE WHEN @ContractNo IS NULL THEN N', Contract number' ELSE N'' END
        + CASE WHEN @ContractDate IS NULL THEN N', Contract date' ELSE N'' END
        + CASE WHEN @ContractValue IS NULL OR @ContractValue <= 0 THEN N', Contract value (greater than 0)' ELSE N'' END;

    IF @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(2048) = N'Please complete: ' + STUFF(@Missing, 1, 2, N'') + N'.';
        THROW 50072, @Msg, 1;
    END
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    IF EXISTS (SELECT 1 FROM dbo.ProjectContract WHERE RequestId = @Id)
        UPDATE dbo.ProjectContract
        SET    VendorId = @VendorId, ContractNo = @ContractNo, ContractDate = @ContractDate,
               ContractValue = @ContractValue, Remarks = @Remarks, UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  RequestId = @Id;
    ELSE
        INSERT INTO dbo.ProjectContract (RequestId, VendorId, ContractNo, ContractDate, ContractValue, Remarks, CreatedAt, CreatedBy)
        VALUES (@Id, @VendorId, @ContractNo, @ContractDate, @ContractValue, @Remarks, @Now, @Username);

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Request_CompleteProcurement  (purchasing, PROCUREMENT -> SCHEDULING; BR-11, BR-12, BR-15)
      Hasil: SELECT Status.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_CompleteProcurement
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'purchasing')
        THROW 50075, N'Only Purchasing can complete procurement.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'PROCUREMENT'
        THROW 50074, N'This request is not in procurement.', 1;

    DECLARE @Value DECIMAL(18, 2), @ContractNo NVARCHAR(50), @VendorName NVARCHAR(150);

    SELECT  @Value = c.ContractValue, @ContractNo = c.ContractNo, @VendorName = v.Name
    FROM    dbo.ProjectContract c JOIN dbo.Vendor v ON v.Id = c.VendorId
    WHERE   c.RequestId = @Id;

    DECLARE @Missing NVARCHAR(500) =
          CASE WHEN @Value IS NULL THEN N', Contract data' ELSE N'' END
        + CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a JOIN dbo.AttachmentType t ON t.Id = a.AttachmentTypeId
                                WHERE a.RequestId = @Id AND a.IsActive = 1 AND t.Stage = 'CONTRACT')
               THEN N', Contract attachment' ELSE N'' END;

    IF @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(2048) = N'Please complete before finishing procurement: ' + STUFF(@Missing, 1, 2, N'') + N'.';
        THROW 50072, @Msg, 1;
    END

    UPDATE dbo.ProjectRequest
    SET    Status = 'SCHEDULING', PlanCost = @Value, PreparationStartAt = @Now, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'CONTRACT', @Status, 'SCHEDULING',
            LEFT(N'Contract ' + @ContractNo + N' · ' + @VendorName + N' · IDR ' + FORMAT(@Value, N'#,0.##', 'en-US'), 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT CAST('SCHEDULING' AS VARCHAR(20)) AS Status;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Request_ReturnTor  (purchasing, PROCUREMENT -> PLANNING; alasan wajib; Keputusan 14-11-2026)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_ReturnTor
    @Id        INT,
    @Username  NVARCHAR(100),
    @Reason    NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    IF @Reason IS NULL
        THROW 50072, N'Reason is required.', 1;
    IF LEN(@Reason) > 1000
        THROW 50072, N'Reason must be at most 1000 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'purchasing')
        THROW 50075, N'Only Purchasing can return the TOR.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'PROCUREMENT'
        THROW 50074, N'This request is not in procurement.', 1;

    UPDATE dbo.ProjectRequest
    SET    Status = 'PLANNING', ExecutionType = NULL, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'RETURN_TOR', @Status, 'PLANNING', @Reason, @Username, @Now);

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Request_GetContract  (Details; 0 baris = belum ada kontrak)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetContract
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  c.Id, c.RequestId, c.VendorId, v.Code AS VendorCode, v.Name AS VendorName,
            c.ContractNo, c.ContractDate, c.ContractValue, c.Remarks,
            c.CreatedAt, c.CreatedBy, c.UpdatedAt, c.UpdatedBy
    FROM    dbo.ProjectContract c
            JOIN dbo.Vendor v         ON v.Id = c.VendorId
            JOIN dbo.ProjectRequest r ON r.Id = c.RequestId
    WHERE   c.RequestId = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)));
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: Request.sql, Task.sql, Vendor.sql dijalankan; ada request PLANNING (mis. Id 3 setelah
   management approval) dan request PLANNING lain untuk jalur outsource; user civil dan purchasing.

   DECLARE @InHouse INT = 3, @Out INT = <id request PLANNING lain>,
           @Civil NVARCHAR(100) = N'<user civil>', @Purch NVARCHAR(100) = N'<user purchasing>';

   -- 1) Validasi: bukan civil -> 50075; outsource tanpa TOR -> 50072
   BEGIN TRY EXEC dbo.usp_Request_ChooseExecution @Id = @InHouse, @Username = @Purch, @ExecutionType = 'INHOUSE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_ChooseExecution @Id = @Out, @Username = @Civil, @ExecutionType = 'OUTSOURCE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (TOR)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) In-house -> SCHEDULING; PlanCost = BoqTotal; PreparationStartAt = waktu management approval terakhir
   EXEC dbo.usp_Request_ChooseExecution @Id = @InHouse, @Username = @Civil, @ExecutionType = 'INHOUSE';
   SELECT Id, Status, ExecutionType, BoqTotal, PlanCost, PreparationStartAt FROM dbo.ProjectRequest WHERE Id = @InHouse;

   -- 3) Purchasing hanya melihat outsource (RL-06): @InHouse tidak muncul / GetById 0 baris
   EXEC dbo.usp_Request_GetById @Id = @InHouse, @Username = @Purch;
   SELECT * FROM dbo.fn_User_OutsourceOnly(@Purch);                            -- 1 baris bila hanya purchasing

   -- 4) Upload TOR (lewat aplikasi sebagai civil, Tahap C) lalu:
   --EXEC dbo.usp_Request_ChooseExecution @Id = @Out, @Username = @Civil, @ExecutionType = 'OUTSOURCE', @Remarks = N'TOR attached';
   --SELECT * FROM dbo.fn_User_Tasks(@Purch) WHERE RequestId = @Out;           -- PROCUREMENT

   -- 5) Purchasing: kembalikan TOR (alasan wajib) -> PLANNING, ExecutionType NULL
   --BEGIN TRY EXEC dbo.usp_Request_ReturnTor @Id = @Out, @Username = @Purch, @Reason = N' ';
   --END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '5 expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   --EXEC dbo.usp_Request_ReturnTor @Id = @Out, @Username = @Purch, @Reason = N'Scope of work is unclear';

   -- 6) Setelah dikirim ulang: simpan kontrak (vendor dari Vendor.sql), selesaikan tanpa lampiran kontrak -> 50072,
   --    upload lampiran kontrak (aplikasi), selesaikan -> SCHEDULING, PlanCost = nilai kontrak
   --DECLARE @Vendor INT = (SELECT TOP (1) Id FROM dbo.Vendor WHERE IsActive = 1);
   --EXEC dbo.usp_Request_SaveContract @Id = @Out, @Username = @Purch, @VendorId = @Vendor,
   --     @ContractNo = N'SPK/001/XI/2026', @ContractDate = '2026-11-14', @ContractValue = 4600000;
   --EXEC dbo.usp_Request_GetContract @RequestId = @Out, @Username = @Civil;
   --BEGIN TRY EXEC dbo.usp_Request_CompleteProcurement @Id = @Out, @Username = @Purch;
   --END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '6 expect 50072 (attachment)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   ===================================================================== */
GO
/* ---------- end RequestExecution.sql ---------- */
/* ---------- begin RequestSchedule.sql ---------- */
PRINT N'[skema] RequestSchedule.sql';
GO
/* =====================================================================
   RequestSchedule.sql  -  Schedule, action plan berbobot, estimasi biaya bulanan, site handover
                           (T4-2; PRD 3.3 langkah 3-4, BR-13, BR-14, BR-15, BR-16, BR-17, ST-10, ST-11)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestExecution.sql
             (dan jalankan ulang Task.sql: tugas SCHEDULING untuk civil).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Aturan (Keputusan 14-11-2026, lihat docs/PRD-log.md):
     - Tanggal mulai project diisi Civil (BR-15). Tanggal selesai project = tanggal selesai plan terakhir
       dari action plan (tidak diinput terpisah).
     - Action plan: nama, bobot (%), tanggal mulai/selesai plan; mulai plan >= tanggal mulai project.
     - Estimasi biaya: total per bulan (BR-13), hanya bulan mulai project s.d. bulan selesai project.
     - Saat SCHEDULING Civil boleh menyimpan draft belum lengkap (total bobot <= 100, total estimasi <= plan cost).
       Site handover (-> IN_PROGRESS) wajib: total bobot = 100 dan total estimasi = plan cost.
     - Saat IN_PROGRESS Civil tetap boleh mengubah schedule/action plan/estimasi, dengan alasan wajib
       (tercatat di riwayat: SCHEDULE_CHANGE / ESTIMATE_CHANGE), dan setiap simpan harus tetap valid penuh.
     - Tanggal site handover: >= tanggal mulai project dan <= hari ini (ST-11).
     - Lihat: semua role yang boleh melihat request, kecuali purchasing-only (matriks PRD 5.2).
   Addendum (T4-4, Keputusan 17-11-2026; BR-81, BR-83, BR-84, BR-85):
     - Selama addendum terbuka (PENDING_APPROVAL / FINAL_CONTRACT / ADJUSTMENT) perubahan schedule dan estimasi biasa dikunci;
       penyesuaian addendum lewat usp_Addendum_SaveAdjustment (RequestAddendum.sql) yang memanggil kedua SP
       ini dengan @AddendumId.
     - Action plan "sudah punya progress" = progress mingguan tersimpan > 0% atau mulai aktual terisi:
       tidak boleh dihapus; nama dan tanggal mulai plan terkunci (bobot dan tanggal selesai boleh diubah).
       Action plan yang selalu 0% boleh dihapus (baris progress 0% minggu lalu ikut dihapus).
     - Saat IN_PROGRESS, setelah schedule disimpan, % aktual / % plan / status jadwal di ringkasan project
       dihitung ulang (usp_Request_RefreshScheduleSummary, RequestProgress.sql); minggu lama tidak diubah.
     - Penyesuaian addendum: estimasi bulan sebelum bulan berjalan tidak boleh berubah.
   Error   : 50072 = Input wajib kosong / tidak valid / data belum lengkap
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai (civil)
   Catatan : Progress mingguan dan tanggal aktual per action plan dikerjakan di T5 (kolom sudah disiapkan).
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Migrasi kolom dbo.ProjectRequest
   --------------------------------------------------------------------- */
IF COL_LENGTH(N'dbo.ProjectRequest', N'ProjectStartDate') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD ProjectStartDate DATE NULL;   -- tanggal mulai project dari schedule Civil (BR-15)
END
GO

IF COL_LENGTH(N'dbo.ProjectRequest', N'SiteHandoverDate') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD SiteHandoverDate DATE NULL;   -- site handover / start execution (ST-11)
END
GO

/* ---------------------------------------------------------------------
   2. TABLE dbo.ProjectActionPlan  (BR-16)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectActionPlan', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectActionPlan
    (
        Id               INT IDENTITY(1,1) NOT NULL,
        RequestId        INT            NOT NULL,
        SortOrder        INT            NOT NULL,
        Name             NVARCHAR(200)  NOT NULL,
        WeightPercent    DECIMAL(5, 2)  NOT NULL,
        PlanStartDate    DATE           NOT NULL,
        PlanEndDate      DATE           NOT NULL,
        ProgressPercent  DECIMAL(5, 2)  NOT NULL CONSTRAINT DF_ProjectActionPlan_Progress DEFAULT (0),  -- T5
        ActualStartDate  DATE           NULL,                                                           -- T5
        ActualEndDate    DATE           NULL,                                                           -- T5
        CreatedAt        DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectActionPlan_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy        NVARCHAR(100)  NOT NULL,
        UpdatedAt        DATETIME2(3)   NULL,
        UpdatedBy        NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectActionPlan PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ProjectActionPlan_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT CK_ProjectActionPlan_Weight   CHECK (WeightPercent > 0 AND WeightPercent <= 100),
        CONSTRAINT CK_ProjectActionPlan_Dates    CHECK (PlanEndDate >= PlanStartDate),
        CONSTRAINT CK_ProjectActionPlan_Progress CHECK (ProgressPercent >= 0 AND ProgressPercent <= 100)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ProjectActionPlan_Request' AND object_id = OBJECT_ID(N'dbo.ProjectActionPlan'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectActionPlan_Request ON dbo.ProjectActionPlan (RequestId, SortOrder);
END
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.ProjectCostEstimate  (estimasi total per bulan; BR-13)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectCostEstimate', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectCostEstimate
    (
        Id           INT IDENTITY(1,1) NOT NULL,
        RequestId    INT            NOT NULL,
        PeriodMonth  DATE           NOT NULL,       -- tanggal 1 bulan tersebut
        Amount       DECIMAL(18, 2) NOT NULL,
        CreatedAt    DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectCostEstimate_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy    NVARCHAR(100)  NOT NULL,
        CONSTRAINT PK_ProjectCostEstimate PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectCostEstimate_Month UNIQUE (RequestId, PeriodMonth),
        CONSTRAINT FK_ProjectCostEstimate_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT CK_ProjectCostEstimate_Amount CHECK (Amount > 0),
        CONSTRAINT CK_ProjectCostEstimate_Month  CHECK (DAY(PeriodMonth) = 1)
    );
END
GO

/* ---------------------------------------------------------------------
   4. usp_Request_GetSchedule  (Details)
      Result 1: ringkasan (0 baris = tidak ada / di luar lingkup / purchasing-only)
      Result 2: action plan (urut SortOrder)
      Result 3: estimasi biaya per bulan
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetSchedule
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))   -- purchasing: tanpa akses schedule (5.2)
             THEN 1 ELSE 0 END;

    SELECT  r.Id AS RequestId, r.Status, r.ExecutionType, r.PlanCost, r.PreparationStartAt,
            r.ProjectStartDate,
            (SELECT MAX(a.PlanEndDate) FROM dbo.ProjectActionPlan a WHERE a.RequestId = r.Id) AS ProjectEndDate,
            r.SiteHandoverDate,
            ISNULL((SELECT SUM(a.WeightPercent) FROM dbo.ProjectActionPlan a WHERE a.RequestId = r.Id), 0) AS TotalWeight,
            ISNULL((SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = r.Id), 0) AS TotalEstimate
    FROM    dbo.ProjectRequest r
    WHERE   r.Id = @RequestId AND @Visible = 1;

    SELECT  a.Id, a.RequestId, a.SortOrder, a.Name, a.WeightPercent, a.PlanStartDate, a.PlanEndDate,
            a.ProgressPercent, a.ActualStartDate, a.ActualEndDate
    FROM    dbo.ProjectActionPlan a
    WHERE   a.RequestId = @RequestId AND @Visible = 1
    ORDER BY a.SortOrder, a.Id;

    SELECT  e.Id, e.RequestId, e.PeriodMonth, e.Amount
    FROM    dbo.ProjectCostEstimate e
    WHERE   e.RequestId = @RequestId AND @Visible = 1
    ORDER BY e.PeriodMonth;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Request_SaveSchedule  (civil; SCHEDULING atau IN_PROGRESS)
      @ActionPlanJson: [{"id":0,"name":"Excavation","weight":25,"start":"2026-12-01","end":"2026-12-10"}, ...]
        id 0 / null = baris baru; baris lama yang tidak ada di JSON dihapus. Urutan JSON = SortOrder.
      @Reason wajib saat IN_PROGRESS (Keputusan 14-11-2026).
      @AddendumId: hanya dari usp_Addendum_SaveAdjustment (tanpa alasan dan riwayat sendiri).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveSchedule
    @Id                INT,
    @Username          NVARCHAR(100),
    @ProjectStartDate  DATE,
    @ActionPlanJson    NVARCHAR(MAX),
    @Reason            NVARCHAR(MAX) = NULL,
    @AddendumId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can change the schedule.', 1;
    IF @ProjectStartDate IS NULL
        THROW 50072, N'Project start date is required.', 1;
    IF LEN(@Reason) > 1000
        THROW 50072, N'Reason must be at most 1000 characters.', 1;
    IF ISJSON(ISNULL(@ActionPlanJson, N'[]')) = 0
        THROW 50072, N'Action plan data is invalid.', 1;

    DECLARE @Items TABLE
    (
        Seq        INT            NOT NULL PRIMARY KEY,
        ItemId     INT            NULL,
        Name       NVARCHAR(400)  NULL,
        Weight     DECIMAL(9, 2)  NULL,
        StartDate  DATE           NULL,
        EndDate    DATE           NULL
    );

    INSERT INTO @Items (Seq, ItemId, Name, Weight, StartDate, EndDate)
    SELECT  CAST(j.[key] AS INT) + 1, NULLIF(x.id, 0), NULLIF(LTRIM(RTRIM(x.name)), N''), x.weight, x.start, x.[end]
    FROM    OPENJSON(ISNULL(@ActionPlanJson, N'[]')) j
            CROSS APPLY OPENJSON(j.[value])
            WITH (id INT '$.id', name NVARCHAR(400) '$.name', weight DECIMAL(9, 2) '$.weight',
                  start DATE '$.start', [end] DATE '$.end') x;

    -- Validasi per baris (pesan pertama yang ditemukan, dengan nomor baris)
    DECLARE @Msg NVARCHAR(2048);

    IF (SELECT COUNT(*) FROM @Items) > 100
        THROW 50072, N'At most 100 action plans are allowed.', 1;

    SELECT TOP (1) @Msg = N'Action plan row ' + CAST(i.Seq AS NVARCHAR(10)) + N': ' +
           CASE WHEN i.Name IS NULL                         THEN N'name is required.'
                WHEN LEN(i.Name) > 200                      THEN N'name must be at most 200 characters.'
                WHEN i.Weight IS NULL OR i.Weight <= 0      THEN N'weight must be greater than 0.'
                WHEN i.Weight > 100                         THEN N'weight must be at most 100%.'
                WHEN i.StartDate IS NULL OR i.EndDate IS NULL THEN N'plan start and end dates are required.'
                WHEN i.EndDate < i.StartDate                THEN N'plan end date must be on or after the start date.'
                ELSE N'plan start date must be on or after the project start date.' END
    FROM   @Items i
    WHERE  i.Name IS NULL OR LEN(i.Name) > 200
       OR  i.Weight IS NULL OR i.Weight <= 0 OR i.Weight > 100
       OR  i.StartDate IS NULL OR i.EndDate IS NULL OR i.EndDate < i.StartDate
       OR  i.StartDate < @ProjectStartDate
    ORDER BY i.Seq;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    IF EXISTS (SELECT ItemId FROM @Items WHERE ItemId IS NOT NULL GROUP BY ItemId HAVING COUNT(*) > 1)
        THROW 50072, N'Action plan data is invalid (duplicate rows).', 1;

    DECLARE @TotalWeight DECIMAL(9, 2) = ISNULL((SELECT SUM(Weight) FROM @Items), 0);
    IF @TotalWeight > 100
    BEGIN
        SET @Msg = N'Total action plan weight must not exceed 100% (currently ' + FORMAT(@TotalWeight, N'0.##', 'en-US') + N'%).';
        THROW 50072, @Msg, 1;
    END

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @HandoverDate DATE;

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @HandoverDate = r.SiteHandoverDate
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status NOT IN ('SCHEDULING', 'IN_PROGRESS')
        THROW 50074, N'The schedule can only be changed during scheduling or while in progress.', 1;

    -- T4-4: addendum terbuka mengunci perubahan biasa (BR-81). Statement di dalam IF dikompilasi saat dijalankan.
    IF OBJECT_ID(N'dbo.ProjectAddendum', N'U') IS NOT NULL
    BEGIN
        DECLARE @OpenAddendumId INT, @OpenAddendumStatus VARCHAR(20);
        SELECT TOP (1) @OpenAddendumId = d.Id, @OpenAddendumStatus = d.Status
        FROM   dbo.ProjectAddendum d
        WHERE  d.RequestId = @Id AND d.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT');

        IF @AddendumId IS NULL AND @OpenAddendumId IS NOT NULL
            THROW 50074, N'An addendum is in progress. Schedule changes are locked until the addendum is completed.', 1;
        IF @AddendumId IS NOT NULL AND (@OpenAddendumId IS NULL OR @OpenAddendumId <> @AddendumId OR @OpenAddendumStatus <> 'ADJUSTMENT')
            THROW 50074, N'This addendum is not awaiting adjustment.', 1;
    END
    ELSE IF @AddendumId IS NOT NULL
        THROW 50074, N'This addendum is not awaiting adjustment.', 1;

    -- Id lama harus milik request ini
    IF EXISTS (SELECT 1 FROM @Items i WHERE i.ItemId IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a WHERE a.Id = i.ItemId AND a.RequestId = @Id))
        THROW 50072, N'Action plan data is outdated. Please reload the page.', 1;

    DECLARE @NewEnd DATE = (SELECT MAX(EndDate) FROM @Items);

    IF @Status = 'IN_PROGRESS'
    BEGIN
        -- Perubahan saat berjalan: alasan wajib dan data tetap lengkap (Keputusan 14-11-2026)
        IF @Reason IS NULL AND @AddendumId IS NULL
            THROW 50072, N'Reason is required to change the schedule while the project is in progress.', 1;
        IF @TotalWeight <> 100
        BEGIN
            SET @Msg = N'Total action plan weight must be 100% (currently ' + FORMAT(@TotalWeight, N'0.##', 'en-US') + N'%).';
            THROW 50072, @Msg, 1;
        END
        IF @HandoverDate IS NOT NULL AND @ProjectStartDate > @HandoverDate
            THROW 50072, N'Project start date cannot be after the site handover date.', 1;
        -- Penyesuaian addendum menyimpan estimasi sesudah schedule (dicek di usp_Request_SaveCostEstimate)
        IF @AddendumId IS NULL
           AND EXISTS (SELECT 1 FROM dbo.ProjectCostEstimate e
                       WHERE e.RequestId = @Id
                         AND (e.PeriodMonth < DATEFROMPARTS(YEAR(@ProjectStartDate), MONTH(@ProjectStartDate), 1)
                              OR e.PeriodMonth > DATEFROMPARTS(YEAR(@NewEnd), MONTH(@NewEnd), 1)))
            THROW 50072, N'Some cost estimate months fall outside the new schedule. Adjust the cost estimate first.', 1;
    END

    -- BR-83 (Keputusan 17-11-2026): action plan yang sudah punya progress (> 0% tersimpan atau mulai aktual terisi)
    -- tidak boleh dihapus; nama dan tanggal mulai plan terkunci. Dicek hanya bila tabel progress sudah ada
    -- (urutan script); statement di dalam IF dikompilasi saat dijalankan.
    IF OBJECT_ID(N'dbo.ProjectProgressItem', N'U') IS NOT NULL
    BEGIN
        SELECT TOP (1) @Msg = N'Action plan "' + a.Name + N'" already has progress: '
               + CASE WHEN i.Seq IS NULL       THEN N'it cannot be removed.'
                      WHEN i.Name <> a.Name    THEN N'its name cannot be changed.'
                      ELSE N'its plan start date cannot be changed.' END
        FROM   dbo.ProjectActionPlan a
               LEFT JOIN @Items i ON i.ItemId = a.Id
        WHERE  a.RequestId = @Id
          AND  (a.ActualStartDate IS NOT NULL
                OR EXISTS (SELECT 1 FROM dbo.ProjectProgressItem p WHERE p.ActionPlanId = a.Id AND p.ProgressPercent > 0))
          AND  (i.Seq IS NULL OR i.Name <> a.Name OR i.StartDate <> a.PlanStartDate)
        ORDER BY a.SortOrder;

        IF @Msg IS NOT NULL
            THROW 50072, @Msg, 1;

        -- Action plan 0% yang dihapus: baris progress 0% minggu lalu ikut dihapus (% minggu itu tidak berubah)
        DELETE p
        FROM   dbo.ProjectProgressItem p
               JOIN dbo.ProjectActionPlan a ON a.Id = p.ActionPlanId
        WHERE  a.RequestId = @Id
          AND  NOT EXISTS (SELECT 1 FROM @Items i WHERE i.ItemId = a.Id);
    END

    UPDATE dbo.ProjectRequest
    SET    ProjectStartDate = @ProjectStartDate, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    DELETE a
    FROM   dbo.ProjectActionPlan a
    WHERE  a.RequestId = @Id
      AND  NOT EXISTS (SELECT 1 FROM @Items i WHERE i.ItemId = a.Id);

    UPDATE a
    SET    a.SortOrder = i.Seq, a.Name = i.Name, a.WeightPercent = i.Weight,
           a.PlanStartDate = i.StartDate, a.PlanEndDate = i.EndDate, a.UpdatedAt = @Now, a.UpdatedBy = @Username
    FROM   dbo.ProjectActionPlan a
           JOIN @Items i ON i.ItemId = a.Id
    WHERE  a.RequestId = @Id;

    INSERT INTO dbo.ProjectActionPlan (RequestId, SortOrder, Name, WeightPercent, PlanStartDate, PlanEndDate, CreatedAt, CreatedBy)
    SELECT @Id, i.Seq, i.Name, i.Weight, i.StartDate, i.EndDate, @Now, @Username
    FROM   @Items i
    WHERE  i.ItemId IS NULL;

    -- BR-84: ringkasan progress dihitung ulang dengan bobot/schedule baru (RequestProgress.sql; EXEC diselesaikan
    -- saat dijalankan, jadi aman walau script itu belum dijalankan ulang)
    DECLARE @OldPercent DECIMAL(5, 2), @NewPercent DECIMAL(5, 2);
    IF @Status = 'IN_PROGRESS' AND OBJECT_ID(N'dbo.usp_Request_RefreshScheduleSummary', N'P') IS NOT NULL
        EXEC dbo.usp_Request_RefreshScheduleSummary @Id = @Id, @Username = @Username,
             @OldPercent = @OldPercent OUTPUT, @NewPercent = @NewPercent OUTPUT;

    IF @Status = 'IN_PROGRESS' AND @AddendumId IS NULL
        INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
        VALUES (@Id, 'SCHEDULE_CHANGE', @Status, @Status,
                LEFT(@Reason + CASE WHEN ISNULL(@OldPercent, -1) <> ISNULL(@NewPercent, -1)
                                    THEN N' · Progress ' + FORMAT(ISNULL(@OldPercent, 0), N'0.##', 'en-US') + N'% -> '
                                         + FORMAT(ISNULL(@NewPercent, 0), N'0.##', 'en-US') + N'%'
                                    ELSE N'' END, 1000),
                @Username, @Now);

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Request_SaveCostEstimate  (civil; SCHEDULING atau IN_PROGRESS; ganti seluruh estimasi)
      @EstimateJson: [{"month":"2026-12-01","amount":1500000}, ...]  (tanggal apa pun di bulan itu boleh)
      Bulan hanya dari bulan mulai s.d. bulan selesai project (Keputusan 14-11-2026); wajib schedule dulu.
      @AddendumId: hanya dari usp_Addendum_SaveAdjustment (tanpa alasan dan riwayat sendiri; bulan sebelum
      bulan berjalan tidak boleh berubah, BR-85).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveCostEstimate
    @Id            INT,
    @Username      NVARCHAR(100),
    @EstimateJson  NVARCHAR(MAX),
    @Reason        NVARCHAR(MAX) = NULL,
    @AddendumId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can change the cost estimate.', 1;
    IF LEN(@Reason) > 1000
        THROW 50072, N'Reason must be at most 1000 characters.', 1;
    IF ISJSON(ISNULL(@EstimateJson, N'[]')) = 0
        THROW 50072, N'Cost estimate data is invalid.', 1;

    DECLARE @Items TABLE
    (
        Seq     INT            NOT NULL PRIMARY KEY,
        Month   DATE           NULL,
        Amount  DECIMAL(18, 2) NULL
    );

    INSERT INTO @Items (Seq, Month, Amount)
    SELECT  CAST(j.[key] AS INT) + 1,
            CASE WHEN x.[month] IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(x.[month]), MONTH(x.[month]), 1) END,
            x.amount
    FROM    OPENJSON(ISNULL(@EstimateJson, N'[]')) j
            CROSS APPLY OPENJSON(j.[value]) WITH ([month] DATE '$.month', amount DECIMAL(18, 2) '$.amount') x;

    DECLARE @Msg NVARCHAR(2048);

    SELECT TOP (1) @Msg = N'Cost estimate row ' + CAST(i.Seq AS NVARCHAR(10)) + N': ' +
           CASE WHEN i.Month IS NULL THEN N'month is required.' ELSE N'amount must be greater than 0.' END
    FROM   @Items i
    WHERE  i.Month IS NULL OR i.Amount IS NULL OR i.Amount <= 0
    ORDER BY i.Seq;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    IF EXISTS (SELECT Month FROM @Items GROUP BY Month HAVING COUNT(*) > 1)
        THROW 50072, N'Each month can only appear once in the cost estimate.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @PlanCost DECIMAL(18, 2), @StartDate DATE;

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @PlanCost = r.PlanCost, @StartDate = r.ProjectStartDate
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status NOT IN ('SCHEDULING', 'IN_PROGRESS')
        THROW 50074, N'The cost estimate can only be changed during scheduling or while in progress.', 1;

    -- T4-4: addendum terbuka mengunci perubahan biasa (BR-81)
    IF OBJECT_ID(N'dbo.ProjectAddendum', N'U') IS NOT NULL
    BEGIN
        DECLARE @OpenAddendumId INT, @OpenAddendumStatus VARCHAR(20);
        SELECT TOP (1) @OpenAddendumId = d.Id, @OpenAddendumStatus = d.Status
        FROM   dbo.ProjectAddendum d
        WHERE  d.RequestId = @Id AND d.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT');

        IF @AddendumId IS NULL AND @OpenAddendumId IS NOT NULL
            THROW 50074, N'An addendum is in progress. Cost estimate changes are locked until the addendum is completed.', 1;
        IF @AddendumId IS NOT NULL AND (@OpenAddendumId IS NULL OR @OpenAddendumId <> @AddendumId OR @OpenAddendumStatus <> 'ADJUSTMENT')
            THROW 50074, N'This addendum is not awaiting adjustment.', 1;
    END
    ELSE IF @AddendumId IS NOT NULL
        THROW 50074, N'This addendum is not awaiting adjustment.', 1;

    DECLARE @EndDate DATE = (SELECT MAX(a.PlanEndDate) FROM dbo.ProjectActionPlan a WHERE a.RequestId = @Id);

    IF @StartDate IS NULL OR @EndDate IS NULL
        THROW 50072, N'Please save the schedule and action plans before the cost estimate.', 1;

    DECLARE @FirstMonth DATE = DATEFROMPARTS(YEAR(@StartDate), MONTH(@StartDate), 1),
            @LastMonth  DATE = DATEFROMPARTS(YEAR(@EndDate), MONTH(@EndDate), 1);

    IF EXISTS (SELECT 1 FROM @Items WHERE Month < @FirstMonth OR Month > @LastMonth)
    BEGIN
        SET @Msg = N'Cost estimate months must be between ' + FORMAT(@FirstMonth, N'MMM yyyy', 'en-US')
                 + N' and ' + FORMAT(@LastMonth, N'MMM yyyy', 'en-US') + N' (project schedule).';
        THROW 50072, @Msg, 1;
    END

    -- BR-85: penyesuaian addendum tidak boleh mengubah estimasi bulan sebelum bulan berjalan
    DECLARE @CurMonth DATE = DATEFROMPARTS(YEAR(@Now), MONTH(@Now), 1);
    IF @AddendumId IS NOT NULL
       AND (EXISTS (SELECT i.Month, i.Amount FROM @Items i WHERE i.Month < @CurMonth
                    EXCEPT
                    SELECT e.PeriodMonth, e.Amount FROM dbo.ProjectCostEstimate e WHERE e.RequestId = @Id AND e.PeriodMonth < @CurMonth)
            OR EXISTS (SELECT e.PeriodMonth, e.Amount FROM dbo.ProjectCostEstimate e WHERE e.RequestId = @Id AND e.PeriodMonth < @CurMonth
                       EXCEPT
                       SELECT i.Month, i.Amount FROM @Items i WHERE i.Month < @CurMonth))
    BEGIN
        SET @Msg = N'Cost estimates before ' + FORMAT(@CurMonth, N'MMM yyyy', 'en-US')
                 + N' cannot be changed in an addendum adjustment.';
        THROW 50072, @Msg, 1;
    END

    DECLARE @Total DECIMAL(18, 2) = ISNULL((SELECT SUM(Amount) FROM @Items), 0);

    IF @PlanCost IS NOT NULL AND @Total > @PlanCost
    BEGIN
        SET @Msg = N'Total cost estimate (IDR ' + FORMAT(@Total, N'#,0.##', 'en-US') + N') must not exceed the plan cost (IDR '
                 + FORMAT(@PlanCost, N'#,0.##', 'en-US') + N').';
        THROW 50072, @Msg, 1;
    END

    IF @Status = 'IN_PROGRESS'
    BEGIN
        IF @Reason IS NULL AND @AddendumId IS NULL
            THROW 50072, N'Reason is required to change the cost estimate while the project is in progress.', 1;
        IF @PlanCost IS NULL OR @Total <> @PlanCost
        BEGIN
            SET @Msg = N'Total cost estimate must equal the plan cost (IDR ' + FORMAT(ISNULL(@PlanCost, 0), N'#,0.##', 'en-US') + N').';
            THROW 50072, @Msg, 1;
        END
    END

    DELETE FROM dbo.ProjectCostEstimate WHERE RequestId = @Id;

    INSERT INTO dbo.ProjectCostEstimate (RequestId, PeriodMonth, Amount, CreatedAt, CreatedBy)
    SELECT @Id, i.Month, i.Amount, @Now, @Username
    FROM   @Items i;

    UPDATE dbo.ProjectRequest SET UpdatedAt = @Now, UpdatedBy = @Username WHERE Id = @Id;

    IF @Status = 'IN_PROGRESS' AND @AddendumId IS NULL
        INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
        VALUES (@Id, 'ESTIMATE_CHANGE', @Status, @Status, LEFT(@Reason, 1000), @Username, @Now);

    -- T5-2: estimasi berubah saat berjalan -> hitung ulang status biaya (BR-69, BR-71; RequestActualCost.sql).
    -- EXEC diselesaikan saat dijalankan, jadi aman walau script T5-2 belum dijalankan.
    IF @Status = 'IN_PROGRESS' AND OBJECT_ID(N'dbo.usp_Request_RefreshCostStatus', N'P') IS NOT NULL
        EXEC dbo.usp_Request_RefreshCostStatus @Id = @Id, @Username = @Username;

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   7. usp_Request_SiteHandover  (civil; SCHEDULING -> IN_PROGRESS; ST-11, BR-13, BR-14, BR-16)
      Hasil: SELECT Status.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SiteHandover
    @Id            INT,
    @Username      NVARCHAR(100),
    @HandoverDate  DATE,
    @Remarks       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can record the site handover.', 1;
    IF @HandoverDate IS NULL
        THROW 50072, N'Site handover date is required.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);
    DECLARE @Status VARCHAR(20), @PlanCost DECIMAL(18, 2), @StartDate DATE;

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @PlanCost = r.PlanCost, @StartDate = r.ProjectStartDate
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'SCHEDULING'
        THROW 50074, N'Site handover can only be recorded during scheduling.', 1;

    -- T4-4 (Keputusan 18-11-2026): site handover diblok selama addendum masih terbuka (konsisten dengan BR-81)
    IF OBJECT_ID(N'dbo.ProjectAddendum', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.ProjectAddendum d
                   WHERE d.RequestId = @Id AND d.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT'))
        THROW 50074, N'Complete or reject the open addendum before recording the site handover.', 1;

    DECLARE @EndDate DATE, @Weight DECIMAL(9, 2), @PlanCount INT;
    SELECT  @EndDate = MAX(a.PlanEndDate), @Weight = SUM(a.WeightPercent), @PlanCount = COUNT(*)
    FROM    dbo.ProjectActionPlan a
    WHERE   a.RequestId = @Id;

    DECLARE @Total DECIMAL(18, 2) = ISNULL((SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = @Id), 0);

    DECLARE @Missing NVARCHAR(1000) =
          CASE WHEN @StartDate IS NULL THEN N', Project start date' ELSE N'' END
        + CASE WHEN @PlanCount = 0 THEN N', Action plans'
               WHEN ISNULL(@Weight, 0) <> 100 THEN N', Action plan weights totalling 100% (currently ' + FORMAT(ISNULL(@Weight, 0), N'0.##', 'en-US') + N'%)'
               ELSE N'' END
        + CASE WHEN @PlanCost IS NULL OR @Total <> @PlanCost
               THEN N', Cost estimate totalling the plan cost (IDR ' + FORMAT(ISNULL(@PlanCost, 0), N'#,0.##', 'en-US')
                    + N'; currently IDR ' + FORMAT(@Total, N'#,0.##', 'en-US') + N')'
               ELSE N'' END;

    IF @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(2048) = N'Please complete before site handover: ' + STUFF(@Missing, 1, 2, N'') + N'.';
        THROW 50072, @Msg, 1;
    END

    -- Estimasi di luar rentang schedule (schedule diubah setelah estimasi disimpan)
    IF EXISTS (SELECT 1 FROM dbo.ProjectCostEstimate e
               WHERE e.RequestId = @Id
                 AND (e.PeriodMonth < DATEFROMPARTS(YEAR(@StartDate), MONTH(@StartDate), 1)
                      OR e.PeriodMonth > DATEFROMPARTS(YEAR(@EndDate), MONTH(@EndDate), 1)))
        THROW 50072, N'Some cost estimate months fall outside the project schedule. Please update the cost estimate.', 1;

    IF @HandoverDate < @StartDate
        THROW 50072, N'Site handover date must be on or after the project start date.', 1;
    IF @HandoverDate > @Today
        THROW 50072, N'Site handover date cannot be in the future.', 1;

    UPDATE dbo.ProjectRequest
    SET    Status = 'IN_PROGRESS', SiteHandoverDate = @HandoverDate, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'SITE_HANDOVER', @Status, 'IN_PROGRESS',
            LEFT(N'Handover ' + FORMAT(@HandoverDate, N'dd MMM yyyy', 'en-US') + ISNULL(N' · ' + @Remarks, N''), 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT CAST('IN_PROGRESS' AS VARCHAR(20)) AS Status;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: Task.sql dijalankan ulang; ada request SCHEDULING (mis. hasil test in-house T4-1, PlanCost terisi).
   Tanggal contoh: mulai project 02-11-2026 (<= hari ini, agar site handover bisa dicatat; ST-11), selesai 20-12-2026.
   Estimasi memakai PlanCost 10.000.000; ganti nilainya agar totalnya sama dengan PlanCost request Anda.

   DECLARE @Req INT = 3, @Civil NVARCHAR(100) = N'users1',
           @Other NVARCHAR(100) = N'marisi';

   -- 1) Bukan civil -> 50075; mulai plan sebelum mulai project -> 50072; total bobot > 100 -> 50072
   BEGIN TRY EXEC dbo.usp_Request_SaveSchedule @Id = @Req, @Username = @Other, @ProjectStartDate = '2026-11-02', @ActionPlanJson = N'[]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SaveSchedule @Id = @Req, @Username = @Civil, @ProjectStartDate = '2026-11-02',
        @ActionPlanJson = N'[{"id":0,"name":"Survey","weight":10,"start":"2026-11-01","end":"2026-11-05"}]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (row 1 start)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SaveSchedule @Id = @Req, @Username = @Civil, @ProjectStartDate = '2026-11-02',
        @ActionPlanJson = N'[{"id":0,"name":"A","weight":60,"start":"2026-11-02","end":"2026-11-20"},{"id":0,"name":"B","weight":50,"start":"2026-11-21","end":"2026-12-20"}]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (weight > 100)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Draft belum lengkap (total 40%) boleh disimpan saat SCHEDULING
   EXEC dbo.usp_Request_SaveSchedule @Id = @Req, @Username = @Civil, @ProjectStartDate = '2026-11-02',
        @ActionPlanJson = N'[{"id":0,"name":"Preparation works","weight":40,"start":"2026-11-02","end":"2026-11-20"}]';
   EXEC dbo.usp_Request_GetSchedule @RequestId = @Req, @Username = @Civil;          -- TotalWeight 40, ProjectEndDate 2026-11-20

   -- 3) Handover belum lengkap -> 50072 (bobot, estimasi)
   BEGIN TRY EXEC dbo.usp_Request_SiteHandover @Id = @Req, @Username = @Civil, @HandoverDate = '2026-11-14';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '3 expect 50072 (incomplete)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 4) Lengkapi: ubah baris 1 (Id lama dipertahankan) + tambah baris 2 -> total 100%, selesai 2026-12-20
   DECLARE @Ap1 INT = (SELECT MIN(Id) FROM dbo.ProjectActionPlan WHERE RequestId = @Req);
   DECLARE @Json NVARCHAR(MAX) = N'[{"id":' + CAST(@Ap1 AS NVARCHAR(10)) + N',"name":"Preparation works","weight":40,"start":"2026-11-02","end":"2026-11-20"},'
                               + N'{"id":0,"name":"Main construction","weight":60,"start":"2026-11-21","end":"2026-12-20"}]';
   EXEC dbo.usp_Request_SaveSchedule @Id = @Req, @Username = @Civil, @ProjectStartDate = '2026-11-02', @ActionPlanJson = @Json;
   EXEC dbo.usp_Request_GetSchedule @RequestId = @Req, @Username = @Civil;          -- baris 1 Id sama, TotalWeight 100

   -- 5) Estimasi: bulan di luar Nov-Des 2026 -> 50072; bulan ganda -> 50072; melebihi PlanCost -> 50072; lalu simpan valid
   BEGIN TRY EXEC dbo.usp_Request_SaveCostEstimate @Id = @Req, @Username = @Civil, @EstimateJson = N'[{"month":"2026-10-01","amount":1000}]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '5a expect 50072 (month range)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SaveCostEstimate @Id = @Req, @Username = @Civil, @EstimateJson = N'[{"month":"2026-11-01","amount":1000},{"month":"2026-11-15","amount":1000}]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '5b expect 50072 (duplicate month)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SaveCostEstimate @Id = @Req, @Username = @Civil, @EstimateJson = N'[{"month":"2026-11-01","amount":999999999999}]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '5c expect 50072 (over plan cost)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Request_SaveCostEstimate @Id = @Req, @Username = @Civil,
        @EstimateJson = N'[{"month":"2026-11-01","amount":4000000},{"month":"2026-12-01","amount":6000000}]';   -- total = PlanCost

   -- 6) Handover di masa depan -> 50072; sebelum mulai project -> 50072; valid -> IN_PROGRESS
   BEGIN TRY EXEC dbo.usp_Request_SiteHandover @Id = @Req, @Username = @Civil, @HandoverDate = '2099-01-01';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '6a expect 50072 (future)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SiteHandover @Id = @Req, @Username = @Civil, @HandoverDate = '2026-11-01';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '6b expect 50072 (before start)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Request_SiteHandover @Id = @Req, @Username = @Civil, @HandoverDate = '2026-11-14', @Remarks = N'Site handed over';

   -- 7) Saat IN_PROGRESS: tanpa alasan -> 50072; total <> PlanCost -> 50072; dengan alasan -> riwayat ESTIMATE_CHANGE
   BEGIN TRY EXEC dbo.usp_Request_SaveCostEstimate @Id = @Req, @Username = @Civil,
        @EstimateJson = N'[{"month":"2026-11-01","amount":3000000},{"month":"2026-12-01","amount":7000000}]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '7a expect 50072 (reason)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SaveCostEstimate @Id = @Req, @Username = @Civil,
        @EstimateJson = N'[{"month":"2026-11-01","amount":3000000}]', @Reason = N'Test';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '7b expect 50072 (total = plan cost)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Request_SaveCostEstimate @Id = @Req, @Username = @Civil,
        @EstimateJson = N'[{"month":"2026-11-01","amount":3000000},{"month":"2026-12-01","amount":7000000}]',
        @Reason = N'Material delivery moved to December';
   SELECT TOP (3) Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt FROM dbo.ApprovalHistory WHERE RequestId = @Req ORDER BY Id DESC;

   -- 8) Tugas Saya civil: request SCHEDULING lain (bila ada) muncul sebagai SCHEDULING; @Req tidak lagi (sudah IN_PROGRESS)
   EXEC dbo.usp_Task_GetList @Username = @Civil, @TaskType = 'SCHEDULING';
   ===================================================================== */
GO
/* ---------- end RequestSchedule.sql ---------- */
/* ---------- begin RequestProgress.sql ---------- */
PRINT N'[skema] RequestProgress.sql';
GO
/* =====================================================================
   RequestProgress.sql  -  Progress mingguan per action plan, plan progress (kurva S), status jadwal
                           (T5-1; PRD 3.3 langkah 5, BR-16, BR-17, BR-68, BR-71, CF-08, Data 4)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestSchedule.sql
             (dan jalankan ulang RequestSchedule.sql: action plan yang sudah punya progress tidak boleh dihapus).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Aturan (Keputusan 14-11-2026 dan 16-11-2026, lihat docs/PRD-log.md):
     - Minggu = Senin s.d. Minggu. Satu catatan progress per project per minggu; simpan ulang minggu yang sama
       menimpa isinya. Hanya saat IN_PROGRESS, minggu dari minggu mulai project s.d. minggu berjalan.
     - Civil mengisi % progress SEMUA action plan untuk minggu itu. Progress per action plan tidak boleh turun
       dibanding minggu sebelumnya (dan tidak boleh melebihi minggu sesudahnya bila mengubah minggu lama).
     - Tanggal aktual per action plan diisi Civil: mulai aktual wajib bila progress terkini > 0; selesai aktual
       wajib bila progress terkini = 100% dan harus kosong bila < 100%. Tanggal aktual tidak di masa depan.
     - % aktual project = Σ(bobot × % progress) / 100 (BR-17).
     - % plan = Σ(bobot × porsi hari plan yang sudah lewat), bobot disebar linear per hari antara tanggal mulai
       dan selesai plan (BR-17, Keputusan 14-11-2026); dihitung pada hari Minggu minggu tersebut.
     - Status jadwal (BR-68, ambang CF-08 dari AppSetting): deviasi = aktual − plan;
         ON_TRACK bila deviasi >= SCHEDULE_ONTRACK_MIN_DEV (-5); SLIGHT_DELAY bila >= SCHEDULE_SLIGHT_MIN_DEV (-15);
         selain itu DELAY. DELAY juga bila tanggal selesai project (plan) sudah lewat pada minggu itu dan aktual < 100.
     - Status project (ProjectRequest) diambil dari minggu terakhir yang tersimpan; dihitung otomatis saat
       progress disimpan, tidak bisa diinput manual (BR-71).
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai (civil)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Migrasi kolom dbo.ProjectRequest (ringkasan progress + status jadwal terkini)
   --------------------------------------------------------------------- */
IF COL_LENGTH(N'dbo.ProjectRequest', N'ProgressPercent') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        ProgressPercent      DECIMAL(5, 2) NULL,    -- % aktual minggu terakhir
        PlanProgressPercent  DECIMAL(5, 2) NULL,    -- % plan minggu terakhir
        ScheduleStatus       VARCHAR(20)   NULL
            CONSTRAINT CK_ProjectRequest_ScheduleStatus CHECK (ScheduleStatus IS NULL OR ScheduleStatus IN ('ON_TRACK', 'SLIGHT_DELAY', 'DELAY')),
        ScheduleStatusAt     DATETIME2(3)  NULL;
END
GO

/* ---------------------------------------------------------------------
   2. TABLE dbo.ProjectProgressWeek  (satu baris per project per minggu)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectProgressWeek', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectProgressWeek
    (
        Id              INT IDENTITY(1,1) NOT NULL,
        RequestId       INT            NOT NULL,
        WeekStart       DATE           NOT NULL,     -- Senin
        WeekEnd         DATE           NOT NULL,     -- Minggu
        PlanPercent     DECIMAL(5, 2)  NOT NULL,
        ActualPercent   DECIMAL(5, 2)  NOT NULL,
        Deviation       DECIMAL(6, 2)  NOT NULL,
        ScheduleStatus  VARCHAR(20)    NOT NULL,
        Remarks         NVARCHAR(1000) NULL,
        CreatedAt       DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectProgressWeek_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy       NVARCHAR(100)  NOT NULL,
        UpdatedAt       DATETIME2(3)   NULL,
        UpdatedBy       NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectProgressWeek PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectProgressWeek UNIQUE (RequestId, WeekStart),
        CONSTRAINT FK_ProjectProgressWeek_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT CK_ProjectProgressWeek_Status CHECK (ScheduleStatus IN ('ON_TRACK', 'SLIGHT_DELAY', 'DELAY')),
        CONSTRAINT CK_ProjectProgressWeek_Week   CHECK (WeekEnd = DATEADD(DAY, 6, WeekStart))
    );
END
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.ProjectProgressItem  (% progress per action plan per minggu)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectProgressItem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectProgressItem
    (
        Id               INT IDENTITY(1,1) NOT NULL,
        WeekId           INT           NOT NULL,
        ActionPlanId     INT           NOT NULL,
        ProgressPercent  DECIMAL(5, 2) NOT NULL,
        CONSTRAINT PK_ProjectProgressItem PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectProgressItem UNIQUE (WeekId, ActionPlanId),
        CONSTRAINT FK_ProjectProgressItem_Week       FOREIGN KEY (WeekId)       REFERENCES dbo.ProjectProgressWeek (Id),
        CONSTRAINT FK_ProjectProgressItem_ActionPlan FOREIGN KEY (ActionPlanId) REFERENCES dbo.ProjectActionPlan (Id),
        CONSTRAINT CK_ProjectProgressItem_Progress   CHECK (ProgressPercent >= 0 AND ProgressPercent <= 100)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ProjectProgressItem_ActionPlan' AND object_id = OBJECT_ID(N'dbo.ProjectProgressItem'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectProgressItem_ActionPlan ON dbo.ProjectProgressItem (ActionPlanId) INCLUDE (WeekId, ProgressPercent);
END
GO

/* ---------------------------------------------------------------------
   4. dbo.fn_WeekStart(@Date)  -> Senin minggu tersebut (tidak bergantung SET DATEFIRST; 1900-01-01 = Senin)
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_WeekStart
(
    @Date DATE
)
RETURNS DATE
AS
BEGIN
    RETURN DATEADD(DAY, -(DATEDIFF(DAY, '19000101', @Date) % 7), @Date);
END
GO

/* ---------------------------------------------------------------------
   5. dbo.fn_Request_PlanProgress(@RequestId, @AsOf)  -> % plan project pada tanggal @AsOf (BR-17)
      Per action plan: porsi = (hari dari mulai plan s.d. @AsOf, inklusif) / (durasi plan, inklusif), dibatasi 0..1.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_Request_PlanProgress
(
    @RequestId INT,
    @AsOf      DATE
)
RETURNS TABLE
AS
RETURN
(
    SELECT CAST(ROUND(ISNULL(SUM(
               a.WeightPercent *
               CASE WHEN @AsOf <  a.PlanStartDate THEN 0.0
                    WHEN @AsOf >= a.PlanEndDate   THEN 1.0
                    ELSE CAST(DATEDIFF(DAY, a.PlanStartDate, @AsOf) + 1 AS DECIMAL(18, 6))
                         / (DATEDIFF(DAY, a.PlanStartDate, a.PlanEndDate) + 1)
               END), 0), 2) AS DECIMAL(5, 2)) AS PlanPercent
    FROM   dbo.ProjectActionPlan a
    WHERE  a.RequestId = @RequestId
);
GO

/* ---------------------------------------------------------------------
   6. usp_Request_GetProgress  (Details)
      Result 1: ringkasan (0 baris = tidak ada / di luar lingkup / purchasing-only)
      Result 2: daftar minggu tersimpan, terbaru di atas
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetProgress
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))   -- purchasing: tanpa akses progress (5.2)
             THEN 1 ELSE 0 END;

    SELECT  r.Id AS RequestId, r.Status, r.ProjectStartDate,
            (SELECT MAX(a.PlanEndDate) FROM dbo.ProjectActionPlan a WHERE a.RequestId = r.Id) AS ProjectEndDate,
            r.ProgressPercent, r.PlanProgressPercent, r.ScheduleStatus, r.ScheduleStatusAt,
            (SELECT MAX(w.WeekStart) FROM dbo.ProjectProgressWeek w WHERE w.RequestId = r.Id) AS LatestWeekStart,
            dbo.fn_WeekStart(@Today) AS CurrentWeekStart,
            CASE WHEN r.ProjectStartDate IS NULL THEN NULL ELSE dbo.fn_WeekStart(r.ProjectStartDate) END AS FirstWeekStart,
            (SELECT p.PlanPercent FROM dbo.fn_Request_PlanProgress(r.Id, @Today) p) AS PlanPercentToday
    FROM    dbo.ProjectRequest r
    WHERE   r.Id = @RequestId AND @Visible = 1;

    SELECT  w.Id, w.RequestId, w.WeekStart, w.WeekEnd, w.PlanPercent, w.ActualPercent, w.Deviation, w.ScheduleStatus,
            w.Remarks, w.CreatedAt, w.CreatedBy, w.UpdatedAt, w.UpdatedBy
    FROM    dbo.ProjectProgressWeek w
    WHERE   w.RequestId = @RequestId AND @Visible = 1
    ORDER BY w.WeekStart DESC;
END
GO

/* ---------------------------------------------------------------------
   7. usp_Request_GetProgressWeek  (form input satu minggu)
      Per action plan: % minggu ini (bila sudah tersimpan), atau % minggu tersimpan sebelumnya sebagai nilai awal;
      batas bawah (minggu sebelumnya) dan batas atas (minggu sesudahnya); % plan action plan pada hari Minggu.
      Result 1: info minggu (WeekStart, WeekEnd, IsSaved, Remarks) · Result 2: baris action plan.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetProgressWeek
    @RequestId INT,
    @WeekDate  DATE,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @WeekStart DATE = dbo.fn_WeekStart(ISNULL(@WeekDate, CAST(SYSDATETIME() AS DATE)));
    DECLARE @WeekEnd DATE = DATEADD(DAY, 6, @WeekStart);

    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
             THEN 1 ELSE 0 END;

    DECLARE @WeekId INT = (SELECT w.Id FROM dbo.ProjectProgressWeek w WHERE w.RequestId = @RequestId AND w.WeekStart = @WeekStart);

    SELECT  @WeekStart AS WeekStart, @WeekEnd AS WeekEnd,
            CAST(CASE WHEN @WeekId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsSaved,
            (SELECT w.Remarks FROM dbo.ProjectProgressWeek w WHERE w.Id = @WeekId) AS Remarks
    WHERE   @Visible = 1;

    SELECT  a.Id AS ActionPlanId, a.SortOrder, a.Name, a.WeightPercent, a.PlanStartDate, a.PlanEndDate,
            a.ActualStartDate, a.ActualEndDate,
            CAST(ROUND(CASE WHEN @WeekEnd <  a.PlanStartDate THEN 0.0
                            WHEN @WeekEnd >= a.PlanEndDate   THEN 100.0
                            ELSE 100.0 * (DATEDIFF(DAY, a.PlanStartDate, @WeekEnd) + 1) / (DATEDIFF(DAY, a.PlanStartDate, a.PlanEndDate) + 1)
                       END, 2) AS DECIMAL(5, 2)) AS PlanPercent,
            cur.ProgressPercent AS SavedPercent,
            ISNULL(prev.ProgressPercent, 0) AS MinPercent,
            ISNULL(nxt.ProgressPercent, 100) AS MaxPercent
    FROM    dbo.ProjectActionPlan a
            OUTER APPLY (SELECT i.ProgressPercent FROM dbo.ProjectProgressItem i
                         WHERE i.WeekId = @WeekId AND i.ActionPlanId = a.Id) cur
            OUTER APPLY (SELECT TOP (1) i.ProgressPercent
                         FROM dbo.ProjectProgressItem i JOIN dbo.ProjectProgressWeek w ON w.Id = i.WeekId
                         WHERE i.ActionPlanId = a.Id AND w.WeekStart < @WeekStart
                         ORDER BY w.WeekStart DESC) prev
            OUTER APPLY (SELECT TOP (1) i.ProgressPercent
                         FROM dbo.ProjectProgressItem i JOIN dbo.ProjectProgressWeek w ON w.Id = i.WeekId
                         WHERE i.ActionPlanId = a.Id AND w.WeekStart > @WeekStart
                         ORDER BY w.WeekStart ASC) nxt
    WHERE   a.RequestId = @RequestId AND @Visible = 1
    ORDER BY a.SortOrder, a.Id;
END
GO

/* ---------------------------------------------------------------------
   8. usp_Request_SaveProgress  (civil; IN_PROGRESS)
      @WeekDate  : tanggal mana pun di minggu tersebut (dinormalisasi ke Senin)
      @ItemsJson : [{"id":<ActionPlanId>,"progress":50,"actualStart":"2026-11-10","actualEnd":null}, ...]
                   wajib memuat SEMUA action plan request.
      Hasil: SELECT minggu tersimpan (WeekStart, PlanPercent, ActualPercent, Deviation, ScheduleStatus).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveProgress
    @Id         INT,
    @Username   NVARCHAR(100),
    @WeekDate   DATE,
    @ItemsJson  NVARCHAR(MAX),
    @Remarks    NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can enter progress.', 1;
    IF @WeekDate IS NULL
        THROW 50072, N'Week is required.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;
    IF ISJSON(ISNULL(@ItemsJson, N'[]')) = 0
        THROW 50072, N'Progress data is invalid.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);
    DECLARE @WeekStart DATE = dbo.fn_WeekStart(@WeekDate);
    DECLARE @WeekEnd DATE = DATEADD(DAY, 6, @WeekStart);
    DECLARE @Msg NVARCHAR(2048);

    DECLARE @Items TABLE
    (
        Seq          INT           NOT NULL PRIMARY KEY,
        ActionPlanId INT           NULL,
        Progress     DECIMAL(9, 2) NULL,
        ActualStart  DATE          NULL,
        ActualEnd    DATE          NULL
    );

    INSERT INTO @Items (Seq, ActionPlanId, Progress, ActualStart, ActualEnd)
    SELECT  CAST(j.[key] AS INT) + 1, x.id, x.progress, x.actualStart, x.actualEnd
    FROM    OPENJSON(ISNULL(@ItemsJson, N'[]')) j
            CROSS APPLY OPENJSON(j.[value])
            WITH (id INT '$.id', progress DECIMAL(9, 2) '$.progress', actualStart DATE '$.actualStart', actualEnd DATE '$.actualEnd') x;

    -- Validasi isi per baris (tanpa data database)
    SELECT TOP (1) @Msg = N'Action plan row ' + CAST(i.Seq AS NVARCHAR(10)) + N': ' +
           CASE WHEN i.Progress IS NULL OR i.Progress < 0 OR i.Progress > 100 THEN N'progress must be between 0 and 100%.'
                WHEN i.ActualStart > @Today OR i.ActualEnd > @Today           THEN N'actual dates cannot be in the future.'
                ELSE N'actual end date must be on or after the actual start date.' END
    FROM   @Items i
    WHERE  i.Progress IS NULL OR i.Progress < 0 OR i.Progress > 100
       OR  i.ActualStart > @Today OR i.ActualEnd > @Today
       OR  (i.ActualStart IS NOT NULL AND i.ActualEnd IS NOT NULL AND i.ActualEnd < i.ActualStart)
    ORDER BY i.Seq;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    DECLARE @Status VARCHAR(20), @StartDate DATE, @CoCode VARCHAR(10);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @StartDate = r.ProjectStartDate, @CoCode = r.CoCode
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'IN_PROGRESS'
        THROW 50074, N'Progress can only be entered while the project is in progress.', 1;
    IF @StartDate IS NULL
        THROW 50072, N'Project start date is not set.', 1;
    IF @WeekStart < dbo.fn_WeekStart(@StartDate)
        THROW 50072, N'The week is before the project start date.', 1;
    IF @WeekStart > dbo.fn_WeekStart(@Today)
        THROW 50072, N'Progress cannot be entered for a future week.', 1;

    -- Semua action plan request tepat satu kali
    IF EXISTS (SELECT 1 FROM @Items i
               WHERE i.ActionPlanId IS NULL
                  OR NOT EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a WHERE a.Id = i.ActionPlanId AND a.RequestId = @Id))
       OR EXISTS (SELECT ActionPlanId FROM @Items GROUP BY ActionPlanId HAVING COUNT(*) > 1)
       OR EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a WHERE a.RequestId = @Id
                  AND NOT EXISTS (SELECT 1 FROM @Items i WHERE i.ActionPlanId = a.Id))
        THROW 50072, N'Action plan data is outdated. Please reload the page.', 1;

    -- Tidak boleh turun dibanding minggu sebelumnya / melebihi minggu sesudahnya
    SELECT TOP (1) @Msg = N'"' + a.Name + N'": progress cannot be '
           + CASE WHEN i.Progress < ISNULL(prev.ProgressPercent, 0)
                  THEN N'lower than the previous week (' + FORMAT(prev.ProgressPercent, N'0.##', 'en-US') + N'%).'
                  ELSE N'higher than a later week (' + FORMAT(nxt.ProgressPercent, N'0.##', 'en-US') + N'%). Update the later week first.' END
    FROM   @Items i
           JOIN dbo.ProjectActionPlan a ON a.Id = i.ActionPlanId
           OUTER APPLY (SELECT TOP (1) pi.ProgressPercent
                        FROM dbo.ProjectProgressItem pi JOIN dbo.ProjectProgressWeek w ON w.Id = pi.WeekId
                        WHERE pi.ActionPlanId = a.Id AND w.WeekStart < @WeekStart ORDER BY w.WeekStart DESC) prev
           OUTER APPLY (SELECT TOP (1) pi.ProgressPercent
                        FROM dbo.ProjectProgressItem pi JOIN dbo.ProjectProgressWeek w ON w.Id = pi.WeekId
                        WHERE pi.ActionPlanId = a.Id AND w.WeekStart > @WeekStart ORDER BY w.WeekStart ASC) nxt
    WHERE  i.Progress < ISNULL(prev.ProgressPercent, 0)
       OR  i.Progress > ISNULL(nxt.ProgressPercent, 100)
    ORDER BY a.SortOrder;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    -- Progress terkini per action plan setelah simpan: minggu ini bila ini minggu terakhir, selain itu minggu terakhir
    DECLARE @IsLatest BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectProgressWeek w WHERE w.RequestId = @Id AND w.WeekStart > @WeekStart)
             THEN 0 ELSE 1 END;

    DECLARE @Current TABLE (ActionPlanId INT PRIMARY KEY, Progress DECIMAL(9, 2) NOT NULL, ActualStart DATE NULL, ActualEnd DATE NULL);
    INSERT INTO @Current (ActionPlanId, Progress, ActualStart, ActualEnd)
    SELECT  i.ActionPlanId,
            CASE WHEN @IsLatest = 1 THEN i.Progress
                 ELSE (SELECT TOP (1) pi.ProgressPercent
                       FROM dbo.ProjectProgressItem pi JOIN dbo.ProjectProgressWeek w ON w.Id = pi.WeekId
                       WHERE pi.ActionPlanId = i.ActionPlanId ORDER BY w.WeekStart DESC) END,
            i.ActualStart, i.ActualEnd
    FROM    @Items i;
    UPDATE @Current SET Progress = 0 WHERE Progress IS NULL;   -- action plan baru tanpa data minggu terakhir

    -- Tanggal aktual sesuai progress terkini (Keputusan 16-11-2026)
    SELECT TOP (1) @Msg = N'"' + a.Name + N'": ' +
           CASE WHEN c.Progress > 0 AND c.ActualStart IS NULL   THEN N'actual start date is required once progress is above 0%.'
                WHEN c.Progress = 100 AND c.ActualEnd IS NULL   THEN N'actual end date is required when progress is 100%.'
                ELSE N'actual end date must be empty until progress reaches 100%.' END
    FROM   @Current c
           JOIN dbo.ProjectActionPlan a ON a.Id = c.ActionPlanId
    WHERE  (c.Progress > 0 AND c.ActualStart IS NULL)
       OR  (c.Progress = 100 AND c.ActualEnd IS NULL)
       OR  (c.Progress < 100 AND c.ActualEnd IS NOT NULL)
    ORDER BY a.SortOrder;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    /* -- Hitung % aktual, % plan, status jadwal minggu ini (BR-17, BR-68) -- */
    DECLARE @Actual DECIMAL(5, 2) =
        CAST(ROUND((SELECT ISNULL(SUM(a.WeightPercent * i.Progress), 0) / 100.0
                    FROM @Items i JOIN dbo.ProjectActionPlan a ON a.Id = i.ActionPlanId), 2) AS DECIMAL(5, 2));
    DECLARE @Plan DECIMAL(5, 2) = (SELECT p.PlanPercent FROM dbo.fn_Request_PlanProgress(@Id, @WeekEnd) p);
    DECLARE @Dev DECIMAL(6, 2) = @Actual - @Plan;
    DECLARE @EndDate DATE = (SELECT MAX(a.PlanEndDate) FROM dbo.ProjectActionPlan a WHERE a.RequestId = @Id);

    -- Ambang CF-08 (baris Company, fallback '*'); default sesuai PRD bila tidak ada
    DECLARE @OnTrackMin DECIMAL(9, 2) = ISNULL((SELECT TOP (1) TRY_CAST(s.SettingValue AS DECIMAL(9, 2)) FROM dbo.AppSetting s
                                                WHERE s.SettingKey = 'SCHEDULE_ONTRACK_MIN_DEV' AND s.CoCode IN (@CoCode, '*')
                                                ORDER BY CASE WHEN s.CoCode = @CoCode THEN 0 ELSE 1 END), -5);
    DECLARE @SlightMin DECIMAL(9, 2)  = ISNULL((SELECT TOP (1) TRY_CAST(s.SettingValue AS DECIMAL(9, 2)) FROM dbo.AppSetting s
                                                WHERE s.SettingKey = 'SCHEDULE_SLIGHT_MIN_DEV' AND s.CoCode IN (@CoCode, '*')
                                                ORDER BY CASE WHEN s.CoCode = @CoCode THEN 0 ELSE 1 END), -15);

    DECLARE @WeekStatus VARCHAR(20) =
        CASE WHEN @EndDate < @WeekEnd AND @Actual < 100 THEN 'DELAY'
             WHEN @Dev >= @OnTrackMin THEN 'ON_TRACK'
             WHEN @Dev >= @SlightMin  THEN 'SLIGHT_DELAY'
             ELSE 'DELAY' END;

    /* -- Simpan minggu (timpa bila sudah ada) -- */
    DECLARE @WeekId INT = (SELECT w.Id FROM dbo.ProjectProgressWeek w WITH (UPDLOCK, HOLDLOCK)
                           WHERE w.RequestId = @Id AND w.WeekStart = @WeekStart);

    IF @WeekId IS NULL
    BEGIN
        INSERT INTO dbo.ProjectProgressWeek
            (RequestId, WeekStart, WeekEnd, PlanPercent, ActualPercent, Deviation, ScheduleStatus, Remarks, CreatedAt, CreatedBy)
        VALUES (@Id, @WeekStart, @WeekEnd, @Plan, @Actual, @Dev, @WeekStatus, @Remarks, @Now, @Username);
        SET @WeekId = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.ProjectProgressWeek
        SET    PlanPercent = @Plan, ActualPercent = @Actual, Deviation = @Dev, ScheduleStatus = @WeekStatus,
               Remarks = @Remarks, UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  Id = @WeekId;
        DELETE FROM dbo.ProjectProgressItem WHERE WeekId = @WeekId;
    END

    INSERT INTO dbo.ProjectProgressItem (WeekId, ActionPlanId, ProgressPercent)
    SELECT @WeekId, i.ActionPlanId, i.Progress
    FROM   @Items i;

    /* -- Action plan: progress terkini + tanggal aktual -- */
    UPDATE a
    SET    a.ProgressPercent = c.Progress, a.ActualStartDate = c.ActualStart, a.ActualEndDate = c.ActualEnd,
           a.UpdatedAt = @Now, a.UpdatedBy = @Username
    FROM   dbo.ProjectActionPlan a
           JOIN @Current c ON c.ActionPlanId = a.Id;

    /* -- Ringkasan project = minggu terakhir yang tersimpan (BR-71) -- */
    UPDATE r
    SET    r.ProgressPercent = w.ActualPercent, r.PlanProgressPercent = w.PlanPercent,
           r.ScheduleStatus = w.ScheduleStatus, r.ScheduleStatusAt = @Now,
           r.UpdatedAt = @Now, r.UpdatedBy = @Username
    FROM   dbo.ProjectRequest r
           CROSS APPLY (SELECT TOP (1) x.ActualPercent, x.PlanPercent, x.ScheduleStatus
                        FROM dbo.ProjectProgressWeek x WHERE x.RequestId = r.Id ORDER BY x.WeekStart DESC) w
    WHERE  r.Id = @Id;

    COMMIT TRANSACTION;

    SELECT @WeekStart AS WeekStart, @Plan AS PlanPercent, @Actual AS ActualPercent, @Dev AS Deviation, @WeekStatus AS ScheduleStatus;
END
GO

/* ---------------------------------------------------------------------
   9. usp_Request_RefreshScheduleSummary  (internal; T4-4, BR-84, Keputusan 17-11-2026)
      Dipanggil saat schedule / bobot berubah ketika IN_PROGRESS (usp_Request_SaveSchedule, termasuk penyesuaian
      addendum). Ringkasan project dihitung ulang pada minggu terakhir yang tersimpan:
        % aktual = Σ(bobot baru × % progress terkini action plan) / 100 (boleh turun; BR-84)
        % plan   = fn_Request_PlanProgress pada hari Minggu minggu itu (schedule terbaru)
        status   = aturan sama dengan usp_Request_SaveProgress (CF-08)
      Baris minggu lama (ProjectProgressWeek / ProjectProgressItem) TIDAK diubah.
      Tanpa minggu tersimpan: tidak ada perubahan. Tidak membuka transaksi sendiri (ikut pemanggil).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_RefreshScheduleSummary
    @Id          INT,
    @Username    NVARCHAR(100),
    @OldPercent  DECIMAL(5, 2) = NULL OUTPUT,
    @NewPercent  DECIMAL(5, 2) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CoCode VARCHAR(10), @WeekEnd DATE;

    SELECT  @OldPercent = r.ProgressPercent, @CoCode = r.CoCode
    FROM    dbo.ProjectRequest r
    WHERE   r.Id = @Id;

    SET @NewPercent = @OldPercent;
    SET @WeekEnd = (SELECT MAX(w.WeekEnd) FROM dbo.ProjectProgressWeek w WHERE w.RequestId = @Id);

    IF @WeekEnd IS NULL
        RETURN;

    DECLARE @Actual DECIMAL(5, 2) =
        CAST(ROUND((SELECT ISNULL(SUM(a.WeightPercent * a.ProgressPercent), 0) / 100.0
                    FROM dbo.ProjectActionPlan a WHERE a.RequestId = @Id), 2) AS DECIMAL(5, 2));
    DECLARE @Plan DECIMAL(5, 2) = (SELECT p.PlanPercent FROM dbo.fn_Request_PlanProgress(@Id, @WeekEnd) p);
    DECLARE @Dev DECIMAL(6, 2) = @Actual - @Plan;
    DECLARE @EndDate DATE = (SELECT MAX(a.PlanEndDate) FROM dbo.ProjectActionPlan a WHERE a.RequestId = @Id);

    DECLARE @OnTrackMin DECIMAL(9, 2) = ISNULL((SELECT TOP (1) TRY_CAST(s.SettingValue AS DECIMAL(9, 2)) FROM dbo.AppSetting s
                                                WHERE s.SettingKey = 'SCHEDULE_ONTRACK_MIN_DEV' AND s.CoCode IN (@CoCode, '*')
                                                ORDER BY CASE WHEN s.CoCode = @CoCode THEN 0 ELSE 1 END), -5);
    DECLARE @SlightMin DECIMAL(9, 2)  = ISNULL((SELECT TOP (1) TRY_CAST(s.SettingValue AS DECIMAL(9, 2)) FROM dbo.AppSetting s
                                                WHERE s.SettingKey = 'SCHEDULE_SLIGHT_MIN_DEV' AND s.CoCode IN (@CoCode, '*')
                                                ORDER BY CASE WHEN s.CoCode = @CoCode THEN 0 ELSE 1 END), -15);

    DECLARE @Status VARCHAR(20) =
        CASE WHEN @EndDate < @WeekEnd AND @Actual < 100 THEN 'DELAY'
             WHEN @Dev >= @OnTrackMin THEN 'ON_TRACK'
             WHEN @Dev >= @SlightMin  THEN 'SLIGHT_DELAY'
             ELSE 'DELAY' END;

    UPDATE dbo.ProjectRequest
    SET    ProgressPercent = @Actual, PlanProgressPercent = @Plan,
           ScheduleStatus = @Status, ScheduleStatusAt = SYSDATETIME(),
           UpdatedAt = SYSDATETIME(), UpdatedBy = @Username
    WHERE  Id = @Id;

    SET @NewPercent = @Actual;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: request IN_PROGRESS dengan 2 action plan, mis. hasil test T4-2:
     "Preparation works" 40%  02-11-2026 s.d. 20-11-2026 · "Main construction" 60%  21-11-2026 s.d. 20-12-2026.
   Hari ini 16-11-2026 (Senin) -> minggu berjalan 16-11 s.d. 22-11; minggu lalu 09-11 s.d. 15-11.

   DECLARE @Req INT = 1008, @Civil NVARCHAR(100) = N'users1', @Other NVARCHAR(100) = N'hdahlia';
   DECLARE @A1 INT = (SELECT MIN(Id) FROM dbo.ProjectActionPlan WHERE RequestId = @Req),
           @A2 INT = (SELECT MAX(Id) FROM dbo.ProjectActionPlan WHERE RequestId = @Req);
   DECLARE @J NVARCHAR(MAX);

   -- 0) Fungsi bantu
   SELECT dbo.fn_WeekStart('2026-11-16') AS Mon1, dbo.fn_WeekStart('2026-11-22') AS Mon2;                 -- 2026-11-16 keduanya
   SELECT * FROM dbo.fn_Request_PlanProgress(@Req, '2026-11-15');                                         -- 40 x 14/19 = 29.47
   EXEC dbo.usp_Request_GetProgressWeek @RequestId = @Req, @WeekDate = '2026-11-10', @Username = @Civil;

   -- 1) Bukan civil -> 50075; minggu depan -> 50072; action plan kurang -> 50072; progress > 0 tanpa mulai aktual -> 50072
   BEGIN TRY EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Other, @WeekDate = '2026-11-10', @ItemsJson = N'[]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"id":' + CAST(@A1 AS NVARCHAR(10)) + N',"progress":0},{"id":' + CAST(@A2 AS NVARCHAR(10)) + N',"progress":0}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Civil, @WeekDate = '2026-11-25', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (future week)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"id":' + CAST(@A1 AS NVARCHAR(10)) + N',"progress":10}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Civil, @WeekDate = '2026-11-10', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (missing plan)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"id":' + CAST(@A1 AS NVARCHAR(10)) + N',"progress":50},{"id":' + CAST(@A2 AS NVARCHAR(10)) + N',"progress":0}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Civil, @WeekDate = '2026-11-10', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1d expect 50072 (actual start)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Minggu lalu: plan 29.47 (Minggu 15-11), aktual 40 x 50% = 20 -> deviasi -9.47 -> SLIGHT_DELAY
   SET @J = N'[{"id":' + CAST(@A1 AS NVARCHAR(10)) + N',"progress":50,"actualStart":"2026-11-03"},{"id":' + CAST(@A2 AS NVARCHAR(10)) + N',"progress":0}]';
   EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Civil, @WeekDate = '2026-11-10', @ItemsJson = @J, @Remarks = N'Week 2';

   -- 3) Minggu ini: turun dari 50 -> 50072; selesai 100 tanpa selesai aktual -> 50072; valid -> plan pada 22-11
   SET @J = N'[{"id":' + CAST(@A1 AS NVARCHAR(10)) + N',"progress":40,"actualStart":"2026-11-03"},{"id":' + CAST(@A2 AS NVARCHAR(10)) + N',"progress":0}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Civil, @WeekDate = '2026-11-16', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '3a expect 50072 (decrease)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"id":' + CAST(@A1 AS NVARCHAR(10)) + N',"progress":100,"actualStart":"2026-11-03"},{"id":' + CAST(@A2 AS NVARCHAR(10)) + N',"progress":0}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Civil, @WeekDate = '2026-11-16', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '3b expect 50072 (actual end)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"id":' + CAST(@A1 AS NVARCHAR(10)) + N',"progress":100,"actualStart":"2026-11-03","actualEnd":"2026-11-16"},{"id":' + CAST(@A2 AS NVARCHAR(10)) + N',"progress":0}]';
   EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Civil, @WeekDate = '2026-11-16', @ItemsJson = @J;   -- plan 40 + 60x2/30 = 44, aktual 40 -> ON_TRACK

   -- 4) Ubah minggu lalu ke 60 (boleh: >= 0 sebelumnya, <= 100 minggu sesudahnya); ringkasan project tetap dari minggu terakhir
   SET @J = N'[{"id":' + CAST(@A1 AS NVARCHAR(10)) + N',"progress":60,"actualStart":"2026-11-03","actualEnd":"2026-11-16"},{"id":' + CAST(@A2 AS NVARCHAR(10)) + N',"progress":0}]';
   EXEC dbo.usp_Request_SaveProgress @Id = @Req, @Username = @Civil, @WeekDate = '2026-11-10', @ItemsJson = @J;      -- aktual 24, SLIGHT_DELAY
   EXEC dbo.usp_Request_GetProgress @RequestId = @Req, @Username = @Civil;          -- ProgressPercent 40, ScheduleStatus ON_TRACK (minggu 16-11)
   SELECT Id, Name, ProgressPercent, ActualStartDate, ActualEndDate FROM dbo.ProjectActionPlan WHERE RequestId = @Req ORDER BY SortOrder;

   -- 5) Hapus action plan yang sudah punya progress lewat SaveSchedule -> 50072 (jalankan ulang RequestSchedule.sql dulu)
   BEGIN TRY EXEC dbo.usp_Request_SaveSchedule @Id = @Req, @Username = @Civil, @ProjectStartDate = '2026-11-02',
        @ActionPlanJson = N'[{"id":0,"name":"Only one","weight":100,"start":"2026-11-02","end":"2026-12-20"}]', @Reason = N'Test';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '5 expect 50072 (has progress)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   ===================================================================== */
GO
/* ---------- end RequestProgress.sql ---------- */
/* ---------- begin RequestActualCost.sql ---------- */
PRINT N'[skema] RequestActualCost.sql';
GO
/* =====================================================================
   RequestActualCost.sql  -  Actual cost bulanan per item (input manual), status biaya dan keseluruhan
                             (T5-2; PRD 3.3 langkah 5, 6.4, BR-18, BR-19, BR-69, BR-70, BR-71, CF-08)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestProgress.sql
             (kolom ScheduleStatus dipakai kolom OverallStatus) dan Unit.sql; lalu jalankan ulang RequestSchedule.sql
             (perubahan estimasi saat In Progress menghitung ulang status biaya).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Aturan (Keputusan 16-11-2026, lihat docs/PRD-log.md):
     - Civil menyimpan SELURUH item satu bulan sekaligus; simpan menimpa item bulan itu (sama dengan upload ulang,
       BR-19). Daftar item kosong = hapus actual bulan itu. Setiap simpan tercatat di riwayat (ACTUAL_COST).
     - Bulan: dari bulan awal Preparation (atau bulan mulai project bila kosong) s.d. bulan berjalan.
     - Status request: IN_PROGRESS atau BAPP_REVIEW.
     - Item (6.4): jenis GOODS/SERVICE, nama, qty > 0, satuan (teks bebas; master Unit hanya saran), harga satuan > 0,
       amount = qty × harga satuan (toleransi pembulatan IDR 1), no. referensi dan keterangan opsional.
     - Status biaya (BR-69): rasio = Σ actual ÷ Σ estimasi s.d. bulan closing terakhir (bulan actual terakhir) × 100.
       Bila bulan actual terakhir sebelum bulan estimasi pertama (biaya masa Preparation), pembanding = estimasi bulan
       pertama. Tanpa actual = ON_TRACK. Ambang dari AppSetting COST_ONTRACK_MAX_PCT (100), COST_ATRISK_MAX_PCT (110).
     - Status keseluruhan (BR-70): kolom terhitung OverallStatus = status terburuk jadwal dan biaya.
     - Lihat detail bulan/item: civil, fat, gm, director, administrator (matriks PRD 5.2); ringkasan status
       untuk semua role yang boleh melihat request (kecuali purchasing-only).
     - Lampiran detail cost per project per bulan (BR-96, Keputusan 18-11-2026): tabel ProjectActualFile (bagian 9-12).
       Simpan manual dengan item wajib punya minimal satu lampiran aktif (file baru dikirim lewat @FilesJson);
       bulan hasil Excel boleh tanpa lampiran (ditandai missing di Details); lampiran terakhir bulan berisi actual
       tidak bisa dihapus. Jenis lampiran ACTUAL_DETAIL (stage COST).
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai (civil)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Migrasi kolom dbo.ProjectRequest (ringkasan biaya + status)
   --------------------------------------------------------------------- */
IF COL_LENGTH(N'dbo.ProjectRequest', N'CostStatus') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        ActualCostTotal   DECIMAL(18, 2) NULL,
        CostRatioPercent  DECIMAL(9, 2)  NULL,
        CostStatus        VARCHAR(20)    NULL
            CONSTRAINT CK_ProjectRequest_CostStatus CHECK (CostStatus IS NULL OR CostStatus IN ('ON_TRACK', 'AT_RISK', 'OVER_BUDGET')),
        CostStatusAt      DATETIME2(3)   NULL,
        LastActualMonth   DATE           NULL;
END
GO

-- Status keseluruhan (BR-70): terburuk antara jadwal dan biaya; NULL bila keduanya belum dihitung
IF COL_LENGTH(N'dbo.ProjectRequest', N'OverallStatus') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD OverallStatus AS
        CAST(CASE WHEN ScheduleStatus = 'DELAY' OR CostStatus = 'OVER_BUDGET'      THEN 'DELAYED'
                  WHEN ScheduleStatus = 'SLIGHT_DELAY' OR CostStatus = 'AT_RISK'   THEN 'AT_RISK'
                  WHEN ScheduleStatus IS NULL AND CostStatus IS NULL               THEN NULL
                  ELSE 'ON_TRACK' END AS VARCHAR(20));
END
GO

/* ---------------------------------------------------------------------
   2. TABLE dbo.ProjectActualMonth  (satu baris per project per bulan; entitas CostActualUpload PRD 6.7)
      AttachmentId: cadangan (lampiran per request); tidak dipakai. File Excel upload pusat (T5-3) -> UploadId.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectActualMonth', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectActualMonth
    (
        Id            INT IDENTITY(1,1) NOT NULL,
        RequestId     INT            NOT NULL,
        PeriodMonth   DATE           NOT NULL,       -- tanggal 1 bulan tersebut
        TotalAmount   DECIMAL(18, 2) NOT NULL,
        ItemCount     INT            NOT NULL,
        Source        VARCHAR(10)    NOT NULL,       -- MANUAL | EXCEL
        AttachmentId  INT            NULL,
        Remarks       NVARCHAR(1000) NULL,
        CreatedAt     DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectActualMonth_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy     NVARCHAR(100)  NOT NULL,
        UpdatedAt     DATETIME2(3)   NULL,
        UpdatedBy     NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectActualMonth PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectActualMonth UNIQUE (RequestId, PeriodMonth),
        CONSTRAINT FK_ProjectActualMonth_Request    FOREIGN KEY (RequestId)    REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_ProjectActualMonth_Attachment FOREIGN KEY (AttachmentId) REFERENCES dbo.RequestAttachment (Id),
        CONSTRAINT CK_ProjectActualMonth_Month  CHECK (DAY(PeriodMonth) = 1),
        CONSTRAINT CK_ProjectActualMonth_Source CHECK (Source IN ('MANUAL', 'EXCEL'))
    );
END
GO

/* ---------------------------------------------------------------------
   2a. TABLE dbo.ActualCostUpload  (T5-3; arsip file Excel actual cost, satu file bisa banyak project/bulan; BR-19)
       Status: PENDING (sudah diupload + dipreview) -> IMPORTED (dikonfirmasi) | CANCELLED.
       RelativePath relatif terhadap FileStorage:RealizationAttachmentsPath (mis. ActualCost\2026\<guid>.xlsx).
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ActualCostUpload', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ActualCostUpload
    (
        Id                INT IDENTITY(1,1) NOT NULL,
        OriginalFileName  NVARCHAR(260)  NOT NULL,
        RelativePath      NVARCHAR(400)  NOT NULL,
        ContentType       VARCHAR(100)   NOT NULL,
        FileSizeBytes     BIGINT         NOT NULL,
        RowTotal          INT            NOT NULL,
        GroupTotal        INT            NOT NULL,       -- jumlah project + bulan
        TotalAmount       DECIMAL(18, 2) NOT NULL,
        Status            VARCHAR(10)    NOT NULL CONSTRAINT DF_ActualCostUpload_Status DEFAULT ('PENDING'),
        CreatedAt         DATETIME2(3)   NOT NULL CONSTRAINT DF_ActualCostUpload_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy         NVARCHAR(100)  NOT NULL,
        ProcessedAt       DATETIME2(3)   NULL,
        ProcessedBy       NVARCHAR(100)  NULL,
        CONSTRAINT PK_ActualCostUpload PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_ActualCostUpload_Status CHECK (Status IN ('PENDING', 'IMPORTED', 'CANCELLED')),
        CONSTRAINT CK_ActualCostUpload_Size   CHECK (FileSizeBytes > 0)
    );
END
GO

-- Bulan actual hasil upload Excel menunjuk file arsipnya
IF COL_LENGTH(N'dbo.ProjectActualMonth', N'UploadId') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectActualMonth ADD
        UploadId INT NULL CONSTRAINT FK_ProjectActualMonth_Upload FOREIGN KEY REFERENCES dbo.ActualCostUpload (Id);
END
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.ProjectActualItem  (detail per item barang/jasa; PRD 6.4)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectActualItem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectActualItem
    (
        Id           INT IDENTITY(1,1) NOT NULL,
        MonthId      INT            NOT NULL,
        LineNumber       INT            NOT NULL,
        ItemType     VARCHAR(10)    NOT NULL,        -- GOODS | SERVICE
        ItemName     NVARCHAR(200)  NOT NULL,
        Qty          DECIMAL(18, 4) NOT NULL,
        Unit         NVARCHAR(30)   NOT NULL,
        UnitPrice    DECIMAL(18, 2) NOT NULL,
        Amount       DECIMAL(18, 2) NOT NULL,
        ReferenceNo  NVARCHAR(100)  NULL,            -- PO / GR / jurnal
        Notes        NVARCHAR(500)  NULL,
        CONSTRAINT PK_ProjectActualItem PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ProjectActualItem_Month FOREIGN KEY (MonthId) REFERENCES dbo.ProjectActualMonth (Id),
        CONSTRAINT CK_ProjectActualItem_Type  CHECK (ItemType IN ('GOODS', 'SERVICE')),
        CONSTRAINT CK_ProjectActualItem_Qty   CHECK (Qty > 0),
        CONSTRAINT CK_ProjectActualItem_Price CHECK (UnitPrice > 0 AND Amount > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ProjectActualItem_Month' AND object_id = OBJECT_ID(N'dbo.ProjectActualItem'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectActualItem_Month ON dbo.ProjectActualItem (MonthId, LineNumber);
END
GO

/* ---------------------------------------------------------------------
   4. dbo.fn_User_CanSeeActualCost(@Username)  -> 1 baris bila boleh melihat detail actual cost (matriks 5.2)
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanSeeActualCost
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    FROM   dbo.fn_User_Roles(@Username) r
    WHERE  r.RoleCode IN (N'civil', N'fat', N'dgo', N'gm', N'director', N'administrator')   -- dgo: 18-11-2026
);
GO

/* ---------------------------------------------------------------------
   5. usp_Request_RefreshCostStatus  (internal; dipanggil saat actual / estimasi disimpan; BR-69, BR-71)
      Tidak membuka transaksi sendiri (ikut transaksi pemanggil).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_RefreshCostStatus
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CoCode VARCHAR(10) = (SELECT r.CoCode FROM dbo.ProjectRequest r WHERE r.Id = @Id);

    DECLARE @Total DECIMAL(18, 2), @LastMonth DATE;
    SELECT  @Total = SUM(m.TotalAmount), @LastMonth = MAX(m.PeriodMonth)
    FROM    dbo.ProjectActualMonth m
    WHERE   m.RequestId = @Id;

    DECLARE @FirstEstMonth DATE = (SELECT MIN(e.PeriodMonth) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = @Id);
    DECLARE @CompareTo DATE = CASE WHEN @FirstEstMonth IS NOT NULL AND (@LastMonth IS NULL OR @LastMonth < @FirstEstMonth)
                                   THEN @FirstEstMonth ELSE @LastMonth END;
    DECLARE @Estimate DECIMAL(18, 2) = (SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e
                                        WHERE e.RequestId = @Id AND e.PeriodMonth <= @CompareTo);

    DECLARE @OnTrackMax DECIMAL(9, 2) = ISNULL((SELECT TOP (1) TRY_CAST(s.SettingValue AS DECIMAL(9, 2)) FROM dbo.AppSetting s
                                                WHERE s.SettingKey = 'COST_ONTRACK_MAX_PCT' AND s.CoCode IN (@CoCode, '*')
                                                ORDER BY CASE WHEN s.CoCode = @CoCode THEN 0 ELSE 1 END), 100);
    DECLARE @AtRiskMax DECIMAL(9, 2)  = ISNULL((SELECT TOP (1) TRY_CAST(s.SettingValue AS DECIMAL(9, 2)) FROM dbo.AppSetting s
                                                WHERE s.SettingKey = 'COST_ATRISK_MAX_PCT' AND s.CoCode IN (@CoCode, '*')
                                                ORDER BY CASE WHEN s.CoCode = @CoCode THEN 0 ELSE 1 END), 110);

    DECLARE @Ratio DECIMAL(9, 2) =
        CASE WHEN @LastMonth IS NULL OR ISNULL(@Estimate, 0) = 0 THEN NULL
             ELSE CAST(ROUND(@Total * 100.0 / @Estimate, 2) AS DECIMAL(9, 2)) END;

    DECLARE @Status VARCHAR(20) =
        CASE WHEN @LastMonth IS NULL                  THEN 'ON_TRACK'        -- belum ada bulan closing
             WHEN ISNULL(@Estimate, 0) = 0           THEN 'OVER_BUDGET'     -- ada actual tanpa estimasi sama sekali
             WHEN @Ratio <= @OnTrackMax              THEN 'ON_TRACK'
             WHEN @Ratio <= @AtRiskMax               THEN 'AT_RISK'
             ELSE 'OVER_BUDGET' END;

    UPDATE dbo.ProjectRequest
    SET    ActualCostTotal = @Total, CostRatioPercent = @Ratio, CostStatus = @Status,
           CostStatusAt = SYSDATETIME(), LastActualMonth = @LastMonth
    WHERE  Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Request_GetActualCost  (Details)
      Result 1: ringkasan (0 baris = tidak ada / di luar lingkup / purchasing-only)
      Result 2: per bulan: estimasi vs actual (hanya bila CanSeeDetail = 1)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetActualCost
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
             THEN 1 ELSE 0 END;
    DECLARE @CanSeeDetail BIT = CASE WHEN @Visible = 1 AND EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username)) THEN 1 ELSE 0 END;

    SELECT  r.Id AS RequestId, r.Status, r.PlanCost, r.ActualCostTotal, r.CostRatioPercent, r.CostStatus, r.CostStatusAt,
            r.LastActualMonth, r.ScheduleStatus, r.OverallStatus,
            DATEFROMPARTS(YEAR(ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)),
                          MONTH(ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)), 1) AS FirstMonth,
            DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1) AS CurrentMonth,
            @CanSeeDetail AS CanSeeDetail
    FROM    dbo.ProjectRequest r
    WHERE   r.Id = @RequestId AND @Visible = 1;

    SELECT  ISNULL(e.PeriodMonth, m.PeriodMonth) AS PeriodMonth,
            ISNULL(e.Amount, 0) AS EstimateAmount,
            ISNULL(m.TotalAmount, 0) AS ActualAmount,
            ISNULL(m.ItemCount, 0) AS ItemCount,
            m.Source, m.UpdatedAt, m.UpdatedBy, m.CreatedAt, m.CreatedBy,
            CAST(CASE WHEN m.Id IS NULL THEN 0 ELSE 1 END AS BIT) AS HasActual,
            -- BR-96: jumlah lampiran detail cost aktif bulan itu (0 + HasActual = missing attachment)
            (SELECT COUNT(*) FROM dbo.ProjectActualFile f
             WHERE f.RequestId = @RequestId AND f.PeriodMonth = ISNULL(e.PeriodMonth, m.PeriodMonth) AND f.IsActive = 1) AS FileCount
    FROM    (SELECT * FROM dbo.ProjectCostEstimate WHERE RequestId = @RequestId) e
            FULL OUTER JOIN (SELECT * FROM dbo.ProjectActualMonth WHERE RequestId = @RequestId) m
                ON m.PeriodMonth = e.PeriodMonth
    WHERE   @CanSeeDetail = 1
    ORDER BY ISNULL(e.PeriodMonth, m.PeriodMonth);
END
GO

/* ---------------------------------------------------------------------
   7. usp_Request_GetActualMonth  (form / detail satu bulan; hanya role yang boleh melihat detail)
      Result 1: header bulan (0 baris bila tidak berhak) · Result 2: item
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetActualMonth
    @RequestId INT,
    @Month     DATE,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PeriodMonth DATE = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
    DECLARE @CanSee BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
              AND EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username))
             THEN 1 ELSE 0 END;

    DECLARE @MonthId INT = (SELECT m.Id FROM dbo.ProjectActualMonth m WHERE m.RequestId = @RequestId AND m.PeriodMonth = @PeriodMonth);

    SELECT  @PeriodMonth AS PeriodMonth,
            (SELECT e.Amount FROM dbo.ProjectCostEstimate e WHERE e.RequestId = @RequestId AND e.PeriodMonth = @PeriodMonth) AS EstimateAmount,
            m.TotalAmount, m.ItemCount, m.Source, m.AttachmentId, m.UploadId, m.Remarks, m.CreatedAt, m.CreatedBy, m.UpdatedAt, m.UpdatedBy,
            CAST(CASE WHEN @MonthId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsSaved
    FROM    (SELECT 1 AS x) d
            LEFT JOIN dbo.ProjectActualMonth m ON m.Id = @MonthId
    WHERE   @CanSee = 1;

    SELECT  i.Id, i.LineNumber, i.ItemType, i.ItemName, i.Qty, i.Unit, i.UnitPrice, i.Amount, i.ReferenceNo, i.Notes
    FROM    dbo.ProjectActualItem i
    WHERE   i.MonthId = @MonthId AND @CanSee = 1
    ORDER BY i.LineNumber, i.Id;
END
GO

/* ---------------------------------------------------------------------
   8. usp_Request_SaveActualMonth  (civil; IN_PROGRESS / BAPP_REVIEW; ganti seluruh item satu bulan)
      @ItemsJson: [{"type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000,
                    "ref":"PO-123","notes":null}, ...]   '[]' = hapus actual bulan itu
      @Source   : MANUAL (T5-2) | EXCEL (T5-3, dengan @UploadId; dipanggil usp_ActualUpload_Import)
      @FilesJson: lampiran detail cost baru (BR-96) yang sudah disimpan aplikasi ke storage:
                  [{"name":"rekap.pdf","path":"2026\\15\\<guid>.pdf","type":"application/pdf","size":12345}, ...]
                  MANUAL dengan item: wajib minimal satu lampiran aktif bulan itu (lama + baru).
      Hasil: SELECT ringkasan biaya terbaru.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveActualMonth
    @Id            INT,
    @Username      NVARCHAR(100),
    @Month         DATE,
    @ItemsJson     NVARCHAR(MAX),
    @Remarks       NVARCHAR(MAX) = NULL,
    @Source        VARCHAR(10)   = 'MANUAL',
    @AttachmentId  INT           = NULL,
    @UploadId      INT           = NULL,
    @FilesJson     NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');
    SET @Source  = UPPER(LTRIM(RTRIM(ISNULL(@Source, 'MANUAL'))));
    IF ISJSON(ISNULL(@FilesJson, N'[]')) = 0
        THROW 50072, N'Attachment data is invalid.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can enter actual cost.', 1;
    IF @Month IS NULL
        THROW 50072, N'Month is required.', 1;
    IF @Source NOT IN ('MANUAL', 'EXCEL')
        THROW 50072, N'Source is invalid.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;
    IF ISJSON(ISNULL(@ItemsJson, N'[]')) = 0
        THROW 50072, N'Actual cost data is invalid.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);
    DECLARE @PeriodMonth DATE = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
    DECLARE @Msg NVARCHAR(2048);

    DECLARE @Items TABLE
    (
        Seq         INT            NOT NULL PRIMARY KEY,
        ItemType    VARCHAR(20)    NULL,
        ItemName    NVARCHAR(400)  NULL,
        Qty         DECIMAL(18, 4) NULL,
        Unit        NVARCHAR(60)   NULL,
        UnitPrice   DECIMAL(18, 2) NULL,
        Amount      DECIMAL(18, 2) NULL,
        ReferenceNo NVARCHAR(200)  NULL,
        Notes       NVARCHAR(1000) NULL
    );

    INSERT INTO @Items (Seq, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo, Notes)
    SELECT  CAST(j.[key] AS INT) + 1,
            UPPER(LTRIM(RTRIM(x.[type]))), NULLIF(LTRIM(RTRIM(x.[name])), N''), x.qty, NULLIF(LTRIM(RTRIM(x.unit)), N''),
            x.price, x.amount, NULLIF(LTRIM(RTRIM(x.[ref])), N''), NULLIF(LTRIM(RTRIM(x.notes)), N'')
    FROM    OPENJSON(ISNULL(@ItemsJson, N'[]')) j
            CROSS APPLY OPENJSON(j.[value])
            WITH ([type] VARCHAR(20) '$.type', [name] NVARCHAR(400) '$.name', qty DECIMAL(18, 4) '$.qty',
                  unit NVARCHAR(60) '$.unit', price DECIMAL(18, 2) '$.price', amount DECIMAL(18, 2) '$.amount',
                  [ref] NVARCHAR(200) '$.ref', notes NVARCHAR(1000) '$.notes') x;

    IF (SELECT COUNT(*) FROM @Items) > 500
        THROW 50072, N'At most 500 items per month are allowed.', 1;

    SELECT TOP (1) @Msg = N'Item row ' + CAST(i.Seq AS NVARCHAR(10)) + N': ' +
           CASE WHEN ISNULL(i.ItemType, '') NOT IN ('GOODS', 'SERVICE') THEN N'type must be Goods or Service.'
                WHEN i.ItemName IS NULL                          THEN N'item name is required.'
                WHEN LEN(i.ItemName) > 200                       THEN N'item name must be at most 200 characters.'
                WHEN i.Qty IS NULL OR i.Qty <= 0                 THEN N'quantity must be greater than 0.'
                WHEN i.Unit IS NULL                              THEN N'unit is required.'
                WHEN LEN(i.Unit) > 30                            THEN N'unit must be at most 30 characters.'
                WHEN i.UnitPrice IS NULL OR i.UnitPrice <= 0     THEN N'unit price must be greater than 0.'
                WHEN i.Amount IS NULL OR i.Amount <= 0           THEN N'amount must be greater than 0.'
                WHEN ABS(i.Amount - ROUND(i.Qty * i.UnitPrice, 2)) > 1
                     THEN N'amount must equal quantity × unit price (' + FORMAT(ROUND(i.Qty * i.UnitPrice, 2), N'#,0.##', 'en-US') + N').'
                WHEN LEN(i.ReferenceNo) > 100                    THEN N'reference number must be at most 100 characters.'
                ELSE N'notes must be at most 500 characters.' END
    FROM   @Items i
    WHERE  ISNULL(i.ItemType, '') NOT IN ('GOODS', 'SERVICE')
       OR  i.ItemName IS NULL OR LEN(i.ItemName) > 200
       OR  i.Qty IS NULL OR i.Qty <= 0
       OR  i.Unit IS NULL OR LEN(i.Unit) > 30
       OR  i.UnitPrice IS NULL OR i.UnitPrice <= 0
       OR  i.Amount IS NULL OR i.Amount <= 0
       OR  ABS(i.Amount - ROUND(i.Qty * i.UnitPrice, 2)) > 1
       OR  LEN(i.ReferenceNo) > 100 OR LEN(i.Notes) > 500
    ORDER BY i.Seq;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    DECLARE @Status VARCHAR(20), @FirstDate DATE;

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @FirstDate = ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status NOT IN ('IN_PROGRESS', 'BAPP_REVIEW')
        THROW 50074, N'Actual cost can only be entered while the project is in progress or in BAPP review.', 1;
    IF @FirstDate IS NOT NULL AND @PeriodMonth < DATEFROMPARTS(YEAR(@FirstDate), MONTH(@FirstDate), 1)
    BEGIN
        SET @Msg = N'The month is before the preparation start (' + FORMAT(@FirstDate, N'MMM yyyy', 'en-US') + N').';
        THROW 50072, @Msg, 1;
    END
    IF @PeriodMonth > DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1)
        THROW 50072, N'Actual cost cannot be entered for a future month.', 1;
    IF @AttachmentId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a WHERE a.Id = @AttachmentId AND a.RequestId = @Id)
        THROW 50072, N'The upload file is invalid.', 1;
    IF @UploadId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.ActualCostUpload u WHERE u.Id = @UploadId AND u.Status = 'PENDING')
        THROW 50072, N'The upload file is invalid or already processed.', 1;
    IF @Source = 'EXCEL' AND @UploadId IS NULL
        THROW 50072, N'The upload file is required for Excel source.', 1;

    DECLARE @MonthId INT = (SELECT m.Id FROM dbo.ProjectActualMonth m WITH (UPDLOCK, HOLDLOCK)
                            WHERE m.RequestId = @Id AND m.PeriodMonth = @PeriodMonth);
    DECLARE @Count INT = (SELECT COUNT(*) FROM @Items);
    DECLARE @Total DECIMAL(18, 2) = ISNULL((SELECT SUM(Amount) FROM @Items), 0);

    IF @Count = 0 AND @MonthId IS NULL
        THROW 50072, N'Please add at least one item.', 1;

    -- BR-96: lampiran detail cost baru (file sudah di storage) + wajib minimal satu untuk simpan manual
    DECLARE @Files TABLE (Seq INT PRIMARY KEY, FileName NVARCHAR(260), RelPath NVARCHAR(400), ContentType VARCHAR(100), Size BIGINT);
    INSERT INTO @Files (Seq, FileName, RelPath, ContentType, Size)
    SELECT  CAST(j.[key] AS INT) + 1, NULLIF(LTRIM(RTRIM(x.[name])), N''), NULLIF(LTRIM(RTRIM(x.[path])), N''), x.[type], x.size
    FROM    OPENJSON(ISNULL(@FilesJson, N'[]')) j
            CROSS APPLY OPENJSON(j.[value])
            WITH ([name] NVARCHAR(260) '$.name', [path] NVARCHAR(400) '$.path', [type] VARCHAR(100) '$.type', size BIGINT '$.size') x;

    IF EXISTS (SELECT 1 FROM @Files)
    BEGIN
        DECLARE @FileTypeId INT, @FileExtList VARCHAR(200), @FileMaxMB INT;
        SELECT  @FileTypeId = t.Id, @FileExtList = t.AllowedExtensions, @FileMaxMB = t.MaxSizeMB
        FROM    dbo.AttachmentType t WHERE t.Code = 'ACTUAL_DETAIL' AND t.IsActive = 1;

        IF @FileTypeId IS NULL
            THROW 50072, N'The cost detail attachment type is not configured. Please contact the administrator.', 1;

        SELECT TOP (1) @Msg = N'Attachment "' + ISNULL(f.FileName, N'?') + N'": '
               + CASE WHEN f.FileName IS NULL OR f.RelPath IS NULL OR ISNULL(f.Size, 0) <= 0 THEN N'file is invalid.'
                      WHEN f.Size > CAST(@FileMaxMB AS BIGINT) * 1048576 THEN N'file size exceeds the maximum.'
                      ELSE N'file type is not allowed.' END
        FROM   @Files f
        WHERE  f.FileName IS NULL OR f.RelPath IS NULL OR ISNULL(f.Size, 0) <= 0
           OR  f.Size > CAST(@FileMaxMB AS BIGINT) * 1048576
           OR  CHARINDEX('.', f.FileName) = 0
           OR  CHARINDEX(',' + LOWER(RIGHT(f.FileName, CHARINDEX('.', REVERSE(f.FileName)) - 1)) + ',', ',' + @FileExtList + ',') = 0
        ORDER BY f.Seq;

        IF @Msg IS NOT NULL
            THROW 50072, @Msg, 1;

        INSERT INTO dbo.ProjectActualFile
            (RequestId, PeriodMonth, AttachmentTypeId, OriginalFileName, RelativePath, ContentType, FileSizeBytes, CreatedAt, CreatedBy)
        SELECT  @Id, @PeriodMonth, @FileTypeId, f.FileName, f.RelPath, ISNULL(NULLIF(f.ContentType, ''), 'application/octet-stream'),
                f.Size, @Now, @Username
        FROM    @Files f;
    END

    IF @Source = 'MANUAL' AND @Count > 0
       AND NOT EXISTS (SELECT 1 FROM dbo.ProjectActualFile f
                       WHERE f.RequestId = @Id AND f.PeriodMonth = @PeriodMonth AND f.IsActive = 1)
        THROW 50072, N'Please attach the cost detail document (e.g. PO / invoice / receipt summary) for this month.', 1;

    IF @MonthId IS NOT NULL
        DELETE FROM dbo.ProjectActualItem WHERE MonthId = @MonthId;

    IF @Count = 0
    BEGIN
        -- Hapus actual bulan ini
        DELETE FROM dbo.ProjectActualMonth WHERE Id = @MonthId;
    END
    ELSE
    BEGIN
        IF @MonthId IS NULL
        BEGIN
            INSERT INTO dbo.ProjectActualMonth
                (RequestId, PeriodMonth, TotalAmount, ItemCount, Source, AttachmentId, UploadId, Remarks, CreatedAt, CreatedBy)
            VALUES (@Id, @PeriodMonth, @Total, @Count, @Source, @AttachmentId, @UploadId, @Remarks, @Now, @Username);
            SET @MonthId = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
            UPDATE dbo.ProjectActualMonth
            SET    TotalAmount = @Total, ItemCount = @Count, Source = @Source, AttachmentId = @AttachmentId,
                   UploadId = @UploadId, Remarks = @Remarks, UpdatedAt = @Now, UpdatedBy = @Username
            WHERE  Id = @MonthId;

        INSERT INTO dbo.ProjectActualItem (MonthId, LineNumber, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo, Notes)
        SELECT @MonthId, i.Seq, i.ItemType, i.ItemName, i.Qty, i.Unit, i.UnitPrice, i.Amount, i.ReferenceNo, i.Notes
        FROM   @Items i;
    END

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'ACTUAL_COST', @Status, @Status,
            LEFT(N'Actual cost ' + FORMAT(@PeriodMonth, N'MMM yyyy', 'en-US')
                 + CASE WHEN @Count = 0 THEN N' removed'
                        ELSE N': IDR ' + FORMAT(@Total, N'#,0.##', 'en-US') + N' (' + CAST(@Count AS NVARCHAR(10)) + N' items, '
                             + LOWER(@Source) + N')' END
                 + ISNULL(N' · ' + @Remarks, N''), 1000),
            @Username, @Now);

    UPDATE dbo.ProjectRequest SET UpdatedAt = @Now, UpdatedBy = @Username WHERE Id = @Id;

    EXEC dbo.usp_Request_RefreshCostStatus @Id = @Id, @Username = @Username;

    COMMIT TRANSACTION;

    SELECT  r.ActualCostTotal, r.CostRatioPercent, r.CostStatus, r.ScheduleStatus, r.OverallStatus, r.LastActualMonth
    FROM    dbo.ProjectRequest r
    WHERE   r.Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   9. Lampiran detail cost per bulan (BR-96, Keputusan 18-11-2026)
      Jenis lampiran ACTUAL_DETAIL (stage COST) untuk aturan file; disimpan di tabel sendiri (kunci RequestId +
      PeriodMonth) agar hak lihat mengikuti detail actual cost (fn_User_CanSeeActualCost).
   --------------------------------------------------------------------- */
MERGE dbo.AttachmentType AS t
USING (VALUES ('ACTUAL_DETAIL', N'Actual Cost Detail', 'COST', 'pdf,xlsx,jpg,png', 20)) AS s (Code, Name, Stage, AllowedExtensions, MaxSizeMB)
   ON t.Code = s.Code
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, CreatedBy)
    VALUES (s.Code, s.Name, s.Stage, s.AllowedExtensions, s.MaxSizeMB, 0, 0, 0, N'seed');
GO

IF OBJECT_ID(N'dbo.ProjectActualFile', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectActualFile
    (
        Id                INT IDENTITY(1,1) NOT NULL,
        RequestId         INT            NOT NULL,
        PeriodMonth       DATE           NOT NULL,       -- tanggal 1 bulan tersebut
        AttachmentTypeId  INT            NOT NULL,
        OriginalFileName  NVARCHAR(260)  NOT NULL,
        RelativePath      NVARCHAR(400)  NOT NULL,       -- relatif terhadap FileStorage:RealizationAttachmentsPath
        ContentType       VARCHAR(100)   NOT NULL,
        FileSizeBytes     BIGINT         NOT NULL,
        IsActive          BIT            NOT NULL CONSTRAINT DF_ProjectActualFile_IsActive DEFAULT (1),
        CreatedAt         DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectActualFile_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy         NVARCHAR(100)  NOT NULL,
        UpdatedAt         DATETIME2(3)   NULL,
        UpdatedBy         NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectActualFile PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ProjectActualFile_Request FOREIGN KEY (RequestId)        REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_ProjectActualFile_Type    FOREIGN KEY (AttachmentTypeId) REFERENCES dbo.AttachmentType (Id),
        CONSTRAINT CK_ProjectActualFile_Month   CHECK (DAY(PeriodMonth) = 1),
        CONSTRAINT CK_ProjectActualFile_Size    CHECK (FileSizeBytes > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ProjectActualFile_Month' AND object_id = OBJECT_ID(N'dbo.ProjectActualFile'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectActualFile_Month ON dbo.ProjectActualFile (RequestId, PeriodMonth, IsActive);
END
GO

/* ---------------------------------------------------------------------
   10. usp_ActualFile_List  (lampiran aktif satu bulan; @Month NULL = semua bulan; hak lihat detail actual cost)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualFile_List
    @RequestId INT,
    @Month     DATE = NULL,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PeriodMonth DATE = CASE WHEN @Month IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1) END;

    SELECT  f.Id, f.RequestId, f.PeriodMonth, f.OriginalFileName, f.ContentType, f.FileSizeBytes, f.CreatedAt, f.CreatedBy,
            e.FullName AS CreatedByName
    FROM    dbo.ProjectActualFile f
            JOIN dbo.ProjectRequest r         ON r.Id = f.RequestId
            LEFT JOIN home..users u           ON u.Username = f.CreatedBy
            LEFT JOIN home..app_employees e   ON e.EmployeeCode = u.EmployeeCode
    WHERE   f.RequestId = @RequestId AND f.IsActive = 1
      AND   (@PeriodMonth IS NULL OR f.PeriodMonth = @PeriodMonth)
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) a WHERE a.DepartmentID = r.DepartmentID)
      AND   NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username))
    ORDER BY f.PeriodMonth, f.CreatedAt, f.Id;
END
GO

/* ---------------------------------------------------------------------
   11. usp_ActualFile_Insert  (civil; IN_PROGRESS / BAPP_REVIEW; tambah lampiran ke bulan, mis. bulan dari Excel)
       File sudah disimpan aplikasi (aplikasi menghapus file bila SP gagal). Hasil: SELECT Id.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualFile_Insert
    @RequestId         INT,
    @Month             DATE,
    @Username          NVARCHAR(100),
    @OriginalFileName  NVARCHAR(260),
    @RelativePath      NVARCHAR(400),
    @ContentType       VARCHAR(100),
    @FileSizeBytes     BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @OriginalFileName = NULLIF(LTRIM(RTRIM(@OriginalFileName)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can attach cost detail documents.', 1;
    IF @Month IS NULL
        THROW 50072, N'Month is required.', 1;
    IF @OriginalFileName IS NULL OR NULLIF(@RelativePath, N'') IS NULL OR ISNULL(@FileSizeBytes, 0) <= 0
        THROW 50072, N'Please choose a file.', 1;

    DECLARE @PeriodMonth DATE = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Status VARCHAR(20), @FirstDate DATE;

    SELECT  @Status = r.Status, @FirstDate = ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)
    FROM    dbo.ProjectRequest r
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status NOT IN ('IN_PROGRESS', 'BAPP_REVIEW')
        THROW 50074, N'Cost detail documents can only be changed while the project is in progress or in BAPP review.', 1;
    IF (@FirstDate IS NOT NULL AND @PeriodMonth < DATEFROMPARTS(YEAR(@FirstDate), MONTH(@FirstDate), 1))
       OR @PeriodMonth > DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1)
        THROW 50072, N'The month is outside the actual cost period.', 1;

    DECLARE @TypeId INT, @Ext VARCHAR(200), @MaxMB INT, @FileExt VARCHAR(20);
    SELECT  @TypeId = t.Id, @Ext = t.AllowedExtensions, @MaxMB = t.MaxSizeMB
    FROM    dbo.AttachmentType t WHERE t.Code = 'ACTUAL_DETAIL' AND t.IsActive = 1;

    IF @TypeId IS NULL
        THROW 50072, N'The cost detail attachment type is not configured. Please contact the administrator.', 1;

    SET @FileExt = CASE WHEN CHARINDEX('.', @OriginalFileName) = 0 THEN ''
                        ELSE LOWER(RIGHT(@OriginalFileName, CHARINDEX('.', REVERSE(@OriginalFileName)) - 1)) END;
    IF @FileExt = '' OR CHARINDEX(',' + @FileExt + ',', ',' + @Ext + ',') = 0
        THROW 50072, N'File type is not allowed for the cost detail document.', 1;
    IF @FileSizeBytes > CAST(@MaxMB AS BIGINT) * 1048576
        THROW 50072, N'File size exceeds the maximum for the cost detail document.', 1;

    INSERT INTO dbo.ProjectActualFile
        (RequestId, PeriodMonth, AttachmentTypeId, OriginalFileName, RelativePath, ContentType, FileSizeBytes, CreatedBy)
    VALUES (@RequestId, @PeriodMonth, @TypeId, @OriginalFileName, @RelativePath,
            ISNULL(NULLIF(@ContentType, ''), 'application/octet-stream'), @FileSizeBytes, @Username);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS Id;
END
GO

/* ---------------------------------------------------------------------
   12. usp_ActualFile_Deactivate  (civil; IN_PROGRESS / BAPP_REVIEW; lampiran terakhir bulan berisi actual tidak boleh)
       usp_ActualFile_GetById      (download; hak lihat detail actual cost)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualFile_Deactivate
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can remove cost detail documents.', 1;

    DECLARE @RequestId INT, @PeriodMonth DATE, @Status VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT  @RequestId = f.RequestId, @PeriodMonth = f.PeriodMonth, @Status = r.Status
    FROM    dbo.ProjectActualFile f WITH (UPDLOCK, ROWLOCK)
            JOIN dbo.ProjectRequest r ON r.Id = f.RequestId
    WHERE   f.Id = @Id AND f.IsActive = 1
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) a WHERE a.DepartmentID = r.DepartmentID);

    IF @RequestId IS NULL
        THROW 50073, N'Attachment not found.', 1;
    IF @Status NOT IN ('IN_PROGRESS', 'BAPP_REVIEW')
        THROW 50074, N'Cost detail documents can only be changed while the project is in progress or in BAPP review.', 1;
    IF EXISTS (SELECT 1 FROM dbo.ProjectActualMonth m WHERE m.RequestId = @RequestId AND m.PeriodMonth = @PeriodMonth)
       AND NOT EXISTS (SELECT 1 FROM dbo.ProjectActualFile f
                       WHERE f.RequestId = @RequestId AND f.PeriodMonth = @PeriodMonth AND f.IsActive = 1 AND f.Id <> @Id)
        THROW 50074, N'This is the last cost detail document for the month. Upload another one before removing it.', 1;

    UPDATE dbo.ProjectActualFile
    SET    IsActive = 0, UpdatedAt = SYSDATETIME(), UpdatedBy = @Username
    WHERE  Id = @Id;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_ActualFile_GetById
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  f.Id, f.RequestId, f.PeriodMonth, f.OriginalFileName, f.RelativePath, f.ContentType, f.FileSizeBytes
    FROM    dbo.ProjectActualFile f
            JOIN dbo.ProjectRequest r ON r.Id = f.RequestId
    WHERE   f.Id = @Id AND f.IsActive = 1
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) a WHERE a.DepartmentID = r.DepartmentID)
      AND   NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username));
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: Unit.sql, RequestActualCost.sql, lalu RequestSchedule.sql dijalankan ulang.
   Contoh memakai request IN_PROGRESS hasil test T4-2/T5-1: PlanCost 10.000.000, estimasi Nov 2026 4.000.000 (atau
   3.000.000 setelah test 7 T4-2) dan Des 2026 sisanya; Preparation mulai Nov 2026. Sesuaikan angka.

   DECLARE @Req INT = 1008, @Civil NVARCHAR(100) = N'users1', @Other NVARCHAR(100) = N'hdahlia';
   DECLARE @J NVARCHAR(MAX);

   -- 0) BR-96: simpan manual tanpa lampiran -> 50072 "Please attach the cost detail document";
   --    dengan lampiran (path dummy) -> tersimpan, usp_ActualFile_List 1 baris; hapus lampiran terakhir -> 50074
   --SET @J = N'[{"type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000}]';
   --EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = @J,
   --     @FilesJson = N'[{"name":"rekap.pdf","path":"2026\\1008\\test.pdf","type":"application/pdf","size":1000}]';
   --EXEC dbo.usp_ActualFile_List @RequestId = @Req, @Month = '2026-11-01', @Username = @Civil;

   -- 1) Bukan civil -> 50075; bulan depan -> 50072; amount tidak sama qty x harga -> 50072; jenis salah -> 50072
   BEGIN TRY EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Other, @Month = '2026-11-01', @ItemsJson = N'[]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-12-01', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (future month)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":600000}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (amount)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"type":"OTHER","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1d expect 50072 (type)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Nov 2026: 2 item, total 3.500.000 vs estimasi Nov (mis. 3.000.000) -> rasio 116.67 -> OVER_BUDGET
   SET @J = N'[{"type":"GOODS","name":"Cement","qty":20,"unit":"sak","price":75000,"amount":1500000,"ref":"PO-001"},'
          + N'{"type":"SERVICE","name":"Labor","qty":1,"unit":"ls","price":2000000,"amount":2000000}]';
   EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-15', @ItemsJson = @J, @Remarks = N'November closing';

   -- 3) Simpan ulang Nov (menimpa): 1 item 3.200.000 -> rasio 106.67 -> AT_RISK; OverallStatus ikut (terburuk jadwal/biaya)
   SET @J = N'[{"type":"SERVICE","name":"Labor","qty":1,"unit":"ls","price":3200000,"amount":3200000}]';
   EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = @J;
   EXEC dbo.usp_Request_GetActualCost  @RequestId = @Req, @Username = @Civil;
   EXEC dbo.usp_Request_GetActualMonth @RequestId = @Req, @Month = '2026-11-01', @Username = @Civil;

   -- 4) User tanpa hak detail (mis. adm/kabag departemen itu): ringkasan ada, result 2 kosong
   EXEC dbo.usp_Request_GetActualCost @RequestId = @Req, @Username = N'<user adm/kabag departemen request>';

   -- 5) Hapus actual Nov ('[]') -> CostStatus ON_TRACK, LastActualMonth NULL; riwayat ACTUAL_COST "removed"
   EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = N'[]';
   SELECT TOP (3) Action, Remarks, ActionAt FROM dbo.ApprovalHistory WHERE RequestId = @Req ORDER BY Id DESC;

   -- 6) Master Unit untuk saran satuan
   EXEC dbo.usp_Unit_GetActive;
   ===================================================================== */
GO
/* ---------- end RequestActualCost.sql ---------- */
/* ---------- begin RequestActualUpload.sql ---------- */
PRINT N'[skema] RequestActualUpload.sql';
GO
/* =====================================================================
   RequestActualUpload.sql  -  Upload actual cost via template Excel (T5-3; PRD 6.4, BR-18, BR-19, BR-67)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestActualCost.sql
             (jalankan ulang: tabel ActualCostUpload, kolom ProjectActualMonth.UploadId, parameter @UploadId).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Alur (Keputusan 16-11-2026, lihat docs/PRD-log.md):
     1. Civil mengupload SATU file untuk banyak project/bulan di halaman pusat (Cost Management > Actual Cost Upload).
        Aplikasi (ClosedXML) membaca baris -> JSON -> usp_ActualUpload_Validate (tanpa menulis data).
     2. Ada error di baris mana pun -> tidak ada yang disimpan (all or nothing); daftar error + nomor baris ditampilkan.
     3. Valid -> file disimpan ke arsip + baris ActualCostUpload status PENDING (usp_ActualUpload_Create),
        preview per project + bulan (item, total, bulan yang akan ditimpa).
     4. Civil konfirmasi -> usp_ActualUpload_Import: validasi ulang, lalu per project + bulan memanggil
        usp_Request_SaveActualMonth (Source EXCEL, menimpa bulan itu, BR-19), status IMPORTED. Satu transaksi.
        Batal -> usp_ActualUpload_Cancel (CANCELLED; file tetap diarsipkan).
   Kolom template (6.4): Request No · Month (yyyy-MM) · Type (Goods/Service) · Item name · Qty · Unit · Unit price ·
                         Amount · Reference no. · Notes.  Request No = nomor TERKINI.
   Error   : 50072 = Input tidak valid / file berubah / sudah diproses
             50073 = Upload tidak ditemukan
             50075 = Role user tidak sesuai (civil)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_ActualUpload_CheckRows  (internal)
      Memeriksa tabel sementara #UploadRows milik pemanggil; mengisi RequestId dan Error per baris.
      #UploadRows: RowNo, RequestNo, PeriodMonth, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo,
                   Notes, RequestId, Error.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_CheckRows
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @CurrentMonth DATE = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1);

    -- Request (nomor terkini, dalam lingkup user)
    UPDATE u
    SET    u.RequestId = r.Id
    FROM   #UploadRows u
           JOIN dbo.ProjectRequest r ON r.RequestNo = u.RequestNo
    WHERE  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    UPDATE u
    SET    u.Error = CASE
             WHEN u.RequestNo IS NULL THEN N'Request No is required.'
             WHEN u.RequestId IS NULL AND EXISTS (SELECT 1 FROM dbo.RequestNoHistory h WHERE h.RequestNo = u.RequestNo)
                  THEN N'Request No ' + u.RequestNo + N' is an old number; use the current number '
                       + ISNULL((SELECT TOP (1) r.RequestNo FROM dbo.RequestNoHistory h JOIN dbo.ProjectRequest r ON r.Id = h.RequestId
                                 WHERE h.RequestNo = u.RequestNo), N'') + N'.'
             WHEN u.RequestId IS NULL THEN N'Request No ' + u.RequestNo + N' was not found.'
             WHEN r.Status NOT IN ('IN_PROGRESS', 'BAPP_REVIEW')
                  THEN N'Request ' + u.RequestNo + N' is not in progress or BAPP review.'
             WHEN u.PeriodMonth IS NULL THEN N'Month is required (yyyy-MM).'
             WHEN u.PeriodMonth > @CurrentMonth THEN N'Month cannot be in the future.'
             WHEN ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate) IS NOT NULL
                  AND u.PeriodMonth < DATEFROMPARTS(YEAR(ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)),
                                                    MONTH(ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)), 1)
                  THEN N'Month is before the preparation start of ' + u.RequestNo + N'.'
             WHEN ISNULL(u.ItemType, '') NOT IN ('GOODS', 'SERVICE') THEN N'Type must be Goods or Service.'
             WHEN u.ItemName IS NULL THEN N'Item name is required.'
             WHEN LEN(u.ItemName) > 200 THEN N'Item name must be at most 200 characters.'
             WHEN u.Qty IS NULL OR u.Qty <= 0 THEN N'Qty must be greater than 0.'
             WHEN u.Unit IS NULL THEN N'Unit is required.'
             WHEN LEN(u.Unit) > 30 THEN N'Unit must be at most 30 characters.'
             WHEN u.UnitPrice IS NULL OR u.UnitPrice <= 0 THEN N'Unit price must be greater than 0.'
             WHEN u.Amount IS NULL OR u.Amount <= 0 THEN N'Amount must be greater than 0.'
             WHEN ABS(u.Amount - ROUND(u.Qty * u.UnitPrice, 2)) > 1
                  THEN N'Amount must equal Qty × Unit price (' + FORMAT(ROUND(u.Qty * u.UnitPrice, 2), N'#,0.##', 'en-US') + N').'
             WHEN LEN(u.ReferenceNo) > 100 THEN N'Reference no. must be at most 100 characters.'
             WHEN LEN(u.Notes) > 500 THEN N'Notes must be at most 500 characters.'
             ELSE u.Error END
    FROM   #UploadRows u
           LEFT JOIN dbo.ProjectRequest r ON r.Id = u.RequestId;

    -- Batas item per project + bulan (sama dengan input manual)
    UPDATE u
    SET    u.Error = N'More than 500 items for ' + u.RequestNo + N' in ' + FORMAT(u.PeriodMonth, N'MMM yyyy', 'en-US') + N'.'
    FROM   #UploadRows u
    WHERE  u.Error IS NULL
      AND  (SELECT COUNT(*) FROM #UploadRows x WHERE x.RequestId = u.RequestId AND x.PeriodMonth = u.PeriodMonth) > 500;
END
GO

/* ---------------------------------------------------------------------
   2. usp_ActualUpload_Validate  (preview; tidak menulis data)
      @RowsJson: [{"row":2,"requestNo":"PM-CPX-11-26-002","month":"2026-11-01","type":"GOODS","name":"Cement",
                   "qty":10,"unit":"sak","price":65000,"amount":650000,"ref":"PO-1","notes":null}, ...]
      Result 1: error (RowNo, Message) · Result 2: ringkasan per project + bulan (hanya bila tanpa error).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_Validate
    @Username  NVARCHAR(100),
    @RowsJson  NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can upload actual cost.', 1;
    IF ISJSON(ISNULL(@RowsJson, N'[]')) = 0
        THROW 50072, N'Upload data is invalid.', 1;

    CREATE TABLE #UploadRows
    (
        RowNo        INT            NOT NULL PRIMARY KEY,
        RequestNo    VARCHAR(40)    NULL,
        PeriodMonth  DATE           NULL,
        ItemType     VARCHAR(20)    NULL,
        ItemName     NVARCHAR(400)  NULL,
        Qty          DECIMAL(18, 4) NULL,
        Unit         NVARCHAR(60)   NULL,
        UnitPrice    DECIMAL(18, 2) NULL,
        Amount       DECIMAL(18, 2) NULL,
        ReferenceNo  NVARCHAR(200)  NULL,
        Notes        NVARCHAR(1000) NULL,
        RequestId    INT            NULL,
        Error        NVARCHAR(500)  NULL
    );

    INSERT INTO #UploadRows (RowNo, RequestNo, PeriodMonth, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo, Notes)
    SELECT  x.[row], NULLIF(UPPER(LTRIM(RTRIM(x.requestNo))), ''),
            CASE WHEN x.[month] IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(x.[month]), MONTH(x.[month]), 1) END,
            UPPER(LTRIM(RTRIM(x.[type]))), NULLIF(LTRIM(RTRIM(x.[name])), N''), x.qty, NULLIF(LTRIM(RTRIM(x.unit)), N''),
            x.price, x.amount, NULLIF(LTRIM(RTRIM(x.[ref])), N''), NULLIF(LTRIM(RTRIM(x.notes)), N'')
    FROM    OPENJSON(ISNULL(@RowsJson, N'[]'))
            WITH ([row] INT '$.row', requestNo VARCHAR(40) '$.requestNo', [month] DATE '$.month', [type] VARCHAR(20) '$.type',
                  [name] NVARCHAR(400) '$.name', qty DECIMAL(18, 4) '$.qty', unit NVARCHAR(60) '$.unit',
                  price DECIMAL(18, 2) '$.price', amount DECIMAL(18, 2) '$.amount', [ref] NVARCHAR(200) '$.ref',
                  notes NVARCHAR(1000) '$.notes') x;

    EXEC dbo.usp_ActualUpload_CheckRows @Username = @Username;

    SELECT RowNo, Error AS Message FROM #UploadRows WHERE Error IS NOT NULL ORDER BY RowNo;

    SELECT  g.RequestId, r.RequestNo, r.Title, r.Status, r.CoCode, g.PeriodMonth, g.ItemCount, g.TotalAmount,
            m.TotalAmount AS ExistingAmount, m.Source AS ExistingSource,
            CAST(CASE WHEN m.Id IS NULL THEN 0 ELSE 1 END AS BIT) AS WillReplace,
            e.Amount AS EstimateAmount
    FROM    (SELECT RequestId, PeriodMonth, COUNT(*) AS ItemCount, SUM(Amount) AS TotalAmount
             FROM #UploadRows GROUP BY RequestId, PeriodMonth) g
            JOIN dbo.ProjectRequest r ON r.Id = g.RequestId
            LEFT JOIN dbo.ProjectActualMonth m ON m.RequestId = g.RequestId AND m.PeriodMonth = g.PeriodMonth
            LEFT JOIN dbo.ProjectCostEstimate e ON e.RequestId = g.RequestId AND e.PeriodMonth = g.PeriodMonth
    WHERE   NOT EXISTS (SELECT 1 FROM #UploadRows WHERE Error IS NOT NULL)
    ORDER BY r.RequestNo, g.PeriodMonth;
END
GO

/* ---------------------------------------------------------------------
   3. usp_ActualUpload_Create  (arsip file yang lolos validasi; status PENDING)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_Create
    @Username          NVARCHAR(100),
    @OriginalFileName  NVARCHAR(260),
    @RelativePath      NVARCHAR(400),
    @ContentType       VARCHAR(100),
    @FileSizeBytes     BIGINT,
    @RowTotal          INT,
    @GroupTotal        INT,
    @TotalAmount       DECIMAL(18, 2),
    @NewId             INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can upload actual cost.', 1;
    IF NULLIF(LTRIM(RTRIM(@OriginalFileName)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@RelativePath)), N'') IS NULL
       OR ISNULL(@FileSizeBytes, 0) <= 0
        THROW 50072, N'Upload file is invalid.', 1;

    INSERT INTO dbo.ActualCostUpload
        (OriginalFileName, RelativePath, ContentType, FileSizeBytes, RowTotal, GroupTotal, TotalAmount, CreatedBy)
    VALUES (@OriginalFileName, @RelativePath, @ContentType, @FileSizeBytes, ISNULL(@RowTotal, 0), ISNULL(@GroupTotal, 0),
            ISNULL(@TotalAmount, 0), @Username);

    SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
END
GO

/* ---------------------------------------------------------------------
   4. usp_ActualUpload_Import  (konfirmasi; @RowsJson = isi file yang sama, dibaca ulang aplikasi)
      All or nothing: validasi ulang, lalu tiap project + bulan -> usp_Request_SaveActualMonth (EXCEL), satu transaksi.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_Import
    @UploadId  INT,
    @Username  NVARCHAR(100),
    @RowsJson  NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can upload actual cost.', 1;
    IF ISJSON(ISNULL(@RowsJson, N'[]')) = 0
        THROW 50072, N'Upload data is invalid.', 1;

    CREATE TABLE #UploadRows
    (
        RowNo        INT            NOT NULL PRIMARY KEY,
        RequestNo    VARCHAR(40)    NULL,
        PeriodMonth  DATE           NULL,
        ItemType     VARCHAR(20)    NULL,
        ItemName     NVARCHAR(400)  NULL,
        Qty          DECIMAL(18, 4) NULL,
        Unit         NVARCHAR(60)   NULL,
        UnitPrice    DECIMAL(18, 2) NULL,
        Amount       DECIMAL(18, 2) NULL,
        ReferenceNo  NVARCHAR(200)  NULL,
        Notes        NVARCHAR(1000) NULL,
        RequestId    INT            NULL,
        Error        NVARCHAR(500)  NULL
    );

    INSERT INTO #UploadRows (RowNo, RequestNo, PeriodMonth, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo, Notes)
    SELECT  x.[row], NULLIF(UPPER(LTRIM(RTRIM(x.requestNo))), ''),
            CASE WHEN x.[month] IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(x.[month]), MONTH(x.[month]), 1) END,
            UPPER(LTRIM(RTRIM(x.[type]))), NULLIF(LTRIM(RTRIM(x.[name])), N''), x.qty, NULLIF(LTRIM(RTRIM(x.unit)), N''),
            x.price, x.amount, NULLIF(LTRIM(RTRIM(x.[ref])), N''), NULLIF(LTRIM(RTRIM(x.notes)), N'')
    FROM    OPENJSON(ISNULL(@RowsJson, N'[]'))
            WITH ([row] INT '$.row', requestNo VARCHAR(40) '$.requestNo', [month] DATE '$.month', [type] VARCHAR(20) '$.type',
                  [name] NVARCHAR(400) '$.name', qty DECIMAL(18, 4) '$.qty', unit NVARCHAR(60) '$.unit',
                  price DECIMAL(18, 2) '$.price', amount DECIMAL(18, 2) '$.amount', [ref] NVARCHAR(200) '$.ref',
                  notes NVARCHAR(1000) '$.notes') x;

    IF NOT EXISTS (SELECT 1 FROM #UploadRows)
        THROW 50072, N'The file has no data rows.', 1;

    EXEC dbo.usp_ActualUpload_CheckRows @Username = @Username;

    IF EXISTS (SELECT 1 FROM #UploadRows WHERE Error IS NOT NULL)
        THROW 50072, N'The file is no longer valid (data changed since the preview). Please upload it again.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @FileName NVARCHAR(260);

    BEGIN TRANSACTION;

    SELECT @FileName = u.OriginalFileName
    FROM   dbo.ActualCostUpload u WITH (UPDLOCK, ROWLOCK)
    WHERE  u.Id = @UploadId AND u.CreatedBy = @Username;

    IF @FileName IS NULL
        THROW 50073, N'Upload not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ActualCostUpload WHERE Id = @UploadId AND Status = 'PENDING')
        THROW 50072, N'This upload has already been processed.', 1;

    DECLARE @ReqId INT, @Month DATE, @Json NVARCHAR(MAX), @Remark NVARCHAR(1000) = LEFT(N'Excel upload: ' + @FileName, 1000);

    DECLARE grp CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT RequestId, PeriodMonth FROM #UploadRows ORDER BY RequestId, PeriodMonth;
    OPEN grp;
    FETCH NEXT FROM grp INTO @ReqId, @Month;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Json =
        (
            SELECT  ItemType AS [type], ItemName AS [name], Qty AS qty, Unit AS unit, UnitPrice AS price, Amount AS amount,
                    ReferenceNo AS [ref], Notes AS notes
            FROM    #UploadRows
            WHERE   RequestId = @ReqId AND PeriodMonth = @Month
            ORDER BY RowNo
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );

        -- Simpan seperti input manual (menimpa bulan, riwayat, status biaya); hasil SELECT-nya diabaikan pemanggil
        EXEC dbo.usp_Request_SaveActualMonth @Id = @ReqId, @Username = @Username, @Month = @Month, @ItemsJson = @Json,
             @Remarks = @Remark, @Source = 'EXCEL', @UploadId = @UploadId;

        FETCH NEXT FROM grp INTO @ReqId, @Month;
    END
    CLOSE grp;
    DEALLOCATE grp;

    UPDATE dbo.ActualCostUpload
    SET    Status = 'IMPORTED', ProcessedAt = @Now, ProcessedBy = @Username
    WHERE  Id = @UploadId;

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   5. usp_ActualUpload_Cancel  (batal setelah preview; file tetap diarsipkan)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_Cancel
    @UploadId  INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.ActualCostUpload
    SET    Status = 'CANCELLED', ProcessedAt = SYSDATETIME(), ProcessedBy = @Username
    WHERE  Id = @UploadId AND CreatedBy = @Username AND Status = 'PENDING';

    IF @@ROWCOUNT = 0
        THROW 50072, N'This upload was not found or has already been processed.', 1;
END
GO

/* ---------------------------------------------------------------------
   6. usp_ActualUpload_GetPaged  (riwayat upload; civil, fat, gm, director, administrator)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_GetPaged
    @Username    NVARCHAR(100),
    @PageNumber  INT = 1,
    @PageSize    INT = 10,
    @TotalCount  INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 10 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;

    DECLARE @CanSee BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username)) THEN 1 ELSE 0 END;

    SELECT @TotalCount = COUNT(*) FROM dbo.ActualCostUpload WHERE @CanSee = 1;

    SELECT  u.Id, u.OriginalFileName, u.FileSizeBytes, u.RowTotal, u.GroupTotal, u.TotalAmount, u.Status,
            u.CreatedAt, u.CreatedBy, u.ProcessedAt, u.ProcessedBy
    FROM    dbo.ActualCostUpload u
    WHERE   @CanSee = 1
    ORDER BY u.CreatedAt DESC, u.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO

/* ---------------------------------------------------------------------
   7. usp_ActualUpload_GetById  (download arsip / konfirmasi; 0 baris bila tidak berhak)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_GetById
    @UploadId  INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  u.Id, u.OriginalFileName, u.RelativePath, u.ContentType, u.FileSizeBytes, u.RowTotal, u.GroupTotal,
            u.TotalAmount, u.Status, u.CreatedAt, u.CreatedBy, u.ProcessedAt, u.ProcessedBy
    FROM    dbo.ActualCostUpload u
    WHERE   u.Id = @UploadId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username));
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: RequestActualCost.sql dijalankan ulang, lalu file ini. Ada request IN_PROGRESS (mis. hasil test T4-2).

   DECLARE @Civil NVARCHAR(100) = N'users1', @No VARCHAR(40) = 'IT-OPX-11-26-002',
           @J NVARCHAR(MAX), @UploadId INT;

   -- 1) Validasi: baris salah -> result 1 berisi error per baris, result 2 kosong
   SET @J = N'[{"row":2,"requestNo":"' + @No + N'","month":"2026-11-01","type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":600000},'
          + N'{"row":3,"requestNo":"XX-OPX-01-26-999","month":"2026-11-01","type":"SERVICE","name":"Labor","qty":1,"unit":"ls","price":100,"amount":100},'
          + N'{"row":4,"requestNo":"' + @No + N'","month":"2027-01-01","type":"OTHER","name":"X","qty":1,"unit":"ls","price":1,"amount":1}]';
   EXEC dbo.usp_ActualUpload_Validate @Username = @Civil, @RowsJson = @J;      -- baris 2 amount, 3 not found, 4 future month

   -- 2) Validasi file benar: 2 baris November untuk request yang sama
   SET @J = N'[{"row":2,"requestNo":"' + @No + N'","month":"2026-11-01","type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000,"ref":"PO-9"},'
          + N'{"row":3,"requestNo":"' + @No + N'","month":"2026-11-01","type":"SERVICE","name":"Labor","qty":1,"unit":"ls","price":1000000,"amount":1000000}]';
   EXEC dbo.usp_ActualUpload_Validate @Username = @Civil, @RowsJson = @J;      -- result 2: 1 grup Nov, 2 item, 1.650.000, WillReplace bila sudah ada

   -- 3) Arsip (PENDING) lalu import -> bulan Nov diganti (Source EXCEL, UploadId), status IMPORTED, riwayat ACTUAL_COST
   EXEC dbo.usp_ActualUpload_Create @Username = @Civil, @OriginalFileName = N'actual-nov.xlsx', @RelativePath = N'ActualCost\2026\test.xlsx',
        @ContentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', @FileSizeBytes = 1024,
        @RowTotal = 2, @GroupTotal = 1, @TotalAmount = 1650000, @NewId = @UploadId OUTPUT;
   EXEC dbo.usp_ActualUpload_Import @UploadId = @UploadId, @Username = @Civil, @RowsJson = @J;
   SELECT * FROM dbo.ActualCostUpload WHERE Id = @UploadId;
   SELECT m.PeriodMonth, m.TotalAmount, m.ItemCount, m.Source, m.UploadId FROM dbo.ProjectActualMonth m
          JOIN dbo.ProjectRequest r ON r.Id = m.RequestId WHERE r.RequestNo = @No;

   -- 4) Import ulang upload yang sama -> 50072 (sudah diproses); cancel upload yang sudah IMPORTED -> 50072
   BEGIN TRY EXEC dbo.usp_ActualUpload_Import @UploadId = @UploadId, @Username = @Civil, @RowsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4a expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_ActualUpload_Cancel @UploadId = @UploadId, @Username = @Civil;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 5) Riwayat upload
   DECLARE @T INT; EXEC dbo.usp_ActualUpload_GetPaged @Username = @Civil, @TotalCount = @T OUTPUT; SELECT @T AS TotalCount;
   ===================================================================== */
GO
/* ---------- end RequestActualUpload.sql ---------- */
/* ---------- begin RequestMigration.sql ---------- */
PRINT N'[skema] RequestMigration.sql';
GO
/* =====================================================================
   RequestMigration.sql  -  Input project berjalan saat go-live (T4-3; PRD 9.3: FR-03, BR-76, BR-77)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Request.sql (kolom IsMigrated),
             RequestExecution.sql (ProjectContract), dan RequestSchedule.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Aturan (Keputusan 16-11-2026, lihat docs/PRD-log.md):
     - Khusus civil. Project lama langsung dicatat pada status PLANNING atau SCHEDULING, tanpa approval di CIMS.
       Project yang sudah berjalan: masuk SCHEDULING, lalu Civil mengisi schedule/action plan/estimasi dan
       mencatat site handover (tanggal lampau) lewat alur T4-2, sehingga validasi T4-2 tetap berlaku.
     - Wajib: departemen (lingkup user), judul, kategori, sub-kategori, lokasi. Lainnya opsional.
     - SCHEDULING wajib cara eksekusi:
         INHOUSE   : BOQ total wajib -> plan cost = BOQ total.
         OUTSOURCE : kontrak diinput Civil (vendor aktif, nomor, tanggal, nilai) -> plan cost = nilai kontrak.
       Awal periode Preparation: tanggal yang diisi, atau default tanggal kontrak (outsource) / hari ini (in-house).
     - Nomor request format sama, bulan/tahun = bulan input (BR-77); IsMigrated = 1.
     - Approval di luar sistem (BR-76): baris opsional (langkah/role, nama approver, tanggal) dicatat di riwayat
       sebagai OUTSIDE_APPROVAL ("Approved outside CIMS"); pembuatan dicatat sebagai MIGRATION.
     - Requester tercatat = user civil yang menginput (pemilik data migrasi).
   Error   : 50072 = Input wajib kosong / tidak valid
             50075 = Role user tidak sesuai (civil)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_Lookup_DepartmentsForUser  (pilihan departemen dalam lingkup user, punya ABRV)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_DepartmentsForUser
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  d.DepartmentID, d.CoCode, d.DeptName, d.ABRV
    FROM    dbo.fn_User_AllowedDepartments(@Username) f
            JOIN home..APP_Departments d ON d.DepartmentID = f.DepartmentID
    WHERE   LTRIM(RTRIM(ISNULL(d.ABRV, ''))) <> ''
    ORDER BY d.CoCode, d.DeptName, d.DepartmentID;
END
GO

/* ---------------------------------------------------------------------
   2. usp_Request_CreateRunning  (civil; FR-03)
      @TargetStatus  : PLANNING | SCHEDULING
      @ExecutionType : wajib bila SCHEDULING (INHOUSE | OUTSOURCE); harus NULL bila PLANNING
      @ApprovalsJson : [{"step":"Kabag","name":"Budi","date":"2026-09-01"}, ...] (opsional, maks. 10 baris)
      Hasil: SELECT Id, RequestNo, Status.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_CreateRunning
    @Username              NVARCHAR(100),
    @DepartmentID          INT,
    @Title                 NVARCHAR(MAX),
    @Category              VARCHAR(10),
    @SubCategoryId         INT,
    @LocationId            INT,
    @PicEmployeeCode       VARCHAR(30)    = NULL,
    @SubDepartmentID       INT            = NULL,
    @BudgetRemarks         VARCHAR(12)    = NULL,
    @TargetCompletionDate  DATE           = NULL,
    @BudgetExpectation     DECIMAL(18, 2) = NULL,
    @Background            NVARCHAR(MAX)  = NULL,
    @Objective             NVARCHAR(MAX)  = NULL,
    @TargetStatus          VARCHAR(20),
    @ExecutionType         VARCHAR(10)    = NULL,
    @BoqTotal              DECIMAL(18, 2) = NULL,
    @VendorId              INT            = NULL,
    @ContractNo            NVARCHAR(50)   = NULL,
    @ContractDate          DATE           = NULL,
    @ContractValue         DECIMAL(18, 2) = NULL,
    @PreparationStartDate  DATE           = NULL,
    @ApprovalsJson         NVARCHAR(MAX)  = NULL,
    @Remarks               NVARCHAR(MAX)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);
    DECLARE @Msg NVARCHAR(2048);

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can enter running projects.', 1;

    /* -- Civil yang menginput (karyawan aktif) = requester data migrasi -- */
    DECLARE @EmpCode VARCHAR(30);
    SELECT  @EmpCode = e.EmployeeCode
    FROM    home..users u
            JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
    WHERE   u.Username = @Username
      AND   (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME());

    IF @EmpCode IS NULL
        THROW 50072, N'Your employee data was not found.', 1;

    /* -- Normalisasi -- */
    SET @Title           = NULLIF(LTRIM(RTRIM(@Title)), N'');
    SET @Category        = UPPER(LTRIM(RTRIM(@Category)));
    SET @PicEmployeeCode = NULLIF(LTRIM(RTRIM(@PicEmployeeCode)), '');
    SET @BudgetRemarks   = NULLIF(UPPER(LTRIM(RTRIM(@BudgetRemarks))), '');
    SET @Background      = NULLIF(LTRIM(RTRIM(@Background)), N'');
    SET @Objective       = NULLIF(LTRIM(RTRIM(@Objective)), N'');
    SET @TargetStatus    = UPPER(LTRIM(RTRIM(@TargetStatus)));
    SET @ExecutionType   = NULLIF(UPPER(LTRIM(RTRIM(@ExecutionType))), '');
    SET @ContractNo      = NULLIF(LTRIM(RTRIM(@ContractNo)), N'');
    SET @Remarks         = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    /* -- Departemen (lingkup user) -> Company + ABRV -- */
    DECLARE @CoCode VARCHAR(10), @Abrv VARCHAR(30);
    SELECT  @CoCode = d.CoCode, @Abrv = LTRIM(RTRIM(REPLACE(d.ABRV, ' - NKM', '')))
    FROM    home..APP_Departments d
    WHERE   d.DepartmentID = @DepartmentID
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = d.DepartmentID);

    IF @CoCode IS NULL
        THROW 50072, N'Please select a valid requesting department.', 1;
    IF ISNULL(@CoCode, '') NOT IN ('ABL', 'NKM')
        THROW 50072, N'The department company must be ABL or NKM.', 1;
    IF ISNULL(@Abrv, '') = ''
        THROW 50072, N'The requesting department has no abbreviation (ABRV); request number cannot be generated.', 1;

    /* -- Wajib -- */
    IF @Title IS NULL                                           THROW 50072, N'Request title is required.', 1;
    IF LEN(@Title) > 200                                        THROW 50072, N'Request title must be at most 200 characters.', 1;
    IF ISNULL(@Category, '') NOT IN ('CAPEX', 'OPEX', 'LVE')    THROW 50072, N'Budget classification is required (CAPEX, OPEX, or LVE).', 1;
    IF @SubCategoryId IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.SubCategory WHERE Id = @SubCategoryId AND Category = @Category AND IsActive = 1)
        THROW 50072, N'Please select a valid sub-category for the budget classification.', 1;
    IF @LocationId IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.Location WHERE Id = @LocationId AND CoCode = @CoCode AND IsActive = 1)
        THROW 50072, N'Please select a valid location for the department company.', 1;

    /* -- Opsional, divalidasi bila diisi -- */
    IF @PicEmployeeCode IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM home..app_employees e
                       WHERE e.EmployeeCode = @PicEmployeeCode AND e.DepartmentID = @DepartmentID
                         AND (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME()))
        THROW 50072, N'PIC must be an active employee of the requesting department.', 1;
    IF @SubDepartmentID IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM home..APP_SubDepartments s
                       WHERE s.SubDepartmentID = @SubDepartmentID AND s.DepartmentID = @DepartmentID AND s.Disabled = 0)
        THROW 50072, N'Cost center is invalid for the requesting department.', 1;
    IF @BudgetRemarks IS NOT NULL AND @BudgetRemarks NOT IN ('BUDGETED', 'UNBUDGETED')
        THROW 50072, N'Budget remarks must be Budgeted or Unbudgeted.', 1;
    IF @BudgetExpectation IS NOT NULL AND @BudgetExpectation < 0
        THROW 50072, N'Budget expectation cannot be negative.', 1;
    IF @BoqTotal IS NOT NULL AND @BoqTotal <= 0
        THROW 50072, N'BOQ total must be greater than 0.', 1;
    IF LEN(@Background) > 2000 OR LEN(@Objective) > 2000
        THROW 50072, N'Each text field must be at most 2000 characters.', 1;
    IF LEN(@Remarks) > 900
        THROW 50072, N'Remarks must be at most 900 characters.', 1;

    /* -- Status tujuan + cara eksekusi -- */
    IF ISNULL(@TargetStatus, '') NOT IN ('PLANNING', 'SCHEDULING')
        THROW 50072, N'Current status must be Planning or Scheduling.', 1;

    IF @TargetStatus = 'PLANNING' AND @ExecutionType IS NOT NULL
        THROW 50072, N'The execution method is chosen later for projects in planning.', 1;

    DECLARE @PlanCost DECIMAL(18, 2) = NULL, @PrepStart DATETIME2(3) = NULL;

    IF @TargetStatus = 'SCHEDULING'
    BEGIN
        IF ISNULL(@ExecutionType, '') NOT IN ('INHOUSE', 'OUTSOURCE')
            THROW 50072, N'Please choose in-house or outsource for projects in scheduling.', 1;

        IF @ExecutionType = 'INHOUSE'
        BEGIN
            IF @BoqTotal IS NULL
                THROW 50072, N'BOQ total is required for in-house execution (plan cost).', 1;
            SET @PlanCost = @BoqTotal;
            SET @PrepStart = CAST(ISNULL(@PreparationStartDate, @Today) AS DATETIME2(3));
        END
        ELSE
        BEGIN
            DECLARE @Missing NVARCHAR(500) =
                  CASE WHEN @VendorId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Vendor v WHERE v.Id = @VendorId AND v.IsActive = 1)
                       THEN N', Vendor (active)' ELSE N'' END
                + CASE WHEN @ContractNo IS NULL THEN N', Contract number' ELSE N'' END
                + CASE WHEN @ContractDate IS NULL THEN N', Contract date' ELSE N'' END
                + CASE WHEN @ContractValue IS NULL OR @ContractValue <= 0 THEN N', Contract value (greater than 0)' ELSE N'' END;
            IF @Missing <> N''
            BEGIN
                SET @Msg = N'Please complete the contract: ' + STUFF(@Missing, 1, 2, N'') + N'.';
                THROW 50072, @Msg, 1;
            END
            IF LEN(@ContractNo) > 50
                THROW 50072, N'Contract number must be at most 50 characters.', 1;
            IF @ContractDate > @Today
                THROW 50072, N'Contract date cannot be in the future.', 1;
            SET @PlanCost = @ContractValue;
            SET @PrepStart = CAST(ISNULL(@PreparationStartDate, @ContractDate) AS DATETIME2(3));
        END

        IF @PreparationStartDate IS NOT NULL AND @PreparationStartDate > @Today
            THROW 50072, N'Preparation start date cannot be in the future.', 1;
    END
    ELSE IF @VendorId IS NOT NULL OR @ContractNo IS NOT NULL OR @ContractDate IS NOT NULL OR @ContractValue IS NOT NULL
        THROW 50072, N'Contract data can only be entered for outsourced projects in scheduling.', 1;

    /* -- Approval di luar sistem (BR-76) -- */
    IF ISJSON(ISNULL(@ApprovalsJson, N'[]')) = 0
        THROW 50072, N'Outside approval data is invalid.', 1;

    DECLARE @Approvals TABLE (Seq INT PRIMARY KEY, Step NVARCHAR(200) NULL, Name NVARCHAR(200) NULL, ApprovedOn DATE NULL);

    INSERT INTO @Approvals (Seq, Step, Name, ApprovedOn)
    SELECT  CAST(j.[key] AS INT) + 1, NULLIF(LTRIM(RTRIM(x.step)), N''), NULLIF(LTRIM(RTRIM(x.name)), N''), x.[date]
    FROM    OPENJSON(ISNULL(@ApprovalsJson, N'[]')) j
            CROSS APPLY OPENJSON(j.[value]) WITH (step NVARCHAR(200) '$.step', name NVARCHAR(200) '$.name', [date] DATE '$.date') x;

    DELETE FROM @Approvals WHERE Step IS NULL AND Name IS NULL AND ApprovedOn IS NULL;   -- baris kosong

    IF (SELECT COUNT(*) FROM @Approvals) > 10
        THROW 50072, N'At most 10 outside approval rows are allowed.', 1;

    SELECT TOP (1) @Msg = N'Outside approval row ' + CAST(a.Seq AS NVARCHAR(10)) + N': ' +
           CASE WHEN a.Step IS NULL AND a.Name IS NULL THEN N'step/role or approver name is required.'
                WHEN LEN(a.Step) > 100 OR LEN(a.Name) > 100 THEN N'step/role and name must be at most 100 characters.'
                ELSE N'date cannot be in the future.' END
    FROM   @Approvals a
    WHERE  (a.Step IS NULL AND a.Name IS NULL) OR LEN(a.Step) > 100 OR LEN(a.Name) > 100 OR a.ApprovedOn > @Today
    ORDER BY a.Seq;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    /* -- Simpan -- */
    DECLARE @Id INT, @RequestNo VARCHAR(40);
    DECLARE @Yr SMALLINT = YEAR(@Now), @Mon TINYINT = MONTH(@Now), @Next INT;

    BEGIN TRANSACTION;

    -- Nomor request: format sama, bulan/tahun = bulan input (BR-41, BR-77)
    UPDATE dbo.RequestNoSequence WITH (UPDLOCK, HOLDLOCK)
    SET    @Next = LastNo = LastNo + 1,
           UpdatedAt = @Now
    WHERE  CoCode = @CoCode AND Abrv = @Abrv AND Category = @Category AND SeqYear = @Yr AND SeqMonth = @Mon;

    IF @@ROWCOUNT = 0
    BEGIN
        SET @Next = 1;
        INSERT INTO dbo.RequestNoSequence (CoCode, Abrv, Category, SeqYear, SeqMonth, LastNo)
        VALUES (@CoCode, @Abrv, @Category, @Yr, @Mon, @Next);
    END

    SET @RequestNo = CASE WHEN @CoCode = 'NKM' THEN 'NKM-' ELSE '' END
                   + @Abrv + '-'
                   + CASE @Category WHEN 'CAPEX' THEN 'CPX' WHEN 'OPEX' THEN 'OPX' ELSE 'LVE' END + '-'
                   + RIGHT('0' + CAST(@Mon AS VARCHAR(2)), 2) + '-'
                   + RIGHT(CAST(@Yr AS VARCHAR(4)), 2) + '-'
                   + RIGHT('00' + CAST(@Next AS VARCHAR(10)), CASE WHEN @Next > 999 THEN LEN(CAST(@Next AS VARCHAR(10))) ELSE 3 END);

    INSERT INTO dbo.ProjectRequest
        (CoCode, DepartmentID, RequestNo, Status, RequesterUsername, RequesterEmployeeCode, PicEmployeeCode,
         Title, Category, SubCategoryId, BudgetRemarks, SubDepartmentID, LocationId, TargetCompletionDate,
         BudgetExpectation, Background, Objective, BoqTotal, ExecutionType, PlanCost, PreparationStartAt,
         IsMigrated, SubmittedAt, CreatedAt, CreatedBy)
    VALUES
        (@CoCode, @DepartmentID, @RequestNo, @TargetStatus, @Username, @EmpCode, @PicEmployeeCode,
         @Title, @Category, @SubCategoryId, @BudgetRemarks, @SubDepartmentID, @LocationId, @TargetCompletionDate,
         @BudgetExpectation, @Background, @Objective, @BoqTotal, @ExecutionType, @PlanCost, @PrepStart,
         1, @Now, @Now, @Username);

    SET @Id = CAST(SCOPE_IDENTITY() AS INT);

    -- Nomor tercatat (pencarian nomor; alasan SUBMIT = nomor pertama)
    INSERT INTO dbo.RequestNoHistory (RequestId, RequestNo, Reason, CreatedBy)
    VALUES (@Id, @RequestNo, 'SUBMIT', @Username);

    IF @ExecutionType = 'OUTSOURCE'
        INSERT INTO dbo.ProjectContract (RequestId, VendorId, ContractNo, ContractDate, ContractValue, Remarks, CreatedAt, CreatedBy)
        VALUES (@Id, @VendorId, @ContractNo, @ContractDate, @ContractValue, N'Running project (data migration)', @Now, @Username);

    -- Riwayat: pembuatan data migrasi, lalu approval di luar sistem (BR-76)
    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'MIGRATION', NULL, @TargetStatus,
            LEFT(N'Running project entered (data migration)'
                 + CASE WHEN @ExecutionType IS NULL THEN N'' ELSE N' · ' + CASE @ExecutionType WHEN 'INHOUSE' THEN N'In-house' ELSE N'Outsource' END END
                 + ISNULL(N' · ' + @Remarks, N''), 1000),
            @Username, @Now);

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    SELECT  @Id, 'OUTSIDE_APPROVAL', NULL, NULL,
            LEFT(N'Approved outside CIMS'
                 + ISNULL(N' · ' + a.Step, N'')
                 + ISNULL(N' · ' + a.Name, N'')
                 + ISNULL(N' · ' + FORMAT(a.ApprovedOn, N'dd MMM yyyy', 'en-US'), N''), 1000),
            @Username, @Now
    FROM    @Approvals a
    ORDER BY a.Seq;

    COMMIT TRANSACTION;

    SELECT @Id AS Id, @RequestNo AS RequestNo, @TargetStatus AS Status;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: Request.sql dijalankan ulang (IsMigrated), lalu file ini.

   DECLARE @Civil NVARCHAR(100) = N'users1', @Other NVARCHAR(100) = N'240701',
           @Dept INT = 19, @Sub INT = 1, @Loc INT = 35,
           @Vendor INT = (SELECT TOP (1) Id FROM dbo.Vendor WHERE IsActive = 1);

   -- 0) Pilihan departemen untuk civil (semua ABL + NKM yang punya ABRV)
   EXEC dbo.usp_Lookup_DepartmentsForUser @Username = @Civil;

   -- 1) Bukan civil -> 50075; SCHEDULING tanpa cara eksekusi -> 50072; in-house tanpa BOQ -> 50072; outsource tanpa kontrak -> 50072
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Other, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'PLANNING';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (execution)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING', @ExecutionType = 'INHOUSE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (BOQ)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING', @ExecutionType = 'OUTSOURCE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1d expect 50072 (contract)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'PLANNING',
        @ApprovalsJson = N'[{"step":"Kabag","name":"Budi","date":"2099-01-01"}]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1e expect 50072 (approval date)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) PLANNING + 2 approval di luar sistem -> nomor bulan ini, IsMigrated = 1, riwayat MIGRATION + 2x OUTSIDE_APPROVAL
   EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'Running project - planning',
        @Category = 'CAPEX', @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'PLANNING', @BoqTotal = 8000000,
        @ApprovalsJson = N'[{"step":"Kabag","name":"Budi","date":"2026-09-01"},{"step":"GM","name":"","date":"2026-09-10"}]';

   -- 3) SCHEDULING in-house -> PlanCost = BOQ; lanjut isi schedule/handover lewat T4-2 untuk project yang sudah berjalan
   EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'Running project - in-house',
        @Category = 'CAPEX', @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING',
        @ExecutionType = 'INHOUSE', @BoqTotal = 10000000, @PreparationStartDate = '2026-10-01';

   -- 4) SCHEDULING outsource -> ProjectContract terisi, PlanCost = nilai kontrak, Preparation = tanggal kontrak
   EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'Running project - outsource',
        @Category = 'CAPEX', @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING',
        @ExecutionType = 'OUTSOURCE', @VendorId = @Vendor, @ContractNo = N'SPK/OLD/001', @ContractDate = '2026-10-15', @ContractValue = 25000000;

   SELECT TOP (3) Id, RequestNo, Status, IsMigrated, ExecutionType, BoqTotal, PlanCost, PreparationStartAt
   FROM dbo.ProjectRequest WHERE IsMigrated = 1 ORDER BY Id DESC;
   SELECT h.RequestId, h.Action, h.ToStatus, h.Remarks FROM dbo.ApprovalHistory h
   WHERE h.RequestId IN (SELECT TOP (3) Id FROM dbo.ProjectRequest WHERE IsMigrated = 1 ORDER BY Id DESC) ORDER BY h.Id;
   EXEC dbo.usp_Task_GetList @Username = @Civil, @TaskType = 'SCHEDULING';             -- 2 project baru muncul
   ===================================================================== */
GO
/* ---------- end RequestMigration.sql ---------- */
/* ---------- begin RequestAddendum.sql ---------- */
PRINT N'[skema] RequestAddendum.sql';
GO
/* =====================================================================
   RequestAddendum.sql  -  Addendum kontrak (outsource) dan perubahan budget/BOQ (in-house)
                           (T4-4; PRD 3.3 langkah 6, 3.3.1, 3.9, 5.2, BR-78 s.d. BR-87, BR-12, BR-13, BR-37)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST dengan urutan:
               1. AttachmentType.sql   (whitelist Stage ADDENDUM di Insert/Update)
               2. RequestSubmit.sql    (usp_Request_GetApprovalSteps tidak menampilkan titik ADDENDUM)
               3. RequestApproval.sql  (fn_User_ActionableSteps: titik ADDENDUM)
               4. RequestSchedule.sql  (kunci addendum, BR-83, BR-85)
               5. RequestProgress.sql  (usp_Request_RefreshScheduleSummary, BR-84)
               6. RequestAddendum.sql  (file ini)
               7. Task.sql             (tugas ADDENDUM untuk civil)
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Alur (Keputusan 17-11-2026, diubah 18-11-2026; lihat docs/PRD-log.md):
     1. Input addendum oleh CIVIL (outsource dan in-house; status request SCHEDULING atau IN_PROGRESS; BR-78, BR-79):
        nomor dokumen referensi (opsional), tanggal, nilai baru (total), alasan, lampiran wajib:
          OUTSOURCE -> draft kontrak baru (jenis lampiran ADDENDUM)
          INHOUSE   -> BOQ revisi (jenis lampiran BOQ_REVISION)
        Satu addendum terbuka per project; nomor urut AddendumNo 1, 2, ... (termasuk yang ditolak).
        Nomor addendum otomatis AddendumCode = {RequestNo}-A{AddendumNo}, mis. QC-CPX-11-26-001-A1
        (Keputusan 18-11-2026); disimpan saat dibuat agar tetap walau format berubah.
     2. Nilai baru > plan cost -> PENDING_APPROVAL: langkah titik ADDENDUM dari WorkflowStep di-snapshot ke
        ApprovalStep (Round = AddendumNo; BR-37, BR-80). Reject (alasan wajib) -> REJECTED, nilai lama tetap.
        Approve langkah terakhir (atau tanpa approval bila nilai sama / turun):
          OUTSOURCE -> FINAL_CONTRACT (BR-87): civil upload kontrak final bertanda tangan
                       (usp_Addendum_UploadFinalContract, jenis lampiran ADDENDUM_FINAL) -> ADJUSTMENT
          INHOUSE   -> ADJUSTMENT
     3. ADJUSTMENT -> civil menyimpan action plan + estimasi (usp_Addendum_SaveAdjustment; BR-82):
        total bobot = 100% dan total estimasi = nilai baru; plan cost = nilai baru; status biaya dan
        ringkasan progress dihitung ulang (BR-84) -> COMPLETED.
     Selama PENDING_APPROVAL / FINAL_CONTRACT / ADJUSTMENT: perubahan schedule/estimasi biasa dan addendum lain
     dikunci (BR-81). Purchasing hanya melihat (BR-86).
     Nilai kontrak asli (ProjectContract) dan BOQ total asli tidak diubah; nilai berlaku = ProjectRequest.PlanCost.
   Lihat (BR-86): request dalam lingkup user; OUTSOURCE hanya civil, purchasing, fat, gm, director,
     administrator (baris Kontrak 5.2); INHOUSE semua role yang melihat request (baris Feasibility/BOQ).
   Error   : 50072 = Input wajib kosong / tidak valid / data belum lengkap
             50073 = Request / addendum tidak ditemukan atau di luar lingkup user
             50074 = Status request / addendum tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Migrasi CHECK constraint: titik ADDENDUM (WorkflowStep, ApprovalStep) dan Stage ADDENDUM (AttachmentType)
   --------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE name = N'CK_WorkflowStep_Point' AND parent_object_id = OBJECT_ID(N'dbo.WorkflowStep')
             AND definition NOT LIKE N'%ADDENDUM%')
BEGIN
    ALTER TABLE dbo.WorkflowStep DROP CONSTRAINT CK_WorkflowStep_Point;
    ALTER TABLE dbo.WorkflowStep ADD CONSTRAINT CK_WorkflowStep_Point CHECK ([Point] IN ('REQUEST', 'MGMT', 'BAPP', 'ADDENDUM'));
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE name = N'CK_ApprovalStep_Point' AND parent_object_id = OBJECT_ID(N'dbo.ApprovalStep')
             AND definition NOT LIKE N'%ADDENDUM%')
BEGIN
    ALTER TABLE dbo.ApprovalStep DROP CONSTRAINT CK_ApprovalStep_Point;
    ALTER TABLE dbo.ApprovalStep ADD CONSTRAINT CK_ApprovalStep_Point CHECK ([Point] IN ('REQUEST', 'MGMT', 'BAPP', 'ADDENDUM'));
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE name = N'CK_AttachmentType_Stage' AND parent_object_id = OBJECT_ID(N'dbo.AttachmentType')
             AND definition NOT LIKE N'%ADDENDUM%')
BEGIN
    ALTER TABLE dbo.AttachmentType DROP CONSTRAINT CK_AttachmentType_Stage;
    ALTER TABLE dbo.AttachmentType ADD CONSTRAINT CK_AttachmentType_Stage
        CHECK (Stage IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP', 'COST', 'ADDENDUM'));
END
GO

/* ---------------------------------------------------------------------
   2. SEED (hanya menambah yang belum ada)
   --------------------------------------------------------------------- */
-- 2a. Workflow titik ADDENDUM (PRD 3.9): ABL -> gm, NKM -> director; tanpa Revise, Reject = addendum batal
MERGE dbo.WorkflowStep AS t
USING (VALUES
        ('ABL', 'ADDENDUM', 1, 'gm',       'PLANT', NULL, NULL, NULL, 1),
        ('NKM', 'ADDENDUM', 1, 'director', 'PLANT', NULL, NULL, NULL, 1)
      ) AS s (CoCode, [Point], StepOrder, RoleCode, Scope, Category, DepartmentGroupCode, ReviseTo, AllowReject)
   ON t.CoCode = s.CoCode AND t.[Point] = s.[Point] AND t.StepOrder = s.StepOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CoCode, [Point], StepOrder, RoleCode, Scope, Category, DepartmentGroupCode, ReviseTo, AllowReject, CreatedBy)
    VALUES (s.CoCode, s.[Point], s.StepOrder, s.RoleCode, s.Scope, s.Category, s.DepartmentGroupCode, s.ReviseTo,
            CAST(s.AllowReject AS BIT), N'seed');
GO

-- 2b. Jenis lampiran addendum (MD-09; aturan file PRD 6.5 sama dengan kontrak/BOQ)
MERGE dbo.AttachmentType AS t
USING (VALUES
        ('ADDENDUM',       N'Draft Contract Addendum',  'ADDENDUM', 'pdf,xlsx,dwg', 20),   -- outsource, saat raise
        ('ADDENDUM_FINAL', N'Signed Contract Addendum', 'ADDENDUM', 'pdf,xlsx,dwg', 20),   -- outsource, kontrak final (BR-87)
        ('BOQ_REVISION',   N'Revised BOQ',              'ADDENDUM', 'pdf,xlsx,dwg', 20)    -- in-house, saat raise
      ) AS s (Code, Name, Stage, AllowedExtensions, MaxSizeMB)
   ON t.Code = s.Code
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, CreatedBy)
    VALUES (s.Code, s.Name, s.Stage, s.AllowedExtensions, s.MaxSizeMB, 0, 0, 0, N'seed');
GO

-- 18-11-2026: lampiran ADDENDUM kini = draft kontrak. Nama seed lama diganti hanya bila belum diubah administrator.
UPDATE dbo.AttachmentType
SET    Name = N'Draft Contract Addendum', UpdatedAt = SYSDATETIME(), UpdatedBy = N'seed'
WHERE  Code = 'ADDENDUM' AND Name = N'Contract Addendum';
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.ProjectAddendum
      File addendum disimpan di tabel ini (bukan RequestAttachment) agar hak lihat BR-86 berlaku juga untuk file.
      RelativePath relatif terhadap FileStorage:RealizationAttachmentsPath.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectAddendum', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectAddendum
    (
        Id                INT IDENTITY(1,1) NOT NULL,
        RequestId         INT            NOT NULL,
        AddendumNo        INT            NOT NULL,       -- 1, 2, ... per project
        AddendumCode      VARCHAR(50)    NULL,           -- {RequestNo}-A{AddendumNo} (diisi usp_Addendum_Create)
        ExecutionType     VARCHAR(10)    NOT NULL,       -- INHOUSE | OUTSOURCE (saat dibuat)
        DocumentNo        NVARCHAR(50)   NULL,           -- nomor dokumen referensi (opsional)
        AddendumDate      DATE           NOT NULL,
        PreviousValue     DECIMAL(18, 2) NOT NULL,       -- plan cost saat addendum dibuat
        NewValue          DECIMAL(18, 2) NOT NULL,       -- nilai kontrak / BOQ baru (total)
        Reason            NVARCHAR(1000) NOT NULL,
        RequiresApproval  BIT            NOT NULL,
        Status            VARCHAR(20)    NOT NULL,       -- PENDING_APPROVAL | FINAL_CONTRACT | ADJUSTMENT | COMPLETED | REJECTED
        AttachmentTypeId  INT            NOT NULL,       -- file saat raise: draft kontrak (outsource) / BOQ revisi (in-house)
        OriginalFileName  NVARCHAR(260)  NOT NULL,
        RelativePath      NVARCHAR(400)  NOT NULL,
        ContentType       VARCHAR(100)   NOT NULL,
        FileSizeBytes     BIGINT         NOT NULL,
        FinalAttachmentTypeId INT        NULL,           -- kontrak final bertanda tangan (outsource; BR-87)
        FinalFileName     NVARCHAR(260)  NULL,
        FinalRelativePath NVARCHAR(400)  NULL,
        FinalContentType  VARCHAR(100)   NULL,
        FinalFileSizeBytes BIGINT        NULL,
        FinalUploadedAt   DATETIME2(3)   NULL,
        FinalUploadedBy   NVARCHAR(100)  NULL,
        ApprovedAt        DATETIME2(3)   NULL,           -- addendum berlaku (approve terakhir / tanpa approval)
        ClosedAt          DATETIME2(3)   NULL,           -- COMPLETED / REJECTED
        ClosedBy          NVARCHAR(100)  NULL,
        CreatedAt         DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectAddendum_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy         NVARCHAR(100)  NOT NULL,
        CONSTRAINT PK_ProjectAddendum PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectAddendum_No UNIQUE (RequestId, AddendumNo),
        CONSTRAINT FK_ProjectAddendum_Request FOREIGN KEY (RequestId)        REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_ProjectAddendum_Type    FOREIGN KEY (AttachmentTypeId) REFERENCES dbo.AttachmentType (Id),
        CONSTRAINT CK_ProjectAddendum_Exec    CHECK (ExecutionType IN ('INHOUSE', 'OUTSOURCE')),
        CONSTRAINT CK_ProjectAddendum_Value   CHECK (NewValue > 0 AND PreviousValue >= 0),
        CONSTRAINT CK_ProjectAddendum_Status  CHECK (Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT', 'COMPLETED', 'REJECTED')),
        CONSTRAINT CK_ProjectAddendum_Size    CHECK (FileSizeBytes > 0)
    );
END
GO

-- Migrasi 18-11-2026 (BR-87): kontrak final bertanda tangan untuk addendum outsource
IF COL_LENGTH(N'dbo.ProjectAddendum', N'FinalFileName') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectAddendum ADD
        FinalAttachmentTypeId INT           NULL,
        FinalFileName         NVARCHAR(260) NULL,
        FinalRelativePath     NVARCHAR(400) NULL,
        FinalContentType      VARCHAR(100)  NULL,
        FinalFileSizeBytes    BIGINT        NULL,
        FinalUploadedAt       DATETIME2(3)  NULL,
        FinalUploadedBy       NVARCHAR(100) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ProjectAddendum_FinalType')
BEGIN
    ALTER TABLE dbo.ProjectAddendum ADD CONSTRAINT FK_ProjectAddendum_FinalType
        FOREIGN KEY (FinalAttachmentTypeId) REFERENCES dbo.AttachmentType (Id);
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE name = N'CK_ProjectAddendum_Status' AND parent_object_id = OBJECT_ID(N'dbo.ProjectAddendum')
             AND definition NOT LIKE N'%FINAL_CONTRACT%')
BEGIN
    ALTER TABLE dbo.ProjectAddendum DROP CONSTRAINT CK_ProjectAddendum_Status;
    ALTER TABLE dbo.ProjectAddendum ADD CONSTRAINT CK_ProjectAddendum_Status
        CHECK (Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT', 'COMPLETED', 'REJECTED'));
END
GO

-- Index "satu addendum terbuka" dibuat ulang bila filter lama (tanpa FINAL_CONTRACT)
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ProjectAddendum_Open' AND object_id = OBJECT_ID(N'dbo.ProjectAddendum')
             AND filter_definition NOT LIKE N'%FINAL_CONTRACT%')
BEGIN
    DROP INDEX UX_ProjectAddendum_Open ON dbo.ProjectAddendum;
END
GO

-- Migrasi 18-11-2026: nomor addendum otomatis + nomor dokumen referensi opsional untuk in-house
IF COL_LENGTH(N'dbo.ProjectAddendum', N'AddendumCode') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectAddendum ADD AddendumCode VARCHAR(50) NULL;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ProjectAddendum') AND name = N'DocumentNo' AND is_nullable = 0)
BEGIN
    ALTER TABLE dbo.ProjectAddendum ALTER COLUMN DocumentNo NVARCHAR(50) NULL;
END
GO

-- Isi nomor otomatis untuk addendum yang dibuat sebelum migrasi
UPDATE d
SET    d.AddendumCode = r.RequestNo + '-A' + CAST(d.AddendumNo AS VARCHAR(10))
FROM   dbo.ProjectAddendum d
       JOIN dbo.ProjectRequest r ON r.Id = d.RequestId
WHERE  d.AddendumCode IS NULL AND r.RequestNo IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ProjectAddendum_Code' AND object_id = OBJECT_ID(N'dbo.ProjectAddendum'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_ProjectAddendum_Code ON dbo.ProjectAddendum (AddendumCode) WHERE AddendumCode IS NOT NULL;
END
GO

-- Satu addendum terbuka per project (BR-78, BR-81)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ProjectAddendum_Open' AND object_id = OBJECT_ID(N'dbo.ProjectAddendum'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_ProjectAddendum_Open ON dbo.ProjectAddendum (RequestId)
        WHERE Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT');
END
GO

/* ---------------------------------------------------------------------
   4. dbo.fn_User_CanSeeAddendum(@ExecutionType, @Username)  (BR-86)
      1 baris = boleh melihat addendum (data + file) project dengan cara eksekusi tsb.
      Lingkup request (fn_User_AllowedDepartments / purchasing-only) dicek terpisah di SP.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanSeeAddendum
(
    @ExecutionType VARCHAR(10),
    @Username      NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    WHERE  @ExecutionType = 'INHOUSE'
       OR  (@ExecutionType = 'OUTSOURCE'
            AND EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r
                        WHERE r.RoleCode IN (N'civil', N'purchasing', N'fat', N'dgo', N'gm', N'director', N'administrator')))
);
GO

/* ---------------------------------------------------------------------
   5. usp_Addendum_Create  (civil, outsource dan in-house; BR-78, BR-79, BR-80, BR-87)
      File sudah disimpan aplikasi sebelum SP dipanggil (aplikasi menghapus file bila SP gagal).
      Hasil: SELECT Id, AddendumNo, Status, RequiresApproval.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Addendum_Create
    @RequestId         INT,
    @Username          NVARCHAR(100),
    @DocumentNo        NVARCHAR(100),
    @AddendumDate      DATE,
    @NewValue          DECIMAL(18, 2),
    @Reason            NVARCHAR(MAX),
    @OriginalFileName  NVARCHAR(260),
    @RelativePath      NVARCHAR(400),
    @ContentType       VARCHAR(100),
    @FileSizeBytes     BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @DocumentNo       = NULLIF(LTRIM(RTRIM(@DocumentNo)), N'');
    SET @Reason           = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    SET @OriginalFileName = NULLIF(LTRIM(RTRIM(@OriginalFileName)), N'');
    SET @RelativePath     = NULLIF(LTRIM(RTRIM(@RelativePath)), N'');

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Msg NVARCHAR(2048);
    DECLARE @Status VARCHAR(20), @Exec VARCHAR(10), @PlanCost DECIMAL(18, 2), @CoCode VARCHAR(10),
            @Category VARCHAR(10), @DepartmentID INT, @RequestNo VARCHAR(40);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @Exec = r.ExecutionType, @PlanCost = r.PlanCost, @CoCode = r.CoCode,
            @Category = r.Category, @DepartmentID = r.DepartmentID, @RequestNo = r.RequestNo
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)));

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;

    -- BR-79 (diubah 18-11-2026): addendum outsource dan in-house di-raise oleh civil
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can raise an addendum.', 1;
    IF @Exec IS NULL OR @Status NOT IN ('SCHEDULING', 'IN_PROGRESS') OR @PlanCost IS NULL OR @RequestNo IS NULL
        THROW 50074, N'An addendum can only be entered during scheduling or while the project is in progress.', 1;
    IF EXISTS (SELECT 1 FROM dbo.ProjectAddendum d WITH (UPDLOCK, HOLDLOCK)
               WHERE d.RequestId = @RequestId AND d.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT'))
        THROW 50074, N'Another addendum is still in progress. Complete it before entering a new one.', 1;

    -- Validasi isi (setelah cek status agar pesan status lebih dulu); nomor dokumen referensi opsional (18-11-2026)
    DECLARE @Missing NVARCHAR(500) =
          CASE WHEN @AddendumDate IS NULL THEN N', Addendum date' ELSE N'' END
        + CASE WHEN @NewValue IS NULL OR @NewValue <= 0
               THEN CASE WHEN @Exec = 'OUTSOURCE' THEN N', New contract value (greater than 0)' ELSE N', New BOQ value (greater than 0)' END
               ELSE N'' END
        + CASE WHEN @Reason IS NULL THEN N', Reason' ELSE N'' END
        + CASE WHEN @OriginalFileName IS NULL OR @RelativePath IS NULL OR ISNULL(@FileSizeBytes, 0) <= 0
               THEN CASE WHEN @Exec = 'OUTSOURCE' THEN N', Draft contract document' ELSE N', Revised BOQ document' END
               ELSE N'' END;

    IF @Missing <> N''
    BEGIN
        SET @Msg = N'Please complete: ' + STUFF(@Missing, 1, 2, N'') + N'.';
        THROW 50072, @Msg, 1;
    END
    IF LEN(@DocumentNo) > 50
        THROW 50072, N'Reference document number must be at most 50 characters.', 1;
    IF LEN(@Reason) > 1000
        THROW 50072, N'Reason must be at most 1000 characters.', 1;

    -- Aturan file dari master Jenis Lampiran (MD-09): ADDENDUM (outsource) / BOQ_REVISION (in-house)
    DECLARE @TypeId INT, @Ext VARCHAR(200), @MaxMB INT, @FileExt VARCHAR(20);
    SELECT  @TypeId = t.Id, @Ext = t.AllowedExtensions, @MaxMB = t.MaxSizeMB
    FROM    dbo.AttachmentType t
    WHERE   t.Code = CASE WHEN @Exec = 'OUTSOURCE' THEN 'ADDENDUM' ELSE 'BOQ_REVISION' END
      AND   t.IsActive = 1;

    IF @TypeId IS NULL
        THROW 50072, N'The addendum attachment type is not configured. Please contact the administrator.', 1;

    SET @FileExt = CASE WHEN CHARINDEX('.', @OriginalFileName) = 0 THEN ''
                        ELSE LOWER(RIGHT(@OriginalFileName, CHARINDEX('.', REVERSE(@OriginalFileName)) - 1)) END;
    IF @FileExt = '' OR CHARINDEX(',' + @FileExt + ',', ',' + @Ext + ',') = 0
        THROW 50072, N'File type is not allowed for the addendum document.', 1;
    IF @FileSizeBytes > CAST(@MaxMB AS BIGINT) * 1048576
        THROW 50072, N'File size exceeds the maximum for the addendum document.', 1;

    -- BR-85: estimasi bulan sebelum bulan berjalan tidak bisa diubah, jadi nilai baru minimal sebesar totalnya
    DECLARE @CurMonth DATE = DATEFROMPARTS(YEAR(@Now), MONTH(@Now), 1);
    DECLARE @PastEstimate DECIMAL(18, 2) = ISNULL((SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e
                                                   WHERE e.RequestId = @RequestId AND e.PeriodMonth < @CurMonth), 0);
    IF @NewValue < @PastEstimate
    BEGIN
        SET @Msg = N'The new value must be at least IDR ' + FORMAT(@PastEstimate, N'#,0.##', 'en-US')
                 + N' (cost estimates of past months, which cannot be changed).';
        THROW 50072, @Msg, 1;
    END

    DECLARE @No INT = ISNULL((SELECT MAX(d.AddendumNo) FROM dbo.ProjectAddendum d WHERE d.RequestId = @RequestId), 0) + 1;
    DECLARE @Code VARCHAR(50) = @RequestNo + '-A' + CAST(@No AS VARCHAR(10));   -- {RequestNo}-A{n}
    DECLARE @NeedApproval BIT = CASE WHEN @NewValue > @PlanCost THEN 1 ELSE 0 END;   -- BR-80

    -- Snapshot langkah approval titik ADDENDUM (BR-37, BR-52: kondisi kategori / grup departemen)
    DECLARE @Steps TABLE (StepOrder INT PRIMARY KEY, WorkflowStepId INT, RoleCode VARCHAR(50), Scope VARCHAR(10),
                          DepartmentGroupCode VARCHAR(20), AllowReject BIT);
    IF @NeedApproval = 1
    BEGIN
        INSERT INTO @Steps (StepOrder, WorkflowStepId, RoleCode, Scope, DepartmentGroupCode, AllowReject)
        SELECT  w.StepOrder, w.Id, w.RoleCode, w.Scope, w.DepartmentGroupCode, w.AllowReject
        FROM    dbo.WorkflowStep w
        WHERE   w.CoCode = @CoCode
          AND   w.[Point] = 'ADDENDUM'
          AND   w.IsActive = 1
          AND   (w.Category IS NULL OR w.Category = @Category)
          AND   (w.DepartmentGroupCode IS NULL
                 OR EXISTS (SELECT 1 FROM dbo.DepartmentGroup g JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                            WHERE g.CoCode = w.CoCode AND g.GroupCode = w.DepartmentGroupCode AND g.IsActive = 1
                              AND m.DepartmentID = @DepartmentID));

        IF NOT EXISTS (SELECT 1 FROM @Steps)
            THROW 50074, N'No approval workflow is configured for addendums. Please contact the administrator.', 1;
    END

    -- Tanpa approval: outsource menunggu kontrak final (BR-87), in-house langsung penyesuaian (BR-82)
    DECLARE @NewStatus VARCHAR(20) = CASE WHEN @NeedApproval = 1 THEN 'PENDING_APPROVAL'
                                          WHEN @Exec = 'OUTSOURCE' THEN 'FINAL_CONTRACT'
                                          ELSE 'ADJUSTMENT' END;

    INSERT INTO dbo.ProjectAddendum
        (RequestId, AddendumNo, AddendumCode, ExecutionType, DocumentNo, AddendumDate, PreviousValue, NewValue, Reason,
         RequiresApproval, Status, AttachmentTypeId, OriginalFileName, RelativePath, ContentType, FileSizeBytes,
         ApprovedAt, CreatedAt, CreatedBy)
    VALUES
        (@RequestId, @No, @Code, @Exec, @DocumentNo, @AddendumDate, @PlanCost, @NewValue, @Reason,
         @NeedApproval, @NewStatus, @TypeId, @OriginalFileName, @RelativePath,
         ISNULL(NULLIF(@ContentType, ''), 'application/octet-stream'), @FileSizeBytes,
         CASE WHEN @NeedApproval = 0 THEN @Now END, @Now, @Username);

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF @NeedApproval = 1
    BEGIN
        INSERT INTO dbo.ApprovalStep
            (RequestId, [Point], Round, StepOrder, WorkflowStepId, RoleCode, Scope, DepartmentGroupCode, ReviseTo,
             AllowReject, Status, StartedAt, CreatedAt)
        SELECT  @RequestId, 'ADDENDUM', @No, ROW_NUMBER() OVER (ORDER BY s.StepOrder), s.WorkflowStepId, s.RoleCode,
                s.Scope, s.DepartmentGroupCode, NULL, s.AllowReject, 'PENDING', NULL, @Now
        FROM    @Steps s;

        UPDATE dbo.ApprovalStep SET StartedAt = @Now
        WHERE  RequestId = @RequestId AND [Point] = 'ADDENDUM' AND Round = @No AND StepOrder = 1;
    END

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, 'ADDENDUM', @Status, @Status,
            LEFT(N'Addendum ' + @Code + ISNULL(N' (ref. ' + @DocumentNo + N')', N'') + N' · IDR '
                 + FORMAT(@PlanCost, N'#,0.##', 'en-US') + N' -> IDR ' + FORMAT(@NewValue, N'#,0.##', 'en-US')
                 + CASE WHEN @NeedApproval = 1 THEN N' · approval required' ELSE N'' END
                 + N' · ' + @Reason, 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewId AS Id, @No AS AddendumNo, @Code AS AddendumCode, @NewStatus AS Status, @NeedApproval AS RequiresApproval;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Addendum_ApprovalAct  (langkah titik ADDENDUM; @Action = APPROVE | REJECT; BR-80, BR-39)
      @StepId = langkah yang ditampilkan ke user (cegah aksi ganda). Alasan wajib untuk REJECT.
      Hasil: SELECT Status (status addendum yang baru).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Addendum_ApprovalAct
    @AddendumId  INT,
    @StepId      INT,
    @Username    NVARCHAR(100),
    @Action      VARCHAR(10),
    @Remarks     NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Action  = UPPER(LTRIM(RTRIM(@Action)));
    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF @Action IS NULL OR @Action NOT IN ('APPROVE', 'REJECT')
        THROW 50072, N'Invalid approval action.', 1;
    IF @Action = 'REJECT' AND @Remarks IS NULL
        THROW 50072, N'Rejection reason is required.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @RequestId INT = (SELECT d.RequestId FROM dbo.ProjectAddendum d WHERE d.Id = @AddendumId);
    DECLARE @ReqStatus VARCHAR(20);

    BEGIN TRANSACTION;

    -- Kunci baris request: aksi bersamaan diproses berurutan (BR-39)
    SELECT  @ReqStatus = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @ReqStatus IS NULL
        THROW 50073, N'Addendum not found.', 1;

    DECLARE @No INT, @AddStatus VARCHAR(20), @Code VARCHAR(50), @Exec VARCHAR(10);
    SELECT  @No = d.AddendumNo, @AddStatus = d.Status, @Code = ISNULL(d.AddendumCode, CAST(d.AddendumNo AS VARCHAR(10))),
            @Exec = d.ExecutionType
    FROM    dbo.ProjectAddendum d
    WHERE   d.Id = @AddendumId;

    DECLARE @StepOrder INT, @StepStatus VARCHAR(10), @StartedAt DATETIME2(3), @AllowReject BIT;
    SELECT  @StepOrder = s.StepOrder, @StepStatus = s.Status, @StartedAt = s.StartedAt, @AllowReject = s.AllowReject
    FROM    dbo.ApprovalStep s
    WHERE   s.Id = @StepId AND s.RequestId = @RequestId AND s.[Point] = 'ADDENDUM' AND s.Round = @No;

    IF @StepOrder IS NULL
        THROW 50073, N'Approval step not found.', 1;
    IF @AddStatus <> 'PENDING_APPROVAL' OR @StepStatus <> 'PENDING' OR @StartedAt IS NULL
       OR @ReqStatus NOT IN ('SCHEDULING', 'IN_PROGRESS')
        THROW 50074, N'This approval step has already been processed.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_ActionableSteps(@Username) a WHERE a.ApprovalStepId = @StepId)
        THROW 50075, N'You are not authorized to process this approval step.', 1;
    IF @Action = 'REJECT' AND @AllowReject = 0
        THROW 50074, N'Rejection is not allowed at this approval step.', 1;

    UPDATE dbo.ApprovalStep
    SET    Status = CASE @Action WHEN 'APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END,
           ActedAt = @Now, ActedBy = @Username, Remarks = @Remarks
    WHERE  Id = @StepId;

    DECLARE @NewStatus VARCHAR(20);

    IF @Action = 'APPROVE'
    BEGIN
        DECLARE @NextOrder INT = (SELECT MIN(StepOrder) FROM dbo.ApprovalStep
                                  WHERE RequestId = @RequestId AND [Point] = 'ADDENDUM' AND Round = @No
                                    AND Status = 'PENDING' AND StepOrder > @StepOrder);
        IF @NextOrder IS NOT NULL
        BEGIN
            SET @NewStatus = 'PENDING_APPROVAL';
            UPDATE dbo.ApprovalStep SET StartedAt = @Now
            WHERE  RequestId = @RequestId AND [Point] = 'ADDENDUM' AND Round = @No AND StepOrder = @NextOrder;
        END
        ELSE
        BEGIN
            -- Disetujui: outsource menunggu kontrak final (BR-87), in-house langsung penyesuaian (BR-82)
            SET @NewStatus = CASE WHEN @Exec = 'OUTSOURCE' THEN 'FINAL_CONTRACT' ELSE 'ADJUSTMENT' END;
            UPDATE dbo.ProjectAddendum SET Status = @NewStatus, ApprovedAt = @Now WHERE Id = @AddendumId;
        END
    END
    ELSE
    BEGIN
        -- Ditolak: addendum batal, nilai lama tetap berlaku (BR-80)
        SET @NewStatus = 'REJECTED';
        UPDATE dbo.ApprovalStep SET Status = 'VOID'
        WHERE  RequestId = @RequestId AND [Point] = 'ADDENDUM' AND Round = @No AND Status = 'PENDING';
        UPDATE dbo.ProjectAddendum SET Status = 'REJECTED', ClosedAt = @Now, ClosedBy = @Username WHERE Id = @AddendumId;
    END

    INSERT INTO dbo.ApprovalHistory (RequestId, ApprovalStepId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, @StepId, @Action, @ReqStatus, @ReqStatus,
            LEFT(N'Addendum ' + @Code + ISNULL(N' · ' + @Remarks, N''), 1000), @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* ---------------------------------------------------------------------
   6b. usp_Addendum_UploadFinalContract  (civil; outsource FINAL_CONTRACT -> ADJUSTMENT; BR-87, Keputusan 18-11-2026)
       Kontrak final bertanda tangan (jenis lampiran ADDENDUM_FINAL). File sudah disimpan aplikasi sebelum SP
       dipanggil (aplikasi menghapus file bila SP gagal). Hasil: SELECT Status ('ADJUSTMENT').
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Addendum_UploadFinalContract
    @AddendumId        INT,
    @Username          NVARCHAR(100),
    @OriginalFileName  NVARCHAR(260),
    @RelativePath      NVARCHAR(400),
    @ContentType       VARCHAR(100),
    @FileSizeBytes     BIGINT,
    @Remarks           NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @OriginalFileName = NULLIF(LTRIM(RTRIM(@OriginalFileName)), N'');
    SET @RelativePath     = NULLIF(LTRIM(RTRIM(@RelativePath)), N'');
    SET @Remarks          = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can upload the signed contract addendum.', 1;
    IF @OriginalFileName IS NULL OR @RelativePath IS NULL OR ISNULL(@FileSizeBytes, 0) <= 0
        THROW 50072, N'Please attach the signed contract addendum.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @RequestId INT = (SELECT d.RequestId FROM dbo.ProjectAddendum d WHERE d.Id = @AddendumId);
    DECLARE @ReqStatus VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT  @ReqStatus = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @ReqStatus IS NULL
        THROW 50073, N'Addendum not found.', 1;

    DECLARE @AddStatus VARCHAR(20), @Code VARCHAR(50);
    SELECT  @AddStatus = d.Status, @Code = ISNULL(d.AddendumCode, CAST(d.AddendumNo AS VARCHAR(10)))
    FROM    dbo.ProjectAddendum d WITH (UPDLOCK, ROWLOCK)
    WHERE   d.Id = @AddendumId;

    IF @AddStatus <> 'FINAL_CONTRACT' OR @ReqStatus NOT IN ('SCHEDULING', 'IN_PROGRESS')
        THROW 50074, N'This addendum is not waiting for the signed contract.', 1;

    -- Aturan file dari master Jenis Lampiran (MD-09): ADDENDUM_FINAL
    DECLARE @TypeId INT, @Ext VARCHAR(200), @MaxMB INT, @FileExt VARCHAR(20);
    SELECT  @TypeId = t.Id, @Ext = t.AllowedExtensions, @MaxMB = t.MaxSizeMB
    FROM    dbo.AttachmentType t
    WHERE   t.Code = 'ADDENDUM_FINAL' AND t.IsActive = 1;

    IF @TypeId IS NULL
        THROW 50072, N'The signed contract attachment type is not configured. Please contact the administrator.', 1;

    SET @FileExt = CASE WHEN CHARINDEX('.', @OriginalFileName) = 0 THEN ''
                        ELSE LOWER(RIGHT(@OriginalFileName, CHARINDEX('.', REVERSE(@OriginalFileName)) - 1)) END;
    IF @FileExt = '' OR CHARINDEX(',' + @FileExt + ',', ',' + @Ext + ',') = 0
        THROW 50072, N'File type is not allowed for the signed contract.', 1;
    IF @FileSizeBytes > CAST(@MaxMB AS BIGINT) * 1048576
        THROW 50072, N'File size exceeds the maximum for the signed contract.', 1;

    UPDATE dbo.ProjectAddendum
    SET    Status = 'ADJUSTMENT', FinalAttachmentTypeId = @TypeId, FinalFileName = @OriginalFileName,
           FinalRelativePath = @RelativePath, FinalContentType = ISNULL(NULLIF(@ContentType, ''), 'application/octet-stream'),
           FinalFileSizeBytes = @FileSizeBytes, FinalUploadedAt = @Now, FinalUploadedBy = @Username
    WHERE  Id = @AddendumId;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, 'ADDENDUM_CONTRACT', @ReqStatus, @ReqStatus,
            LEFT(N'Addendum ' + @Code + N' · signed contract uploaded' + ISNULL(N' · ' + @Remarks, N''), 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT CAST('ADJUSTMENT' AS VARCHAR(20)) AS Status;
END
GO

/* ---------------------------------------------------------------------
   7. usp_Addendum_SaveAdjustment  (civil; addendum ADJUSTMENT -> COMPLETED; BR-82 s.d. BR-85)
      @ActionPlanJson / @EstimateJson: format sama dengan usp_Request_SaveSchedule / usp_Request_SaveCostEstimate.
      Satu transaksi: plan cost = nilai baru, schedule, estimasi, cek kelengkapan, status biaya + progress.
      Hasil: SELECT Status ('COMPLETED').
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Addendum_SaveAdjustment
    @AddendumId        INT,
    @Username          NVARCHAR(100),
    @ProjectStartDate  DATE,
    @ActionPlanJson    NVARCHAR(MAX),
    @EstimateJson      NVARCHAR(MAX),
    @Remarks           NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can adjust the schedule for an addendum.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Msg NVARCHAR(2048);
    DECLARE @RequestId INT = (SELECT d.RequestId FROM dbo.ProjectAddendum d WHERE d.Id = @AddendumId);
    DECLARE @ReqStatus VARCHAR(20), @OldPlanCost DECIMAL(18, 2), @OldPercent DECIMAL(5, 2);

    BEGIN TRANSACTION;

    SELECT  @ReqStatus = r.Status, @OldPlanCost = r.PlanCost, @OldPercent = r.ProgressPercent
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @ReqStatus IS NULL
        THROW 50073, N'Addendum not found.', 1;

    DECLARE @No INT, @AddStatus VARCHAR(20), @NewValue DECIMAL(18, 2), @Code VARCHAR(50);
    SELECT  @No = d.AddendumNo, @AddStatus = d.Status, @NewValue = d.NewValue,
            @Code = ISNULL(d.AddendumCode, CAST(d.AddendumNo AS VARCHAR(10)))
    FROM    dbo.ProjectAddendum d WITH (UPDLOCK, ROWLOCK)
    WHERE   d.Id = @AddendumId;

    IF @AddStatus <> 'ADJUSTMENT' OR @ReqStatus NOT IN ('SCHEDULING', 'IN_PROGRESS')
        THROW 50074, N'This addendum is not awaiting adjustment.', 1;

    -- Plan cost = nilai baru lebih dulu, agar validasi estimasi memakai nilai baru (BR-12, BR-13)
    UPDATE dbo.ProjectRequest SET PlanCost = @NewValue WHERE Id = @RequestId;

    EXEC dbo.usp_Request_SaveSchedule @Id = @RequestId, @Username = @Username, @ProjectStartDate = @ProjectStartDate,
         @ActionPlanJson = @ActionPlanJson, @AddendumId = @AddendumId;

    EXEC dbo.usp_Request_SaveCostEstimate @Id = @RequestId, @Username = @Username, @EstimateJson = @EstimateJson,
         @AddendumId = @AddendumId;

    -- BR-82: penyesuaian wajib lengkap (juga saat SCHEDULING)
    DECLARE @TotalWeight DECIMAL(9, 2) = ISNULL((SELECT SUM(a.WeightPercent) FROM dbo.ProjectActionPlan a WHERE a.RequestId = @RequestId), 0);
    DECLARE @TotalEstimate DECIMAL(18, 2) = ISNULL((SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = @RequestId), 0);

    IF @TotalWeight <> 100
    BEGIN
        SET @Msg = N'Total action plan weight must be 100% (currently ' + FORMAT(@TotalWeight, N'0.##', 'en-US') + N'%).';
        THROW 50072, @Msg, 1;
    END
    IF @TotalEstimate <> @NewValue
    BEGIN
        SET @Msg = N'Total cost estimate must equal the new value (IDR ' + FORMAT(@NewValue, N'#,0.##', 'en-US') + N').';
        THROW 50072, @Msg, 1;
    END

    -- Status biaya dihitung ulang dengan estimasi baru (SCHEDULING juga, agar konsisten bila sudah ada actual)
    IF @ReqStatus = 'SCHEDULING' AND OBJECT_ID(N'dbo.usp_Request_RefreshCostStatus', N'P') IS NOT NULL
        EXEC dbo.usp_Request_RefreshCostStatus @Id = @RequestId, @Username = @Username;

    UPDATE dbo.ProjectAddendum
    SET    Status = 'COMPLETED', ClosedAt = @Now, ClosedBy = @Username
    WHERE  Id = @AddendumId;

    DECLARE @NewPercent DECIMAL(5, 2) = (SELECT r.ProgressPercent FROM dbo.ProjectRequest r WHERE r.Id = @RequestId);

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, 'ADDENDUM_ADJUST', @ReqStatus, @ReqStatus,
            LEFT(N'Addendum ' + @Code + N' completed · Plan cost IDR '
                 + FORMAT(ISNULL(@OldPlanCost, 0), N'#,0.##', 'en-US') + N' -> IDR ' + FORMAT(@NewValue, N'#,0.##', 'en-US')
                 + CASE WHEN ISNULL(@OldPercent, -1) <> ISNULL(@NewPercent, -1)
                        THEN N' · Progress ' + FORMAT(ISNULL(@OldPercent, 0), N'0.##', 'en-US') + N'% -> '
                             + FORMAT(ISNULL(@NewPercent, 0), N'0.##', 'en-US') + N'%'
                        ELSE N'' END
                 + ISNULL(N' · ' + @Remarks, N''), 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT CAST('COMPLETED' AS VARCHAR(20)) AS Status;
END
GO

/* ---------------------------------------------------------------------
   8. usp_Addendum_GetByRequest  (Details; BR-86)
      Result 1: addendum (terbaru di atas); 0 baris = tidak ada / tidak boleh melihat
      Result 2: langkah approval semua addendum (Round = AddendumNo)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Addendum_GetByRequest
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
                            AND  (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)))
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeAddendum(r.ExecutionType, @Username)))
             THEN 1 ELSE 0 END;

    SELECT  d.Id, d.RequestId, d.AddendumNo, d.AddendumCode, d.ExecutionType, d.DocumentNo, d.AddendumDate, d.PreviousValue, d.NewValue,
            d.Reason, d.RequiresApproval, d.Status, d.AttachmentTypeId, t.Name AS AttachmentTypeName,
            d.OriginalFileName, d.ContentType, d.FileSizeBytes, d.ApprovedAt, d.ClosedAt, d.ClosedBy,
            ce.FullName AS ClosedByName, d.CreatedAt, d.CreatedBy, e.FullName AS CreatedByName,
            ft.Name AS FinalAttachmentTypeName, d.FinalFileName, d.FinalFileSizeBytes, d.FinalUploadedAt, d.FinalUploadedBy,
            fe.FullName AS FinalUploadedByName
    FROM    dbo.ProjectAddendum d
            JOIN dbo.AttachmentType t        ON t.Id = d.AttachmentTypeId
            LEFT JOIN dbo.AttachmentType ft  ON ft.Id = d.FinalAttachmentTypeId
            LEFT JOIN home..users fu         ON fu.Username = d.FinalUploadedBy
            LEFT JOIN home..app_employees fe ON fe.EmployeeCode = fu.EmployeeCode
            LEFT JOIN home..users u          ON u.Username = d.CreatedBy
            LEFT JOIN home..app_employees e  ON e.EmployeeCode = u.EmployeeCode
            LEFT JOIN home..users cu         ON cu.Username = d.ClosedBy
            LEFT JOIN home..app_employees ce ON ce.EmployeeCode = cu.EmployeeCode
    WHERE   d.RequestId = @RequestId AND @Visible = 1
    ORDER BY d.AddendumNo DESC;

    SELECT  s.Id, s.Round AS AddendumNo, s.StepOrder, s.RoleCode, h.Description AS RoleName, s.AllowReject,
            s.Status, s.StartedAt, s.ActedAt, s.ActedBy, ae.FullName AS ActedByName, s.Remarks,
            CAST(CASE WHEN s.Status = 'PENDING' AND s.StartedAt IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsCurrent
    FROM    dbo.ApprovalStep s
            LEFT JOIN dbo.HierarchyLevel h   ON h.[Role] = s.RoleCode
            LEFT JOIN home..users au         ON au.Username = s.ActedBy
            LEFT JOIN home..app_employees ae ON ae.EmployeeCode = au.EmployeeCode
    WHERE   s.RequestId = @RequestId AND s.[Point] = 'ADDENDUM' AND @Visible = 1
    ORDER BY s.Round DESC, s.StepOrder;
END
GO

/* ---------------------------------------------------------------------
   9. usp_Addendum_GetFile  (download; hak lihat sama dengan usp_Addendum_GetByRequest)
      @Kind: DRAFT (default) = file saat raise (draft kontrak / BOQ revisi); FINAL = kontrak final bertanda tangan.
      0 baris = tidak ada / tidak boleh melihat / file FINAL belum diupload.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Addendum_GetFile
    @Id        INT,
    @Username  NVARCHAR(100),
    @Kind      VARCHAR(10) = 'DRAFT'
AS
BEGIN
    SET NOCOUNT ON;

    SET @Kind = CASE WHEN UPPER(@Kind) = 'FINAL' THEN 'FINAL' ELSE 'DRAFT' END;

    SELECT  d.Id, d.RequestId, d.AddendumNo, d.AddendumCode,
            CASE WHEN @Kind = 'FINAL' THEN d.FinalFileName      ELSE d.OriginalFileName END AS OriginalFileName,
            CASE WHEN @Kind = 'FINAL' THEN d.FinalRelativePath  ELSE d.RelativePath     END AS RelativePath,
            CASE WHEN @Kind = 'FINAL' THEN d.FinalContentType   ELSE d.ContentType      END AS ContentType,
            CASE WHEN @Kind = 'FINAL' THEN d.FinalFileSizeBytes ELSE d.FileSizeBytes    END AS FileSizeBytes
    FROM    dbo.ProjectAddendum d
            JOIN dbo.ProjectRequest r ON r.Id = d.RequestId
    WHERE   d.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)))
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeAddendum(d.ExecutionType, @Username))
      AND   EXISTS (SELECT 1 FROM dbo.fn_Request_VisibleToUser(r.Status, r.DepartmentID, @Username))   -- RL-05 FAT (Request.sql)
      AND   (@Kind = 'DRAFT' OR d.FinalRelativePath IS NOT NULL);
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: request OUTSOURCE IN_PROGRESS (@Out) dengan schedule + estimasi + progress minggu ini,
   dan request INHOUSE SCHEDULING atau IN_PROGRESS (@In). File dummy: path palsu cukup untuk uji SQL
   (unduhan file palsu akan gagal di aplikasi; batalkan data uji sebelum uji aplikasi bila perlu).

   DECLARE @Out INT = <id outsource>, @In INT = <id inhouse>,
           @Civil NVARCHAR(100) = N'<user civil>', @Purch NVARCHAR(100) = N'<user purchasing>',
           @Gm NVARCHAR(100) = N'<user gm ABL>', @Emp NVARCHAR(100) = N'<user emp dept project>';

   -- 0) Seed dan constraint
   SELECT * FROM dbo.WorkflowStep WHERE [Point] = 'ADDENDUM';                          -- ABL gm, NKM director
   SELECT Code, Name, Stage FROM dbo.AttachmentType WHERE Stage = 'ADDENDUM';          -- ADDENDUM (Draft...), ADDENDUM_FINAL, BOQ_REVISION
   SELECT Id, Status, ExecutionType, PlanCost, ProgressPercent FROM dbo.ProjectRequest WHERE Id IN (@Out, @In);

   -- 1) Purchasing raise -> 50075 (hanya civil, 18-11-2026); data kurang -> 50072 (tanpa nomor referensi); ekstensi salah -> 50072
   BEGIN TRY EXEC dbo.usp_Addendum_Create @RequestId = @Out, @Username = @Purch, @DocumentNo = NULL, @AddendumDate = '2026-11-17',
        @NewValue = 5000000, @Reason = N'Extra work', @OriginalFileName = N'draft.pdf', @RelativePath = N'Addendum\draft.pdf',
        @ContentType = 'application/pdf', @FileSizeBytes = 1000;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Addendum_Create @RequestId = @Out, @Username = @Civil, @DocumentNo = N' ', @AddendumDate = NULL,
        @NewValue = 0, @Reason = NULL, @OriginalFileName = NULL, @RelativePath = NULL, @ContentType = NULL, @FileSizeBytes = 0;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (list, tanpa Reference)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Addendum_Create @RequestId = @Out, @Username = @Civil, @DocumentNo = N'ADD-01', @AddendumDate = '2026-11-17',
        @NewValue = 5000000, @Reason = N'Extra work', @OriginalFileName = N'add.exe', @RelativePath = N'Addendum\test.exe',
        @ContentType = 'application/octet-stream', @FileSizeBytes = 1000;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (file type)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Outsource nilai NAIK (civil + draft kontrak) -> PENDING_APPROVAL, langkah gm aktif; addendum kedua -> 50074;
   --    schedule biasa -> 50074; purchasing tetap bisa melihat (GetByRequest)
   EXEC dbo.usp_Addendum_Create @RequestId = @Out, @Username = @Civil, @DocumentNo = NULL, @AddendumDate = '2026-11-17',
        @NewValue = 5000000, @Reason = N'Extra work', @OriginalFileName = N'draft.pdf', @RelativePath = N'Addendum\draft.pdf',
        @ContentType = 'application/pdf', @FileSizeBytes = 1000;                       -- (sesuaikan nilai > PlanCost)
   EXEC dbo.usp_Addendum_GetByRequest @RequestId = @Out, @Username = @Purch;
   SELECT * FROM dbo.fn_User_ActionableSteps(@Gm) WHERE RequestId = @Out;              -- 1 baris, Point ADDENDUM
   SELECT * FROM dbo.fn_User_Tasks(@Gm) WHERE RequestId = @Out;                        -- APPROVAL
   BEGIN TRY EXEC dbo.usp_Addendum_Create @RequestId = @Out, @Username = @Civil, @DocumentNo = N'ADD-02', @AddendumDate = '2026-11-17',
        @NewValue = 6000000, @Reason = N'X', @OriginalFileName = N'add.pdf', @RelativePath = N'Addendum\test2.pdf',
        @ContentType = 'application/pdf', @FileSizeBytes = 1000;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '2a expect 50074 (open addendum)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SaveCostEstimate @Id = @Out, @Username = @Civil, @EstimateJson = N'[]', @Reason = N'x';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '2b expect 50074 (locked)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 3) Hak lihat (BR-86): emp -> 0 baris untuk outsource; GetFile emp -> 0 baris
   EXEC dbo.usp_Addendum_GetByRequest @RequestId = @Out, @Username = @Emp;

   -- 4) Approve oleh gm -> FINAL_CONTRACT (outsource, BR-87); tugas ADDENDUM civil muncul (setelah Task.sql)
   DECLARE @Add INT = (SELECT Id FROM dbo.ProjectAddendum WHERE RequestId = @Out AND Status = 'PENDING_APPROVAL');
   DECLARE @Step INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Gm) WHERE RequestId = @Out AND [Point] = 'ADDENDUM');
   BEGIN TRY EXEC dbo.usp_Addendum_ApprovalAct @AddendumId = @Add, @StepId = @Step, @Username = @Gm, @Action = 'REJECT';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4a expect 50072 (reason)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Addendum_ApprovalAct @AddendumId = @Add, @StepId = @Step, @Username = @Gm, @Action = 'APPROVE', @Remarks = N'OK';
   SELECT * FROM dbo.fn_User_Tasks(@Civil) WHERE RequestId = @Out;                     -- ADDENDUM

   -- 4b) Kontrak final: penyesuaian sebelum upload -> 50074; purchasing upload -> 50075; civil upload -> ADJUSTMENT
   BEGIN TRY EXEC dbo.usp_Addendum_SaveAdjustment @AddendumId = @Add, @Username = @Civil, @ProjectStartDate = '2026-11-02',
        @ActionPlanJson = N'[]', @EstimateJson = N'[]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4b expect 50074 (final contract first)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Addendum_UploadFinalContract @AddendumId = @Add, @Username = @Purch, @OriginalFileName = N'signed.pdf',
        @RelativePath = N'Addendum\signed.pdf', @ContentType = 'application/pdf', @FileSizeBytes = 1000;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4c expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Addendum_UploadFinalContract @AddendumId = @Add, @Username = @Civil, @OriginalFileName = N'signed.pdf',
        @RelativePath = N'Addendum\signed.pdf', @ContentType = 'application/pdf', @FileSizeBytes = 1000;   -- ADJUSTMENT
   EXEC dbo.usp_Addendum_GetFile @Id = @Add, @Username = @Civil, @Kind = 'FINAL';      -- 1 baris signed.pdf

   -- 5) Penyesuaian (civil): ambil action plan + estimasi sekarang lewat GetSchedule, lalu
   --    5a) hapus action plan yang punya progress > 0 -> 50072; ubah nama / tanggal mulai -> 50072
   --    5b) ubah estimasi bulan lalu -> 50072; total estimasi <> nilai baru -> 50072; bobot <> 100 -> 50072
   --    5c) valid -> COMPLETED; PlanCost = nilai baru; riwayat ADDENDUM_ADJUST (progress lama -> baru bila bobot berubah)
   EXEC dbo.usp_Request_GetSchedule @RequestId = @Out, @Username = @Civil;
   --DECLARE @Plans NVARCHAR(MAX) = N'[{"id":<A1>,"name":"<nama sama>","weight":30,"start":"<mulai sama>","end":"2026-12-31"},
   --                                  {"id":<A2>,"name":"...","weight":50,"start":"...","end":"..."},
   --                                  {"id":0,"name":"Additional works","weight":20,"start":"2026-12-01","end":"2026-12-20"}]';
   --DECLARE @Est NVARCHAR(MAX) = N'[{"month":"2026-11-01","amount":<sama atau baru>},{"month":"2026-12-01","amount":<sisa>}]';
   --EXEC dbo.usp_Addendum_SaveAdjustment @AddendumId = @Add, @Username = @Civil, @ProjectStartDate = '<sama>',
   --     @ActionPlanJson = @Plans, @EstimateJson = @Est, @Remarks = N'Adjusted per addendum 1';
   SELECT Id, PlanCost, ProgressPercent, PlanProgressPercent, ScheduleStatus, CostStatus FROM dbo.ProjectRequest WHERE Id = @Out;
   EXEC dbo.usp_Request_GetHistory @RequestId = @Out, @Username = @Civil;              -- ADDENDUM, APPROVE, ADDENDUM_CONTRACT, ADDENDUM_ADJUST

   -- 6) In-house nilai TURUN -> langsung ADJUSTMENT (tanpa approval, tanpa kontrak final); outsource nilai turun -> FINAL_CONTRACT
   --EXEC dbo.usp_Addendum_Create @RequestId = @In, @Username = @Civil, @DocumentNo = N'BOQ-REV-1', @AddendumDate = '2026-11-17',
   --     @NewValue = <lebih kecil dari PlanCost>, @Reason = N'Scope reduced', @OriginalFileName = N'boq.xlsx',
   --     @RelativePath = N'Addendum\boq.xlsx', @ContentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', @FileSizeBytes = 1000;
   --EXEC dbo.usp_Addendum_GetByRequest @RequestId = @In, @Username = @Emp;            -- in-house: emp boleh lihat

   -- 7) Reject (addendum lain yang PENDING_APPROVAL) -> REJECTED, PlanCost tetap, schedule tidak terkunci lagi
   --EXEC dbo.usp_Addendum_ApprovalAct @AddendumId = <id>, @StepId = <step>, @Username = @Gm, @Action = 'REJECT', @Remarks = N'Not justified';

   -- 8) BR-83 di luar addendum (In Progress, perubahan biasa): action plan 0% boleh dihapus; yang > 0% -> 50072
   -- 9) Bersihkan data uji (opsional, DB dev):
   --DELETE FROM dbo.ApprovalHistory WHERE RequestId = @Out AND Action IN ('ADDENDUM', 'ADDENDUM_CONTRACT', 'ADDENDUM_ADJUST');
   --DELETE h FROM dbo.ApprovalHistory h JOIN dbo.ApprovalStep s ON s.Id = h.ApprovalStepId WHERE s.RequestId = @Out AND s.[Point] = 'ADDENDUM';
   --DELETE FROM dbo.ApprovalStep WHERE RequestId = @Out AND [Point] = 'ADDENDUM';
   --DELETE FROM dbo.ProjectAddendum WHERE RequestId = @Out;
   ===================================================================== */
GO
/* ---------- end RequestAddendum.sql ---------- */
/* ---------- begin RequestBapp.sql ---------- */
PRINT N'[skema] RequestBapp.sql';
GO
/* =====================================================================
   RequestBapp.sql  -  BAPP online, approval BAPP, Project Closed, cetak Berita Acara
                       (T6-1; PRD 3.4, 3.9, 5.1, 5.2, BR-20, BR-21, BR-37, BR-88, BR-89, BR-90, BR-93, BR-94, BR-95,
                       RL-13, ST-11, ST-12, ST-13)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER, sp_set_session_context)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST dengan urutan:
               1. Role.sql             (role dgo di HierarchyLevel)
               2. Scope.sql            (dgo: lingkup Company seperti fat)
               3. Request.sql          (fn_User_CanSeeBapp termasuk dgo; lampiran tahap BAPP)
               4. RequestActualCost.sql, RequestAddendum.sql (hak lihat dgo = fat)
               5. RequestApproval.sql  (usp_Request_ApprovalAct: titik BAPP hanya lewat usp_Bapp_ApprovalAct)
               6. RequestBapp.sql      (file ini)
               7. Task.sql             (tugas BAPP untuk civil)
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Alur (Keputusan 18-11-2026, diubah: penutupan online tanpa tanda tangan basah; lihat docs/PRD-log.md):
     1. IN_PROGRESS -> Civil menerbitkan BAPP online (usp_Bapp_Issue; BR-88): syarat semua action plan 100% + tanggal
        selesai aktual dan tidak ada addendum terbuka. Isian: tanggal BAPP, lingkup pekerjaan, catatan (opsional);
        foto dokumentasi wajib (BAPP_PHOTO_INITIAL / _PROGRESS / _FINAL, masing-masing minimal satu; 18-11-2026). Nomor BAPP otomatis (BR-95). Langkah titik BAPP di-snapshot
        (BR-37) -> BAPP_REVIEW.
     2. Approver lewat usp_Bapp_ApprovalAct (default ABL: kabag -> fat -> dgo -> gm; NKM: kabag -> fat -> director):
          kabag : Hasil pemeriksaan wajib saat Accept (SESUAI | SESUAI_CATATAN); BELUM_SESUAI hanya dengan No (BR-89);
                  catatan wajib untuk SESUAI_CATATAN dan BELUM_SESUAI
          fat   : Accept wajib konfirmasi "tidak ada outstanding biaya/tagihan" (BR-93)
          dgo   : Accept wajib konfirmasi "status project CLOSED" (BR-93); NKM tanpa dgo -> diisi sistem saat Closed
          Accept langkah terakhir -> CLOSED; No (alasan wajib) -> IN_PROGRESS, terbit ulang = ronde baru, nomor sama.
     3. Setelah CLOSED, Civil mencetak Berita Acara (usp_Bapp_GetPrintData; BR-94).
   Lihat (matriks 5.2 baris BAPP): kabag, mo, civil, fat, dgo, gm, director, administrator (fn_User_CanSeeBapp).
   Error   : 50072 = Input wajib kosong / tidak valid / syarat belum lengkap
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Workflow BAPP ABL: kabag -> fat -> dgo -> gm (BR-20, 18-11-2026)
      Hanya mengubah isi default (kabag 1, fat 2, gm 3, tanpa dgo); isi yang sudah diubah administrator dibiarkan.
   --------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.WorkflowStep WHERE CoCode = 'ABL' AND [Point] = 'BAPP' AND StepOrder = 3 AND RoleCode = 'gm')
   AND NOT EXISTS (SELECT 1 FROM dbo.WorkflowStep WHERE CoCode = 'ABL' AND [Point] = 'BAPP' AND (RoleCode = 'dgo' OR StepOrder = 4))
BEGIN
    UPDATE dbo.WorkflowStep
    SET    StepOrder = 4, UpdatedAt = SYSDATETIME(), UpdatedBy = N'seed'
    WHERE  CoCode = 'ABL' AND [Point] = 'BAPP' AND StepOrder = 3 AND RoleCode = 'gm';

    INSERT INTO dbo.WorkflowStep (CoCode, [Point], StepOrder, RoleCode, Scope, Category, DepartmentGroupCode, ReviseTo, AllowReject, CreatedBy)
    VALUES ('ABL', 'BAPP', 3, 'dgo', 'PLANT', NULL, NULL, 'CIVIL', 0, N'seed');
END
GO

/* ---------------------------------------------------------------------
   2. Jenis lampiran tahap BAPP (MD-09)
      - BAPP (dokumen): tidak wajib lagi karena form BAPP dibuat sistem (BR-88, 18-11-2026). Flag wajib seed
        dinolkan hanya bila masih bawaan seed (1/1/1).
      - Foto dokumentasi Lampiran 2 (wajib sejak 18-11-2026, dicek usp_Bapp_Issue): awal, proses, hasil akhir.
        Flag wajib per kategori diisi 1 agar kartu Attachments menampilkan 'required'.
   --------------------------------------------------------------------- */
UPDATE dbo.AttachmentType
SET    IsMandatoryCapex = 0, IsMandatoryOpex = 0, IsMandatoryLve = 0, UpdatedAt = SYSDATETIME(), UpdatedBy = N'seed'
WHERE  Code = 'BAPP' AND IsMandatoryCapex = 1 AND IsMandatoryOpex = 1 AND IsMandatoryLve = 1;
GO

MERGE dbo.AttachmentType AS t
USING (VALUES
        ('BAPP_PHOTO_INITIAL',  N'Photo - Initial',  'BAPP', 'jpg,jpeg,png', 10),
        ('BAPP_PHOTO_PROGRESS', N'Photo - Progress', 'BAPP', 'jpg,jpeg,png', 10),
        ('BAPP_PHOTO_FINAL',    N'Photo - Final',    'BAPP', 'jpg,jpeg,png', 10)
      ) AS s (Code, Name, Stage, AllowedExtensions, MaxSizeMB)
   ON t.Code = s.Code
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, CreatedBy)
    VALUES (s.Code, s.Name, s.Stage, s.AllowedExtensions, s.MaxSizeMB, 1, 1, 1, N'seed');
GO

-- 18-11-2026: foto menjadi wajib; baris seed lama dengan flag 0 diubah ke 1
UPDATE dbo.AttachmentType
SET    IsMandatoryCapex = 1, IsMandatoryOpex = 1, IsMandatoryLve = 1, UpdatedAt = SYSDATETIME(), UpdatedBy = N'seed'
WHERE  Code IN ('BAPP_PHOTO_INITIAL', 'BAPP_PHOTO_PROGRESS', 'BAPP_PHOTO_FINAL')
  AND  IsMandatoryCapex = 0 AND IsMandatoryOpex = 0 AND IsMandatoryLve = 0 AND CreatedBy = N'seed';
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.ProjectBapp  (satu baris per penerbitan BAPP; Round = ronde ApprovalStep titik BAPP)
      Status: REVIEW | RETURNED (No) | ACCEPTED (langkah terakhir, Closed)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectBapp', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectBapp
    (
        Id                 INT IDENTITY(1,1) NOT NULL,
        RequestId          INT            NOT NULL,
        Round              INT            NOT NULL,
        BappNo             NVARCHAR(50)   NULL,          -- otomatis (BR-95)
        BappDate           DATE           NOT NULL,
        ScopeOfWork        NVARCHAR(2000) NULL,          -- lingkup pekerjaan (bagian C), diisi Civil
        Remarks            NVARCHAR(1000) NULL,
        Status             VARCHAR(10)    NOT NULL CONSTRAINT DF_ProjectBapp_Status DEFAULT ('REVIEW'),
        IssuedAt           DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectBapp_IssuedAt DEFAULT (SYSDATETIME()),
        IssuedBy           NVARCHAR(100)  NOT NULL,
        InspectionResult   VARCHAR(20)    NULL,          -- bagian D, diisi kabag
        InspectionNotes    NVARCHAR(1000) NULL,
        InspectedAt        DATETIME2(3)   NULL,
        InspectedBy        NVARCHAR(100)  NULL,
        NoOutstandingAt    DATETIME2(3)   NULL,          -- bagian F, konfirmasi fat
        NoOutstandingBy    NVARCHAR(100)  NULL,
        ClosedStatusAt     DATETIME2(3)   NULL,          -- bagian F, konfirmasi dgo / sistem (NKM)
        ClosedStatusBy     NVARCHAR(100)  NULL,
        ClosedAt           DATETIME2(3)   NULL,          -- RETURNED / ACCEPTED
        ClosedBy           NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectBapp PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectBapp_Round UNIQUE (RequestId, Round),
        CONSTRAINT FK_ProjectBapp_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT CK_ProjectBapp_Status CHECK (Status IN ('REVIEW', 'RETURNED', 'ACCEPTED')),
        CONSTRAINT CK_ProjectBapp_Inspection CHECK (InspectionResult IS NULL OR InspectionResult IN ('SESUAI', 'SESUAI_CATATAN', 'BELUM_SESUAI'))
    );
END
GO

-- Migrasi 18-11-2026 (BAPP online): kolom isian form
IF COL_LENGTH(N'dbo.ProjectBapp', N'ScopeOfWork') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectBapp ADD
        ScopeOfWork       NVARCHAR(2000) NULL,
        InspectionResult  VARCHAR(20)    NULL,
        InspectionNotes   NVARCHAR(1000) NULL,
        InspectedAt       DATETIME2(3)   NULL,
        InspectedBy       NVARCHAR(100)  NULL,
        NoOutstandingAt   DATETIME2(3)   NULL,
        NoOutstandingBy   NVARCHAR(100)  NULL,
        ClosedStatusAt    DATETIME2(3)   NULL,
        ClosedStatusBy    NVARCHAR(100)  NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ProjectBapp_Inspection')
BEGIN
    ALTER TABLE dbo.ProjectBapp ADD CONSTRAINT CK_ProjectBapp_Inspection
        CHECK (InspectionResult IS NULL OR InspectionResult IN ('SESUAI', 'SESUAI_CATATAN', 'BELUM_SESUAI'));
END
GO

/* ---------------------------------------------------------------------
   4. TABLE dbo.BappNoSequence  (BR-95: NNN per Company per tahun)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.BappNoSequence', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BappNoSequence
    (
        CoCode     VARCHAR(10)  NOT NULL,
        SeqYear    SMALLINT     NOT NULL,
        LastNo     INT          NOT NULL,
        UpdatedAt  DATETIME2(3) NOT NULL CONSTRAINT DF_BappNoSequence_UpdatedAt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_BappNoSequence PRIMARY KEY CLUSTERED (CoCode, SeqYear)
    );
END
GO

/* ---------------------------------------------------------------------
   5. usp_Bapp_Issue  (civil; IN_PROGRESS -> BAPP_REVIEW; BR-88, BR-95, BR-37, BR-81)
      Hasil: SELECT Status, BappNo.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Bapp_Issue
    @RequestId    INT,
    @Username     NVARCHAR(100),
    @BappDate     DATE,
    @ScopeOfWork  NVARCHAR(MAX),
    @Remarks      NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @ScopeOfWork = NULLIF(LTRIM(RTRIM(@ScopeOfWork)), N'');
    SET @Remarks     = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can issue the BAPP.', 1;
    IF @BappDate IS NULL
        THROW 50072, N'BAPP date is required.', 1;
    IF @ScopeOfWork IS NULL
        THROW 50072, N'Scope of work is required.', 1;
    IF LEN(@ScopeOfWork) > 2000
        THROW 50072, N'Scope of work must be at most 2000 characters.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @CoCode VARCHAR(10), @Category VARCHAR(10), @DeptId INT;

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @CoCode = r.CoCode, @Category = r.Category, @DeptId = r.DepartmentID
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'IN_PROGRESS'
        THROW 50074, N'The BAPP can only be issued while the project is in progress.', 1;

    -- BR-81: tidak ada addendum terbuka
    IF OBJECT_ID(N'dbo.ProjectAddendum', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.ProjectAddendum d
                   WHERE d.RequestId = @RequestId AND d.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT'))
        THROW 50074, N'Complete or reject the open addendum before issuing the BAPP.', 1;

    -- BR-88: semua action plan 100% + tanggal selesai aktual (dokumen BAPP tidak diupload lagi; form dibuat sistem)
    IF NOT EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a WHERE a.RequestId = @RequestId)
       OR EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a
                  WHERE a.RequestId = @RequestId AND (a.ProgressPercent < 100 OR a.ActualEndDate IS NULL))
        THROW 50072, N'Please complete before issuing the BAPP: all action plans at 100% with an actual end date (save the weekly progress first).', 1;

    -- BR-88 (diubah 18-11-2026): foto dokumentasi wajib (awal, proses, hasil akhir)
    DECLARE @MissingPhotos NVARCHAR(500) = N'';
    SELECT @MissingPhotos += N', ' + t.Name
    FROM   dbo.AttachmentType t
    WHERE  t.Code IN ('BAPP_PHOTO_INITIAL', 'BAPP_PHOTO_PROGRESS', 'BAPP_PHOTO_FINAL')
      AND  NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a
                       WHERE a.RequestId = @RequestId AND a.AttachmentTypeId = t.Id AND a.IsActive = 1)
    ORDER BY CHARINDEX(',' + t.Code + ',', ',BAPP_PHOTO_INITIAL,BAPP_PHOTO_PROGRESS,BAPP_PHOTO_FINAL,');

    IF @MissingPhotos <> N''
    BEGIN
        DECLARE @PhotoMsg NVARCHAR(2048) = N'Please upload the documentation photos before issuing the BAPP: ' + STUFF(@MissingPhotos, 1, 2, N'') + N'.';
        THROW 50072, @PhotoMsg, 1;
    END

    -- BR-95: nomor BAPP; terbit ulang memakai nomor ronde sebelumnya
    DECLARE @BappNo NVARCHAR(50) = (SELECT TOP (1) b.BappNo FROM dbo.ProjectBapp b
                                    WHERE b.RequestId = @RequestId AND b.BappNo IS NOT NULL ORDER BY b.Round DESC);
    IF @BappNo IS NULL
    BEGIN
        DECLARE @Yr SMALLINT = YEAR(@BappDate), @Next INT;

        UPDATE dbo.BappNoSequence WITH (UPDLOCK, HOLDLOCK)
        SET    @Next = LastNo = LastNo + 1, UpdatedAt = @Now
        WHERE  CoCode = @CoCode AND SeqYear = @Yr;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @Next = 1;
            INSERT INTO dbo.BappNoSequence (CoCode, SeqYear, LastNo) VALUES (@CoCode, @Yr, @Next);
        END

        SET @BappNo = RIGHT(N'00' + CAST(@Next AS NVARCHAR(10)), CASE WHEN @Next > 999 THEN LEN(CAST(@Next AS NVARCHAR(10))) ELSE 3 END)
                    + N'/BAPP/' + @CoCode + N'/'
                    + CHOOSE(MONTH(@BappDate), N'I', N'II', N'III', N'IV', N'V', N'VI', N'VII', N'VIII', N'IX', N'X', N'XI', N'XII')
                    + N'/' + CAST(@Yr AS NVARCHAR(4));
    END

    -- Snapshot langkah titik BAPP: ronde baru (BR-37, BR-52)
    DECLARE @Round INT = ISNULL((SELECT MAX(Round) FROM dbo.ApprovalStep WHERE RequestId = @RequestId AND [Point] = 'BAPP'), 0) + 1;

    UPDATE dbo.ApprovalStep SET Status = 'VOID'
    WHERE  RequestId = @RequestId AND [Point] = 'BAPP' AND Status = 'PENDING';

    INSERT INTO dbo.ApprovalStep
        (RequestId, [Point], Round, StepOrder, WorkflowStepId, RoleCode, Scope, DepartmentGroupCode, ReviseTo, AllowReject)
    SELECT  @RequestId, 'BAPP', @Round, w.StepOrder, w.Id, w.RoleCode, w.Scope, w.DepartmentGroupCode, w.ReviseTo, w.AllowReject
    FROM    dbo.WorkflowStep w
    WHERE   w.CoCode = @CoCode
      AND   w.[Point] = 'BAPP'
      AND   w.IsActive = 1
      AND   (w.Category IS NULL OR w.Category = @Category)
      AND   (w.DepartmentGroupCode IS NULL
             OR EXISTS (SELECT 1 FROM dbo.DepartmentGroup g JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                        WHERE g.CoCode = w.CoCode AND g.GroupCode = w.DepartmentGroupCode AND g.IsActive = 1
                          AND m.DepartmentID = @DeptId));

    IF @@ROWCOUNT = 0
        THROW 50074, N'No approval workflow is configured for the BAPP. Please contact the administrator.', 1;

    UPDATE dbo.ApprovalStep SET StartedAt = @Now
    WHERE  RequestId = @RequestId AND [Point] = 'BAPP' AND Round = @Round
      AND  StepOrder = (SELECT MIN(StepOrder) FROM dbo.ApprovalStep WHERE RequestId = @RequestId AND [Point] = 'BAPP' AND Round = @Round);

    INSERT INTO dbo.ProjectBapp (RequestId, Round, BappNo, BappDate, ScopeOfWork, Remarks, Status, IssuedAt, IssuedBy)
    VALUES (@RequestId, @Round, @BappNo, @BappDate, @ScopeOfWork, @Remarks, 'REVIEW', @Now, @Username);

    UPDATE dbo.ProjectRequest
    SET    Status = 'BAPP_REVIEW', UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @RequestId;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, 'BAPP_ISSUE', @Status, 'BAPP_REVIEW',
            LEFT(N'BAPP ' + @BappNo + N' · ' + FORMAT(@BappDate, N'dd MMM yyyy', 'en-US') + ISNULL(N' · ' + @Remarks, N''), 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT CAST('BAPP_REVIEW' AS VARCHAR(20)) AS Status, @BappNo AS BappNo;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Bapp_ApprovalAct  (Accept / No langkah titik BAPP + isian form; BR-89, BR-93)
      @Action           : APPROVE (Accept) | REVISE (No)
      @InspectionResult : langkah kabag: SESUAI | SESUAI_CATATAN | BELUM_SESUAI
      @Confirm          : langkah fat (tidak ada outstanding) / dgo (status CLOSED); wajib 1 untuk Accept
      Validasi hak, status, dan perpindahan status dikerjakan usp_Request_ApprovalAct (dipanggil di sini;
      titik BAPP hanya bisa diproses lewat SP ini, ditandai SESSION_CONTEXT 'BappAct').
      Hasil: SELECT Status (status request yang baru).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Bapp_ApprovalAct
    @RequestId         INT,
    @StepId            INT,
    @Username          NVARCHAR(100),
    @Action            VARCHAR(10),
    @Remarks           NVARCHAR(MAX) = NULL,
    @InspectionResult  VARCHAR(20)   = NULL,
    @InspectionNotes   NVARCHAR(MAX) = NULL,
    @Confirm           BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Action           = UPPER(LTRIM(RTRIM(@Action)));
    SET @InspectionResult = NULLIF(UPPER(LTRIM(RTRIM(@InspectionResult))), '');
    SET @InspectionNotes  = NULLIF(LTRIM(RTRIM(@InspectionNotes)), N'');

    DECLARE @RoleCode VARCHAR(50), @Round INT;
    SELECT  @RoleCode = s.RoleCode, @Round = s.Round
    FROM    dbo.ApprovalStep s
    WHERE   s.Id = @StepId AND s.RequestId = @RequestId AND s.[Point] = 'BAPP';

    IF @RoleCode IS NULL
        THROW 50073, N'Approval step not found.', 1;
    IF @Action IS NULL OR @Action NOT IN ('APPROVE', 'REVISE')
        THROW 50072, N'Invalid approval action.', 1;
    IF LEN(@InspectionNotes) > 1000
        THROW 50072, N'Inspection notes must be at most 1000 characters.', 1;

    -- Isian per langkah (aturan berdasar role langkah dari snapshot workflow)
    IF @RoleCode = 'kabag'
    BEGIN
        IF @Action = 'APPROVE' AND @InspectionResult IS NULL
            THROW 50072, N'Please choose the inspection result.', 1;
        IF @InspectionResult IS NOT NULL AND @InspectionResult NOT IN ('SESUAI', 'SESUAI_CATATAN', 'BELUM_SESUAI')
            THROW 50072, N'Inspection result is invalid.', 1;
        IF @Action = 'APPROVE' AND @InspectionResult = 'BELUM_SESUAI'
            THROW 50072, N'"Not as specified" can only be submitted with No (return to Civil).', 1;
        IF @InspectionResult IN ('SESUAI_CATATAN', 'BELUM_SESUAI') AND @InspectionNotes IS NULL
            THROW 50072, N'Inspection notes are required for this inspection result.', 1;
    END
    IF @RoleCode = 'fat' AND @Action = 'APPROVE' AND ISNULL(@Confirm, 0) = 0
        THROW 50072, N'Please confirm that there is no outstanding cost or invoice for this project.', 1;
    IF @RoleCode = 'dgo' AND @Action = 'APPROVE' AND ISNULL(@Confirm, 0) = 0
        THROW 50072, N'Please confirm that the project status is updated to CLOSED.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Result TABLE (Status VARCHAR(20));

    BEGIN TRANSACTION;

    EXEC sp_set_session_context @key = N'BappAct', @value = 1;

    INSERT INTO @Result (Status)
    EXEC dbo.usp_Request_ApprovalAct @Id = @RequestId, @StepId = @StepId, @Username = @Username,
         @Action = @Action, @Remarks = @Remarks;

    EXEC sp_set_session_context @key = N'BappAct', @value = NULL;

    DECLARE @NewStatus VARCHAR(20) = (SELECT TOP (1) Status FROM @Result);

    UPDATE dbo.ProjectBapp
    SET    InspectionResult = CASE WHEN @RoleCode = 'kabag' THEN @InspectionResult ELSE InspectionResult END,
           InspectionNotes  = CASE WHEN @RoleCode = 'kabag' THEN @InspectionNotes  ELSE InspectionNotes  END,
           InspectedAt      = CASE WHEN @RoleCode = 'kabag' THEN @Now              ELSE InspectedAt      END,
           InspectedBy      = CASE WHEN @RoleCode = 'kabag' THEN @Username         ELSE InspectedBy      END,
           NoOutstandingAt  = CASE WHEN @RoleCode = 'fat' AND @Action = 'APPROVE' THEN @Now      ELSE NoOutstandingAt END,
           NoOutstandingBy  = CASE WHEN @RoleCode = 'fat' AND @Action = 'APPROVE' THEN @Username ELSE NoOutstandingBy END,
           ClosedStatusAt   = CASE WHEN @RoleCode = 'dgo' AND @Action = 'APPROVE' THEN @Now      ELSE ClosedStatusAt  END,
           ClosedStatusBy   = CASE WHEN @RoleCode = 'dgo' AND @Action = 'APPROVE' THEN @Username ELSE ClosedStatusBy  END
    WHERE  RequestId = @RequestId AND Round = @Round;

    -- BR-93: tanpa langkah dgo (NKM) -> konfirmasi status CLOSED diisi sistem saat Closed
    IF @NewStatus = 'CLOSED'
        UPDATE dbo.ProjectBapp
        SET    ClosedStatusAt = @Now, ClosedStatusBy = N'system'
        WHERE  RequestId = @RequestId AND Round = @Round AND ClosedStatusAt IS NULL;

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* ---------------------------------------------------------------------
   7. usp_Bapp_GetByRequest  (Details; terbaru di atas; 0 baris = tidak ada / tidak boleh melihat)
      Result 1: BAPP per ronde · Result 2: langkah approval semua ronde titik BAPP
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Bapp_GetByRequest
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
                            AND  EXISTS (SELECT 1 FROM dbo.fn_Request_VisibleToUser(r.Status, r.DepartmentID, @Username)))
              AND EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeBapp(@Username))
             THEN 1 ELSE 0 END;

    SELECT  b.Id, b.RequestId, b.Round, b.BappNo, b.BappDate, b.ScopeOfWork, b.Remarks, b.Status,
            b.IssuedAt, b.IssuedBy, ie.FullName AS IssuedByName,
            b.InspectionResult, b.InspectionNotes, b.InspectedAt, b.InspectedBy,
            b.NoOutstandingAt, b.NoOutstandingBy, b.ClosedStatusAt, b.ClosedStatusBy,
            b.ClosedAt, b.ClosedBy, ce.FullName AS ClosedByName
    FROM    dbo.ProjectBapp b
            LEFT JOIN home..users iu         ON iu.Username = b.IssuedBy
            LEFT JOIN home..app_employees ie ON ie.EmployeeCode = iu.EmployeeCode
            LEFT JOIN home..users cu         ON cu.Username = b.ClosedBy
            LEFT JOIN home..app_employees ce ON ce.EmployeeCode = cu.EmployeeCode
    WHERE   b.RequestId = @RequestId AND @Visible = 1
    ORDER BY b.Round DESC;

    SELECT  s.Id, s.Round, s.StepOrder, s.RoleCode, h.Description AS RoleName, s.Status, s.StartedAt,
            s.ActedAt, s.ActedBy, ae.FullName AS ActedByName, s.Remarks,
            CAST(CASE WHEN s.Status = 'PENDING' AND s.StartedAt IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsCurrent
    FROM    dbo.ApprovalStep s
            LEFT JOIN dbo.HierarchyLevel h   ON h.[Role] = s.RoleCode
            LEFT JOIN home..users au         ON au.Username = s.ActedBy
            LEFT JOIN home..app_employees ae ON ae.EmployeeCode = au.EmployeeCode
    WHERE   s.RequestId = @RequestId AND s.[Point] = 'BAPP' AND @Visible = 1
    ORDER BY s.Round DESC, s.StepOrder;
END
GO

/* ---------------------------------------------------------------------
   8. usp_Bapp_GetPrintData  (cetak Berita Acara; civil; status CLOSED / SURVEY_COMPLETED; BR-94)
      Result 1: header (project, kontrak, pelaksanaan, biaya, BAPP ronde ACCEPTED)
      Result 2: tanda tangan digital (penerbit + langkah approval ronde ACCEPTED)
      Result 3: rincian actual cost per item (Lampiran 1)
      Result 4: foto dokumentasi (Lampiran 2; lampiran BAPP_PHOTO_*)
      0 baris result 1 = tidak boleh / belum Closed.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Bapp_GetPrintData
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Allowed BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
              AND EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE r.Id = @RequestId AND r.Status IN ('CLOSED', 'SURVEY_COMPLETED')
                            AND EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
             THEN 1 ELSE 0 END;

    DECLARE @Round INT = (SELECT MAX(b.Round) FROM dbo.ProjectBapp b WHERE b.RequestId = @RequestId AND b.Status = 'ACCEPTED');
    IF @Round IS NULL SET @Allowed = 0;

    SELECT  r.Id AS RequestId, r.CoCode, r.RequestNo, r.Title, r.ExecutionType, r.Category,
            sd.SubDepartmentCode AS CostCenterCode, sd.SubDepartmentName AS CostCenterName,
            d.DeptName, d.ABRV,
            c.ContractNo, c.ContractDate, c.ContractValue, v.Name AS VendorName,
            r.ProjectStartDate AS PlanStartDate,
            (SELECT MAX(a.PlanEndDate)     FROM dbo.ProjectActionPlan a WHERE a.RequestId = r.Id) AS PlanEndDate,
            (SELECT MIN(a.ActualStartDate) FROM dbo.ProjectActionPlan a WHERE a.RequestId = r.Id) AS ActualStartDate,
            (SELECT MAX(a.ActualEndDate)   FROM dbo.ProjectActionPlan a WHERE a.RequestId = r.Id) AS ActualEndDate,
            r.SiteHandoverDate, r.PlanCost, ISNULL(r.ActualCostTotal, 0) AS ActualCostTotal,
            b.Round, b.BappNo, b.BappDate, b.ScopeOfWork, b.InspectionResult, b.InspectionNotes,
            b.NoOutstandingAt, b.ClosedStatusAt, b.ClosedStatusBy, b.ClosedAt AS ProjectClosedAt
    FROM    dbo.ProjectRequest r
            JOIN dbo.ProjectBapp b                ON b.RequestId = r.Id AND b.Round = @Round
            LEFT JOIN home..APP_SubDepartments sd ON sd.SubDepartmentID = r.SubDepartmentID
            LEFT JOIN home..APP_Departments d     ON d.DepartmentID = r.DepartmentID
            LEFT JOIN dbo.ProjectContract c       ON c.RequestId = r.Id
            LEFT JOIN dbo.Vendor v                ON v.Id = c.VendorId
    WHERE   r.Id = @RequestId AND @Allowed = 1;

    -- Tanda tangan digital: penerbit (Civil) lalu langkah approval ronde ACCEPTED
    SELECT  CAST('civil' AS VARCHAR(50)) AS RoleCode, 0 AS StepOrder, b.IssuedBy AS Username, e.FullName, b.IssuedAt AS SignedAt
    FROM    dbo.ProjectBapp b
            LEFT JOIN home..users u         ON u.Username = b.IssuedBy
            LEFT JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
    WHERE   b.RequestId = @RequestId AND b.Round = @Round AND @Allowed = 1
    UNION ALL
    SELECT  s.RoleCode, s.StepOrder, s.ActedBy, e.FullName, s.ActedAt
    FROM    dbo.ApprovalStep s
            LEFT JOIN home..users u         ON u.Username = s.ActedBy
            LEFT JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
    WHERE   s.RequestId = @RequestId AND s.[Point] = 'BAPP' AND s.Round = @Round AND s.Status = 'APPROVED' AND @Allowed = 1
    ORDER BY StepOrder;

    -- Lampiran 1: rincian actual cost semua bulan
    SELECT  m.PeriodMonth, i.LineNumber, i.ItemType, i.ItemName, i.Qty, i.Unit, i.UnitPrice, i.Amount, i.ReferenceNo
    FROM    dbo.ProjectActualMonth m
            JOIN dbo.ProjectActualItem i ON i.MonthId = m.Id
    WHERE   m.RequestId = @RequestId AND @Allowed = 1
    ORDER BY m.PeriodMonth, i.LineNumber;

    -- Lampiran 2: foto dokumentasi (wajib saat terbit)
    SELECT  a.Id, t.Code AS AttachmentTypeCode, t.Name AS AttachmentTypeName, a.OriginalFileName, a.CreatedAt
    FROM    dbo.RequestAttachment a
            JOIN dbo.AttachmentType t ON t.Id = a.AttachmentTypeId
    WHERE   a.RequestId = @RequestId AND a.IsActive = 1 AND @Allowed = 1
      AND   t.Code IN ('BAPP_PHOTO_INITIAL', 'BAPP_PHOTO_PROGRESS', 'BAPP_PHOTO_FINAL')
    ORDER BY CHARINDEX(',' + t.Code + ',', ',BAPP_PHOTO_INITIAL,BAPP_PHOTO_PROGRESS,BAPP_PHOTO_FINAL,'), a.CreatedAt;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: Role.sql dijalankan dan user DGO ABL punya role 'dgo' di home..users.Role;
   request ABL IN_PROGRESS (@Req) tanpa addendum terbuka; semua action plan 100% + selesai aktual.

   DECLARE @Req INT = <id>, @Civil NVARCHAR(100) = N'<civil>', @Kabag NVARCHAR(100) = N'<kabag>',
           @Fat NVARCHAR(100) = N'<fat>', @Dgo NVARCHAR(100) = N'<dgo>', @Gm NVARCHAR(100) = N'<gm>';
   DECLARE @S INT;

   -- 0) Workflow ABL BAPP: kabag 1, fat 2, dgo 3, gm 4; NKM: kabag 1, fat 2, director 3; role dgo terdaftar
   SELECT CoCode, StepOrder, RoleCode FROM dbo.WorkflowStep WHERE [Point] = 'BAPP' ORDER BY CoCode, StepOrder;
   SELECT * FROM dbo.HierarchyLevel WHERE [Role] = N'dgo';

   -- 1) Tanpa lingkup pekerjaan -> 50072; terbit -> BAPP_REVIEW + nomor 001/BAPP/ABL/XI/2026
   BEGIN TRY EXEC dbo.usp_Bapp_Issue @RequestId = @Req, @Username = @Civil, @BappDate = '2026-11-18', @ScopeOfWork = N' ';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Bapp_Issue @RequestId = @Req, @Username = @Civil, @BappDate = '2026-11-18', @ScopeOfWork = N'Pekerjaan sekat ruangan lantai 2';

   -- 2) Titik BAPP lewat usp_Request_ApprovalAct langsung -> 50074; kabag Accept tanpa hasil / BELUM_SESUAI -> 50072
   SET @S = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Kabag) WHERE RequestId = @Req AND [Point] = 'BAPP');
   BEGIN TRY EXEC dbo.usp_Request_ApprovalAct @Id = @Req, @StepId = @S, @Username = @Kabag, @Action = 'APPROVE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '2a expect 50074' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Bapp_ApprovalAct @RequestId = @Req, @StepId = @S, @Username = @Kabag, @Action = 'APPROVE', @InspectionResult = 'BELUM_SESUAI', @InspectionNotes = N'x';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '2b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 3) kabag Accept (SESUAI) -> fat Accept tanpa konfirmasi -> 50072, dengan konfirmasi -> dgo Accept (konfirmasi) -> gm Accept -> CLOSED
   EXEC dbo.usp_Bapp_ApprovalAct @RequestId = @Req, @StepId = @S, @Username = @Kabag, @Action = 'APPROVE', @InspectionResult = 'SESUAI';
   SET @S = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Fat) WHERE RequestId = @Req AND [Point] = 'BAPP');
   BEGIN TRY EXEC dbo.usp_Bapp_ApprovalAct @RequestId = @Req, @StepId = @S, @Username = @Fat, @Action = 'APPROVE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '3a expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Bapp_ApprovalAct @RequestId = @Req, @StepId = @S, @Username = @Fat, @Action = 'APPROVE', @Confirm = 1;
   SET @S = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Dgo) WHERE RequestId = @Req AND [Point] = 'BAPP');
   EXEC dbo.usp_Bapp_ApprovalAct @RequestId = @Req, @StepId = @S, @Username = @Dgo, @Action = 'APPROVE', @Confirm = 1;
   SET @S = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Gm) WHERE RequestId = @Req AND [Point] = 'BAPP');
   EXEC dbo.usp_Bapp_ApprovalAct @RequestId = @Req, @StepId = @S, @Username = @Gm, @Action = 'APPROVE';

   -- 4) Cetak: civil -> 4 result set; kabag -> 0 baris
   EXEC dbo.usp_Bapp_GetPrintData @RequestId = @Req, @Username = @Civil;
   EXEC dbo.usp_Bapp_GetPrintData @RequestId = @Req, @Username = @Kabag;

   -- 5) No (alasan wajib) di ronde lain -> IN_PROGRESS; terbit ulang -> nomor BAPP sama
   ===================================================================== */
GO
/* ---------- end RequestBapp.sql ---------- */
/* ---------- begin RequestSurvey.sql ---------- */
PRINT N'[skema] RequestSurvey.sql';
GO
/* =====================================================================
   RequestSurvey.sql  -  Survei kepuasan user setelah Project Closed + daftar User Satisfaction
                         (T6-2; PRD 3.4 langkah 7, 5.2, 6.6, BR-22, BR-24, BR-47, BR-48, BR-49, BR-91, BR-92, ST-14, KPI-03)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH SurveyTemplateItem.sql dan RequestBapp.sql,
             lalu jalankan ulang Task.sql (tugas SURVEY_SEND untuk civil dan SURVEY untuk kabag).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Alur (Keputusan 18-11-2026, lihat docs/PRD-log.md):
     1. CLOSED -> Civil klik Send survey (usp_Survey_Send): item template aktif kategori request di-snapshot (BR-48).
     2. Kabag departemen peminta (role kabag, ABRV + Company sama; BR-24) mengisi: semua item skala 1-10 wajib (BR-49),
        Note for Civil opsional. Yang pertama submit berlaku. Submit final -> SURVEY_COMPLETED (ST-14).
     3. Skor survei = rata-rata (nilai / 10) x 100% (6.6).
   Lihat (matriks 5.2): kabag (dept sendiri), mo (grup), civil, gm, director, administrator (fn_User_CanSeeSurvey +
     lingkup fn_User_AllowedDepartments). adm / emp / fat / dgo / purchasing tidak.
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request / survei tidak ditemukan atau di luar lingkup user
             50074 = Status tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.ProjectSurvey  (satu survei per project)  ·  dbo.ProjectSurveyItem (snapshot item + nilai)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectSurvey', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectSurvey
    (
        Id            INT IDENTITY(1,1) NOT NULL,
        RequestId     INT            NOT NULL,
        Category      VARCHAR(10)    NOT NULL,       -- kategori saat dikirim (template)
        Status        VARCHAR(10)    NOT NULL CONSTRAINT DF_ProjectSurvey_Status DEFAULT ('SENT'),
        SentAt        DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectSurvey_SentAt DEFAULT (SYSDATETIME()),
        SentBy        NVARCHAR(100)  NOT NULL,
        SubmittedAt   DATETIME2(3)   NULL,
        SubmittedBy   NVARCHAR(100)  NULL,
        NoteForCivil  NVARCHAR(2000) NULL,
        ScorePercent  DECIMAL(5, 2)  NULL,
        CONSTRAINT PK_ProjectSurvey PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectSurvey_Request UNIQUE (RequestId),
        CONSTRAINT FK_ProjectSurvey_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT CK_ProjectSurvey_Status CHECK (Status IN ('SENT', 'COMPLETED'))
    );
END
GO

IF OBJECT_ID(N'dbo.ProjectSurveyItem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectSurveyItem
    (
        Id              INT IDENTITY(1,1) NOT NULL,
        SurveyId        INT            NOT NULL,
        TemplateItemId  INT            NULL,           -- asal (informasi saja)
        SortOrder       INT            NOT NULL,
        ItemText        NVARCHAR(200)  NOT NULL,       -- snapshot (BR-48)
        Score           TINYINT        NULL,           -- 1..10
        CONSTRAINT PK_ProjectSurveyItem PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ProjectSurveyItem_Survey FOREIGN KEY (SurveyId) REFERENCES dbo.ProjectSurvey (Id),
        CONSTRAINT CK_ProjectSurveyItem_Score CHECK (Score IS NULL OR Score BETWEEN 1 AND 10)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ProjectSurveyItem_Survey' AND object_id = OBJECT_ID(N'dbo.ProjectSurveyItem'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectSurveyItem_Survey ON dbo.ProjectSurveyItem (SurveyId, SortOrder);
END
GO

/* ---------------------------------------------------------------------
   2. dbo.fn_User_CanSeeSurvey(@Username)   (matriks 5.2 baris Survei)
      dbo.fn_User_CanFillSurvey(@RequestId, @Username)  (BR-24, BR-91: kabag ABRV + Company departemen peminta)
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanSeeSurvey
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    FROM   dbo.fn_User_Roles(@Username) r
    WHERE  r.RoleCode IN (N'kabag', N'mo', N'civil', N'gm', N'director', N'administrator')
);
GO

CREATE OR ALTER FUNCTION dbo.fn_User_CanFillSurvey
(
    @RequestId INT,
    @Username  NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    FROM   dbo.ProjectRequest pr
           JOIN home..APP_Departments rd   ON rd.DepartmentID = pr.DepartmentID
           JOIN home..users u              ON u.Username = @Username
           JOIN home..app_employees e      ON e.EmployeeCode = u.EmployeeCode
           LEFT JOIN home..APP_Departments ed ON ed.DepartmentID = e.DepartmentID
    WHERE  pr.Id = @RequestId
      AND  (e.ResignDate IS NULL OR e.ResignDate > GETDATE())
      AND  e.CoCode = pr.CoCode
      AND  ed.ABRV = rd.ABRV
      AND  EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'kabag')
);
GO

/* ---------------------------------------------------------------------
   3. usp_Survey_Send  (civil; request CLOSED; BR-91, BR-48)
      Hasil: SELECT Id, ItemCount.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Survey_Send
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can send the survey.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @Category VARCHAR(10);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @Category = r.Category
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'CLOSED'
        THROW 50074, N'The survey can only be sent after the project is closed.', 1;
    IF EXISTS (SELECT 1 FROM dbo.ProjectSurvey s WITH (UPDLOCK, HOLDLOCK) WHERE s.RequestId = @RequestId)
        THROW 50074, N'The survey has already been sent.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SurveyTemplateItem t WHERE t.Category = @Category AND t.IsActive = 1)
        THROW 50072, N'No active survey items for this category. Please contact the administrator.', 1;

    INSERT INTO dbo.ProjectSurvey (RequestId, Category, Status, SentAt, SentBy)
    VALUES (@RequestId, @Category, 'SENT', @Now, @Username);

    DECLARE @SurveyId INT = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO dbo.ProjectSurveyItem (SurveyId, TemplateItemId, SortOrder, ItemText)
    SELECT  @SurveyId, t.Id, ROW_NUMBER() OVER (ORDER BY t.SortOrder, t.Id), t.ItemText
    FROM    dbo.SurveyTemplateItem t
    WHERE   t.Category = @Category AND t.IsActive = 1;

    DECLARE @Count INT = @@ROWCOUNT;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, 'SURVEY_SEND', @Status, @Status, N'Survey sent to the requesting department head', @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @SurveyId AS Id, @Count AS ItemCount;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Survey_Get  (Details; 0 baris result 1 = belum dikirim / tidak boleh melihat)
      Result 1: header (+ CanFill) · Result 2: item
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Survey_Get
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeSurvey(@Username))
             THEN 1 ELSE 0 END;

    DECLARE @SurveyId INT = (SELECT s.Id FROM dbo.ProjectSurvey s WHERE s.RequestId = @RequestId);

    SELECT  s.Id, s.RequestId, s.Category, s.Status, s.SentAt, s.SentBy, se.FullName AS SentByName,
            s.SubmittedAt, s.SubmittedBy, sb.FullName AS SubmittedByName, s.NoteForCivil, s.ScorePercent,
            CAST(CASE WHEN s.Status = 'SENT' AND EXISTS (SELECT 1 FROM dbo.fn_User_CanFillSurvey(@RequestId, @Username))
                      THEN 1 ELSE 0 END AS BIT) AS CanFill
    FROM    dbo.ProjectSurvey s
            LEFT JOIN home..users su          ON su.Username = s.SentBy
            LEFT JOIN home..app_employees se  ON se.EmployeeCode = su.EmployeeCode
            LEFT JOIN home..users bu          ON bu.Username = s.SubmittedBy
            LEFT JOIN home..app_employees sb  ON sb.EmployeeCode = bu.EmployeeCode
    WHERE   s.Id = @SurveyId AND @Visible = 1;

    SELECT  i.Id, i.SortOrder, i.ItemText, i.Score
    FROM    dbo.ProjectSurveyItem i
    WHERE   i.SurveyId = @SurveyId AND @Visible = 1
    ORDER BY i.SortOrder, i.Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Survey_Submit  (kabag departemen peminta; survei SENT -> COMPLETED, request -> SURVEY_COMPLETED)
      @ScoresJson: [{"id":<ProjectSurveyItem.Id>,"score":9}, ...]  semua item wajib 1..10 (BR-49)
      Hasil: SELECT ScorePercent.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Survey_Submit
    @RequestId    INT,
    @Username     NVARCHAR(100),
    @ScoresJson   NVARCHAR(MAX),
    @NoteForCivil NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @NoteForCivil = NULLIF(LTRIM(RTRIM(@NoteForCivil)), N'');

    IF LEN(@NoteForCivil) > 2000
        THROW 50072, N'Note for Civil must be at most 2000 characters.', 1;
    IF ISJSON(ISNULL(@ScoresJson, N'[]')) = 0
        THROW 50072, N'Survey data is invalid.', 1;

    DECLARE @Scores TABLE (ItemId INT PRIMARY KEY, Score INT NULL);
    INSERT INTO @Scores (ItemId, Score)
    SELECT  x.id, x.score
    FROM    OPENJSON(ISNULL(@ScoresJson, N'[]')) WITH (id INT '$.id', score INT '$.score') x
    WHERE   x.id IS NOT NULL;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @SurveyId INT, @SurveyStatus VARCHAR(10);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;

    SELECT @SurveyId = s.Id, @SurveyStatus = s.Status FROM dbo.ProjectSurvey s WHERE s.RequestId = @RequestId;

    IF @SurveyId IS NULL
        THROW 50073, N'Survey not found.', 1;
    IF @SurveyStatus <> 'SENT' OR @Status <> 'CLOSED'
        THROW 50074, N'This survey has already been submitted.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_CanFillSurvey(@RequestId, @Username))
        THROW 50075, N'Only the department head of the requesting department can fill this survey.', 1;

    -- BR-49: semua item wajib dinilai 1..10
    IF EXISTS (SELECT 1 FROM dbo.ProjectSurveyItem i
               WHERE i.SurveyId = @SurveyId
                 AND NOT EXISTS (SELECT 1 FROM @Scores s WHERE s.ItemId = i.Id AND s.Score BETWEEN 1 AND 10))
        THROW 50072, N'Please rate every item from 1 to 10.', 1;

    UPDATE i
    SET    i.Score = s.Score
    FROM   dbo.ProjectSurveyItem i
           JOIN @Scores s ON s.ItemId = i.Id
    WHERE  i.SurveyId = @SurveyId;

    DECLARE @ScorePct DECIMAL(5, 2) =
        CAST(ROUND((SELECT AVG(CAST(i.Score AS DECIMAL(9, 4))) FROM dbo.ProjectSurveyItem i WHERE i.SurveyId = @SurveyId) * 10, 2) AS DECIMAL(5, 2));

    UPDATE dbo.ProjectSurvey
    SET    Status = 'COMPLETED', SubmittedAt = @Now, SubmittedBy = @Username, NoteForCivil = @NoteForCivil, ScorePercent = @ScorePct
    WHERE  Id = @SurveyId;

    UPDATE dbo.ProjectRequest
    SET    Status = 'SURVEY_COMPLETED', UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @RequestId;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, 'SURVEY_SUBMIT', @Status, 'SURVEY_COMPLETED',
            LEFT(N'Survey score ' + FORMAT(@ScorePct, N'0.##', 'en-US') + N'%' + ISNULL(N' · ' + @NoteForCivil, N''), 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @ScorePct AS ScorePercent;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Survey_GetPaged  (halaman User Satisfaction; BR-92)
      Baris = project CLOSED / SURVEY_COMPLETED dalam lingkup user; SurveyStatus: NOT_SENT | SENT | COMPLETED.
      Periode (@Month) = bulan tanggal submit; belum diisi: bulan dikirim; belum dikirim: bulan Closed.
      @PageSize maks. 5000 (export, FR-04). @SortBy: PeriodDate | RequestNo | Score (default PeriodDate DESC).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Survey_GetPaged
    @Username      NVARCHAR(100),
    @CoCode        VARCHAR(10)   = NULL,
    @Category      VARCHAR(10)   = NULL,
    @SurveyStatus  VARCHAR(10)   = NULL,
    @Month         DATE          = NULL,
    @Search        NVARCHAR(100) = NULL,
    @SortBy        NVARCHAR(20)  = N'PeriodDate',
    @SortDir       NVARCHAR(4)   = N'DESC',
    @PageNumber    INT           = 1,
    @PageSize      INT           = 10,
    @TotalCount    INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode       = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    SET @Category     = NULLIF(LTRIM(RTRIM(@Category)), '');
    SET @SurveyStatus = NULLIF(LTRIM(RTRIM(@SurveyStatus)), '');
    SET @Search       = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy       = CASE WHEN @SortBy IN (N'PeriodDate', N'RequestNo', N'Score') THEN @SortBy ELSE N'PeriodDate' END;
    SET @SortDir      = CASE WHEN UPPER(@SortDir) = N'ASC' THEN N'ASC' ELSE N'DESC' END;
    SET @PageNumber   = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize     = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 10 WHEN @PageSize > 5000 THEN 5000 ELSE @PageSize END;

    DECLARE @MonthStart DATE = CASE WHEN @Month IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1) END;
    DECLARE @CanSee BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeSurvey(@Username)) THEN 1 ELSE 0 END;

    DECLARE @Scope TABLE (DepartmentID INT PRIMARY KEY);
    INSERT INTO @Scope (DepartmentID) SELECT DISTINCT f.DepartmentID FROM dbo.fn_User_AllowedDepartments(@Username) f;

    ;WITH x AS
    (
        SELECT  r.Id AS RequestId, r.CoCode, r.RequestNo, r.Title, r.Category, r.Status, d.DeptName, d.ABRV,
                CASE WHEN s.Id IS NULL THEN 'NOT_SENT' ELSE s.Status END AS SurveyStatus,
                s.SentAt, s.SubmittedAt, s.SubmittedBy, sb.FullName AS SubmittedByName, s.ScorePercent, s.NoteForCivil,
                (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = r.Id AND h.ToStatus = 'CLOSED') AS ClosedAt
        FROM    dbo.ProjectRequest r
                JOIN @Scope sc ON sc.DepartmentID = r.DepartmentID
                LEFT JOIN dbo.ProjectSurvey s        ON s.RequestId = r.Id
                LEFT JOIN home..APP_Departments d    ON d.DepartmentID = r.DepartmentID
                LEFT JOIN home..users bu             ON bu.Username = s.SubmittedBy
                LEFT JOIN home..app_employees sb     ON sb.EmployeeCode = bu.EmployeeCode
        WHERE   r.Status IN ('CLOSED', 'SURVEY_COMPLETED') AND @CanSee = 1
    ),
    y AS
    (
        SELECT x.*, CAST(COALESCE(x.SubmittedAt, x.SentAt, x.ClosedAt) AS DATE) AS PeriodDate
        FROM   x
        WHERE  (@CoCode IS NULL OR x.CoCode = @CoCode)
          AND  (@Category IS NULL OR x.Category = @Category)
          AND  (@SurveyStatus IS NULL OR x.SurveyStatus = @SurveyStatus)
          AND  (@Search IS NULL OR x.Title LIKE N'%' + @Search + N'%' OR x.RequestNo LIKE '%' + @Search + '%')
    )
    SELECT  y.*, COUNT(*) OVER () AS TotalRows
    INTO    #rows
    FROM    y
    WHERE   (@MonthStart IS NULL OR (y.PeriodDate >= @MonthStart AND y.PeriodDate < DATEADD(MONTH, 1, @MonthStart)));

    SET @TotalCount = ISNULL((SELECT TOP (1) TotalRows FROM #rows), 0);

    SELECT  RequestId, CoCode, RequestNo, Title, Category, Status, DeptName, ABRV, SurveyStatus, SentAt, SubmittedAt,
            SubmittedBy, SubmittedByName, ScorePercent, NoteForCivil, ClosedAt, PeriodDate
    FROM    #rows
    ORDER BY
        CASE WHEN @SortBy = N'PeriodDate' AND @SortDir = N'ASC'  THEN PeriodDate END ASC,
        CASE WHEN @SortBy = N'PeriodDate' AND @SortDir = N'DESC' THEN PeriodDate END DESC,
        CASE WHEN @SortBy = N'RequestNo'  AND @SortDir = N'ASC'  THEN RequestNo END ASC,
        CASE WHEN @SortBy = N'RequestNo'  AND @SortDir = N'DESC' THEN RequestNo END DESC,
        CASE WHEN @SortBy = N'Score'      AND @SortDir = N'ASC'  THEN ScorePercent END ASC,
        CASE WHEN @SortBy = N'Score'      AND @SortDir = N'DESC' THEN ScorePercent END DESC,
        RequestId DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;

    DROP TABLE #rows;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: request CLOSED (@Req) hasil T6-1; user civil, kabag ABRV departemen peminta, kabag departemen lain, adm.

   DECLARE @Req INT = <id>, @Civil NVARCHAR(100) = N'<civil>', @Kabag NVARCHAR(100) = N'<kabag dept>',
           @KabagLain NVARCHAR(100) = N'<kabag lain>', @Adm NVARCHAR(100) = N'<adm>';

   -- 1) Bukan civil -> 50075; civil kirim -> survei + 5 item (template kategori); kirim ulang -> 50074
   BEGIN TRY EXEC dbo.usp_Survey_Send @RequestId = @Req, @Username = @Kabag;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Survey_Send @RequestId = @Req, @Username = @Civil;
   BEGIN TRY EXEC dbo.usp_Survey_Send @RequestId = @Req, @Username = @Civil;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50074' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Lihat: kabag -> CanFill 1; adm -> 0 baris
   EXEC dbo.usp_Survey_Get @RequestId = @Req, @Username = @Kabag;
   EXEC dbo.usp_Survey_Get @RequestId = @Req, @Username = @Adm;

   -- 3) Kabag lain -> 50073/50075; item kurang -> 50072; lengkap (10,9,8,10,7) -> 88.00, request SURVEY_COMPLETED
   DECLARE @J NVARCHAR(MAX) = (SELECT i.Id AS id, CASE i.SortOrder WHEN 1 THEN 10 WHEN 2 THEN 9 WHEN 3 THEN 8 WHEN 4 THEN 10 ELSE 7 END AS score
                               FROM dbo.ProjectSurveyItem i JOIN dbo.ProjectSurvey s ON s.Id = i.SurveyId
                               WHERE s.RequestId = @Req FOR JSON PATH);
   BEGIN TRY EXEC dbo.usp_Survey_Submit @RequestId = @Req, @Username = @KabagLain, @ScoresJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '3a expect 50073/50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Survey_Submit @RequestId = @Req, @Username = @Kabag, @ScoresJson = N'[]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '3b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Survey_Submit @RequestId = @Req, @Username = @Kabag, @ScoresJson = @J, @NoteForCivil = N'Good job';

   -- 4) Daftar: civil -> baris @Req COMPLETED 88; filter NOT_SENT / bulan
   DECLARE @T INT;
   EXEC dbo.usp_Survey_GetPaged @Username = @Civil, @TotalCount = @T OUTPUT; SELECT @T AS Total;
   EXEC dbo.usp_Survey_GetPaged @Username = @Civil, @SurveyStatus = 'NOT_SENT', @TotalCount = @T OUTPUT;
   ===================================================================== */
GO
/* ---------- end RequestSurvey.sql ---------- */
/* ---------- begin Task.sql ---------- */
PRINT N'[skema] Task.sql';
GO
/* =====================================================================
   Task.sql  -  Tugas Saya + badge header (T2-4; PRD 7.1, FR-01, FR-02, BR-32, BR-63, BR-66)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestApproval.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Satu sumber untuk daftar Tugas Saya (FR-01) dan angka badge (FR-02): dbo.fn_User_Tasks.
     - Jenis tugas (PRD 7.1) yang sudah ada sampai T2:
         APPROVAL    : langkah approval aktif yang boleh diproses user (fn_User_ActionableSteps;
                       role, lingkup, Company, bukan request sendiri). Berlaku juga untuk MGMT/BAPP nanti.
         REVISE      : request RETURNED milik requester (pembuat request) -> revisi dan Submit ulang.
         REJECTED    : request REJECTED milik requester -> informasi; hilang setelah Details dibuka
                       (dbo.RequestTaskRead).
         FEASIBILITY : request FEASIBILITY -> role civil (lingkup Civil = ABL dan NKM, BR-59).
         DOC_PREPARATION : request DOC_PREPARATION -> role civil (BOQ, Drawing, kirim ke management; T3-2).
         PLANNING    : request PLANNING -> role civil (aktif setelah management approval, T3).
         PROCUREMENT : request PROCUREMENT (TOR dikirim) -> role purchasing (input kontrak; T4-1).
         SCHEDULING  : request SCHEDULING -> role civil (schedule, action plan, estimasi biaya, site handover; T4-2).
         PROGRESS    : request IN_PROGRESS yang progress minggu berjalan (Senin s.d. Minggu) belum disimpan
                       -> role civil (pengingat input progress mingguan; T5-1, BR-16, BR-66). Hilang setelah
                       progress minggu itu disimpan. TaskSince = Senin minggu berjalan.
         ADDENDUM    : addendum berstatus FINAL_CONTRACT (outsource: upload kontrak final, BR-87) atau ADJUSTMENT
                       (penyesuaian action plan + estimasi, BR-82) -> role civil (T4-4). TaskSince = saat langkah itu
                       mulai. Approval addendum (nilai naik) muncul sebagai APPROVAL titik ADDENDUM.
         BAPP        : project In Progress dengan semua action plan 100% + tanggal selesai aktual -> role civil
                       (terbitkan BAPP; T6-1, BR-88). Approval BAPP muncul sebagai APPROVAL titik BAPP.
         SURVEY_SEND : project Closed yang belum dikirim survei -> role civil (T6-2, BR-91).
         SURVEY      : survei terkirim -> kabag ABRV + Company departemen peminta (fn_User_CanFillSurvey; T6-2).
       Urutan menjalankan: Task.sql SETELAH RequestProgress.sql, RequestAddendum.sql, RequestSurvey.sql, (memakai ProjectProgressWeek dan fn_WeekStart)
       dan SETELAH RequestAddendum.sql (memakai ProjectAddendum).
       Jenis lain (TOR -> purchasing, BAPP, survei) ditambah di modulnya (T4/T6).
     - TaskSince = sejak kapan tugas menunggu (StartedAt langkah, atau waktu status terakhir dari history).
       Tidak ada penanda overdue (BR-32).
     - Semua tugas juga dibatasi lingkup lihat user (fn_User_AllowedDepartments).
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.RequestTaskRead  (tugas informasi yang sudah dibuka, mis. REJECTED)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestTaskRead', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestTaskRead
    (
        RequestId  INT            NOT NULL,
        Username   NVARCHAR(100)  NOT NULL,
        TaskType   VARCHAR(20)    NOT NULL,
        ReadAt     DATETIME2(3)   NOT NULL CONSTRAINT DF_RequestTaskRead_ReadAt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_RequestTaskRead PRIMARY KEY CLUSTERED (RequestId, Username, TaskType),
        CONSTRAINT FK_RequestTaskRead_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id)
    );
END
GO

/* ---------------------------------------------------------------------
   2. Index status request (tugas REVISE/REJECTED/civil difilter per status)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_ProjectRequest_Status' AND object_id = OBJECT_ID(N'dbo.ProjectRequest'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectRequest_Status
        ON dbo.ProjectRequest (Status) INCLUDE (DepartmentID, RequesterUsername);
END
GO

/* ---------------------------------------------------------------------
   3. dbo.fn_User_Tasks(@Username)
      Satu baris per tugas: TaskType, RequestId, ApprovalStepId (hanya APPROVAL), TaskSince.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_Tasks
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    WITH r AS
    (
        SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
        FROM   home..users u
               CROSS APPLY STRING_SPLIT(u.[Role], N';') s
        WHERE  u.Username = @Username
          AND  LTRIM(RTRIM(s.value)) <> N''
    ),
    scope AS
    (
        SELECT DepartmentID FROM dbo.fn_User_AllowedDepartments(@Username)
    )
    -- Langkah approval aktif (request / management / BAPP)
    SELECT  CAST('APPROVAL' AS VARCHAR(20)) AS TaskType, a.RequestId, a.ApprovalStepId, a.StartedAt AS TaskSince
    FROM    dbo.fn_User_ActionableSteps(@Username) a
            JOIN dbo.ProjectRequest pr ON pr.Id = a.RequestId
    WHERE   pr.DepartmentID IN (SELECT DepartmentID FROM scope)

    UNION ALL

    -- Dikembalikan untuk revisi -> requester
    SELECT  'REVISE', pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = 'RETURNED')
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'RETURNED'
      AND   pr.RequesterUsername = @Username
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)

    UNION ALL

    -- Ditolak -> requester (informasi, sampai Details dibuka)
    SELECT  'REJECTED', pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = 'REJECTED')
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'REJECTED'
      AND   pr.RequesterUsername = @Username
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
      AND   NOT EXISTS (SELECT 1 FROM dbo.RequestTaskRead t
                        WHERE t.RequestId = pr.Id AND t.Username = @Username AND t.TaskType = 'REJECTED')

    UNION ALL

    -- Pekerjaan Civil (Feasibility / Document Preparation (T3-2) / Planning / Scheduling (T4-2))
    SELECT  pr.Status, pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = pr.Status)
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status IN ('FEASIBILITY', 'DOC_PREPARATION', 'PLANNING', 'SCHEDULING')
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)

    UNION ALL

    -- Procurement (TOR dikirim Civil) -> purchasing input kontrak (T4-1, BR-11)
    SELECT  pr.Status, pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = pr.Status)
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'PROCUREMENT'
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'purchasing')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)

    UNION ALL

    -- Progress minggu berjalan belum disimpan -> civil (T5-1, BR-16)
    SELECT  'PROGRESS', pr.Id, NULL, CAST(wk.WeekStart AS DATETIME2(3))
    FROM    dbo.ProjectRequest pr
            CROSS APPLY (SELECT dbo.fn_WeekStart(CAST(SYSDATETIME() AS DATE)) AS WeekStart) wk
    WHERE   pr.Status = 'IN_PROGRESS'
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
      AND   NOT EXISTS (SELECT 1 FROM dbo.ProjectProgressWeek w WHERE w.RequestId = pr.Id AND w.WeekStart = wk.WeekStart)

    UNION ALL

    -- T6-1: semua action plan 100% + selesai aktual saat In Progress -> civil terbitkan BAPP (BR-88)
    SELECT  'BAPP', pr.Id, NULL,
            (SELECT CAST(MAX(a.ActualEndDate) AS DATETIME2(3)) FROM dbo.ProjectActionPlan a WHERE a.RequestId = pr.Id)
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'IN_PROGRESS'
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
      AND   EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a WHERE a.RequestId = pr.Id)
      AND   NOT EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a
                        WHERE a.RequestId = pr.Id AND (a.ProgressPercent < 100 OR a.ActualEndDate IS NULL))

    UNION ALL

    -- T6-2: project Closed belum dikirim survei -> civil 'Send survey' (BR-91)
    SELECT  'SURVEY_SEND', pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = 'CLOSED')
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'CLOSED'
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
      AND   NOT EXISTS (SELECT 1 FROM dbo.ProjectSurvey s WHERE s.RequestId = pr.Id)

    UNION ALL

    -- T6-2: survei terkirim -> kabag departemen peminta 'Fill survey' (BR-91, BR-24)
    SELECT  'SURVEY', pr.Id, NULL, s.SentAt
    FROM    dbo.ProjectSurvey s
            JOIN dbo.ProjectRequest pr ON pr.Id = s.RequestId
    WHERE   s.Status = 'SENT' AND pr.Status = 'CLOSED'
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_CanFillSurvey(pr.Id, @Username))

    UNION ALL

    -- Addendum berlaku -> civil: outsource upload kontrak final (BR-87), lalu penyesuaian action plan + estimasi (BR-82)
    SELECT  'ADDENDUM', pr.Id, NULL, COALESCE(d.FinalUploadedAt, d.ApprovedAt, d.CreatedAt)
    FROM    dbo.ProjectAddendum d
            JOIN dbo.ProjectRequest pr ON pr.Id = d.RequestId
    WHERE   d.Status IN ('FINAL_CONTRACT', 'ADJUSTMENT')
      AND   pr.Status IN ('SCHEDULING', 'IN_PROGRESS')
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
);
GO

/* ---------------------------------------------------------------------
   4. usp_Task_GetSummary  (jumlah per jenis; total = badge header FR-02)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetSummary
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  t.TaskType, COUNT(*) AS TaskCount
    FROM    dbo.fn_User_Tasks(@Username) t
    GROUP BY t.TaskType
    ORDER BY CHARINDEX(',' + t.TaskType + ',', ',APPROVAL,REVISE,REJECTED,FEASIBILITY,DOC_PREPARATION,PLANNING,PROCUREMENT,SCHEDULING,ADDENDUM,PROGRESS,BAPP,SURVEY_SEND,SURVEY,');
END
GO

/* ---------------------------------------------------------------------
   5. usp_Task_GetList  (daftar Tugas Saya; @TaskType NULL = semua). Terlama di atas.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetList
    @Username NVARCHAR(100),
    @TaskType VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @TaskType = NULLIF(LTRIM(RTRIM(@TaskType)), '');

    SELECT  t.TaskType, t.RequestId, t.ApprovalStepId, t.TaskSince,
            pr.RequestNo, pr.Title, pr.Category, pr.Status, pr.CoCode, d.DeptName, d.ABRV,
            req.FullName AS RequesterName,
            s.[Point], s.StepOrder, s.RoleCode, h.Description AS RoleName
    FROM    dbo.fn_User_Tasks(@Username) t
            JOIN dbo.ProjectRequest pr            ON pr.Id = t.RequestId
            LEFT JOIN home..APP_Departments d     ON d.DepartmentID = pr.DepartmentID
            LEFT JOIN home..app_employees req     ON req.EmployeeCode = pr.RequesterEmployeeCode
            LEFT JOIN dbo.ApprovalStep s          ON s.Id = t.ApprovalStepId
            LEFT JOIN dbo.HierarchyLevel h        ON h.[Role] = s.RoleCode
    WHERE   (@TaskType IS NULL OR t.TaskType = @TaskType)
    ORDER BY CASE WHEN t.TaskSince IS NULL THEN 1 ELSE 0 END, t.TaskSince, t.RequestId;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Task_MarkRead  (tugas informasi dibuka -> hilang dari Tugas Saya)
      Hanya mencatat bila tugas itu memang milik user saat ini (selain itu diabaikan, tanpa error).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Task_MarkRead
    @RequestId INT,
    @Username  NVARCHAR(100),
    @TaskType  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaskType <> 'REJECTED'
        RETURN;   -- hanya tugas informasi; tugas lain hilang karena statusnya berubah

    INSERT INTO dbo.RequestTaskRead (RequestId, Username, TaskType)
    SELECT  @RequestId, @Username, @TaskType
    WHERE   EXISTS (SELECT 1 FROM dbo.fn_User_Tasks(@Username) t
                    WHERE t.RequestId = @RequestId AND t.TaskType = @TaskType)
      AND   NOT EXISTS (SELECT 1 FROM dbo.RequestTaskRead x WITH (UPDLOCK, HOLDLOCK)
                        WHERE x.RequestId = @RequestId AND x.Username = @Username AND x.TaskType = @TaskType);
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel hanya hidup dalam satu eksekusi: jalankan blok bersama DECLARE-nya.

   DECLARE @Kabag NVARCHAR(100) = N'marisi', @Mo NVARCHAR(100) = N'maamanullang',
           @Requester NVARCHAR(100) = N'asimbolon', @Civil NVARCHAR(100) = N'<user civil>';

   -- 1) Approver: request WAITING_APPROVAL departemennya -> APPROVAL (sama dengan fn_User_ActionableSteps)
   EXEC dbo.usp_Task_GetSummary @Username = @Kabag;
   EXEC dbo.usp_Task_GetList    @Username = @Kabag;
   SELECT COUNT(*) AS Harus_Sama FROM dbo.fn_User_ActionableSteps(@Kabag);

   -- 2) Requester: request RETURNED -> REVISE; REJECTED (belum dibuka) -> REJECTED
   EXEC dbo.usp_Task_GetSummary @Username = @Requester;
   EXEC dbo.usp_Task_GetList    @Username = @Requester;

   -- 3) MarkRead: REJECTED hilang; jenis lain / request bukan miliknya -> tidak tercatat, tanpa error
   DECLARE @Rej INT = (SELECT TOP (1) RequestId FROM dbo.fn_User_Tasks(@Requester) WHERE TaskType = 'REJECTED');
   EXEC dbo.usp_Task_MarkRead @RequestId = @Rej, @Username = @Requester, @TaskType = 'REJECTED';
   EXEC dbo.usp_Task_MarkRead @RequestId = @Rej, @Username = @Requester, @TaskType = 'REJECTED';  -- ulang: tetap 1 baris
   SELECT * FROM dbo.RequestTaskRead;
   EXEC dbo.usp_Task_GetList @Username = @Requester, @TaskType = 'REJECTED';                      -- @Rej tidak ada lagi

   -- 4) Civil: request FEASIBILITY (ABL dan NKM) -> FEASIBILITY; user non-civil -> tidak ada jenis ini
   EXEC dbo.usp_Task_GetSummary @Username = @Civil;
   EXEC dbo.usp_Task_GetList    @Username = @Civil, @TaskType = 'FEASIBILITY';

   -- 4b) Civil: project IN_PROGRESS tanpa progress minggu berjalan -> PROGRESS (TaskSince = Senin minggu ini);
   --     setelah usp_Request_SaveProgress untuk minggu ini, baris project itu hilang
   EXEC dbo.usp_Task_GetList @Username = 'users1', @TaskType = 'PROGRESS';
   SELECT pr.Id, pr.RequestNo, w.WeekStart FROM dbo.ProjectRequest pr
          LEFT JOIN dbo.ProjectProgressWeek w ON w.RequestId = pr.Id AND w.WeekStart = dbo.fn_WeekStart(CAST(SYSDATETIME() AS DATE))
   WHERE  pr.Status = 'IN_PROGRESS';                                                  -- WeekStart NULL = muncul sebagai tugas

   -- 5) User tanpa tugas / tidak ada -> 0 baris
   EXEC dbo.usp_Task_GetSummary @Username = N'tidak-ada-xyz';
   ===================================================================== */
GO
/* ---------- end Task.sql ---------- */
/* ---------- begin Dashboard.sql ---------- */
PRINT N'[skema] Dashboard.sql';
GO
/* =====================================================================
   Dashboard.sql  -  Dashboard dasar (PRD 9.1 "Dashboard dasar", 7.1 FR-01, 8.1 BR-68..BR-71, 9.4 FR-04)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestActualCost.sql
             (kolom OverallStatus/CostStatus) dan RequestProgress.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Aturan (Keputusan 16-11-2026, lihat docs/PRD-log.md):
     - Kartu per kategori (CAPEX/OPEX/LVE):
         * Project aktif (IN_PROGRESS + BAPP_REVIEW) per status keseluruhan On Track / At Risk / Delayed (BR-70).
           OverallStatus NULL (belum ada progress & actual) dihitung On Track (catatan PRD 8.1).
         * Plan cost project aktif, estimasi dan actual kumulatif s.d. bulan terpilih.
         * Pipeline: Approval (WAITING_APPROVAL, MGMT_APPROVAL) · Civil review (FEASIBILITY, DOC_PREPARATION) ·
           Preparation (PLANNING, PROCUREMENT, SCHEDULING) · Closed pada bulan terpilih (CLOSED/SURVEY_COMPLETED,
           tanggal masuk CLOSED dari riwayat; aktif setelah T6).
     - Filter bulan: biaya kumulatif s.d. bulan itu dan Closed di bulan itu. Status jadwal/biaya/keseluruhan =
       nilai terakhir yang dihitung (riwayat status tidak disimpan).
     - Filter Company: NULL = semua Company dalam lingkup user. Lingkup data lewat fn_User_AllowedDepartments.
     - Purchasing tidak punya akses dashboard (matriks 5.2); dicek di Controller.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_Dashboard_GetSummary  (kartu per kategori; selalu 3 baris CAPEX, OPEX, LVE)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetSummary
    @Username  NVARCHAR(100),
    @CoCode    VARCHAR(10) = NULL,
    @Month     DATE        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, @Today)), MONTH(ISNULL(@Month, @Today)), 1);
    DECLARE @NextMonth DATE = DATEADD(MONTH, 1, @MonthStart);

    DECLARE @Scope TABLE (DepartmentID INT PRIMARY KEY);
    INSERT INTO @Scope (DepartmentID)
    SELECT DISTINCT f.DepartmentID FROM dbo.fn_User_AllowedDepartments(@Username) f;

    ;WITH r AS
    (
        SELECT  pr.Id, pr.Category, pr.Status, pr.OverallStatus, pr.PlanCost,
                (SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = pr.Id AND e.PeriodMonth <= @MonthStart) AS EstimateToMonth,
                (SELECT SUM(m.TotalAmount) FROM dbo.ProjectActualMonth m WHERE m.RequestId = pr.Id AND m.PeriodMonth <= @MonthStart) AS ActualToMonth,
                CASE WHEN pr.Status IN ('CLOSED', 'SURVEY_COMPLETED')
                     THEN (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = 'CLOSED') END AS ClosedAt
        FROM    dbo.ProjectRequest pr
                JOIN @Scope s ON s.DepartmentID = pr.DepartmentID
        WHERE   (@CoCode IS NULL OR pr.CoCode = @CoCode)
    )
    SELECT  c.Category,
            COUNT(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') THEN 1 END)                                              AS ActiveTotal,
            COUNT(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') AND ISNULL(r.OverallStatus, 'ON_TRACK') = 'ON_TRACK' THEN 1 END) AS OnTrack,
            COUNT(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') AND r.OverallStatus = 'AT_RISK' THEN 1 END)               AS AtRisk,
            COUNT(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') AND r.OverallStatus = 'DELAYED' THEN 1 END)               AS Delayed,
            ISNULL(SUM(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') THEN r.PlanCost END), 0)                             AS PlanCost,
            ISNULL(SUM(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') THEN r.EstimateToMonth END), 0)                      AS EstimateToMonth,
            ISNULL(SUM(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') THEN r.ActualToMonth END), 0)                        AS ActualToMonth,
            COUNT(CASE WHEN r.Status IN ('WAITING_APPROVAL', 'MGMT_APPROVAL') THEN 1 END)                                         AS InApproval,
            COUNT(CASE WHEN r.Status IN ('FEASIBILITY', 'DOC_PREPARATION') THEN 1 END)                                            AS InCivilReview,
            COUNT(CASE WHEN r.Status IN ('PLANNING', 'PROCUREMENT', 'SCHEDULING') THEN 1 END)                                     AS InPreparation,
            COUNT(CASE WHEN r.ClosedAt >= @MonthStart AND r.ClosedAt < @NextMonth THEN 1 END)                                     AS ClosedInMonth
    FROM    (VALUES ('CAPEX', 1), ('OPEX', 2), ('LVE', 3)) AS c (Category, SortOrder)
            LEFT JOIN r ON r.Category = c.Category
    GROUP BY c.Category, c.SortOrder
    ORDER BY c.SortOrder;
END
GO

/* ---------------------------------------------------------------------
   2. usp_Dashboard_GetProjects  (tabel project aktif: IN_PROGRESS + BAPP_REVIEW)
      @OverallStatus : ON_TRACK (termasuk belum dihitung) | AT_RISK | DELAYED | NULL = semua
      @SortBy        : Overall | RequestNo | Title | Category | Progress | PlanCost   (default Overall: Delayed dulu)
      @PageSize      : 1..100 untuk tampilan; 0 = semua baris (export Excel, maks. 5000)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetProjects
    @Username       NVARCHAR(100),
    @CoCode         VARCHAR(10)   = NULL,
    @Month          DATE          = NULL,
    @Category       VARCHAR(10)   = NULL,
    @OverallStatus  VARCHAR(20)   = NULL,
    @Search         NVARCHAR(100) = NULL,
    @SortBy         NVARCHAR(20)  = N'Overall',
    @SortDir        NVARCHAR(4)   = N'DESC',
    @PageNumber     INT           = 1,
    @PageSize       INT           = 10,
    @TotalCount     INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode        = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    SET @Category      = NULLIF(LTRIM(RTRIM(@Category)), '');
    SET @OverallStatus = NULLIF(LTRIM(RTRIM(@OverallStatus)), '');
    SET @Search        = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy        = CASE WHEN @SortBy IN (N'Overall', N'RequestNo', N'Title', N'Category', N'Progress', N'PlanCost') THEN @SortBy ELSE N'Overall' END;
    SET @SortDir       = CASE WHEN UPPER(@SortDir) = N'ASC' THEN N'ASC' ELSE N'DESC' END;
    SET @PageNumber    = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN @PageSize IS NULL OR @PageSize < 0 THEN 10
                              WHEN @PageSize = 0 THEN 5000
                              WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, @Today)), MONTH(ISNULL(@Month, @Today)), 1);

    DECLARE @Scope TABLE (DepartmentID INT PRIMARY KEY);
    INSERT INTO @Scope (DepartmentID)
    SELECT DISTINCT f.DepartmentID FROM dbo.fn_User_AllowedDepartments(@Username) f;

    DECLARE @Rows TABLE
    (
        Id INT PRIMARY KEY, CoCode VARCHAR(10), RequestNo VARCHAR(40), Title NVARCHAR(200), Category VARCHAR(10),
        Status VARCHAR(20), DepartmentID INT, ExecutionType VARCHAR(10), ProjectStartDate DATE, ProjectEndDate DATE,
        ProgressPercent DECIMAL(5, 2), PlanProgressPercent DECIMAL(5, 2), ScheduleStatus VARCHAR(20),
        PlanCost DECIMAL(18, 2), EstimateToMonth DECIMAL(18, 2), ActualToMonth DECIMAL(18, 2),
        CostStatus VARCHAR(20), OverallStatus VARCHAR(20), Severity INT
    );

    INSERT INTO @Rows
    SELECT  pr.Id, pr.CoCode, pr.RequestNo, pr.Title, pr.Category, pr.Status, pr.DepartmentID, pr.ExecutionType,
            pr.ProjectStartDate,
            (SELECT MAX(a.PlanEndDate) FROM dbo.ProjectActionPlan a WHERE a.RequestId = pr.Id),
            pr.ProgressPercent, pr.PlanProgressPercent, pr.ScheduleStatus, pr.PlanCost,
            (SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = pr.Id AND e.PeriodMonth <= @MonthStart),
            (SELECT SUM(m.TotalAmount) FROM dbo.ProjectActualMonth m WHERE m.RequestId = pr.Id AND m.PeriodMonth <= @MonthStart),
            pr.CostStatus, pr.OverallStatus,
            CASE pr.OverallStatus WHEN 'DELAYED' THEN 3 WHEN 'AT_RISK' THEN 2 ELSE 1 END
    FROM    dbo.ProjectRequest pr
            JOIN @Scope s ON s.DepartmentID = pr.DepartmentID
    WHERE   pr.Status IN ('IN_PROGRESS', 'BAPP_REVIEW')
      AND   (@CoCode   IS NULL OR pr.CoCode = @CoCode)
      AND   (@Category IS NULL OR pr.Category = @Category)
      AND   (@OverallStatus IS NULL OR ISNULL(pr.OverallStatus, 'ON_TRACK') = @OverallStatus)
      AND   (@Search IS NULL OR pr.Title LIKE N'%' + @Search + N'%' OR pr.RequestNo LIKE '%' + @Search + '%');

    SELECT @TotalCount = COUNT(*) FROM @Rows;

    SELECT  x.Id, x.CoCode, x.RequestNo, x.Title, x.Category, x.Status, x.DepartmentID, d.DeptName, d.ABRV,
            x.ExecutionType, x.ProjectStartDate, x.ProjectEndDate, x.ProgressPercent, x.PlanProgressPercent,
            x.ScheduleStatus, x.PlanCost, x.EstimateToMonth, x.ActualToMonth, x.CostStatus, x.OverallStatus
    FROM    @Rows x
            LEFT JOIN home..APP_Departments d ON d.DepartmentID = x.DepartmentID
    ORDER BY
        CASE WHEN @SortBy = N'Overall'   AND @SortDir = N'ASC'  THEN x.Severity  END ASC,
        CASE WHEN @SortBy = N'Overall'   AND @SortDir = N'DESC' THEN x.Severity  END DESC,
        CASE WHEN @SortBy = N'RequestNo' AND @SortDir = N'ASC'  THEN x.RequestNo END ASC,
        CASE WHEN @SortBy = N'RequestNo' AND @SortDir = N'DESC' THEN x.RequestNo END DESC,
        CASE WHEN @SortBy = N'Title'     AND @SortDir = N'ASC'  THEN x.Title     END ASC,
        CASE WHEN @SortBy = N'Title'     AND @SortDir = N'DESC' THEN x.Title     END DESC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'ASC'  THEN CHARINDEX(',' + x.Category + ',', ',CAPEX,OPEX,LVE,') END ASC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'DESC' THEN CHARINDEX(',' + x.Category + ',', ',CAPEX,OPEX,LVE,') END DESC,
        CASE WHEN @SortBy = N'Progress'  AND @SortDir = N'ASC'  THEN x.ProgressPercent END ASC,
        CASE WHEN @SortBy = N'Progress'  AND @SortDir = N'DESC' THEN x.ProgressPercent END DESC,
        CASE WHEN @SortBy = N'PlanCost'  AND @SortDir = N'ASC'  THEN x.PlanCost  END ASC,
        CASE WHEN @SortBy = N'PlanCost'  AND @SortDir = N'DESC' THEN x.PlanCost  END DESC,
        x.RequestNo ASC, x.Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)

   DECLARE @Civil NVARCHAR(100) = N'users1', @Adm NVARCHAR(100) = N'hdahlia', @T INT;

   -- 1) Kartu: 3 baris (CAPEX, OPEX, LVE); civil = semua departemen ABL + NKM
   EXEC dbo.usp_Dashboard_GetSummary @Username = @Civil, @Month = '2026-11-01';
   EXEC dbo.usp_Dashboard_GetSummary @Username = @Civil, @CoCode = 'NKM', @Month = '2026-11-01';   -- hanya NKM
   EXEC dbo.usp_Dashboard_GetSummary @Username = @Adm,   @Month = '2026-11-01';                   -- hanya departemennya
   -- Bandingkan ActualToMonth bulan Okt vs Nov: Okt tidak memuat actual Nov
   EXEC dbo.usp_Dashboard_GetSummary @Username = @Civil, @Month = '2026-10-01';

   -- 2) Tabel: default urut Delayed dulu; filter status / kategori / cari; export (PageSize 0)
   EXEC dbo.usp_Dashboard_GetProjects @Username = @Civil, @Month = '2026-11-01', @TotalCount = @T OUTPUT; SELECT @T AS TotalCount;
   EXEC dbo.usp_Dashboard_GetProjects @Username = @Civil, @OverallStatus = 'DELAYED', @TotalCount = @T OUTPUT;
   EXEC dbo.usp_Dashboard_GetProjects @Username = @Civil, @Category = 'CAPEX', @Search = N'PM-', @SortBy = N'Progress', @SortDir = N'ASC', @TotalCount = @T OUTPUT;
   EXEC dbo.usp_Dashboard_GetProjects @Username = @Civil, @PageSize = 0, @TotalCount = @T OUTPUT;

   -- 3) Request List untuk export (Request.sql dijalankan ulang): PageSize sampai 5000
   EXEC dbo.usp_Request_GetPaged @Username = @Civil, @PageSize = 5000, @TotalCount = @T OUTPUT; SELECT @T AS TotalCount;
   ===================================================================== */
GO
/* ---------- end Dashboard.sql ---------- */
/* ---------- begin DashboardChart.sql ---------- */
PRINT N'[skema] DashboardChart.sql';
GO
/* =====================================================================
   DashboardChart.sql  -  Data grafik dasar (sebagian T8 ditarik ke MVP, Keputusan 16-11-2026; PRD 4, 8.1, BR-17, BR-69)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Dashboard.sql dan RequestProgress.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Grafik (library Chart.js lokal):
     1. Dashboard - status keseluruhan per kategori : memakai usp_Dashboard_GetSummary (tanpa SP baru).
     2. Dashboard - biaya bulanan estimasi vs actual : usp_Dashboard_GetMonthlyCost (di bawah).
     3. Details   - kurva S progress (plan vs actual per minggu) : usp_Request_GetProgressCurve (di bawah).
     4. Details   - kurva biaya (estimasi vs actual kumulatif) : memakai usp_Request_GetActualCost result 2 (tanpa SP baru).
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_Dashboard_GetMonthlyCost
      Project aktif (IN_PROGRESS + BAPP_REVIEW) dalam lingkup user + filter Company/kategori.
      Satu baris per bulan yang punya estimasi atau actual. Actual hanya s.d. bulan terpilih (NULL sesudahnya);
      estimasi semua bulan (rencana ke depan tetap terlihat).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetMonthlyCost
    @Username  NVARCHAR(100),
    @CoCode    VARCHAR(10) = NULL,
    @Month     DATE        = NULL,
    @Category  VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode   = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    SET @Category = NULLIF(LTRIM(RTRIM(@Category)), '');
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, @Today)), MONTH(ISNULL(@Month, @Today)), 1);

    DECLARE @Projects TABLE (Id INT PRIMARY KEY);
    INSERT INTO @Projects (Id)
    SELECT  pr.Id
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status IN ('IN_PROGRESS', 'BAPP_REVIEW')
      AND   (@CoCode   IS NULL OR pr.CoCode = @CoCode)
      AND   (@Category IS NULL OR pr.Category = @Category)
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = pr.DepartmentID);

    ;WITH e AS
    (
        SELECT ce.PeriodMonth, SUM(ce.Amount) AS Amount
        FROM   dbo.ProjectCostEstimate ce JOIN @Projects p ON p.Id = ce.RequestId
        GROUP BY ce.PeriodMonth
    ),
    a AS
    (
        SELECT am.PeriodMonth, SUM(am.TotalAmount) AS Amount
        FROM   dbo.ProjectActualMonth am JOIN @Projects p ON p.Id = am.RequestId
        WHERE  am.PeriodMonth <= @MonthStart
        GROUP BY am.PeriodMonth
    )
    SELECT  ISNULL(e.PeriodMonth, a.PeriodMonth) AS PeriodMonth,
            ISNULL(e.Amount, 0) AS EstimateAmount,
            CASE WHEN ISNULL(e.PeriodMonth, a.PeriodMonth) <= @MonthStart THEN ISNULL(a.Amount, 0) END AS ActualAmount
    FROM    e FULL OUTER JOIN a ON a.PeriodMonth = e.PeriodMonth
    ORDER BY ISNULL(e.PeriodMonth, a.PeriodMonth);
END
GO

/* ---------------------------------------------------------------------
   2. usp_Request_GetProgressCurve  (kurva S satu project; BR-17)
      Satu baris per minggu (Senin) dari minggu mulai project s.d. minggu selesai plan terakhir.
      PlanPercent = % plan pada hari Minggu minggu itu (fn_Request_PlanProgress, bobot linear per hari);
      ActualPercent = % aktual tersimpan minggu itu (NULL bila belum diisi). Lingkup sama dengan usp_Request_GetProgress.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetProgressCurve
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
             THEN 1 ELSE 0 END;

    IF @Visible = 0 RETURN;

    DECLARE @Start DATE = (SELECT ProjectStartDate FROM dbo.ProjectRequest WHERE Id = @RequestId);
    DECLARE @End DATE = (SELECT MAX(PlanEndDate) FROM dbo.ProjectActionPlan WHERE RequestId = @RequestId);
    IF @Start IS NULL OR @End IS NULL RETURN;

    -- Minggu tersimpan bisa melewati tanggal selesai plan (project terlambat): ikutkan sampai minggu tersimpan terakhir
    DECLARE @LastSaved DATE = (SELECT MAX(WeekStart) FROM dbo.ProjectProgressWeek WHERE RequestId = @RequestId);
    DECLARE @FirstWeek DATE = dbo.fn_WeekStart(@Start);
    DECLARE @LastWeek DATE = dbo.fn_WeekStart(@End);
    IF @LastSaved > @LastWeek SET @LastWeek = @LastSaved;

    ;WITH w AS
    (
        SELECT @FirstWeek AS WeekStart
        UNION ALL
        SELECT DATEADD(DAY, 7, WeekStart) FROM w WHERE WeekStart < @LastWeek
    )
    SELECT  w.WeekStart, DATEADD(DAY, 6, w.WeekStart) AS WeekEnd,
            p.PlanPercent,
            s.ActualPercent
    FROM    w
            CROSS APPLY dbo.fn_Request_PlanProgress(@RequestId, DATEADD(DAY, 6, w.WeekStart)) p
            LEFT JOIN dbo.ProjectProgressWeek s ON s.RequestId = @RequestId AND s.WeekStart = w.WeekStart
    ORDER BY w.WeekStart
    OPTION (MAXRECURSION 600);   -- maks. ±11 tahun mingguan
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)

   DECLARE @Civil NVARCHAR(100) = N'<user civil>', @Req INT = <id request IN_PROGRESS dengan schedule>;

   -- 1) Biaya bulanan: estimasi semua bulan, actual s.d. bulan terpilih (Okt: actual Nov = NULL)
   EXEC dbo.usp_Dashboard_GetMonthlyCost @Username = @Civil, @Month = '2026-11-01';
   EXEC dbo.usp_Dashboard_GetMonthlyCost @Username = @Civil, @Month = '2026-10-01';
   EXEC dbo.usp_Dashboard_GetMonthlyCost @Username = @Civil, @Month = '2026-11-01', @Category = 'CAPEX', @CoCode = 'ABL';

   -- 2) Kurva S: satu baris per minggu dari minggu mulai s.d. minggu selesai; PlanPercent naik ke 100 di minggu terakhir,
   --    ActualPercent terisi pada minggu yang sudah disimpan (mis. 16-11-2026: 12.75)
   EXEC dbo.usp_Request_GetProgressCurve @RequestId = @Req, @Username = @Civil;
   EXEC dbo.usp_Request_GetProgressCurve @RequestId = @Req, @Username = N'<user purchasing>';   -- 0 baris
   ===================================================================== */
GO
/* ---------- end DashboardChart.sql ---------- */
/* =====================================================================
   BAGIAN 2 - DATA MASTER + HIERARCHY + WORKFLOW (sumber: [ABL-ITD\SQL_DEV].[CIMS], 2026-11-20 09:13)
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
    DELETE FROM dbo.Unit;
    DELETE FROM dbo.SubCategory;
    DELETE FROM dbo.SurveyTemplateItem;
    DELETE FROM dbo.AssessmentQuestion;
    DELETE FROM dbo.AttachmentType;
    DELETE FROM dbo.Location;
    DELETE FROM dbo.Customer;
    DELETE FROM dbo.WorkCalendarHoliday;
    DELETE FROM dbo.WorkCalendarWeekend;
    DELETE FROM dbo.AppSetting;
    DELETE FROM dbo.WorkflowStep;
    DELETE FROM dbo.DepartmentGroupMember;
    DELETE FROM dbo.DepartmentGroup;
    DELETE FROM dbo.HierarchyLevel;

    -- dbo.HierarchyLevel (15 baris)
    INSERT INTO dbo.HierarchyLevel ([Role], [HierarchyLevel], [Description]) VALUES
        ('administrator', 1, N'Administrator Sistem'),
        ('komisaris', 2, NULL),
        ('director', 3, N'Director'),
        ('gm', 4, N'General Manager'),
        ('civil', 5, N'Civil Department'),
        ('dgo', 5, N'DGO'),
        ('fat', 5, N'Finance, Accounting & Tax'),
        ('mo', 6, N'Manager Operational'),
        ('purchasing', 6, N'Purchasing'),
        ('kabag', 7, N'Kepala Bagian'),
        ('plan', 8, N'Planner'),
        ('spv', 9, N'Supervisor'),
        ('adm', 10, N'Admin Departemen'),
        ('emp', 11, N'Employee'),
        ('creator', 12, NULL);

    -- dbo.DepartmentGroup (1 baris)
    SET IDENTITY_INSERT dbo.DepartmentGroup ON;
    INSERT INTO dbo.DepartmentGroup ([Id], [CoCode], [GroupCode], [GroupName], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, 'ABL', 'MILL', N'Mill (lingkup MO)', 1, '2026-11-03T13:04:56.2580000', N'seed', NULL, NULL);
    SET IDENTITY_INSERT dbo.DepartmentGroup OFF;
    IF EXISTS (SELECT 1 FROM dbo.DepartmentGroup) BEGIN DECLARE @Max_DepartmentGroup int = (SELECT MAX(Id) FROM dbo.DepartmentGroup); DBCC CHECKIDENT ('dbo.DepartmentGroup', RESEED, @Max_DepartmentGroup) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.DepartmentGroup', RESEED, 0) WITH NO_INFOMSGS;

    -- dbo.DepartmentGroupMember (6 baris)
    INSERT INTO dbo.DepartmentGroupMember ([GroupId], [DepartmentID], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, 17, '2026-11-03T13:04:56.2660000', N'seed', NULL, NULL),
        (1, 18, '2026-11-03T13:04:56.2660000', N'seed', NULL, NULL),
        (1, 19, '2026-11-03T13:04:56.2660000', N'seed', NULL, NULL),
        (1, 20, '2026-11-03T13:04:56.2660000', N'seed', NULL, NULL),
        (1, 600, '2026-11-03T13:04:56.2660000', N'seed', NULL, NULL),
        (1, 601, '2026-11-03T13:04:56.2660000', N'seed', NULL, NULL);

    -- dbo.WorkflowStep (15 baris)
    SET IDENTITY_INSERT dbo.WorkflowStep ON;
    INSERT INTO dbo.WorkflowStep ([Id], [CoCode], [Point], [StepOrder], [RoleCode], [Scope], [Category], [DepartmentGroupCode], [ReviseTo], [AllowReject], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, 'ABL', 'REQUEST', 1, 'kabag', 'DEPT', NULL, NULL, 'REQUESTER', 1, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (2, 'ABL', 'REQUEST', 2, 'mo', 'GROUP', NULL, 'MILL', 'REQUESTER', 1, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (3, 'ABL', 'MGMT', 1, 'gm', 'PLANT', NULL, NULL, 'CIVIL', 1, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (4, 'ABL', 'MGMT', 2, 'director', 'PLANT', 'CAPEX', NULL, 'CIVIL', 1, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (5, 'ABL', 'BAPP', 1, 'kabag', 'DEPT', NULL, NULL, 'CIVIL', 0, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (6, 'ABL', 'BAPP', 2, 'fat', 'PLANT', NULL, NULL, 'CIVIL', 0, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (7, 'ABL', 'BAPP', 4, 'gm', 'PLANT', NULL, NULL, 'CIVIL', 0, 1, '2026-11-03T13:04:56.2800000', N'seed', '2026-11-18T13:28:49.8660000', N'seed'),
        (8, 'NKM', 'REQUEST', 1, 'kabag', 'DEPT', NULL, NULL, 'REQUESTER', 1, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (9, 'NKM', 'MGMT', 1, 'director', 'PLANT', NULL, NULL, 'CIVIL', 1, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (10, 'NKM', 'BAPP', 1, 'kabag', 'DEPT', NULL, NULL, 'CIVIL', 0, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (11, 'NKM', 'BAPP', 2, 'fat', 'PLANT', NULL, NULL, 'CIVIL', 0, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (12, 'NKM', 'BAPP', 3, 'director', 'PLANT', NULL, NULL, 'CIVIL', 0, 1, '2026-11-03T13:04:56.2800000', N'seed', NULL, NULL),
        (1002, 'ABL', 'ADDENDUM', 1, 'gm', 'PLANT', NULL, NULL, NULL, 1, 1, '2026-11-17T14:06:13.4220000', N'seed', NULL, NULL),
        (1003, 'NKM', 'ADDENDUM', 1, 'director', 'PLANT', NULL, NULL, NULL, 1, 1, '2026-11-17T14:06:13.4220000', N'seed', NULL, NULL),
        (1004, 'ABL', 'BAPP', 3, 'dgo', 'PLANT', NULL, NULL, 'CIVIL', 0, 1, '2026-11-18T13:28:49.8670000', N'seed', NULL, NULL);
    SET IDENTITY_INSERT dbo.WorkflowStep OFF;
    IF EXISTS (SELECT 1 FROM dbo.WorkflowStep) BEGIN DECLARE @Max_WorkflowStep int = (SELECT MAX(Id) FROM dbo.WorkflowStep); DBCC CHECKIDENT ('dbo.WorkflowStep', RESEED, @Max_WorkflowStep) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.WorkflowStep', RESEED, 0) WITH NO_INFOMSGS;

    -- dbo.AppSetting (5 baris)
    INSERT INTO dbo.AppSetting ([CoCode], [SettingKey], [SettingValue], [ValueType], [Description], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        ('*', 'COST_ATRISK_MAX_PCT', N'110', 'DECIMAL', N'Maximum ratio for At Risk; above it is Over Budget, %', '2026-11-03T13:04:56.2910000', N'seed', '2026-11-04T08:36:59.2540000', N'hdahlia'),
        ('*', 'COST_ONTRACK_MAX_PCT', N'100', 'DECIMAL', N'Maximum actual/estimate ratio for On Track, %', '2026-11-03T13:04:56.2910000', N'seed', NULL, NULL),
        ('*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'5', 'INT', N'Emergency follow-up approval limit, working days', '2026-11-03T13:04:56.2910000', N'seed', '2026-11-04T08:35:50.9510000', N'hdahlia'),
        ('*', 'SCHEDULE_ONTRACK_MIN_DEV', N'-5', 'DECIMAL', N'Minimum progress deviation for On Track, % points', '2026-11-03T13:04:56.2910000', N'seed', NULL, NULL),
        ('*', 'SCHEDULE_SLIGHT_MIN_DEV', N'-15', 'DECIMAL', N'Minimum deviation for Slightly Delay; below it is Delay, % points', '2026-11-03T13:04:56.2910000', N'seed', NULL, NULL);

    -- dbo.WorkCalendarWeekend (2 baris)
    INSERT INTO dbo.WorkCalendarWeekend ([CoCode], [IsoDayOfWeek], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        ('ABL', 7, '2026-11-03T13:04:56.3020000', N'seed', NULL, NULL),
        ('NKM', 7, '2026-11-03T13:04:56.3020000', N'seed', NULL, NULL);

    -- dbo.WorkCalendarHoliday (0 baris)

    -- dbo.Customer (9 baris)
    SET IDENTITY_INSERT dbo.Customer ON;
    INSERT INTO dbo.Customer ([Id], [Code], [Name], [Phone], [Email], [Address], [IsActive], [CreatedAt], [UpdatedAt]) VALUES
        (1, N'CUST001', N'PT Contoh Satu (Rev)', N'+6282172337576', N'a@mail.com', N'JL.Jalan 001', 1, '2026-10-29T08:41:23.9340000', '2026-10-29T10:57:49.7600000'),
        (5, N'CUST002', N'Customer 002', N'082172337576', N'work.hd001@gmail.com', N'Jalan Raya Pasir Putih KM.14 No.8
Jalan Raya Pasir Putih KM.14 No.8 , Desa Baru, Kampar', 1, '2026-10-29T10:14:20.9400000', '2026-10-29T14:18:16.6260000'),
        (6, N'CUST003', N'PT.Customer 003', NULL, NULL, NULL, 1, '2026-10-29T10:16:04.0200000', '2026-10-29T10:16:22.4590000'),
        (7, N'CUST004', N'PT.Customer 004', NULL, NULL, NULL, 1, '2026-10-29T10:16:48.9280000', NULL),
        (8, N'CUST005', N'PT.Customer 005', NULL, NULL, NULL, 1, '2026-10-29T10:17:20.7730000', '2026-10-29T11:16:26.4700000'),
        (9, N'CUST006', N'PT.Customer 006', NULL, NULL, NULL, 1, '2026-10-29T10:17:43.2440000', NULL),
        (10, N'CUST007', N'PT.Customer 007', NULL, NULL, NULL, 1, '2026-10-29T13:45:29.8190000', NULL),
        (11, N'CUST008', N'PT.Customer 008', NULL, NULL, NULL, 1, '2026-10-29T13:50:11.5840000', NULL),
        (12, N'CUST010', N'Customer 10', NULL, NULL, NULL, 1, '2026-10-29T14:50:24.8980000', '2026-10-29T14:50:40.2310000');
    SET IDENTITY_INSERT dbo.Customer OFF;
    IF EXISTS (SELECT 1 FROM dbo.Customer) BEGIN DECLARE @Max_Customer int = (SELECT MAX(Id) FROM dbo.Customer); DBCC CHECKIDENT ('dbo.Customer', RESEED, @Max_Customer) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.Customer', RESEED, 0) WITH NO_INFOMSGS;

    -- dbo.Location (41 baris)
    SET IDENTITY_INSERT dbo.Location ON;
    INSERT INTO dbo.Location ([Id], [CoCode], [Name], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, 'ABL', N'Main Office 1st floor', 1, '2026-11-03T14:55:38.5390000', N'seed', '2026-11-03T14:58:15.2010000', N'uji'),
        (2, 'ABL', N'Main Office 2nd floor', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (3, 'ABL', N'HRGA', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (4, 'ABL', N'Interco Meeting Room', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (5, 'ABL', N'Pos 1 Security', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (6, 'ABL', N'Pos 2 Security', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (7, 'ABL', N'Pos 3 Security', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (8, 'ABL', N'Pos 4 Security', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (9, 'ABL', N'Pos 5 Security', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (10, 'ABL', N'Paper Raw Material', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (11, 'ABL', N'Purchasing Office', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (12, 'ABL', N'Warehouse & Logistic Office', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (13, 'ABL', N'Paper Finished Goods', 1, '2026-11-03T14:55:38.5390000', N'seed', '2026-11-03T15:16:43.2480000', N'hdahlia'),
        (14, 'ABL', N'Tissue Finished Goods', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (15, 'ABL', N'Canteen & Hall', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (16, 'ABL', N'Mess', 1, '2026-11-03T14:55:38.5390000', N'seed', '2026-11-03T15:07:33.1690000', N'hdahlia'),
        (17, 'ABL', N'Multi Purpose Hall', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (18, 'ABL', N'MO Office', 1, '2026-11-03T14:55:38.5390000', N'seed', '2026-11-03T15:25:41.6680000', N'hdahlia'),
        (19, 'ABL', N'Finishing Office', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (20, 'ABL', N'TPM Office', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (21, 'ABL', N'Converting Office', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (22, 'ABL', N'Cassie Meeting Room', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (23, 'ABL', N'Fabrication Area', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (24, 'ABL', N'Engineering Office', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (25, 'ABL', N'Heavy Equipment', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (26, 'ABL', N'Workshop', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (27, 'ABL', N'Elektrical Office', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (28, 'ABL', N'Parking Lot', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (29, 'ABL', N'Boiler', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (30, 'ABL', N'Reverse Osmosis', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (31, 'ABL', N'Utility Office', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (32, 'ABL', N'Fiber Storage', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (33, 'ABL', N'Tissue Raw Material', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (34, 'ABL', N'TPM Mill', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (35, 'ABL', N'PM Mill', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (36, 'ABL', N'Finishing Mill', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (37, 'ABL', N'Converting Mill', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (38, 'ABL', N'Water Treatment', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (39, 'ABL', N'Waste Pond', 1, '2026-11-03T14:55:38.5390000', N'seed', NULL, NULL),
        (40, 'ABL', N'PM 3 Mill', 1, '2026-11-03T14:55:38.5390000', N'seed', '2026-11-03T15:26:11.9640000', N'hdahlia'),
        (41, 'NKM', N'Gudang Uji', 1, '2026-11-03T14:56:33.9200000', N'uji', NULL, NULL);
    SET IDENTITY_INSERT dbo.Location OFF;
    IF EXISTS (SELECT 1 FROM dbo.Location) BEGIN DECLARE @Max_Location int = (SELECT MAX(Id) FROM dbo.Location); DBCC CHECKIDENT ('dbo.Location', RESEED, @Max_Location) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.Location', RESEED, 0) WITH NO_INFOMSGS;

    -- dbo.AttachmentType (15 baris)
    SET IDENTITY_INSERT dbo.AttachmentType ON;
    INSERT INTO dbo.AttachmentType ([Id], [Code], [Name], [Stage], [AllowedExtensions], [MaxSizeMB], [IsMandatoryCapex], [IsMandatoryOpex], [IsMandatoryLve], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, 'ROI', N'ROI Calculation', 'REQUEST', 'pdf,jpg,png', 5, 1, 0, 0, 1, '2026-11-03T15:47:38.9870000', N'seed', NULL, NULL),
        (2, 'AREA_PHOTO', N'Area Photo', 'REQUEST', 'pdf,jpg,png', 5, 1, 1, 1, 1, '2026-11-03T15:47:38.9870000', N'seed', NULL, NULL),
        (3, 'BOQ', N'Bill of Quantities', 'DOCUMENT', 'pdf,xlsx,dwg', 20, 1, 1, 1, 1, '2026-11-03T15:47:38.9870000', N'seed', NULL, NULL),
        (4, 'DRAWING', N'Drawing', 'DOCUMENT', 'pdf,xlsx,dwg', 20, 1, 0, 0, 1, '2026-11-03T15:47:38.9870000', N'seed', NULL, NULL),
        (5, 'TOR', N'Terms of Reference', 'PROCUREMENT', 'pdf,xlsx,dwg', 20, 0, 0, 0, 1, '2026-11-03T15:47:38.9870000', N'seed', NULL, NULL),
        (6, 'CONTRACT', N'Contract', 'CONTRACT', 'pdf,xlsx,dwg', 20, 0, 0, 0, 1, '2026-11-03T15:47:38.9870000', N'seed', NULL, NULL),
        (7, 'BAPP', N'BAPP', 'BAPP', 'pdf,xlsx,dwg', 20, 0, 0, 0, 1, '2026-11-03T15:47:38.9870000', N'seed', '2026-11-18T13:28:49.8810000', N'seed'),
        (8, 'ACTUAL_COST', N'Actual Cost Upload', 'COST', 'xlsx', 5, 0, 0, 0, 1, '2026-11-03T15:47:38.9870000', N'seed', NULL, NULL),
        (9, 'ADDENDUM', N'Draft Contract Addendum', 'ADDENDUM', 'pdf,xlsx,dwg', 20, 0, 0, 0, 1, '2026-11-17T14:06:13.4300000', N'seed', '2026-11-18T10:08:15.7320000', N'seed'),
        (10, 'BOQ_REVISION', N'Revised BOQ', 'ADDENDUM', 'pdf,xlsx,dwg', 20, 0, 0, 0, 1, '2026-11-17T14:06:13.4300000', N'seed', NULL, NULL),
        (11, 'ADDENDUM_FINAL', N'Signed Contract Addendum', 'ADDENDUM', 'pdf,xlsx,dwg', 20, 0, 0, 0, 1, '2026-11-18T10:08:15.7280000', N'seed', NULL, NULL),
        (12, 'BAPP_PHOTO_INITIAL', N'Photo - Initial', 'BAPP', 'jpg,jpeg,png', 10, 1, 1, 1, 1, '2026-11-18T13:28:49.9000000', N'seed', '2026-11-18T13:55:08.0290000', N'seed'),
        (13, 'BAPP_PHOTO_PROGRESS', N'Photo - Progress', 'BAPP', 'jpg,jpeg,png', 10, 1, 1, 1, 1, '2026-11-18T13:28:49.9000000', N'seed', '2026-11-18T13:55:08.0290000', N'seed'),
        (14, 'BAPP_PHOTO_FINAL', N'Photo - Final', 'BAPP', 'jpg,jpeg,png', 10, 1, 1, 1, 1, '2026-11-18T13:28:49.9000000', N'seed', '2026-11-18T13:55:08.0290000', N'seed'),
        (15, 'ACTUAL_DETAIL', N'Actual Cost Detail', 'COST', 'pdf,xlsx,jpg,png', 20, 0, 0, 0, 1, '2026-11-18T14:36:04.9540000', N'seed', NULL, NULL);
    SET IDENTITY_INSERT dbo.AttachmentType OFF;
    IF EXISTS (SELECT 1 FROM dbo.AttachmentType) BEGIN DECLARE @Max_AttachmentType int = (SELECT MAX(Id) FROM dbo.AttachmentType); DBCC CHECKIDENT ('dbo.AttachmentType', RESEED, @Max_AttachmentType) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.AttachmentType', RESEED, 0) WITH NO_INFOMSGS;

    -- dbo.AssessmentQuestion (12 baris)
    SET IDENTITY_INSERT dbo.AssessmentQuestion ON;
    INSERT INTO dbo.AssessmentQuestion ([Id], [SortOrder], [QuestionText], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, 1, N'Is the proposed area suitable and ready for the project?', 1, '2026-11-03T15:54:41.7950000', N'seed', '2026-11-04T07:52:51.9660000', N'hdahlia'),
        (2, 2, N'Is the proposed location available for construction?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (3, 3, N'Has the existing site condition been assessed?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (4, 4, N'Is a layout drawing available?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (5, 5, N'Is the required scope of work clearly defined?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (6, 6, N'Is the project required to meet safety or regulatory requirements?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (7, 7, N'Will the project affect existing operations?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (8, 8, N'Is there any alternative location or solution?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (9, 9, N'Is the proposed completion date critical to operations?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (10, 10, N'Is the estimated budget available?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (11, 11, N'Are any utilities or supporting facilities required?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL),
        (12, 12, N'Are there any special restrictions or requirements?', 1, '2026-11-03T15:54:41.7950000', N'seed', NULL, NULL);
    SET IDENTITY_INSERT dbo.AssessmentQuestion OFF;
    IF EXISTS (SELECT 1 FROM dbo.AssessmentQuestion) BEGIN DECLARE @Max_AssessmentQuestion int = (SELECT MAX(Id) FROM dbo.AssessmentQuestion); DBCC CHECKIDENT ('dbo.AssessmentQuestion', RESEED, @Max_AssessmentQuestion) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.AssessmentQuestion', RESEED, 0) WITH NO_INFOMSGS;

    -- dbo.SurveyTemplateItem (15 baris)
    SET IDENTITY_INSERT dbo.SurveyTemplateItem ON;
    INSERT INTO dbo.SurveyTemplateItem ([Id], [Category], [SortOrder], [ItemText], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, 'CAPEX', 1, N'Compliance with user requirements', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (2, 'CAPEX', 2, N'Work quality', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (3, 'CAPEX', 3, N'Timeliness of completion', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (4, 'CAPEX', 4, N'Communication and coordination', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (5, 'CAPEX', 5, N'Site cleanliness and housekeeping', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (6, 'OPEX', 1, N'Compliance with user requirements', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (7, 'OPEX', 2, N'Work quality', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (8, 'OPEX', 3, N'Timeliness of completion', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (9, 'OPEX', 4, N'Communication and coordination', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (10, 'OPEX', 5, N'Site cleanliness and housekeeping', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (11, 'LVE', 1, N'Compliance with user requirements', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (12, 'LVE', 2, N'Work quality', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (13, 'LVE', 3, N'Timeliness of completion', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (14, 'LVE', 4, N'Communication and coordination', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL),
        (15, 'LVE', 5, N'Site cleanliness and housekeeping', 1, '2026-11-03T16:03:38.8810000', N'seed', NULL, NULL);
    SET IDENTITY_INSERT dbo.SurveyTemplateItem OFF;
    IF EXISTS (SELECT 1 FROM dbo.SurveyTemplateItem) BEGIN DECLARE @Max_SurveyTemplateItem int = (SELECT MAX(Id) FROM dbo.SurveyTemplateItem); DBCC CHECKIDENT ('dbo.SurveyTemplateItem', RESEED, @Max_SurveyTemplateItem) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.SurveyTemplateItem', RESEED, 0) WITH NO_INFOMSGS;

    -- dbo.SubCategory (12 baris)
    SET IDENTITY_INSERT dbo.SubCategory ON;
    INSERT INTO dbo.SubCategory ([Id], [Category], [Code], [Name], [SortOrder], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, 'CAPEX', 'CONSTRUCTION_PROJECT', N'Construction project', 1, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (2, 'CAPEX', 'FACILITY_EXPANSION', N'Facility expansion', 2, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (3, 'CAPEX', 'MAJOR_RENOVATION', N'Major renovation', 3, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (4, 'CAPEX', 'ASSET_UPGRADE', N'Asset upgrade', 4, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (5, 'OPEX', 'PREVENTIVE_MAINT', N'Preventive maintenance', 1, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (6, 'OPEX', 'CORRECTIVE_MAINT', N'Corrective maintenance', 2, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (7, 'OPEX', 'EMERGENCY_MAINT', N'Emergency maintenance', 3, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (8, 'OPEX', 'CIVIL_IMPROVEMENT', N'Civil improvement', 4, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (9, 'LVE', 'MINOR_CIVIL_WORKS', N'Minor civil works', 1, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (10, 'LVE', 'JDI_REQUISITION', N'JDI requisition', 2, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (11, 'LVE', 'NON_VALUE_ADDED', N'Non value-added requisition', 3, 1, '2026-11-04T08:44:30.3340000', N'seed', NULL, NULL),
        (15, 'OPEX', 'ROAD_WORK', N'Road Work', 5, 0, '2026-11-04T08:54:14.5630000', N'hdahlia', '2026-11-04T08:55:01.0280000', N'hdahlia');
    SET IDENTITY_INSERT dbo.SubCategory OFF;
    IF EXISTS (SELECT 1 FROM dbo.SubCategory) BEGIN DECLARE @Max_SubCategory int = (SELECT MAX(Id) FROM dbo.SubCategory); DBCC CHECKIDENT ('dbo.SubCategory', RESEED, @Max_SubCategory) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.SubCategory', RESEED, 0) WITH NO_INFOMSGS;

    -- dbo.Unit (12 baris)
    SET IDENTITY_INSERT dbo.Unit ON;
    INSERT INTO dbo.Unit ([Id], [Name], [Description], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
        (1, N'm', N'Meter', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (2, N'm²', N'Square meter', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (3, N'm³', N'Cubic meter', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (4, N'kg', N'Kilogram', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (5, N'ton', N'Ton', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (6, N'unit', N'Unit', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (7, N'set', N'Set', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (8, N'lot', N'Lot', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (9, N'ls', N'Lump sum', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (10, N'hari', N'Day', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (11, N'jam', N'Hour', 1, '2026-11-16T09:52:09.3610000', N'seed', NULL, NULL),
        (12, N'roll', N'Roll', 1, '2026-11-16T09:53:52.5060000', N'uji', NULL, NULL);
    SET IDENTITY_INSERT dbo.Unit OFF;
    IF EXISTS (SELECT 1 FROM dbo.Unit) BEGIN DECLARE @Max_Unit int = (SELECT MAX(Id) FROM dbo.Unit); DBCC CHECKIDENT ('dbo.Unit', RESEED, @Max_Unit) WITH NO_INFOMSGS; END
    ELSE DBCC CHECKIDENT ('dbo.Unit', RESEED, 0) WITH NO_INFOMSGS;

    COMMIT TRANSACTION;
    PRINT N'CIMS publish: BAGIAN 2 (data) selesai.';
END
GO
PRINT N'CIMS publish: SELESAI (' + CONVERT(nvarchar(19), GETDATE(), 120) + N')';
GO
SET NOEXEC OFF;
GO
