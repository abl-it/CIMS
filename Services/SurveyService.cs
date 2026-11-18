using System.Data;
using System.Text.Json;
using CIMS.Models;
using Dapper;

namespace CIMS.Services
{
    /// <summary>Survei kepuasan (T6-2): Dapper + stored procedure dbo.usp_Survey_* (Database/RequestSurvey.sql).</summary>
    public class SurveyService : ISurveyService
    {
        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<SurveyService> _logger;

        public SurveyService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService, ILogger<SurveyService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<ProjectSurvey?> GetByRequestAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            using var grid = await conn.QueryMultipleAsync(new CommandDefinition(
                "dbo.usp_Survey_Get", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));

            var survey = await grid.ReadFirstOrDefaultAsync<ProjectSurvey>();
            var items = (await grid.ReadAsync<ProjectSurveyItem>()).AsList();
            if (survey != null) survey.Items = items;
            return survey;
        }

        public async Task<int> SendAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            var row = await QuerySingleAsync<SendResult>("dbo.usp_Survey_Send", p, ct);
            return row.ItemCount;
        }

        public async Task<decimal> SubmitAsync(int requestId, IReadOnlyList<SurveyScoreInput> scores, string? noteForCivil,
            CancellationToken ct = default)
        {
            // Nilai kosong ikut dikirim sebagai null; SP menolak bila ada item tanpa nilai 1-10 (BR-49).
            var json = JsonSerializer.Serialize(scores.Select(s => new { id = s.Id, score = s.Score }));

            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@ScoresJson", json, DbType.String);
            p.Add("@NoteForCivil", noteForCivil, DbType.String);

            return await QuerySingleAsync<decimal>("dbo.usp_Survey_Submit", p, ct);
        }

        public async Task<PagedResult<SurveyListItem>> GetPagedAsync(string? coCode, string? category, string? surveyStatus,
            DateTime? month, string? search, string? sortBy, string? sortDir, int pageNumber, int pageSize,
            CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@CoCode", coCode, DbType.AnsiString);
            p.Add("@Category", category, DbType.AnsiString);
            p.Add("@SurveyStatus", surveyStatus, DbType.AnsiString);
            p.Add("@Month", month?.Date, DbType.Date);
            p.Add("@Search", search, DbType.String);
            p.Add("@SortBy", sortBy ?? "PeriodDate", DbType.String);
            p.Add("@SortDir", sortDir ?? "DESC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<SurveyListItem>(new CommandDefinition(
                "dbo.usp_Survey_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<SurveyListItem>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
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

        private sealed class SendResult
        {
            public int Id { get; set; }
            public int ItemCount { get; set; }
        }
    }
}
