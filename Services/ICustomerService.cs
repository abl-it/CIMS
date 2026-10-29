using CIMS.Models;

namespace CIMS.Services
{
    public interface ICustomerService
    {
        Task<PagedResult<Customer>> GetPagedAsync(string? search, bool? isActive, string? sortBy, string? sortDir,
            int pageNumber, int pageSize, CancellationToken ct = default);

        Task<Customer?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <returns>Id customer baru.</returns>
        /// <exception cref="CustomerDuplicateCodeException">SP error 50001.</exception>
        /// <exception cref="CustomerValidationException">SP error 50002.</exception>
        Task<int> InsertAsync(Customer customer, CancellationToken ct = default);

        /// <exception cref="CustomerDuplicateCodeException">SP error 50001.</exception>
        /// <exception cref="CustomerValidationException">SP error 50002.</exception>
        /// <exception cref="CustomerNotFoundException">SP error 50003.</exception>
        Task UpdateAsync(Customer customer, CancellationToken ct = default);

        /// <exception cref="CustomerNotFoundException">SP error 50003.</exception>
        Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default);
    }
}
