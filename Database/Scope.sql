/* =====================================================================
   Scope.sql  -  Lingkup data departemen per user (T0-2; PRD BR-24, BR-28, BR-29, BR-56, BR-57)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Prasyarat: Role.sql dan Config.sql sudah dijalankan; STRING_SPLIT (compat level >= 130);
              hak baca ke database [home] (users, app_employees, APP_Departments).
   Catatan :
     - Lingkup ini HANYA untuk MELIHAT data. Hak approve ditentukan langkah workflow (T2);
       approver hanya untuk request dengan CoCode sama dengan CoCode karyawannya (BR-63).
     - Setiap SP list/detail transaksi wajib membatasi data lewat function ini.
   ===================================================================== */

/* ---------------------------------------------------------------------
   dbo.fn_User_AllowedDepartments(@Username)
   DepartmentID + CoCode (APP_Departments, Disabled = 0) yang boleh dilihat user,
   gabungan semua role CIMS user (any-of):
     administrator, civil, purchasing, director, gm -> semua departemen ABL dan NKM
     fat                                            -> semua departemen pada CoCode karyawan
     kabag, adm, plan, spv, emp                     -> ABRV dan CoCode sama dengan departemen karyawan
     mo                                             -> anggota grup aktif MILL pada CoCode karyawan
   Tanpa role CIMS / user tidak ada -> 0 baris.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_AllowedDepartments
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    WITH me AS
    (
        SELECT  e.CoCode, ad.ABRV
        FROM    home..users u
                JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
                LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
        WHERE   u.Username = @Username
    ),
    r AS
    (
        SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
        FROM   home..users u
               CROSS APPLY STRING_SPLIT(u.[Role], N';') s
        WHERE  u.Username = @Username
          AND  LTRIM(RTRIM(s.value)) <> N''
    )
    SELECT  d.DepartmentID, d.CoCode
    FROM    home..APP_Departments d
            CROSS JOIN me
    WHERE   ISNULL(d.Disabled, 0) = 0
      AND   (
                -- semua departemen ABL dan NKM
                (EXISTS (SELECT 1 FROM r WHERE r.RoleCode IN (N'administrator', N'civil', N'purchasing', N'director', N'gm'))
                 AND d.CoCode IN (N'ABL', N'NKM'))
                -- fat: Company karyawan
             OR (EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'fat')
                 AND d.CoCode = me.CoCode)
                -- kabag / adm / plan / spv / emp: ABRV + Company yang sama
             OR (EXISTS (SELECT 1 FROM r WHERE r.RoleCode IN (N'kabag', N'adm', N'plan', N'spv', N'emp'))
                 AND d.ABRV = me.ABRV AND d.CoCode = me.CoCode)
                -- mo: anggota grup MILL pada Company karyawan
             OR (EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'mo')
                 AND d.CoCode = me.CoCode
                 AND EXISTS (SELECT 1
                             FROM   dbo.DepartmentGroup g
                                    JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                             WHERE  g.CoCode = me.CoCode AND g.GroupCode = N'MILL' AND g.IsActive = 1
                               AND  m.DepartmentID = d.DepartmentID))
            )
);
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok; ganti <...> dengan username nyata)

   -- Cari contoh user per role (role portal ada di home..users.[Role]):
   SELECT u.Username, u.[Role], e.CoCode, ad.ABRV, ad.DepartmentID
   FROM   home..users u
          JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
          LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
   ORDER BY u.[Role];

   -- 1) Satu user per role: lihat jumlah dan isi
   SELECT COUNT(*) AS Jumlah FROM dbo.fn_User_AllowedDepartments(N'<user-administrator/civil/gm/director/purchasing>');   -- semua ABL + NKM (Disabled = 0)
   SELECT COUNT(*) AS Jumlah FROM dbo.fn_User_AllowedDepartments(N'<user-fat>');    -- hanya CoCode karyawan
   SELECT * FROM dbo.fn_User_AllowedDepartments(N'<user-kabag-atau-adm>');          -- ABRV + CoCode yang sama

   -- 2) User QC (C500): harus mengembalikan C500 dan D500 (DepartmentID keduanya)
   SELECT f.DepartmentID, f.CoCode, ad.DeptName, ad.ABRV
   FROM   dbo.fn_User_AllowedDepartments(N'<user-kabag-QC>') f
          JOIN home..APP_Departments ad ON ad.DepartmentID = f.DepartmentID;

   -- 3) User mo: tepat 6 departemen MILL (17, 18, 19, 20, 600, 601)
   SELECT * FROM dbo.fn_User_AllowedDepartments(N'<user-mo>') ORDER BY DepartmentID;

   -- 4) User dengan 'kabag;civil' (gabungan): sama dengan lingkup civil (semua)
   SELECT COUNT(*) FROM dbo.fn_User_AllowedDepartments(N'<user-kabag-civil>');

   -- 5) User emp / spv / plan: sama dengan adm (ABRV + Company; QC -> C500 dan D500)
   SELECT * FROM dbo.fn_User_AllowedDepartments(N'<user-emp>');
   -- User tanpa role CIMS (mis. hanya komisaris/creator) atau tidak ada: 0 baris
   SELECT * FROM dbo.fn_User_AllowedDepartments(N'tidak-ada-xyz');

   -- 6) Jika error "Invalid column name 'Disabled'" / konversi tipe: laporkan tipe kolom
   --    home..APP_Departments.Disabled (diasumsikan bit/int, NULL dianggap aktif).
   ===================================================================== */
