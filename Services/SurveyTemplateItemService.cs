using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class SurveyTemplateItemService : ISurveyTemplateItemService
    {
        private const int ErrDuplicate = 50041;
        private const int ErrRequiredEmpty = 50042;
        private const int ErrNotFound = 50043;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<SurveyTemplateItemService> _logger;

        public SurveyTemplateItemService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<SurveyTemplateItemService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<PagedResult<SurveyTemplateItem>> GetPagedAsync(string? category, string? search, bool? isActive,
            string? sortBy, string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Category", category, DbType.AnsiString);
            p.Add("@Search", search, DbType.String);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@SortBy", sortBy ?? "Category", DbType.String);
            p.Add("@SortDir", sortDir ?? "ASC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<SurveyTemplateItem>(new CommandDefinition(
                "dbo.usp_SurveyTemplateItem_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<SurveyTemplateItem>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<SurveyTemplateItem?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<SurveyTemplateItem>(new CommandDefinition(
                "dbo.usp_SurveyTemplateItem_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<int> InsertAsync(SurveyTemplateItem item, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Category", item.Category, DbType.AnsiString);
            p.Add("@SortOrder", item.SortOrder, DbType.Int32);
            p.Add("@ItemText", item.ItemText, DbType.String);
            p.Add("@IsActive", item.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_SurveyTemplateItem_Insert", p, ct);
            return p.Get<int>("@NewId");
        }

        public async Task UpdateAsync(SurveyTemplateItem item, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", item.Id, DbType.Int32);
            p.Add("@Category", item.Category, DbType.AnsiString);
            p.Add("@SortOrder", item.SortOrder, DbType.Int32);
            p.Add("@ItemText", item.ItemText, DbType.String);
            p.Add("@IsActive", item.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_SurveyTemplateItem_Update", p, ct);
        }

        public async Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_SurveyTemplateItem_SetActive", p, ct);
        }

        /// <summary>Username pelaku untuk audit (CreatedBy/UpdatedBy).</summary>
        private string? ActionBy => _currentUserService.CurrentUser?.Username;

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50041-50043) ke exception bertipe.</summary>
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
                _logger.LogWarning(ex, "{Procedure}: item survei duplikat.", procedure);
                throw new SurveyTemplateItemDuplicateException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrRequiredEmpty)
            {
                _logger.LogWarning(ex, "{Procedure}: input tidak valid.", procedure);
                throw new SurveyTemplateItemValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: item survei tidak ditemukan.", procedure);
                throw new SurveyTemplateItemNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }
    }
}
