using CIMS.Services;
using Microsoft.AspNetCore.Mvc.Filters;

namespace CIMS.Filters
{
    /// <summary>
    /// Otorisasi role untuk action/controller MVC. Semantik any-of: lolos bila SALAH SATU role user ada di daftar.
    /// Membaca role dari ICurrentUserService (dimuat sekali per request oleh ProfileAttribute), tanpa query ulang.
    /// Gagal: Home/NotAuthorized (request AJAX: 403 JSON).
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
    public class RoleAuthorizeAttribute : ActionFilterAttribute
    {
        private readonly HashSet<string> _roles;

        public RoleAuthorizeAttribute(params string[] roles)
        {
            _roles = new HashSet<string>(roles, StringComparer.OrdinalIgnoreCase);
        }

        public override void OnActionExecuting(ActionExecutingContext context)
        {
            var user = context.HttpContext.RequestServices.GetRequiredService<ICurrentUserService>().CurrentUser;
            if (CimsRoles.HasAny(user, _roles)) return;

            var logger = context.HttpContext.RequestServices.GetRequiredService<ILogger<RoleAuthorizeAttribute>>();
            logger.LogWarning("Akses ditolak untuk {Username} pada {Path}; role diizinkan: {Roles}.",
                user?.Username, context.HttpContext.Request.Path.Value, string.Join(",", _roles));

            context.Result = AccessDenied.For(context.HttpContext.Request);
        }
    }
}
