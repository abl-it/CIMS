using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class LocationService : ILocationService
    {
        private const int ErrDuplicateName = 50011;
        private const int ErrRequiredEmpty = 50012;
        private const int ErrNotFound = 50013;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<LocationService> _logger;

        public LocationService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<LocationService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<PagedResult<Location>> GetPagedAsync(string? coCode, string? search, bool? isActive,
            string? sortBy, string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@CoCode", coCode, DbType.AnsiString);
            p.Add("@Search", search, DbType.String);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@SortBy", sortBy ?? "Name", DbType.String);
            p.Add("@SortDir", sortDir ?? "ASC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<Location>(new CommandDefinition(
                "dbo.usp_Location_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<Location>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<Location?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<Location>(new CommandDefinition(
                "dbo.usp_Location_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<int> InsertAsync(Location location, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@CoCode", location.CoCode, DbType.AnsiString);
            p.Add("@Name", location.Name, DbType.String);
            p.Add("@IsActive", location.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_Location_Insert", p, ct);
            return p.Get<int>("@NewId");
        }

        public async Task UpdateAsync(Location location, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", location.Id, DbType.Int32);
            p.Add("@CoCode", location.CoCode, DbType.AnsiString);
            p.Add("@Name", location.Name, DbType.String);
            p.Add("@IsActive", location.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_Location_Update", p, ct);
        }

        public async Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_Location_SetActive", p, ct);
        }

        /// <summary>Username pelaku untuk audit (CreatedBy/UpdatedBy).</summary>
        private string? ActionBy => _currentUserService.CurrentUser?.Username;

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50011-50013) ke exception bertipe.</summary>
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
                _logger.LogWarning(ex, "{Procedure}: nama lokasi duplikat.", procedure);
                throw new LocationDuplicateNameException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrRequiredEmpty)
            {
                _logger.LogWarning(ex, "{Procedure}: input wajib kosong.", procedure);
                throw new LocationValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: data lokasi tidak ditemukan.", procedure);
                throw new LocationNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }
    }
}
