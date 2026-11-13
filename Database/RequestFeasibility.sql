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

   DECLARE @Id INT = 3, @Civil NVARCHAR(100) = N'<user civil>', @Bukan NVARCHAR(100) = N'marisi';

   -- 1) Bukan civil -> 50075; alasan kosong / sub-kategori tidak cocok kategori -> 50072
   DECLARE @Sub INT = (SELECT TOP (1) Id FROM dbo.SubCategory WHERE Category = 'CAPEX' AND IsActive = 1 ORDER BY SortOrder);
   DECLARE @SubOpex INT = (SELECT TOP (1) Id FROM dbo.SubCategory WHERE Category = 'OPEX' AND IsActive = 1 ORDER BY SortOrder);
   BEGIN TRY EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Bukan, @Category = 'CAPEX', @SubCategoryId = @Sub, @Reason = N'x';
   END TRY BEGIN CATCH SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Civil, @Category = 'CAPEX', @SubCategoryId = @Sub, @Reason = N' ';
   END TRY BEGIN CATCH SELECT '1b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_ChangeCategory @Id = @Id, @Username = @Civil, @Category = 'CAPEX', @SubCategoryId = @SubOpex, @Reason = N'x';
   END TRY BEGIN CATCH SELECT '1c expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

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
   END TRY BEGIN CATCH SELECT '4b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 5) FEASIBLE tanpa lampiran ROI (CAPEX) -> 50072 menyebut ROI; upload ROI lewat aplikasi sebagai civil, lalu
   --    jalankan lagi tanpa TRY/CATCH -> DOC_PREPARATION
   BEGIN TRY EXEC dbo.usp_Request_FeasibilityDecide @Id = @Id, @Username = @Civil, @Decision = 'FEASIBLE';
   END TRY BEGIN CATCH SELECT '5 expect 50072 (ROI)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   --    berhasil -> DOC_PREPARATION; ubah kategori lagi -> 50074; tugas FEASIBILITY civil hilang
   SELECT * FROM dbo.fn_User_Tasks(@Civil) WHERE RequestId = @Id;

   -- 6) Request FEASIBILITY lain: REVISE tanpa catatan -> 50072; REVISE -> RETURNED (requester Resubmit -> Kabag lagi);
   --    REJECT dengan alasan -> REJECTED
   --EXEC dbo.usp_Request_FeasibilityDecide @Id = <id>, @Username = @Civil, @Decision = 'REVISE', @Remarks = N'Please add drawing reference';
   --EXEC dbo.usp_Request_FeasibilityDecide @Id = <id>, @Username = @Civil, @Decision = 'REJECT', @Remarks = N'Not feasible on this site';
   ===================================================================== */
