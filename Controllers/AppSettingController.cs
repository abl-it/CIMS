using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>
    /// Halaman Settings: ubah nilai AppSetting (CF-02, CF-08). Hanya administrator (BR-38, matriks 5.2).
    /// Tanpa Create/Delete/paging: key dan override per Company dikelola lewat script SQL.
    /// </summary>
    [RoleAuthorize(CimsRoles.Administrator)]
    public class AppSettingController : Controller
    {
        private readonly IAppSettingService _settingService;

        public AppSettingController(IAppSettingService settingService)
        {
            _settingService = settingService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(AppSettingListViewModel query, CancellationToken ct)
        {
            query.CoCode = AppSetting.CoCodes.FirstOrDefault(
                c => string.Equals(c, query.CoCode, StringComparison.OrdinalIgnoreCase));
            query.Items = await _settingService.ListAsync(query.CoCode, ct);
            return View(query);
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string coCode, string settingKey, string? returnUrl, CancellationToken ct)
        {
            if (string.IsNullOrWhiteSpace(coCode) || string.IsNullOrWhiteSpace(settingKey)) return NotFound();

            var setting = await _settingService.GetByKeyAsync(coCode, settingKey, ct);
            if (setting == null) return NotFound();
            ViewData["ReturnUrl"] = LocalOrNull(returnUrl);
            return View(AppSettingFormViewModel.FromEntity(setting));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(AppSettingFormViewModel model, string? returnUrl, CancellationToken ct)
        {
            returnUrl = LocalOrNull(returnUrl);
            ViewData["ReturnUrl"] = returnUrl;

            // Field tampilan selalu dari database, bukan dari form.
            var setting = await _settingService.GetByKeyAsync(model.CoCode, model.SettingKey, ct);
            if (setting == null)
            {
                TempData["Error"] = "Setting not found.";
                return RedirectToAction(nameof(Index));
            }
            model.LoadDisplay(setting);

            if (!ModelState.IsValid) return View(model);

            try
            {
                await _settingService.UpdateValueAsync(model.CoCode, model.SettingKey, model.SettingValue, ct);
                TempData["Success"] = "Setting updated successfully.";
                // Kembali ke list asal (filter tetap); tanpa returnUrl -> Index.
                return returnUrl != null ? LocalRedirect(returnUrl) : RedirectToAction(nameof(Index));
            }
            catch (AppSettingValidationException ex)
            {
                // Satu-satunya input adalah Value, jadi error ditampilkan di bawah field tersebut.
                ModelState.AddModelError(nameof(model.SettingValue), ex.Message);
            }
            catch (AppSettingNotFoundException ex)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }

            return View(model);
        }

        /// <summary>returnUrl hanya dipakai bila lokal (cegah open redirect).</summary>
        private string? LocalOrNull(string? returnUrl) =>
            !string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl) ? returnUrl : null;
    }
}
