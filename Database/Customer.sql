/* =====================================================================
   Customer.sql  -  Modul pilot: Customer (master data CRUD)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Error   : 50001 = Kode duplikat
             50002 = Input wajib kosong
             50003 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Customer', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Customer
    (
        Id          INT IDENTITY(1,1)  NOT NULL,
        Code        NVARCHAR(20)       NOT NULL,
        Name        NVARCHAR(100)      NOT NULL,
        Phone       NVARCHAR(20)       NULL,
        Email       NVARCHAR(100)      NULL,
        Address     NVARCHAR(250)      NULL,
        IsActive    BIT                NOT NULL CONSTRAINT DF_Customer_IsActive  DEFAULT (1),
        CreatedAt   DATETIME2(3)       NOT NULL CONSTRAINT DF_Customer_CreatedAt DEFAULT (SYSDATETIME()),
        UpdatedAt   DATETIME2(3)       NULL,
        CONSTRAINT PK_Customer PRIMARY KEY CLUSTERED (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_Customer_Code' AND object_id = OBJECT_ID(N'dbo.Customer'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Customer_Code ON dbo.Customer (Code);
END
GO

/* ---------------------------------------------------------------------
   2. usp_Customer_GetPaged
      Search (Code/Name), filter status, sorting whitelist, paging.
      @SortBy  : Code | Name | CreatedAt   (default Code)
      @SortDir : ASC | DESC                (default ASC)
      @TotalCount = total baris setelah filter (OUTPUT)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_GetPaged
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Code',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy  IN (N'Code', N'Name', N'CreatedAt') THEN @SortBy  ELSE N'Code' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.Customer
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%'
                             OR Name LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Code, Name, Phone, Email, Address, IsActive, CreatedAt, UpdatedAt
    FROM dbo.Customer
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%'
                             OR Name LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'ASC'  THEN Code      END ASC,
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'DESC' THEN Code      END DESC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   3. usp_Customer_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, Name, Phone, Email, Address, IsActive, CreatedAt, UpdatedAt
    FROM dbo.Customer
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Customer_Insert
      @NewId = Id baru (OUTPUT)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_Insert
    @Code      NVARCHAR(20),
    @Name      NVARCHAR(100),
    @Phone     NVARCHAR(20)  = NULL,
    @Email     NVARCHAR(100) = NULL,
    @Address   NVARCHAR(250) = NULL,
    @IsActive  BIT           = 1,
    @NewId     INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code    = LTRIM(RTRIM(@Code));
    SET @Name    = LTRIM(RTRIM(@Name));
    SET @Phone   = NULLIF(LTRIM(RTRIM(@Phone)),   N'');
    SET @Email   = NULLIF(LTRIM(RTRIM(@Email)),   N'');
    SET @Address = NULLIF(LTRIM(RTRIM(@Address)), N'');

    IF ISNULL(@Code, N'') = N'' THROW 50002, N'Kode customer wajib diisi.', 1;
    IF ISNULL(@Name, N'') = N'' THROW 50002, N'Nama customer wajib diisi.', 1;

    BEGIN TRY
        INSERT INTO dbo.Customer (Code, Name, Phone, Email, Address, IsActive)
        VALUES (@Code, @Name, @Phone, @Email, @Address, ISNULL(@IsActive, 1));

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50001, N'Kode customer sudah digunakan.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   5. usp_Customer_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_Update
    @Id        INT,
    @Code      NVARCHAR(20),
    @Name      NVARCHAR(100),
    @Phone     NVARCHAR(20)  = NULL,
    @Email     NVARCHAR(100) = NULL,
    @Address   NVARCHAR(250) = NULL,
    @IsActive  BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code    = LTRIM(RTRIM(@Code));
    SET @Name    = LTRIM(RTRIM(@Name));
    SET @Phone   = NULLIF(LTRIM(RTRIM(@Phone)),   N'');
    SET @Email   = NULLIF(LTRIM(RTRIM(@Email)),   N'');
    SET @Address = NULLIF(LTRIM(RTRIM(@Address)), N'');

    IF ISNULL(@Code, N'') = N'' THROW 50002, N'Kode customer wajib diisi.', 1;
    IF ISNULL(@Name, N'') = N'' THROW 50002, N'Nama customer wajib diisi.', 1;

    BEGIN TRY
        UPDATE dbo.Customer
        SET Code      = @Code,
            Name      = @Name,
            Phone     = @Phone,
            Email     = @Email,
            Address   = @Address,
            IsActive  = ISNULL(@IsActive, IsActive),
            UpdatedAt = SYSDATETIME()
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50003, N'Data customer tidak ditemukan.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50001, N'Kode customer sudah digunakan.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   6. usp_Customer_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Customer_SetActive
    @Id        INT,
    @IsActive  BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Customer
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME()
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50003, N'Data customer tidak ditemukan.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Insert
   DECLARE @NewId INT;
   EXEC dbo.usp_Customer_Insert @Code = N'CUST001', @Name = N'PT Contoh Satu',
        @Phone = N'0721-123456', @Email = N'a@contoh.co.id', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;

   -- 2) Duplikat -> harus error 50001
   EXEC dbo.usp_Customer_Insert @Code = N'cust001', @Name = N'Duplikat';

   -- 3) List + paging
   DECLARE @Total INT;
   EXEC dbo.usp_Customer_GetPaged @Search = N'contoh', @IsActive = 1,
        @SortBy = N'Name', @SortDir = N'DESC', @PageNumber = 1, @PageSize = 10,
        @TotalCount = @Total OUTPUT;
   SELECT @Total AS TotalCount;

   -- 4) Update, soft delete, get by id
   EXEC dbo.usp_Customer_Update @Id = 1, @Code = N'CUST001', @Name = N'PT Contoh Satu (Rev)';
   EXEC dbo.usp_Customer_SetActive @Id = 1, @IsActive = 0;
   EXEC dbo.usp_Customer_GetById @Id = 1;

   -- 5) Id tidak ada -> harus error 50003
   EXEC dbo.usp_Customer_SetActive @Id = 999999, @IsActive = 0;
   ===================================================================== */
