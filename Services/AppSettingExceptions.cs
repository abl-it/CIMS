namespace CIMS.Services
{
    /// <summary>SP error 50052: nilai kosong / tidak valid / di luar rentang.</summary>
    public class AppSettingValidationException : Exception
    {
        public AppSettingValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50053: setting tidak ditemukan.</summary>
    public class AppSettingNotFoundException : Exception
    {
        public AppSettingNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
