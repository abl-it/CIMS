using System.Globalization;
using CIMS.Filters;
using CIMS.Models;
using CIMS.Services;
using Microsoft.AspNetCore.Mvc;

namespace CIMS.Controllers
{
    /// <summary>
    /// Upload actual cost via template Excel (T5-3; PRD 6.4, BR-18, BR-19). Matriks 5.2 "Upload actual cost":
    /// civil = C; fat, gm, director, administrator = R (riwayat + unduh arsip).
    /// </summary>
    [RoleAuthorize(CimsRoles.Civil, CimsRoles.Fat, CimsRoles.Dgo, CimsRoles.Gm, CimsRoles.Director, CimsRoles.Administrator)]
    public class ActualCostUploadController : Controller
    {
        /// <summary>Batas body upload: di atas ukuran maksimum jenis lampiran COST (5 MB) + overhead multipart.</summary>
        private const long UploadBodyLimit = 25L * 1024 * 1024;

        private readonly IActualCostUploadService _uploadService;
        private readonly ICurrentUserService _currentUserService;

        public ActualCostUploadController(IActualCostUploadService uploadService, ICurrentUserService currentUserService)
        {
            _uploadService = uploadService;
            _currentUserService = currentUserService;
        }

        [HttpGet]
        public async Task<IActionResult> Index(int page = 1, CancellationToken ct = default)
        {
            const int pageSize = 10;
            if (page < 1) page = 1;

            var result = await _uploadService.GetPagedAsync(page, pageSize, ct);
            if (result.TotalCount > 0 && page > result.TotalPages)
                return RedirectToAction(nameof(Index), new { page = result.TotalPages });

            var (extensions, maxSize) = await _uploadService.GetFileRulesAsync(ct);
            return View(new ActualUploadIndexViewModel
            {
                Page = page,
                PageSize = pageSize,
                CanUpload = CimsRoles.HasAny(_currentUserService.CurrentUser, new[] { CimsRoles.Civil }),
                CurrentUsername = _currentUserService.CurrentUser?.Username,
                AllowedExtensions = extensions,
                MaxSizeMB = maxSize,
                Result = result
            });
        }

        /// <summary>Template Excel kosong (kolom PRD 6.4).</summary>
        [HttpGet]
        [RoleAuthorize(CimsRoles.Civil)]
        public IActionResult Template()
        {
            return File(_uploadService.BuildTemplate(),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "CIMS-actual-cost-template.xlsx");
        }

        /// <summary>Upload + validasi (all or nothing). Valid -> arsip PENDING + halaman preview untuk konfirmasi.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        [RequestSizeLimit(UploadBodyLimit)]
        [RequestFormLimits(MultipartBodyLengthLimit = UploadBodyLimit)]
        public async Task<IActionResult> Upload(IFormFile? file, CancellationToken ct)
        {
            try
            {
                var preview = await _uploadService.PreviewAsync(file, ct);
                return View("Preview", preview);
            }
            catch (Exception ex) when (ex is RequestValidationException or RequestNotAuthorizedException)
            {
                TempData["Error"] = ex.Message;
                return RedirectToAction(nameof(Index));
            }
        }

        /// <summary>Lanjutkan upload PENDING (preview belum dikonfirmasi/dibatalkan): validasi ulang file arsip.</summary>
        [HttpGet]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> Preview(int id, CancellationToken ct)
        {
            var preview = await _uploadService.GetPendingPreviewAsync(id, ct);
            if (preview == null)
            {
                TempData["Error"] = "This upload cannot be continued: it is not pending, not yours, or its file is missing from the archive.";
                return RedirectToAction(nameof(Index));
            }

            return View("Preview", preview);
        }

        /// <summary>Konfirmasi: simpan semua project + bulan dari file (satu transaksi).</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> Confirm(int uploadId, CancellationToken ct)
        {
            try
            {
                var upload = await _uploadService.ImportAsync(uploadId, ct);
                TempData["Success"] = $"Actual cost imported from {upload.OriginalFileName}: {upload.GroupTotal} project-month(s), "
                                      + $"IDR {upload.TotalAmount.ToString("#,0.##", CultureInfo.InvariantCulture)}.";
            }
            catch (Exception ex) when (ex is RequestValidationException or RequestNotFoundException
                                           or RequestInvalidStateException or RequestNotAuthorizedException)
            {
                TempData["Error"] = ex.Message;
            }

            return RedirectToAction(nameof(Index));
        }

        /// <summary>Batal setelah preview; file tetap diarsipkan (CANCELLED).</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        [RoleAuthorize(CimsRoles.Civil)]
        public async Task<IActionResult> Cancel(int uploadId, CancellationToken ct)
        {
            try
            {
                await _uploadService.CancelAsync(uploadId, ct);
                TempData["Success"] = "Upload cancelled. No data was saved.";
            }
            catch (RequestValidationException ex)
            {
                TempData["Error"] = ex.Message;
            }

            return RedirectToAction(nameof(Index));
        }

        /// <summary>Unduh file arsip asli (BR-19).</summary>
        [HttpGet]
        public async Task<IActionResult> Download(int id, CancellationToken ct)
        {
            var found = await _uploadService.GetForDownloadAsync(id, ct);
            if (found == null)
            {
                // Tidak berhak / data tidak ada / file fisik hilang dari arsip -> pesan, bukan halaman 404 kosong
                TempData["Error"] = "The file is not available in the archive.";
                return RedirectToAction(nameof(Index));
            }

            var (upload, fullPath) = found.Value;
            return PhysicalFile(fullPath, upload.ContentType ?? "application/octet-stream", upload.OriginalFileName);
        }
    }
}
