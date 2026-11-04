using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    [RoleAuthorize(CimsRoles.Administrator, CimsRoles.Civil)]
    public class SurveyTemplateItemController : Controller
    {
        private static readonly string[] AllowedSortBy = { "Category", "SortOrder", "ItemText", "CreatedAt" };

        private readonly ISurveyTemplateItemService _itemService;

        public SurveyTemplateItemController(ISurveyTemplateItemService itemService)
        {
            _itemService = itemService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(SurveyTemplateItemListViewModel query, CancellationToken ct)
        {
            query.Category = SurveyTemplateItem.Categories.FirstOrDefault(
                c => string.Equals(c, query.Category, StringComparison.OrdinalIgnoreCase));
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "Category";
            query.SortDir = string.Equals(query.SortDir, "DESC", StringComparison.OrdinalIgnoreCase) ? "DESC" : "ASC";
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _itemService.GetPagedAsync(
                query.Category, query.Search, query.IsActive, query.SortBy, query.SortDir, query.Page, query.PageSize, ct);

            // Halaman melebihi total -> arahkan ke halaman terakhir.
            if (result.TotalCount > 0 && query.Page > result.TotalPages)
            {
                return RedirectToAction(nameof(Index), new
                {
                    category = query.Category,
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
            var item = await _itemService.GetByIdAsync(id, ct);
            if (item == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(item);
        }

        [HttpGet]
        public IActionResult Create(string? category, string? returnUrl)
        {
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            // Kategori dari filter list (bila ada) dipakai sebagai nilai awal.
            var initial = SurveyTemplateItem.Categories.FirstOrDefault(
                c => string.Equals(c, category, StringComparison.OrdinalIgnoreCase)) ?? string.Empty;
            return View(new SurveyTemplateItemFormViewModel { Category = initial });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(SurveyTemplateItemFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                var newId = await _itemService.InsertAsync(model.ToEntity(), ct);
                TempData["Success"] = "Survey item added successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = newId });
            }
            catch (SurveyTemplateItemDuplicateException ex)
            {
                ModelState.AddModelError(nameof(model.ItemText), ex.Message);
            }
            catch (SurveyTemplateItemValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Edit(int id, string? returnUrl, CancellationToken ct)
        {
            var item = await _itemService.GetByIdAsync(id, ct);
            if (item == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(SurveyTemplateItemFormViewModel.FromEntity(item));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(int id, SurveyTemplateItemFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            if (id != model.Id) return BadRequest();
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                await _itemService.UpdateAsync(model.ToEntity(), ct);
                TempData["Success"] = "Survey item updated successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = model.Id });
            }
            catch (SurveyTemplateItemDuplicateException ex)
            {
                ModelState.AddModelError(nameof(model.ItemText), ex.Message);
            }
            catch (SurveyTemplateItemValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }
            catch (SurveyTemplateItemNotFoundException ex)
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
                await _itemService.SetActiveAsync(id, isActive, ct);
                TempData["Success"] = isActive ? "Survey item activated." : "Survey item deactivated.";
            }
            catch (SurveyTemplateItemNotFoundException ex)
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
