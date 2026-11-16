using System.Data;
using System.Text.Json;
using CIMS.Models;
using Dapper;
using Microsoft.Data.SqlClient;

namespace CIMS.Services
{
    public class RequestService : IRequestService
    {
        internal const int ErrInvalid = 50072;
        internal const int ErrNotFound = 50073;
        internal const int ErrInvalidState = 50074;
        internal const int ErrNotAuthorized = 50075;

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly ILogger<RequestService> _logger;

        public RequestService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            ILogger<RequestService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _logger = logger;
        }

        public async Task<PagedResult<RequestListItem>> GetPagedAsync(string? coCode, int? departmentId, string? search,
            string? category, string? status, string? sortBy, string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@DepartmentID", departmentId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@CoCode", coCode, DbType.AnsiString);
            p.Add("@Search", search, DbType.String);
            p.Add("@Category", category, DbType.AnsiString);
            p.Add("@Status", status, DbType.AnsiString);
            p.Add("@SortBy", sortBy ?? "CreatedAt", DbType.String);
            p.Add("@SortDir", sortDir ?? "DESC", DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<RequestListItem>(new CommandDefinition(
                "dbo.usp_Request_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<RequestListItem>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<ProjectRequest?> GetByIdAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<ProjectRequest>(new CommandDefinition(
                "dbo.usp_Request_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<IReadOnlyList<RequestAssessmentItem>> GetAssessmentAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<RequestAssessmentItem>(new CommandDefinition(
                "dbo.usp_Request_GetAssessment", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<int> SaveDraftAsync(ProjectRequest request, IEnumerable<RequestAnswerInput> answers, CancellationToken ct = default)
        {
            // Hanya jawaban yang diisi; format sesuai OPENJSON di SP: [{"q":1,"a":true}]
            var json = JsonSerializer.Serialize(answers
                .Where(a => a.Answer.HasValue)
                .Select(a => new { q = a.QuestionId, a = a.Answer!.Value }));

            var p = new DynamicParameters();
            p.Add("@Id", request.Id > 0 ? request.Id : null, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Title", request.Title, DbType.String);
            p.Add("@Category", request.Category, DbType.AnsiString);
            p.Add("@SubCategoryId", request.SubCategoryId, DbType.Int32);
            p.Add("@BudgetRemarks", request.BudgetRemarks, DbType.AnsiString);
            p.Add("@SubDepartmentID", request.SubDepartmentID, DbType.Int32);
            p.Add("@LocationId", request.LocationId, DbType.Int32);
            p.Add("@PicEmployeeCode", request.PicEmployeeCode, DbType.AnsiString);
            p.Add("@TargetCompletionDate", request.TargetCompletionDate?.Date, DbType.Date);
            p.Add("@AreaLength", request.AreaLength, DbType.Decimal, precision: 10, scale: 2);
            p.Add("@AreaWidth", request.AreaWidth, DbType.Decimal, precision: 10, scale: 2);
            p.Add("@BudgetExpectation", request.BudgetExpectation, DbType.Decimal, precision: 18, scale: 2);
            p.Add("@Background", request.Background, DbType.String);
            p.Add("@Objective", request.Objective, DbType.String);
            p.Add("@OperationalImpact", request.OperationalImpact, DbType.String);
            p.Add("@RiskIfNotApproved", request.RiskIfNotApproved, DbType.String);
            p.Add("@ExpectedBenefits", request.ExpectedBenefits, DbType.String);
            p.Add("@Alternatives", request.Alternatives, DbType.String);
            p.Add("@SpecialNote", request.SpecialNote, DbType.String);
            p.Add("@ExpectedRoiPercent", request.ExpectedRoiPercent, DbType.Decimal, precision: 9, scale: 2);
            p.Add("@RoiExplanation", request.RoiExplanation, DbType.String);
            p.Add("@AdditionalInfo", request.AdditionalInfo, DbType.String);
            p.Add("@AssessmentJson", json, DbType.String);
            p.Add("@SavedId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            await ExecuteAsync("dbo.usp_Request_SaveDraft", p, ct);
            return p.Get<int>("@SavedId");
        }

        public async Task<(string RequestNo, string Status)> SubmitAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            const string procedure = "dbo.usp_Request_Submit";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                var row = await conn.QuerySingleAsync<(string RequestNo, string Status)>(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
                return row;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        public async Task CancelAsync(int id, string? reason, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Reason", reason, DbType.String);

            await ExecuteAsync("dbo.usp_Request_Cancel", p, ct);
        }

        public async Task<IReadOnlyList<ApprovalStepItem>> GetApprovalStepsAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<ApprovalStepItem>(new CommandDefinition(
                "dbo.usp_Request_GetApprovalSteps", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<IReadOnlyList<ApprovalHistoryItem>> GetHistoryAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<ApprovalHistoryItem>(new CommandDefinition(
                "dbo.usp_Request_GetHistory", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<ApprovalStepItem?> GetActionableStepAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<ApprovalStepItem>(new CommandDefinition(
                "dbo.usp_Request_GetActionableStep", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<string> ApprovalActAsync(int id, int stepId, string action, string? remarks, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@StepId", stepId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Action", action, DbType.AnsiString);
            p.Add("@Remarks", remarks, DbType.String);

            const string procedure = "dbo.usp_Request_ApprovalAct";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                return await conn.QuerySingleAsync<string>(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        public async Task<string?> ChangeCategoryAsync(int id, string category, int subCategoryId, string? reason, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Category", category, DbType.AnsiString);
            p.Add("@SubCategoryId", subCategoryId, DbType.Int32);
            p.Add("@Reason", reason, DbType.String);

            return await QuerySingleValueAsync<string?>("dbo.usp_Request_ChangeCategory", p, ct);
        }

        public async Task<string> FeasibilityDecideAsync(int id, string decision, string? remarks, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Decision", decision, DbType.AnsiString);
            p.Add("@Remarks", remarks, DbType.String);

            return (await QuerySingleValueAsync<string>("dbo.usp_Request_FeasibilityDecide", p, ct))!;
        }

        public async Task SetBoqTotalAsync(int id, decimal boqTotal, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@BoqTotal", boqTotal, DbType.Decimal, precision: 18, scale: 2);

            await ExecuteAsync("dbo.usp_Request_SetBoqTotal", p, ct);
        }

        public async Task<string> SendToManagementAsync(int id, string? remarks, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Remarks", remarks, DbType.String);

            return (await QuerySingleValueAsync<string>("dbo.usp_Request_SendToManagement", p, ct))!;
        }

        public async Task<string> ChooseExecutionAsync(int id, string executionType, string? remarks, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@ExecutionType", executionType, DbType.AnsiString);
            p.Add("@Remarks", remarks, DbType.String);

            return (await QuerySingleValueAsync<string>("dbo.usp_Request_ChooseExecution", p, ct))!;
        }

        public async Task SaveContractAsync(int id, int vendorId, string contractNo, DateTime contractDate,
            decimal contractValue, string? remarks, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@VendorId", vendorId, DbType.Int32);
            p.Add("@ContractNo", contractNo, DbType.String);
            p.Add("@ContractDate", contractDate.Date, DbType.Date);
            p.Add("@ContractValue", contractValue, DbType.Decimal, precision: 18, scale: 2);
            p.Add("@Remarks", remarks, DbType.String);

            await ExecuteAsync("dbo.usp_Request_SaveContract", p, ct);
        }

        public async Task<string> CompleteProcurementAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            return (await QuerySingleValueAsync<string>("dbo.usp_Request_CompleteProcurement", p, ct))!;
        }

        public async Task ReturnTorAsync(int id, string? reason, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Reason", reason, DbType.String);

            await ExecuteAsync("dbo.usp_Request_ReturnTor", p, ct);
        }

        public async Task<ProjectContract?> GetContractAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<ProjectContract>(new CommandDefinition(
                "dbo.usp_Request_GetContract", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        }

        public async Task<ProjectSchedule?> GetScheduleAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            using var grid = await conn.QueryMultipleAsync(new CommandDefinition(
                "dbo.usp_Request_GetSchedule", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));

            var summary = await grid.ReadFirstOrDefaultAsync<ProjectScheduleSummary>();
            var plans = (await grid.ReadAsync<ProjectActionPlanItem>()).AsList();
            var estimates = (await grid.ReadAsync<ProjectCostEstimateItem>()).AsList();
            if (summary == null) return null;

            return new ProjectSchedule { Summary = summary, ActionPlans = plans, CostEstimates = estimates };
        }

        public async Task SaveScheduleAsync(int id, DateTime projectStartDate, IEnumerable<ActionPlanInput> actionPlans,
            string? reason, CancellationToken ct = default)
        {
            // Urutan list = SortOrder. Tanggal dikirim "yyyy-MM-dd" (OPENJSON ... DATE).
            var json = JsonSerializer.Serialize(actionPlans.Select(a => new
            {
                id = a.Id,
                name = a.Name,
                weight = a.WeightPercent,
                start = a.PlanStartDate?.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture),
                end = a.PlanEndDate?.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture)
            }));

            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@ProjectStartDate", projectStartDate.Date, DbType.Date);
            p.Add("@ActionPlanJson", json, DbType.String);
            p.Add("@Reason", reason, DbType.String);

            await ExecuteAsync("dbo.usp_Request_SaveSchedule", p, ct);
        }

        public async Task SaveCostEstimateAsync(int id, IEnumerable<(DateTime Month, decimal Amount)> estimates,
            string? reason, CancellationToken ct = default)
        {
            var json = JsonSerializer.Serialize(estimates.Select(e => new
            {
                month = new DateTime(e.Month.Year, e.Month.Month, 1).ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture),
                amount = e.Amount
            }));

            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@EstimateJson", json, DbType.String);
            p.Add("@Reason", reason, DbType.String);

            await ExecuteAsync("dbo.usp_Request_SaveCostEstimate", p, ct);
        }

        public async Task<string> SiteHandoverAsync(int id, DateTime handoverDate, string? remarks, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@HandoverDate", handoverDate.Date, DbType.Date);
            p.Add("@Remarks", remarks, DbType.String);

            return (await QuerySingleValueAsync<string>("dbo.usp_Request_SiteHandover", p, ct))!;
        }

        public async Task<(int Id, string RequestNo, string Status)> CreateRunningAsync(RunningProjectFormViewModel model,
            CancellationToken ct = default)
        {
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            var approvals = JsonSerializer.Serialize(model.Approvals
                .Where(a => !a.IsEmpty)
                .Select(a => new { step = a.Step, name = a.Name, date = a.Date?.ToString("yyyy-MM-dd", inv) }));

            // Field yang tidak relevan untuk status/cara eksekusi dikosongkan (SP menolak data kontrak di luar outsource).
            var scheduling = model.TargetStatus == RequestStatus.Scheduling;
            var executionType = scheduling ? model.ExecutionType : null;
            var outsource = executionType == RequestExecutionType.Outsource;

            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@DepartmentID", model.DepartmentID, DbType.Int32);
            p.Add("@Title", model.Title, DbType.String);
            p.Add("@Category", model.Category, DbType.AnsiString);
            p.Add("@SubCategoryId", model.SubCategoryId, DbType.Int32);
            p.Add("@LocationId", model.LocationId, DbType.Int32);
            p.Add("@PicEmployeeCode", model.PicEmployeeCode, DbType.AnsiString);
            p.Add("@SubDepartmentID", model.SubDepartmentID, DbType.Int32);
            p.Add("@BudgetRemarks", model.BudgetRemarks, DbType.AnsiString);
            p.Add("@TargetCompletionDate", model.TargetCompletionDate?.Date, DbType.Date);
            p.Add("@BudgetExpectation", model.BudgetExpectation, DbType.Decimal, precision: 18, scale: 2);
            p.Add("@Background", model.Background, DbType.String);
            p.Add("@Objective", model.Objective, DbType.String);
            p.Add("@TargetStatus", model.TargetStatus, DbType.AnsiString);
            p.Add("@ExecutionType", executionType, DbType.AnsiString);
            p.Add("@BoqTotal", model.BoqTotal, DbType.Decimal, precision: 18, scale: 2);
            p.Add("@VendorId", outsource ? model.VendorId : null, DbType.Int32);
            p.Add("@ContractNo", outsource ? model.ContractNo : null, DbType.String);
            p.Add("@ContractDate", outsource ? model.ContractDate?.Date : null, DbType.Date);
            p.Add("@ContractValue", outsource ? model.ContractValue : null, DbType.Decimal, precision: 18, scale: 2);
            p.Add("@PreparationStartDate", scheduling ? model.PreparationStartDate?.Date : null, DbType.Date);
            p.Add("@ApprovalsJson", approvals, DbType.String);
            p.Add("@Remarks", model.Remarks, DbType.String);

            const string procedure = "dbo.usp_Request_CreateRunning";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                var row = await conn.QuerySingleAsync<(int Id, string RequestNo, string Status)>(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
                return row;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        public async Task<IReadOnlyList<CategoryChangeItem>> GetCategoryChangesAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<CategoryChangeItem>(new CommandDefinition(
                "dbo.usp_Request_GetCategoryChanges", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        /// <summary>Jalankan SP yang mengembalikan satu nilai (satu baris, satu kolom); error SP diterjemahkan.</summary>
        private async Task<T?> QuerySingleValueAsync<T>(string procedure, DynamicParameters parameters, CancellationToken ct)
        {
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                return await conn.QuerySingleAsync<T>(new CommandDefinition(
                    procedure, parameters, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        /// <summary>Username pelaku; SP memakai ini untuk lingkup data dan audit.</summary>
        private string Username => _currentUserService.CurrentUser?.Username
            ?? throw new InvalidOperationException("CurrentUser belum dimuat.");

        /// <summary>Jalankan SP non-query; terjemahkan error khusus SP (50072-50074) ke exception bertipe.</summary>
        private async Task ExecuteAsync(string procedure, DynamicParameters parameters, CancellationToken ct)
        {
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    procedure, parameters, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        /// <summary>Terjemahan error SP request/lampiran; dipakai juga oleh RequestAttachmentService.</summary>
        internal static Exception Translate(Exception ex, string procedure, ILogger logger)
        {
            if (ex is SqlException sql)
            {
                switch (sql.Number)
                {
                    case ErrInvalid:
                        logger.LogWarning(ex, "{Procedure}: input tidak valid.", procedure);
                        return new RequestValidationException(sql.Message, ex);
                    case ErrNotFound:
                        logger.LogWarning(ex, "{Procedure}: data tidak ditemukan / di luar lingkup.", procedure);
                        return new RequestNotFoundException(sql.Message, ex);
                    case ErrInvalidState:
                        logger.LogWarning(ex, "{Procedure}: status request tidak mengizinkan aksi.", procedure);
                        return new RequestInvalidStateException(sql.Message, ex);
                    case ErrNotAuthorized:
                        logger.LogWarning(ex, "{Procedure}: user tidak berhak melakukan aksi ini.", procedure);
                        return new RequestNotAuthorizedException(sql.Message, ex);
                }
            }

            logger.LogError(ex, "{Procedure}: gagal dieksekusi.", procedure);
            return ex;
        }
    }
}
