using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>
    /// Request / business case (T2-1: Draft). Matriks PRD 5.2:
    ///   lihat  = adm, plan, spv, emp, kabag, mo, civil, gm, director, administrator (purchasing/fat tidak);
    ///   buat/ubah draft + lampiran = adm, plan, spv (BR-01);
    ///   purchasing = hanya request outsource (RL-06; difilter di SP lewat fn_User_OutsourceOnly).
    /// Lingkup data (departemen/Company) dibatasi di stored procedure (fn_AppUserAllowedDepartments).
    /// </summary>
    // FAT (RL-05; Keputusan 18-11-2026): hanya lihat project In Progress ke atas (difilter di SP lewat fn_Request_VisibleToUser).
    [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv, CimsRoles.Emp, CimsRoles.Kabag, CimsRoles.Mo,
        CimsRoles.Civil, CimsRoles.Gm, CimsRoles.Director, CimsRoles.Administrator, CimsRoles.Purchasing, CimsRoles.Fat, CimsRoles.Dgo)]
    public class RequestController : Controller
    {
        private static readonly string[] AllowedSortBy = { "CreatedAt", "RequestNo", "Title", "Category", "Status" };
        private static readonly string[] CoCodes = { "ABL", "NKM" };

        /// <summary>Role requester (BR-01): boleh membuat/mengubah draft.</summary>
        private static readonly string[] RequesterRoles = { CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv };

        /// <summary>Role Feasibility / ubah kategori (matriks 5.2: civil).</summary>
        private static readonly string[] CivilRoles = { CimsRoles.Civil };

        /// <summary>Role kontrak outsource (BR-11): purchasing.</summary>
        private static readonly string[] PurchasingRoles = { CimsRoles.Purchasing };

        /// <summary>Role yang melihat ABL dan NKM (BR-57): tampil filter Company.</summary>
        private static readonly string[] CrossCompanyRoles = { CimsRoles.Administrator, CimsRoles.Civil, CimsRoles.Director, CimsRoles.Gm };

        /// <summary>Batas body upload: di atas MaxSizeMB terbesar (100 MB) + overhead multipart.</summary>
        private const long UploadBodyLimit = 105L * 1024 * 1024;

        private readonly IRequestService _requestService;
        private readonly IRequestAttachmentService _attachmentService;
        private readonly IRequestLookupService _lookupService;
        private readonly ISubCategoryService _subCategoryService;
        private readonly ICurrentUserService _currentUserService;
        private readonly IUserTaskService _taskService;
        private readonly IVendorService _vendorService;
        private readonly IUnitService _unitService;
        private readonly IAddendumService _addendumService;
        private readonly IBappService _bappService;
        private readonly IActualFileService _actualFileService;
        private readonly ISurveyService _surveyService;

        public RequestController(IRequestService requestService, IRequestAttachmentService attachmentService,
            IRequestLookupService lookupService, ISubCategoryService subCategoryService, ICurrentUserService currentUserService,
            IUserTaskService taskService, IVendorService vendorService, IUnitService unitService, IAddendumService addendumService,
            IBappService bappService, IActualFileService actualFileService, ISurveyService surveyService)
        {
            _actualFileService = actualFileService;
            _surveyService = surveyService;
            _addendumService = addendumService;
            _bappService = bappService;
            _unitService = unitService;
            _vendorService = vendorService;
            _requestService = requestService;
            _attachmentService = attachmentService;
            _lookupService = lookupService;
            _subCategoryService = subCategoryService;
            _currentUserService = currentUserService;
            _taskService = taskService;
        }

        private CurrentUser? AppUser => _currentUserService.CurrentUser;

        [HttpGet]
        public async Task<IActionResult> Index(RequestListViewModel query, CancellationToken ct)
        {
            await NormalizeListQueryAsync(query, ct);
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _requestService.GetPagedAsync(query.CoCode, query.DepartmentId, query.Search, query.Category,
                query.Status, query.SortBy, query.SortDir, query.Page, query.PageSize, query.AddendumOpen, ct);

            // Halaman melebihi total -> arahkan ke halaman terakhir.
            if (result.TotalCount > 0 && query.Page > result.TotalPages)
            {
                return RedirectToAction(nameof(Index), new
                {
                    coCode = query.ShowCompanyFilter ? query.CoCode ?? string.Empty : null,
                    departmentId = query.DepartmentId,
                    search = query.Search,
                    category = query.Category,
                    status = query.Status,
                    addendum = query.Addendum,
                    sortBy = query.SortBy,
                    sortDir = query.SortDir,
                    page = result.TotalPages,
                    pageSize = query.PageSize
                });
            }

            query.Result = result;
            return View(query);
        }

        /// <summary>Export Request List sesuai filter aktif (FR-04; maks. 5000 baris).</summary>
        [HttpGet]
        public async Task<IActionResult> Export(RequestListViewModel query, CancellationToken ct)
        {
            await NormalizeListQueryAsync(query, ct);
            var result = await _requestService.GetPagedAsync(query.CoCode, query.DepartmentId, query.Search, query.Category,
                query.Status, query.SortBy, query.SortDir, 1, 5000, query.AddendumOpen, ct);

            var columns = new List<ExcelExport.Column<RequestListItem>>
            {
                new("Request No", x => x.RequestNo),
                new("Title", x => x.Title),
                new("Category", x => x.Category),
                new("Sub-category", x => x.SubCategoryName),
                new("Company", x => x.CoCode),
                new("Department", x => x.ABRV ?? x.DeptName),
                new("Requester", x => x.RequesterName),
                new("Status", x => RequestStatus.Label(x.Status)),
                new("Open addendum", x => x.OpenAddendumStatus == null ? null : $"{x.OpenAddendumCode} - {AddendumStatus.Label(x.OpenAddendumStatus)}"),
                new("Target completion", x => x.TargetCompletionDate, "dd mmm yyyy"),
                new("Budget expectation (IDR)", x => x.BudgetExpectation, "#,##0"),
                new("Submitted", x => x.SubmittedAt, "dd mmm yyyy hh:mm"),
                new("Created", x => x.CreatedAt, "dd mmm yyyy hh:mm")
            };

            var dept = query.DepartmentId.HasValue ? query.Departments.FirstOrDefault(d => d.DepartmentID == query.DepartmentId) : null;
            var filter = string.Join(" · ", new[]
            {
                query.ShowCompanyFilter ? "Company " + (query.CoCode ?? "All") : null,
                dept != null ? "Department " + dept.DeptName : null,
                query.Category != null ? "Category " + query.Category : null,
                query.Status != null ? "Status " + RequestStatus.Label(query.Status) : null,
                query.AddendumOpen ? "Addendum open" : null,
                !string.IsNullOrWhiteSpace(query.Search) ? "Search \"" + query.Search + "\"" : null
            }.Where(s => s != null));

            var bytes = ExcelExport.Build("Requests", "CIMS - Request List", filter, columns, result.Items);
            return File(bytes, ExcelExport.ContentType, $"CIMS-requests-{DateTime.Now:yyyyMMdd-HHmm}.xlsx");
        }

        /// <summary>Filter list request (Index dan Export): Company (BR-57), departemen dalam lingkup, whitelist.</summary>
        private async Task NormalizeListQueryAsync(RequestListViewModel query, CancellationToken ct)
        {
            query.ShowCompanyFilter = CimsRoles.HasAny(AppUser, CrossCompanyRoles);
            query.CanCreate = CimsRoles.HasAny(AppUser, RequesterRoles);

            // Filter Company hanya untuk role lintas Company; default = Company user (BR-57). "" = semua Company.
            if (query.ShowCompanyFilter)
            {
                if (!Request.Query.ContainsKey("coCode")) query.CoCode = AppUser?.CoCode;
                query.CoCode = CoCodes.FirstOrDefault(c => string.Equals(c, query.CoCode, StringComparison.OrdinalIgnoreCase));
            }
            else
            {
                query.CoCode = null;
            }

            // Filter departemen: hanya departemen dalam lingkup user dan milik Company terpilih (cascade)
            query.Departments = await _lookupService.GetDepartmentsForUserAsync(AppUser!.Username, ct);
            if (query.DepartmentId != null
                && !query.Departments.Any(d => d.DepartmentID == query.DepartmentId
                                               && (query.CoCode == null || d.CoCode == query.CoCode)))
            {
                query.DepartmentId = null;
            }

            query.Category = ProjectRequest.Categories.FirstOrDefault(
                c => string.Equals(c, query.Category, StringComparison.OrdinalIgnoreCase));
            query.Status = RequestStatus.All.Select(s => s.Key).FirstOrDefault(
                s => string.Equals(s, query.Status, StringComparison.OrdinalIgnoreCase));
            query.Addendum = string.Equals(query.Addendum, "open", StringComparison.OrdinalIgnoreCase) ? "open" : null;
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "CreatedAt";
            query.SortDir = string.Equals(query.SortDir, "ASC", StringComparison.OrdinalIgnoreCase) ? "ASC" : "DESC";
        }

        [HttpGet]
        public async Task<IActionResult> Details(int id, string? returnUrl, DateTime? week, string? month, CancellationToken ct)
        {
            var request = await _requestService.GetByIdAsync(id, ct);
            if (request == null) return NotFound();

            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);

            // Tugas informasi "Rejected" hilang dari Tugas Saya setelah requester membuka Details (PRD 7.1)
            if (request.Status == RequestStatus.Rejected
                && string.Equals(request.RequesterUsername, AppUser?.Username, StringComparison.OrdinalIgnoreCase))
            {
                await _taskService.MarkReadAsync(id, UserTaskType.Rejected, ct);
            }

            var isRequester = CimsRoles.HasAny(AppUser, RequesterRoles);
            var canEdit = RequestStatus.IsEditable(request.Status) && isRequester;
            // Feasibility oleh Civil (T3-1); SP memvalidasi ulang role dan status.
            var isCivil = CimsRoles.HasAny(AppUser, CivilRoles);
            var canDecideFeasibility = request.Status == RequestStatus.Feasibility && isCivil;
            // Document Preparation oleh Civil (T3-2): BOQ/Drawing, BOQ total, kirim ke management.
            var canPrepareDocuments = request.Status == RequestStatus.DocPreparation && isCivil;
            // Planning oleh Civil (T4-1): TOR + In-house/Outsource. Procurement oleh Purchasing: kontrak.
            var canChooseExecution = request.Status == RequestStatus.Planning && isCivil;
            var canProcure = request.Status == RequestStatus.Procurement && CimsRoles.HasAny(AppUser, PurchasingRoles);
            // T6-1: Civil saat In Progress mengunggah lampiran BAPP dan menerbitkan BAPP (BR-88)
            var canIssueBapp = request.Status == RequestStatus.InProgress && isCivil;
            var canManageAttachments = canEdit || canDecideFeasibility || canPrepareDocuments || canChooseExecution || canProcure
                                       || canIssueBapp;
            var attachmentStage = canManageAttachments ? RequestAttachmentService.StageForStatus(request.Status) : null;
            var steps = await _requestService.GetApprovalStepsAsync(id, ct);
            var contract = await _requestService.GetContractAsync(id, ct);
            // Addendum (T4-4): dimuat setelah cara eksekusi dipilih; hak lihat BR-86 di SP.
            var addenda = request.ExecutionType != null
                ? await _addendumService.GetByRequestAsync(id, ct)
                : Array.Empty<ProjectAddendum>();
            var openAddendum = addenda.FirstOrDefault(a => a.IsOpen);
            var isScheduleStage = request.Status is RequestStatus.Scheduling or RequestStatus.InProgress;
            // BR-79 (diubah 18-11-2026): addendum di-raise Civil (outsource dan in-house); satu addendum terbuka (BR-78).
            // Purchasing hanya melihat (BR-86). SP memvalidasi ulang.
            var canCreateAddendum = isScheduleStage && openAddendum == null && isCivil && request.ExecutionType != null;
            // BR-87: outsource menunggu kontrak final bertanda tangan dari Civil
            var canUploadAddendumContract = isScheduleStage && isCivil && openAddendum?.Status == AddendumStatus.FinalContract;
            // Schedule (T4-2): Civil mengubah saat Scheduling / In Progress; handover hanya saat Scheduling.
            var canEditSchedule = isCivil && isScheduleStage;
            var schedule = request.Status is RequestStatus.Scheduling or RequestStatus.InProgress or RequestStatus.BappReview
                    or RequestStatus.Closed or RequestStatus.SurveyCompleted
                ? await _requestService.GetScheduleAsync(id, ct)
                : null;
            // Progress mingguan (T5-1): tampil mulai In Progress; input oleh Civil hanya saat In Progress.
            var progress = request.Status is RequestStatus.InProgress or RequestStatus.BappReview
                    or RequestStatus.Closed or RequestStatus.SurveyCompleted
                ? await _requestService.GetProgressAsync(id, ct)
                : null;
            var canEnterProgress = isCivil && request.Status == RequestStatus.InProgress && progress != null;
            ProgressWeekForm? progressWeek = null;
            if (progress != null)
            {
                // Detail per action plan untuk semua yang boleh melihat progress (form untuk Civil, baca saja untuk
                // management dan role lain). Default: Civil = minggu berjalan, lainnya = minggu terakhir yang tersimpan.
                // Minggu dibatasi: minggu mulai project s.d. minggu berjalan (SP tetap memvalidasi).
                var weekDate = (week ?? (canEnterProgress ? DateTime.Today : progress.Summary.LatestWeekStart ?? DateTime.Today)).Date;
                var first = progress!.Summary.FirstWeekStart ?? progress.Summary.CurrentWeekStart;
                if (weekDate < first) weekDate = first;
                if (weekDate > progress.Summary.CurrentWeekStart.AddDays(6)) weekDate = progress.Summary.CurrentWeekStart;
                progressWeek = await _requestService.GetProgressWeekAsync(id, weekDate, ct);
            }

            // Actual cost (T5-2): tampil mulai In Progress; input Civil saat In Progress / BAPP Review.
            var actualCost = progress != null ? await _requestService.GetActualCostAsync(id, ct) : null;
            var canEnterActual = isCivil && actualCost != null
                                 && request.Status is RequestStatus.InProgress or RequestStatus.BappReview;
            ActualMonthForm? actualMonth = null;
            if (actualCost is { Summary.CanSeeDetail: true })
            {
                // ?month=yyyy-MM; default bulan berjalan; dibatasi bulan awal s.d. bulan berjalan
                var current = actualCost.Summary.CurrentMonth;
                var monthDate = DateTime.TryParseExact(month, "yyyy-MM", System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.None, out var parsed) ? parsed : current;
                if (actualCost.Summary.FirstMonth is { } firstMonth && monthDate < firstMonth) monthDate = firstMonth;
                if (monthDate > current) monthDate = current;
                actualMonth = await _requestService.GetActualMonthAsync(id, monthDate, ct);
                // BR-96: lampiran detail cost bulan terpilih
                if (actualMonth != null)
                    actualMonth.Files = await _actualFileService.ListAsync(id, actualMonth.Header.PeriodMonth, ct);
            }

            // Langkah approval aktif user: titik ADDENDUM diproses di kartu Addendum (usp_Addendum_ApprovalAct),
            // titik lain di panel approval biasa (usp_Request_ApprovalAct).
            var actionableStep = await _requestService.GetActionableStepAsync(id, ct);
            var addendumStep = actionableStep?.Point == "ADDENDUM" ? actionableStep : null;
            // T6-1: langkah BAPP diproses di kartu BAPP (form online per langkah, usp_Bapp_ApprovalAct)
            var bappStep = actionableStep?.Point == "BAPP" ? actionableStep : null;
            if (addendumStep != null || bappStep != null) actionableStep = null;

            // T6-2: survei kepuasan setelah Closed (lihat dibatasi di SP sesuai 5.2)
            var isClosed = request.Status is RequestStatus.Closed or RequestStatus.SurveyCompleted;
            var survey = isClosed ? await _surveyService.GetByRequestAsync(id, ct) : null;

            return View(new RequestDetailsViewModel
            {
                Request = request,
                Assessment = await _requestService.GetAssessmentAsync(id, ct),
                Attachments = await _attachmentService.ListAsync(id, ct),
                AttachmentTypes = attachmentStage != null ? await _lookupService.GetAttachmentTypesByStageAsync(attachmentStage, ct) : Array.Empty<AttachmentType>(),
                CanDecideFeasibility = canDecideFeasibility,
                CanPrepareDocuments = canPrepareDocuments,
                CanManageAttachments = canManageAttachments,
                SubCategories = canDecideFeasibility ? await LoadSubCategoriesAsync(ct) : Array.Empty<SubCategory>(),
                CategoryChanges = await _requestService.GetCategoryChangesAsync(id, ct),
                CanChooseExecution = canChooseExecution,
                CanProcure = canProcure,
                Contract = contract,
                Vendors = canProcure ? await _vendorService.GetActiveAsync(contract?.VendorId, ct) : Array.Empty<VendorOption>(),
                Schedule = schedule,
                // BR-81: selama addendum terbuka perubahan schedule/estimasi biasa dikunci (SP juga menolak)
                CanEditSchedule = canEditSchedule && schedule != null && openAddendum == null,
                // Handover diblok selama addendum terbuka (Keputusan 18-11-2026; SP juga menolak)
                CanHandover = canEditSchedule && schedule != null && request.Status == RequestStatus.Scheduling && openAddendum == null,
                Progress = progress,
                CanEnterProgress = canEnterProgress,
                ProgressWeek = progressWeek,
                ProgressCurve = progress != null ? await _requestService.GetProgressCurveAsync(id, ct) : Array.Empty<ProgressCurvePoint>(),
                ActualCost = actualCost,
                CanEnterActual = canEnterActual,
                ActualMonth = actualMonth,
                Units = canEnterActual ? await _unitService.GetActiveAsync(ct) : Array.Empty<UnitOption>(),
                ApprovalSteps = steps,
                History = await _requestService.GetHistoryAsync(id, ct),
                CanEdit = canEdit,
                // Tombol Cancel disembunyikan bila management approval sudah dimulai (BR-09); SP tetap memvalidasi.
                CanCancel = isRequester && RequestStatus.IsCancellable(request.Status)
                            && !steps.Any(s => s.Point == "MGMT" && s.Status == "APPROVED"),
                // Hak approve dari langkah workflow (fn_User_ActionableSteps), bukan dari role saja
                ActionableStep = actionableStep,
                Addenda = addenda,
                CanCreateAddendum = canCreateAddendum,
                AddendumFileType = canCreateAddendum ? await _addendumService.GetFileTypeAsync(request.ExecutionType, ct) : null,
                CanUploadAddendumContract = canUploadAddendumContract,
                AddendumFinalFileType = canUploadAddendumContract ? await _addendumService.GetFinalFileTypeAsync(ct) : null,
                AddendumActionableStep = addendumStep,
                CanAdjustAddendum = canEditSchedule && schedule != null && openAddendum?.Status == AddendumStatus.Adjustment,
                // T6-1: BAPP (lihat dibatasi di SP sesuai 5.2)
                Bapps = request.Status is RequestStatus.InProgress or RequestStatus.BappReview or RequestStatus.Closed
                        or RequestStatus.SurveyCompleted
                    ? await _bappService.GetByRequestAsync(id, ct)
                    : Array.Empty<ProjectBapp>(),
                CanIssueBapp = canIssueBapp,
                BappActionableStep = bappStep,
                CanPrintBapp = isCivil && request.Status is RequestStatus.Closed or RequestStatus.SurveyCompleted,
                AllPlansComplete = schedule != null && schedule.ActionPlans.Count > 0
                                   && schedule.ActionPlans.All(a => a.ProgressPercent >= 100 && a.ActualEndDate.HasValue),
                Survey = survey,
                CanSendSurvey = isCivil && request.Status == RequestStatus.Closed && survey == null
            });
        }

        /// <summary>
        /// Raise addendum oleh Civil (T4-4; BR-78, BR-79, diubah 18-11-2026): outsource = nilai kontrak baru + draft kontrak,
        /// in-house = nilai BOQ baru + BOQ revisi. Nilai naik -> menunggu approval (BR-80).
        /// </summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        [RequestSizeLimit(UploadBodyLimit)]
        [RequestFormLimits(MultipartBodyLengthLimit = UploadBodyLimit)]
        public async Task<IActionResult> CreateAddendum(int id, AddendumInput input, IFormFile? file, string? returnUrl,
            CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            return await RunActionAsync(id, returnUrl, async () =>
            {
                var result = await _addendumService.CreateAsync(id, input, file, ct);
                var code = result.AddendumCode ?? $"{result.AddendumNo}";
                TempData["Success"] = result.Status switch
                {
                    AddendumStatus.PendingApproval => $"Addendum {code} saved and sent for approval.",
                    AddendumStatus.FinalContract => $"Addendum {code} saved. Upload the signed contract to continue.",
                    _ => $"Addendum {code} saved. You can now adjust the action plans and cost estimate."
                };
            });
        }

        /// <summary>Upload kontrak final bertanda tangan addendum outsource oleh Civil (T4-4; BR-87): lanjut ke penyesuaian.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        [RequestSizeLimit(UploadBodyLimit)]
        [RequestFormLimits(MultipartBodyLengthLimit = UploadBodyLimit)]
        public async Task<IActionResult> UploadAddendumContract(int id, int addendumId, IFormFile? file, string? remarks,
            string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            return await RunActionAsync(id, returnUrl, async () =>
            {
                await _addendumService.UploadFinalContractAsync(id, addendumId, file, remarks, ct);
                TempData["Success"] = "Signed contract uploaded. You can now adjust the action plans and cost estimate.";
            });
        }

        /// <summary>
        /// Approve / Reject addendum (T4-4; BR-80). Hak sebenarnya dari snapshot langkah titik ADDENDUM
        /// (default GM ABL / Director NKM, dari tabel workflow), diperiksa di SP.
        /// </summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Kabag, CimsRoles.Mo, CimsRoles.Gm, CimsRoles.Director)]
        public async Task<IActionResult> AddendumApprovalAct(int id, int addendumId, int stepId, string? approvalAction,
            string? remarks, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (approvalAction is not (ApprovalAction.Approve or ApprovalAction.Reject))
            {
                TempData["Error"] = "Invalid approval action.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                var status = await _addendumService.ApprovalActAsync(addendumId, stepId, approvalAction, remarks, ct);
                TempData["Success"] = approvalAction == ApprovalAction.Reject
                    ? "Addendum rejected. The previous value remains in effect."
                    : $"Addendum approved. Status: {AddendumStatus.Label(status)}.";
            });
        }

        /// <summary>
        /// Penyesuaian addendum oleh Civil (T4-4; BR-82 s.d. BR-85): action plan + estimasi dalam satu simpan;
        /// total bobot 100% dan total estimasi = nilai baru; plan cost menjadi nilai baru.
        /// </summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> SaveAddendumAdjustment(int id, int addendumId, DateTime? projectStartDate,
            List<ActionPlanInput>? actionPlans, List<CostEstimateInput>? estimates, string? remarks, string? returnUrl,
            CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (projectStartDate == null)
            {
                TempData["Error"] = "Project start date is required.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            var error = TryParseEstimates(estimates, out var rows);
            if (error != null)
            {
                TempData["Error"] = error;
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                await _addendumService.SaveAdjustmentAsync(addendumId, projectStartDate.Value, NonEmptyPlans(actionPlans),
                    rows, remarks, ct);
                TempData["Success"] = "Addendum adjustment saved. The new value is now the plan cost.";
            });
        }

        /// <summary>Terbitkan BAPP oleh Civil (T6-1; BR-88): In Progress -> BAPP Review, langkah approval di-snapshot.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> IssueBapp(int id, BappInput input, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (input.BappDate == null)
            {
                TempData["Error"] = "BAPP date is required.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                var (status, bappNo) = await _bappService.IssueAsync(id, input, ct);
                TempData["Success"] = $"BAPP {bappNo} issued. Status: {RequestStatus.Label(status)}.";
            });
        }

        /// <summary>
        /// Accept / No langkah BAPP online (T6-1; BR-89, BR-93): Kabag isi hasil pemeriksaan, FAT konfirmasi tidak ada
        /// outstanding, DGO konfirmasi status CLOSED. Hak dan aturan per langkah diperiksa di SP (snapshot workflow).
        /// </summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Kabag, CimsRoles.Fat, CimsRoles.Dgo, CimsRoles.Gm, CimsRoles.Director)]
        public async Task<IActionResult> BappApprovalAct(int id, int stepId, string? approvalAction, string? remarks,
            BappApprovalInput input, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (approvalAction is not (ApprovalAction.Approve or ApprovalAction.Revise))
            {
                TempData["Error"] = "Invalid approval action.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                var status = await _bappService.ApprovalActAsync(id, stepId, approvalAction, remarks, input, ct);
                TempData["Success"] = status switch
                {
                    RequestStatus.Closed => "BAPP accepted. The project is now closed.",
                    RequestStatus.InProgress => "BAPP returned to Civil.",
                    _ => "BAPP accepted. Waiting for the next approval step."
                };
            });
        }

        /// <summary>Cetak Berita Acara (T6-1; BR-94): Civil, setelah Closed. Halaman A4 untuk Print / Save as PDF.</summary>
        [HttpGet]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> PrintBapp(int id, CancellationToken ct)
        {
            var model = await _bappService.GetPrintDataAsync(id, ct);
            if (model == null) return NotFound();
            return View(model);
        }

        /// <summary>Kirim survei kepuasan ke Kabag departemen peminta (T6-2; BR-91, BR-48): Civil, status Closed.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> SendSurvey(int id, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            return await RunActionAsync(id, returnUrl, async () =>
            {
                var count = await _surveyService.SendAsync(id, ct);                TempData["Success"] = $"Survey sent to the requesting department head ({count} items).";
            });
        }

        /// <summary>
        /// Submit survei oleh Kabag departemen peminta (T6-2; BR-24, BR-49): semua item 1-10, Note for Civil opsional.
        /// Final: request menjadi Survey Completed. Hak isi diperiksa di SP (fn_User_CanFillSurvey).
        /// </summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Kabag)]
        public async Task<IActionResult> SubmitSurvey(int id, List<SurveyScoreInput>? scores, string? noteForCivil,
            string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            var rows = scores ?? new List<SurveyScoreInput>();
            if (rows.Count == 0 || rows.Any(s => s.Score is null or < 1 or > 10))
            {
                TempData["Error"] = "Please rate every item from 1 to 10.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                var score = await _surveyService.SubmitAsync(id, rows, noteForCivil, ct);
                TempData["Success"] = $"Survey submitted. Score: {score.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)}%.";
            });
        }

        /// <summary>Unduh dokumen addendum: kind=final = kontrak final, selain itu file saat raise (hak lihat BR-86 di SP).</summary>
        [HttpGet]
        public async Task<IActionResult> DownloadAddendum(int id, string? kind, CancellationToken ct)
        {
            var final = string.Equals(kind, "final", StringComparison.OrdinalIgnoreCase);
            var found = await _addendumService.GetForDownloadAsync(id, final, ct);
            if (found == null) return NotFound();

            var (file, fullPath) = found.Value;
            return PhysicalFile(fullPath, file.ContentType, file.OriginalFileName);
        }

        /// <summary>Baris action plan yang kosong total (belum diisi sama sekali) diabaikan; sisanya divalidasi SP.</summary>
        private static List<ActionPlanInput> NonEmptyPlans(List<ActionPlanInput>? actionPlans) =>
            (actionPlans ?? new List<ActionPlanInput>())
                .Where(a => a.Id > 0 || !string.IsNullOrWhiteSpace(a.Name) || a.WeightPercent.HasValue
                            || a.PlanStartDate.HasValue || a.PlanEndDate.HasValue)
                .ToList();

        /// <summary>Estimasi dari form (bulan "yyyy-MM"); baris kosong diabaikan. Mengembalikan pesan error atau null.</summary>
        private static string? TryParseEstimates(List<CostEstimateInput>? estimates, out List<(DateTime Month, decimal Amount)> rows)
        {
            rows = new List<(DateTime Month, decimal Amount)>();
            var rowNo = 0;
            foreach (var e in estimates ?? new List<CostEstimateInput>())
            {
                rowNo++;
                if (string.IsNullOrWhiteSpace(e.Month) && e.Amount == null) continue;   // baris kosong
                if (!DateTime.TryParseExact(e.Month, "yyyy-MM", System.Globalization.CultureInfo.InvariantCulture,
                        System.Globalization.DateTimeStyles.None, out var month))
                    return $"Cost estimate row {rowNo}: month is required.";
                if (e.Amount is null or <= 0)
                    return $"Cost estimate row {rowNo}: amount must be greater than 0.";
                rows.Add((month, e.Amount.Value));
            }

            return null;
        }

        /// <summary>
        /// Approve / Revise / Reject langkah approval: titik REQUEST (T2-3; kabag (D), mo (G)) dan
        /// MGMT (T3-3; gm, director). Hak sebenarnya (role langkah, lingkup, Company, bukan request sendiri,
        /// yang pertama berlaku) diperiksa di SP dari snapshot langkah.
        /// </summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Kabag, CimsRoles.Mo, CimsRoles.Gm, CimsRoles.Director)]
        public async Task<IActionResult> ApprovalAct(int id, int stepId, string? approvalAction, string? remarks,
            string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (!ApprovalAction.IsValid(approvalAction))
            {
                TempData["Error"] = "Invalid approval action.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            try
            {
                var status = await _requestService.ApprovalActAsync(id, stepId, approvalAction!, remarks, ct);
                TempData["Success"] = $"{ApprovalAction.SuccessMessage(approvalAction!)} Status: {RequestStatus.Label(status)}.";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotAuthorizedException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl });
        }

        /// <summary>Keputusan Feasibility oleh Civil (T3-1; PRD 3.1 langkah 4): FEASIBLE / REVISE / REJECT.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> FeasibilityDecide(int id, string? decision, string? remarks, string? returnUrl,
            CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (!FeasibilityDecision.IsValid(decision))
            {
                TempData["Error"] = "Invalid feasibility decision.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            try
            {
                var status = await _requestService.FeasibilityDecideAsync(id, decision!, remarks, ct);
                TempData["Success"] = $"{FeasibilityDecision.SuccessMessage(decision!)} Status: {RequestStatus.Label(status)}.";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotAuthorizedException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl });
        }

        /// <summary>Ubah kategori / sub-kategori saat Feasibility (BR-02); kategori berubah -> nomor baru (BR-54).</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> ChangeCategory(int id, string? category, int? subCategoryId, string? reason,
            string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            var cat = ProjectRequest.Categories.FirstOrDefault(c => string.Equals(c, category, StringComparison.OrdinalIgnoreCase));
            if (cat == null || subCategoryId is null or <= 0)
            {
                TempData["Error"] = "Please select the budget classification and sub-category.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            try
            {
                var requestNo = await _requestService.ChangeCategoryAsync(id, cat, subCategoryId.Value, reason, ct);
                TempData["Success"] = $"Budget classification changed. Request no.: {requestNo}.";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotAuthorizedException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl });
        }

        /// <summary>Isi / ubah BOQ total (IDR) saat Document Preparation (T3-2; BR-05, BR-12).</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> SetBoqTotal(int id, decimal? boqTotal, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (boqTotal is null or <= 0)
            {
                TempData["Error"] = "BOQ total must be greater than 0.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            try
            {
                await _requestService.SetBoqTotalAsync(id, boqTotal.Value, ct);
                TempData["Success"] = "BOQ total saved.";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotAuthorizedException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl });
        }

        /// <summary>Kirim ke management (T3-2; BR-53): langkah MGMT disusun dari tabel saat ini.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> SendToManagement(int id, string? remarks, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            try
            {
                var status = await _requestService.SendToManagementAsync(id, remarks, ct);
                TempData["Success"] = $"Request sent to management. Status: {RequestStatus.Label(status)}.";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotAuthorizedException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl });
        }

        /// <summary>Civil memilih In-house / Outsource saat Planning (T4-1; PRD 3.3, BR-11, BR-12, BR-15).</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> ChooseExecution(int id, string? executionType, string? remarks, string? returnUrl,
            CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (!RequestExecutionType.IsValid(executionType))
            {
                TempData["Error"] = "Please choose in-house or outsource.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                var status = await _requestService.ChooseExecutionAsync(id, executionType!, remarks, ct);
                TempData["Success"] = $"{RequestExecutionType.SuccessMessage(executionType!)} Status: {RequestStatus.Label(status)}.";
            });
        }

        /// <summary>Purchasing menyimpan data kontrak saat Procurement (T4-1; BR-11).</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Purchasing)]
        public async Task<IActionResult> SaveContract(int id, int? vendorId, string? contractNo, DateTime? contractDate,
            decimal? contractValue, string? remarks, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            var missing = new List<string>();
            if (vendorId is null or <= 0) missing.Add("Vendor");
            if (string.IsNullOrWhiteSpace(contractNo)) missing.Add("Contract number");
            if (contractDate == null) missing.Add("Contract date");
            if (contractValue is null or <= 0) missing.Add("Contract value (greater than 0)");
            if (missing.Count > 0)
            {
                TempData["Error"] = $"Please complete: {string.Join(", ", missing)}.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                await _requestService.SaveContractAsync(id, vendorId!.Value, contractNo!, contractDate!.Value,
                    contractValue!.Value, remarks, ct);
                TempData["Success"] = "Contract saved.";
            });
        }

        /// <summary>Purchasing menyelesaikan procurement (T4-1): wajib kontrak + lampiran kontrak -> Scheduling.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Purchasing)]
        public async Task<IActionResult> CompleteProcurement(int id, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            return await RunActionAsync(id, returnUrl, async () =>
            {
                var status = await _requestService.CompleteProcurementAsync(id, ct);
                TempData["Success"] = $"Procurement completed. Status: {RequestStatus.Label(status)}.";
            });
        }

        /// <summary>Purchasing mengembalikan TOR ke Civil (T4-1; Keputusan 14-11-2026): alasan wajib -> Planning.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Purchasing)]
        public async Task<IActionResult> ReturnTor(int id, string? reason, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (string.IsNullOrWhiteSpace(reason))
            {
                TempData["Error"] = "Reason is required.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                await _requestService.ReturnTorAsync(id, reason, ct);
                TempData["Success"] = "TOR returned to Civil.";
            });
        }

        /// <summary>Civil menyimpan tanggal mulai project + action plan (T4-2; BR-15, BR-16). In Progress: alasan wajib.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> SaveSchedule(int id, DateTime? projectStartDate, List<ActionPlanInput>? actionPlans,
            string? reason, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (projectStartDate == null)
            {
                TempData["Error"] = "Project start date is required.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            var plans = NonEmptyPlans(actionPlans);

            return await RunActionAsync(id, returnUrl, async () =>
            {
                await _requestService.SaveScheduleAsync(id, projectStartDate.Value, plans, reason, ct);
                TempData["Success"] = "Schedule saved.";
            });
        }

        /// <summary>Civil menyimpan estimasi biaya per bulan (T4-2; BR-13). In Progress: alasan wajib, total = plan cost.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> SaveCostEstimate(int id, List<CostEstimateInput>? estimates, string? reason,
            string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            var error = TryParseEstimates(estimates, out var rows);
            if (error != null)
            {
                TempData["Error"] = error;
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                await _requestService.SaveCostEstimateAsync(id, rows, reason, ct);
                TempData["Success"] = "Cost estimate saved.";
            });
        }

        /// <summary>Civil mencatat site handover (T4-2; ST-11): Scheduling -> In Progress.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> SiteHandover(int id, DateTime? handoverDate, string? remarks, string? returnUrl,
            CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (handoverDate == null)
            {
                TempData["Error"] = "Site handover date is required.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            return await RunActionAsync(id, returnUrl, async () =>
            {
                var status = await _requestService.SiteHandoverAsync(id, handoverDate.Value, remarks, ct);
                TempData["Success"] = $"Site handover recorded. Status: {RequestStatus.Label(status)}.";
            });
        }

        /// <summary>Civil menyimpan progress mingguan (T5-1; BR-16, BR-17, BR-68). Kembali ke minggu yang sama.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> SaveProgress(int id, DateTime? weekStart, List<ProgressInput>? items, string? remarks,
            string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            var weekText = weekStart?.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
            if (weekStart == null)
            {
                TempData["Error"] = "Week is required.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            try
            {
                var result = await _requestService.SaveProgressAsync(id, weekStart.Value, items ?? new List<ProgressInput>(), remarks, ct);
                var inv = System.Globalization.CultureInfo.InvariantCulture;
                TempData["Success"] = $"Progress saved for the week of {result.WeekStart.ToString("dd MMM yyyy", inv)}: "
                                      + $"actual {result.ActualPercent.ToString("0.##", inv)}% vs plan {result.PlanPercent.ToString("0.##", inv)}% "
                                      + $"({ScheduleStatus.Label(result.ScheduleStatus)}).";
            }
            catch (Exception ex) when (ex is RequestValidationException or RequestInvalidStateException or RequestNotAuthorizedException)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl, week = weekText });
        }

        /// <summary>
        /// Civil menyimpan actual cost satu bulan (T5-2; BR-18, BR-19): seluruh item bulan itu diganti; tanpa item = hapus.
        /// Kembali ke bulan yang sama.
        /// </summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        [RequestSizeLimit(UploadBodyLimit)]
        [RequestFormLimits(MultipartBodyLengthLimit = UploadBodyLimit)]
        public async Task<IActionResult> SaveActualCost(int id, string? month, List<ActualItemInput>? items, string? remarks,
            List<IFormFile>? files, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            if (!DateTime.TryParseExact(month, "yyyy-MM", inv, System.Globalization.DateTimeStyles.None, out var monthDate))
            {
                TempData["Error"] = "Month is required.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            // Baris kosong total diabaikan; sisanya divalidasi SP
            var rows = (items ?? new List<ActualItemInput>()).Where(i => !i.IsEmpty).ToList();

            try
            {
                // BR-96: lampiran detail cost baru disimpan bersama item (wajib minimal satu untuk bulan berisi actual)
                var newFiles = (files ?? new List<IFormFile>()).Where(f => f is { Length: > 0 }).ToList();
                var result = await _actualFileService.SaveMonthAsync(id, monthDate, rows, remarks, newFiles, ct);
                var monthText = monthDate.ToString("MMM yyyy", inv);
                TempData["Success"] = rows.Count == 0
                    ? $"Actual cost for {monthText} removed. Cost status: {CostStatus.Label(result.CostStatus)}."
                    : $"Actual cost for {monthText} saved. Total actual IDR {(result.ActualCostTotal ?? 0).ToString("#,0.##", inv)} "
                      + $"({(result.CostRatioPercent.HasValue ? result.CostRatioPercent.Value.ToString("0.##", inv) + "% of estimate, " : "")}"
                      + $"{CostStatus.Label(result.CostStatus)}).";
            }
            catch (Exception ex) when (ex is RequestValidationException or RequestInvalidStateException or RequestNotAuthorizedException)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), null, new { id, returnUrl, month }, "actualForm");
        }

        /// <summary>Tambah lampiran detail cost ke satu bulan (BR-96; mis. bulan hasil upload Excel). Kembali ke bulan itu.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        [RequestSizeLimit(UploadBodyLimit)]
        [RequestFormLimits(MultipartBodyLengthLimit = UploadBodyLimit)]
        public async Task<IActionResult> UploadActualFile(int id, string? month, IFormFile? file, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            if (!DateTime.TryParseExact(month, "yyyy-MM", System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.None, out var monthDate))
            {
                TempData["Error"] = "Month is required.";
                return RedirectToAction(nameof(Details), new { id, returnUrl });
            }

            try
            {
                await _actualFileService.AddAsync(id, monthDate, file, ct);
                TempData["Success"] = "Cost detail document uploaded.";
            }
            catch (Exception ex) when (ex is RequestValidationException or RequestInvalidStateException or RequestNotAuthorizedException)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), null, new { id, returnUrl, month }, "actualForm");
        }

        /// <summary>Hapus lampiran detail cost (BR-96); lampiran terakhir bulan berisi actual ditolak SP.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> RemoveActualFile(int id, int fileId, string? month, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            try
            {
                await _actualFileService.RemoveAsync(fileId, ct);
                TempData["Success"] = "Cost detail document removed.";
            }
            catch (Exception ex) when (ex is RequestValidationException or RequestInvalidStateException
                                           or RequestNotAuthorizedException or RequestNotFoundException)
            {
                TempData["Error"] = ex.Message;
            }

            return RedirectToAction(nameof(Details), null, new { id, returnUrl, month }, "actualForm");
        }

        /// <summary>Unduh lampiran detail cost (hak lihat detail actual cost diperiksa di SP).</summary>
        [HttpGet]
        public async Task<IActionResult> DownloadActualFile(int id, CancellationToken ct)
        {
            var found = await _actualFileService.GetForDownloadAsync(id, ct);
            if (found == null) return NotFound();

            var (file, fullPath) = found.Value;
            return PhysicalFile(fullPath, file.ContentType, file.OriginalFileName);
        }

        /// <summary>
        /// Jalankan aksi workflow (PRG): error validasi/status/role -> TempData["Error"] lalu kembali ke Details;
        /// request tidak ditemukan / di luar lingkup -> Index.
        /// </summary>
        private async Task<IActionResult> RunActionAsync(int id, string? returnUrl, Func<Task> action)
        {
            try
            {
                await action();
            }
            catch (Exception ex) when (ex is RequestValidationException or RequestInvalidStateException or RequestNotAuthorizedException)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv)]
        public async Task<IActionResult> Submit(int id, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            try
            {
                var (requestNo, status) = await _requestService.SubmitAsync(id, ct);
                TempData["Success"] = $"Request {requestNo} submitted ({RequestStatus.Label(status)}).";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv)]
        public async Task<IActionResult> Cancel(int id, string? reason, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            try
            {
                await _requestService.CancelAsync(id, reason, ct);
                TempData["Success"] = "Request cancelled.";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return RedirectToAction(nameof(Details), new { id, returnUrl });
        }

        [HttpGet]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv)]
        public async Task<IActionResult> Create(string? returnUrl, CancellationToken ct)
        {
            var user = AppUser;
            if (user?.DepartmentID == null || string.IsNullOrEmpty(user.CoCode))
            {
                TempData["Error"] = "Your department or company is not set in the employee data.";
                return RedirectToAction(nameof(Index));
            }

            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            var model = new RequestFormViewModel { CoCode = user.CoCode, DeptName = user.DeptName, ABRV = user.ABRV };
            await LoadFormAsync(model, user.DepartmentID.Value, user.CoCode, null, ct);
            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv)]
        public async Task<IActionResult> Create(RequestFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            var user = AppUser;
            if (user?.DepartmentID == null || string.IsNullOrEmpty(user.CoCode))
            {
                TempData["Error"] = "Your department or company is not set in the employee data.";
                return RedirectToAction(nameof(Index));
            }

            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            model.Id = 0;
            model.CoCode = user.CoCode;
            model.DeptName = user.DeptName;
            model.ABRV = user.ABRV;

            if (ModelState.IsValid)
            {
                try
                {
                    var newId = await _requestService.SaveDraftAsync(model.ToEntity(), model.Answers, ct);
                    TempData["Success"] = "Draft saved. You can now add attachments.";
                    // Ke Details (tempat lampiran dikelola); returnUrl ikut agar Back kembali ke list asal.
                    return RedirectToAction(nameof(Details), new { id = newId, returnUrl });
                }
                catch (RequestValidationException ex)
                {
                    ModelState.AddModelError(string.Empty, ex.Message);
                }
            }

            await LoadFormAsync(model, user.DepartmentID.Value, user.CoCode, model.Answers, ct);
            return View(model);
        }

        [HttpGet]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv)]
        public async Task<IActionResult> Edit(int id, string? returnUrl, CancellationToken ct)
        {
            var request = await _requestService.GetByIdAsync(id, ct);
            if (request == null) return NotFound();
            if (!RequestStatus.IsEditable(request.Status))
            {
                TempData["Error"] = "Only draft or returned requests can be edited.";
                return RedirectToAction(nameof(Details), new { id, returnUrl = LocalOrNull(returnUrl) });
            }

            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            var model = RequestFormViewModel.FromEntity(request);
            var saved = await _requestService.GetAssessmentAsync(id, ct);
            await LoadFormAsync(model, request.DepartmentID, request.CoCode,
                saved.Select(a => new RequestAnswerInput { QuestionId = a.QuestionId, Answer = a.Answer }), ct);
            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv)]
        public async Task<IActionResult> Edit(int id, RequestFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            if (id != model.Id) return BadRequest();
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;

            // Data tampilan dan lingkup selalu dari database, bukan dari form.
            var request = await _requestService.GetByIdAsync(id, ct);
            if (request == null)
            {
                TempData["Error"] = "Request not found.";
                return RedirectToAction(nameof(Index));
            }
            model.RequestNo = request.RequestNo;
            model.Status = request.Status;
            model.CoCode = request.CoCode;
            model.DeptName = request.DeptName;
            model.ABRV = request.ABRV;

            if (ModelState.IsValid)
            {
                try
                {
                    await _requestService.SaveDraftAsync(model.ToEntity(), model.Answers, ct);
                    TempData["Success"] = "Draft updated successfully.";
                    // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                    return returnUrl != null
                        ? LocalRedirect(returnUrl)
                        : RedirectToAction(nameof(Details), new { id });
                }
                catch (RequestValidationException ex)
                {
                    ModelState.AddModelError(string.Empty, ex.Message);
                }
                catch (RequestNotFoundException ex)
                {
                    TempData["Error"] = ex.Message;
                    return RedirectToAction(nameof(Index));
                }
                catch (RequestInvalidStateException ex)
                {
                    TempData["Error"] = ex.Message;
                    return RedirectToAction(nameof(Details), new { id, returnUrl });
                }
            }

            await LoadFormAsync(model, request.DepartmentID, request.CoCode, model.Answers, ct);
            return View(model);
        }

        // Civil: Feasibility (ROI), Document Preparation (BOQ/Drawing), Planning (TOR);
        // Purchasing: Procurement (lampiran kontrak). Status + role dicek di service/SP.
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv, CimsRoles.Civil, CimsRoles.Purchasing)]
        [RequestSizeLimit(UploadBodyLimit)]
        [RequestFormLimits(MultipartBodyLengthLimit = UploadBodyLimit)]
        public async Task<IActionResult> UploadAttachment(int id, int attachmentTypeId, IFormFile? file, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            try
            {
                await _attachmentService.UploadAsync(id, attachmentTypeId, file, ct);
                TempData["Success"] = "Attachment uploaded.";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            // Kembali ke kartu Attachments (upload/hapus beberapa file tanpa menggulir lagi)
            return RedirectToAction(nameof(Details), null, new { id, returnUrl }, "attachments");
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv, CimsRoles.Civil, CimsRoles.Purchasing)]
        public async Task<IActionResult> DeactivateAttachment(int id, int attachmentId, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            try
            {
                await _attachmentService.DeactivateAsync(attachmentId, ct);
                TempData["Success"] = "Attachment removed.";
            }
            catch (RequestInvalidStateException ex)
            {
                TempData["Error"] = ex.Message;
            }
            catch (RequestNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
            }

            // Kembali ke kartu Attachments (upload/hapus beberapa file tanpa menggulir lagi)
            return RedirectToAction(nameof(Details), null, new { id, returnUrl }, "attachments");
        }

        [HttpGet]
        public async Task<IActionResult> DownloadAttachment(int id, CancellationToken ct)
        {
            var found = await _attachmentService.GetForDownloadAsync(id, ct);
            if (found == null) return NotFound();

            var (attachment, fullPath) = found.Value;
            return PhysicalFile(fullPath, attachment.ContentType, attachment.OriginalFileName);
        }

        /// <summary>Input project berjalan (T4-3; FR-03): form, khusus Civil.</summary>
        [HttpGet]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> CreateRunning(string? returnUrl, CancellationToken ct)
        {
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            var model = new RunningProjectFormViewModel();
            for (var i = 0; i < 2; i++) model.Approvals.Add(new OutsideApprovalInput());
            await LoadRunningFormAsync(model, ct);
            return View(model);
        }

        /// <summary>Simpan project berjalan (T4-3; FR-03, BR-76, BR-77) -> Details.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> CreateRunning(RunningProjectFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;

            // Aturan bersyarat (SP tetap memvalidasi ulang)
            if (model.TargetStatus == RequestStatus.Scheduling)
            {
                if (!RequestExecutionType.IsValid(model.ExecutionType))
                    ModelState.AddModelError(nameof(model.ExecutionType), "Execution method is required for projects in scheduling.");
                else if (model.ExecutionType == RequestExecutionType.InHouse && model.BoqTotal == null)
                    ModelState.AddModelError(nameof(model.BoqTotal), "BOQ total is required for in-house execution.");
                else if (model.ExecutionType == RequestExecutionType.Outsource)
                {
                    if (model.VendorId is null or <= 0) ModelState.AddModelError(nameof(model.VendorId), "Vendor is required.");
                    if (string.IsNullOrWhiteSpace(model.ContractNo)) ModelState.AddModelError(nameof(model.ContractNo), "Contract number is required.");
                    if (model.ContractDate == null) ModelState.AddModelError(nameof(model.ContractDate), "Contract date is required.");
                    if (model.ContractValue == null) ModelState.AddModelError(nameof(model.ContractValue), "Contract value is required.");
                }
            }
            if (model.Approvals.Count(a => !a.IsEmpty) > RunningProjectFormViewModel.MaxOutsideApprovals)
                ModelState.AddModelError(string.Empty, $"At most {RunningProjectFormViewModel.MaxOutsideApprovals} outside approval rows are allowed.");

            if (ModelState.IsValid)
            {
                try
                {
                    var (newId, requestNo, status) = await _requestService.CreateRunningAsync(model, ct);
                    TempData["Success"] = $"Running project {requestNo} entered ({RequestStatus.Label(status)}).";
                    return RedirectToAction(nameof(Details), new { id = newId, returnUrl });
                }
                catch (RequestValidationException ex)
                {
                    ModelState.AddModelError(string.Empty, ex.Message);
                }
                catch (RequestNotAuthorizedException ex)
                {
                    TempData["Error"] = ex.Message;
                    return RedirectToAction(nameof(Index));
                }
            }

            await LoadRunningFormAsync(model, ct);
            return View(model);
        }

        /// <summary>
        /// Pilihan yang bergantung departemen untuk form project berjalan (AJAX): cost center, PIC, lokasi Company.
        /// Departemen harus dalam lingkup user.
        /// </summary>
        [HttpGet]
        [RoleAuthorizeApi(CimsRoles.Civil)]
        public async Task<IActionResult> RunningLookups(int departmentId, CancellationToken ct)
        {
            var dept = (await _lookupService.GetDepartmentsForUserAsync(AppUser!.Username, ct))
                .FirstOrDefault(d => d.DepartmentID == departmentId);
            if (dept == null)
                return NotFound(new { success = false, message = "Department not found." });

            return Json(new
            {
                success = true,
                coCode = dept.CoCode,
                costCenters = (await _lookupService.GetCostCentersAsync(departmentId, ct))
                    .Select(c => new { id = c.SubDepartmentID, text = $"{c.SubDepartmentCode} {c.SubDepartmentName}" }),
                employees = (await _lookupService.GetActiveEmployeesAsync(departmentId, null, ct))
                    .Select(e => new { id = e.EmployeeCode, text = $"{e.FullName} ({e.EmployeeCode})" }),
                locations = (await _lookupService.GetLocationsAsync(dept.CoCode, ct))
                    .Select(l => new { id = l.Id, text = l.Name })
            });
        }

        /// <summary>Isi dropdown form project berjalan; pilihan per departemen dimuat bila departemen sudah dipilih.</summary>
        private async Task LoadRunningFormAsync(RunningProjectFormViewModel model, CancellationToken ct)
        {
            model.Departments = await _lookupService.GetDepartmentsForUserAsync(AppUser!.Username, ct);
            model.SubCategories = await LoadSubCategoriesAsync(ct);
            model.Vendors = await _vendorService.GetActiveAsync(model.VendorId, ct);

            var dept = model.Departments.FirstOrDefault(d => d.DepartmentID == model.DepartmentID);
            if (dept != null)
            {
                model.CostCenters = await _lookupService.GetCostCentersAsync(dept.DepartmentID, ct);
                model.Employees = await _lookupService.GetActiveEmployeesAsync(dept.DepartmentID, null, ct);
                model.Locations = await _lookupService.GetLocationsAsync(dept.CoCode, ct);
            }
        }

        /// <summary>Isi dropdown dan daftar pertanyaan assessment (jawaban digabung per QuestionId).</summary>
        private async Task LoadFormAsync(RequestFormViewModel model, int departmentId, string coCode,
            IEnumerable<RequestAnswerInput>? answers, CancellationToken ct)
        {
            model.SubCategories = await LoadSubCategoriesAsync(ct);
            model.CostCenters = await _lookupService.GetCostCentersAsync(departmentId, ct);
            model.Locations = await _lookupService.GetLocationsAsync(coCode, ct);
            model.Employees = await _lookupService.GetActiveEmployeesAsync(departmentId, null, ct);

            var given = (answers ?? Enumerable.Empty<RequestAnswerInput>())
                .GroupBy(a => a.QuestionId)
                .ToDictionary(g => g.Key, g => g.First().Answer);
            var questions = await _lookupService.GetAssessmentQuestionsAsync(ct);
            model.Answers = questions.Select(q => new RequestAnswerInput
            {
                QuestionId = q.QuestionId,
                QuestionText = q.QuestionText,
                Answer = given.TryGetValue(q.QuestionId, out var a) ? a : null
            }).ToList();
        }

        /// <summary>Sub-kategori aktif semua kategori (cascade di form).</summary>
        private async Task<IReadOnlyList<SubCategory>> LoadSubCategoriesAsync(CancellationToken ct)
        {
            var subCategories = new List<SubCategory>();
            foreach (var category in ProjectRequest.Categories)
                subCategories.AddRange(await _subCategoryService.GetActiveByCategoryAsync(category, ct));
            return subCategories;
        }

        /// <summary>returnUrl hanya dipakai bila lokal (cegah open redirect).</summary>
        private string? LocalOrNull(string? returnUrl) =>
            !string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl) ? returnUrl : null;
    }
}
