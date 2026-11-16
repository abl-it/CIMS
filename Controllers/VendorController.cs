using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>Master Vendor (MD-03). Pengelola: administrator, civil, purchasing (Purchasing memilih vendor di kontrak, BR-11).</summary>
    [RoleAuthorize(CimsRoles.Administrator, CimsRoles.Civil, CimsRoles.Purchasing)]
    public class VendorController : Controller
    {
        private static readonly string[] AllowedSortBy = { "Code", "Name", "CreatedAt" };

        private readonly IVendorService _vendorService;

        public VendorController(IVendorService vendorService)
        {
            _vendorService = vendorService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(VendorListViewModel query, CancellationToken ct)
        {
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "Name";
            query.SortDir = string.Equals(query.SortDir, "DESC", StringComparison.OrdinalIgnoreCase) ? "DESC" : "ASC";
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _vendorService.GetPagedAsync(
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
            var vendor = await _vendorService.GetByIdAsync(id, ct);
            if (vendor == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(vendor);
        }

        [HttpGet]
        public IActionResult Create(string? returnUrl)
        {
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(new VendorFormViewModel());
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(VendorFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                var newId = await _vendorService.InsertAsync(model.ToEntity(), ct);
                TempData["Success"] = "Vendor added successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = newId });
            }
            catch (VendorDuplicateCodeException ex)
            {
                ModelState.AddModelError(nameof(model.Code), ex.Message);
            }
            catch (VendorDuplicateErpNoException ex)
            {
                ModelState.AddModelError(nameof(model.ErpVendorNo), ex.Message);
            }
            catch (VendorValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Edit(int id, string? returnUrl, CancellationToken ct)
        {
            var vendor = await _vendorService.GetByIdAsync(id, ct);
            if (vendor == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(VendorFormViewModel.FromEntity(vendor));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(int id, VendorFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            if (id != model.Id) return BadRequest();
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                await _vendorService.UpdateAsync(model.ToEntity(), ct);
                TempData["Success"] = "Vendor updated successfully.";
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = model.Id });
            }
            catch (VendorDuplicateCodeException ex)
            {
                ModelState.AddModelError(nameof(model.Code), ex.Message);
            }
            catch (VendorDuplicateErpNoException ex)
            {
                ModelState.AddModelError(nameof(model.ErpVendorNo), ex.Message);
            }
            catch (VendorValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }
            catch (VendorNotFoundException ex)
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
                await _vendorService.SetActiveAsync(id, isActive, ct);
                TempData["Success"] = isActive ? "Vendor activated." : "Vendor deactivated.";
            }
            catch (VendorNotFoundException ex)
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
