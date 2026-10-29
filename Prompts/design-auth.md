# Tugas: Autentikasi SSO berbasis middleware (mengikuti pola project Training)

Baca CLAUDE.md terlebih dahulu dan ikuti semua aturannya.
Keputusan ini menggantikan aturan lama "jangan membuat mekanisme autentikasi baru":
saya sudah menyetujui mekanisme di bawah ini.

Project referensi (HANYA BACA, jangan diubah): [ISI PATH PROJECT TRAINING, contoh D:\#PROJECT\...\Training]
File acuan di sana:
- Program.cs (urutan middleware dan konfigurasi Session)
- Middleware/SessionTokenMiddleware.cs
- Filters/ProfileAttribute.cs
- Services/CurrentUserService.cs dan Services/IServices/ICurrentUserService.cs
- ViewComponents/ProfileViewComponent.cs dan Views/Shared/Components/Profile/Default.cshtml
- Controllers/HomeController.cs (LogOut, NotAuthorized)

## Ruang lingkup

- **Tahap A (sekarang): autentikasi saja.** Login wajib lewat portal SSO, identitas user,
  blok user di header, logout, halaman NotAuthorized.
- **Tahap B (NANTI, jangan dikerjakan sekarang): role.** Filter RoleAuthorize, RoleAuthorizeApi,
  AllowAllRoles, dan menu per role. Menunggu daftar role CIMS dari saya.
- Jangan mengubah Service, SQL, atau View modul Customer. Customer cukup otomatis
  terlindungi oleh middleware.

## Cara kerja pola di Training (hasil analisis, ikuti alurnya)

1. User login di portal (aplikasi terpisah). Portal mengarahkan ke aplikasi dengan query `?token={sessionId}`.
2. `SessionTokenMiddleware` (dipasang setelah UseSession dan sebelum UseAuthorization):
   - ada `?token=` -> GET `{SSO:InternalApi}/home/api/token?sessionId=...` -> respons berisi JWT
     -> validasi tanda tangan (HS256, kunci simetris) -> ambil claim `ClaimTypes.Name`
     -> simpan ke Session: `JWT`, `Username`, `SessionID`.
   - token gagal atau tidak valid -> redirect ke `SSO:PublicLogin`.
   - tanpa `?token=` dan Session tidak punya `JWT` -> redirect ke `SSO:PublicLogin`.
   - Parameter validasi token (ValidateIssuer=false, ValidateAudience=false, ClockSkew=0)
     ikuti Training persis, karena token diterbitkan portal. Jangan diubah.
3. Identitas user dimuat dari `Session["Username"]` ke scoped `ICurrentUserService` oleh `ProfileAttribute`.
4. Data user dari database `home`: `home..users` JOIN `home..app_employees` LEFT JOIN `home..APP_Departments`.
5. Logout: Session.Clear() dan hapus cookie sesi.
Tidak ada ASP.NET Authentication scheme dan tidak ada [Authorize]. Pola itu tetap dipakai di CIMS.

## Perbedaan dari Training (WAJIB, ini perbaikan, bukan kreativitas)

1. **Kunci JWT tidak boleh ada di source code.** Training menulis kunci langsung di class middleware.
   Di CIMS: baca dari konfigurasi `SSO:JwtKey`.
   - appsettings.json: `"JwtKey": ""` (kosong, tanpa nilai asli).
   - Development: User Secrets. Production: environment variable atau file konfigurasi
     di server di luar repo.
   - Jika kunci kosong saat startup (non-Development): aplikasi gagal start dengan pesan jelas.
   - Jangan menulis nilai kunci asli di file mana pun (repo, CLAUDE.md, Prompts, log).
2. **Dev bypass lewat konfigurasi, bukan hardcode.** Training memaksa username "iswin" di Development.
   Di CIMS: `Auth:DevUsername` di appsettings.Development.json. Hanya berlaku jika
   Environment = Development DAN nilainya terisi. Jika kosong, alur normal (SSO) berjalan.
3. **Jangan log sessionId, token, atau URL token** (Training mencatatnya).
   Log cukup: path, hasil (diterima atau ditolak), username setelah valid. Level Information atau Warning.
4. **Bersihkan token dari URL.** Setelah token valid dan sesi dibuat, redirect (302) ke URL yang
   sama tanpa query `token` (query lain dipertahankan), agar token tidak tertinggal di address bar,
   history, dan log IIS.
5. **Request AJAX/API tanpa sesi -> 401 JSON, bukan redirect.** Deteksi: header
   `X-Requested-With: XMLHttpRequest` atau `Accept` memuat `application/json`.
   Body: `{ "success": false, "message": "Sesi berakhir" }`.
   Di `notify.fetchError` (wwwroot/js/notify.js): status 401 -> SweetAlert2 "Sesi berakhir" lalu arahkan
   ke halaman login. Status 403 -> SweetAlert2 "Anda tidak berwenang".
6. **IHttpClientFactory**, bukan `new HttpClient()` per request. Timeout 10 detik. Gagal terhubung
   ke portal -> log Error, redirect ke login (halaman non-AJAX) atau 401 (AJAX).
7. **Cookie sesi unik:** `Cookie.Name = ".CIMS.Session"` agar tidak bertabrakan dengan aplikasi lain
   pada host yang sama (portal dan Training berbagi host). HttpOnly, IsEssential, SameSite=Lax,
   SecurePolicy=SameAsRequest, IdleTimeout 480 menit (sesuaikan jika saya minta).
8. **ProfileAttribute dipasang global**, bukan per controller: daftarkan lewat
   `AddControllersWithViews(o => o.Filters.AddService<ProfileAttribute>())`. Dengan begitu controller
   baru tidak bisa lupa memasangnya. Filter ini memuat `CurrentUser` sekali per request. ViewComponent
   profil membaca dari `ICurrentUserService`, tidak query database lagi.
9. **Controller dan Service baru dilarang membaca `Session["Username"]` langsung.**
   Pakai `ICurrentUserService`.
10. **Logout memakai POST + anti-forgery** (Training memakai GET). Tombol Logout di dropdown user
    berupa form POST dengan `data-confirm` (SweetAlert2, "Keluar dari CIMS?") sesuai standar
    notifikasi di CLAUDE.md.

## Yang dibangun (Tahap A)

### A.1 Database/Auth.sql (kerjakan DULU, lalu berhenti dan tunggu PASS)
- `dbo.usp_Auth_GetUserByUsername(@Username NVARCHAR(100))` (CREATE OR ALTER, idempotent).
- Isi query sama dengan Training: `home..users` JOIN `home..app_employees` ON EmployeeCode,
  LEFT JOIN `home..APP_Departments` ON DepartmentID, WHERE `u.Username = @Username`.
- Kolom yang dikembalikan hanya yang dibutuhkan: Username, EmployeeCode, FullName, JobTitle,
  CoCode, DepartmentName, ABRV. Jangan menyalin seluruh model Employees dari Training.
- Stored procedure, bukan SQL inline (aturan CLAUDE.md).
- Prasyarat: login database CIMS punya hak baca ke database `home` (cross-database).
  Jika Anda tidak bisa memastikannya dari kode, tulis di laporan sebagai pertanyaan untuk saya.
  Jangan mengubah hak akses dan jangan menjalankan script SQL.
- Training tidak memeriksa `ResignDate`. Jangan ubah perilaku itu. Catat sebagai pertanyaan terbuka.

### A.2 Kode (setelah A.1 PASS)
- `Models/CurrentUser.cs`: properti sesuai kolom di atas.
- `Services/ICurrentUserService` + `CurrentUserService` (Scoped): `CurrentUser? CurrentUser { get; set; }`.
- `Services/IAuthService` + `AuthService` (Dapper, stored procedure): `GetUserByUsernameAsync`.
  Registrasi DI mengikuti pola yang sudah ada.
- `Middleware/SessionTokenMiddleware.cs` sesuai pola dan perbedaan di atas.
- `Filters/ProfileAttribute.cs` (global): memuat CurrentUser dari `Session["Username"]`.
  Jika user belum ada di `home..users` -> redirect ke `Home/NotAuthorized`.
  Kecualikan Home/NotAuthorized, Home/Error, dan Home/LogOut agar tidak terjadi loop redirect.
- `Program.cs`: urutan `UseStaticFiles` -> `UseRouting` -> `UseSession` ->
  `UseMiddleware<SessionTokenMiddleware>` -> `UseAuthorization`. Static files tidak melewati middleware.
- `Controllers/HomeController`: `NotAuthorized` dan `LogOut` (POST, `ValidateAntiForgeryToken`):
  Session.Clear(), hapus cookie `.CIMS.Session` dan `.Portal.Session` (mengikuti Training agar
  logout benar-benar keluar dari portal), lalu redirect ke `SSO:PublicLogin`.
- `Views/Home/NotAuthorized.cshtml`: Bootstrap 5.3, tanpa inline style, tombol Kembali dan Logout.
- Header app shell (design-sidebar): blok user di kanan (nama, departemen, dropdown berisi Logout).
  Tampilkan link "Kembali ke Portal" bila `SSO:PortalHomeUrl` terisi. Mobile: dropdown tetap bisa
  disentuh (target minimal 44px). Jika app shell belum ada, tempatkan di navbar `_Layout.cshtml`
  yang sekarang dan laporkan.
- `appsettings.json`: bagian `SSO` berisi `InternalApi`, `PublicLogin`, `PortalHomeUrl`, `JwtKey` (kosong).
  Nilai awal `InternalApi` dan `PublicLogin`: samakan dengan appsettings.json project Training
  (baca dari sana, anggap sama kecuali saya bilang lain).
  `appsettings.Development.json`: `Auth:DevUsername` = [ISI USERNAME DEV SAYA].

### A.3 CLAUDE.md
- Ganti kalimat Security "Autentikasi/otorisasi mengikuti mekanisme existing..." dengan bagian baru
  "Autentikasi": alur SSO + SessionTokenMiddleware, kunci dari konfigurasi (dilarang di repo),
  Dev bypass lewat `Auth:DevUsername`, aturan "pakai ICurrentUserService, jangan baca Session langsung",
  cookie `.CIMS.Session`, logout POST. Tulis ringkas (maks 20 baris).
- Tambahkan di Checklist UI: user block di header berfungsi di mobile.

## Test

- Dev dengan `Auth:DevUsername` terisi: /Customer terbuka tanpa token, header menampilkan nama dan
  departemen dari database.
- Dev dengan `Auth:DevUsername` kosong: redirect ke `SSO:PublicLogin`.
- Simulasi non-Dev (ASPNETCORE_ENVIRONMENT=Production di lokal):
  - tanpa token dan tanpa sesi: redirect ke login.
  - token tidak valid: redirect ke login.
  - token valid dari portal: sesi dibuat, lalu redirect ke URL bersih tanpa `?token=`.
    (Butuh portal mendaftarkan CIMS. Jika belum, tandai sebagai "belum teruji" di laporan.)
- AJAX tanpa sesi: respons 401 JSON, dan `notify.fetchError` menampilkan SweetAlert2.
- Username valid di portal tapi tidak ada di `home..users`: halaman NotAuthorized, tidak ada loop redirect.
- Logout: ada konfirmasi SweetAlert2, request POST dengan anti-forgery, sesi bersih, redirect ke login.
  Mengakses /Customer sesudahnya diarahkan ke login.
- Pencarian teks di seluruh repo: nilai kunci JWT dan string "iswin" tidak ada. Tidak ada log yang
  mencetak sessionId atau token.
- dotnet build: 0 error, 0 warning.

## Tahap B (jangan dikerjakan sekarang, hanya catat sebagai rencana di CLAUDE.md satu baris)

Filter RoleAuthorize (MVC), RoleAuthorizeApi (403 JSON), AllowAllRoles, dan menu sidebar per role.
Sumber role dan daftar role CIMS: saya tentukan nanti. Jangan menebak nama role.

## Cara kerja

1. Tampilkan rencana lengkap (file baru dan file yang diubah) dan tunggu persetujuan saya.
2. Kerjakan A.1 saja (Database/Auth.sql). Berhenti. Saya jalankan SQL di database dev dan jawab PASS.
3. Setelah PASS: A.2 dan A.3, lalu dotnet build.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result, lalu berhenti dan tunggu PASS.
