using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class AppSettingService : IAppSettingService
    {
        private const int ErrInvalid = 50052;
        private const int ErrNotFound = 50053;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<AppSettingService> _logger;

        public AppSettingService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<AppSettingService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<IReadOnlyList<AppSetting>> ListAsync(string? coCode, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@CoCode", coCode, DbType.AnsiString);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<AppSetting>(new CommandDefinition(
                "dbo.usp_AppSetting_List", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<AppSetting?> GetByKeyAsync(string coCode, string settingKey, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@CoCode", coCode, DbType.AnsiString);
            p.Add("@SettingKey", settingKey, DbType.AnsiString);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<AppSetting>(new CommandDefinition(
                "dbo.usp_AppSetting_GetByKey", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task UpdateValueAsync(string coCode, string settingKey, string settingValue, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@CoCode", coCode, DbType.AnsiString);
            p.Add("@SettingKey", settingKey, DbType.AnsiString);
            p.Add("@SettingValue", settingValue, DbType.String);
            p.Add("@ActionBy", ActionBy, DbType.String);

            const string procedure = "dbo.usp_AppSetting_UpdateValue";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (SqlException ex) when (ex.Number == ErrInvalid)
            {
                _logger.LogWarning(ex, "{Procedure}: nilai setting tidak valid ({CoCode}, {SettingKey}).", procedure, coCode, settingKey);
                throw new AppSettingValidationException(ex.Message, ex);
            }
            catch (SqlException ex) when (ex.Number == ErrNotFound)
            {
                _logger.LogWarning(ex, "{Procedure}: setting tidak ditemukan ({CoCode}, {SettingKey}).", procedure, coCode, settingKey);
                throw new AppSettingNotFoundException(ex.Message, ex);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
                throw;
            }
        }

        /// <summary>Username pelaku untuk audit (UpdatedBy).</summary>
        private string? ActionBy => _currentUserService.CurrentUser?.Username;
    }
}
