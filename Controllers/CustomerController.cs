using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    public class CustomerController : Controller
    {
        private static readonly string[] AllowedSortBy = { "Code", "Name", "CreatedAt" };

        private readonly ICustomerService _customerService;

        public CustomerController(ICustomerService customerService)
        {
            _customerService = customerService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(CustomerListViewModel query, CancellationToken ct)
        {
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "Code";
            query.SortDir = string.Equals(query.SortDir, "DESC", StringComparison.OrdinalIgnoreCase) ? "DESC" : "ASC";
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _customerService.GetPagedAsync(
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
        public async Task<IActionResult> Details(int id, CancellationToken ct)
        {
            var customer = await _customerService.GetByIdAsync(id, ct);
            if (customer == null) return NotFound();
            return View(customer);
        }

        [HttpGet]
        public IActionResult Create() => View(new CustomerFormViewModel());

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(CustomerFormViewModel model, CancellationToken ct)
        {
            if (!ModelState.IsValid) return View(model);

            try
            {
                var newId = await _customerService.InsertAsync(model.ToEntity(), ct);
                TempData["Success"] = "Customer berhasil ditambahkan.";
                return RedirectToAction(nameof(Details), new { id = newId });
            }
            catch (CustomerDuplicateCodeException ex)
            {
                ModelState.AddModelError(nameof(model.Code), ex.Message);
            }
            catch (CustomerValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Edit(int id, CancellationToken ct)
        {
            var customer = await _customerService.GetByIdAsync(id, ct);
            if (customer == null) return NotFound();
            return View(CustomerFormViewModel.FromEntity(customer));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(int id, CustomerFormViewModel model, CancellationToken ct)
        {
            if (id != model.Id) return BadRequest();
            if (!ModelState.IsValid) return View(model);

            try
            {
                await _customerService.UpdateAsync(model.ToEntity(), ct);
                TempData["Success"] = "Customer berhasil diperbarui.";
                return RedirectToAction(nameof(Details), new { id = model.Id });
            }
            catch (CustomerDuplicateCodeException ex)
            {
                ModelState.AddModelError(nameof(model.Code), ex.Message);
            }
            catch (CustomerValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }
            catch (CustomerNotFoundException ex)
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
                await _customerService.SetActiveAsync(id, isActive, ct);
                TempData["Success"] = isActive ? "Customer diaktifkan kembali." : "Customer dinonaktifkan.";
            }
            catch (CustomerNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
                return LocalRedirect(returnUrl);

            return RedirectToAction(nameof(Index));
        }
    }
}
