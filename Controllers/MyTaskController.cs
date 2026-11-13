using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>
    /// Tugas Saya (T2-4; FR-01). Hanya-baca: setiap user CIMS melihat tugasnya sendiri; isi dan lingkup
    /// ditentukan dbo.fn_User_Tasks (role langkah, lingkup, Company, requester). Aksi dilakukan di halaman tujuan.
    /// </summary>
    public class MyTaskController : Controller
    {
        private readonly IUserTaskService _taskService;

        public MyTaskController(IUserTaskService taskService)
        {
            _taskService = taskService;
        }

        [HttpGet]
        [AllowAllRoles]
        public async Task<IActionResult> Index(string? type, CancellationToken ct)
        {
            // Jenis di luar whitelist dianggap "semua"
            type = UserTaskType.IsValid(type) ? type : null;

            return View(new UserTaskListViewModel
            {
                Type = type,
                Summary = await _taskService.GetSummaryAsync(ct),
                Items = await _taskService.GetListAsync(type, ct)
            });
        }
    }
}
