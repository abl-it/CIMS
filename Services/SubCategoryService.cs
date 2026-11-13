using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class SubCategoryService : ISubCategoryService
    {
        private const int ErrDuplicateCode = 50061;
        private const int ErrRequiredEmpty = 50062;
        private const int ErrNotFound = 50063;
        private const int ErrDuplicateName = 50064;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<SubCategoryService> _logger;

        public SubCategoryService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<SubCategoryService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<PagedResult<SubCategory>> GetPagedAsync(string? category, string? search, bool? isActive,
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
            var items = (await conn.QueryAsync<SubCategory>(new CommandDefinition(
                "dbo.usp_SubCategory_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<SubCategory>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<SubCategory?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<SubCategory>(new CommandDefinition(
                "dbo.usp_SubCategory_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<IReadOnlyList<SubCategory>> GetActiveByCategoryAsync(string category, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Category", category, DbType.AnsiString);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<SubCategory>(new CommandDefinition(
                "dbo.usp_SubCategory_GetActiveByCategory", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<int> InsertAsync(SubCategory subCategory, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Category", subCategory.Category, DbType.AnsiString);
            p.Add("@Code", subCategory.Code, DbType.AnsiString);
            p.Add("@Name", subCategory.Name, DbType.String);
            p.Add("@SortOrder", subCategory.SortOrder, DbType.Int32);
            p.Add("@IsActive", subCategory.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_SubCategory_Insert", p, ct);
            return p.Get<int>("@NewId");
        }

        public async Task UpdateAsync(SubCategory subCategory, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", subCategory.Id, DbType.Int32);
            p.Add("@Name", subCategory.Name, DbType.String);
            p.Add("@SortOrder", subCategory.SortOrder, DbType.Int32);
            p.Add("@IsActive", subCategory.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_SubCategory_Update", p, ct);
        }

        public async Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_SubCategory_SetActive", p, ct);
        }

        /// <summary>Username pelaku untuk audit (CreatedBy/UpdatedBy).</summary>
        private string? ActionBy => _currentUserService.CurrentUser?.Username;

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50061-50064) ke exception bertipe.</summary>
        private async Task ExecuteAsync(string procedure, DynamicParameters parameters, CancellationToken ct)
        {
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    procedure, parameters, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (SqlException ex) when (ex.Number == ErrDuplicateCode)
            {
                _logger.LogWarning(ex, "{Procedure}: Code sub-kategori duplikat.", procedure);
                throw new SubCategoryDuplicateCodeException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrDuplicateName)
            {
                _logger.LogWarning(ex, "{Procedure}: nama sub-kategori duplikat pada kategori yang sama.", procedure);
                throw new SubCategoryDuplicateNameException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrRequiredEmpty)
            {
                _logger.LogWarning(ex, "{Procedure}: input tidak valid.", procedure);
                throw new SubCategoryValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: sub-kategori tidak ditemukan.", procedure);
                throw new SubCategoryNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }
    }
}
