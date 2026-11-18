using System.Data;
using CIMS.Models;
using Dapper;

namespace CIMS.Services
{
    /// <summary>BAPP online (T6-1): Dapper + stored procedure dbo.usp_Bapp_* (Database/RequestBapp.sql).</summary>
    public class BappService : IBappService
    {
        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<BappService> _logger;

        public BappService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService, ILogger<BappService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<IReadOnlyList<ProjectBapp>> GetByRequestAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            using var grid = await conn.QueryMultipleAsync(new CommandDefinition(
                "dbo.usp_Bapp_GetByRequest", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));

            var bapps = (await grid.ReadAsync<ProjectBapp>()).AsList();
            var steps = (await grid.ReadAsync<BappStepItem>()).AsList();

            foreach (var b in bapps)
                b.Steps = steps.Where(s => s.Round == b.Round).OrderBy(s => s.StepOrder).ToList();

            return bapps;
        }

        public async Task<(string Status, string? BappNo)> IssueAsync(int requestId, BappInput input, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@BappDate", input.BappDate?.Date, DbType.Date);
            p.Add("@ScopeOfWork", input.ScopeOfWork, DbType.String);
            p.Add("@Remarks", input.Remarks, DbType.String);

            var row = await QuerySingleAsync<IssueResult>("dbo.usp_Bapp_Issue", p, ct);
            return (row.Status, row.BappNo);
        }

        public async Task<string> ApprovalActAsync(int requestId, int stepId, string action, string? remarks, BappApprovalInput input,
            CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@StepId", stepId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Action", action, DbType.AnsiString);
            p.Add("@Remarks", remarks, DbType.String);
            p.Add("@InspectionResult", input.InspectionResult, DbType.AnsiString);
            p.Add("@InspectionNotes", input.InspectionNotes, DbType.String);
            p.Add("@Confirm", input.Confirm, DbType.Boolean);

            return await QuerySingleAsync<string>("dbo.usp_Bapp_ApprovalAct", p, ct);
        }

        public async Task<BappPrintViewModel?> GetPrintDataAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            using var grid = await conn.QueryMultipleAsync(new CommandDefinition(
                "dbo.usp_Bapp_GetPrintData", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));

            var header = await grid.ReadFirstOrDefaultAsync<BappPrintHeader>();
            var signatures = (await grid.ReadAsync<BappSignature>()).AsList();
            var items = (await grid.ReadAsync<BappPrintItem>()).AsList();
            var photos = (await grid.ReadAsync<BappPhoto>()).AsList();
            if (header == null) return null;

            return new BappPrintViewModel { Header = header, Signatures = signatures, Items = items, Photos = photos };
        }

        private async Task<T> QuerySingleAsync<T>(string procedure, DynamicParameters parameters, CancellationToken ct)
        {
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                return await conn.QuerySingleAsync<T>(new CommandDefinition(
                    procedure, parameters, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        private string Username => _currentUserService.CurrentUser?.Username
            ?? throw new InvalidOperationException("CurrentUser belum dimuat.");

        private sealed class IssueResult
        {
            public string Status { get; set; } = string.Empty;
            public string? BappNo { get; set; }
        }
    }
}
