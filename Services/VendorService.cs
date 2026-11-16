using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class VendorService : IVendorService
    {
        private const int ErrDuplicateCode = 50081;
        private const int ErrValidation = 50082;
        private const int ErrNotFound = 50083;
        private const int ErrDuplicateErpNo = 50084;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<VendorService> _logger;

        public VendorService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<VendorService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<PagedResult<Vendor>> GetPagedAsync(string? search, bool? isActive, string? sortBy,
            string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default)
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
            var items = (await conn.QueryAsync<Vendor>(new CommandDefinition(
                "dbo.usp_Vendor_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<Vendor>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<Vendor?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<Vendor>(new CommandDefinition(
                "dbo.usp_Vendor_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<IReadOnlyList<VendorOption>> GetActiveAsync(int? includeId = null, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@IncludeId", includeId, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<VendorOption>(new CommandDefinition(
                "dbo.usp_Vendor_GetActive", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<int> InsertAsync(Vendor vendor, CancellationToken ct = default)
        {
            var p = BuildParameters(vendor);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_Vendor_Insert", p, ct);
            return p.Get<int>("@NewId");
        }

        public async Task UpdateAsync(Vendor vendor, CancellationToken ct = default)
        {
            var p = BuildParameters(vendor);
            p.Add("@Id", vendor.Id, DbType.Int32);

            await ExecuteAsync("dbo.usp_Vendor_Update", p, ct);
        }

        public async Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_Vendor_SetActive", p, ct);
        }

        /// <summary>Parameter bersama Insert/Update (tanpa @Id / @NewId).</summary>
        private DynamicParameters BuildParameters(Vendor vendor)
        {
            var p = new DynamicParameters();
            p.Add("@Code", vendor.Code, DbType.AnsiString);
            p.Add("@Name", vendor.Name, DbType.String);
            p.Add("@ErpVendorNo", vendor.ErpVendorNo, DbType.AnsiString);
            p.Add("@ContactPerson", vendor.ContactPerson, DbType.String);
            p.Add("@Phone", vendor.Phone, DbType.AnsiString);
            p.Add("@Email", vendor.Email, DbType.AnsiString);
            p.Add("@Address", vendor.Address, DbType.String);
            p.Add("@IsActive", vendor.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);
            return p;
        }

        /// <summary>Username pelaku untuk audit (CreatedBy/UpdatedBy).</summary>
        private string? ActionBy => _currentUserService.CurrentUser?.Username;

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50081-50084) ke exception bertipe.</summary>
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
                _logger.LogWarning(ex, "{Procedure}: kode vendor duplikat.", procedure);
                throw new VendorDuplicateCodeException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrDuplicateErpNo)
            {
                _logger.LogWarning(ex, "{Procedure}: nomor vendor ERP duplikat.", procedure);
                throw new VendorDuplicateErpNoException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrValidation)
            {
                _logger.LogWarning(ex, "{Procedure}: input wajib kosong / tidak valid.", procedure);
                throw new VendorValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: data vendor tidak ditemukan.", procedure);
                throw new VendorNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }
    }
}
