using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>Request / business case (T2). Semua akses dibatasi lingkup data user (fn_User_AllowedDepartments).</summary>
    public interface IRequestService
    {
        /// <param name="addendumOpen">true = hanya project dengan addendum terbuka (T4-4, follow up).</param>
        Task<PagedResult<RequestListItem>> GetPagedAsync(string? coCode, int? departmentId, string? search, string? category,
            string? status, string? sortBy, string? sortDir, int pageNumber, int pageSize, bool addendumOpen = false,
            CancellationToken ct = default);

        /// <returns>null bila tidak ada atau di luar lingkup user.</returns>
        Task<ProjectRequest?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <summary>Draft/Returned: pertanyaan aktif + jawaban; status lain: snapshot jawaban.</summary>
        Task<IReadOnlyList<RequestAssessmentItem>> GetAssessmentAsync(int requestId, CancellationToken ct = default);

        /// <summary>Simpan draft baru (Id = 0) atau ubah draft/returned. Jawaban null = belum dijawab (tidak disimpan).</summary>
        /// <returns>Id request.</returns>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        Task<int> SaveDraftAsync(ProjectRequest request, IEnumerable<RequestAnswerInput> answers, CancellationToken ct = default);

        /// <summary>Submit pertama / Resubmit (T2-2): cek kelengkapan, nomor, snapshot langkah approval.</summary>
        /// <returns>Nomor request dan status baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (pesan memuat daftar kekurangan).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        Task<(string RequestNo, string Status)> SubmitAsync(int id, CancellationToken ct = default);

        /// <summary>Batalkan request (BR-09); alasan wajib.</summary>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        Task CancelAsync(int id, string? reason, CancellationToken ct = default);

        /// <summary>Langkah approval ronde terakhir per titik.</summary>
        Task<IReadOnlyList<ApprovalStepItem>> GetApprovalStepsAsync(int requestId, CancellationToken ct = default);

        /// <summary>Jejak aksi, terbaru di atas.</summary>
        Task<IReadOnlyList<ApprovalHistoryItem>> GetHistoryAsync(int requestId, CancellationToken ct = default);

        /// <summary>Langkah approval aktif yang boleh diproses user saat ini (T2-3); null = tidak ada.</summary>
        Task<ApprovalStepItem?> GetActionableStepAsync(int requestId, CancellationToken ct = default);

        /// <summary>Approve / Revise / Reject langkah titik REQUEST (BR-03, BR-08, BR-30, BR-39, BR-50).</summary>
        /// <param name="action">APPROVE | REVISE | REJECT (lihat <see cref="ApprovalAction"/>).</param>
        /// <returns>Status request yang baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074 (termasuk sudah diproses approver lain).</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075.</exception>
        Task<string> ApprovalActAsync(int id, int stepId, string action, string? remarks, CancellationToken ct = default);

        /// <summary>Ubah kategori / sub-kategori saat Feasibility oleh Civil (BR-02); kategori berubah -> nomor baru (BR-54).</summary>
        /// <returns>Nomor request setelah perubahan.</returns>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<string?> ChangeCategoryAsync(int id, string category, int subCategoryId, string? reason, CancellationToken ct = default);

        /// <summary>Keputusan Feasibility oleh Civil: FEASIBLE | REVISE | REJECT (lihat <see cref="FeasibilityDecision"/>).</summary>
        /// <returns>Status request yang baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (termasuk lampiran wajib belum lengkap).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<string> FeasibilityDecideAsync(int id, string decision, string? remarks, CancellationToken ct = default);

        /// <summary>Isi / ubah BOQ total (IDR) saat Document Preparation oleh Civil (BR-05, BR-12).</summary>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task SetBoqTotalAsync(int id, decimal boqTotal, CancellationToken ct = default);

        /// <summary>Kirim ke management (BR-53: langkah MGMT disusun saat ini). Wajib BOQ total + lampiran DOCUMENT wajib.</summary>
        /// <returns>Status request yang baru (MGMT_APPROVAL, atau PLANNING bila tidak ada langkah MGMT).</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (pesan memuat daftar kekurangan).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<string> SendToManagementAsync(int id, string? remarks, CancellationToken ct = default);

        /// <summary>Civil memilih In-house (-> SCHEDULING, plan cost = BOQ) atau Outsource (-> PROCUREMENT, wajib TOR) (T4-1; BR-11, BR-12, BR-15).</summary>
        /// <param name="executionType">INHOUSE | OUTSOURCE (lihat <see cref="RequestExecutionType"/>).</param>
        /// <returns>Status request yang baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (BOQ / TOR belum ada).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<string> ChooseExecutionAsync(int id, string executionType, string? remarks, CancellationToken ct = default);

        /// <summary>Purchasing menyimpan / mengubah data kontrak saat PROCUREMENT (BR-11).</summary>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Purchasing).</exception>
        Task SaveContractAsync(int id, int vendorId, string contractNo, DateTime contractDate, decimal contractValue,
            string? remarks, CancellationToken ct = default);

        /// <summary>Purchasing menyelesaikan procurement (wajib kontrak + lampiran kontrak) -> SCHEDULING, plan cost = nilai kontrak.</summary>
        /// <returns>Status request yang baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (pesan memuat daftar kekurangan).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Purchasing).</exception>
        Task<string> CompleteProcurementAsync(int id, CancellationToken ct = default);

        /// <summary>Purchasing mengembalikan TOR ke Civil (-> PLANNING); alasan wajib (Keputusan 14-11-2026).</summary>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Purchasing).</exception>
        Task ReturnTorAsync(int id, string? reason, CancellationToken ct = default);

        /// <summary>Kontrak request (null = belum ada / di luar lingkup).</summary>
        Task<ProjectContract?> GetContractAsync(int requestId, CancellationToken ct = default);

        /// <summary>Schedule, action plan, estimasi (T4-2); null = tidak ada / di luar lingkup / tanpa akses.</summary>
        Task<ProjectSchedule?> GetScheduleAsync(int requestId, CancellationToken ct = default);

        /// <summary>Simpan tanggal mulai project + seluruh action plan (BR-15, BR-16). In Progress: alasan wajib, total bobot 100%.</summary>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task SaveScheduleAsync(int id, DateTime projectStartDate, IEnumerable<ActionPlanInput> actionPlans, string? reason,
            CancellationToken ct = default);

        /// <summary>Ganti seluruh estimasi biaya bulanan (BR-13). In Progress: alasan wajib, total = plan cost.</summary>
        /// <param name="estimates">Bulan (tanggal 1) dan nilai.</param>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task SaveCostEstimateAsync(int id, IEnumerable<(DateTime Month, decimal Amount)> estimates, string? reason,
            CancellationToken ct = default);

        /// <summary>Site handover (ST-11): Scheduling -> In Progress; wajib bobot 100% dan estimasi = plan cost.</summary>
        /// <returns>Status request yang baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (pesan memuat daftar kekurangan).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<string> SiteHandoverAsync(int id, DateTime handoverDate, string? remarks, CancellationToken ct = default);

        /// <summary>Input project berjalan oleh Civil (T4-3; FR-03, BR-76, BR-77): langsung Planning / Scheduling, IsMigrated = 1.</summary>
        /// <returns>Id, nomor request, dan status.</returns>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<(int Id, string RequestNo, string Status)> CreateRunningAsync(RunningProjectFormViewModel model, CancellationToken ct = default);

        /// <summary>Ringkasan progress + daftar minggu (T5-1); null = tidak ada / tanpa akses.</summary>
        Task<ProjectProgress?> GetProgressAsync(int requestId, CancellationToken ct = default);

        /// <summary>Kurva S project: % plan dan % aktual per minggu (grafik Details; BR-17). Kosong bila tanpa akses / schedule.</summary>
        Task<IReadOnlyList<ProgressCurvePoint>> GetProgressCurveAsync(int requestId, CancellationToken ct = default);

        /// <summary>Data form progress untuk minggu yang memuat <paramref name="weekDate"/>; null = tanpa akses.</summary>
        Task<ProgressWeekForm?> GetProgressWeekAsync(int requestId, DateTime weekDate, CancellationToken ct = default);

        /// <summary>Simpan progress mingguan (BR-16, BR-17, BR-68); status jadwal dihitung SP (BR-71).</summary>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<ProgressSaveResult> SaveProgressAsync(int id, DateTime weekDate, IEnumerable<ProgressInput> items, string? remarks,
            CancellationToken ct = default);

        /// <summary>Ringkasan biaya + estimasi vs actual per bulan (T5-2); null = tidak ada / tanpa akses.</summary>
        Task<ProjectActualCost?> GetActualCostAsync(int requestId, CancellationToken ct = default);

        /// <summary>Header + item satu bulan; null = tidak berhak melihat detail.</summary>
        Task<ActualMonthForm?> GetActualMonthAsync(int requestId, DateTime month, CancellationToken ct = default);

        /// <summary>Ganti seluruh item actual satu bulan (BR-18, BR-19); daftar kosong = hapus bulan. Status biaya dihitung SP.</summary>
        /// <param name="source">MANUAL | EXCEL (T5-3, dengan <paramref name="attachmentId"/>).</param>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<ActualSaveResult> SaveActualMonthAsync(int id, DateTime month, IEnumerable<ActualItemInput> items, string? remarks,
            string source = "MANUAL", int? attachmentId = null, CancellationToken ct = default);

        /// <summary>Log perubahan kategori (BR-02), terbaru di atas.</summary>
        Task<IReadOnlyList<CategoryChangeItem>> GetCategoryChangesAsync(int requestId, CancellationToken ct = default);
    }
}
