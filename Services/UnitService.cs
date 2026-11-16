using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class UnitService : IUnitService
    {
        private const int ErrDuplicateName = 50091;
        private const int ErrValidation = 50092;
        private const int ErrNotFound = 50093;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<UnitService> _logger;

        public UnitService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<UnitService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<PagedResult<Unit>> GetPagedAsync(string? search, bool? isActive, string? sortBy, string? sortDir,
            int pageNumber, int pageSize, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Search", search, DbType.String);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@SortBy", sortBy ?? "Name", DbType.String);
            p.Add("@SortDir", sortDir ?? "ASC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<Unit>(new CommandDefinition(
                "dbo.usp_Unit_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<Unit>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<Unit?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<Unit>(new CommandDefinition(
                "dbo.usp_Unit_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<IReadOnlyList<UnitOption>> GetActiveAsync(CancellationToken ct = default)
        {
            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<UnitOption>(new CommandDefinition(
                "dbo.usp_Unit_GetActive", commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<int> InsertAsync(Unit unit, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Name", unit.Name, DbType.String);
            p.Add("@Description", unit.Description, DbType.String);
            p.Add("@IsActive", unit.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_Unit_Insert", p, ct);
            return p.Get<int>("@NewId");
        }

        public async Task UpdateAsync(Unit unit, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", unit.Id, DbType.Int32);
            p.Add("@Name", unit.Name, DbType.String);
            p.Add("@Description", unit.Description, DbType.String);
            p.Add("@IsActive", unit.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_Unit_Update", p, ct);
        }

        public async Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_Unit_SetActive", p, ct);
        }

        /// <summary>Username pelaku untuk audit (CreatedBy/UpdatedBy).</summary>
        private string? ActionBy => _currentUserService.CurrentUser?.Username;

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50091-50093) ke exception bertipe.</summary>
        private async Task ExecuteAsync(string procedure, DynamicParameters parameters, CancellationToken ct)
        {
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    procedure, parameters, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (SqlException ex) when (ex.Number == ErrDuplicateName)
            {
                _logger.LogWarning(ex, "{Procedure}: nama satuan duplikat.", procedure);
                throw new UnitDuplicateNameException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrValidation)
            {
                _logger.LogWarning(ex, "{Procedure}: input wajib kosong / tidak valid.", procedure);
                throw new UnitValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: data satuan tidak ditemukan.", procedure);
                throw new UnitNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }
    }
}
