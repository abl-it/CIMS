# Dokumentasi Developer CIMS

Dokumen teknis untuk developer CIMS (ASP.NET Core 8 MVC + Dapper + SQL Server). Sumber kebenaran bisnis tetap `docs/PRD.md`; aturan coding tetap `CLAUDE.md`. Dokumen di folder ini menjelaskan **bagaimana kode memenuhi PRD**.

| File | Isi |
|---|---|
| [01-Flow-Diagram.md](01-Flow-Diagram.md) | Arsitektur, alur HTTP request (SSO → filter → controller → service → SP), state machine status request, alur approval, urutan script SQL |
| [02-Function-Map.md](02-Function-Map.md) | Peta per fungsi: action Controller → role → method Service → stored procedure → file SQL |
| [03-Troubleshooting.md](03-Troubleshooting.md) | Best practice troubleshooting: langkah diagnosis, kode error SP, gejala umum dan penyebabnya, query diagnosis |
| [04-Workflow-Change.md](04-Workflow-Change.md) | Alur workflow approval dan best practice bila workflow berubah (tambah/hapus/ubah langkah, role baru, titik baru) |

| [CIMS-Developer-Flow.drawio](CIMS-Developer-Flow.drawio) | Versi **draw.io** (6 halaman): Arsitektur, Status Request, Workflow Approval, Alur Fitur per Fase, Troubleshooting, Perubahan Workflow. Buka dengan draw.io desktop, app.diagrams.net, atau ekstensi VS Code "Draw.io Integration" |

Diagram di file `.md` memakai **Mermaid** (tampil langsung di GitHub, Azure DevOps, VS Code dengan ekstensi Markdown Preview Mermaid).

Pembaruan: dokumen ini dibuat dari source per 19-11-2026. Bila menambah action/SP baru, perbarui `02-Function-Map.md` di commit yang sama.
