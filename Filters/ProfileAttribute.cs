using CIMS.Middleware;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace CIMS.Filters
{
    /// <summary>
    /// Filter global: memuat CurrentUser sekali per request dari Session["Username"].
    /// User yang belum ada di home..users diarahkan ke Home/NotAuthorized (403 JSON untuk AJAX).
    /// </summary>
    public class ProfileAttribute : ActionFilterAttribute
    {
        private static readonly string[] ExcludedHomeActions = { "NotAuthorized", "Error", "LogOut" };

        private readonly IAuthService _authService;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<ProfileAttribute> _logger;

        public ProfileAttribute(IAuthService authService, ICurrentUserService currentUserService, ILogger<ProfileAttribute> logger)
        {
            _authService = authService;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public override async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
        {
            var controller = context.RouteData.Values["controller"]?.ToString();
            var action = context.RouteData.Values["action"]?.ToString();

            // Hindari loop redirect.
            if (string.Equals(controller, "Home", StringComparison.OrdinalIgnoreCase)
                && ExcludedHomeActions.Contains(action, StringComparer.OrdinalIgnoreCase))
            {
                await next();
                return;
            }

            var http = context.HttpContext;
            var username = http.Session.GetString("Username");
            var user = string.IsNullOrWhiteSpace(username)
                ? null
                : await _authService.GetUserByUsernameAsync(username, http.RequestAborted);

            if (user == null)
            {
                _logger.LogWarning("User {Username} tidak terdaftar di home..users.", username);

                if (http.Request.IsAjaxRequest())
                {
                    context.Result = new JsonResult(new { success = false, message = "Anda tidak berwenang" })
                    {
                        StatusCode = StatusCodes.Status403Forbidden
                    };
                }
                else
                {
                    context.Result = new RedirectToActionResult("NotAuthorized", "Home", null);
                }
                return;
            }

            // Role hanya untuk tampilan: kegagalan memuat role tidak boleh memblokir akses.
            try
            {
                user.Roles = (await _authService.GetUserRolesAsync(user.Username, http.RequestAborted)).ToList();
            }
            catch (Exception ex) when (!http.RequestAborted.IsCancellationRequested)
            {
                _logger.LogError(ex, "Gagal memuat role user {Username}.", user.Username);
            }

            _currentUserService.CurrentUser = user;
            await next();
        }
    }
}
