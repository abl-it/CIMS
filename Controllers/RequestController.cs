using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>
    /// Request / business case (T2-1: Draft). Matriks PRD 5.2:
    ///   lihat  = adm, plan, spv, emp, kabag, mo, civil, gm, director, administrator (purchasing/fat tidak);
    ///   buat/ubah draft + lampiran = adm, plan, spv (BR-01).
    /// Lingkup data (departemen/Company) dibatasi di stored procedure (fn_AppUserAllowedDepartments).
    /// </summary>
    [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv, CimsRoles.Emp, CimsRoles.Kabag, CimsRoles.Mo,
        CimsRoles.Civil, CimsRoles.Gm, CimsRoles.Director, CimsRoles.Administrator)]
    public class RequestController : Controller
    {
        private static readonly string[] AllowedSortBy = { "CreatedAt", "RequestNo", "Title", "Category", "Status" };
        private static readonly string[] CoCodes = { "ABL", "NKM" };

        /// <summary>Role requester (BR-01): boleh membuat/mengubah draft.</summary>
        private static readonly string[] RequesterRoles = { CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv };

        /// <summary>Role Feasibility / ubah kategori (matriks 5.2: civil).</summary>
        private static readonly string[] CivilRoles = { CimsRoles.Civil };

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

        public RequestController(IRequestService requestService, IRequestAttachmentService attachmentService,
            IRequestLookupService lookupService, ISubCategoryService subCategoryService, ICurrentUserService currentUserService,
            IUserTaskService taskService)
        {
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

            var result = await _requestService.GetPagedAsync(query.CoCode, query.Search, query.Category, query.Status,
                query.SortBy, query.SortDir, query.Page, query.PageSize, ct);

            // Halaman melebihi total -> arahkan ke halaman terakhir.
            if (result.TotalCount > 0 && query.Page > result.TotalPages)
            {
                return RedirectToAction(nameof(Index), new
                {
                    coCode = query.ShowCompanyFilter ? query.CoCode ?? string.Empty : null,
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
            var canDecideFeasibility = request.Status == RequestStatus.Feasibility && CimsRoles.HasAny(AppUser, CivilRoles);
            var canManageAttachments = canEdit || canDecideFeasibility;
            var steps = await _requestService.GetApprovalStepsAsync(id, ct);

            return View(new RequestDetailsViewModel
            {
                Request = request,
                Assessment = await _requestService.GetAssessmentAsync(id, ct),
                Attachments = await _attachmentService.ListAsync(id, ct),
                AttachmentTypes = canManageAttachments ? await _lookupService.GetAttachmentTypesByStageAsync("REQUEST", ct) : Array.Empty<AttachmentType>(),
                CanDecideFeasibility = canDecideFeasibility,
                CanManageAttachments = canManageAttachments,
                SubCategories = canDecideFeasibility ? await LoadSubCategoriesAsync(ct) : Array.Empty<SubCategory>(),
                CategoryChanges = await _requestService.GetCategoryChangesAsync(id, ct),
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
        /// Approve / Revise / Reject langkah approval sebelum Civil (T2-3; matriks 5.2: kabag (D), mo (G)).
        /// Hak sebenarnya (role langkah, lingkup, Company, bukan request sendiri, yang pertama berlaku) diperiksa di SP.
        /// </summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Kabag, CimsRoles.Mo)]
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

        // Civil boleh saat Feasibility (mis. lampiran ROI); status + role dicek di service/SP.
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv, CimsRoles.Civil)]
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
        [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv, CimsRoles.Civil)]
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
