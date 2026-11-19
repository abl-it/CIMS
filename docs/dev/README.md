# Dokumentasi Developer CIMS

Dokumen teknis untuk developer CIMS (ASP.NET Core 8 MVC + Dapper + SQL Server). Sumber kebenaran bisnis tetap `docs/PRD.md`; aturan coding tetap `CLAUDE.md`. Dokumen di folder ini menjelaskan **bagaimana kode memenuhi PRD**.

| File | Isi |
|---|---|
| [01-Flow-Diagram.md](01-Flow-Diagram.md) | Arsitektur, alur HTTP request (SSO → filter → controller → service → SP), state machine status request, alur approval, urutan script SQL |
| [02-Function-Map.md](02-Function-Map.md) | Peta per fungsi: action Controller → role → method Service → stored procedure → file SQL |
| [03-Troubleshooting.md](03-Troubleshooting.md) | Best practice troubleshooting: langkah diagnosis, kode error SP, gejala umum dan penyebabnya, query diagnosis |
| [04-Workflow-Change.md](04-Workflow-Change.md) | Alur workflow approval dan best practice bila workflow berubah (tambah/hapus/ubah langkah, role baru, titik baru) |

| [CIMS-Developer-Flow.drawio](CIMS-Developer-Flow.drawio) | Versi **draw.io** (6 halaman): Arsitektur, Status Request, Workflow Approval, Alur Fitur per Fase, Troubleshooting, Perubahan Workflow. Buka dengan draw.io desktop, app.diagrams.net, atau ekstensi VS Code "Draw.io Integration" |
| [CIMS-Module-Flow.drawio](CIMS-Module-Flow.drawio) | Alur per modul (**draw.io**, 14 halaman, swimlane per aktor): Request & Submit, Approval, Feasibility & Doc Prep, Execution & Procurement, Schedule & Site Handover, Progress Mingguan, Actual Cost (Manual), Actual Cost Upload (Excel), Addendum, BAPP & Closing, Survey, Running Project, Lampiran, Tugas Saya |

Buku panduan developer (format sama dengan buku panduan role): [`docs/CIMS-User-Guide-Developer.docx`](../CIMS-User-Guide-Developer.docx) / [`.pdf`](../CIMS-User-Guide-Developer.pdf) — setup lingkungan, konfigurasi, struktur project, konvensi kode, membuat modul baru (pola Customer, tahap A/B/C + PASS), workflow approval, troubleshooting, build/Git/deployment IIS, dan referensi cepat.

Alur sistem untuk management (GM / Director): [`docs/CIMS-Management-Flow.drawio`](../CIMS-Management-Flow.drawio) (7 halaman: Gambaran Umum, Titik Keputusan, Management Approval, Addendum, BAPP & Closing, Monitoring, Status & KPI) dan buku panduan [`docs/CIMS-User-Guide-Management.docx`](../CIMS-User-Guide-Management.docx) / [`.pdf`](../CIMS-User-Guide-Management.pdf).

Diagram di file `.md` memakai **Mermaid** (tampil langsung di GitHub, Azure DevOps, VS Code dengan ekstensi Markdown Preview Mermaid).

Pembaruan: dokumen ini dibuat dari source per 19-11-2026. Bila menambah action/SP baru, perbarui `02-Function-Map.md` di commit yang sama.
