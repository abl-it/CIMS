using System.Data;
using CIMS.Models;
using Dapper;

namespace CIMS.Services
{
    public class AuthService : IAuthService
    {
        private readonly IDbConnectionFactory _connectionFactory;

        public AuthService(IDbConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<CurrentUser?> GetUserByUsernameAsync(string username, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<CurrentUser>(new CommandDefinition(
                "dbo.usp_Auth_GetUserByUsername", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<IReadOnlyList<UserRole>> GetUserRolesAsync(string username, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            var roles = await conn.QueryAsync<UserRole>(new CommandDefinition(
                "dbo.usp_Auth_GetUserRoles", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            return roles.AsList();
        }
    }
}
