namespace CIMS.Services
{
    /// <summary>SP error 50011: nama lokasi duplikat pada Company yang sama.</summary>
    public class LocationDuplicateNameException : Exception
    {
        public LocationDuplicateNameException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50012: input wajib kosong / tidak valid.</summary>
    public class LocationValidationException : Exception
    {
        public LocationValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50013: data lokasi tidak ditemukan.</summary>
    public class LocationNotFoundException : Exception
    {
        public LocationNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
