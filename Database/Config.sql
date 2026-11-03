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
        [Point]              VARCHAR(10)   NOT NULL,   -- REQUEST | MGMT | BAPP
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
        CONSTRAINT CK_WorkflowStep_Point    CHECK ([Point] IN ('REQUEST', 'MGMT', 'BAPP')),
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
        ('*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'3',   'INT',     N'Batas approval susulan Emergency, hari kerja (BR-65)'),
        ('*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'-5',  'DECIMAL', N'Deviasi progress minimum On Track, poin % (BR-68)'),
        ('*', 'SCHEDULE_SLIGHT_MIN_DEV',     N'-15', 'DECIMAL', N'Deviasi minimum Slightly Delay; di bawahnya Delay (BR-68)'),
        ('*', 'COST_ONTRACK_MAX_PCT',        N'100', 'DECIMAL', N'Rasio actual/estimasi maksimum On Track (BR-69)'),
        ('*', 'COST_ATRISK_MAX_PCT',         N'110', 'DECIMAL', N'Rasio maksimum At Risk; di atasnya Over Budget (BR-69)')
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

    DECLARE @Holiday INT =
    (
        SELECT COUNT(*)
        FROM   dbo.WorkCalendarHoliday h
        WHERE  h.CoCode = @CoCode
          AND  h.HolidayDate > @F AND h.HolidayDate <= @T
          AND  NOT EXISTS (SELECT 1
                           FROM   dbo.WorkCalendarWeekend w
                           WHERE  w.CoCode = h.CoCode
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
   ===================================================================== */
