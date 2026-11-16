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
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveSchedule
    @Id                INT,
    @Username          NVARCHAR(100),
    @ProjectStartDate  DATE,
    @ActionPlanJson    NVARCHAR(MAX),
    @Reason            NVARCHAR(MAX) = NULL
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

    -- Id lama harus milik request ini
    IF EXISTS (SELECT 1 FROM @Items i WHERE i.ItemId IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a WHERE a.Id = i.ItemId AND a.RequestId = @Id))
        THROW 50072, N'Action plan data is outdated. Please reload the page.', 1;

    DECLARE @NewEnd DATE = (SELECT MAX(EndDate) FROM @Items);

    IF @Status = 'IN_PROGRESS'
    BEGIN
        -- Perubahan saat berjalan: alasan wajib dan data tetap lengkap (Keputusan 14-11-2026)
        IF @Reason IS NULL
            THROW 50072, N'Reason is required to change the schedule while the project is in progress.', 1;
        IF @TotalWeight <> 100
        BEGIN
            SET @Msg = N'Total action plan weight must be 100% (currently ' + FORMAT(@TotalWeight, N'0.##', 'en-US') + N'%).';
            THROW 50072, @Msg, 1;
        END
        IF @HandoverDate IS NOT NULL AND @ProjectStartDate > @HandoverDate
            THROW 50072, N'Project start date cannot be after the site handover date.', 1;
        IF EXISTS (SELECT 1 FROM dbo.ProjectCostEstimate e
                   WHERE e.RequestId = @Id
                     AND (e.PeriodMonth < DATEFROMPARTS(YEAR(@ProjectStartDate), MONTH(@ProjectStartDate), 1)
                          OR e.PeriodMonth > DATEFROMPARTS(YEAR(@NewEnd), MONTH(@NewEnd), 1)))
            THROW 50072, N'Some cost estimate months fall outside the new schedule. Adjust the cost estimate first.', 1;
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

    IF @Status = 'IN_PROGRESS'
        INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
        VALUES (@Id, 'SCHEDULE_CHANGE', @Status, @Status, LEFT(@Reason, 1000), @Username, @Now);

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Request_SaveCostEstimate  (civil; SCHEDULING atau IN_PROGRESS; ganti seluruh estimasi)
      @EstimateJson: [{"month":"2026-12-01","amount":1500000}, ...]  (tanggal apa pun di bulan itu boleh)
      Bulan hanya dari bulan mulai s.d. bulan selesai project (Keputusan 14-11-2026); wajib schedule dulu.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveCostEstimate
    @Id            INT,
    @Username      NVARCHAR(100),
    @EstimateJson  NVARCHAR(MAX),
    @Reason        NVARCHAR(MAX) = NULL
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

    DECLARE @Total DECIMAL(18, 2) = ISNULL((SELECT SUM(Amount) FROM @Items), 0);

    IF @PlanCost IS NOT NULL AND @Total > @PlanCost
    BEGIN
        SET @Msg = N'Total cost estimate (IDR ' + FORMAT(@Total, N'#,0.##', 'en-US') + N') must not exceed the plan cost (IDR '
                 + FORMAT(@PlanCost, N'#,0.##', 'en-US') + N').';
        THROW 50072, @Msg, 1;
    END

    IF @Status = 'IN_PROGRESS'
    BEGIN
        IF @Reason IS NULL
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

    IF @Status = 'IN_PROGRESS'
        INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
        VALUES (@Id, 'ESTIMATE_CHANGE', @Status, @Status, LEFT(@Reason, 1000), @Username, @Now);

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
