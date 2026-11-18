using System.Globalization;
using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>
    /// Dashboard dasar (PRD 9.1; 7.1 FR-01, 8.1 BR-68..BR-71, 9.4 FR-04). Matriks 5.2 "Dashboard dan Report":
    /// semua role CIMS kecuali purchasing. Lingkup data dibatasi di SP (fn_User_AllowedDepartments).
    /// </summary>
    [RoleAuthorize(CimsRoles.Adm, CimsRoles.Plan, CimsRoles.Spv, CimsRoles.Emp, CimsRoles.Kabag, CimsRoles.Mo,
        CimsRoles.Civil, CimsRoles.Fat, CimsRoles.Dgo, CimsRoles.Gm, CimsRoles.Director, CimsRoles.Administrator)]
    public class DashboardController : Controller
    {
        private static readonly string[] CoCodes = { "ABL", "NKM" };
        private static readonly string[] OverallStatuses = { OverallStatus.OnTrack, OverallStatus.AtRisk, OverallStatus.Delayed };

        /// <summary>Role yang melihat ABL dan NKM (BR-57): tampil filter Company.</summary>
        private static readonly string[] CrossCompanyRoles = { CimsRoles.Administrator, CimsRoles.Civil, CimsRoles.Director, CimsRoles.Gm };

        private readonly IDashboardService _dashboardService;
        private readonly IUserTaskService _taskService;
        private readonly ICurrentUserService _currentUserService;

        public DashboardController(IDashboardService dashboardService, IUserTaskService taskService,
            ICurrentUserService currentUserService)
        {
            _dashboardService = dashboardService;
            _taskService = taskService;
            _currentUserService = currentUserService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(DashboardViewModel query, CancellationToken ct)
        {
            Normalize(query);
            query.PageSize = Math.Clamp(query.PageSize, 1, 10);

            var result = await _dashboardService.GetProjectsAsync(query.CoCode, query.MonthDate, query.Category,
                query.OverallStatus, query.Search, query.SortBy, query.SortDir, query.Page, query.PageSize, ct);

            // Halaman melebihi total -> arahkan ke halaman terakhir.
            if (result.TotalCount > 0 && query.Page > result.TotalPages)
            {
                return RedirectToAction(nameof(Index), new
                {
                    coCode = query.ShowCompanyFilter ? query.CoCode ?? string.Empty : null,
                    month = query.Month,
                    category = query.Category,
                    overallStatus = query.OverallStatus,
                    search = query.Search,
                    sortBy = query.SortBy,
                    sortDir = query.SortDir,
                    page = result.TotalPages
                });
            }

            query.Result = result;
            query.Summary = await _dashboardService.GetSummaryAsync(query.CoCode, query.MonthDate, ct);
            query.MonthlyCost = await _dashboardService.GetMonthlyCostAsync(query.CoCode, query.MonthDate, query.Category, ct);
            query.TaskSummary = await _taskService.GetSummaryAsync(ct);
            return View(query);
        }

        /// <summary>Export tabel project aktif sesuai filter aktif (FR-04).</summary>
        [HttpGet]
        public async Task<IActionResult> Export(DashboardViewModel query, CancellationToken ct)
        {
            Normalize(query);
            var result = await _dashboardService.GetProjectsAsync(query.CoCode, query.MonthDate, query.Category,
                query.OverallStatus, query.Search, query.SortBy, query.SortDir, 1, 0, ct);

            var inv = CultureInfo.InvariantCulture;
            var monthText = query.MonthDate.ToString("MMM yyyy", inv);
            var columns = new List<ExcelExport.Column<DashboardProjectItem>>
            {
                new("Request No", x => x.RequestNo),
                new("Title", x => x.Title),
                new("Category", x => x.Category),
                new("Company", x => x.CoCode),
                new("Department", x => x.ABRV ?? x.DeptName),
                new("Status", x => RequestStatus.Label(x.Status)),
                new("Execution", x => RequestExecutionType.Label(x.ExecutionType)),
                new("Project start", x => x.ProjectStartDate, "dd mmm yyyy"),
                new("Project end", x => x.ProjectEndDate, "dd mmm yyyy"),
                new("Actual progress (%)", x => x.ProgressPercent, "0.00"),
                new("Plan progress (%)", x => x.PlanProgressPercent, "0.00"),
                new("Schedule status", x => ScheduleStatus.Label(x.ScheduleStatus)),
                new("Plan cost (IDR)", x => x.PlanCost, "#,##0"),
                new($"Estimate to {monthText} (IDR)", x => x.EstimateToMonth, "#,##0"),
                new($"Actual to {monthText} (IDR)", x => x.ActualToMonth, "#,##0"),
                new("Cost status", x => CostStatus.Label(x.CostStatus)),
                new("Overall status", x => OverallStatus.Label(x.OverallStatusOrDefault))
            };

            var filter = string.Join(" · ", new[]
            {
                "Month " + monthText,
                "Company " + (query.CoCode ?? "All"),
                query.Category != null ? "Category " + query.Category : null,
                query.OverallStatus != null ? "Overall " + OverallStatus.Label(query.OverallStatus) : null,
                !string.IsNullOrWhiteSpace(query.Search) ? "Search \"" + query.Search + "\"" : null
            }.Where(s => s != null));

            var bytes = ExcelExport.Build("Active Projects", "CIMS - Active Projects", filter, columns, result.Items);
            return File(bytes, ExcelExport.ContentType, $"CIMS-active-projects-{query.MonthDate:yyyy-MM}.xlsx");
        }

        /// <summary>Filter: Company (role lintas Company, default Company user), bulan (default bulan berjalan), whitelist.</summary>
        private void Normalize(DashboardViewModel query)
        {
            var user = _currentUserService.CurrentUser;
            query.ShowCompanyFilter = CimsRoles.HasAny(user, CrossCompanyRoles);
            if (query.ShowCompanyFilter)
            {
                // "" = semua Company; parameter tidak ada = Company user (BR-57)
                if (!Request.Query.ContainsKey("coCode")) query.CoCode = user?.CoCode;
                query.CoCode = CoCodes.FirstOrDefault(c => string.Equals(c, query.CoCode, StringComparison.OrdinalIgnoreCase));
            }
            else
            {
                query.CoCode = null;
            }

            var inv = CultureInfo.InvariantCulture;
            var today = DateTime.Today;
            query.MonthDate = DateTime.TryParseExact(query.Month, "yyyy-MM", inv, DateTimeStyles.None, out var m)
                ? m : new DateTime(today.Year, today.Month, 1);
            if (query.MonthDate > new DateTime(today.Year, today.Month, 1)) query.MonthDate = new DateTime(today.Year, today.Month, 1);
            query.Month = query.MonthDate.ToString("yyyy-MM", inv);

            query.Category = ProjectRequest.Categories.FirstOrDefault(c => string.Equals(c, query.Category, StringComparison.OrdinalIgnoreCase));
            query.OverallStatus = OverallStatuses.FirstOrDefault(s => string.Equals(s, query.OverallStatus, StringComparison.OrdinalIgnoreCase));
            query.SortBy = DashboardViewModel.AllowedSortBy.FirstOrDefault(s => string.Equals(s, query.SortBy, StringComparison.OrdinalIgnoreCase)) ?? "Overall";
            query.SortDir = string.Equals(query.SortDir, "ASC", StringComparison.OrdinalIgnoreCase) ? "ASC" : "DESC";
            if (query.Page < 1) query.Page = 1;
        }
    }
}
