using CIMS.Services;
using Microsoft.AspNetCore.Mvc.Filters;

namespace CIMS.Filters
{
    /// <summary>
    /// Otorisasi role untuk endpoint AJAX/API: selalu 403 JSON { success:false, message:"Tidak berwenang" }.
    /// Semantik any-of seperti <see cref="RoleAuthorizeAttribute"/>.
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
    public class RoleAuthorizeApiAttribute : ActionFilterAttribute
    {
        private readonly HashSet<string> _roles;

        public RoleAuthorizeApiAttribute(params string[] roles)
        {
            _roles = new HashSet<string>(roles, StringComparer.OrdinalIgnoreCase);
        }

        public override void OnActionExecuting(ActionExecutingContext context)
        {
            var user = context.HttpContext.RequestServices.GetRequiredService<ICurrentUserService>().CurrentUser;
            if (CimsRoles.HasAny(user, _roles)) return;

            var logger = context.HttpContext.RequestServices.GetRequiredService<ILogger<RoleAuthorizeApiAttribute>>();
            logger.LogWarning("Akses API ditolak untuk {Username} pada {Path}; role diizinkan: {Roles}.",
                user?.Username, context.HttpContext.Request.Path.Value, string.Join(",", _roles));

            context.Result = AccessDenied.Json();
        }
    }
}
