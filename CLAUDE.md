# CLAUDE.md

Panduan untuk Claude Code pada project ASP.NET Core 8 MVC ini. Baca seluruh file ini sebelum mengubah code.

## Prinsip Kerja

- **Fix the problem with the smallest safe change.** Jangan refactor besar untuk bug kecil.
- Jangan ubah framework, architecture, naming, namespace, atau struktur database tanpa alasan jelas dan persetujuan.
- Jangan mengarang class, method, property, atau konfigurasi yang belum ada. Cek dulu di source code.
- Jangan mengklaim "berhasil" sebelum `dotnet build` (dan test, jika ada) benar-benar dijalankan.
- Jika informasi belum cukup untuk menentukan root cause, katakan apa yang belum diketahui. Jangan menebak.
- Kerjakan per modul/fitur kecil. Selesaikan satu tahap sebelum lanjut ke tahap berikutnya.

## Technology Stack (tetap, jangan diganti)

- .NET 8 / ASP.NET Core 8 MVC, C#
- Dapper + SQL Server + Stored Procedure
- **Tidak memakai Entity Framework. Tidak memakai Blazor.**
- Bootstrap 5.3 (lokal di wwwroot/lib/bootstrap, bukan CDN) (UI), JavaScript / Fetch / AJAX
- Dependency Injection bawaan ASP.NET Core
- async/await untuk seluruh akses I/O dan database

## Architecture

Pola: **Controller → Service (Dapper) → Stored Procedure**

**Tidak ada layer Repository.** Service berisi business logic sekaligus akses data via Dapper.

```
/Controllers      -> hanya routing, validasi input, return View/Json. Tanpa business logic.
/Models           -> entity, ViewModel, DTO
/Services         -> business logic + akses data via Dapper (interface IxxxService + implementasi)
/Views            -> Razor views (MVC)
/wwwroot          -> static files (css, js, lib)
/Database         -> script SQL: tabel, stored procedure (versioned, idempotent)
```

Aturan:
- Controller tidak boleh mengakses database atau Dapper langsung. Selalu lewat Service.
- **Jangan membuat class/interface Repository baru.** Query Dapper ditulis di Service.
- Satu Service per domain/modul (mis. `OrderService`). Jika Service terlalu besar, pecah per sub-domain, bukan dengan menambah layer Repository.
- Semua query lewat **stored procedure** dengan parameter (`DynamicParameters`). Dilarang string concatenation untuk SQL (SQL injection).
- Koneksi dibuat per operasi lewat factory/`IDbConnection` yang di-inject ke Service. Gunakan `using`, jangan simpan koneksi sebagai field static.
- Connection string dibaca dari `appsettings.json` / `appsettings.{Environment}.json`. Jangan hardcode.
- Register DI di `Program.cs` (atau extension method yang sudah ada). Ikuti pola registrasi existing.

## Database (SQL Server, T-SQL)

- Gunakan syntax T-SQL yang valid untuk SQL Server.
- Perhatikan: NULL handling, identity (`SCOPE_IDENTITY()` / `OUTPUT`), datatype, date/time.
- Pagination: `OFFSET ... FETCH NEXT ...` dengan `ORDER BY` yang deterministik.
- Setiap stored procedure baru disimpan sebagai file `.sql` di `/Database`, bisa dijalankan ulang (`CREATE OR ALTER PROCEDURE`).
- Jangan ubah struktur tabel existing tanpa konfirmasi. Berikan script migrasi terpisah.
- Claude Code **tidak menjalankan script SQL ke database production**. Hanya dev/test.

## Date/Time

- Aplikasi internal/operasional memakai **local time** (`DateTime.Now`, `GETDATE()`), bukan UTC, kecuali ada instruksi eksplisit.

## UI: Bootstrap 5.3 + Mobile Responsive

Semua halaman wajib tampil baik di desktop, tablet, dan mobile (mobile-first).

### Dasar
- `_Layout.cshtml` wajib memuat: `<meta name="viewport" content="width=device-width, initial-scale=1">`
- Gunakan Bootstrap 5.3 yang sudah ada di project (`wwwroot/lib`). Jangan menambah CSS framework lain.
- Custom style taruh di `wwwroot/css/site.css`. Hindari inline style dan ukuran fixed dalam `px` untuk layout.

### Layout & Navigasi
- Konten dibungkus `container` / `container-fluid`, lalu `row` + `col-12 col-md-* col-lg-*`. Mulai dari ukuran mobile (`col-12`), baru tambahkan breakpoint yang lebih besar.
- Navigasi aplikasi memakai app shell header + sidebar (lihat "Layout dan Navigasi"); sidebar menjadi **offcanvas** (`offcanvas-lg`) di mobile.

### Tabel & Data List
- Tabel selalu dibungkus `<div class="table-responsive">`.
- Tabel memakai token compact (`.cims-compact`, setara `table-sm`); kolom aksi berupa tombol ikon dengan `title` dan `aria-label` (aksi berisiko tetap `data-confirm`).
- Untuk tabel dengan banyak kolom: pada layar kecil tampilkan sebagai **card list** (`d-md-none` untuk card, `d-none d-md-block` untuk tabel), atau sembunyikan kolom sekunder dengan `d-none d-md-table-cell`.
- Pagination memakai komponen `pagination` Bootstrap (`pagination-sm` di mobile bila perlu), server-side paging.

### Form
- Gunakan `form-control`, `form-select`, `form-label` (label kecil di atas input; tidak memakai `form-floating`); satu kolom di mobile (`col-12`), multi-kolom mulai `col-md-6`.
- Input memakai `type` yang tepat (`email`, `tel`, `number`, `date`) agar keyboard mobile sesuai.
- Target sentuh minimal ~44px di mobile: `btn` default / `btn-lg` untuk aksi utama berlaku **hanya di mobile (< 768px)**; di desktop `.cims-compact` menyeragamkan tinggi kontrol (jangan menambah `btn-sm`/`py-1` manual). Hindari tombol berdempetan.
- Tombol aksi utama di mobile: `d-grid` (full width), di desktop `d-md-flex justify-content-md-end`.
- Validasi: client-side (`jquery-validation-unobtrusive` bila sudah ada) + wajib validasi server-side (`ModelState`).

### Komponen
- Gunakan komponen Bootstrap: `card`, `modal` (untuk form/konten, bukan konfirmasi), `badge`, `spinner-border`. Notifikasi dan dialog hanya lewat `notify` (lihat "Notifikasi dan Dialog").
- Modal di mobile: `modal-dialog-scrollable` dan `modal-fullscreen-sm-down` untuk form panjang.
- Gambar: `img-fluid`. Hindari lebar fixed.
- Ikon: gunakan yang sudah ada di project (mis. Bootstrap Icons) bila tersedia.

### AJAX
- Gunakan `fetch` dengan `async/await`. Tampilkan `spinner-border` saat loading. Respons non-2xx dan kegagalan jaringan memakai `notify.fetchError(...)`/`notify.error(...)`; aksi berhasil memakai `notify.success(...)`.
- URL endpoint memakai helper Razor (`@Url.Action(...)`) atau base path dari layout, **jangan hardcode** `/api/...`, agar aman saat di-deploy ke IIS dengan virtual directory.

### Checklist UI sebelum dianggap selesai
- [ ] Tampil benar di lebar 360px (mobile), 768px (tablet), 1366px (desktop)
- [ ] Tidak ada horizontal scroll di mobile
- [ ] Tabel tidak memotong konten (responsive/card)
- [ ] Tombol dan input mudah disentuh; di mobile tinggi kontrol >= 44px
- [ ] Desktop: baris tabel rapat (token compact), filter list satu baris, form 2 kolom (3 untuk field pendek di >= lg), header tabel sticky bila panjang
- [ ] Menu bisa diakses via hamburger/offcanvas di mobile, menutup setelah dipilih, dan item aktif benar (`aria-current="page"`)
- [ ] Blok user di header (nama, departemen, Logout) berfungsi dan mudah disentuh di mobile
- [ ] Toast sukses tidak menutupi navbar/tombol utama; tombol SweetAlert2 mudah disentuh (uji ±360px)
- [ ] Tidak ada `confirm(` / `alert(` bawaan browser di Views dan js

## Layout dan Navigasi

App shell di `Views/Shared/_Layout.cshtml`: `<header>` sticky (logo CIMS, subjudul, tagline di >= lg, hamburger di < lg) · `<nav aria-label="Menu utama">` sidebar · `<main>` konten (`container-fluid`, latar abu-abu kebiruan). Warna dan ukuran lewat CSS variables `--cims-*` di `wwwroot/css/site.css`. Ikon: Bootstrap Icons lokal (`wwwroot/lib/bootstrap-icons`).

- **Responsive:** >= lg sidebar tetap di kiri (lebar `--cims-sidebar-width`, compact: item ±36px, font 0.875rem, boleh scroll vertikal sendiri), hanya konten yang scroll; < lg sidebar menjadi offcanvas (`offcanvas-lg`) dengan item lebih besar (≥ ±44px) untuk sentuh. Offcanvas menutup hanya saat item daun (link tujuan) dipilih.
- **Menu dua tingkat (maks. 2):** grup + submenu, accordion (`data-bs-parent`), grup berisi `<button>` collapse dengan `aria-expanded`/`aria-controls` dan chevron; item tanpa submenu adalah link biasa. Grup yang berisi item aktif terbuka otomatis dan ditandai aktif.
- **Data menu: SATU tempat**, daftar `MenuItem` (teks, ikon, controller, action, enabled, children) di `Views/Shared/_Sidebar.cshtml`; markup tidak perlu disentuh. Item `enabled = false` tampil nonaktif (`disabled`, `aria-disabled`, tooltip "Segera hadir"; badge "Segera" hanya untuk item tingkat atas tanpa submenu), bukan link ke `#`.
- Item aktif ditentukan dari controller/action pada `ViewContext.RouteData` (sub-halaman ikut aktif, mis. `/Customer/Edit/5`) dan diberi `aria-current="page"`.
- **Modul baru WAJIB menambahkan item atau submenu di `_Sidebar.cshtml`** (satu baris; ubah `enabled` menjadi `true` saat halamannya siap).
- Toast dan SweetAlert2 harus tampil di atas header (z-index); jangan menghapus toast container, `notify.js`, atau `_Notifications` dari layout.

## Kepadatan UI (Compact)

Desktop dan tablet (>= 768px) compact; mobile (< 768px) tetap default Bootstrap dengan target sentuh ~44px. Seluruhnya CSS-first di `wwwroot/css/site.css` (blok "Kepadatan UI") lewat class pembungkus `.cims-compact` pada `<main>` di `_Layout.cshtml`; header, sidebar, toast, dan SweetAlert2 tidak terpengaruh.

- **Token (`:root`):** `--cims-font-size` 0.875rem · `--cims-font-size-sm` 0.8125rem · `--cims-badge-font-size` 0.75rem · `--cims-space-1/2/3` 0.25/0.5/0.75rem · `--cims-control-height` 2rem · `--cims-table-cell-py/px` 0.25/0.5rem · `--cims-card-padding` 0.75rem · `--cims-table-offset` (untuk `max-height` tabel).
- **Class bantu:** `.cims-page-header` (judul + aksi utama sejajar), `.cims-filter` (filter bar satu baris), `.cims-list-footer` (info + pagination), `.cims-icon-btn` (tombol ikon di tabel), `.cims-detail-item` (pasangan label-nilai pada Details).
- **Lebar konten:** wrapper `.cims-content` di `_Layout.cshtml` (token `--cims-content-max-width` 1320px, `--cims-content-narrow-max-width` 960px; satu-satunya tempat ukuran `px` layout). Pilih mode lewat `ViewData["ContentWidth"]` di blok `@{ }` view: kosong = default 1320px (halaman list/tabel), `"narrow"` = 960px (form dan detail: Create, Edit, Details), `"full"` = tanpa batas (dashboard, Gantt, laporan lebar). **Dilarang menambah `max-width`/lebar `px` manual di view atau elemen anak.** Kolom tabel Status/Aksi memakai `.cims-col-fit`.
- **View baru wajib memakai class dan token ini, tanpa kelas ukuran manual per elemen** (`btn-sm`, `py-1`, `mb-1`, dsb.). Hindari `!important` dan inline style; fokus keyboard (focus ring) tidak boleh dihilangkan.

## Autentikasi

SSO berbasis middleware (pola project Training); tidak ada ASP.NET Authentication scheme dan tidak ada `[Authorize]`.

- **Alur:** user login di portal → portal mengarahkan ke CIMS dengan `?token={sessionId}` → `Middleware/SessionTokenMiddleware` menukar sessionId ke JWT (`{SSO:InternalApi}/home/api/token`), memvalidasi (HS256, `SSO:JwtKey`), lalu menyimpan `JWT`, `Username`, `SessionID` di Session dan me-redirect ke URL tanpa `?token=`. Tanpa sesi → redirect ke `SSO:PublicLogin` (request AJAX: 401 JSON `{ success:false, message:"Sesi berakhir" }`).
- **Urutan pipeline:** `UseStaticFiles` → `UseRouting` → `UseSession` → `SessionTokenMiddleware` → `UseAuthorization`. Cookie sesi `.CIMS.Session`.
- **Kunci JWT dilarang ada di repo/log/dokumen.** `SSO:JwtKey` kosong di `appsettings.json`; Development lewat User Secrets, Production lewat environment variable (`SSO__JwtKey`) atau file konfigurasi di server. Kosong di non-Development → aplikasi gagal start. Jangan mencatat sessionId, token, atau URL token ke log.
- **Dev bypass:** `Auth:DevUsername` di `appsettings.Development.json`; hanya berlaku di Development dan bila terisi (kosong = alur SSO normal).
- **Identitas user:** `ProfileAttribute` (filter global) memuat `CurrentUser` dari `usp_Auth_GetUserByUsername` (`home..users`). **Controller/Service wajib memakai `ICurrentUserService`, dilarang membaca `Session["Username"]` langsung.** User tidak terdaftar → `Home/NotAuthorized` (AJAX: 403 JSON).
- **Role (tampilan saja):** dropdown user menampilkan role tertinggi (`CurrentUser.HighestRole`: `Description`, jika kosong kode role; tooltip memuat semua role). `ProfileAttribute` memuat `Roles` sekali per request (kegagalan hanya dicatat, tidak memblokir).
- **Sumber role:** `home..users.Role` (dipisah `;`) dicocokkan dengan `dbo.HierarchyLevel` lewat `usp_Auth_GetUserRoles` (`Database/Role.sql`); level kecil = lebih tinggi. Isi tabel disesuaikan tanpa ubah kode.
- **Otorisasi berbasis role BELUM aktif** (tanpa filter, default-deny, atau menu per role); menunggu `Prompts/design-role.md`. Role tidak boleh dipakai untuk keputusan akses sebelum itu.
- **Logout:** POST + anti-forgery + `data-confirm` (tombol di dropdown user pada header); `Session.Clear()`, hapus cookie `.CIMS.Session` dan `.Portal.Session`, redirect ke `SSO:PublicLogin`.
- **Tahap B (rencana, belum dikerjakan):** RoleAuthorize (MVC), RoleAuthorizeApi (403 JSON), AllowAllRoles, menu sidebar per role; daftar role CIMS ditentukan oleh user, jangan menebak nama role. `CurrentUser.PortalRole` (`home..users.Role`) hanya dimuat dan **tidak boleh** dipakai untuk keputusan akses. Training mengambil role lewat `dbo.fc_GetRole(@username)` (definisinya tidak ada di source); user memeriksanya sebelum memutuskan apakah CIMS memakai role portal atau tabel role sendiri.

## Notifikasi dan Dialog

Berlaku untuk seluruh aplikasi. Library lokal (bukan CDN): SweetAlert2 di `wwwroot/lib/sweetalert2`, Bootstrap Toast; API di `wwwroot/js/notify.js`.

1. **Konfirmasi** (nonaktifkan/aktifkan, hapus, batal dengan perubahan belum tersimpan, aksi berisiko) memakai **SweetAlert2**. Dilarang `confirm()` / `alert()` bawaan browser dan modal Bootstrap untuk konfirmasi.
2. **Error** memakai **SweetAlert2** (icon error): `TempData["Error"]`, error AJAX/fetch (non-2xx dan jaringan), error umum server (`ModelState` kunci kosong). Pengecualian: error per field tetap inline (`asp-validation-for`), mis. kode duplikat di bawah field Code.
3. **Sukses** memakai **Bootstrap Toast** (`text-bg-success`, pojok kanan bawah, auto-hide 4 detik, ada tombol tutup): `TempData["Success"]` dan aksi AJAX berhasil.
4. Di luar tiga kasus di atas (info, warning), tanyakan dulu kepada user.

API global `notify`: `notify.success(message)` · `notify.error(message, title?)` · `notify.confirm({ title, text, confirmText, cancelText, danger })` → `Promise<boolean>` · `notify.fetchError(responseOrError)`.
Konfirmasi deklaratif: `form`/`button`/`a` dengan `data-confirm="pesan"` (opsional `data-confirm-title`, `data-confirm-ok`, `data-confirm-danger="true"`). Form tetap dikirim utuh (token anti-forgery ikut). Guard perubahan belum tersimpan: `form[data-dirty-guard]` + `a[data-confirm][data-confirm-if-dirty="#idForm"]`.
Notifikasi server dirender oleh `Views/Shared/_Notifications.cshtml` (nilai di-encode lewat atribut data; jangan menyisipkan teks mentah ke string JavaScript).

## Security

- Validasi semua input di server. Gunakan `[ValidateAntiForgeryToken]` untuk POST form MVC.
- Encode output (Razor default sudah encode; hindari `Html.Raw` pada data user).
- Autentikasi: lihat bagian "Autentikasi" (SSO via middleware). Jangan membuat mekanisme autentikasi lain tanpa konfirmasi.
- Jangan commit secret, password, atau connection string production.

## Coding Style

- Pertahankan namespace dan naming yang sudah ada.
- Interface Service diawali `I` (mis. `IOrderService`), method async berakhiran `Async`, parameter `CancellationToken` bila pola existing memakainya.
- Logging memakai `ILogger<T>`. Jangan menelan exception tanpa log.
- Perubahan kecil: tunjukkan hanya bagian yang berubah. Jika full file lebih aman, berikan full file.

## Build & Test

```
dotnet restore
dotnet build
dotnet test        # jika ada project test
dotnet run --project <NamaProject>
```

Sebelum menyatakan task selesai: `dotnet build` harus 0 error. Laporkan warning baru jika ada.

## Deployment (IIS / Windows Server)

Jika aplikasi jalan di localhost tetapi gagal setelah publish, periksa dulu: publish output, `appsettings` & environment, base URL / endpoint AJAX, IIS binding & HTTPS, static files, permission folder, identity app pool, firewall, connection string, dan log. Jangan langsung menyimpulkan masalah ada di source code.

## Cara Memberi Laporan

Format laporan hasil kerja:

```
Diagnosis:
Root Cause:
Perubahan: (file + bagian yang diubah)
Test: (command / langkah verifikasi)
Expected Result:
```

Jika user menjawab "PASS", anggap step selesai, pertahankan perubahannya, dan lanjut ke step berikutnya tanpa mengulang solusi sebelumnya.

## Modul Acuan: Customer

Modul baru WAJIB mengikuti pola Customer berikut.

- **File per layer:** SQL `Database/Customer.sql` · Model `Models/Customer.cs`, `Models/PagedResult.cs` · ViewModel `Models/CustomerViewModels.cs` · Service `Services/ICustomerService.cs`, `CustomerService.cs`, `CustomerExceptions.cs`, `IDbConnectionFactory.cs` · Controller `Controllers/CustomerController.cs` · Views `Views/Customer/` (Index, Details, Create, Edit, `_CustomerForm`).
- **Exception SP → Controller:** 50001 `CustomerDuplicateCodeException` → `ModelState.AddModelError(nameof(Code))` · 50002 `CustomerValidationException` → error umum form · 50003 `CustomerNotFoundException` → `NotFound()` (GET) atau `TempData["Error"]` + redirect ke Index (POST). Service menerjemahkan `SqlException.Number`; error lain dicatat dan dilempar ulang.
- **PagedResult<T>:** `Items`, `TotalCount`, `PageNumber`, `PageSize`, `TotalPages`. `TotalCount` dari parameter OUTPUT SP.
- **PRG + TempData:** POST valid → redirect; pesan lewat `TempData["Success"]` / `["Error"]`, ditampilkan lewat `_Notifications` (toast untuk sukses, SweetAlert2 untuk error). Semua POST memakai `[ValidateAntiForgeryToken]`; `returnUrl` hanya dipakai jika `Url.IsLocalUrl`.
- **Pola list:** search (kode/nama), filter status (`bool?`), sort dengan whitelist kolom (SP dan Controller), `SortDir` ASC/DESC, paging server-side dengan `PageSize` dibatasi di Controller; `Page` melebihi total → redirect ke halaman terakhir; semua filter ikut terbawa di link sort/paging. Soft delete lewat `SetActive` (tanpa Delete).
- **Sidebar:** Customer terdaftar di `_Sidebar.cshtml` (grup "Master Data" > Customer) sebagai contoh; modul baru menambah item/submenu di sana.
- **Pola view mobile-first:** tabel `d-none d-md-block` dalam `table-responsive` + card list `d-md-none`; kolom sekunder `d-none d-lg-table-cell`; form `form-label` di atas input, `col-12 col-md-6 col-lg-*`, `type` tel/email; kolom aksi tabel berupa tombol ikon; tombol aksi `d-grid d-md-flex justify-content-md-end`; `_ValidationScriptsPartial` di `@section Scripts`; URL via tag helper `asp-*`.
