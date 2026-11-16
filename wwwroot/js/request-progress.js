// Form progress mingguan di halaman Details request (T5-1; BR-16, BR-17).
// - % aktual project minggu ini = Σ(bobot × % progress) / 100, tampil langsung.
// - Tanggal aktual mengikuti progress: mulai wajib bila > 0%; selesai wajib bila 100%, dinonaktifkan bila < 100%.
// - Batas min/max (tidak turun dari minggu sebelumnya) dicek browser lewat atribut min/max.
// Validasi akhir tetap di stored procedure.
(function () {
    'use strict';

    var form = document.querySelector('form[data-progress-form]');
    if (!form) return;

    var fmt = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });
    var totalEl = form.querySelector('[data-progress-total]');
    var rows = Array.from(form.querySelectorAll('[data-progress-row]'));

    var valueOf = function (input) {
        var v = parseFloat(input.value);
        return isNaN(v) ? 0 : v;
    };

    var applyRow = function (row) {
        var progress = valueOf(row.querySelector('[data-progress-value]'));
        var start = row.querySelector('[data-actual-start]');
        var end = row.querySelector('[data-actual-end]');
        start.required = progress > 0;
        var done = progress >= 100;
        end.required = done;
        end.disabled = !done;
        if (!done) end.value = '';
        end.min = start.value || '';
    };

    var updateTotal = function () {
        var total = rows.reduce(function (sum, row) {
            var weight = parseFloat(row.getAttribute('data-weight')) || 0;
            return sum + weight * valueOf(row.querySelector('[data-progress-value]')) / 100;
        }, 0);
        totalEl.textContent = fmt.format(Math.round(total * 100) / 100);
    };

    form.addEventListener('input', function (e) {
        var row = e.target.closest('[data-progress-row]');
        if (!row) return;
        applyRow(row);
        updateTotal();
    });

    rows.forEach(applyRow);
    updateTotal();
})();
