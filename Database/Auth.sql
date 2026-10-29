/* =====================================================================
   Auth.sql  -  Autentikasi SSO: data user dari database portal "home"
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Prasyarat: login database CIMS harus punya hak BACA (SELECT) ke database
              [home]: tabel users, app_employees, APP_Departments (cross-database).
              Script ini TIDAK mengubah hak akses.
   Catatan : Query mengikuti project Training. ResignDate sengaja TIDAK
             diperiksa (perilaku Training dipertahankan) - pertanyaan terbuka.
   ===================================================================== */

/* ---------------------------------------------------------------------
   usp_Auth_GetUserByUsername
   Mengembalikan 0 atau 1 baris. 0 baris = user ada di portal tetapi belum
   terdaftar di home..users (aplikasi menampilkan halaman NotAuthorized).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetUserByUsername
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  u.Username,
            e.EmployeeCode,
            e.FullName,
            e.JobTitle,
            e.CoCode,
            ad.DeptName,
            ad.ABRV
    FROM    home..users u
            JOIN home..app_employees e ON u.EmployeeCode = e.EmployeeCode
            LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
    WHERE   u.Username = @Username;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti username dengan yang ada di home..users)

   -- 1) User valid -> 1 baris
   EXEC dbo.usp_Auth_GetUserByUsername @Username = N'<username-valid>';

   -- 2) User tidak ada -> 0 baris
   EXEC dbo.usp_Auth_GetUserByUsername @Username = N'tidak-ada-xyz';

   -- 3) Jika error "The server principal ... is not able to access the database 'home'
   --    under the current security context" / permission denied:
   --    login CIMS belum punya hak baca ke database home -> minta DBA
   --    (script ini tidak mengubah hak akses).
   ===================================================================== */
