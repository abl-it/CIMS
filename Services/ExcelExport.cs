using ClosedXML.Excel;

namespace CIMS.Services
{
    /// <summary>
    /// Export Excel sederhana dari list (FR-04): satu sheet, baris judul + filter, header, data.
    /// Tanpa akses database; dipakai Controller setelah data diambil lewat Service.
    /// </summary>
    public static class ExcelExport
    {
        public const string ContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

        /// <summary>Definisi kolom: judul, nilai per baris, format angka/tanggal Excel (opsional).</summary>
        public sealed record Column<T>(string Header, Func<T, object?> Value, string? Format = null);

        /// <param name="title">Judul di baris 1.</param>
        /// <param name="filterText">Ringkasan filter aktif di baris 2 (opsional).</param>
        public static byte[] Build<T>(string sheetName, string title, string? filterText,
            IReadOnlyList<Column<T>> columns, IEnumerable<T> rows)
        {
            using var wb = new XLWorkbook();
            var ws = wb.Worksheets.Add(sheetName);

            ws.Cell(1, 1).Value = title;
            ws.Cell(1, 1).Style.Font.Bold = true;
            ws.Cell(1, 1).Style.Font.FontSize = 14;
            ws.Cell(2, 1).Value = $"Exported {DateTime.Now:dd MMM yyyy HH:mm}" + (string.IsNullOrWhiteSpace(filterText) ? "" : " · " + filterText);

            const int headerRow = 4;
            for (var c = 0; c < columns.Count; c++)
            {
                var cell = ws.Cell(headerRow, c + 1);
                cell.Value = columns[c].Header;
                cell.Style.Font.Bold = true;
                cell.Style.Fill.BackgroundColor = XLColor.FromHtml("#DCE6F1");
            }

            var r = headerRow + 1;
            foreach (var row in rows)
            {
                for (var c = 0; c < columns.Count; c++)
                {
                    var cell = ws.Cell(r, c + 1);
                    cell.Value = ToCellValue(columns[c].Value(row));
                    if (columns[c].Format != null) cell.Style.NumberFormat.Format = columns[c].Format;
                }
                r++;
            }

            ws.SheetView.FreezeRows(headerRow);
            if (r > headerRow + 1) ws.Range(headerRow, 1, r - 1, columns.Count).SetAutoFilter();
            ws.Columns(1, columns.Count).AdjustToContents(headerRow, Math.Min(r, headerRow + 500));

            using var ms = new MemoryStream();
            wb.SaveAs(ms);
            return ms.ToArray();
        }

        private static XLCellValue ToCellValue(object? value) => value switch
        {
            null => Blank.Value,
            string s => s,
            DateTime d => d,
            decimal m => m,
            int i => i,
            long l => l,
            double db => db,
            bool b => b,
            _ => value.ToString() ?? string.Empty
        };
    }
}
