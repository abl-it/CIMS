# Tugas: Tampilan View lebih compact (density desktop), mobile tetap nyaman disentuh

Baca CLAUDE.md terlebih dahulu dan ikuti semua aturannya.
Terapkan pertama kali pada view modul Customer (Index, Create, Edit, Details) sebagai acuan.
Modul berikutnya wajib mengikuti standar ini.

## Prinsip

- **Compact hanya untuk desktop dan tablet (>= 768px).** Di bawah 768px (mobile) ukuran kontrol
  TIDAK dikecilkan: target sentuh minimal ~44px sesuai CLAUDE.md. Layout card list di mobile tetap.
- **Pendekatan CSS-first (perubahan terkecil yang aman):** definisikan kepadatan sekali di
  wwwroot/css/site.css lewat CSS variables dan satu class pembungkus `.cims-compact` pada `<main>`
  di _Layout.cshtml. Jangan menambahkan `-sm` / `py-1` / `mb-1` manual di setiap elemen view.
  Perubahan markup per view hanya jika CSS tidak cukup.
- Jangan mengubah Controller, Service, SQL, JavaScript (kecuali bagian di bawah yang menyebutnya),
  atau perilaku fitur. Ini murni perubahan tampilan.
- Konsisten dengan app shell (header dan sidebar compact dari design-sidebar). Pakai token ukuran
  yang sama jika sudah ada. Jangan membuat skala ukuran kedua.

## Token kepadatan (CSS variables di :root, nilai awal usulan, sesuaikan jika terlihat janggal)

- --cims-font-size: 0.875rem (body konten), --cims-font-size-sm: 0.8125rem (tabel, label, hint)
- --cims-space-1: 0.25rem, --cims-space-2: 0.5rem, --cims-space-3: 0.75rem
- --cims-control-height: 2rem (input, select, tombol pada desktop)
- --cims-table-cell-py: 0.25rem, --cims-table-cell-px: 0.5rem
- --cims-card-padding: 0.75rem
- Aturan: semua nilai di media query `@media (min-width: 768px)` memakai token ini.
  Di bawah 768px, kembali ke default Bootstrap.

## Spesifikasi per elemen (desktop >= 768px)

### Page header
- Judul halaman (h1/h2) sekitar 1.25rem, margin bawah rapat. Tombol aksi utama ("Tambah")
  sejajar dengan judul di sisi kanan (satu baris), bukan di baris sendiri.
- Hapus ruang kosong berlebih di atas konten (padding container-fluid diperkecil).

### Filter bar (halaman list)
- Satu baris: search, filter status, tombol Cari, tombol Reset. Kontrol setinggi --cims-control-height.
- Di mobile: tumpuk satu kolom, ukuran normal (tidak compact).
- Filter bar dibungkus card tipis atau tanpa card, tanpa padding besar.

### Tabel
- `table-sm` setara: padding sel mengikuti token, font --cims-font-size-sm, header tidak lebih tinggi
  dari baris data.
- Header tabel sticky di dalam `.table-responsive` bila tinggi tabel melebihi viewport
  (position: sticky; top: 0, latar solid).
- Kolom aksi: tombol ikon (Bootstrap Icons: lihat, ubah, nonaktifkan) dengan `title` / tooltip dan
  `aria-label`, bukan tombol bertuliskan teks. Aksi berisiko tetap lewat `data-confirm`.
- Badge status ukuran kecil (font-size 0.75rem).
- Mobile: card list tetap, tetapi padding card dan jarak antar card dirapatkan sedikit tanpa
  mengecilkan tombol.

### Pagination dan info
- `pagination-sm`, digabung dalam satu baris dengan teks "Menampilkan x-y dari z" (kiri) dan
  pilihan ukuran halaman (jika sudah ada) dan pagination (kanan). Di mobile: tumpuk, ukuran normal.

### Form (Create, Edit)
- Grid 2 kolom di >= md (`col-md-6`), 3 kolom untuk field pendek di >= lg bila wajar.
  Field panjang (Alamat, Keterangan) tetap `col-12`. Mobile: satu kolom.
- Label kecil di atas input (font --cims-font-size-sm), jarak antar field --cims-space-2.
- Pesan validasi inline (asp-validation-for) berukuran kecil dan tidak menggeser layout berlebihan.
- Tombol Simpan dan Batal di baris sendiri di kanan bawah form (desktop). Mobile: full width (d-grid).
- Form dibungkus satu card dengan padding --cims-card-padding. Lebar form dibatasi
  (mis. max-width 960px) agar tidak melebar kosong di layar lebar.

### Detail
- Tampilkan sebagai `dl` dua kolom (label dan nilai) di >= md, 2 pasangan per baris di >= lg.
  Mobile: satu kolom.
- Tombol Ubah dan Kembali sejajar dengan judul seperti pada page header.

### Komponen lain
- Card: `card-body` padding --cims-card-padding, `card-header` padding vertikal rapat.
- Modal: padding header dan footer dirapatkan di desktop. SweetAlert2 dan toast TIDAK diubah.
- Alert inline (bila masih ada): padding rapat.

## Aturan teknis

- Seluruh perubahan gaya ada di wwwroot/css/site.css (atau satu file CSS khusus yang dirujuk dari
  _Layout bila site.css sudah terlalu besar). Tanpa inline style. Tanpa CSS framework baru.
- Jangan memakai `!important` kecuali benar-benar diperlukan untuk menimpa Bootstrap. Jelaskan setiap
  pemakaiannya di laporan.
- Pertahankan semua yang sudah ada di _Layout.cshtml (toast container, sweetalert2, notify.js,
  partial notifikasi, validation scripts, sidebar offcanvas).
- Kontras warna dan fokus keyboard (focus ring) tetap terlihat. Compact tidak boleh menghilangkan
  indikator fokus.

## Update CLAUDE.md

- Tambahkan bagian "Kepadatan UI (Compact)": prinsip desktop compact vs mobile nyaman sentuh,
  daftar token, class `.cims-compact`, dan aturan "view baru memakai class dan token ini,
  tanpa kelas ukuran manual per elemen".
- Perbarui Checklist UI: tinggi baris tabel, filter satu baris di desktop, form 2 kolom di desktop,
  target sentuh >= 44px di mobile.
- Perbarui bagian Form dan Tabel agar tidak bertentangan dengan standar compact
  (mis. anjuran `btn-lg` untuk aksi utama berlaku hanya di mobile).

## Test

- Lebar 1366x768: halaman list menampilkan filter bar satu baris, minimal 10 baris data, header
  tabel, dan pagination tanpa scroll halaman (sidebar dan header tetap).
- Lebar 768px (tablet): tampilan compact, tidak ada horizontal scroll.
- Lebar 360px (mobile): card list, kontrol berukuran normal (tinggi >= 44px), form satu kolom,
  tombol full width, tidak ada horizontal scroll.
- Form Create/Edit: dua kolom di desktop. Pesan validasi (mis. kode duplikat) tampil rapi di bawah field.
- Fokus keyboard (Tab) terlihat jelas pada semua kontrol.
- Fungsi Customer (list, search, sort, paging, create, edit, SetActive, toast, SweetAlert2) tetap normal.
- dotnet build: 0 error, 0 warning.

## Cara kerja

Tampilkan rencana dulu (daftar token CSS, perubahan _Layout, view yang disentuh, dan elemen yang butuh
perubahan markup, bukan hanya CSS) dan tunggu persetujuan saya sebelum menulis code.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result, lalu berhenti dan tunggu PASS.
Setelah PASS saya bandingkan tampilan di browser (1366x768 dan 360px) sebelum modul lain dikerjakan.
