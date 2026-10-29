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
- Desktop (>= lg): tetap di kiri, lebar sekitar 220px (compact), konten di sebelah kanan
  scroll sendiri. Sidebar tidak ikut tergulung, tetapi boleh scroll vertikal sendiri
  (overflow-y: auto) jika menu melebihi tinggi layar.
- Mobile/tablet (< lg): sidebar menjadi offcanvas Bootstrap 5.3 (offcanvas-lg),
  menutup otomatis setelah pengguna memilih menu.
- Struktur menu **dua tingkat** (grup + submenu), kedalaman maksimal 2. Ikon tingkat
  atas mengacu pada gambar. Usulan awal (mengikuti kategori CAPEX/OPEX/LVE pada gambar,
  daftar ini hanya data sehingga mudah diubah belakangan):
  - Home
  - Dashboard
  - Request: Daftar Request, Buat Request
  - Project / Maintenance: CAPEX, OPEX, LVE
  - Cost Management: CAPEX, OPEX, LVE
  - Gantt Chart: CAPEX, OPEX, LVE
  - User Satisfaction
  - Report
  - Master Data: Customer
- Perilaku submenu:
  - Item tingkat atas yang punya submenu adalah <button> toggle (bukan link), memakai
    Bootstrap collapse, dengan ikon chevron di kanan yang berputar saat terbuka,
    plus aria-expanded dan aria-controls.
  - Mode accordion: hanya satu grup terbuka dalam satu waktu (data-bs-parent).
  - Saat halaman dimuat, grup yang berisi item aktif otomatis terbuka dan grup
    induknya ditandai aktif.
  - Submenu menjorok ke dalam, font lebih kecil, tanpa ikon (atau penanda titik kecil).
  - Item tanpa submenu adalah link biasa.
  - Pada offcanvas (< lg): mengetuk grup hanya membuka/menutup submenu (offcanvas tetap
    terbuka). Offcanvas menutup hanya saat item daun (link tujuan) dipilih.
- Item yang halamannya belum ada tampil **nonaktif**, BUKAN link mati ke "#":
  class disabled, aria-disabled, gaya muted, tooltip "Segera hadir". Badge "Segera"
  hanya untuk item tingkat atas tanpa submenu. Grup yang semua anaknya nonaktif tetap
  bisa dibuka agar struktur menu terlihat.
- Saat ini halaman yang benar-benar ada hanya Home (Home/Index) dan Customer
  (Customer/Index). Sisanya nonaktif.
- Status aktif ditentukan dari controller/action saat ini (ViewContext.RouteData),
  termasuk sub-halaman (mis. /Customer/Edit/5 tetap menandai Customer aktif).
  Beri aria-current="page" pada item aktif.
- **Tampilan compact** (desktop):
  - Font item 0.875rem, font submenu sekitar 0.8125rem.
  - Tinggi item sekitar 36px (padding vertikal rapat), ikon 1rem, jarak antar item minimal.
  - Sudut membulat kecil, item aktif berlatar biru terang seperti pada gambar.
  - Kartu "Civil Department" di bawah diperkecil dan disembunyikan pada layar yang
    pendek (media query max-height).
  - Pada layar < lg (offcanvas, perangkat sentuh), tinggi item dinaikkan ke minimal
    sekitar 40-44px agar mudah disentuh. Compact hanya untuk desktop.
- Bagian bawah sidebar: kartu kecil "Civil Department" dengan teks
  "Build Better, Support Production" (seperti pada gambar).
- Menu didefinisikan di SATU tempat sebagai data bersarang (item: teks, ikon,
  controller, action, enabled, children), dirender oleh partial
  Views/Shared/_Sidebar.cshtml. Pilih lokasi definisi yang paling sederhana
  (di dalam partial atau satu class kecil), tetapi tetap satu tempat.
  Menambah modul baru cukup menambah satu baris (atau satu submenu) di data itu,
  tanpa menyentuh markup.

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
  perilaku responsive (sidebar desktop, offcanvas mobile), struktur menu dua tingkat
  (grup + submenu, accordion), gaya compact, lokasi data menu, dan aturan
  "modul baru wajib menambahkan item atau submenu di sidebar".
- Perbarui Checklist UI: menu bisa diakses via hamburger di mobile, item aktif benar.
- Tambahkan di bagian "Modul Acuan: Customer" bahwa Customer terdaftar di sidebar
  sebagai contoh.

## Test

- Desktop >= 992px: header sticky, sidebar tetap di kiri, hanya konten yang scroll.
- Lebar 360px: sidebar tersembunyi, hamburger membuka offcanvas, menu menutup setelah
  dipilih, tidak ada horizontal scroll.
- /Customer, /Customer/Create, /Customer/Edit/{id}: grup Master Data terbuka otomatis,
  item Customer tampil aktif, grup induknya ditandai aktif.
- Mengetuk grup membuka/menutup submenu, grup lain menutup (accordion), chevron berputar.
- Di lebar 360px: mengetuk grup tidak menutup offcanvas, memilih item Customer menutupnya.
- Item nonaktif tidak bisa diklik atau difokuskan sebagai link biasa.
- Tampilan compact: seluruh menu muat dalam satu layar laptop (tinggi sekitar 768px)
  tanpa scroll saat semua grup tertutup.
- Fungsi Customer (list, create, edit, SetActive), toast, dan SweetAlert2 tetap normal.
- dotnet build: 0 error, 0 warning.

## Cara kerja

Tampilkan rencana lengkap (file baru dan file yang diubah, struktur daftar menu,
sumber Bootstrap Icons) dan tunggu persetujuan saya sebelum menulis code.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result,
lalu berhenti dan tunggu PASS.
