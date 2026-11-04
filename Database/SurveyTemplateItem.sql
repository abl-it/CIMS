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
