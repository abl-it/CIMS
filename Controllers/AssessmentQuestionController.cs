using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    [RoleAuthorize(CimsRoles.Administrator, CimsRoles.Civil)]
    public class AssessmentQuestionController : Controller
    {
        private static readonly string[] AllowedSortBy = { "SortOrder", "QuestionText", "CreatedAt" };

        private readonly IAssessmentQuestionService _questionService;

        public AssessmentQuestionController(IAssessmentQuestionService questionService)
        {
            _questionService = questionService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(AssessmentQuestionListViewModel query, CancellationToken ct)
        {
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "SortOrder";
            query.SortDir = string.Equals(query.SortDir, "DESC", StringComparison.OrdinalIgnoreCase) ? "DESC" : "ASC";
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _questionService.GetPagedAsync(
                query.Search, query.IsActive, query.SortBy, query.SortDir, query.Page, query.PageSize, ct);

            // Halaman melebihi total -> arahkan ke halaman terakhir.
            if (result.TotalCount > 0 && query.Page > result.TotalPages)
            {
                return RedirectToAction(nameof(Index), new
                {
                    search = query.Search,
                    isActive = query.IsActive,
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
            var question = await _questionService.GetByIdAsync(id, ct);
            if (question == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(question);
        }

        [HttpGet]
        public IActionResult Create(string? returnUrl)
        {
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(new AssessmentQuestionFormViewModel());
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(AssessmentQuestionFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                var newId = await _questionService.InsertAsync(model.ToEntity(), ct);
                TempData["Success"] = "Question added successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = newId });
            }
            catch (AssessmentQuestionDuplicateException ex)
            {
                ModelState.AddModelError(nameof(model.QuestionText), ex.Message);
            }
            catch (AssessmentQuestionValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Edit(int id, string? returnUrl, CancellationToken ct)
        {
            var question = await _questionService.GetByIdAsync(id, ct);
            if (question == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(AssessmentQuestionFormViewModel.FromEntity(question));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(int id, AssessmentQuestionFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            if (id != model.Id) return BadRequest();
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                await _questionService.UpdateAsync(model.ToEntity(), ct);
                TempData["Success"] = "Question updated successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = model.Id });
            }
            catch (AssessmentQuestionDuplicateException ex)
            {
                ModelState.AddModelError(nameof(model.QuestionText), ex.Message);
            }
            catch (AssessmentQuestionValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }
            catch (AssessmentQuestionNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> SetActive(int id, bool isActive, string? returnUrl, CancellationToken ct)
        {
            try
            {
                await _questionService.SetActiveAsync(id, isActive, ct);
                TempData["Success"] = isActive ? "Question activated." : "Question deactivated.";
            }
            catch (AssessmentQuestionNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
                return LocalRedirect(returnUrl);

            return RedirectToAction(nameof(Index));
        }

        /// <summary>returnUrl hanya dipakai bila lokal (cegah open redirect).</summary>
        private string? LocalOrNull(string? returnUrl) =>
            !string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl) ? returnUrl : null;
    }
}
