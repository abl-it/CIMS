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
