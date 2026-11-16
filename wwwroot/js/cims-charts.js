// Helper grafik CIMS (Chart.js 4, lokal di wwwroot/lib/chart.js). Dipakai dashboard-charts.js dan request-charts.js.
// Warna diambil dari variabel CSS Bootstrap agar konsisten dengan badge status; angka format en-US (UI Inggris).
(function () {
    'use strict';

    if (!window.Chart) return;

    var css = getComputedStyle(document.documentElement);
    var color = function (name, fallback) {
        var v = css.getPropertyValue(name).trim();
        return v || fallback;
    };

    var palette = {
        success: color('--bs-success', '#198754'),
        warning: color('--bs-warning', '#ffc107'),
        danger: color('--bs-danger', '#dc3545'),
        primary: color('--bs-primary', '#0d6efd'),
        secondary: color('--bs-secondary', '#6c757d'),
        body: color('--bs-body-color', '#212529'),
        border: color('--bs-border-color', '#dee2e6')
    };

    var number = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
    var percent = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });

    // Angka ringkas untuk sumbu (1.2M, 350K)
    var compact = function (v) {
        var a = Math.abs(v);
        if (a >= 1e9) return (v / 1e9).toFixed(1).replace(/\.0$/, '') + 'B';
        if (a >= 1e6) return (v / 1e6).toFixed(1).replace(/\.0$/, '') + 'M';
        if (a >= 1e3) return (v / 1e3).toFixed(0) + 'K';
        return String(v);
    };

    Chart.defaults.font.family = getComputedStyle(document.body).fontFamily;
    Chart.defaults.color = palette.body;
    Chart.defaults.borderColor = palette.border;
    Chart.defaults.maintainAspectRatio = false;
    Chart.defaults.plugins.legend.position = 'bottom';

    window.cimsCharts = {
        palette: palette,
        number: number,
        percent: percent,
        compact: compact,

        // Data JSON dari <script type="application/json" id="...">
        readJson: function (id) {
            var el = document.getElementById(id);
            if (!el) return null;
            try { return JSON.parse(el.textContent); } catch (e) { return null; }
        },

        // Jumlah kumulatif; null tetap null (mis. actual sesudah bulan terpilih)
        cumulative: function (values) {
            var sum = 0;
            return values.map(function (v) {
                if (v === null || v === undefined) return null;
                sum += Number(v);
                return sum;
            });
        },

        // Tooltip IDR untuk grafik biaya
        idrTooltip: function (ctx) {
            var v = ctx.parsed.y;
            return v === null ? null : ctx.dataset.label + ': IDR ' + number.format(v);
        }
    };
})();
