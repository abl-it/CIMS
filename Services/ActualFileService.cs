using System.Data;
using System.Globalization;
using System.Text.Json;
using CIMS.Models;
using Dapper;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Extensions.Options;

namespace CIMS.Services
{
    /// <summary>Lampiran detail cost per bulan (BR-96): Dapper + dbo.usp_ActualFile_* dan usp_Request_SaveActualMonth.</summary>
    public class ActualFileService : IActualFileService
    {
        private const string CostStage = "COST";
        private const string DetailCode = "ACTUAL_DETAIL";

        private static readonly FileExtensionContentTypeProvider ContentTypes = new();

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly IRequestService _requestService;
        private readonly IRequestLookupService _lookupService;
        private readonly FileStorageOptions _storage;
        private readonly ILogger<ActualFileService> _logger;

        public ActualFileService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            IRequestService requestService, IRequestLookupService lookupService, IOptions<FileStorageOptions> storage,
            ILogger<ActualFileService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _requestService = requestService;
            _lookupService = lookupService;
            _storage = storage.Value;
            _logger = logger;
        }

        public async Task<IReadOnlyList<ActualFile>> ListAsync(int requestId, DateTime? month, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Month", month?.Date, DbType.Date);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<ActualFile>(new CommandDefinition(
                "dbo.usp_ActualFile_List", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<ActualSaveResult> SaveMonthAsync(int requestId, DateTime month, IReadOnlyList<ActualItemInput> items,
            string? remarks, IReadOnlyList<IFormFile> files, CancellationToken ct = default)
        {
            var saved = new List<SavedFile>();
            try
            {
                if (files.Count > 0)
                {
                    var request = await _requestService.GetByIdAsync(requestId, ct)
                        ?? throw new RequestNotFoundException("Request not found.");
                    var type = await GetTypeAsync(ct);
                    foreach (var f in files)
                        saved.Add(await SaveFileAsync(request, f, type, ct));
                }

                var filesJson = saved.Count == 0 ? null : JsonSerializer.Serialize(saved.Select(s => new
                {
                    name = s.OriginalName,
                    path = s.RelativePath,
                    type = s.ContentType,
                    size = s.Size
                }));

                return await _requestService.SaveActualMonthAsync(requestId, month, items, remarks, ct: ct, filesJson: filesJson);
            }
            catch
            {
                // Simpan gagal: hapus file yang baru ditulis (belum pernah terdaftar)
                foreach (var s in saved) TryDeleteOrphan(s.FullPath);
                throw;
            }
        }

        public async Task AddAsync(int requestId, DateTime month, IFormFile? file, CancellationToken ct = default)
        {
            var request = await _requestService.GetByIdAsync(requestId, ct)
                ?? throw new RequestNotFoundException("Request not found.");
            var type = await GetTypeAsync(ct);
            var saved = await SaveFileAsync(request, file, type, ct);

            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Month", month.Date, DbType.Date);
            p.Add("@Username", Username, DbType.String);
            p.Add("@OriginalFileName", saved.OriginalName, DbType.String);
            p.Add("@RelativePath", saved.RelativePath, DbType.String);
            p.Add("@ContentType", saved.ContentType, DbType.AnsiString);
            p.Add("@FileSizeBytes", saved.Size, DbType.Int64);

            const string procedure = "dbo.usp_ActualFile_Insert";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.QuerySingleAsync<int>(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex)
            {
                TryDeleteOrphan(saved.FullPath);
                if (ex is OperationCanceledException) throw;
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        public async Task RemoveAsync(int fileId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", fileId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            const string procedure = "dbo.usp_ActualFile_Deactivate";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        public async Task<(ActualFile File, string FullPath)?> GetForDownloadAsync(int fileId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", fileId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            var file = await conn.QueryFirstOrDefaultAsync<ActualFile>(new CommandDefinition(
                "dbo.usp_ActualFile_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            if (file?.RelativePath == null) return null;

            var fullPath = ResolveFullPath(file.RelativePath);
            if (!File.Exists(fullPath))
            {
                _logger.LogWarning("File lampiran detail cost {FileId} tidak ditemukan di storage.", fileId);
                return null;
            }

            return (file, fullPath);
        }

        private async Task<AttachmentType> GetTypeAsync(CancellationToken ct)
        {
            var types = await _lookupService.GetAttachmentTypesByStageAsync(CostStage, ct);
            return types.FirstOrDefault(t => string.Equals(t.Code, DetailCode, StringComparison.OrdinalIgnoreCase))
                ?? throw new RequestValidationException("The cost detail attachment type is not configured. Please contact the administrator.");
        }

        /// <summary>Validasi awal lalu tulis file: {akar}\{tahun dibuat request}\{RequestId}\{guid}.{ext} (BR-44).</summary>
        private async Task<SavedFile> SaveFileAsync(ProjectRequest request, IFormFile? file, AttachmentType type, CancellationToken ct)
        {
            if (file == null || file.Length == 0)
                throw new RequestValidationException("Please choose a file.");

            var originalName = Path.GetFileName(file.FileName);
            if (originalName.Length > 260) originalName = originalName[^260..];
            var ext = Path.GetExtension(originalName).TrimStart('.').ToLowerInvariant();
            var allowed = type.AllowedExtensions.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (ext.Length == 0 || !allowed.Contains(ext, StringComparer.OrdinalIgnoreCase))
                throw new RequestValidationException($"\"{originalName}\": file type is not allowed. Allowed: {type.AllowedExtensions}.");
            if (file.Length > type.MaxSizeMB * 1024L * 1024L)
                throw new RequestValidationException($"\"{originalName}\": file size exceeds the maximum of {type.MaxSizeMB} MB.");

            var relativePath = Path.Combine(request.CreatedAt.Year.ToString(CultureInfo.InvariantCulture),
                request.Id.ToString(CultureInfo.InvariantCulture), $"{Guid.NewGuid():N}.{ext}");
            var fullPath = ResolveFullPath(relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);

            await using (var stream = new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                await file.CopyToAsync(stream, ct);
            }

            var contentType = ContentTypes.TryGetContentType(originalName, out var ctType) ? ctType : "application/octet-stream";
            return new SavedFile(originalName, relativePath, fullPath, contentType, file.Length);
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
                _logger.LogWarning(ex, "Gagal menghapus file lampiran detail cost yatim setelah simpan gagal.");
            }
        }

        private sealed record SavedFile(string OriginalName, string RelativePath, string FullPath, string ContentType, long Size);
    }
}
