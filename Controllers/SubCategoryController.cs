using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    [RoleAuthorize(CimsRoles.Administrator, CimsRoles.Civil)]
    public class SubCategoryController : Controller
    {
        private static readonly string[] AllowedSortBy = { "Category", "SortOrder", "Code", "Name", "CreatedAt" };

        private readonly ISubCategoryService _subCategoryService;

        public SubCategoryController(ISubCategoryService subCategoryService)
        {
            _subCategoryService = subCategoryService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(SubCategoryListViewModel query, CancellationToken ct)
        {
            query.Category = SubCategory.Categories.FirstOrDefault(
                c => string.Equals(c, query.Category, StringComparison.OrdinalIgnoreCase));
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "Category";
            query.SortDir = string.Equals(query.SortDir, "DESC", StringComparison.OrdinalIgnoreCase) ? "DESC" : "ASC";
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _subCategoryService.GetPagedAsync(
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
            var subCategory = await _subCategoryService.GetByIdAsync(id, ct);
            if (subCategory == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(subCategory);
        }

        [HttpGet]
        public IActionResult Create(string? category, string? returnUrl)
        {
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            // Kategori dari filter list (bila ada) dipakai sebagai nilai awal.
            var initial = SubCategory.Categories.FirstOrDefault(
                c => string.Equals(c, category, StringComparison.OrdinalIgnoreCase)) ?? string.Empty;
            return View(new SubCategoryFormViewModel { Category = initial });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(SubCategoryFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                var newId = await _subCategoryService.InsertAsync(model.ToEntity(), ct);
                TempData["Success"] = "Sub-category added successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = newId });
            }
            catch (SubCategoryDuplicateCodeException ex)
            {
                ModelState.AddModelError(nameof(model.Code), ex.Message);
            }
            catch (SubCategoryDuplicateNameException ex)
            {
                ModelState.AddModelError(nameof(model.Name), ex.Message);
            }
            catch (SubCategoryValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Edit(int id, string? returnUrl, CancellationToken ct)
        {
            var subCategory = await _subCategoryService.GetByIdAsync(id, ct);
            if (subCategory == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(SubCategoryFormViewModel.FromEntity(subCategory));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(int id, SubCategoryFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            if (id != model.Id) return BadRequest();
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;

            // Code dan Category hanya tampil saat Edit; ambil dari database agar validasi & tampilan konsisten.
            var existing = await _subCategoryService.GetByIdAsync(id, ct);
            if (existing == null)
            {
                TempData["Error"] = "Sub-category not found.";
                return RedirectToAction(nameof(Index));
            }
            model.Code = existing.Code;
            model.Category = existing.Category;
            ModelState.Remove(nameof(model.Code));
            ModelState.Remove(nameof(model.Category));

            if (!ModelState.IsValid) return View(model);

            try
            {
                await _subCategoryService.UpdateAsync(model.ToEntity(), ct);
                TempData["Success"] = "Sub-category updated successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = model.Id });
            }
            catch (SubCategoryDuplicateNameException ex)
            {
                ModelState.AddModelError(nameof(model.Name), ex.Message);
            }
            catch (SubCategoryValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }
            catch (SubCategoryNotFoundException ex)
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
                await _subCategoryService.SetActiveAsync(id, isActive, ct);
                TempData["Success"] = isActive ? "Sub-category activated." : "Sub-category deactivated.";
            }
            catch (SubCategoryNotFoundException ex)
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
