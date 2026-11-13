using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace CIMS.Controllers
{
    public class HomeController : Controller
    {
        private readonly ILogger<HomeController> _logger;
        private readonly IConfiguration _configuration;
        private readonly IUserTaskService _taskService;

        public HomeController(ILogger<HomeController> logger, IConfiguration configuration, IUserTaskService taskService)
        {
            _logger = logger;
            _configuration = configuration;
            _taskService = taskService;
        }

        /// <summary>Dashboard: shortcut Tugas Saya per jenis (FR-01).</summary>
        [AllowAllRoles]
        public async Task<IActionResult> Index(CancellationToken ct)
        {
            return View(new HomeIndexViewModel { TaskSummary = await _taskService.GetSummaryAsync(ct) });
        }

        [AllowAllRoles]
        public IActionResult Privacy()
        {
            return View();
        }

        [HttpGet]
        public IActionResult NotAuthorized()
        {
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public IActionResult LogOut()
        {
            HttpContext.Session.Clear();
            Response.Cookies.Delete(".CIMS.Session");
            Response.Cookies.Delete(".Portal.Session");

            var loginUrl = _configuration["SSO:PublicLogin"];
            return string.IsNullOrWhiteSpace(loginUrl) ? Redirect("~/") : Redirect(loginUrl);
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }
    }
}
