# Tugas: Layout utama dengan Sidebar Navigation (app shell CIMS)

Baca CLAUDE.md terlebih dahulu dan ikuti semua aturannya.
Gambar referensi: Prompts\ui-referensi-dashboard.png (baca file gambar ini dan
jadikan acuan visual untuk warna, proporsi, dan gaya).

## Ruang lingkup (penting)

Tugas ini HANYA membangun **app shell**: header + sidebar + area konten.
Isi dashboard (kartu CAPEX / OPEX / LVE, tabel, donut, grafik, Gantt) TIDAK dikerjakan
sekarang, karena modul datanya (Project, Cost, Gantt) belum ada. Itu fase berikutnya.
Jangan membuat data palsu atau angka dummy.

## Struktur yang harus dibangun (mengacu pada gambar)

### 1. Header (sticky, di atas)
- Kiri: logo teks "CIMS" + subjudul "Civil Integrated Management System".
- Tengah (hanya layar >= lg): tagline "Better Planning | Higher Efficiency | Sustainable Facility".
- Layar < lg: tombol hamburger yang membuka sidebar (offcanvas).
- "Last Updated" dan filter "Month" pada gambar BUKAN bagian shell. Jangan dibuat sekarang
  (itu milik halaman dashboard di fase berikutnya).

### 2. Sidebar (kiri)
- Desktop (>= lg): tetap di kiri, lebar sekitar 240px, konten di sebelah kanan scroll
  sendiri. Sidebar tidak ikut tergulung.
- Mobile/tablet (< lg): sidebar menjadi offcanvas Bootstrap 5.3 (offcanvas-lg),
  menutup otomatis setelah pengguna memilih menu.
- Item menu (urutan dan ikon mengacu pada gambar):
  Home, Dashboard, Request, Project / Maintenance, Cost Management, Gantt Chart,
  User Satisfaction, Report.
- Tambahkan item "Customer" (modul yang sudah ada) pada grup tersendiri, misalnya
  "Master Data".
- Item yang halamannya belum ada (Dashboard, Request, Project / Maintenance,
  Cost Management, Gantt Chart, User Satisfaction, Report) tampil **nonaktif**
  (class disabled, aria-disabled, tooltip atau badge "Segera"), BUKAN link mati ke "#".
- Home mengarah ke Home/Index. Customer mengarah ke Customer/Index.
- Status aktif ditentukan dari controller/action saat ini (ViewContext.RouteData),
  termasuk sub-halaman (mis. /Customer/Edit/5 tetap menandai Customer aktif).
  Beri aria-current="page" pada item aktif.
- Bagian bawah sidebar: kartu kecil "Civil Department" dengan teks
  "Build Better, Support Production" (seperti pada gambar).
- Menu didefinisikan di SATU tempat (partial Views/Shared/_Sidebar.cshtml, berupa daftar
  item: teks, ikon, controller, action, enabled). Menambah modul baru cukup menambah
  satu baris di daftar itu.

### 3. Area konten
- Container fluid dengan padding yang nyaman, latar abu-abu kebiruan lembut
  (bukan putih polos) agar kartu atau tabel terlihat terangkat.
- Home/Index: ganti isi default template menjadi halaman landing ringkas
  berjudul "Civil Dashboard" dengan satu kartu informasi bahwa widget CAPEX/OPEX/LVE
  menyusul. Jangan membuat widget.

## Aturan teknis

- Bootstrap 5.3 lokal (sudah ada). Tidak menambah CSS framework lain.
- Ikon: tambahkan **Bootstrap Icons lokal** di wwwroot/lib/bootstrap-icons
  (paket resmi, bukan CDN). Tampilkan rencana sumber unduhan dulu dan tunggu persetujuan.
- Warna dan ukuran didefinisikan sebagai CSS variables di wwwroot/css/site.css
  (mis. --cims-header-bg, --cims-sidebar-bg, --cims-sidebar-active, --cims-content-bg).
  Ambil nilai warna dari gambar referensi. Perkiraan awal: header biru navy gelap,
  sidebar biru, item aktif biru terang.
- Hindari inline style dan ukuran layout fixed dalam px selain lebar sidebar.
- **Pertahankan semua yang sudah ada di _Layout.cshtml**: container toast, referensi
  sweetalert2 dan notify.js, partial _Notifications, section scripts, validation scripts.
  Pastikan toast dan SweetAlert2 tampil di atas header (z-index) dan toast tidak
  tertutup header.
- Jangan mengubah Controller, Service, atau SQL. Untuk Home, perubahan hanya pada View
  (dan Controller hanya jika benar-benar perlu, jelaskan alasannya).
- Semantik: <header>, <nav aria-label="Menu utama">, <main>.

## Update CLAUDE.md

- Tambahkan bagian "Layout dan Navigasi": struktur shell (header, sidebar, konten),
  perilaku responsive (sidebar desktop, offcanvas mobile), lokasi daftar menu
  (_Sidebar.cshtml), dan aturan "modul baru wajib menambahkan item menu di sidebar".
- Perbarui Checklist UI: menu bisa diakses via hamburger di mobile, item aktif benar.
- Tambahkan di bagian "Modul Acuan: Customer" bahwa Customer terdaftar di sidebar
  sebagai contoh.

## Test

- Desktop >= 992px: header sticky, sidebar tetap di kiri, hanya konten yang scroll.
- Lebar 360px: sidebar tersembunyi, hamburger membuka offcanvas, menu menutup setelah
  dipilih, tidak ada horizontal scroll.
- /Customer, /Customer/Create, /Customer/Edit/{id}: item Customer tampil aktif.
- Item nonaktif tidak bisa diklik atau difokuskan sebagai link biasa.
- Fungsi Customer (list, create, edit, SetActive), toast, dan SweetAlert2 tetap normal.
- dotnet build: 0 error, 0 warning.

## Cara kerja

Tampilkan rencana lengkap (file baru dan file yang diubah, struktur daftar menu,
sumber Bootstrap Icons) dan tunggu persetujuan saya sebelum menulis code.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result,
lalu berhenti dan tunggu PASS.
