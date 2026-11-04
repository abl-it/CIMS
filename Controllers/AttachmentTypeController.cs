using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    [RoleAuthorize(CimsRoles.Administrator, CimsRoles.Civil)]
    public class AttachmentTypeController : Controller
    {
        private static readonly string[] AllowedSortBy = { "Code", "Name", "Stage", "CreatedAt" };

        private readonly IAttachmentTypeService _attachmentTypeService;

        public AttachmentTypeController(IAttachmentTypeService attachmentTypeService)
        {
            _attachmentTypeService = attachmentTypeService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(AttachmentTypeListViewModel query, CancellationToken ct)
        {
            query.Stage = AttachmentType.Stages.Select(s => s.Key).FirstOrDefault(
                s => string.Equals(s, query.Stage, StringComparison.OrdinalIgnoreCase));
            query.SortBy = AllowedSortBy.Contains(query.SortBy, StringComparer.OrdinalIgnoreCase)
                ? AllowedSortBy.First(s => s.Equals(query.SortBy, StringComparison.OrdinalIgnoreCase))
                : "Stage";
            query.SortDir = string.Equals(query.SortDir, "DESC", StringComparison.OrdinalIgnoreCase) ? "DESC" : "ASC";
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);
            if (query.Page < 1) query.Page = 1;

            var result = await _attachmentTypeService.GetPagedAsync(
                query.Stage, query.Search, query.IsActive, query.SortBy, query.SortDir, query.Page, query.PageSize, ct);

            // Halaman melebihi total -> arahkan ke halaman terakhir.
            if (result.TotalCount > 0 && query.Page > result.TotalPages)
            {
                return RedirectToAction(nameof(Index), new
                {
                    stage = query.Stage,
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
            var attachmentType = await _attachmentTypeService.GetByIdAsync(id, ct);
            if (attachmentType == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(attachmentType);
        }

        [HttpGet]
        public IActionResult Create(string? returnUrl)
        {
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(new AttachmentTypeFormViewModel());
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(AttachmentTypeFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                var newId = await _attachmentTypeService.InsertAsync(model.ToEntity(), ct);
                TempData["Success"] = "Attachment type added successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = newId });
            }
            catch (AttachmentTypeDuplicateCodeException ex)
            {
                ModelState.AddModelError(nameof(model.Code), ex.Message);
            }
            catch (AttachmentTypeValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Edit(int id, string? returnUrl, CancellationToken ct)
        {
            var attachmentType = await _attachmentTypeService.GetByIdAsync(id, ct);
            if (attachmentType == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(AttachmentTypeFormViewModel.FromEntity(attachmentType));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(int id, AttachmentTypeFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            if (id != model.Id) return BadRequest();
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;
            if (!ModelState.IsValid) return View(model);

            try
            {
                await _attachmentTypeService.UpdateAsync(model.ToEntity(), ct);
                TempData["Success"] = "Attachment type updated successfully.";
                // Kembali ke list asal (filter, sort, halaman tetap); tanpa returnUrl -> Details.
                return returnUrl != null
                    ? LocalRedirect(returnUrl)
                    : RedirectToAction(nameof(Details), new { id = model.Id });
            }
            catch (AttachmentTypeValidationException ex)
            {
                ModelState.AddModelError(string.Empty, ex.Message);
            }
            catch (AttachmentTypeNotFoundException ex)
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
                await _attachmentTypeService.SetActiveAsync(id, isActive, ct);
                TempData["Success"] = isActive ? "Attachment type activated." : "Attachment type deactivated.";
            }
            catch (AttachmentTypeNotFoundException ex)
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
