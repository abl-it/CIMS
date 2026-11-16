using System.Data;
using CIMS.Models;
using Dapper;

namespace CIMS.Services
{
    public class DashboardService : IDashboardService
    {
        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;

        public DashboardService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
        }

        public async Task<IReadOnlyList<DashboardCategorySummary>> GetSummaryAsync(string? coCode, DateTime month,
            CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@CoCode", coCode, DbType.AnsiString);
            p.Add("@Month", month.Date, DbType.Date);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<DashboardCategorySummary>(new CommandDefinition(
                "dbo.usp_Dashboard_GetSummary", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<IReadOnlyList<DashboardMonthlyCost>> GetMonthlyCostAsync(string? coCode, DateTime month,
            string? category, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@CoCode", coCode, DbType.AnsiString);
            p.Add("@Month", month.Date, DbType.Date);
            p.Add("@Category", category, DbType.AnsiString);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<DashboardMonthlyCost>(new CommandDefinition(
                "dbo.usp_Dashboard_GetMonthlyCost", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<PagedResult<DashboardProjectItem>> GetProjectsAsync(string? coCode, DateTime month, string? category,
            string? overallStatus, string? search, string? sortBy, string? sortDir, int pageNumber, int pageSize,
            CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@CoCode", coCode, DbType.AnsiString);
            p.Add("@Month", month.Date, DbType.Date);
            p.Add("@Category", category, DbType.AnsiString);
            p.Add("@OverallStatus", overallStatus, DbType.AnsiString);
            p.Add("@Search", search, DbType.String);
            p.Add("@SortBy", sortBy ?? "Overall", DbType.String);
            p.Add("@SortDir", sortDir ?? "DESC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<DashboardProjectItem>(new CommandDefinition(
                "dbo.usp_Dashboard_GetProjects", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<DashboardProjectItem>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        private string Username => _currentUserService.CurrentUser?.Username
            ?? throw new InvalidOperationException("CurrentUser belum dimuat.");
    }
}
