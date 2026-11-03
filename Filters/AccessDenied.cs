using CIMS.Middleware;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Filters
{
    /// <summary>Hasil penolakan akses: 403 JSON untuk AJAX/API, redirect ke Home/NotAuthorized untuk halaman MVC.</summary>
    internal static class AccessDenied
    {
        public const string Message = "Not authorized";

        public static IActionResult Json() =>
            new JsonResult(new { success = false, message = Message }) { StatusCode = StatusCodes.Status403Forbidden };

        public static IActionResult For(HttpRequest request) =>
            request.IsAjaxRequest() ? Json() : new RedirectToActionResult("NotAuthorized", "Home", null);
    }
}
