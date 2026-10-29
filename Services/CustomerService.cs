using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class CustomerService : ICustomerService
    {
        private const int ErrDuplicateCode = 50001;
        private const int ErrRequiredEmpty = 50002;
        private const int ErrNotFound = 50003;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ILogger<CustomerService> _logger;

        public CustomerService(IDbConnectionFactory connectionFactory, ILogger<CustomerService> logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<PagedResult<Customer>> GetPagedAsync(string? search, bool? isActive, string? sortBy,
            string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Search", search, DbType.String);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@SortBy", sortBy ?? "Code", DbType.String);
            p.Add("@SortDir", sortDir ?? "ASC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<Customer>(new CommandDefinition(
                "dbo.usp_Customer_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<Customer>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<Customer?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<Customer>(new CommandDefinition(
                "dbo.usp_Customer_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<int> InsertAsync(Customer customer, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Code", customer.Code, DbType.String);
            p.Add("@Name", customer.Name, DbType.String);
            p.Add("@Phone", customer.Phone, DbType.String);
            p.Add("@Email", customer.Email, DbType.String);
            p.Add("@Address", customer.Address, DbType.String);
            p.Add("@IsActive", customer.IsActive, DbType.Boolean);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_Customer_Insert", p, ct);
            return p.Get<int>("@NewId");
        }

        public async Task UpdateAsync(Customer customer, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", customer.Id, DbType.Int32);
            p.Add("@Code", customer.Code, DbType.String);
            p.Add("@Name", customer.Name, DbType.String);
            p.Add("@Phone", customer.Phone, DbType.String);
            p.Add("@Email", customer.Email, DbType.String);
            p.Add("@Address", customer.Address, DbType.String);
            p.Add("@IsActive", customer.IsActive, DbType.Boolean);

            await ExecuteAsync("dbo.usp_Customer_Update", p, ct);
        }

        public async Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@IsActive", isActive, DbType.Boolean);

            await ExecuteAsync("dbo.usp_Customer_SetActive", p, ct);
        }

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50001-50003) ke exception bertipe.</summary>
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
                _logger.LogWarning(ex, "{Procedure}: kode customer duplikat.", procedure);
                throw new CustomerDuplicateCodeException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrRequiredEmpty)
            {
                _logger.LogWarning(ex, "{Procedure}: input wajib kosong.", procedure);
                throw new CustomerValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: data customer tidak ditemukan.", procedure);
                throw new CustomerNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }
    }
}
