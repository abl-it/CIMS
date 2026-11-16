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
    [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv, CimsRoles.Emp, CimsRoles.Kabag, CimsRoles.Mo,
        CimsRoles.Civil, CimsRoles.Gm, CimsRoles.Director, CimsRoles.Administrator, CimsRoles.Purchasing)]
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

        public RequestController(IRequestService requestService, IRequestAttachmentService attachmentService,
            IRequestLookupService lookupService, ISubCategoryService subCategoryService, ICurrentUserService currentUserService,
            IUserTaskService taskService, IVendorService vendorService)
        {
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
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "CreatedAt";
            query.SortDir = string.Equals(query.SortDir, "ASC", StringComparison.OrdinalIgnoreCase) ? "ASC" : "DESC";
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _requestService.GetPagedAsync(query.CoCode, query.DepartmentId, query.Search, query.Category,
                query.Status, query.SortBy, query.SortDir, query.Page, query.PageSize, ct);

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
                    sortBy = query.SortBy,
                    sortDir = query.SortDir,
                    page = result.TotalPages,
                    pageSize = query.PageSize
                });
            }

            query.Result = result;
            return View(query);
        }

        [HttpGet]
        public async Task<IActionResult> Details(int id, string? returnUrl, CancellationToken ct)
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
            var canManageAttachments = canEdit || canDecideFeasibility || canPrepareDocuments || canChooseExecution || canProcure;
            var attachmentStage = canManageAttachments ? RequestAttachmentService.StageForStatus(request.Status) : null;
            var steps = await _requestService.GetApprovalStepsAsync(id, ct);
            var contract = await _requestService.GetContractAsync(id, ct);
            // Schedule (T4-2): Civil mengubah saat Scheduling / In Progress; handover hanya saat Scheduling.
            var canEditSchedule = isCivil && request.Status is RequestStatus.Scheduling or RequestStatus.InProgress;
            var schedule = request.Status is RequestStatus.Scheduling or RequestStatus.InProgress or RequestStatus.BappReview
                    or RequestStatus.Closed or RequestStatus.SurveyCompleted
                ? await _requestService.GetScheduleAsync(id, ct)
                : null;

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
                CanEditSchedule = canEditSchedule && schedule != null,
                CanHandover = canEditSchedule && schedule != null && request.Status == RequestStatus.Scheduling,
                ApprovalSteps = steps,
                History = await _requestService.GetHistoryAsync(id, ct),
                CanEdit = canEdit,
                // Tombol Cancel disembunyikan bila management approval sudah dimulai (BR-09); SP tetap memvalidasi.
                CanCancel = isRequester && RequestStatus.IsCancellable(request.Status)
                            && !steps.Any(s => s.Point == "MGMT" && s.Status == "APPROVED"),
                // Hak approve dari langkah workflow (fn_User_ActionableSteps), bukan dari role saja
                ActionableStep = await _requestService.GetActionableStepAsync(id, ct)
            });
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

            // Baris kosong total (belum diisi sama sekali) diabaikan; sisanya divalidasi SP.
            var plans = (actionPlans ?? new List<ActionPlanInput>())
                .Where(a => a.Id > 0 || !string.IsNullOrWhiteSpace(a.Name) || a.WeightPercent.HasValue
                            || a.PlanStartDate.HasValue || a.PlanEndDate.HasValue)
                .ToList();

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
            var rows = new List<(DateTime Month, decimal Amount)>();
            var rowNo = 0;
            foreach (var e in estimates ?? new List<CostEstimateInput>())
            {
                rowNo++;
                if (string.IsNullOrWhiteSpace(e.Month) && e.Amount == null) continue;   // baris kosong
                if (!DateTime.TryParseExact(e.Month, "yyyy-MM", System.Globalization.CultureInfo.InvariantCulture,
                        System.Globalization.DateTimeStyles.None, out var month))
                {
                    TempData["Error"] = $"Cost estimate row {rowNo}: month is required.";
                    return RedirectToAction(nameof(Details), new { id, returnUrl });
                }
                if (e.Amount is null or <= 0)
                {
                    TempData["Error"] = $"Cost estimate row {rowNo}: amount must be greater than 0.";
                    return RedirectToAction(nameof(Details), new { id, returnUrl });
                }
                rows.Add((month, e.Amount.Value));
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

            return RedirectToAction(nameof(Details), new { id, returnUrl });
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

            return RedirectToAction(nameof(Details), new { id, returnUrl });
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
