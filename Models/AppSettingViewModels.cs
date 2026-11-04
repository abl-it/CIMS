using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class AppSettingListViewModel
    {
        /// <summary>Filter Company ('*', ABL, NKM); null = semua baris.</summary>
        public string? CoCode { get; set; }

        public IReadOnlyList<AppSetting> Items { get; set; } = Array.Empty<AppSetting>();
    }

    public class AppSettingFormViewModel
    {
        [Required]
        public string CoCode { get; set; } = string.Empty;

        [Required]
        public string SettingKey { get; set; } = string.Empty;

        [Display(Name = "Value")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(200, ErrorMessage = "{0} must be at most {1} characters.")]
        public string SettingValue { get; set; } = string.Empty;

        // Hanya tampilan (dimuat ulang dari database, tidak dipercaya dari form).
        public string ValueType { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string Label { get; set; } = string.Empty;
        public string Unit { get; set; } = string.Empty;
        public string CompanyLabel { get; set; } = string.Empty;
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }

        /// <summary>Isi field tampilan dari entity (nilai input user tidak ditimpa).</summary>
        public void LoadDisplay(AppSetting s)
        {
            ValueType = s.ValueType;
            Description = s.Description;
            Label = s.Label;
            Unit = s.Unit;
            CompanyLabel = s.CompanyLabel;
            UpdatedAt = s.UpdatedAt;
            UpdatedBy = s.UpdatedBy;
        }

        public static AppSettingFormViewModel FromEntity(AppSetting s)
        {
            var vm = new AppSettingFormViewModel
            {
                CoCode = s.CoCode,
                SettingKey = s.SettingKey,
                SettingValue = s.SettingValue
            };
            vm.LoadDisplay(s);
            return vm;
        }
    }
}
