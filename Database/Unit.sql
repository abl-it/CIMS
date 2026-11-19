/* =====================================================================
   Unit.sql  -  Master data Satuan (T5-2; PRD MD-04, BR-61)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan : Dipakai bersama ABL dan NKM (BR-61). Pengelola: civil, administrator (hak di Controller).
             Satuan item actual cost diketik bebas; master ini hanya daftar saran (Keputusan 16-11-2026).
             Nama unik (tidak peka huruf besar/kecil sesuai collation DB). Soft delete lewat SetActive.
             Seed MERGE hanya MENAMBAH nama yang belum ada (tidak menimpa perubahan).
   Error   : 50091 = Nama satuan duplikat
             50092 = Input wajib kosong / tidak valid
             50093 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Unit', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Unit
    (
        Id           INT IDENTITY(1,1) NOT NULL,
        Name         NVARCHAR(30)  NOT NULL,
        Description  NVARCHAR(100) NULL,
        IsActive     BIT           NOT NULL CONSTRAINT DF_Unit_IsActive  DEFAULT (1),
        CreatedAt    DATETIME2(3)  NOT NULL CONSTRAINT DF_Unit_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy    NVARCHAR(100) NULL,
        UpdatedAt    DATETIME2(3)  NULL,
        UpdatedBy    NVARCHAR(100) NULL,
        CONSTRAINT PK_Unit PRIMARY KEY CLUSTERED (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Unit_Name' AND object_id = OBJECT_ID(N'dbo.Unit'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Unit_Name ON dbo.Unit (Name);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (MD-04; hanya menambah yang belum ada)
   --------------------------------------------------------------------- */
MERGE dbo.Unit AS t
USING (VALUES
        (N'm',    N'Meter'),
        (N'm²',   N'Square meter'),
        (N'm³',   N'Cubic meter'),
        (N'kg',   N'Kilogram'),
        (N'ton',  N'Ton'),
        (N'unit', N'Unit'),
        (N'set',  N'Set'),
        (N'lot',  N'Lot'),
        (N'ls',   N'Lump sum'),
        (N'hari', N'Day'),
        (N'jam',  N'Hour')
      ) AS s (Name, Description)
   ON t.Name = s.Name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Name, Description, CreatedBy)
    VALUES (s.Name, s.Description, N'seed');
GO

/* ---------------------------------------------------------------------
   3. usp_Unit_GetPaged
      @SortBy  : Name | CreatedAt   (default Name) · @SortDir : ASC | DESC (default ASC)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_GetPaged
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Name',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Name', N'CreatedAt') THEN @SortBy ELSE N'Name' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.Unit
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Name LIKE N'%' + @Search + N'%' OR Description LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Name, Description, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Unit
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Name LIKE N'%' + @Search + N'%' OR Description LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Name ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   4. usp_Unit_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Name, Description, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Unit
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Unit_GetActive  (daftar saran satuan pada form actual cost)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_GetActive
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Name, Description
    FROM dbo.Unit
    WHERE IsActive = 1
    ORDER BY Name, Id;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Unit_Insert  (@NewId OUTPUT; @ActionBy = username pelaku)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_Insert
    @Name         NVARCHAR(30),
    @Description  NVARCHAR(100) = NULL,
    @IsActive     BIT           = 1,
    @ActionBy     NVARCHAR(100) = NULL,
    @NewId        INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name        = LTRIM(RTRIM(@Name));
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');

    IF ISNULL(@Name, N'') = N'' THROW 50092, N'Unit name is required.', 1;

    BEGIN TRY
        INSERT INTO dbo.Unit (Name, Description, IsActive, CreatedBy)
        VALUES (@Name, @Description, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50091, N'Unit name is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_Unit_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_Update
    @Id           INT,
    @Name         NVARCHAR(30),
    @Description  NVARCHAR(100) = NULL,
    @IsActive     BIT           = 1,
    @ActionBy     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name        = LTRIM(RTRIM(@Name));
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');

    IF ISNULL(@Name, N'') = N'' THROW 50092, N'Unit name is required.', 1;

    BEGIN TRY
        UPDATE dbo.Unit
        SET Name        = @Name,
            Description = @Description,
            IsActive    = ISNULL(@IsActive, IsActive),
            UpdatedAt   = SYSDATETIME(),
            UpdatedBy   = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50093, N'Unit not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50091, N'Unit name is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   8. usp_Unit_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Unit_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Unit
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50093, N'Unit not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; baris error dijalankan sendiri-sendiri)

   -- 1) Seed: 11 satuan aktif (MD-04)
   SELECT * FROM dbo.Unit ORDER BY Name;
   EXEC dbo.usp_Unit_GetActive;

   -- 2) Insert lalu duplikat (beda huruf besar/kecil) -> 50091; kosong -> 50092
   DECLARE @NewId INT;
   EXEC dbo.usp_Unit_Insert @Name = N'roll', @Description = N'Roll', @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;
   EXEC dbo.usp_Unit_Insert @Name = N'ROLL';                                  -- 50091
   EXEC dbo.usp_Unit_Insert @Name = N'  ';                                    -- 50092

   -- 3) List, update, nonaktif (hilang dari GetActive), Id tidak ada -> 50093
   DECLARE @Total INT; EXEC dbo.usp_Unit_GetPaged @Search = N'm', @TotalCount = @Total OUTPUT; SELECT @Total AS TotalCount;
   EXEC dbo.usp_Unit_Update @Id = @NewId, @Name = N'roll', @Description = N'Roll (paper)', @ActionBy = N'uji';
   EXEC dbo.usp_Unit_SetActive @Id = @NewId, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_Unit_SetActive @Id = 999999, @IsActive = 0;                  -- 50093
   ===================================================================== */
