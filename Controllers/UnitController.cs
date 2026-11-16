using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>Master Satuan (MD-04). Master Data (C) = administrator dan civil (matriks PRD 5.2).</summary>
    [RoleAuthorize(CimsRoles.Administrator, CimsRoles.Civil)]
    public class UnitController : Controller
    {
        private static readonly string[] AllowedSortBy = { "Name", "CreatedAt" };

        private readonly IUnitService _unitService;

        public UnitController(IUnitService unitService)
        {
            _unitService = unitService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(UnitListViewModel query, CancellationToken ct)
        {
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "Name";
            query.SortDir = string.Equals(query.SortDir, "DESC", StringComparison.OrdinalIgnoreCase) ? "DESC" : "ASC";
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _unitService.GetPagedAsync(
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
            var unit = await _unitService.GetByIdAsync(id, ct);
            if (unit == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(unit);
        }

        [HttpGet]
        public IActionResult Create(string? returnUrl)
        {
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(new UnitFormViewModel());
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(UnitFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                var newId = await _unitService.InsertAsync(model.ToEntity(), ct);
                TempData["Success"] = "Unit added successfully.";
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = newId });
            }
            catch (UnitDuplicateNameException ex)
            {
                ModelState.AddModelError(nameof(model.Name), ex.Message);
            }
            catch (UnitValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Edit(int id, string? returnUrl, CancellationToken ct)
        {
            var unit = await _unitService.GetByIdAsync(id, ct);
            if (unit == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(UnitFormViewModel.FromEntity(unit));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(int id, UnitFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            if (id != model.Id) return BadRequest();
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                await _unitService.UpdateAsync(model.ToEntity(), ct);
                TempData["Success"] = "Unit updated successfully.";
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = model.Id });
            }
            catch (UnitDuplicateNameException ex)
            {
                ModelState.AddModelError(nameof(model.Name), ex.Message);
            }
            catch (UnitValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }
            catch (UnitNotFoundException ex)
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
                await _unitService.SetActiveAsync(id, isActive, ct);
                TempData["Success"] = isActive ? "Unit activated." : "Unit deactivated.";
            }
            catch (UnitNotFoundException ex)
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
