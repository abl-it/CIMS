# 01. Flow Diagram untuk Developer

## 1. Arsitektur lapisan

Pola: **Controller → Service (Dapper) → Stored Procedure**. Tidak ada layer Repository, tidak ada Entity Framework.

```mermaid
flowchart LR
    B[Browser<br/>Razor view + JS fetch] -->|HTTP| MW[SessionTokenMiddleware<br/>SSO token / session]
    MW --> PF[ProfileAttribute<br/>filter global: CurrentUser + Roles]
    PF --> RA[RoleAuthorize / RoleAuthorizeApi<br/>/ AllowAllRoles]
    RA --> C[Controller<br/>validasi input, PRG, TempData]
    C --> S[Service<br/>business logic + Dapper]
    S -->|IDbConnectionFactory<br/>DynamicParameters| SP[(Stored Procedure<br/>dbo.usp_*)]
    SP --> T[(Tabel CIMS<br/>+ home..users / app_employees / APP_Departments)]
    S -->|IFormFile| FS[[File storage<br/>FileStorage:* di appsettings]]
    SP -. THROW 5xxxx .-> S
    S -. exception domain .-> C
    C -. ModelState / TempData Error / NotFound .-> B
```

| Lapisan | Folder | Tanggung jawab | Dilarang |
|---|---|---|---|
| Middleware | `Middleware/` | Tukar `?token=` ke JWT, simpan `Username` di Session, redirect ke login | Logging token/sessionId |
| Filter | `Filters/` | `ProfileAttribute` memuat `CurrentUser` + `Roles` sekali per request; default deny; `RoleAuthorize*` per action | String role literal (pakai `CimsRoles`) |
| Controller | `Controllers/` | Routing, validasi `ModelState`, mapping exception → UI, PRG | Akses Dapper/DB langsung, business logic |
| Service | `Services/` | Panggil SP lewat Dapper, terjemahkan `SqlException.Number` → exception domain, simpan file | Repository, SQL string concat |
| SP / fungsi | `Database/*.sql` | Aturan bisnis (status, lingkup data, workflow, validasi) | Dijalankan Claude ke production |

## 2. Alur satu HTTP request (urutan pipeline)

```mermaid
sequenceDiagram
    autonumber
    participant U as Browser
    participant M as SessionTokenMiddleware
    participant P as ProfileAttribute
    participant R as RoleAuthorize
    participant C as Controller
    participant S as Service
    participant D as SQL Server

    U->>M: GET /Request/Details/5 (cookie .CIMS.Session)
    alt ada ?token=
        M->>M: tukar sessionId -> JWT ({SSO:InternalApi}/home/api/token), validasi HS256
        M-->>U: 302 ke URL tanpa ?token=
    else tanpa sesi
        M-->>U: 302 SSO:PublicLogin (AJAX: 401 JSON)
    end
    M->>P: Session["Username"] ada
    P->>D: usp_Auth_GetUserByUsername, usp_Auth_GetUserRoles
    alt user tidak terdaftar / tanpa role CIMS
        P-->>U: Home/NotAuthorized (AJAX: 403 JSON)
    end
    P->>R: CurrentUser.Roles
    R->>R: any-of role cocok?
    R->>C: lolos
    C->>S: GetByIdAsync(id)
    S->>D: EXEC dbo.usp_Request_GetById @Id, @Username
    D-->>S: baris (0 baris = di luar lingkup fn_User_AllowedDepartments)
    S-->>C: model / null
    C-->>U: View / NotFound
```

Urutan di `Program.cs`: `UseStaticFiles` → `UseRequestLocalization` → `UseRouting` → `UseSession` → `SessionTokenMiddleware` → `UseAuthorization`.

## 3. Alur POST (pola PRG + terjemahan error)

```mermaid
flowchart TD
    A[POST + antiforgery token] --> B{ModelState valid?}
    B -- tidak --> V[return View model<br/>error inline asp-validation-for]
    B -- ya --> S[Service.XxxAsync]
    S --> SP[(usp_*)]
    SP -- sukses --> OK[TempData Success<br/>LocalRedirect returnUrl / Details]
    SP -- THROW 5xxx1/50072 validasi --> E1[ModelState.AddModelError<br/>atau TempData Error]
    SP -- THROW 5xxx3/50073 not found --> E2[GET: NotFound<br/>POST: TempData Error + redirect Index]
    SP -- THROW 50074 status --> E3[TempData Error + redirect Details]
    SP -- THROW 50075 tidak berhak --> E4[TempData Error + redirect Details]
    SP -- SqlException lain --> E5[LogError + throw<br/>-> Home/Error]
    OK --> T[_Notifications: toast hijau]
    E1 & E2 & E3 & E4 --> W[_Notifications: SweetAlert2 error]
```

## 4. State machine status request (PRD 3.6)

Kode status di `Models/ProjectRequest.cs` (`RequestStatus`). Status hanya diubah oleh SP, bukan oleh C#.

```mermaid
stateDiagram-v2
    [*] --> DRAFT: usp_Request_SaveDraft (adm/plan/spv)
    DRAFT --> WAITING_APPROVAL: usp_Request_Submit (snapshot REQUEST)
    RETURNED --> WAITING_APPROVAL: usp_Request_Submit (ronde baru)
    DRAFT --> CANCELLED: usp_Request_Cancel
    RETURNED --> CANCELLED: usp_Request_Cancel
    WAITING_APPROVAL --> CANCELLED: Cancel (juga dari FEASIBILITY,<br/>DOC_PREPARATION, MGMT_APPROVAL; BR-09)

    WAITING_APPROVAL --> WAITING_APPROVAL: APPROVE, ada langkah berikut
    WAITING_APPROVAL --> FEASIBILITY: APPROVE langkah terakhir
    WAITING_APPROVAL --> RETURNED: REVISE (ReviseTo=REQUESTER)
    WAITING_APPROVAL --> REJECTED: REJECT

    FEASIBILITY --> DOC_PREPARATION: usp_Request_FeasibilityDecide YES
    FEASIBILITY --> RETURNED: FeasibilityDecide REVISE
    FEASIBILITY --> REJECTED: FeasibilityDecide REJECT

    DOC_PREPARATION --> MGMT_APPROVAL: usp_Request_SendToManagement (snapshot MGMT)
    MGMT_APPROVAL --> PLANNING: APPROVE langkah terakhir
    MGMT_APPROVAL --> FEASIBILITY: REVISE (ReviseTo=CIVIL)
    MGMT_APPROVAL --> REJECTED: REJECT

    PLANNING --> SCHEDULING: usp_Request_ChooseExecution INHOUSE
    PLANNING --> PROCUREMENT: ChooseExecution OUTSOURCE (TOR)
    PROCUREMENT --> PLANNING: usp_Request_ReturnTor
    PROCUREMENT --> SCHEDULING: usp_Request_CompleteProcurement

    SCHEDULING --> IN_PROGRESS: usp_Request_SiteHandover
    IN_PROGRESS --> BAPP_REVIEW: usp_Bapp_Issue (snapshot BAPP)
    BAPP_REVIEW --> IN_PROGRESS: usp_Bapp_ApprovalAct No
    BAPP_REVIEW --> CLOSED: Accept langkah terakhir
    CLOSED --> SURVEY_COMPLETED: usp_Survey_Submit

    REJECTED --> [*]
    CANCELLED --> [*]
    SURVEY_COMPLETED --> [*]
```

Catatan:
- **Running project / emergency** (`usp_Request_CreateRunning`, `RequestMigration.sql`) langsung masuk `PLANNING` atau `SCHEDULING` (`@TargetStatus`), tanpa langkah approval REQUEST/MGMT. `usp_Request_Submit` hanya menerima `DRAFT`/`RETURNED`; `usp_Request_Cancel` menerima `DRAFT` s.d. `MGMT_APPROVAL`.
- **Addendum** (titik `ADDENDUM`) berjalan **tanpa mengubah status request**; request tetap `SCHEDULING`/`IN_PROGRESS`, status addendum ada di `dbo.ProjectAddendum`.

## 5. Alur approval (workflow dinamis, PRD 3.9)

Empat titik approval. Langkah dibaca dari `dbo.WorkflowStep` dan **di-snapshot** ke `dbo.ApprovalStep` saat titik dimulai (BR-37). Aksi approver selalu membaca snapshot, bukan tabel workflow.

```mermaid
flowchart LR
    subgraph CFG[Konfigurasi - Config.sql]
        WS[(dbo.WorkflowStep<br/>CoCode, Point, StepOrder, RoleCode,<br/>Scope, Category, DepartmentGroupCode,<br/>ReviseTo, AllowReject, IsActive)]
        DG[(DepartmentGroup +<br/>DepartmentGroupMember)]
    end
    subgraph SNAP[Snapshot - BR-37]
        AS[(dbo.ApprovalStep<br/>RequestId, Point, Round, StepOrder,<br/>Status PENDING/APPROVED/.../VOID, StartedAt)]
        AH[(dbo.ApprovalHistory)]
    end
    WS -->|usp_Request_Submit: REQUEST| AS
    WS -->|usp_Request_SendToManagement: MGMT| AS
    WS -->|usp_Bapp_Issue: BAPP| AS
    WS -->|usp_Addendum_Create: ADDENDUM bila nilai naik| AS
    DG --> WS
    AS --> F{{fn_User_ActionableSteps<br/>role + lingkup + Company + bukan requester}}
    F --> GA[usp_Request_GetActionableStep<br/>tombol di Details]
    F --> TK[fn_User_Tasks / usp_Task_*<br/>Tugas Saya]
    GA --> ACT[usp_Request_ApprovalAct<br/>usp_Bapp_ApprovalAct<br/>usp_Addendum_ApprovalAct]
    ACT --> AS
    ACT --> AH
```

```mermaid
sequenceDiagram
    autonumber
    participant Req as Requester (adm)
    participant SP as usp_Request_Submit
    participant Kb as Kabag
    participant Mo as MO (grup MILL)
    participant Act as usp_Request_ApprovalAct

    Req->>SP: Submit
    SP->>SP: ambil WorkflowStep (CoCode, 'REQUEST', Category, grup dept), skip yg kondisinya tidak cocok (BR-52)
    SP->>SP: INSERT ApprovalStep ronde N; langkah 1 StartedAt = now; status WAITING_APPROVAL
    Kb->>Act: APPROVE (StepId yang dilihat)
    Act->>Act: UPDLOCK request; cek step masih PENDING (50074) dan user berhak (50075)
    Act->>Act: langkah 1 APPROVED, langkah 2 StartedAt = now
    Mo->>Act: APPROVE
    Act->>Act: tidak ada langkah berikut -> FEASIBILITY
    Note over Act: REVISE: VOID sisa langkah, status sesuai ReviseTo<br/>REJECT: hanya bila AllowReject = 1, VOID sisa langkah
```

## 6. Alur fitur utama per fase

```mermaid
flowchart TD
    subgraph A[Fase A: Request - T1..T3]
        A1[Create/Edit draft<br/>RequestController.Create/Edit] --> A2[Upload lampiran REQUEST<br/>UploadAttachment]
        A2 --> A3[Submit] --> A4[Approval REQUEST<br/>ApprovalAct]
        A4 --> A5[Feasibility Civil<br/>ChangeCategory / FeasibilityDecide]
        A5 --> A6[Doc Prep: BOQ + Drawing<br/>SetBoqTotal + UploadAttachment DOCUMENT]
        A6 --> A7[SendToManagement] --> A8[Approval MGMT<br/>ApprovalAct]
    end
    subgraph B[Fase B: Execution - T4..T5]
        B1[ChooseExecution] --> B2{Outsource?}
        B2 -- ya --> B3[Purchasing: SaveContract<br/>CompleteProcurement / ReturnTor]
        B2 -- tidak --> B4
        B3 --> B4[SaveSchedule + SaveCostEstimate]
        B4 --> B5[SiteHandover] --> B6[SaveProgress mingguan]
        B6 --> B7[Actual cost: SaveActualCost manual<br/>atau ActualCostUpload Excel]
        B6 --> B8[Addendum: Create → Approval → Final contract → Adjustment]
    end
    subgraph C[Fase C: Closing - T6]
        C1[IssueBapp] --> C2[BappApprovalAct<br/>kabag → fat → dgo → gm]
        C2 --> C3[PrintBapp] --> C4[SendSurvey] --> C5[SubmitSurvey Kabag]
    end
    A8 --> B1
    B6 --> C1
```

## 7. Urutan menjalankan script SQL (DB dev/test)

Semua script idempotent (`CREATE OR ALTER`, `IF OBJECT_ID ... IS NULL`, seed `MERGE` hanya menambah). Urutan dari header "Jalankan SETELAH" di masing-masing file:

```mermaid
flowchart LR
    R[Role.sql] --> AU[Auth.sql] --> CF[Config.sql] --> APS[AppSetting.sql] --> SC[Scope.sql]
    SC --> MD[Master: Customer, Location,<br/>AttachmentType, AssessmentQuestion,<br/>SurveyTemplateItem, SubCategory, Unit, Vendor]
    MD --> RQ[Request.sql] --> RS[RequestSubmit.sql] --> RAp[RequestApproval.sql] --> TK[Task.sql]
    TK --> RF[RequestFeasibility.sql] --> RD[RequestDocPrep.sql] --> RE[RequestExecution.sql]
    RE --> RSc[RequestSchedule.sql] --> RP[RequestProgress.sql] --> RAC[RequestActualCost.sql]
    RAC --> RAU[RequestActualUpload.sql] --> RM[RequestMigration.sql] --> RAd[RequestAddendum.sql]
    RAd --> RB[RequestBapp.sql] --> RSv[RequestSurvey.sql] --> DB1[Dashboard.sql] --> DB2[DashboardChart.sql]
```

Bila sebuah file menyebut "dijalankan ulang" (mis. `RequestActualCost.sql` meminta `RequestSchedule.sql` dijalankan ulang), ikuti catatan di header file tersebut. File berisi karakter non-ASCII wajib **UTF-8 dengan BOM** (lihat `FixTextEncoding.sql` bila teks sudah rusak).
