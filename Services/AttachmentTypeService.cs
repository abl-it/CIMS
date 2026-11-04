using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class AttachmentTypeService : IAttachmentTypeService
    {
        private const int ErrDuplicateCode = 50021;
        private const int ErrRequiredEmpty = 50022;
        private const int ErrNotFound = 50023;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<AttachmentTypeService> _logger;

        public AttachmentTypeService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<AttachmentTypeService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<PagedResult<AttachmentType>> GetPagedAsync(string? stage, string? search, bool? isActive,
            string? sortBy, string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Stage", stage, DbType.AnsiString);
            p.Add("@Search", search, DbType.String);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@SortBy", sortBy ?? "Stage", DbType.String);
            p.Add("@SortDir", sortDir ?? "ASC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<AttachmentType>(new CommandDefinition(
                "dbo.usp_AttachmentType_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<AttachmentType>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<AttachmentType?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<AttachmentType>(new CommandDefinition(
                "dbo.usp_AttachmentType_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<int> InsertAsync(AttachmentType attachmentType, CancellationToken ct = default)
        {
            var p = BuildParameters(attachmentType);
            p.Add("@Code", attachmentType.Code, DbType.AnsiString);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_AttachmentType_Insert", p, ct);
            return p.Get<int>("@NewId");
        }

        public async Task UpdateAsync(AttachmentType attachmentType, CancellationToken ct = default)
        {
            var p = BuildParameters(attachmentType);
            p.Add("@Id", attachmentType.Id, DbType.Int32);

            await ExecuteAsync("dbo.usp_AttachmentType_Update", p, ct);
        }

        public async Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@IsActive", isActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);

            await ExecuteAsync("dbo.usp_AttachmentType_SetActive", p, ct);
        }

        /// <summary>Parameter bersama Insert/Update (tanpa Code dan Id).</summary>
        private DynamicParameters BuildParameters(AttachmentType a)
        {
            var p = new DynamicParameters();
            p.Add("@Name", a.Name, DbType.String);
            p.Add("@Stage", a.Stage, DbType.AnsiString);
            p.Add("@AllowedExtensions", a.AllowedExtensions, DbType.String);
            p.Add("@MaxSizeMB", a.MaxSizeMB, DbType.Int32);
            p.Add("@IsMandatoryCapex", a.IsMandatoryCapex, DbType.Boolean);
            p.Add("@IsMandatoryOpex", a.IsMandatoryOpex, DbType.Boolean);
            p.Add("@IsMandatoryLve", a.IsMandatoryLve, DbType.Boolean);
            p.Add("@IsActive", a.IsActive, DbType.Boolean);
            p.Add("@ActionBy", ActionBy, DbType.String);
            return p;
        }

        /// <summary>Username pelaku untuk audit (CreatedBy/UpdatedBy).</summary>
        private string? ActionBy => _currentUserService.CurrentUser?.Username;

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50021-50023) ke exception bertipe.</summary>
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
                _logger.LogWarning(ex, "{Procedure}: code jenis lampiran duplikat.", procedure);
                throw new AttachmentTypeDuplicateCodeException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrRequiredEmpty)
            {
                _logger.LogWarning(ex, "{Procedure}: input tidak valid.", procedure);
                throw new AttachmentTypeValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: data jenis lampiran tidak ditemukan.", procedure);
                throw new AttachmentTypeNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }
    }
}
