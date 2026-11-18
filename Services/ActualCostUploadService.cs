using System.Data;
using System.Globalization;
using System.Text.Json;
using CIMS.Models;
using ClosedXML.Excel;
using Dapper;
using Microsoft.Extensions.Options;

namespace CIMS.Services
{
    /// <summary>
    /// Upload actual cost via template Excel (T5-3; PRD 6.4, BR-18, BR-19). Satu file untuk banyak project/bulan.
    /// Alur: baca (ClosedXML) -> validasi SP (all or nothing) -> arsip PENDING + preview -> konfirmasi (import) / batal.
    /// </summary>
    public class ActualCostUploadService : IActualCostUploadService
    {
        private const string CostStage = "COST";
        private const int MaxRows = 5000;
        private const string XlsxContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

        /// <summary>Urutan kolom template (PRD 6.4).</summary>
        private static readonly string[] Headers =
        {
            "Request No", "Month (yyyy-MM)", "Type (Goods/Service)", "Item name", "Qty", "Unit",
            "Unit price", "Amount", "Reference no.", "Notes"
        };

        private static readonly string[] MonthFormats = { "yyyy-MM", "yyyy-MM-dd", "yyyy/MM", "MM/yyyy", "MMM yyyy", "MMMM yyyy", "MMM-yy" };

        private readonly IDbConnectionFactory _connectionFactory;
        private readonly ICurrentUserService _currentUserService;
        private readonly IRequestLookupService _lookupService;
        private readonly FileStorageOptions _storage;
        private readonly ILogger<ActualCostUploadService> _logger;

        public ActualCostUploadService(IDbConnectionFactory connectionFactory, ICurrentUserService currentUserService,
            IRequestLookupService lookupService, IOptions<FileStorageOptions> storage, ILogger<ActualCostUploadService> logger)
        {
            _connectionFactory = connectionFactory;
            _currentUserService = currentUserService;
            _lookupService = lookupService;
            _storage = storage.Value;
            _logger = logger;
        }

        public async Task<(string AllowedExtensions, int MaxSizeMB)> GetFileRulesAsync(CancellationToken ct = default)
        {
            // Stage COST juga berisi ACTUAL_DETAIL (lampiran detail cost per bulan, BR-96): pilih berdasarkan kode
            var types = await _lookupService.GetAttachmentTypesByStageAsync(CostStage, ct);
            var type = types.FirstOrDefault(t => string.Equals(t.Code, "ACTUAL_COST", StringComparison.OrdinalIgnoreCase));
            return type == null ? ("xlsx", 5) : (type.AllowedExtensions, type.MaxSizeMB);
        }

        public async Task<ActualUploadPreview> PreviewAsync(IFormFile? file, CancellationToken ct = default)
        {
            if (file == null || file.Length == 0)
                throw new RequestValidationException("Please choose a file.");

            var originalName = Path.GetFileName(file.FileName);
            if (originalName.Length > 260) originalName = originalName[^260..];
            var (allowedExtensions, maxSizeMb) = await GetFileRulesAsync(ct);
            var ext = Path.GetExtension(originalName).TrimStart('.').ToLowerInvariant();
            var allowed = allowedExtensions.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (ext != "xlsx" || !allowed.Contains(ext, StringComparer.OrdinalIgnoreCase))
                throw new RequestValidationException("Only .xlsx files based on the template are allowed.");
            if (file.Length > maxSizeMb * 1024L * 1024L)
                throw new RequestValidationException($"File size exceeds the maximum of {maxSizeMb} MB.");

            // Baca ke memori (maks. beberapa MB) supaya bisa dipakai untuk parse dan simpan arsip
            using var buffer = new MemoryStream();
            await file.CopyToAsync(buffer, ct);

            var (rows, parseErrors) = Parse(buffer);
            var preview = new ActualUploadPreview { FileName = originalName, RowCount = rows.Count };

            if (parseErrors.Count > 0)
            {
                preview.Errors = parseErrors;
                return preview;
            }

            var (errors, groups) = await ValidateAsync(rows, ct);
            if (errors.Count > 0)
            {
                preview.Errors = errors;
                return preview;
            }

            // Valid: arsipkan file asli (BR-19) lalu catat PENDING
            var relativePath = Path.Combine("ActualCost", DateTime.Now.Year.ToString(CultureInfo.InvariantCulture), $"{Guid.NewGuid():N}.xlsx");
            var fullPath = ResolveFullPath(relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            buffer.Position = 0;
            await using (var stream = new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                await buffer.CopyToAsync(stream, ct);
            }

            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@OriginalFileName", originalName, DbType.String);
            p.Add("@RelativePath", relativePath, DbType.String);
            p.Add("@ContentType", XlsxContentType, DbType.AnsiString);
            p.Add("@FileSizeBytes", file.Length, DbType.Int64);
            p.Add("@RowTotal", rows.Count, DbType.Int32);
            p.Add("@GroupTotal", groups.Count, DbType.Int32);
            p.Add("@TotalAmount", groups.Sum(g => g.TotalAmount), DbType.Decimal, precision: 18, scale: 2);
            p.Add("@NewId", dbType: DbType.Int32, direction: ParameterDirection.Output);

            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    "dbo.usp_ActualUpload_Create", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex)
            {
                TryDelete(fullPath);
                if (ex is OperationCanceledException) throw;
                var mapped = RequestService.Translate(ex, "dbo.usp_ActualUpload_Create", _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }

            preview.UploadId = p.Get<int>("@NewId");
            preview.Groups = groups;
            return preview;
        }

        public async Task<ActualUploadPreview?> GetPendingPreviewAsync(int uploadId, CancellationToken ct = default)
        {
            var found = await GetForDownloadAsync(uploadId, ct);
            if (found == null) return null;
            var (upload, fullPath) = found.Value;
            if (upload.Status != ActualUploadStatus.Pending
                || !string.Equals(upload.CreatedBy, Username, StringComparison.OrdinalIgnoreCase))
                return null;

            List<ActualUploadRow> rows;
            List<ActualUploadError> parseErrors;
            await using (var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                (rows, parseErrors) = Parse(stream);
            }

            var preview = new ActualUploadPreview { UploadId = uploadId, FileName = upload.OriginalFileName, RowCount = rows.Count };
            if (parseErrors.Count > 0)
            {
                preview.Errors = parseErrors;
                return preview;
            }

            var (errors, groups) = await ValidateAsync(rows, ct);
            preview.Errors = errors;
            preview.Groups = groups;
            return preview;
        }

        public async Task<ActualCostUploadItem> ImportAsync(int uploadId, CancellationToken ct = default)
        {
            var found = await GetForDownloadAsync(uploadId, ct)
                ?? throw new RequestNotFoundException("Upload not found.");

            List<ActualUploadRow> rows;
            await using (var stream = new FileStream(found.FullPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                var (parsed, parseErrors) = Parse(stream);
                if (parseErrors.Count > 0)
                    throw new RequestValidationException("The archived file can no longer be read. Please upload it again.");
                rows = parsed;
            }

            var p = new DynamicParameters();
            p.Add("@UploadId", uploadId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);
            p.Add("@RowsJson", ToJson(rows), DbType.String);

            const string procedure = "dbo.usp_ActualUpload_Import";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct, commandTimeout: 120));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }

            return (await GetForDownloadAsync(uploadId, ct))?.Upload ?? found.Upload;
        }

        public async Task CancelAsync(int uploadId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@UploadId", uploadId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            const string procedure = "dbo.usp_ActualUpload_Cancel";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                await conn.ExecuteAsync(new CommandDefinition(procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        public async Task<PagedResult<ActualCostUploadItem>> GetPagedAsync(int pageNumber, int pageSize, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@PageNumber", pageNumber, DbType.Int32);
            p.Add("@PageSize", pageSize, DbType.Int32);
            p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

            using var conn = _connectionFactory.CreateConnection();
            var items = (await conn.QueryAsync<ActualCostUploadItem>(new CommandDefinition(
                "dbo.usp_ActualUpload_GetPaged", p, commandType: CommandType.StoredProcedure, cancellationToken: ct))).AsList();

            return new PagedResult<ActualCostUploadItem>
            {
                Items = items,
                TotalCount = p.Get<int>("@TotalCount"),
                PageNumber = pageNumber < 1 ? 1 : pageNumber,
                PageSize = pageSize
            };
        }

        public async Task<(ActualCostUploadItem Upload, string FullPath)?> GetForDownloadAsync(int uploadId, CancellationToken ct = default)
        {
            var p = new DynamicParameters();
            p.Add("@UploadId", uploadId, DbType.Int32);
            p.Add("@Username", Username, DbType.String);

            using var conn = _connectionFactory.CreateConnection();
            var upload = await conn.QueryFirstOrDefaultAsync<ActualCostUploadItem>(new CommandDefinition(
                "dbo.usp_ActualUpload_GetById", p, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            if (upload?.RelativePath == null) return null;

            var fullPath = ResolveFullPath(upload.RelativePath);
            if (!File.Exists(fullPath))
            {
                _logger.LogWarning("File upload actual cost {UploadId} tidak ditemukan di storage.", uploadId);
                return null;
            }

            return (upload, fullPath);
        }

        public byte[] BuildTemplate()
        {
            using var wb = new XLWorkbook();
            var ws = wb.Worksheets.Add("Actual Cost");
            for (var i = 0; i < Headers.Length; i++)
            {
                var cell = ws.Cell(1, i + 1);
                cell.Value = Headers[i];
                cell.Style.Font.Bold = true;
                cell.Style.Fill.BackgroundColor = XLColor.FromHtml("#DCE6F1");
            }

            // Bulan sebagai teks agar "2026-11" tidak diubah Excel menjadi tanggal; pilihan jenis Goods/Service
            ws.Column(1).Style.NumberFormat.Format = "@";
            ws.Column(2).Style.NumberFormat.Format = "@";
            ws.Range("C2:C5001").CreateDataValidation().List("\"Goods,Service\"", true);
            ws.Range("E2:E5001").Style.NumberFormat.Format = "#,##0.####";
            ws.Range("G2:H5001").Style.NumberFormat.Format = "#,##0.##";
            ws.SheetView.FreezeRows(1);
            ws.Columns(1, Headers.Length).Width = 18;
            ws.Column(4).Width = 36;
            ws.Column(10).Width = 36;

            var help = wb.Worksheets.Add("Instructions");
            var lines = new[]
            {
                "Actual cost upload template (CIMS)",
                "One row per item (goods or service). One file may contain many projects and months.",
                "Request No: the current request number of a project In Progress or BAPP Review.",
                "Month: yyyy-MM (e.g. 2026-11), from the preparation start month up to the current month.",
                "Type: Goods or Service. Qty, Unit price and Amount must be greater than 0; Amount = Qty x Unit price.",
                "Unit: free text (e.g. m, kg, unit, ls). Reference no. (PO/GR/journal) and Notes are optional.",
                "Uploading a project + month again replaces all items of that month. If any row is invalid, nothing is saved."
            };
            for (var i = 0; i < lines.Length; i++) help.Cell(i + 1, 1).Value = lines[i];
            help.Cell(1, 1).Style.Font.Bold = true;
            help.Column(1).Width = 110;

            using var ms = new MemoryStream();
            wb.SaveAs(ms);
            return ms.ToArray();
        }

        /* ------------------------------------------------------------------ */

        private async Task<(List<ActualUploadError> Errors, List<ActualUploadGroup> Groups)> ValidateAsync(
            List<ActualUploadRow> rows, CancellationToken ct)
        {
            var p = new DynamicParameters();
            p.Add("@Username", Username, DbType.String);
            p.Add("@RowsJson", ToJson(rows), DbType.String);

            const string procedure = "dbo.usp_ActualUpload_Validate";
            try
            {
                using var conn = _connectionFactory.CreateConnection();
                using var grid = await conn.QueryMultipleAsync(new CommandDefinition(
                    procedure, p, commandType: CommandType.StoredProcedure, cancellationToken: ct, commandTimeout: 120));
                var errors = (await grid.ReadAsync<ActualUploadError>()).AsList();
                var groups = (await grid.ReadAsync<ActualUploadGroup>()).AsList();
                return (errors, groups);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var mapped = RequestService.Translate(ex, procedure, _logger);
                if (ReferenceEquals(mapped, ex)) throw;
                throw mapped;
            }
        }

        /// <summary>Baca sheet pertama: baris 1 header (urutan kolom template), data mulai baris 2; baris kosong dilewati.</summary>
        private static (List<ActualUploadRow> Rows, List<ActualUploadError> Errors) Parse(Stream stream)
        {
            var rows = new List<ActualUploadRow>();
            var errors = new List<ActualUploadError>();

            XLWorkbook wb;
            try
            {
                stream.Position = 0;
                wb = new XLWorkbook(stream);
            }
            catch (Exception)
            {
                errors.Add(new ActualUploadError { RowNo = 0, Message = "The file cannot be read as an Excel workbook (.xlsx)." });
                return (rows, errors);
            }

            using (wb)
            {
                var ws = wb.Worksheets.First();
                for (var c = 0; c < Headers.Length; c++)
                {
                    var actual = Text(ws.Cell(1, c + 1));
                    var expected = Headers[c].Split(' ')[0];
                    if (actual == null || !actual.StartsWith(expected, StringComparison.OrdinalIgnoreCase))
                    {
                        errors.Add(new ActualUploadError { RowNo = 1, Message = "The header row does not match the template. Please use the CIMS template." });
                        return (rows, errors);
                    }
                }

                var last = ws.LastRowUsed()?.RowNumber() ?? 1;
                for (var r = 2; r <= last; r++)
                {
                    var cells = Enumerable.Range(1, Headers.Length).Select(c => ws.Cell(r, c)).ToArray();
                    if (cells.All(c => c.Value.IsBlank || string.IsNullOrWhiteSpace(Text(c)))) continue;

                    if (rows.Count >= MaxRows)
                    {
                        errors.Add(new ActualUploadError { RowNo = r, Message = $"The file has more than {MaxRows} data rows." });
                        break;
                    }

                    var row = new ActualUploadRow
                    {
                        Row = r,
                        RequestNo = Text(cells[0]),
                        ItemType = MapType(Text(cells[2])),
                        ItemName = Text(cells[3]),
                        Unit = Text(cells[5]),
                        ReferenceNo = Text(cells[8]),
                        Notes = Text(cells[9])
                    };

                    if (!TryMonth(cells[1], out var month))
                        errors.Add(new ActualUploadError { RowNo = r, Message = "Month must be in yyyy-MM format (e.g. 2026-11)." });
                    row.Month = month;

                    row.Qty = Number(cells[4], r, "Qty", errors);
                    row.UnitPrice = Number(cells[6], r, "Unit price", errors);
                    row.Amount = Number(cells[7], r, "Amount", errors);
                    rows.Add(row);
                }

                if (rows.Count == 0 && errors.Count == 0)
                    errors.Add(new ActualUploadError { RowNo = 2, Message = "The file has no data rows." });
            }

            return (rows, errors);
        }

        private static string? Text(IXLCell cell)
        {
            var value = cell.Value;
            if (value.IsBlank) return null;
            var text = value.IsText ? value.GetText() : cell.GetFormattedString();
            text = text.Trim();
            return text.Length == 0 ? null : text;
        }

        private static string? MapType(string? text) => text?.Trim().ToUpperInvariant() switch
        {
            null => null,
            "GOODS" or "BARANG" => ActualItemType.Goods,
            "SERVICE" or "SERVICES" or "JASA" => ActualItemType.Service,
            var other => other
        };

        private static bool TryMonth(IXLCell cell, out DateTime? month)
        {
            month = null;
            var value = cell.Value;
            if (value.IsBlank) return true;   // kosong -> divalidasi SP (wajib)
            if (value.IsDateTime)
            {
                var d = value.GetDateTime();
                month = new DateTime(d.Year, d.Month, 1);
                return true;
            }
            var text = Text(cell);
            if (text == null) return true;
            if (DateTime.TryParseExact(text, MonthFormats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
            {
                month = new DateTime(parsed.Year, parsed.Month, 1);
                return true;
            }
            return false;
        }

        private static decimal? Number(IXLCell cell, int row, string column, List<ActualUploadError> errors)
        {
            var value = cell.Value;
            if (value.IsBlank) return null;
            if (value.IsNumber) return Math.Round((decimal)value.GetNumber(), 4);
            var text = Text(cell);
            if (text == null) return null;
            if (decimal.TryParse(text, NumberStyles.Number, CultureInfo.InvariantCulture, out var parsed)) return parsed;
            errors.Add(new ActualUploadError { RowNo = row, Message = $"{column} must be a number." });
            return null;
        }

        private static string ToJson(IEnumerable<ActualUploadRow> rows) =>
            JsonSerializer.Serialize(rows.Select(r => new
            {
                row = r.Row,
                requestNo = r.RequestNo,
                month = r.Month?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                type = r.ItemType,
                name = r.ItemName,
                qty = r.Qty,
                unit = r.Unit,
                price = r.UnitPrice,
                amount = r.Amount,
                @ref = r.ReferenceNo,
                notes = r.Notes
            }));

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
                throw new InvalidOperationException("Path file upload di luar folder storage.");
            return full;
        }

        private void TryDelete(string fullPath)
        {
            try
            {
                if (File.Exists(fullPath)) File.Delete(fullPath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Gagal menghapus file upload yatim setelah pencatatan gagal.");
            }
        }
    }
}
