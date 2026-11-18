using System.Globalization;
using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>
    /// Halaman User Satisfaction (T6-2; BR-92, FR-04). Matriks 5.2 baris Survei: kabag (dept sendiri), mo (grup),
    /// civil, gm, director, administrator. Lingkup data dibatasi di SP (fn_User_AllowedDepartments + fn_User_CanSeeSurvey).
    /// </summary>
    [RoleAuthorize(CimsRoles.Kabag, CimsRoles.Mo, CimsRoles.Civil, CimsRoles.Gm, CimsRoles.Director, CimsRoles.Administrator)]
    public class SurveyController : Controller
    {
        private static readonly string[] CoCodes = { "ABL", "NKM" };

        /// <summary>Role yang melihat ABL dan NKM (BR-57): tampil filter Company.</summary>
        private static readonly string[] CrossCompanyRoles = { CimsRoles.Administrator, CimsRoles.Civil, CimsRoles.Director, CimsRoles.Gm };

        private const int ExportMaxRows = 5000;

        private readonly ISurveyService _surveyService;
        private readonly ICurrentUserService _currentUserService;

        public SurveyController(ISurveyService surveyService, ICurrentUserService currentUserService)
        {
            _surveyService = surveyService;
            _currentUserService = currentUserService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(SurveyListViewModel query, CancellationToken ct)
        {
            Normalize(query);
            query.PageSize = Math.Clamp(query.PageSize, 1, 50);

            var result = await _surveyService.GetPagedAsync(query.CoCode, query.Category, query.SurveyStatus, query.MonthDate,
                query.Search, query.SortBy, query.SortDir, query.Page, query.PageSize, ct);

            // Halaman melebihi total -> arahkan ke halaman terakhir.
            if (result.TotalCount > 0 && query.Page > result.TotalPages)
            {
                return RedirectToAction(nameof(Index), new
                {
                    coCode = query.ShowCompanyFilter ? query.CoCode ?? string.Empty : null,
                    category = query.Category,
                    surveyStatus = query.SurveyStatus,
                    month = query.Month,
                    search = query.Search,
                    sortBy = query.SortBy,
                    sortDir = query.SortDir,
                    page = result.TotalPages
                });
            }

            query.Result = result;
            return View(query);
        }

        /// <summary>Export daftar survei sesuai filter aktif (FR-04; maks. 5000 baris).</summary>
        [HttpGet]
        public async Task<IActionResult> Export(SurveyListViewModel query, CancellationToken ct)
        {
            Normalize(query);
            var result = await _surveyService.GetPagedAsync(query.CoCode, query.Category, query.SurveyStatus, query.MonthDate,
                query.Search, query.SortBy, query.SortDir, 1, ExportMaxRows, ct);

            var columns = new List<ExcelExport.Column<SurveyListItem>>
            {
                new("Request No", x => x.RequestNo),
                new("Title", x => x.Title),
                new("Category", x => x.Category),
                new("Company", x => x.CoCode),
                new("Department", x => x.ABRV ?? x.DeptName),
                new("Survey status", x => SurveyStatus.Label(x.SurveyStatus)),
                new("Closed", x => x.ClosedAt, "dd mmm yyyy"),
                new("Sent", x => x.SentAt, "dd mmm yyyy"),
                new("Submitted", x => x.SubmittedAt, "dd mmm yyyy"),
                new("Submitted by", x => x.SubmittedByName ?? x.SubmittedBy),
                new("Score (%)", x => x.ScorePercent, "0.00"),
                new("Note for Civil", x => x.NoteForCivil)
            };

            var inv = CultureInfo.InvariantCulture;
            var filter = string.Join(" · ", new[]
            {
                "Company " + (query.CoCode ?? "All"),
                query.MonthDate != null ? "Month " + query.MonthDate.Value.ToString("MMM yyyy", inv) : null,
                query.Category != null ? "Category " + query.Category : null,
                query.SurveyStatus != null ? "Status " + SurveyStatus.Label(query.SurveyStatus) : null,
                !string.IsNullOrWhiteSpace(query.Search) ? "Search \"" + query.Search + "\"" : null
            }.Where(s => s != null));

            var bytes = ExcelExport.Build("User Satisfaction", "CIMS - User Satisfaction", filter, columns, result.Items);
            return File(bytes, ExcelExport.ContentType, $"CIMS-user-satisfaction-{DateTime.Now:yyyyMMdd-HHmm}.xlsx");
        }

        /// <summary>Filter: Company (role lintas Company, default Company user), bulan opsional, whitelist.</summary>
        private void Normalize(SurveyListViewModel query)
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
            query.MonthDate = DateTime.TryParseExact(query.Month, "yyyy-MM", inv, DateTimeStyles.None, out var m) ? m : null;
            query.Month = query.MonthDate?.ToString("yyyy-MM", inv);

            query.Category = ProjectRequest.Categories.FirstOrDefault(c => string.Equals(c, query.Category, StringComparison.OrdinalIgnoreCase));
            query.SurveyStatus = SurveyStatus.All.FirstOrDefault(s => string.Equals(s, query.SurveyStatus, StringComparison.OrdinalIgnoreCase));
            query.SortBy = SurveyListViewModel.AllowedSortBy.FirstOrDefault(s => string.Equals(s, query.SortBy, StringComparison.OrdinalIgnoreCase)) ?? "PeriodDate";
            query.SortDir = string.Equals(query.SortDir, "ASC", StringComparison.OrdinalIgnoreCase) ? "ASC" : "DESC";
            if (query.Page < 1) query.Page = 1;
        }
    }
}
