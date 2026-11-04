namespace CIMS.Services
{
    /// <summary>SP error 50041: item duplikat pada kategori yang sama.</summary>
    public class SurveyTemplateItemDuplicateException : Exception
    {
        public SurveyTemplateItemDuplicateException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50042: input wajib kosong / tidak valid.</summary>
    public class SurveyTemplateItemValidationException : Exception
    {
        public SurveyTemplateItemValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50043: item survei tidak ditemukan.</summary>
    public class SurveyTemplateItemNotFoundException : Exception
    {
        public SurveyTemplateItemNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
