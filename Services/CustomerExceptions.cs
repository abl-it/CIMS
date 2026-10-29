namespace CIMS.Services
{
    /// <summary>SP error 50001: kode customer duplikat.</summary>
    public class CustomerDuplicateCodeException : Exception
    {
        public CustomerDuplicateCodeException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50002: input wajib kosong.</summary>
    public class CustomerValidationException : Exception
    {
        public CustomerValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50003: data customer tidak ditemukan.</summary>
    public class CustomerNotFoundException : Exception
    {
        public CustomerNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
