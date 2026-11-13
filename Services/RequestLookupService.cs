using System.Data;
using CIMS.Models;
using Dapper;

namespace CIMS.Services
{
    public class RequestLookupService : IRequestLookupService
    {
        private readonly IDbConnectionFactory _connectionFactory;

        public RequestLookupService(IDbConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public Task<IReadOnlyList<CostCenterOption>> GetCostCentersAsync(int departmentId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@DepartmentID", departmentId, DbType.Int32);
            return QueryAsync<CostCenterOption>("dbo.usp_Lookup_CostCenters", p, ct);
        }

        public Task<IReadOnlyList<EmployeeOption>> GetActiveEmployeesAsync(int departmentId, string? search = null, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@DepartmentID", departmentId, DbType.Int32);
            p.Add("@Search", search, DbType.String);
            return QueryAsync<EmployeeOption>("dbo.usp_Lookup_ActiveEmployees", p, ct);
        }

        public Task<IReadOnlyList<LocationOption>> GetLocationsAsync(string coCode, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@CoCode", coCode, DbType.AnsiString);
            return QueryAsync<LocationOption>("dbo.usp_Lookup_Locations", p, ct);
        }

        public async Task<IReadOnlyList<RequestAssessmentItem>> GetAssessmentQuestionsAsync(CancellationToken ct = default)
        {
            // SP mengembalikan Id/SortOrder/QuestionText; dipetakan ke QuestionId agar sama dengan jawaban request.
            using var conn = _connectionFactory.CreateConnection();
            var rows = await conn.QueryAsync<(int Id, int SortOrder, string QuestionText)>(new CommandDefinition(
                "dbo.usp_Lookup_AssessmentQuestions", commandType: CommandType.StoredProcedure, cancellationToken: ct));
            return rows.Select(r => new RequestAssessmentItem
            {
                QuestionId = r.Id,
                SortOrder = r.SortOrder,
                QuestionText = r.QuestionText
            }).ToList();
        }

        public Task<IReadOnlyList<AttachmentType>> GetAttachmentTypesByStageAsync(string stage, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Stage", stage, DbType.AnsiString);
            return QueryAsync<AttachmentType>("dbo.usp_Lookup_AttachmentTypesByStage", p, ct);
        }

        private async Task<IReadOnlyList<T>> QueryAsync<T>(string procedure, DynamicParameters p, CancellationToken ct)
        {
            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<T>(new CommandDefinition(
                procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }
    }
}
