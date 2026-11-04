namespace CIMS.Services
{
    /// <summary>SP error 50031: pertanyaan duplikat.</summary>
    public class AssessmentQuestionDuplicateException : Exception
    {
        public AssessmentQuestionDuplicateException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50032: input wajib kosong / tidak valid.</summary>
    public class AssessmentQuestionValidationException : Exception
    {
        public AssessmentQuestionValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50033: pertanyaan tidak ditemukan.</summary>
    public class AssessmentQuestionNotFoundException : Exception
    {
        public AssessmentQuestionNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
