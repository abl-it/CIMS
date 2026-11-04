/* =====================================================================
   AppSetting.sql  -  Halaman Settings: ubah NILAI dbo.AppSetting (T1; PRD CF-02, CF-08, BR-65, BR-68, BR-69)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Config.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Tabel dbo.AppSetting dan seed 5 key ada di Config.sql (T0-1). Script ini tidak mengubah struktur tabel.
     - Halaman hanya mengubah SettingValue baris yang sudah ada (oleh administrator, tercatat UpdatedBy/UpdatedAt).
       Menambah/menghapus key atau baris override per Company tetap lewat script SQL (BR-38).
     - Validasi nilai per ValueType (INT / DECIMAL maks. 2 desimal / STRING) dan rentang per key.
       Pasangan ambang diperiksa terhadap nilai efektif pasangannya pada Company yang sama
       (baris Company, fallback '*'):
         SCHEDULE_SLIGHT_MIN_DEV < SCHEDULE_ONTRACK_MIN_DEV
         COST_ONTRACK_MAX_PCT    < COST_ATRISK_MAX_PCT
   Error   : 50052 = Nilai kosong / tidak valid / di luar rentang
             50053 = Setting tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Deskripsi seed lama (bahasa Indonesia) -> bahasa Inggris (UI wajib Inggris).
      Hanya baris yang deskripsinya masih teks seed lama; deskripsi lain tidak disentuh.
   --------------------------------------------------------------------- */
UPDATE t
SET    t.Description = s.NewText
FROM   dbo.AppSetting t
       JOIN (VALUES
            ('EMERGENCY_FOLLOWUP_WORKDAYS', N'Batas approval susulan Emergency, hari kerja (BR-65)',
                                            N'Emergency follow-up approval limit, working days'),
            ('SCHEDULE_ONTRACK_MIN_DEV',    N'Deviasi progress minimum On Track, poin % (BR-68)',
                                            N'Minimum progress deviation for On Track, % points'),
            ('SCHEDULE_SLIGHT_MIN_DEV',     N'Deviasi minimum Slightly Delay; di bawahnya Delay (BR-68)',
                                            N'Minimum deviation for Slightly Delay; below it is Delay, % points'),
            ('COST_ONTRACK_MAX_PCT',        N'Rasio actual/estimasi maksimum On Track (BR-69)',
                                            N'Maximum actual/estimate ratio for On Track, %'),
            ('COST_ATRISK_MAX_PCT',         N'Rasio maksimum At Risk; di atasnya Over Budget (BR-69)',
                                            N'Maximum ratio for At Risk; above it is Over Budget, %')
            ) AS s (SettingKey, OldText, NewText)
         ON t.SettingKey = s.SettingKey AND t.Description = s.OldText;
GO

/* ---------------------------------------------------------------------
   2. usp_AppSetting_List
      Semua baris (jumlah kecil, tanpa paging). Filter Company opsional ('*', ABL, NKM).
      Urutan: key menurut urutan bisnis (batas waktu, jadwal, biaya), lalu '*' sebelum Company.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AppSetting_List
    @CoCode  VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode = NULLIF(LTRIM(RTRIM(@CoCode)), '');

    SELECT  CoCode, SettingKey, SettingValue, ValueType, Description,
            CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM    dbo.AppSetting
    WHERE   (@CoCode IS NULL OR CoCode = @CoCode)
    ORDER BY
            CASE CHARINDEX(',' + SettingKey + ',',
                           ',EMERGENCY_FOLLOWUP_WORKDAYS,SCHEDULE_ONTRACK_MIN_DEV,SCHEDULE_SLIGHT_MIN_DEV,COST_ONTRACK_MAX_PCT,COST_ATRISK_MAX_PCT,')
                 WHEN 0 THEN 9999
                 ELSE CHARINDEX(',' + SettingKey + ',',
                           ',EMERGENCY_FOLLOWUP_WORKDAYS,SCHEDULE_ONTRACK_MIN_DEV,SCHEDULE_SLIGHT_MIN_DEV,COST_ONTRACK_MAX_PCT,COST_ATRISK_MAX_PCT,')
            END,
            SettingKey,
            CASE WHEN CoCode = '*' THEN 0 ELSE 1 END,
            CoCode;
END
GO

/* ---------------------------------------------------------------------
   3. usp_AppSetting_GetByKey  (baris persis, TANPA fallback; untuk halaman Edit)
      Nilai efektif dengan fallback '*' tetap lewat usp_AppSetting_Get (Config.sql).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AppSetting_GetByKey
    @CoCode      VARCHAR(10),
    @SettingKey  VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  CoCode, SettingKey, SettingValue, ValueType, Description,
            CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM    dbo.AppSetting
    WHERE   CoCode = @CoCode AND SettingKey = @SettingKey;
END
GO

/* ---------------------------------------------------------------------
   4. usp_AppSetting_UpdateValue
      Hanya SettingValue (+ audit). ValueType, Description, key tidak berubah.
      Nilai disimpan dalam bentuk normal (INT tanpa nol depan; DECIMAL tanpa nol belakang).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AppSetting_UpdateValue
    @CoCode        VARCHAR(10),
    @SettingKey    VARCHAR(50),
    @SettingValue  NVARCHAR(200),
    @ActionBy      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ValueType VARCHAR(10);
    DECLARE @Num       DECIMAL(18, 6);
    DECLARE @Text      NVARCHAR(200) = LTRIM(RTRIM(@SettingValue));

    SELECT @ValueType = ValueType
    FROM   dbo.AppSetting
    WHERE  CoCode = @CoCode AND SettingKey = @SettingKey;

    IF @ValueType IS NULL
        THROW 50053, N'Setting not found.', 1;

    IF ISNULL(@Text, N'') = N''
        THROW 50052, N'Value is required.', 1;

    /* -- Tipe nilai -- */
    IF @ValueType = 'INT'
    BEGIN
        IF TRY_CONVERT(INT, @Text) IS NULL
            THROW 50052, N'Value must be a whole number.', 1;
        SET @Num  = TRY_CONVERT(INT, @Text);
        SET @Text = CONVERT(NVARCHAR(200), TRY_CONVERT(INT, @Text));
    END
    ELSE IF @ValueType = 'DECIMAL'
    BEGIN
        SET @Num = TRY_CONVERT(DECIMAL(18, 6), @Text);
        IF @Num IS NULL
            THROW 50052, N'Value must be a number.', 1;
        IF @Num <> ROUND(@Num, 2)
            THROW 50052, N'Value can have at most 2 decimal places.', 1;

        -- '-5.50' -> '-5.5', '-5.00' -> '-5'
        SET @Text = CONVERT(NVARCHAR(200), CAST(@Num AS DECIMAL(18, 2)));
        SET @Text = REVERSE(SUBSTRING(REVERSE(@Text), PATINDEX(N'%[^0]%', REVERSE(@Text)), 200));
        IF RIGHT(@Text, 1) = N'.' SET @Text = LEFT(@Text, LEN(@Text) - 1);
        IF @Text = N'-0' SET @Text = N'0';
    END

    /* -- Rentang per key -- */
    IF @SettingKey = 'EMERGENCY_FOLLOWUP_WORKDAYS' AND @Num NOT BETWEEN 1 AND 30
        THROW 50052, N'Emergency follow-up limit must be between 1 and 30 working days.', 1;
    IF @SettingKey IN ('SCHEDULE_ONTRACK_MIN_DEV', 'SCHEDULE_SLIGHT_MIN_DEV') AND @Num NOT BETWEEN -100 AND 0
        THROW 50052, N'Schedule deviation must be between -100 and 0 % points.', 1;
    IF @SettingKey IN ('COST_ONTRACK_MAX_PCT', 'COST_ATRISK_MAX_PCT') AND @Num NOT BETWEEN 1 AND 1000
        THROW 50052, N'Cost ratio must be between 1 and 1000 %.', 1;

    /* -- Konsistensi pasangan ambang (nilai efektif pasangan pada Company yang sama) -- */
    DECLARE @PairKey VARCHAR(50) =
        CASE @SettingKey
            WHEN 'SCHEDULE_ONTRACK_MIN_DEV' THEN 'SCHEDULE_SLIGHT_MIN_DEV'
            WHEN 'SCHEDULE_SLIGHT_MIN_DEV'  THEN 'SCHEDULE_ONTRACK_MIN_DEV'
            WHEN 'COST_ONTRACK_MAX_PCT'     THEN 'COST_ATRISK_MAX_PCT'
            WHEN 'COST_ATRISK_MAX_PCT'      THEN 'COST_ONTRACK_MAX_PCT'
        END;

    IF @PairKey IS NOT NULL
    BEGIN
        DECLARE @Pair DECIMAL(18, 6) =
        (
            SELECT TOP (1) TRY_CONVERT(DECIMAL(18, 6), SettingValue)
            FROM   dbo.AppSetting
            WHERE  SettingKey = @PairKey AND CoCode IN (@CoCode, '*')
            ORDER BY CASE WHEN CoCode = @CoCode THEN 0 ELSE 1 END
        );

        IF @Pair IS NOT NULL
        BEGIN
            IF @SettingKey = 'SCHEDULE_ONTRACK_MIN_DEV' AND @Num <= @Pair
                THROW 50052, N'On Track minimum deviation must be greater than the Slightly Delay minimum.', 1;
            IF @SettingKey = 'SCHEDULE_SLIGHT_MIN_DEV'  AND @Num >= @Pair
                THROW 50052, N'Slightly Delay minimum deviation must be less than the On Track minimum.', 1;
            IF @SettingKey = 'COST_ONTRACK_MAX_PCT'     AND @Num >= @Pair
                THROW 50052, N'On Track maximum ratio must be less than the At Risk maximum.', 1;
            IF @SettingKey = 'COST_ATRISK_MAX_PCT'      AND @Num <= @Pair
                THROW 50052, N'At Risk maximum ratio must be greater than the On Track maximum.', 1;
        END
    END

    UPDATE dbo.AppSetting
    SET    SettingValue = @Text,
           UpdatedAt    = SYSDATETIME(),
           UpdatedBy    = @ActionBy
    WHERE  CoCode = @CoCode AND SettingKey = @SettingKey;

    IF @@ROWCOUNT = 0
        THROW 50053, N'Setting not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) List: 5 baris '*', urut EMERGENCY, SCHEDULE_ONTRACK, SCHEDULE_SLIGHT, COST_ONTRACK, COST_ATRISK;
   --    Description sudah bahasa Inggris
   EXEC dbo.usp_AppSetting_List;
   EXEC dbo.usp_AppSetting_List @CoCode = 'ABL';                                         -- 0 baris (belum ada override)
   EXEC dbo.usp_AppSetting_GetByKey '*', 'EMERGENCY_FOLLOWUP_WORKDAYS';                   -- 1 baris

   -- 2) Update valid + normalisasi
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N' 05 ', N'uji';
   EXEC dbo.usp_AppSetting_Get 'ABL', 'EMERGENCY_FOLLOWUP_WORKDAYS';                      -- 5 (fallback '*'), UpdatedBy uji
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV', N'-5.50', N'uji';
   EXEC dbo.usp_AppSetting_GetByKey '*', 'SCHEDULE_ONTRACK_MIN_DEV';                      -- -5.5

   -- 3) Validasi -> 50052
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'';          -- kosong
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'2.5';       -- bukan bilangan bulat
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'0';         -- di luar 1..30
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'abc';       -- bukan angka
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'-5.555';    -- > 2 desimal
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'5';         -- di luar -100..0
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'-20';       -- <= Slightly Delay (-15)
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'COST_ATRISK_MAX_PCT',         N'100';       -- <= On Track (100)

   -- 4) Tidak ditemukan -> 50053
   EXEC dbo.usp_AppSetting_UpdateValue 'ABL', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'3';       -- baris ABL belum ada
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'TIDAK_ADA', N'3';

   -- 5) Kembalikan nilai uji
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'EMERGENCY_FOLLOWUP_WORKDAYS', N'3',  N'uji';
   EXEC dbo.usp_AppSetting_UpdateValue '*', 'SCHEDULE_ONTRACK_MIN_DEV',    N'-5', N'uji';
   ===================================================================== */
