/* =====================================================================
   Vendor.sql  -  Master data Vendor (T4-1; PRD MD-03, BR-11)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan : Vendor dipakai bersama ABL dan NKM (Purchasing melayani keduanya). Isi awal kosong (MD-03).
             Pengelola: purchasing, civil, administrator (hak di Controller).
             Code unik (tidak peka huruf besar/kecil sesuai collation DB). Soft delete lewat SetActive.
   Error   : 50081 = Code duplikat
             50082 = Input wajib kosong / tidak valid
             50083 = Data tidak ditemukan
             50084 = Nomor vendor ERP duplikat
             ErpVendorNo = nomor vendor di ERP; opsional, unik bila diisi (disimpan huruf besar).
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Vendor', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Vendor
    (
        Id             INT IDENTITY(1,1) NOT NULL,
        Code           VARCHAR(20)    NOT NULL,
        ErpVendorNo    VARCHAR(30)    NULL,       -- nomor vendor di ERP (opsional, unik bila diisi)
        Name           NVARCHAR(150)  NOT NULL,
        ContactPerson  NVARCHAR(100)  NULL,
        Phone          VARCHAR(30)    NULL,
        Email          VARCHAR(100)   NULL,
        Address        NVARCHAR(300)  NULL,
        IsActive       BIT            NOT NULL CONSTRAINT DF_Vendor_IsActive  DEFAULT (1),
        CreatedAt      DATETIME2(3)   NOT NULL CONSTRAINT DF_Vendor_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy      NVARCHAR(100)  NULL,
        UpdatedAt      DATETIME2(3)   NULL,
        UpdatedBy      NVARCHAR(100)  NULL,
        CONSTRAINT PK_Vendor PRIMARY KEY CLUSTERED (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Vendor_Code' AND object_id = OBJECT_ID(N'dbo.Vendor'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Vendor_Code ON dbo.Vendor (Code);
END
GO

-- Migrasi: tabel yang sudah dibuat sebelum kolom ErpVendorNo ada
IF COL_LENGTH(N'dbo.Vendor', N'ErpVendorNo') IS NULL
BEGIN
    ALTER TABLE dbo.Vendor ADD ErpVendorNo VARCHAR(30) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Vendor_ErpVendorNo' AND object_id = OBJECT_ID(N'dbo.Vendor'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Vendor_ErpVendorNo ON dbo.Vendor (ErpVendorNo) WHERE ErpVendorNo IS NOT NULL;
END
GO

/* ---------------------------------------------------------------------
   2. usp_Vendor_GetPaged
      Search (Code, Name, ContactPerson), filter status, sorting whitelist, paging.
      @SortBy  : Code | Name | CreatedAt   (default Name)
      @SortDir : ASC | DESC                (default ASC)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_GetPaged
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
    SET @SortBy     = CASE WHEN @SortBy IN (N'Code', N'Name', N'CreatedAt') THEN @SortBy ELSE N'Name' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.Vendor
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%'
                             OR ErpVendorNo LIKE N'%' + @Search + N'%' OR ContactPerson LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Code, ErpVendorNo, Name, ContactPerson, Phone, Email, Address, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Vendor
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%'
                             OR ErpVendorNo LIKE N'%' + @Search + N'%' OR ContactPerson LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'ASC'  THEN Code      END ASC,
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'DESC' THEN Code      END DESC,
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
   3. usp_Vendor_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, ErpVendorNo, Name, ContactPerson, Phone, Email, Address, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Vendor
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Vendor_GetActive  (pilihan dropdown kontrak; @IncludeId = vendor terpilih walau nonaktif)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_GetActive
    @IncludeId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, ErpVendorNo, Name
    FROM dbo.Vendor
    WHERE IsActive = 1 OR Id = @IncludeId
    ORDER BY Name, Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Vendor_Insert  (@NewId OUTPUT; @ActionBy = username pelaku)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_Insert
    @Code           VARCHAR(20),
    @Name           NVARCHAR(150),
    @ErpVendorNo    VARCHAR(30)   = NULL,
    @ContactPerson  NVARCHAR(100) = NULL,
    @Phone          VARCHAR(30)   = NULL,
    @Email          VARCHAR(100)  = NULL,
    @Address        NVARCHAR(300) = NULL,
    @IsActive       BIT           = 1,
    @ActionBy       NVARCHAR(100) = NULL,
    @NewId          INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code          = UPPER(LTRIM(RTRIM(@Code)));
    SET @Name          = LTRIM(RTRIM(@Name));
    SET @ContactPerson = NULLIF(LTRIM(RTRIM(@ContactPerson)), N'');
    SET @Phone         = NULLIF(LTRIM(RTRIM(@Phone)), '');
    SET @Email         = NULLIF(LTRIM(RTRIM(@Email)), '');
    SET @Address       = NULLIF(LTRIM(RTRIM(@Address)), N'');
    SET @ErpVendorNo   = NULLIF(UPPER(LTRIM(RTRIM(@ErpVendorNo))), '');

    IF ISNULL(@Code, '') = ''   THROW 50082, N'Vendor code is required.', 1;
    IF ISNULL(@Name, N'') = N'' THROW 50082, N'Vendor name is required.', 1;
    IF @Email IS NOT NULL AND @Email NOT LIKE '%_@_%._%'
        THROW 50082, N'Email is invalid.', 1;

    BEGIN TRY
        INSERT INTO dbo.Vendor (Code, ErpVendorNo, Name, ContactPerson, Phone, Email, Address, IsActive, CreatedBy)
        VALUES (@Code, @ErpVendorNo, @Name, @ContactPerson, @Phone, @Email, @Address, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627) AND ERROR_MESSAGE() LIKE N'%UX_Vendor_ErpVendorNo%'
            THROW 50084, N'ERP vendor number is already in use.', 1;
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50081, N'Vendor code is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   6. usp_Vendor_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_Update
    @Id             INT,
    @Code           VARCHAR(20),
    @Name           NVARCHAR(150),
    @ErpVendorNo    VARCHAR(30)   = NULL,
    @ContactPerson  NVARCHAR(100) = NULL,
    @Phone          VARCHAR(30)   = NULL,
    @Email          VARCHAR(100)  = NULL,
    @Address        NVARCHAR(300) = NULL,
    @IsActive       BIT           = 1,
    @ActionBy       NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code          = UPPER(LTRIM(RTRIM(@Code)));
    SET @Name          = LTRIM(RTRIM(@Name));
    SET @ContactPerson = NULLIF(LTRIM(RTRIM(@ContactPerson)), N'');
    SET @Phone         = NULLIF(LTRIM(RTRIM(@Phone)), '');
    SET @Email         = NULLIF(LTRIM(RTRIM(@Email)), '');
    SET @Address       = NULLIF(LTRIM(RTRIM(@Address)), N'');
    SET @ErpVendorNo   = NULLIF(UPPER(LTRIM(RTRIM(@ErpVendorNo))), '');

    IF ISNULL(@Code, '') = ''   THROW 50082, N'Vendor code is required.', 1;
    IF ISNULL(@Name, N'') = N'' THROW 50082, N'Vendor name is required.', 1;
    IF @Email IS NOT NULL AND @Email NOT LIKE '%_@_%._%'
        THROW 50082, N'Email is invalid.', 1;

    BEGIN TRY
        UPDATE dbo.Vendor
        SET Code          = @Code,
            ErpVendorNo   = @ErpVendorNo,
            Name          = @Name,
            ContactPerson = @ContactPerson,
            Phone         = @Phone,
            Email         = @Email,
            Address       = @Address,
            IsActive      = ISNULL(@IsActive, IsActive),
            UpdatedAt     = SYSDATETIME(),
            UpdatedBy     = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50083, N'Vendor not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627) AND ERROR_MESSAGE() LIKE N'%UX_Vendor_ErpVendorNo%'
            THROW 50084, N'ERP vendor number is already in use.', 1;
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50081, N'Vendor code is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_Vendor_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Vendor_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Vendor
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50083, N'Vendor not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok; baris error dijalankan sendiri-sendiri)

   -- 1) Insert, lalu duplikat (beda huruf besar/kecil) -> 50081
   DECLARE @NewId INT;
   EXEC dbo.usp_Vendor_Insert @Code = 'v-001', @Name = N'PT Uji Konstruksi', @ContactPerson = N'Budi',
        @Phone = '0811', @Email = 'budi@uji.co.id', @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;                                                  -- Code tersimpan 'V-001'
   EXEC dbo.usp_Vendor_Insert @Code = 'V-001', @Name = N'Lain';              -- 50081

   -- 1b) Nomor vendor ERP: opsional; diisi -> unik (50084); dua vendor tanpa nomor ERP -> boleh
   EXEC dbo.usp_Vendor_Insert @Code = 'V-010', @Name = N'PT ERP Satu', @ErpVendorNo = 'erp-1001';   -- tersimpan 'ERP-1001'
   EXEC dbo.usp_Vendor_Insert @Code = 'V-011', @Name = N'PT ERP Dua',  @ErpVendorNo = 'ERP-1001';   -- 50084
   EXEC dbo.usp_Vendor_Insert @Code = 'V-012', @Name = N'PT Tanpa ERP';                             -- boleh
   DECLARE @T INT; EXEC dbo.usp_Vendor_GetPaged @Search = N'1001', @TotalCount = @T OUTPUT;           -- V-010 muncul

   -- 2) Validasi -> 50082
   EXEC dbo.usp_Vendor_Insert @Code = ' ', @Name = N'A';
   EXEC dbo.usp_Vendor_Insert @Code = 'V-002', @Name = N'A', @Email = 'bukan-email';

   -- 3) List + lookup aktif
   DECLARE @Total INT;
   EXEC dbo.usp_Vendor_GetPaged @Search = N'uji', @IsActive = 1, @TotalCount = @Total OUTPUT;
   SELECT @Total AS TotalCount;
   EXEC dbo.usp_Vendor_GetActive;

   -- 4) Update, nonaktifkan (hilang dari GetActive kecuali @IncludeId), Id tidak ada -> 50083
   EXEC dbo.usp_Vendor_Update @Id = 1, @Code = 'V-001', @Name = N'PT Uji Konstruksi (Rev)', @ActionBy = N'uji';
   EXEC dbo.usp_Vendor_SetActive @Id = 1, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_Vendor_GetActive @IncludeId = 1;                             -- tetap muncul
   EXEC dbo.usp_Vendor_SetActive @Id = 1, @IsActive = 1, @ActionBy = N'uji';
   EXEC dbo.usp_Vendor_SetActive @Id = 999999, @IsActive = 0;                -- 50083
   ===================================================================== */
