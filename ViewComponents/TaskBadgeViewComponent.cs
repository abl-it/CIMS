using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.ViewComponents
{
    /// <summary>
    /// Badge jumlah tugas di header (FR-02); angka = total usp_Task_GetSummary (sama dengan Tugas Saya).
    /// Gagal memuat tidak boleh merusak layout: dicatat ke log dan badge disembunyikan.
    /// </summary>
    public class TaskBadgeViewComponent : ViewComponent
    {
        private readonly IUserTaskService _taskService;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<TaskBadgeViewComponent> _logger;

        public TaskBadgeViewComponent(IUserTaskService taskService, ICurrentUserService currentUserService,
            ILogger<TaskBadgeViewComponent> logger)
        {
            _taskService = taskService;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<IViewComponentResult> InvokeAsync()
        {
            // Halaman tanpa user (NotAuthorized, Error): tanpa badge
            if (_currentUserService.CurrentUser == null)
                return Content(string.Empty);

            try
            {
                var summary = await _taskService.GetSummaryAsync(HttpContext.RequestAborted);
                return View(summary.Sum(s => s.TaskCount));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "Gagal memuat jumlah Tugas Saya untuk badge header.");
                return Content(string.Empty);
            }
        }
    }
}
