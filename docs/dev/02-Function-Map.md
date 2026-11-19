# 02. Peta Fungsi: Controller → Service → Stored Procedure

Cara baca: setiap baris = satu action. **Role** = atribut di action (bila kosong, mengikuti atribut di level class). **Service.Method** = interface `I{Service}` di `Services/`. **SP** = stored procedure yang dipanggil Service (semua `dbo.`). **File SQL** = tempat SP didefinisikan di `Database/`.

Pola umum semua Service: `IDbConnectionFactory.CreateConnection()` per operasi → `DynamicParameters` (selalu menyertakan `@Username` dari `ICurrentUserService` untuk SP transaksi) → `CommandType.StoredProcedure` → terjemahkan `SqlException.Number` ke exception domain.

## 0. Infrastruktur (dipakai semua modul)

| Komponen | Class | SP / fungsi | File SQL |
|---|---|---|---|
| Koneksi DB | `IDbConnectionFactory` / `SqlConnectionFactory` (singleton) | - | `appsettings*.json` → `ConnectionStrings` |
| Login SSO | `Middleware/SessionTokenMiddleware` | - (HTTP ke `SSO:InternalApi`) | - |
| Profil user | `Filters/ProfileAttribute` → `IAuthService.GetUserByUsernameAsync` | `usp_Auth_GetUserByUsername` | `Auth.sql` |
| Role user | `IAuthService.GetUserRolesAsync` | `usp_Auth_GetUserRoles` (`home..users.Role` × `dbo.HierarchyLevel`) | `Role.sql` |
| User aktif di C# | `ICurrentUserService` / `CurrentUserService` (`CurrentUser`, `Roles`, `HighestRole`) | - | - |
| Otorisasi action | `RoleAuthorizeAttribute`, `RoleAuthorizeApiAttribute`, `AllowAllRolesAttribute`, `CimsRoles` | - | - |
| Lingkup data | (dipanggil di dalam SP) | `fn_User_AllowedDepartments`, `fn_Request_VisibleToUser` | `Scope.sql`, `Request.sql` |
| Hak per fitur | (dipanggil di dalam SP) | `fn_User_Roles`, `fn_User_OutsourceOnly`, `fn_User_CanSeeBapp`, `fn_User_CanChangeAttachment`, `fn_User_CanSeeActualCost`, `fn_User_CanSeeAddendum`, `fn_User_CanSeeSurvey`, `fn_User_CanFillSurvey` | `Request.sql`, `RequestFeasibility.sql`, `RequestActualCost.sql`, `RequestAddendum.sql`, `RequestSurvey.sql` |
| Workflow | (dipanggil di dalam SP) | `usp_Workflow_GetSteps`, `fn_User_ActionableSteps` | `Config.sql`, `RequestApproval.sql` |
| Hari kerja / setting | (dipanggil di dalam SP) | `fn_IsWorkingDay`, `fn_WorkingDaysBetween`, `usp_AppSetting_Get` | `Config.sql` |
| Export Excel | `Services/ExcelExport` (static) | - | - |
| Notifikasi UI | `Views/Shared/_Notifications.cshtml`, `wwwroot/js/notify.js` | - | - |

## 1. Request: list, form, submit (T1, T2)

Controller: `RequestController` (class: semua role CIMS, data dibatasi SP).

| Action | HTTP | Role | Service.Method | SP | File SQL | JS |
|---|---|---|---|---|---|---|
| `Index` | GET | class | `IRequestService.GetPagedAsync`, `IRequestLookupService.GetDepartmentsForUserAsync` | `usp_Request_GetPaged`, `usp_Lookup_DepartmentsForUser` | `Request.sql`, `RequestMigration.sql` | `request-list.js` |
| `Export` | GET | class | `IRequestService.GetPagedAsync` + `ExcelExport` | `usp_Request_GetPaged` | `Request.sql` | - |
| `Details` | GET | class | lihat tabel 1a | banyak | - | `request-approval.js`, `request-charts.js`, `request-gantt.js` |
| `Create` | GET | adm, plan, spv | `IRequestLookupService.GetDepartmentsForUserAsync`, `GetCostCentersAsync`, `GetActiveEmployeesAsync`, `GetLocationsAsync`, `GetAssessmentQuestionsAsync`, `ISubCategoryService.GetActiveByCategoryAsync` | `usp_Lookup_*`, `usp_SubCategory_GetActiveByCategory` | `Request.sql`, `SubCategory.sql` | `request-form.js` |
| `Create` | POST | adm, plan, spv | `IRequestService.SaveDraftAsync` | `usp_Request_SaveDraft` | `Request.sql` | `request-form.js` |
| `Edit` | GET | adm, plan, spv | `IRequestService.GetByIdAsync`, `GetAssessmentAsync` + lookup | `usp_Request_GetById`, `usp_Request_GetAssessment` | `Request.sql` | `request-form.js` |
| `Edit` | POST | adm, plan, spv | `IRequestService.SaveDraftAsync` | `usp_Request_SaveDraft` | `Request.sql` | - |
| `Submit` | POST | adm, plan, spv | `IRequestService.SubmitAsync` | `usp_Request_Submit` (nomor + snapshot REQUEST) | `RequestSubmit.sql` | - |
| `Cancel` | POST | adm, plan, spv | `IRequestService.CancelAsync` | `usp_Request_Cancel` | `RequestSubmit.sql` | - |
| `UploadAttachment` | POST | adm, plan, spv, civil, purchasing | `IRequestAttachmentService.UploadAsync` | `usp_RequestAttachment_Insert` | `Request.sql` | - |
| `DeactivateAttachment` | POST | adm, plan, spv, civil, purchasing | `IRequestAttachmentService.DeactivateAsync` | `usp_RequestAttachment_Deactivate` | `Request.sql` | - |
| `DownloadAttachment` | GET | class | `IRequestAttachmentService.GetForDownloadAsync` | `usp_RequestAttachment_GetById` | `Request.sql` | - |

Stage lampiran per status: `RequestAttachmentService.StageForStatus` (DRAFT/RETURNED/FEASIBILITY → `REQUEST`, DOC_PREPARATION → `DOCUMENT`, PLANNING → `PROCUREMENT`, PROCUREMENT → `CONTRACT`, IN_PROGRESS → `BAPP`); jenis lampiran per stage dari `usp_Lookup_AttachmentTypesByStage`.

### 1a. `RequestController.Details` (halaman detail, read-only)

| Bagian halaman | Service.Method | SP | File SQL |
|---|---|---|---|
| Header request | `IRequestService.GetByIdAsync` | `usp_Request_GetById` | `Request.sql` |
| Tandai tugas REJECTED dibaca | `IUserTaskService.MarkReadAsync` | `usp_Task_MarkRead` | `Task.sql` |
| Langkah approval + riwayat | `GetApprovalStepsAsync`, `GetHistoryAsync` | `usp_Request_GetApprovalSteps`, `usp_Request_GetHistory` | `RequestSubmit.sql` |
| Tombol Approve/Revise/Reject | `GetActionableStepAsync` | `usp_Request_GetActionableStep` | `RequestApproval.sql` |
| Assessment | `GetAssessmentAsync` | `usp_Request_GetAssessment` | `Request.sql` |
| Lampiran | `IRequestAttachmentService.ListAsync`, `IRequestLookupService.GetAttachmentTypesByStageAsync` | `usp_RequestAttachment_ListByRequest`, `usp_Lookup_AttachmentTypesByStage` | `Request.sql` |
| Perubahan kategori | `GetCategoryChangesAsync` | `usp_Request_GetCategoryChanges` | `RequestFeasibility.sql` |
| Kontrak + vendor | `GetContractAsync`, `IVendorService.GetActiveAsync` | `usp_Request_GetContract`, `usp_Vendor_GetActive` | `RequestExecution.sql`, `Vendor.sql` |
| Schedule / action plan | `GetScheduleAsync` | `usp_Request_GetSchedule` | `RequestSchedule.sql` |
| Progress + kurva S | `GetProgressAsync`, `GetProgressWeekAsync`, `GetProgressCurveAsync` | `usp_Request_GetProgress`, `usp_Request_GetProgressWeek`, `usp_Request_GetProgressCurve` | `RequestProgress.sql`, `DashboardChart.sql` |
| Actual cost | `GetActualCostAsync`, `GetActualMonthAsync`, `IActualFileService.ListAsync`, `IUnitService.GetActiveAsync` | `usp_Request_GetActualCost`, `usp_Request_GetActualMonth`, `usp_ActualFile_List`, `usp_Unit_GetActive` | `RequestActualCost.sql`, `Unit.sql` |
| Addendum | `IAddendumService.GetByRequestAsync`, `GetFileTypeAsync`, `GetFinalFileTypeAsync` | `usp_Addendum_GetByRequest`, `usp_Lookup_AttachmentTypesByStage` | `RequestAddendum.sql` |
| BAPP | `IBappService.GetByRequestAsync` | `usp_Bapp_GetByRequest` | `RequestBapp.sql` |
| Survei | `ISurveyService.GetByRequestAsync` | `usp_Survey_Get` | `RequestSurvey.sql` |

## 2. Approval, Feasibility, Document Preparation (T2, T3)

| Action | Role | Service.Method | SP | File SQL |
|---|---|---|---|---|
| `ApprovalAct` (titik REQUEST & MGMT) | kabag, mo, gm, director | `IRequestService.ApprovalActAsync` | `usp_Request_ApprovalAct` (+ `fn_User_ActionableSteps`) | `RequestApproval.sql` |
| `ChangeCategory` | civil | `ChangeCategoryAsync` | `usp_Request_ChangeCategory` | `RequestFeasibility.sql` |
| `FeasibilityDecide` | civil | `FeasibilityDecideAsync` | `usp_Request_FeasibilityDecide` | `RequestFeasibility.sql` |
| `SetBoqTotal` | civil | `SetBoqTotalAsync` | `usp_Request_SetBoqTotal` | `RequestDocPrep.sql` |
| `SendToManagement` | civil | `SendToManagementAsync` | `usp_Request_SendToManagement` (snapshot MGMT, BR-53) | `RequestDocPrep.sql` |

## 3. Execution: procurement, schedule, progress (T4)

| Action | Role | Service.Method | SP | File SQL | JS |
|---|---|---|---|---|---|
| `ChooseExecution` | civil | `ChooseExecutionAsync` | `usp_Request_ChooseExecution` | `RequestExecution.sql` | - |
| `SaveContract` | purchasing | `SaveContractAsync` | `usp_Request_SaveContract` | `RequestExecution.sql` | - |
| `CompleteProcurement` | purchasing | `CompleteProcurementAsync` | `usp_Request_CompleteProcurement` | `RequestExecution.sql` | - |
| `ReturnTor` | purchasing | `ReturnTorAsync` | `usp_Request_ReturnTor` | `RequestExecution.sql` | - |
| `SaveSchedule` | civil | `SaveScheduleAsync` | `usp_Request_SaveSchedule` (IN_PROGRESS → `usp_Request_RefreshScheduleSummary`) | `RequestSchedule.sql`, `RequestProgress.sql` | `request-schedule.js` |
| `SaveCostEstimate` | civil | `SaveCostEstimateAsync` | `usp_Request_SaveCostEstimate` (→ `usp_Request_RefreshCostStatus`) | `RequestSchedule.sql` | `request-schedule.js` |
| `SiteHandover` | civil | `SiteHandoverAsync` | `usp_Request_SiteHandover` | `RequestSchedule.sql` | - |
| `SaveProgress` | civil | `SaveProgressAsync` | `usp_Request_SaveProgress` (+ `fn_WeekStart`, `fn_Request_PlanProgress`) | `RequestProgress.sql` | `request-progress.js` |
| `CreateRunning` GET | civil | lookup (`IRequestLookupService.*`, `IVendorService.GetActiveAsync`) | `usp_Lookup_*`, `usp_Vendor_GetActive` | `Request.sql`, `RequestMigration.sql` | `running-project.js` |
| `CreateRunning` POST | civil | `CreateRunningAsync` | `usp_Request_CreateRunning` | `RequestMigration.sql` | `running-project.js` |
| `RunningLookups` (AJAX JSON) | civil (`RoleAuthorizeApi`) | `GetDepartmentsForUserAsync`, `GetCostCentersAsync`, `GetActiveEmployeesAsync`, `GetLocationsAsync` | `usp_Lookup_DepartmentsForUser`, `usp_Lookup_CostCenters`, `usp_Lookup_ActiveEmployees`, `usp_Lookup_Locations` | `RequestMigration.sql`, `Request.sql` | `running-project.js` |

## 4. Addendum (T4-4)

Service: `IAddendumService` / `AddendumService` (stage lampiran `ADDENDUM`, kode `ADDENDUM`, `ADDENDUM_FINAL`, `BOQ_REVISION`).

| Action | Role | Service.Method | SP | File SQL |
|---|---|---|---|---|
| `CreateAddendum` | civil | `CreateAsync` | `usp_Addendum_Create` (snapshot ADDENDUM bila nilai naik) | `RequestAddendum.sql` |
| `AddendumApprovalAct` | kabag, mo, gm, director | `ApprovalActAsync` | `usp_Addendum_ApprovalAct` | `RequestAddendum.sql` |
| `UploadAddendumContract` | civil | `UploadFinalContractAsync` | `usp_Addendum_UploadFinalContract` | `RequestAddendum.sql` |
| `SaveAddendumAdjustment` | civil | `SaveAdjustmentAsync` | `usp_Addendum_SaveAdjustment` | `RequestAddendum.sql` |
| `DownloadAddendum` | class | `GetForDownloadAsync` | `usp_Addendum_GetFile` | `RequestAddendum.sql` |

## 5. Actual cost (T5)

### 5a. Input manual per project (`RequestController`, service `IActualFileService`)

| Action | Role | Service.Method | SP | File SQL | JS |
|---|---|---|---|---|---|
| `SaveActualCost` | civil | `IActualFileService.SaveMonthAsync` → `IRequestService.SaveActualMonthAsync` (file disimpan ke disk, metadata dikirim sebagai `@FilesJson`) | `usp_Request_SaveActualMonth` (→ `usp_Request_RefreshCostStatus`) | `RequestActualCost.sql` | `request-actual.js` |
| `UploadActualFile` | civil | `AddAsync` | `usp_ActualFile_Insert` | `RequestActualCost.sql` | - |
| `RemoveActualFile` | civil | `RemoveAsync` | `usp_ActualFile_Deactivate` | `RequestActualCost.sql` | - |
| `DownloadActualFile` | class | `GetForDownloadAsync` | `usp_ActualFile_GetById` | `RequestActualCost.sql` | - |

### 5b. Upload Excel pusat (`ActualCostUploadController`, service `IActualCostUploadService`)

Class: civil, fat, dgo, gm, director, administrator.

| Action | Role | Service.Method | SP | File SQL | JS |
|---|---|---|---|---|---|
| `Index` | class | `GetPagedAsync`, `GetFileRulesAsync` | `usp_ActualUpload_GetPaged`, `usp_Lookup_AttachmentTypesByStage` (COST) | `RequestActualUpload.sql` | `actual-upload.js` |
| `Template` | civil | `BuildTemplate` (ClosedXML, tanpa DB) | - | - | - |
| `Upload` | civil | `PreviewAsync` | `usp_ActualUpload_Validate` (→ `usp_ActualUpload_CheckRows`), `usp_ActualUpload_Create` | `RequestActualUpload.sql` | `actual-upload.js` |
| `Preview` | civil | `GetPendingPreviewAsync` (baca ulang file arsip) | `usp_ActualUpload_GetById`, `usp_ActualUpload_Validate` | `RequestActualUpload.sql` | - |
| `Confirm` | civil | `ImportAsync` | `usp_ActualUpload_Import` | `RequestActualUpload.sql` | - |
| `Cancel` | civil | `CancelAsync` | `usp_ActualUpload_Cancel` | `RequestActualUpload.sql` | - |
| `Download` | class | `GetForDownloadAsync` | `usp_ActualUpload_GetById` | `RequestActualUpload.sql` | - |

## 6. Closing: BAPP dan survei (T6)

| Action | Controller | Role | Service.Method | SP | File SQL | JS |
|---|---|---|---|---|---|---|
| `IssueBapp` | Request | civil | `IBappService.IssueAsync` | `usp_Bapp_Issue` (nomor BAPP + snapshot BAPP) | `RequestBapp.sql` | - |
| `BappApprovalAct` | Request | kabag, fat, dgo, gm, director | `IBappService.ApprovalActAsync` | `usp_Bapp_ApprovalAct` | `RequestBapp.sql` | - |
| `PrintBapp` | Request | civil | `IBappService.GetPrintDataAsync` | `usp_Bapp_GetPrintData` | `RequestBapp.sql` | `bapp-print.js` |
| `SendSurvey` | Request | civil | `ISurveyService.SendAsync` | `usp_Survey_Send` | `RequestSurvey.sql` | - |
| `SubmitSurvey` | Request | kabag | `ISurveyService.SubmitAsync` | `usp_Survey_Submit` | `RequestSurvey.sql` | - |
| `Index` / `Export` | Survey | kabag, mo, civil, gm, director, administrator | `ISurveyService.GetPagedAsync` | `usp_Survey_GetPaged` | `RequestSurvey.sql` | - |

## 7. Dashboard, Tugas Saya, Home

| Action | Controller | Role | Service.Method | SP | File SQL | JS |
|---|---|---|---|---|---|---|
| `Index` | Home | `AllowAllRoles` | `IUserTaskService.GetSummaryAsync` | `usp_Task_GetSummary` | `Task.sql` | - |
| `LogOut` | Home | (POST, antiforgery) | - | - | - | - |
| `Index` | MyTask | `AllowAllRoles` | `IUserTaskService.GetSummaryAsync`, `GetListAsync` | `usp_Task_GetSummary`, `usp_Task_GetList` (→ `fn_User_Tasks`) | `Task.sql` | - |
| `Index` | Dashboard | semua role CIMS | `IDashboardService.GetProjectsAsync`, `GetSummaryAsync`, `GetMonthlyCostAsync`, `IUserTaskService.GetSummaryAsync` | `usp_Dashboard_GetProjects`, `usp_Dashboard_GetSummary`, `usp_Dashboard_GetMonthlyCost`, `usp_Task_GetSummary` | `Dashboard.sql`, `DashboardChart.sql`, `Task.sql` | `dashboard-charts.js`, `cims-charts.js` |
| `Export` | Dashboard | semua role CIMS | `IDashboardService.GetProjectsAsync` + `ExcelExport` | `usp_Dashboard_GetProjects` | `Dashboard.sql` | - |

## 8. Master data dan Settings

Semua controller master data memakai pola Customer: `Index` (GetPaged) · `Details` / `Edit` GET (GetById) · `Create` POST (Insert) · `Edit` POST (Update) · `SetActive` POST (SetActive). Role class: `administrator`, `civil` (Vendor + `purchasing`).

| Controller | Service | SP (GetPaged / GetById / Insert / Update / SetActive + ekstra) | File SQL | Kode error (duplikat / validasi / not found) |
|---|---|---|---|---|
| `CustomerController` | `ICustomerService` | `usp_Customer_*` | `Customer.sql` | 50001 / 50002 / 50003 |
| `LocationController` | `ILocationService` | `usp_Location_*` | `Location.sql` | 50011 / 50012 / 50013 |
| `AttachmentTypeController` | `IAttachmentTypeService` | `usp_AttachmentType_*` (+ `fn_AttachmentType_NormalizeExt`) | `AttachmentType.sql` | 50021 / 50022 / 50023 |
| `AssessmentQuestionController` | `IAssessmentQuestionService` | `usp_AssessmentQuestion_*` | `AssessmentQuestion.sql` | 50031 / 50032 / 50033 |
| `SurveyTemplateItemController` | `ISurveyTemplateItemService` | `usp_SurveyTemplateItem_*` | `SurveyTemplateItem.sql` | 50041 / 50042 / 50043 |
| `SubCategoryController` | `ISubCategoryService` | `usp_SubCategory_*` + `usp_SubCategory_GetActiveByCategory` | `SubCategory.sql` | 50061 (+50064 nama) / 50062 / 50063 |
| `VendorController` | `IVendorService` | `usp_Vendor_*` + `usp_Vendor_GetActive` | `Vendor.sql` | 50081 (+50084 ERP no) / 50082 / 50083 |
| `UnitController` | `IUnitService` | `usp_Unit_*` + `usp_Unit_GetActive` | `Unit.sql` | 50091 / 50092 / 50093 |
| `AppSettingController` (`administrator`) | `IAppSettingService` | `usp_AppSetting_List`, `usp_AppSetting_GetByKey`, `usp_AppSetting_UpdateValue` | `AppSetting.sql` | - / 50052 / 50053 |

## 9. Kode error SP modul Request (semua SP transaksi)

Diterjemahkan oleh `RequestService.Translate` (dipakai juga oleh `RequestAttachmentService`, `ActualCostUploadService`, `ActualFileService`, `AddendumService`, `BappService`, `SurveyService`):

| `THROW` | Exception (`Services/RequestExceptions.cs`) | Arti | Respons Controller |
|---|---|---|---|
| 50072 | `RequestValidationException` | Input wajib kosong / tidak valid / syarat belum lengkap | `TempData["Error"]` / ModelState |
| 50073 | `RequestNotFoundException` | Data tidak ada **atau di luar lingkup user** | `NotFound()` / `TempData["Error"]` |
| 50074 | `RequestInvalidStateException` | Status tidak mengizinkan aksi (termasuk sudah diproses approver lain) | `TempData["Error"]` + redirect Details |
| 50075 | `RequestNotAuthorizedException` | Role / lingkup / Company tidak sesuai, atau request milik sendiri | `TempData["Error"]` |
| lain | (dilempar ulang, `LogError`) | Bug SP / constraint / koneksi | `Home/Error` |
