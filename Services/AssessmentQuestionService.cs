using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class AssessmentQuestionService : IAssessmentQuestionService
    {
        private const int ErrDuplicate = 50031;
        private const int ErrRequiredEmpty = 50032;
        private const int ErrNotFound = 50033;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<AssessmentQuestionService> _logger;

        public AssessmentQuestionService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<AssessmentQuestionService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<PagedResult<AssessmentQuestion>> GetPagedAsync(string? search, bool? isActive, string? sortBy,
            string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Search", search, DbType.String);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@SortBy", sortBy ?? "SortOrder", DbType.String);
            p.Add("@SortDir", sortDir ?? "ASC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<AssessmentQuestion>(new CommandDefinition(
                "dbo.usp_AssessmentQuestion_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<AssessmentQuestion>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<AssessmentQuestion?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<AssessmentQuestion>(new CommandDefinition(
                "dbo.usp_AssessmentQuestion_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<int> InsertAsync(AssessmentQuestion question, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@SortOrder", question.SortOrder, DbType.Int32);
            p.Add("@QuestionText", question.QuestionText, DbType.String);
            p.Add("@IsActive", question.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_AssessmentQuestion_Insert", p, ct);
            return p.Get<int>("@NewId");
        }

        public async Task UpdateAsync(AssessmentQuestion question, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", question.Id, DbType.Int32);
            p.Add("@SortOrder", question.SortOrder, DbType.Int32);
            p.Add("@QuestionText", question.QuestionText, DbType.String);
            p.Add("@IsActive", question.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_AssessmentQuestion_Update", p, ct);
        }

        public async Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_AssessmentQuestion_SetActive", p, ct);
        }

        /// <summary>Username pelaku untuk audit (CreatedBy/UpdatedBy).</summary>
        private string? ActionBy => _currentUserService.CurrentUser?.Username;

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50031-50033) ke exception bertipe.</summary>
        private async Task ExecuteAsync(string procedure, DynamicParameters parameters, CancellationToken ct)
        {
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    procedure, parameters, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (SqlException ex) when (ex.Number == ErrDuplicate)
            {
                _logger.LogWarning(ex, "{Procedure}: pertanyaan duplikat.", procedure);
                throw new AssessmentQuestionDuplicateException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrRequiredEmpty)
            {
                _logger.LogWarning(ex, "{Procedure}: input tidak valid.", procedure);
                throw new AssessmentQuestionValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: pertanyaan tidak ditemukan.", procedure);
                throw new AssessmentQuestionNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }
    }
}
