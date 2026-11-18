using System.Data;
using System.Globalization;
using System.Text.Json;
using CIMS.Models;
using Dapper;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Extensions.Options;

namespace CIMS.Services
{
    /// <summary>Addendum (T4-4): Dapper + stored procedure dbo.usp_Addendum_* (Database/RequestAddendum.sql).</summary>
    public class AddendumService : IAddendumService
    {
        private const string AddendumStage = "ADDENDUM";
        private const string ContractAddendumCode = "ADDENDUM";        // draft kontrak saat raise (18-11-2026)
        private const string FinalContractCode = "ADDENDUM_FINAL";     // kontrak final bertanda tangan (BR-87)
        private const string BoqRevisionCode = "BOQ_REVISION";

        private static readonly FileExtensionContentTypeProvider ContentTypes = new();

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly IRequestService _requestService;
        private readonly IRequestLookupService _lookupService;
        private readonly FileStorageOptions _storage;
        private readonly ILogger<AddendumService> _logger;

        public AddendumService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            IRequestService requestService, IRequestLookupService lookupService, IOptions<FileStorageOptions> storage,
            ILogger<AddendumService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _requestService = requestService;
            _lookupService = lookupService;
            _storage = storage.Value;
            _logger = logger;
        }

        public async Task<IReadOnlyList<ProjectAddendum>> GetByRequestAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            using var grid = await conn.QueryMultipleAsync(new CommandDefinition(
                "dbo.usp_Addendum_GetByRequest", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));

            var addenda = (await grid.ReadAsync<ProjectAddendum>()).AsList();
            var steps = (await grid.ReadAsync<AddendumStepItem>()).AsList();

            foreach (var a in addenda)
                a.Steps = steps.Where(s => s.AddendumNo == a.AddendumNo).OrderBy(s => s.StepOrder).ToList();

            return addenda;
        }

        public async Task<AttachmentType?> GetFileTypeAsync(string? executionType, CancellationToken ct = default)
        {
            var code = executionType switch
            {
                RequestExecutionType.Outsource => ContractAddendumCode,
                RequestExecutionType.InHouse => BoqRevisionCode,
                _ => null
            };
            if (code == null) return null;
            return await GetTypeByCodeAsync(code, ct);
        }

        public Task<AttachmentType?> GetFinalFileTypeAsync(CancellationToken ct = default) =>
            GetTypeByCodeAsync(FinalContractCode, ct);

        private async Task<AttachmentType?> GetTypeByCodeAsync(string code, CancellationToken ct)
        {
            var types = await _lookupService.GetAttachmentTypesByStageAsync(AddendumStage, ct);
            return types.FirstOrDefault(t => string.Equals(t.Code, code, StringComparison.OrdinalIgnoreCase));
        }

        public async Task<AddendumCreateResult> CreateAsync(int requestId, AddendumInput input, IFormFile? file,
            CancellationToken ct = default)
        {
            // Validasi awal sebelum menulis file; SP memvalidasi ulang (role, status, isi, ekstensi, ukuran).
            var request = await _requestService.GetByIdAsync(requestId, ct)
                ?? throw new RequestNotFoundException("Request not found.");
            var type = await GetFileTypeAsync(request.ExecutionType, ct)
                ?? throw new RequestValidationException("The addendum attachment type is not configured. Please contact the administrator.");

            var saved = await SaveFileAsync(request, file, type,
                request.ExecutionType == RequestExecutionType.Outsource
                    ? "Please attach the draft contract."
                    : "Please attach the revised BOQ document.", ct);
            var (originalName, relativePath, fullPath, contentType) = saved;

            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@DocumentNo", input.DocumentNo, DbType.String);
            p.Add("@AddendumDate", input.AddendumDate?.Date, DbType.Date);
            p.Add("@NewValue", input.NewValue, DbType.Decimal, precision: 18, scale: 2);
            p.Add("@Reason", input.Reason, DbType.String);
            p.Add("@OriginalFileName", originalName, DbType.String);
            p.Add("@RelativePath", relativePath, DbType.String);
            p.Add("@ContentType", contentType, DbType.AnsiString);
            p.Add("@FileSizeBytes", file!.Length, DbType.Int64);

            const string procedure = "dbo.usp_Addendum_Create";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                return await conn.QuerySingleAsync<AddendumCreateResult>(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex)
            {
                // Addendum gagal dicatat: hapus file yang baru ditulis (belum pernah terdaftar).
                TryDeleteOrphan(fullPath);
                if (ex is OperationCanceledException) throw;
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        public async Task UploadFinalContractAsync(int requestId, int addendumId, IFormFile? file, string? remarks,
            CancellationToken ct = default)
        {
            var request = await _requestService.GetByIdAsync(requestId, ct)
                ?? throw new RequestNotFoundException("Request not found.");
            var type = await GetFinalFileTypeAsync(ct)
                ?? throw new RequestValidationException("The signed contract attachment type is not configured. Please contact the administrator.");

            var (originalName, relativePath, fullPath, contentType) =
                await SaveFileAsync(request, file, type, "Please attach the signed contract addendum.", ct);

            var p = new DynamicParameters();
            p.Add("@AddendumId", addendumId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@OriginalFileName", originalName, DbType.String);
            p.Add("@RelativePath", relativePath, DbType.String);
            p.Add("@ContentType", contentType, DbType.AnsiString);
            p.Add("@FileSizeBytes", file!.Length, DbType.Int64);
            p.Add("@Remarks", remarks, DbType.String);

            const string procedure = "dbo.usp_Addendum_UploadFinalContract";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.QuerySingleAsync<string>(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex)
            {
                TryDeleteOrphan(fullPath);
                if (ex is OperationCanceledException) throw;
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        /// <summary>
        /// Validasi awal (ekstensi, ukuran) lalu tulis file ke storage: {akar}\{tahun dibuat request}\{RequestId}\{guid}.{ext}
        /// (sama dengan lampiran, BR-44). Pemanggil menghapus file bila SP gagal.
        /// </summary>
        private async Task<(string OriginalName, string RelativePath, string FullPath, string ContentType)> SaveFileAsync(
            ProjectRequest request, IFormFile? file, AttachmentType type, string missingMessage, CancellationToken ct)
        {
            if (file == null || file.Length == 0)
                throw new RequestValidationException(missingMessage);

            var originalName = Path.GetFileName(file.FileName);
            if (originalName.Length > 260) originalName = originalName[^260..];
            var ext = Path.GetExtension(originalName).TrimStart('.').ToLowerInvariant();
            var allowed = type.AllowedExtensions.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (ext.Length == 0 || !allowed.Contains(ext, StringComparer.OrdinalIgnoreCase))
                throw new RequestValidationException($"File type is not allowed. Allowed: {type.AllowedExtensions}.");
            if (file.Length > type.MaxSizeMB * 1024L * 1024L)
                throw new RequestValidationException($"File size exceeds the maximum of {type.MaxSizeMB} MB.");

            var relativePath = Path.Combine(request.CreatedAt.Year.ToString(CultureInfo.InvariantCulture),
                request.Id.ToString(CultureInfo.InvariantCulture), $"{Guid.NewGuid():N}.{ext}");
            var fullPath = ResolveFullPath(relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);

            await using (var stream = new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                await file.CopyToAsync(stream, ct);
            }

            var contentType = ContentTypes.TryGetContentType(originalName, out var ctType) ? ctType : "application/octet-stream";
            return (originalName, relativePath, fullPath, contentType);
        }

        public async Task<string> ApprovalActAsync(int addendumId, int stepId, string action, string? remarks,
            CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@AddendumId", addendumId, DbType.Int32);
            p.Add("@StepId", stepId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Action", action, DbType.AnsiString);
            p.Add("@Remarks", remarks, DbType.String);

            return await QuerySingleValueAsync<string>("dbo.usp_Addendum_ApprovalAct", p, ct);
        }

        public async Task SaveAdjustmentAsync(int addendumId, DateTime projectStartDate, IEnumerable<ActionPlanInput> actionPlans,
            IEnumerable<(DateTime Month, decimal Amount)> estimates, string? remarks, CancellationToken ct = default)
        {
            // Format JSON sama dengan RequestService.SaveScheduleAsync / SaveCostEstimateAsync (SP dipakai bersama)
            var plansJson = JsonSerializer.Serialize(actionPlans.Select(a => new
            {
                id = a.Id,
                name = a.Name,
                weight = a.WeightPercent,
                start = a.PlanStartDate?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                end = a.PlanEndDate?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
            }));
            var estimatesJson = JsonSerializer.Serialize(estimates.Select(e => new
            {
                month = new DateTime(e.Month.Year, e.Month.Month, 1).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                amount = e.Amount
            }));

            var p = new DynamicParameters();
            p.Add("@AddendumId", addendumId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@ProjectStartDate", projectStartDate.Date, DbType.Date);
            p.Add("@ActionPlanJson", plansJson, DbType.String);
            p.Add("@EstimateJson", estimatesJson, DbType.String);
            p.Add("@Remarks", remarks, DbType.String);

            await QuerySingleValueAsync<string>("dbo.usp_Addendum_SaveAdjustment", p, ct);
        }

        public async Task<(AddendumFile File, string FullPath)?> GetForDownloadAsync(int addendumId, bool final, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", addendumId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@Kind", final ? "FINAL" : "DRAFT", DbType.AnsiString);

            using var conn = _connectionFactory.CreateConnection();
            var file = await conn.QueryFirstOrDefaultAsync<AddendumFile>(new CommandDefinition(
                "dbo.usp_Addendum_GetFile", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            if (file == null || string.IsNullOrEmpty(file.RelativePath)) return null;

            var fullPath = ResolveFullPath(file.RelativePath);
            if (!File.Exists(fullPath))
            {
                _logger.LogWarning("File addendum {AddendumId} tidak ditemukan di storage.", addendumId);
                return null;
            }

            return (file, fullPath);
        }

        /// <summary>Jalankan SP yang mengembalikan satu nilai; error SP diterjemahkan (RequestService.Translate).</summary>
        private async Task<T> QuerySingleValueAsync<T>(string procedure, DynamicParameters parameters, CancellationToken ct)
        {
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                return await conn.QuerySingleAsync<T>(new CommandDefinition(
                    procedure, parameters, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        private string Username => _currentUserService.CurrentUser?.Username
            ?? throw new InvalidOperationException("CurrentUser belum dimuat.");

        /// <summary>Path fisik dari path relatif; wajib tetap di dalam folder akar (sama dengan RequestAttachmentService).</summary>
        private string ResolveFullPath(string relativePath)
        {
            if (string.IsNullOrWhiteSpace(_storage.RealizationAttachmentsPath))
                throw new InvalidOperationException("Konfigurasi 'FileStorage:RealizationAttachmentsPath' kosong.");

            var root = Path.GetFullPath(_storage.RealizationAttachmentsPath);
            if (!root.EndsWith(Path.DirectorySeparatorChar)) root += Path.DirectorySeparatorChar;
            var full = Path.GetFullPath(Path.Combine(root, relativePath));
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Path lampiran di luar folder storage.");
            return full;
        }

        private void TryDeleteOrphan(string fullPath)
        {
            try
            {
                if (File.Exists(fullPath)) File.Delete(fullPath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Gagal menghapus file addendum yatim setelah insert gagal.");
            }
        }
    }
}
