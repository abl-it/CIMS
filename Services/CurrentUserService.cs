using CIMS.Models;

namespace CIMS.Services
{
    public class CurrentUserService : ICurrentUserService
    {
        public CurrentUser? CurrentUser { get; set; }
    }
}
