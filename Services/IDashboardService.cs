using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>Dashboard dasar (PRD 9.1). Semua data dibatasi lingkup user (fn_User_AllowedDepartments).</summary>
    public interface IDashboardService
    {
        /// <summary>Kartu CAPEX, OPEX, LVE (selalu 3 baris).</summary>
        Task<IReadOnlyList<DashboardCategorySummary>> GetSummaryAsync(string? coCode, DateTime month, CancellationToken ct = default);

        /// <summary>Estimasi vs actual per bulan project aktif (grafik); actual hanya s.d. <paramref name="month"/>.</summary>
        Task<IReadOnlyList<DashboardMonthlyCost>> GetMonthlyCostAsync(string? coCode, DateTime month, string? category,
            CancellationToken ct = default);

        /// <summary>Project aktif (In Progress + BAPP Review). <paramref name="pageSize"/> 0 = semua (export, maks. 5000).</summary>
        Task<PagedResult<DashboardProjectItem>> GetProjectsAsync(string? coCode, DateTime month, string? category,
            string? overallStatus, string? search, string? sortBy, string? sortDir, int pageNumber, int pageSize,
            CancellationToken ct = default);
    }
}
