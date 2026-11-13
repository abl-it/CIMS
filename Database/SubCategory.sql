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
