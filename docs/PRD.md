# PRD: CIMS (Civil Integrated Management System)

Status: **FINAL v1.0** (2 November 2026). Semua asumsi disetujui (BR-15 direvisi). Siap disimpan sebagai `docs/PRD.md`. Tidak ada asumsi tersisa (03-11-2026).
Owner: Herman (IT Manager)
Sumber: `CIMS-konteks-proyek.md`, source CIMS (CLAUDE.md, Customer, Role.sql, Auth.sql), flow `CIMS.pdf`, form `User entry.xlsx` (CAPEX/OPEX/LVE), form `7. User Satisfaction feedback after completion.xlsx` (+ appendix), `Departments.sql`, `APP_Departments.xlsx`, `APP_SubDepartments.xlsx`, keputusan Herman 31-10-2026 dan 02-11-2026.

Konvensi: `[BELUM DIPUTUSKAN]` = menunggu keputusan Herman. "Asumsi" = usulan, belum disetujui.
"Flow" = dari `CIMS.pdf`. "Form" = dari file Excel Herman. "Data" = dari ekspor tabel `home`. "Keputusan" = dijawab Herman.
ID: `BO-xx`, `BR-xx`, `FR-xx`, `NFR-xx`, `KPI-xx`, `ST-xx` (status), `RL-xx` (role), `CF-xx` (konfigurasi), `MD-xx` (master data).

---

## 0. Ringkasan Manajemen

| Aspek | Isi |
|---|---|
| Current Situation | Permintaan pekerjaan sipil dari departemen ABL dan NKM masuk lewat form Excel, WhatsApp, atau email. Approval berjalan manual/kertas. Jadwal, progress, dan biaya project CAPEX, OPEX, dan LVE direkap Civil di Excel. |
| Problem | (1) Status request dan project sulit dilacak oleh peminta maupun manajemen. (2) Approval lambat dan jejaknya tidak terdokumentasi. (3) Rekap Plan vs Actual (jadwal dan biaya) serta laporan bulanan memakan waktu dan rawan salah. |
| Impact | Keputusan manajemen terlambat karena data tidak real-time; risiko keterlambatan dan pembengkakan biaya project tidak terdeteksi dini; tidak ada ukuran objektif kepuasan departemen terhadap layanan Civil. |
| Solution | **CIMS**: aplikasi web internal satu alur dari business case (Admin dept → Kabag → MO untuk Mill), feasibility Civil, approval GM dan Director, eksekusi in-house/outsource (kontrak oleh Purchasing), progress mingguan, biaya bulanan per item, BAPP (Kabag → FAT → GM/Director), sampai survei kepuasan. Alur approval dapat diubah lewat tabel saat kebijakan berubah. Melayani ABL dan NKM. |
| Expected Benefit | Semua request tercatat dan terlacak; jejak approval lengkap dan dapat diaudit; status jadwal dan biaya setiap project terlihat otomatis di dashboard; laporan dari export dan dashboard tanpa rekap manual; kepuasan user terukur per project. |
| KPI (review) | KPI-01 Ketepatan waktu project ≥ 90% · KPI-02 Deviasi biaya ≤ 5% · KPI-03 Kepuasan user ≥ 85% · KPI-04 Lead time approval ≤ 10 hari kerja. Baseline diukur 3 bulan pertama setelah go-live. |
| Jadwal | Development selesai 30 November 2026 · UAT 1-14 Desember 2026 · Go-live 15 Desember 2026. |

---

## 1. Business Objective

### 1.1 Latar belakang

Kategori anggaran dan sub-kategori (Form, appendix):

| CAPEX | OPEX | LVE |
|---|---|---|
| Construction project | Preventive maintenance | Minor civil works |
| Facility expansion | Corrective maintenance | JDI requisition |
| Major renovation | Emergency maintenance | Non value-added requisition |
| Asset upgrade | Civil improvement | |

### 1.2 Objective

| ID | Objective | Ukuran keberhasilan | Status |
|---|---|---|---|
| BO-01 | Semua request pekerjaan sipil tercatat dan terlacak dari pengajuan sampai Project Closed | % request tercatat di CIMS; lead time request sampai approval | Keputusan |
| BO-02 | Approval berjenjang dan BAPP terdokumentasi, bisa diaudit, dan bisa disesuaikan saat kebijakan berubah | % approval tercatat; jumlah approval overdue | Keputusan |
| BO-03 | Visibilitas jadwal: progress mingguan per action plan dan % penyelesaian project | % project tepat waktu | Keputusan |
| BO-04 | Kontrol biaya: estimasi bulanan vs actual closing bulanan (detail per item) per project dan kategori | Deviasi biaya terhadap plan | Keputusan |
| BO-05 | Kepuasan user terukur lewat survei Kabag setelah Project Closed | Skor kepuasan rata-rata; response rate survei | Keputusan |
| BO-06 | Laporan manajemen tanpa rekap manual | Waktu penyusunan laporan bulanan | Keputusan |

Target angka: lihat KPI (8.2). Baseline belum ada; diukur 3 bulan pertama setelah go-live (Keputusan).

### 1.3 Ruang lingkup tingkat tinggi

- MVP dan fase: lihat bagian 9.
- In scope: Request (business case) dan approval, alur approval berbasis tabel, jalur Emergency, jadwal Preventive, Project planning/execution, input kontrak oleh Purchasing, Action Plan dan progress mingguan, estimasi biaya bulanan dan actual bulanan per item, Gantt, BAPP dan approval, User Satisfaction (template dinamis), Dashboard, Report, Master Data.
- Out of scope: proses sourcing/tender di sisi Purchasing, pembayaran vendor, akuntansi aset, integrasi otomatis ERP untuk actual cost, delegasi approval, workflow engine generik (lihat 3.9). CIMS melayani dua perusahaan, ABL dan NKM, dengan filter Company (3.10).

---

## 2. Current Process

### 2.1 Status flow

Flow `CIMS.pdf` diperlakukan sebagai **proses target (to-be) di CIMS**, diperbarui dengan keputusan Herman.
Form `User entry.xlsx` dan `User Satisfaction` diperlakukan sebagai desain form target.
Kondisi saat ini (Keputusan, 02-11-2026): request lewat form Excel, WhatsApp, atau email; approval manual/kertas; progress dan biaya direkap di Excel. Data volume dan baseline belum dikumpulkan.

### 2.2 Stakeholder

| Lane | Role | Peran | Sumber |
|---|---|---|---|
| Requester | `adm` | Mengisi business case, memilih kategori, revisi, Cancel | Keputusan + Form |
| Kepala bagian requester | `kabag` | Approve/Revise/Reject request departemennya; accept BAPP; mengisi survei | Keputusan |
| Manager Operational (Mill) | `mo` | Approve/Revise/Reject request dari departemen Mill setelah Kabag | Keputusan |
| Civil Department | `civil` | Feasibility, ubah kategori, BOQ/Drawing, TOR, schedule, action plan, estimasi biaya, progress, actual cost, BAPP, closing, survei | Flow + Keputusan |
| Purchasing | `purchasing` | Input vendor, nilai kontrak, lampiran kontrak | Keputusan |
| GM | `gm` | Approval request dan approval akhir BAPP; level pabrik | Keputusan |
| Director | `director` | Approval request CAPEX; level pabrik | Keputusan |
| FAT (Finance, Accounting & Tax) | `fat` | Review/accept BAPP | Keputusan |

### 2.3 Pain point (Keputusan)

| # | Pain point | Dampak |
|---|---|---|
| P1 | Status request dan project sulit dilacak | Peminta menanyakan status berulang; manajemen tidak punya gambaran real-time |
| P2 | Approval lambat dan jejaknya tidak jelas | Pekerjaan tertunda; sulit diaudit siapa menyetujui apa dan kapan |
| P3 | Rekap Plan vs Actual dan laporan manual di Excel | Waktu habis untuk rekap; data rawan salah; keterlambatan/over budget terlambat diketahui |

---

## 3. Workflow

### 3.1 Fase A: Project Request (alur default)

1. `adm` mengisi business case (6.1), memilih kategori dan sub-kategori, lalu Save (draft) atau Submit.
2. KABAG departemen requester → Approve / Revise (ke adm) / Reject.
3. **Hanya untuk departemen grup MILL** (C100, C200, D100, D200, C600, D600): MO → Approve / Revise (ke adm) / Reject.
4. CIVIL Feasibility Study, boleh mengubah kategori → Revise (ke adm) / Reject / Yes. Request hasil revisi wajib melewati Kabag (dan MO untuk Mill) lagi.
5. Yes → CIVIL Prepare Needed Document: Bill of Quantities dan Drawing.
6. GM Project Evaluation → Revise (ke CIVIL Feasibility) / Reject / OK.
7. OK dan bukan CAPEX → Planning.
8. OK dan CAPEX → DIRECTOR Project Review → Revise (ke CIVIL Feasibility) / Reject / Yes → Planning.

Langkah approval di atas adalah **alur default** yang disimpan di tabel workflow (3.9) dan dapat diubah.

### 3.2 Jalur khusus

- **Emergency maintenance (Keputusan):** CIVIL membuat record atas nama departemen peminta (memilih departemen; kategori otomatis OPEX, sub-kategori Emergency maintenance; nomor memakai ABRV departemen peminta), lalu langsung mengeksekusi. Approval susulan Kabag → GM (ABL) paling lambat **3 hari kerja** (CF-02); lewat batas = warning (BR-65).
- **Preventive maintenance (Keputusan):** MVP: CIVIL membuat work order preventive secara manual, tanpa approval, dengan action plan, biaya, dan progress agar masuk dashboard OPEX. Master jadwal berulang: fase berikutnya.

### 3.3 Fase B: Project Execution

1. CIVIL memilih In-House atau Outsource.
2. Outsource → CIVIL menyiapkan TOR & Outsource Requirements → PURCHASING memproses procurement di luar CIMS, lalu menginput vendor, nilai kontrak, dan lampiran kontrak.
3. CIVIL Prepare Schedule and Action Plan: jadwal, action plan berbobot, dan estimasi biaya per bulan (total = plan cost).
4. CIVIL Site Handover and Start Execution.
5. Selama eksekusi: progress per action plan mingguan; upload actual cost bulanan (detail per item barang/jasa) dari data closing akhir bulan.

### 3.4 Fase C: Project Closing

1. CIVIL Project Complete → Issue BAPP.
2. KABAG review BAPP → Accept / No (kembali ke CIVIL).
3. FAT review BAPP → Accept / No (kembali ke CIVIL).
4. GM review BAPP → Accept / No (kembali ke CIVIL). Accept → Project Closed.
5. CIVIL kirim survei ke KABAG → KABAG mengisi → CIVIL arsipkan.

Rantai approval BAPP juga **alur default** di tabel workflow (3.9). MO tidak ikut approval BAPP (Keputusan).

### 3.5 Aturan bisnis

| ID | Aturan | Sumber |
|---|---|---|
| BR-01 | Request dibuat oleh `adm` departemen peminta. | Keputusan |
| BR-02 | Kategori dan sub-kategori wajib dipilih requester. CIVIL boleh mengubah keduanya saat Feasibility; perubahan dicatat (lama, baru, oleh, waktu, alasan). | Keputusan |
| BR-03 | Request wajib disetujui Kabag departemen peminta sebelum diterima CIVIL. Kabag dapat Approve, Revise, atau Reject. | Keputusan |
| BR-04 | CIVIL dapat mengembalikan request ke `adm`. Request hasil revisi wajib melewati seluruh langkah approval sebelum Civil lagi. | Flow + Keputusan |
| BR-05 | Request yang lolos feasibility wajib dilengkapi **BOQ (semua kategori)**; **Drawing wajib untuk CAPEX**, opsional untuk OPEX/LVE. | Flow + Keputusan |
| BR-06 | Semua request yang lolos feasibility wajib dievaluasi GM. Revise dari GM kembali ke CIVIL (Feasibility). | Flow |
| BR-07 | Hanya request CAPEX yang di-review DIRECTOR, setelah GM OK. Revise dari DIRECTOR kembali ke CIVIL. | Flow + Keputusan |
| BR-08 | Request dapat ditolak permanen (Rejected) oleh approver dengan alasan wajib. | Keputusan |
| BR-09 | Request dapat dibatalkan (Cancelled) oleh requester hanya sebelum disetujui GM. | Keputusan |
| BR-10 | Jumlah revisi tidak dibatasi; setiap revisi tercatat di riwayat. | Keputusan |
| BR-11 | Outsource wajib melalui TOR dari CIVIL. PURCHASING menginput vendor, nilai kontrak, dan lampiran kontrak. | Flow + Keputusan |
| BR-12 | Plan cost: outsource = nilai kontrak; in-house = nilai BOQ yang disetujui GM/Director. | Keputusan |
| BR-13 | CIVIL menyusun estimasi biaya total per bulan (tidak per item). Total estimasi wajib sama dengan plan cost (divalidasi sistem). | Keputusan |
| BR-14 | Schedule & Action Plan disusun sebelum site handover; untuk outsource, setelah kontrak diinput Purchasing. | Flow |
| BR-15 | **Tanggal mulai project mengikuti schedule yang disusun CIVIL** (bukan tanggal site handover). Rentang dari **tanggal kontrak selesai/diinput Purchasing sampai tanggal mulai project** ditandai sebagai **periode Preparation** (tampil di detail project dan Gantt; tidak dihitung dalam status jadwal). Untuk project **in-house**, periode Preparation dihitung dari **selesainya management approval** sampai tanggal mulai project. | Keputusan (02-11-2026, in-house 03-11-2026) |
| BR-16 | Setiap action plan punya bobot (%), total bobot per project = 100%. CIVIL mengisi % progress per action plan setiap minggu. | Keputusan |
| BR-17 | % penyelesaian project = Σ(bobot × % progress action plan). Plan progress mingguan dihitung dari tanggal plan (kurva S). | Keputusan |
| BR-18 | Actual cost diupload bulanan oleh CIVIL lewat satu template Excel untuk semua project, detail per item barang atau jasa, dari data closing akhir bulan; total actual per bulan dibandingkan dengan estimasi bulan tersebut. Input manual tersedia sebagai cadangan. | Keputusan |
| BR-19 | Upload ulang untuk bulan yang sama menimpa data actual bulan tersebut; file asli setiap upload diarsipkan. | Keputusan |
| BR-20 | Approval BAPP default berurutan KABAG → FAT → GM. Penolakan di level mana pun kembali ke CIVIL. | Flow + Keputusan |
| BR-21 | Project Closed hanya setelah langkah terakhir approval BAPP menerima. | Flow |
| BR-22 | Setelah Closed, CIVIL mengirim survei ke KABAG departemen peminta; KABAG mengisi; hasil diarsipkan. | Keputusan |
| BR-23 | GM dan DIRECTOR adalah approver tingkat pabrik untuk seluruh departemen. | Keputusan |
| BR-24 | **Satu ABRV = satu Kabag.** Kabag yang berwenang = pemegang role `kabag` pada ABRV (dan Company) yang sama dengan departemen requester. Contoh: QC C500 dan D500 di-approve Kabag QC yang sama; berlaku juga ENG (C300/D300), UTL (C400/D400), MO (C600/D600), WH-LOG (A400/B200). Bila ternyata ada lebih dari satu, yang approve pertama berlaku. | Keputusan |
| BR-25 | Emergency maintenance dibuat CIVIL atas nama departemen peminta dan boleh dieksekusi sebelum approval; approval Kabag dan GM wajib menyusul dalam **3 hari kerja** (CF-02). | Keputusan |
| BR-26 | Preventive maintenance dibuat manual oleh CIVIL sebagai work order tanpa approval (MVP); jadwal berulang di fase berikutnya. | Keputusan |
| BR-64 | Batas waktu berbasis **hari kerja** dihitung dengan mengecualikan hari libur mingguan dan tanggal libur dari tabel kalender (MD-11), per Company. | Keputusan |
| BR-50 | Request dari departemen Mill wajib disetujui MO setelah Kabag dan sebelum CIVIL. MO dapat Approve, Revise (ke adm), atau Reject. | Keputusan |
| BR-51 | Departemen Mill dan departemen yang menjadi lingkup MO disimpan di tabel grup departemen (bukan hardcode), sehingga dapat diubah saat struktur organisasi berubah. | Keputusan (tabel = sesuai prinsip workflow dinamis) |

### 3.6 Status

| ID | Status | Masuk ketika | Pemegang aksi |
|---|---|---|---|
| ST-01 | Draft | `adm` Save belum Submit | ADM |
| ST-02 | Waiting Approval | Submit / resubmit; sub-langkah dari tabel workflow (default: Kabag, lalu MO untuk Mill) | Sesuai langkah |
| ST-03 | Returned to User | Revise ke requester | ADM |
| ST-04 | Feasibility | Semua langkah approval sebelum Civil selesai | CIVIL |
| ST-05 | Document Preparation | Feasibility = Yes (BOQ, Drawing) | CIVIL |
| ST-06 | Management Approval | CIVIL kirim; sub-langkah dari tabel workflow (default: GM, lalu Director untuk CAPEX) | Sesuai langkah |
| ST-08 | Planning | Semua langkah management approval selesai | CIVIL |
| ST-09 | Procurement | Outsource, TOR dikirim | PURCHASING |
| ST-10 | Scheduling / Preparation | In-house, atau kontrak diinput; berlangsung sampai tanggal mulai project (periode Preparation, BR-15) | CIVIL |
| ST-11 | In Progress | CIVIL mencatat site handover dan start execution (pada/sesudah tanggal mulai project di schedule) | CIVIL |
| ST-12 | BAPP Review | CIVIL menerbitkan BAPP; sub-langkah dari tabel workflow (default: Kabag → FAT → GM) | Sesuai langkah |
| ST-13 | Closed | Langkah terakhir BAPP accept | - |
| ST-14 | Survey Completed | KABAG mengisi survei | - |
| ST-15 | Rejected | Ditolak approver (final) | - |
| ST-16 | Cancelled | Dibatalkan requester sebelum management approval selesai | - |

ST-07 tidak dipakai (digabung ke ST-06 sejak v0.6).

### 3.7 Overdue

| ID | Aturan | Sumber |
|---|---|---|
| BR-32 | **Tidak ada penanda Overdue untuk langkah approval** (keputusan 02-11-2026, menggantikan keputusan 31-10-2026). Lama menunggu tetap terlihat dari tanggal mulai langkah di riwayat approval. | Keputusan |
| BR-65 | **Pengecualian:** Emergency yang approval susulannya belum selesai dalam 3 hari kerja (CF-02) sejak record dibuat **ditandai warning** di list, detail, dan Tugas Saya approver serta Civil. Warning tidak memblokir proses. | Keputusan |

### 3.8 Konfigurasi (tabel SQL)

| ID | Kunci | Isi | Nilai awal |
|---|---|---|---|
| CF-02 | Batas approval susulan Emergency | `dbo.AppSetting` (nilai + satuan) | 3 hari kerja (Keputusan, BR-65) |
| CF-07 | Hari libur mingguan dan tanggal libur | Tabel kalender kerja MD-11 (per Company) | Sabtu-Minggu + libur nasional |
| CF-03 | Format dan ukuran lampiran | Tabel jenis lampiran (6.5) | Lihat 6.5 (Keputusan) |
| CF-04 | Path penyimpanan lampiran | `appsettings.json`: `FileStorage:RealizationAttachmentsPath` = `D:\APP_DATA\CIMSAttachments` | Keputusan |
| CF-05 | Grup departemen (Mill, lingkup MO) | Tabel grup departemen (3.9) | Lihat 3.9 |
| CF-06 | Konfigurasi per Company (workflow, lokasi, setting) | Kolom `CoCode` di tabel terkait (3.10) | Lihat 3.9 dan 3.10 (Keputusan) |

### 3.9 Workflow dinamis (Keputusan)

**Kebutuhan:** alur approval dapat diubah saat kebijakan berubah, tanpa ubah kode.

**Batas desain (Keputusan):**
- **Dinamis (tabel):** rantai approval pada tiga titik: (1) approval request sebelum Civil, (2) management approval setelah dokumen Civil, (3) approval BAPP. Per langkah: urutan, role approver, lingkup approver, **kondisi berlaku** (kategori dan/atau grup departemen requester), boleh Revise dan tujuannya, boleh Reject, aktif/nonaktif.
- **Tetap (kode):** tahapan operasional Civil (Feasibility, Document Preparation, Planning, Procurement, Scheduling, In Progress, Closing, Survey).

**Lingkup approver:**
- `DEPT` = pemegang role pada **ABRV + Company** departemen requester (Kabag), sesuai BR-24.
- `GROUP` = pemegang role yang dipetakan ke grup departemen requester (MO → grup MILL).
- `PLANT` = pemegang role di tingkat pabrik (GM, Director, FAT) **pada Company yang sama dengan request** (Keputusan, BR-63).

Isi default **ABL** (`CoCode = ABL`):

| Titik | Urutan | Role | Lingkup | Berlaku untuk kategori | Berlaku untuk grup dept | Revise ke | Reject |
|---|---|---|---|---|---|---|---|
| REQUEST | 1 | `kabag` | DEPT | Semua | Semua | Requester | Ya |
| REQUEST | 2 | `mo` | GROUP | Semua | MILL | Requester | Ya |
| MGMT | 1 | `gm` | PLANT | Semua | Semua | Civil | Ya |
| MGMT | 2 | `director` | PLANT | CAPEX | Semua | Civil | Ya |
| BAPP | 1 | `kabag` | DEPT | Semua | Semua | Civil | - (No = kembali ke Civil) |
| BAPP | 2 | `fat` | PLANT | Semua | Semua | Civil | - |
| BAPP | 3 | `gm` | PLANT | Semua | Semua | Civil | - |

Isi default **NKM** (`CoCode = NKM`, Keputusan; dapat diubah lewat tabel):

| Titik | Urutan | Role | Lingkup | Berlaku untuk kategori | Berlaku untuk grup dept | Revise ke | Reject |
|---|---|---|---|---|---|---|---|
| REQUEST | 1 | `kabag` | DEPT | Semua | Semua | Requester | Ya |
| MGMT | 1 | `director` | PLANT | **Semua** | Semua | Civil | Ya |
| BAPP | 1 | `kabag` | DEPT | Semua | Semua | Civil | - |
| BAPP | 2 | `fat` | PLANT | Semua | Semua | Civil | - |
| BAPP | 3 | `director` | PLANT | Semua | Semua | Civil | - |

Catatan: di NKM tidak ada langkah MO dan GM; Director meng-approve semua kategori dan menjadi approver akhir BAPP. Approval susulan Emergency NKM: Kabag → Director (Keputusan, mengikuti alur NKM).

**Grup departemen default (Keputusan):**

| Grup | Departemen anggota (`APP_Departments`) | Dipakai untuk |
|---|---|---|
| MILL | C100 PAPER PRODUCTION (PM), C200 PAPER FINISHING (FIN), D100 TISSUE PRODUCTION (TPM), D200 TISSUE CONVERTING (CONV), C600 / D600 MANAGER OPERATIONAL (MO) | Kondisi langkah MO **dan** lingkup data role `mo` (5 ABRV: PM, FIN, TPM, CONV, MO; satu MO) |

| ID | Aturan | Status |
|---|---|---|
| BR-37 | Saat request di-Submit (dan saat BAPP diterbitkan), langkah approval yang berlaku di-snapshot ke request. Perubahan tabel workflow/grup hanya berlaku untuk request/BAPP baru. | Keputusan |
| BR-38 | Perubahan tabel workflow dan grup departemen hanya oleh `administrator`, tercatat (oleh, waktu). MVP lewat script SQL; halaman pengaturan di fase berikutnya. | Keputusan |
| BR-39 | Satu langkah = satu role. Approve oleh siapa pun pemegang role tersebut dalam lingkupnya; yang pertama berlaku. | Keputusan |
| BR-52 | Langkah yang kondisinya tidak terpenuhi (mis. MO untuk departemen non-Mill, Director untuk non-CAPEX) dilewati otomatis dan tidak dimasukkan ke snapshot. | Keputusan |
| BR-53 | Jika Civil mengubah kategori setelah snapshot (mis. OPEX → CAPEX), langkah management approval disusun ulang dari tabel saat request dikirim ke management (bukan saat Submit), agar Director ikut bila menjadi CAPEX. | Keputusan (direkomendasikan) |

### 3.10 Multi-company: ABL dan NKM (Keputusan: keduanya dilayani, ada filter Company)

| ID | Aturan | Status |
|---|---|---|
| BR-56 | Setiap request menyimpan `CoCode` (dari `app_employees.CoCode` requester). Semua data transaksi, lookup department/cost center, dan dashboard difilter per Company. | Keputusan |
| BR-57 | `administrator`, `civil`, `director`, `gm` melihat data ABL dan NKM (filter Company di list, dashboard, report; default = Company user). Role lain hanya Company-nya sendiri. | Keputusan |
| BR-58 | Tabel workflow (3.9) dan grup departemen punya kolom `CoCode`; alur approval per Company. | Keputusan |
| BR-59 | Civil ABL melayani request ABL dan NKM. `purchasing` juga mencakup kedua Company. | Keputusan |
| BR-60 | Alur request NKM: **Kabag → Civil → Director** (semua kategori), disimpan di tabel workflow agar bisa diubah. | Keputusan |
| BR-61 | Per Company: Lokasi dan workflow. Dipakai bersama: Vendor, Satuan, sub-kategori, template survei, Environment Assessment, jenis lampiran. | Keputusan |
| BR-62 | Nomor request NKM: sufiks ` - NKM` pada ABRV dibuang dan diganti prefiks Company: `NKM-{ABRV}-{CPX/OPX/LVE}-{MM}-{YY}-{NNN}` (mis. `NKM-FAT-CPX-11-26-001`). ABL tanpa prefiks. | Keputusan |
| BR-63 | Hak melihat lintas Company tidak memberi hak approve lintas Company: approver hanya untuk request dengan `CoCode` sama dengan `CoCode` karyawannya. Satu orang yang menjabat di dua Company didaftarkan lewat tabel workflow. | Keputusan |

---

## 4. Data: Plan vs Actual

| Elemen | Plan | Actual | Frekuensi | Input oleh |
|---|---|---|---|---|
| Total biaya | Nilai kontrak (outsource) / nilai BOQ disetujui (in-house) | Akumulasi actual bulanan | - | Purchasing / sistem |
| Biaya per bulan | Estimasi total per bulan (total = plan cost) | Total dari item actual bulan tersebut | Bulanan | Civil |
| Jadwal | Tanggal mulai project dan tanggal plan per action plan (schedule Civil); periode Preparation sebelum mulai | Tanggal aktual per action plan | Mingguan | Civil |
| Progress | Plan progress mingguan (kurva S) | Σ(bobot × % progress action plan) | Mingguan | Civil |
| Status jadwal/biaya/keseluruhan | Lihat bagian 8.1 | | Saat progress/actual disimpan | Sistem |

---

## 5. User dan Role

### 5.1 Daftar role

| ID | Kode role | Nama | Level (tampilan) | Lingkup data | Sumber role | Status |
|---|---|---|---|---|---|---|
| RL-01 | `administrator` | Administrator sistem (IT) | 1 | Semua | Seed existing | Keputusan |
| RL-02 | `director` | Director | 3 | Semua | Role umum portal | Keputusan |
| RL-03 | `gm` | General Manager | 4 | Semua | Role umum portal | Keputusan |
| RL-04 | `civil` | Civil Department | 5 | Semua (ABL + NKM) | Role khusus, didaftarkan di portal | Keputusan |
| RL-05 | `fat` | Finance, Accounting & Tax | 5 | Project di tahap BAPP dan biaya | Role khusus, dibuat di portal | Keputusan |
| RL-09 | `mo` | Manager Operational | 6 | Grup MILL (6 DepartmentID, 5 ABRV) | Role umum portal (sudah ada di seed) | Keputusan |
| RL-06 | `purchasing` | Purchasing | 6 | Project outsource (ABL + NKM) | Role khusus, dibuat di portal | Keputusan |
| RL-07 | `kabag` | Kepala Bagian | 7 | Departemen sendiri | Role umum portal | Keputusan |
| RL-08 | `adm` | Admin Departemen (requester) | 10 | Departemen sendiri | Role umum portal | Keputusan |

Level hanya untuk tampilan; nilai sama diperbolehkan. Role seed lain (`komisaris`, `plan`, `spv`, `emp`, `creator`) tidak memberi akses ke CIMS.

### 5.2 Matriks hak akses per modul

Legenda: **C** = buat/ubah · **A** = approve/reject/revise · **R** = lihat · **-** = tidak ada akses. (D) = departemen sendiri (ABRV + Company) · (G) = departemen grup MILL.
Semua role dibatasi Company-nya sendiri kecuali ditetapkan lain di 3.10.
Kolom A mengikuti **default** tabel workflow (3.9); bila tabel diubah, hak approve mengikuti tabel.

| Modul / aksi | adm | kabag | mo | civil | purchasing | fat | gm | director | administrator |
|---|---|---|---|---|---|---|---|---|---|
| Request: buat, revisi, cancel | C (D) | R (D) | R (G) | R | - | - | R | R | R |
| Request: approval sebelum Civil | - | A (D) | A (G) | - | - | - | - | - | - |
| Feasibility, ubah kategori, BOQ, Drawing | R (D) | R (D) | R (G) | C/A | - | - | R | R | R |
| Management approval (GM, Director CAPEX) | - | - | - | - | - | - | A | A | R |
| TOR | - | - | - | C | R | - | R | R | R |
| Kontrak (vendor, nilai, lampiran) | - | - | - | R | C | R | R | R | R |
| Schedule, action plan, estimasi biaya | R (D) | R (D) | R (G) | C | - | R | R | R | R |
| Progress mingguan | R (D) | R (D) | R (G) | C | - | - | R | R | R |
| Upload actual cost | - | - | - | C | - | R | R | R | R |
| BAPP: terbitkan | - | - | - | C | - | - | - | - | - |
| BAPP: accept | - | A (D) | R (G) | R | - | A | A | R | R |
| Survei: isi | - | C (D) | R (G) | R | - | - | R | R | R |
| Dashboard dan Report | R (D) | R (D) | R (G) | R | - | R | R | R | R |
| Master Data | - | - | - | C | - | - | R | R | C |
| Konfigurasi (workflow, grup dept, AppSetting, template) | - | - | - | - | - | - | - | - | via SQL |

### 5.3 Aturan akses

| ID | Aturan | Status |
|---|---|---|
| BR-27 | Akses diizinkan jika salah satu role user ada di matriks (any-of); user tanpa role CIMS ditolak. Pemegang role umum portal (`adm`, `kabag`, `mo`, `gm`, `director`) otomatis bisa masuk. | Keputusan |
| BR-28 | `adm` dan `kabag` hanya melihat dan memproses data **departemennya sendiri = semua DepartmentID dengan ABRV dan Company yang sama** (mis. Kabag/adm QC melihat C500 dan D500); `mo` hanya grup MILL. | Keputusan |
| BR-29 | User dengan beberapa role mendapat gabungan hak aksesnya. | Keputusan |
| BR-30 | Approver tidak boleh meng-approve request yang ia buat sendiri. | Keputusan |
| BR-31 | Karyawan dengan `ResignDate` terisi dan sudah lewat (≤ hari ini) ditolak masuk CIMS. | Keputusan |
| BR-35 | MVP memakai satu role `civil`; setiap aksi tercatat atas nama pelaku. | Keputusan |
| BR-36 | Tidak ada delegasi approval di MVP. | Keputusan |

### 5.4 Input untuk `design-role` (serah-terima)

- Role CIMS: `administrator`, `director`, `gm`, `civil`, `fat`, `mo`, `purchasing`, `kabag`, `adm`. Tambah `fat` (5) dan `purchasing` (6) ke `dbo.HierarchyLevel`; `mo` (6) sudah ada di seed.
- Filter per action memakai daftar role any-of dari matriks 5.2; `AllowAllRoles` = semua role CIMS di atas.
- Tambahan di luar rencana `design-role` saat ini:
  - lingkup data per ABRV + Company untuk `adm`/`kabag` dan grup MILL untuk `mo` (BR-28), serta filter Company (3.10), di stored procedure;
  - `CurrentUser` perlu `DepartmentID` (saat ini `usp_Auth_GetUserByUsername` hanya mengembalikan `DeptName`, `ABRV`, dan `CoCode`; `app_employees.DepartmentID` sudah di-join);
  - cek `ResignDate` (BR-31);
  - hak approve dibaca dari langkah workflow aktif (3.9), bukan hardcode role.
- Sidebar per role: menu tampil hanya jika user punya minimal satu role yang berhak membaca modul tersebut.

---

## 6. Data

### 6.1 Form Request / Business Case (dari `User entry.xlsx`)

Satu form untuk ketiga kategori; perbedaan CAPEX ditandai.

**(i) Preliminary Data**

| Field | Tipe | Wajib | Sumber nilai | Catatan |
|---|---|---|---|---|
| Request number | Teks | Otomatis | Sistem, saat Submit | Format BR-41 |
| PIC of project | Karyawan | Ya | Picker karyawan **aktif** departemen requester (`app_employees`) | Keputusan |
| Company | Kode | Otomatis, terkunci | `app_employees.CoCode` user | Keputusan |
| Requesting department | Lookup | Otomatis, terkunci | Departemen `adm` (`app_employees.DepartmentID` → `APP_Departments`) | Keputusan |
| Request title | Teks | Ya | Input user | |
| Create date | Tanggal | Otomatis | Sistem | Local time |
| Budget classification | Pilihan | Ya | CAPEX / OPEX / LVE | Keputusan (boleh diubah Civil) |
| Sub-kategori | Pilihan cascade | Ya | MD-01, difilter oleh kategori | Keputusan (boleh diubah Civil) |
| Budget remarks | Pilihan | Ya | Budgeted / Unbudgeted | Form |
| Cost center | Lookup cascade | Ya | `APP_SubDepartments.SubDepartmentCode` (mis. C510) dengan `DepartmentID` = department requester | Keputusan; kolom `CostCenter` di data kosong, jadi kode diambil dari `SubDepartmentCode` (Data) |
| Location | Pilihan | Ya | MD-02 | Form |
| Target completion | Tanggal | Ya | Estimasi user | Form |
| Section area (m²) | Desimal | Ya | Panjang × lebar | Simpan panjang, lebar, dan luas hasil hitung |
| Budget expectation (IDR) | Uang | Ya | Estimasi user | Bukan plan cost |

**(ii) Business Justification** (teks panjang, wajib kecuali ditandai)
Background · Objective · Impact to operational · Risk if not approved · Expected benefits · Alternatives · Special request / note (opsional).
**Khusus CAPEX:** Expected ROI (%) / penjelasan · Lampiran perhitungan ROI (PDF, dengan approval end user).

**(iii) Environment Assessment** — pertanyaan Yes/No dari tabel MD-08 (default 12 pertanyaan sesuai form), di-snapshot saat Submit.

**(iv) Additional Information** — teks (opsional) · **Foto area (wajib)**.

**Aksi:** Save (Draft) · Edit · Submit.

| ID | Aturan | Status |
|---|---|---|
| BR-40 | Requesting department otomatis dari departemen `adm` dan tidak bisa diubah; cost center dipilih dari sub-department milik department tersebut. Sub-department/department yang `Disabled` tidak ditampilkan. | Keputusan |
| BR-41 | **Format nomor request: `{ABRV}-{CPX/OPX/LVE}-{MM}-{YY}-{NNN}`** (format form, "CVL" diganti ABRV departemen requester). Contoh: `QC-CPX-10-26-001`. Nomor dibuat saat Submit. Urutan NNN per kombinasi Company + ABRV + kategori + bulan + tahun. Format untuk NKM: BR-62. | Keputusan |
| BR-54 | Jika Civil mengubah kategori, nomor request ikut berubah: **bulan dan tahun tetap** mengikuti Submit awal, kode kategori diganti, NNN diambil dari urutan kategori baru (mis. `QC-OPX-10-26-004` → `QC-CPX-10-26-002`). Nomor lama disimpan di riwayat dan tetap bisa dicari. | Keputusan |
| BR-55 | Karena nomor request bisa berubah, relasi antar tabel, folder lampiran, dan URL memakai Id internal, bukan nomor request. | Keputusan (teknis, wajib) |
| BR-42 | Field ROI dan lampiran ROI wajib hanya untuk CAPEX. | Keputusan |
| BR-43 | Foto area wajib. | Keputusan |

### 6.2 Master data

| ID | Master | Sumber | Pengelola | Isi awal | Status |
|---|---|---|---|---|---|
| MD-01 | Sub-kategori pekerjaan (per CAPEX/OPEX/LVE) | Tabel CIMS | Civil / administrator | 11 baris dari appendix | Keputusan |
| MD-02 | Lokasi / Area | Tabel CIMS | Civil / administrator | 41 lokasi dari appendix | Keputusan |
| MD-03 | Vendor | Tabel CIMS | Purchasing / Civil | Kosong | Keputusan |
| MD-04 | Satuan | Tabel CIMS | Civil | m, m², m³, kg, ton, unit, set, lot, ls (lump sum), hari, jam | Keputusan |
| MD-05 | Department | `home..APP_Departments` (baca saja) | Portal | - | Keputusan |
| MD-06 | Cost center | `home..APP_SubDepartments` (baca saja) | Portal | - | Keputusan |
| MD-07 | Template survei (item penilaian) | Tabel CIMS | administrator | 5 item default (6.5) | Keputusan |
| MD-08 | Pertanyaan Environment Assessment | Tabel CIMS | administrator | 12 pertanyaan default | Keputusan |
| MD-09 | Jenis lampiran (format, ukuran) | Tabel CIMS | administrator | Lihat 6.4 | Keputusan |
| MD-10 | Grup departemen (MILL, lingkup MO) | Tabel CIMS, mereferensikan `APP_Departments.DepartmentID` | administrator | Lihat 3.9 | Keputusan |
| MD-11 | Kalender kerja: hari libur mingguan dan tanggal libur (per Company) | Tabel CIMS | administrator | Sabtu-Minggu; tanggal libur diisi per tahun | Keputusan |

Modul **Customer** tetap disimpan sebagai acuan pola (dirujuk CLAUDE.md), disembunyikan dari menu setelah master pertama CIMS selesai. (Keputusan)

### 6.3 Temuan struktur departemen (Data)

| # | Temuan | Dampak | Penanganan |
|---|---|---|---|
| 1 | Relasi: `app_employees.DepartmentID` → `APP_Departments.DepartmentID`; `APP_SubDepartments.DepartmentID` → `APP_Departments.DepartmentID`. Tidak ada tabel `Departments` terpisah; `DeptName` adalah kolom di `APP_Departments`. | - | Dipakai apa adanya |
| 2 | ABRV dipakai bersama oleh beberapa DepartmentID: QC (C500, D500), ENG (C300, D300), UTL (C400, D400), WH-LOG (A400, B200), MO (C600, D600). | Nomor request dan lingkup departemen | **Satu ABRV = satu Kabag** (Keputusan). Lingkup dan nomor memakai ABRV + Company |
| 3 | Kolom `HoD`/`HoDEmployeeID` kosong/0 di data. | Kabag tidak bisa diambil dari HoD | Kabag = pemegang role `kabag` di departemen yang sama (BR-24) |
| 4 | Kolom `CostCenter` di `APP_SubDepartments` kosong; kode cost center ada di `SubDepartmentCode`. Di `APP_Departments`, `CostCenter` berisi label (mis. "Utility"). | Sumber kode cost center | Pakai `SubDepartmentCode` |
| 5 | Ada dua perusahaan: `CoCode` ABL (Pekanbaru) dan NKM (Tangerang). ABRV NKM mengandung spasi dan sufiks (mis. `FAT - NKM`, `DIR - NKM`). Struktur NKM berbeda: tidak ada departemen GM; ada `A200 OPERASIONAL MANAGER - NKM`. Civil (A350) hanya ada di ABL. | Workflow, nomor, master per company | 3.10 |
| 6 | Kolom `Disabled` ada di kedua tabel. | Departemen nonaktif | Disaring (BR-40) |

### 6.4 Actual cost per item

| Kolom template | Tipe | Wajib | Catatan |
|---|---|---|---|
| Request No | Teks | Ya | Nomor terkini; harus cocok dengan project In Progress |
| Bulan | YYYY-MM | Ya | |
| Jenis | Barang / Jasa | Ya | Keputusan |
| Nama item | Teks | Ya | Tanpa master item (Keputusan) |
| Qty | Desimal | Ya | |
| Satuan | Teks / MD-04 | Ya | |
| Harga satuan | Uang | Ya | |
| Amount | Uang | Ya | = Qty × Harga satuan (divalidasi) |
| No. referensi (PO/GR/Jurnal) | Teks | Tidak | |
| Keterangan | Teks | Tidak | |

Total amount per project per bulan dibandingkan dengan estimasi bulan tersebut (BR-18).

### 6.5 Lampiran

| ID | Aturan | Status |
|---|---|---|
| BR-44 | File disimpan di folder dari `FileStorage:RealizationAttachmentsPath` (`D:\APP_DATA\CIMSAttachments`), metadata di database. Subfolder per tahun/Id request | Keputusan |
| BR-45 | Format yang diizinkan dan ukuran maksimal disimpan di tabel per jenis lampiran (MD-09), dapat diubah tanpa deploy. | Keputusan |
| BR-46 | Lampiran tidak dihapus fisik; hanya dinonaktifkan. | Keputusan |

Jenis lampiran awal (Keputusan; nilai di tabel MD-09):

| Jenis | Format | Maks. ukuran |
|---|---|---|
| ROI calculation, Foto area | PDF, JPG, PNG | 5 MB |
| BOQ, Drawing, TOR, Kontrak, BAPP | PDF, XLSX, DWG | 20 MB |
| File upload actual cost | XLSX | 5 MB |

`RealizationAttachmentsPath` dipakai untuk semua jenis lampiran.

### 6.6 User Satisfaction (dari `7. User Satisfaction ... .xlsx`)

- Diisi KABAG setelah Project Closed. Skala **1-10** per item. (Form)
- Item default (template MD-07): Compliance with user requirements · Work quality · Timeliness of completion · Communication and coordination · Site cleanliness and housekeeping. Ditambah **Note for Civil** (teks).
- Skor per item = nilai / 10; skor survei = rata-rata skor item (contoh form CAPEX: 10, 9, 8, 10, 7 → 88%). (Form)

| ID | Aturan | Status |
|---|---|---|
| BR-47 | Item survei disimpan di tabel template; template default berisi 5 item di atas, per kategori (default ketiganya sama). | Keputusan |
| BR-48 | Saat survei dikirim, item template di-snapshot ke survei. | Keputusan |
| BR-49 | Semua item wajib dinilai sebelum Submit; Note for Civil opsional. | Keputusan |

### 6.7 Entitas (Keputusan)

ProjectRequest · RequestNoHistory · RequestAssessmentAnswer · ApprovalStep (snapshot) · ApprovalHistory · CategoryChangeLog · Attachment · Contract · ActionPlan · ProgressWeekly · CostPlanMonthly · CostActualUpload · CostActualItem · BAPP · Survey · SurveyAnswer · WorkflowStep (definisi) · DepartmentGroup · DepartmentGroupMember · SurveyTemplateItem · AssessmentQuestion · AttachmentType · SubCategory · Location · Vendor · Unit · AppSetting · RequestNoSequence.

---

## 7. Notifikasi dan Integrasi

### 7.1 Notifikasi (Keputusan)

| ID | Kebutuhan | Status |
|---|---|---|
| BR-66 | MVP **tidak mengirim notifikasi** (email, WhatsApp, push). Pemberitahuan hanya di dalam aplikasi. | Keputusan |
| FR-01 | **Shortcut "Tugas Saya" di dashboard setiap user**: daftar pekerjaan yang menunggu aksi user tersebut, dengan jumlah per jenis dan link langsung ke halaman aksinya. | Keputusan |
| FR-02 | Badge jumlah tugas di header, angka sama dengan FR-01. | Keputusan |

Isi "Tugas Saya" (Keputusan, dari daftar kejadian):

| Kejadian | Muncul di Tugas Saya milik | Aksi |
|---|---|---|
| Langkah approval aktif (request, management, BAPP) | Approver langkah tersebut (sesuai role, lingkup, Company) | Approve / Revise / Reject |
| Request di-Revise | Requester (`adm`) | Revisi dan Submit ulang |
| Request di-Reject | Requester (`adm`) | Informasi (hilang setelah dibuka) |
| Request lolos approval awal / management | `civil` | Feasibility / Planning |
| TOR dikirim | `purchasing` | Input vendor, nilai kontrak, lampiran |
| BAPP terbit | Approver BAPP aktif | Accept / No |
| Survei dikirim | Kabag departemen peminta | Isi survei |

Pengingat harian dan penanda overdue tidak ada (BR-32).

### 7.2 Integrasi (Keputusan)

| ID | Kebutuhan | Status |
|---|---|---|
| BR-67 | MVP **tanpa integrasi** selain SSO portal dan baca data `home` (users, app_employees, APP_Departments, APP_SubDepartments). Actual cost lewat upload Excel; kontrak diinput Purchasing. | Keputusan |
| NFR-01 | Tidak ada job terjadwal (Worker Service / SQL Agent) di MVP, karena tidak ada notifikasi dan pengingat. | Keputusan (turunan) |

---

## 8. KPI dan Status Project

### 8.1 Status project (Keputusan; ambang disimpan di tabel, dapat diubah)

| ID | Status | Definisi | Formula | Ambang default |
|---|---|---|---|---|
| BR-68 | **Status jadwal** (On Track / Slightly Delay / Delay) | Selisih progress actual terhadap plan pada minggu berjalan | Deviasi = % progress actual − % progress plan (poin) | On Track: ≥ −5 · Slightly Delay: −5 s.d. −15 · Delay: < −15, **atau** tanggal selesai plan sudah lewat dan progress < 100% |
| BR-69 | **Status biaya** (On Track / At Risk / Over Budget) | Realisasi biaya kumulatif terhadap estimasi kumulatif sampai bulan closing terakhir (*lower is better*) | Rasio = Σ actual ÷ Σ estimasi × 100% | On Track: ≤ 100% · At Risk: > 100% s.d. 110% · Over Budget: > 110% |
| BR-70 | **Status keseluruhan** (On Track / At Risk / Delayed, kartu dashboard) | Status terburuk antara jadwal dan biaya | Peta: On Track+On Track = On Track; Slightly Delay atau At Risk = At Risk; Delay atau Over Budget = Delayed | - |
| BR-71 | Status dihitung otomatis saat progress mingguan atau actual bulanan disimpan; tidak dapat diinput manual. | | | |
| CF-08 | Ambang BR-68 dan BR-69 disimpan di tabel konfigurasi. | | | |

Catatan: project yang belum punya actual (belum ada bulan closing) berstatus biaya On Track. Status jadwal dihitung sejak tanggal mulai project (schedule Civil); selama periode Preparation status jadwal belum dihitung (BR-15).

### 8.2 KPI (Keputusan: **hanya untuk review**)

| ID | KPI | Definisi | Formula | Arah | Target | Bobot | Frekuensi |
|---|---|---|---|---|---|---|---|
| KPI-01 | Ketepatan waktu project | % project Closed pada periode yang selesai ≤ tanggal selesai plan | Jumlah project tepat waktu ÷ jumlah project Closed × 100% | Higher is better | 90% | 30% | Bulanan (Keputusan) |
| KPI-02 | Deviasi biaya | Selisih total actual terhadap plan cost untuk project Closed pada periode | \|Σ actual − Σ plan cost\| ÷ Σ plan cost × 100% | Lower is better | ≤ 5% | 30% | Bulanan (Keputusan) |
| KPI-03 | Kepuasan user | Rata-rata skor survei yang diisi pada periode | Rata-rata skor survei (6.6) | Higher is better | ≥ 85% | 25% | Bulanan (Keputusan) |
| KPI-04 | Lead time approval | Rata-rata hari kerja dari Submit sampai langkah management approval terakhir | Rata-rata (tanggal approval terakhir − tanggal Submit), hari kerja | Lower is better | ≤ 10 hari kerja | 15% | Bulanan (Keputusan) |

| ID | Aturan | Status |
|---|---|---|
| BR-72 | KPI ditampilkan sebagai halaman/kartu review (actual vs target, achievement %, tren bulanan), dengan filter Company, kategori, dan periode. | Keputusan |
| BR-73 | **Tidak ada** owner, input corrective/preventive action, atau alur tindak lanjut KPI di CIMS. | Keputusan |
| BR-74 | Target dan bobot disimpan di tabel per tahun (dan per Company). Achievement %: higher is better = actual ÷ target; lower is better = target ÷ actual; dibatasi maksimum 100%; untuk lower is better dengan actual = 0, achievement = 100%. | Keputusan |
| BR-75 | Penilaian gabungan berbobot (skor KPI total) ditampilkan sebagai informasi saja. | Keputusan |

---

## 9. Implementation

### 9.1 Tahap pembangunan (Keputusan)

Urutan berdasarkan ketergantungan data. Setiap tahap dikerjakan dengan Claude Code memakai template `modul-baru` (pola Customer) atau prompt khusus, dengan alur: rencana → SQL (PASS) → Service/Controller (build 0 error) → Views (build 0 error) → PASS.

| Tahap | Isi | Referensi PRD | Fase |
|---|---|---|---|
| T0 | `design-role` (otorisasi, lingkup ABRV/grup/Company, ResignDate, `DepartmentID` di CurrentUser) + tabel konfigurasi: WorkflowStep, DepartmentGroup, AppSetting, kalender kerja, ambang status | 3.8-3.10, 5, 8.1 | MVP |
| T1 | Master data: Sub-kategori, Lokasi (per Company), Vendor, Satuan, Jenis lampiran, Pertanyaan Environment Assessment, Template survei | 6.2 | MVP |
| T2 | Request (business case), Save/Submit, penomoran, lampiran, approval REQUEST (Kabag, MO), Revise/Reject/Cancel, Tugas Saya | 3.1, 6.1, 6.5, 7.1 | MVP |
| T3 | Feasibility, ubah kategori/sub-kategori (renumber), BOQ/Drawing, management approval (GM/Director) | 3.1, 3.9, BR-53, BR-54 | MVP |
| T4 | In-house/Outsource, TOR, kontrak (Purchasing), schedule & action plan berbobot, estimasi biaya bulanan, site handover, **Input project berjalan** | 3.3, 9.3 | MVP |
| T5 | Progress mingguan, upload actual cost per item (Excel + manual), status jadwal/biaya otomatis | 3.3, 4, 6.4, 8.1 | MVP |
| T6 | BAPP + approval BAPP, Project Closed, survei kepuasan | 3.4, 6.6 | MVP |
| - | **Dashboard dasar**: kartu status per kategori, tabel project, Tugas Saya, filter Company/bulan; export Excel dari setiap list | 7.1, 8.1, 9.4 | MVP |
| T7 | Emergency (warning 3 hari kerja) + Preventive manual | 3.2 | Fase 2 |
| T8 | Gantt, grafik Plan vs Actual lengkap, report lanjutan, halaman KPI review | 8.2 | Fase 2 |
| - | Jadwal Preventive berulang, halaman pengaturan workflow/konfigurasi, delegasi approval, notifikasi | - | Fase berikutnya |

### 9.2 Jadwal (Keputusan: development selesai sebelum **1 Desember 2026**, lalu UAT 2 minggu)

| Minggu | Tanggal | Target | Status |
|---|---|---|---|
| 0 | 2-4 Nov | Finalisasi PRD, `docs/PRD.md`, spesifikasi modul T0-T2 | Keputusan |
| 1 | 5-11 Nov | T0 + T1 | Keputusan |
| 2 | 12-18 Nov | T2 + T3 | Keputusan |
| 3 | 19-25 Nov | T4 + T5 + dashboard dasar | Keputusan |
| 4 | 26-30 Nov | T6, uji per tahap oleh developer, deploy ke server UAT | Keputusan |
| 5-6 | **1-14 Des** | **UAT** (Civil + developer), perbaikan, input master data dan project berjalan | Keputusan |
| - | 15 Des | Go-live production | Keputusan (turunan dari UAT 2 minggu) |

**Risiko jadwal:** ±20 hari kerja development untuk T0-T6 + dashboard tetap ketat. Mitigasi: uji per tahap oleh developer; scope MVP dikunci; perubahan kebijakan lewat tabel, bukan kode; bila tertinggal, T6 (BAPP + survei) boleh masuk selama periode UAT karena belum ada project baru yang sampai tahap closing (Keputusan).

### 9.3 Project berjalan saat go-live (Keputusan)

| ID | Aturan | Status |
|---|---|---|
| FR-03 | Fitur **Input project berjalan** khusus `civil`: project lama dicatat langsung pada status saat ini (Planning / Scheduling / In Progress) tanpa approval di CIMS. | Keputusan |
| BR-76 | Riwayat approval project berjalan ditandai "di luar sistem" (opsional: nama approver dan tanggal manual). | Keputusan |
| BR-77 | Project berjalan memakai format nomor yang sama (bulan/tahun = bulan input) dan ditandai sebagai data migrasi. | Keputusan |

### 9.4 Laporan (Keputusan)

| ID | Aturan | Status |
|---|---|---|
| FR-04 | MVP: **export Excel dari setiap list** (request, project, biaya, survei) sesuai filter aktif. | Keputusan |
| - | Laporan khusus berformat tertentu: fase 2 (format dari manajemen bila ada). | Keputusan |

### 9.5 UAT dan rollout

| ID | Aturan | Status |
|---|---|---|
| - | **Tim UAT: Civil dan developer.** Peran approver (Kabag, MO, GM, Director, FAT, Purchasing) disimulasikan dengan user uji (dev bypass `Auth:DevUsername` atau akun uji di portal). | Keputusan |
| - | Skenario UAT minimal: satu siklus penuh per kategori (CAPEX, OPEX, LVE) untuk ABL dan satu untuk NKM, departemen Mill (lewat MO), ubah kategori oleh Civil (renumber), Revise/Reject, upload actual, BAPP ditolak lalu diterima. | Keputusan |
| - | Rollout ABL dan NKM **bersamaan** saat go-live. | Keputusan |
| NFR-02 | Deploy di IIS/Windows Server internal; folder `D:\APP_DATA\CIMSAttachments` dengan hak tulis app pool; database CIMS dengan hak baca ke `home`. | Keputusan (sesuai fondasi) |

---

## 10. Business Impact

| Area | Sebelum (Current) | Sesudah (CIMS) | Ukuran |
|---|---|---|---|
| Visibilitas | Status ditanyakan manual; rekap Excel | Status request/project real-time di dashboard dan Tugas Saya | Jumlah request tercatat di CIMS = 100% request baru setelah go-live |
| Kecepatan approval | Approval manual/kertas, tanpa jejak waktu | Approval berjenjang di sistem dengan tanggal per langkah | KPI-04 lead time approval ≤ 10 hari kerja |
| Kontrol jadwal | Keterlambatan diketahui terlambat | Status jadwal otomatis mingguan (deviasi progress) | KPI-01 ketepatan waktu ≥ 90% |
| Kontrol biaya | Plan vs Actual direkap manual | Estimasi bulanan vs actual closing per item, status biaya otomatis | KPI-02 deviasi biaya ≤ 5% |
| Kualitas layanan Civil | Tidak terukur | Survei Kabag per project (skala 1-10) | KPI-03 kepuasan ≥ 85% |
| Audit dan kepatuhan | Dokumen tersebar | BOQ, Drawing, TOR, kontrak, BAPP, dan riwayat approval di satu tempat | Kelengkapan dokumen per project |
| Fleksibilitas kebijakan | Perubahan alur = perubahan kebiasaan manual | Alur approval, grup departemen, ambang status, template di tabel | Perubahan kebijakan tanpa deploy |

Baseline "Sebelum" belum dikumpulkan (Keputusan); diukur selama 3 bulan pertama setelah go-live dan dipakai sebagai pembanding KPI.

---

## Lampiran A. Asumsi yang dikonfirmasi (02-11-2026)

| Ref | Asumsi (disetujui; BR-15 direvisi) |
|---|---|
| BO-01..BO-06 | Daftar business objective |
| ST-01..ST-16 | Daftar status workflow |
| BR-02 | Log perubahan kategori (lama, baru, oleh, waktu, alasan) |
| BR-09 | Cancel hanya sebelum management approval selesai |
| BR-15 | ~~Actual start = tanggal site handover~~ → direvisi: tanggal mulai dari schedule Civil; periode Preparation (lihat BR-15) |
| BR-28 | Lingkup `adm` = ABRV + Company (sama dengan Kabag) |
| BR-38, BR-39, BR-52, BR-53 | Detail mekanisme workflow dinamis |
| BR-41, BR-77 | Urutan NNN per Company + ABRV + kategori + bulan + tahun; nomor project berjalan |
| BR-42 | ROI wajib hanya CAPEX |
| BR-44, BR-46 | Subfolder lampiran per tahun/Id; lampiran tidak dihapus fisik |
| BR-48, BR-49 | Snapshot survei; semua item wajib diisi |
| BR-64 | Kalender kerja per Company |
| BR-74, BR-75 | Perhitungan achievement % KPI dan skor gabungan |
| 3.9 | Approval susulan Emergency NKM: Kabag → Director |
| 6.1 | Section area: simpan panjang, lebar, luas |
| 8.1 | Status jadwal belum dihitung selama periode Preparation (disesuaikan dengan BR-15) |
| 9.2 | Go-live 15 Desember 2026; jadwal mingguan |
| 9.5 | Skenario UAT; rollout ABL dan NKM bersamaan |

---

## Catatan teknis dari review source

- Pola modul Customer untuk master data (MD-01..MD-04, MD-07..MD-10). Modul transaksi butuh: status workflow, ApprovalStep/ApprovalHistory, lampiran, audit `CreatedBy`/`UpdatedBy` (belum ada di Customer), lingkup data per departemen/grup.
- Department dan cost center dibaca dari `home` (cross-database, seperti `usp_Auth_GetUserByUsername`). Login database CIMS perlu hak SELECT ke `home..APP_SubDepartments` (Auth.sql saat ini hanya menyebut users, app_employees, APP_Departments).
- Penomoran request harus aman dari race condition (dua Submit bersamaan): urutan diambil dalam transaksi dengan lock pada tabel `RequestNoSequence`, bukan `MAX()+1`.
- Workflow dinamis (3.9) tetap sesuai pola: tabel + stored procedure, tanpa library workflow pihak ketiga.
- Upload actual cost via Excel butuh library baca Excel; keputusan library saat desain modul.
- `FileStorage:RealizationAttachmentsPath`: folder harus bisa ditulis identity app pool IIS di server.

## Pertanyaan terbuka

- Jumlah user per role (untuk sizing; tidak memblokir development).

## Log keputusan

Dipisah ke `docs/PRD-log.md` (riwayat keputusan per tanggal).
