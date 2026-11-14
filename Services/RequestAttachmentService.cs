using System.Data;
using CIMS.Models;
using Dapper;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Extensions.Options;

namespace CIMS.Services
{
    public class RequestAttachmentService : IRequestAttachmentService
    {
        private const string StageRequest = "REQUEST";
        private const string StageDocument = "DOCUMENT";

        /// <summary>Tahap jenis lampiran yang boleh diunggah pada status request; null = tidak boleh.</summary>
        public static string? StageForStatus(string? status) => status switch
        {
            RequestStatus.Draft or RequestStatus.Returned or RequestStatus.Feasibility => StageRequest,
            RequestStatus.DocPreparation => StageDocument,
            _ => null
        };

        private static readonly FileExtensionContentTypeProvider ContentTypes = new();

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly IRequestService _requestService;
        private readonly IRequestLookupService _lookupService;
        private readonly FileStorageOptions _storage;
        private readonly ILogger<RequestAttachmentService> _logger;

        public RequestAttachmentService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            IRequestService requestService, IRequestLookupService lookupService, IOptions<FileStorageOptions> storage,
            ILogger<RequestAttachmentService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _requestService = requestService;
            _lookupService = lookupService;
            _storage = storage.Value;
            _logger = logger;
        }

        public async Task<IReadOnlyList<RequestAttachment>> ListAsync(int requestId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            return (await conn.QueryAsync<RequestAttachment>(new CommandDefinition(
                "dbo.usp_RequestAttachment_ListByRequest", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();
        }

        public async Task<int> UploadAsync(int requestId, int attachmentTypeId, IFormFile? file, CancellationToken ct = default)
        {
            // Validasi awal sebelum menulis file; SP memvalidasi ulang saat mencatat metadata.
            var request = await _requestService.GetByIdAsync(requestId, ct)
                ?? throw new RequestNotFoundException("Request not found.");
            // Tahap lampiran menurut status: REQUEST (Draft/Returned requester, Feasibility Civil) atau
            // DOCUMENT (BOQ/Drawing, Document Preparation Civil; T3-2). Role dicek ulang di SP.
            var stage = StageForStatus(request.Status)
                ?? throw new RequestInvalidStateException("Attachments cannot be changed at the current request status.");

            var types = await _lookupService.GetAttachmentTypesByStageAsync(stage, ct);
            var type = types.FirstOrDefault(t => t.Id == attachmentTypeId)
                ?? throw new RequestValidationException("Attachment type is invalid.");

            if (file == null || file.Length == 0)
                throw new RequestValidationException("Please choose a file.");

            var originalName = Path.GetFileName(file.FileName);
            if (originalName.Length > 260) originalName = originalName[^260..];
            var ext = Path.GetExtension(originalName).TrimStart('.').ToLowerInvariant();
            var allowed = type.AllowedExtensions.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (ext.Length == 0 || !allowed.Contains(ext, StringComparer.OrdinalIgnoreCase))
                throw new RequestValidationException($"File type is not allowed. Allowed: {type.AllowedExtensions}.");
            if (file.Length > type.MaxSizeMB * 1024L * 1024L)
                throw new RequestValidationException($"File size exceeds the maximum of {type.MaxSizeMB} MB.");

            // BR-44: {akar}\{tahun dibuat request}\{RequestId}\{guid}.{ext}; nama asli hanya di database.
            var relativePath = Path.Combine(request.CreatedAt.Year.ToString(), requestId.ToString(), $"{Guid.NewGuid():N}.{ext}");
            var fullPath = ResolveFullPath(relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);

            await using (var stream = new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                await file.CopyToAsync(stream, ct);
            }

            var contentType = ContentTypes.TryGetContentType(originalName, out var ctType) ? ctType : "application/octet-stream";

            var p = new DynamicParameters();
            p.Add("@RequestId", requestId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@AttachmentTypeId", attachmentTypeId, DbType.Int32);
            p.Add("@OriginalFileName", originalName, DbType.String);
            p.Add("@RelativePath", relativePath, DbType.String);
            p.Add("@ContentType", contentType, DbType.AnsiString);
            p.Add("@FileSizeBytes", file.Length, DbType.Int64);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    "dbo.usp_RequestAttachment_Insert", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
                return p.Get<int>("@NewId");
            }
            catch (Exception ex)
            {
                // Metadata gagal dicatat: hapus file yang baru ditulis (belum pernah terdaftar, bukan pelanggaran BR-46).
                TryDeleteOrphan(fullPath);
                if (ex is OperationCanceledException) throw;
                var mapped = RequestService.Translate(ex, "dbo.usp_RequestAttachment_Insert", _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        public async Task<(RequestAttachment Attachment, string FullPath)?> GetForDownloadAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            var attachment = await conn.QueryFirstOrDefaultAsync<RequestAttachment>(new CommandDefinition(
                "dbo.usp_RequestAttachment_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            if (attachment?.RelativePath == null) return null;

            var fullPath = ResolveFullPath(attachment.RelativePath);
            if (!File.Exists(fullPath))
            {
                _logger.LogWarning("File lampiran {AttachmentId} tidak ditemukan di storage.", id);
                return null;
            }

            return (attachment, fullPath);
        }

        public async Task DeactivateAsync(int id, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Id", id, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            const string procedure = "dbo.usp_RequestAttachment_Deactivate";
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

        private string Username => _currentUserService.CurrentUser?.Username
            ?? throw new InvalidOperationException("CurrentUser belum dimuat.");

        /// <summary>Path fisik dari path relatif; wajib tetap di dalam folder akar (cegah path traversal).</summary>
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
                _logger.LogWarning(ex, "Gagal menghapus file lampiran yatim setelah insert metadata gagal.");
            }
        }
    }
}
