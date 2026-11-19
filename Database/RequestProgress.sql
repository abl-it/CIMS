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
