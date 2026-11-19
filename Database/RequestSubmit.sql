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
