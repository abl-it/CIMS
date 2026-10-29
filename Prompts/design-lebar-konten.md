# Tugas: Batasi lebar konten (tidak full page) pada area konten app shell

Baca CLAUDE.md terlebih dahulu dan ikuti semua aturannya.
Ini perubahan tampilan kecil lanjutan dari design-compact. Jangan mengubah Controller, Service, SQL,
atau JavaScript. Jangan mengubah header dan sidebar (keduanya tetap selebar layar / tetap seperti sekarang).

## Masalah

Di layar lebar (mis. 1920px) isi halaman (judul, filter bar, tabel, pagination) merentang penuh sampai
sekitar 1700px. Kolom tabel saling berjauhan dan kolom Aksi terlempar ke ujung kanan, sehingga sulit dipindai.

## Perilaku yang diinginkan

Area konten diberi lebar maksimum dan diletakkan di tengah area konten (di sebelah kanan sidebar).
Judul halaman, tombol aksi, filter, tabel, dan pagination berada dalam satu kolom yang sama lebarnya.

| Mode lebar | Lebar maksimum | Dipakai untuk |
|---|---|---|
| default | 1320px | halaman list/tabel (Index) |
| narrow | 960px | Create, Edit, Details (form dan detail) |
| full | 100% | halaman yang memang butuh lebar: dashboard, Gantt, laporan lebar (belum ada sekarang) |

## Implementasi (perubahan terkecil yang aman)

1. wwwroot/css/site.css: tambahkan CSS variables `--cims-content-max-width: 1320px` dan
   `--cims-content-narrow-max-width: 960px`, lalu class:
   - `.cims-content { width: 100%; max-width: var(--cims-content-max-width); margin-inline: auto; }`
   - `.cims-content--narrow { max-width: var(--cims-content-narrow-max-width); }`
   - `.cims-content--full { max-width: none; }`
   Padding horizontal konten tetap seperti sekarang. Di bawah lebar maksimum, tampilan tidak berubah.
2. _Layout.cshtml: bungkus `@RenderBody()` dalam
   `<div class="cims-content @contentWidthClass">`. Nilai kelas dari `ViewData["ContentWidth"]`
   ("narrow" atau "full"; kosong = default). Pertahankan seluruh isi `<main>`, container toast,
   partial notifikasi, dan section scripts seperti sekarang.
3. Views Customer: Create, Edit, Details diberi `ViewData["ContentWidth"] = "narrow";` di blok `@{ }` atas.
   Index tidak diubah (default). Jangan menambah wrapper atau class lain di dalam view.
4. Tabel list: kolom Aksi dan Status dibuat selebar isinya
   (`width: 1%; white-space: nowrap`, lewat class CSS, bukan inline style), supaya kolom Kode, Nama,
   Telepon, dan Email mendapat sisa lebar dan jarak antar kolom wajar.
5. Hapus `max-width` form 960px yang dibuat pada design-compact bila kini duplikat dengan mode narrow
   (jangan sampai dua aturan lebar bertumpuk).
6. Dilarang mengunci lebar dengan `px` pada elemen anak. Hanya wrapper `.cims-content` yang mengatur lebar.

## Update CLAUDE.md

Tambahkan di bagian "Layout dan Navigasi" (atau "Kepadatan UI"): tiga mode lebar konten (default 1320px,
narrow 960px, full), cara memilih lewat `ViewData["ContentWidth"]`, aturan "halaman list = default,
form dan detail = narrow, dashboard, Gantt, dan laporan lebar = full", dan larangan menambah
`max-width` manual di view.

## Test

- Layar 1920px: konten selebar maksimum 1320px di tengah area konten. Judul, tombol "Tambah Customer",
  filter bar, tabel, dan pagination sejajar pada tepi kiri dan kanan yang sama. Header tetap selebar layar
  dan sidebar tidak berubah.
- Layar 1366px: tampilan praktis sama seperti sebelumnya (tidak ada ruang kosong baru yang mengganggu).
- Create, Edit, Details di 1920px: selebar maksimum 960px, di tengah.
- Kolom Aksi dan Status tidak melebar. Jarak antar kolom wajar.
- 768px dan 360px: tidak berubah, tidak ada horizontal scroll.
- Toast dan SweetAlert2 tetap muncul di posisi yang benar (toast tetap di pojok kanan atas layar,
  bukan di pojok wrapper).
- Fungsi Customer tetap normal. dotnet build: 0 error, 0 warning.

## Cara kerja

Tampilkan rencana singkat (file yang diubah) dan tunggu persetujuan saya sebelum menulis code.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result, lalu berhenti dan tunggu PASS.
