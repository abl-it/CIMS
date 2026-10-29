using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.ViewComponents
{
    /// <summary>Blok user di header. Membaca ICurrentUserService (tanpa query database).</summary>
    public class ProfileViewComponent : ViewComponent
    {
        private readonly ICurrentUserService _currentUserService;
        private readonly IConfiguration _configuration;

        public ProfileViewComponent(ICurrentUserService currentUserService, IConfiguration configuration)
        {
            _currentUserService = currentUserService;
            _configuration = configuration;
        }

        public IViewComponentResult Invoke()
        {
            return View(new ProfileViewModel
            {
                User = _currentUserService.CurrentUser,
                PortalHomeUrl = _configuration["SSO:PortalHomeUrl"]
            });
        }
    }
}
