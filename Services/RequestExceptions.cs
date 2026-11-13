namespace CIMS.Services
{
    /// <summary>SP error 50072: input wajib kosong / tidak valid (request atau lampiran).</summary>
    public class RequestValidationException : Exception
    {
        public RequestValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50073: request / lampiran tidak ditemukan atau di luar lingkup user.</summary>
    public class RequestNotFoundException : Exception
    {
        public RequestNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50074: status request tidak mengizinkan aksi ini.</summary>
    public class RequestInvalidStateException : Exception
    {
        public RequestInvalidStateException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50075: user tidak berhak memproses langkah approval (role, lingkup, Company, request sendiri).</summary>
    public class RequestNotAuthorizedException : Exception
    {
        public RequestNotAuthorizedException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
