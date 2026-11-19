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
