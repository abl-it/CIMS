namespace CIMS.Models
{
    /// <summary>
    /// Setting aplikasi (dbo.AppSetting; CF-02, CF-08). CoCode '*' = semua Company (fallback).
    /// Halaman Settings hanya mengubah SettingValue; key dan override per Company lewat script SQL (BR-38).
    /// </summary>
    public class AppSetting
    {
        /// <summary>CoCode yang valid (sama dengan CHECK constraint).</summary>
        public static readonly string[] CoCodes = { "*", "ABL", "NKM" };

        /// <summary>Nama tampilan dan satuan per key; key lain tampil apa adanya.</summary>
        private static readonly Dictionary<string, (string Label, string Unit)> KeyInfo = new(StringComparer.OrdinalIgnoreCase)
        {
            ["EMERGENCY_FOLLOWUP_WORKDAYS"] = ("Emergency follow-up approval limit", "working days"),
            ["SCHEDULE_ONTRACK_MIN_DEV"] = ("Schedule: On Track minimum deviation", "% points"),
            ["SCHEDULE_SLIGHT_MIN_DEV"] = ("Schedule: Slightly Delay minimum deviation", "% points"),
            ["COST_ONTRACK_MAX_PCT"] = ("Cost: On Track maximum ratio", "%"),
            ["COST_ATRISK_MAX_PCT"] = ("Cost: At Risk maximum ratio", "%")
        };

        public string CoCode { get; set; } = string.Empty;
        public string SettingKey { get; set; } = string.Empty;
        public string SettingValue { get; set; } = string.Empty;
        public string ValueType { get; set; } = string.Empty;
        public string? Description { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }

        public string Label => KeyInfo.TryGetValue(SettingKey, out var i) ? i.Label : SettingKey;
        public string Unit => KeyInfo.TryGetValue(SettingKey, out var i) ? i.Unit : string.Empty;

        public string CompanyLabel => CompanyText(CoCode);

        public static string CompanyText(string? coCode) => coCode == "*" ? "All companies" : coCode ?? string.Empty;
    }
}
