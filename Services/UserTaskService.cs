using System.Data;
using CIMS.Models;
using Dapper;

namespace CIMS.Services
{
    public class UserTaskService : IUserTaskService
    {
        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;

        public UserTaskService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
        }

        public async Task<IReadOnlyList<UserTaskSummaryItem>> GetSummaryAsync(CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<UserTaskSummaryItem>(new CommandDefinition(
                "dbo.usp_Task_GetSummary", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<IReadOnlyList<UserTaskItem>> GetListAsync(string? taskType, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@TaskType", taskType, DbType.AnsiString);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<UserTaskItem>(new CommandDefinition(
                "dbo.usp_Task_GetList", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task MarkReadAsync(int requestId, string taskType, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@TaskType", taskType, DbType.AnsiString);

            using var conn = _connectionFactory.CreateConnection();
            await conn.ExecuteAsync(new CommandDefinition(
                "dbo.usp_Task_MarkRead", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        /// <summary>Username pelaku; SP memakai ini untuk lingkup tugas.</summary>
        private string Username => _currentUserService.CurrentUser?.Username
            ?? throw new InvalidOperationException("CurrentUser belum dimuat.");
    }
}
