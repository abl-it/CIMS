using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>Pilihan dropdown form request (data portal "home" dan master CIMS).</summary>
    public interface IRequestLookupService
    {
        /// <summary>Cost center = sub-department aktif milik department (BR-40).</summary>
        Task<IReadOnlyList<CostCenterOption>> GetCostCentersAsync(int departmentId, CancellationToken ct = default);

        /// <summary>Karyawan aktif pada department (pilihan PIC); maksimal 200 baris.</summary>
        Task<IReadOnlyList<EmployeeOption>> GetActiveEmployeesAsync(int departmentId, string? search = null, CancellationToken ct = default);

        /// <summary>Lokasi aktif per Company (BR-61).</summary>
        Task<IReadOnlyList<LocationOption>> GetLocationsAsync(string coCode, CancellationToken ct = default);

        /// <summary>Pertanyaan Environment Assessment aktif, urut SortOrder.</summary>
        Task<IReadOnlyList<RequestAssessmentItem>> GetAssessmentQuestionsAsync(CancellationToken ct = default);

        /// <summary>Jenis lampiran aktif pada satu tahap (mis. REQUEST).</summary>
        Task<IReadOnlyList<AttachmentType>> GetAttachmentTypesByStageAsync(string stage, CancellationToken ct = default);
    }
}
