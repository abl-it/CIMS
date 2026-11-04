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
