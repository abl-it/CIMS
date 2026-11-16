// Grafik di halaman Details request (Keputusan 16-11-2026):
// - Kurva S: % plan (garis) vs % aktual (garis bertitik; minggu yang belum diisi dilewati) per minggu (BR-17).
// - Kurva biaya: estimasi kumulatif vs actual kumulatif per bulan (BR-69); bulan tanpa actual tidak menambah actual.
(function () {
    'use strict';

    var c = window.cimsCharts;
    if (!c) return;
    var data = c.readJson('requestChartData');
    if (!data) return;

    var sCanvas = document.getElementById('chartSCurve');
    if (sCanvas && data.scurve && data.scurve.length) {
        new Chart(sCanvas, {
            type: 'line',
            data: {
                labels: data.scurve.map(function (p) { return p.week; }),
                datasets: [
                    { label: 'Plan', data: data.scurve.map(function (p) { return p.plan; }), borderColor: c.palette.secondary,
                      borderDash: [6, 4], pointRadius: 0, tension: 0.2 },
                    { label: 'Actual', data: data.scurve.map(function (p) { return p.actual; }), borderColor: c.palette.primary,
                      backgroundColor: c.palette.primary, pointRadius: 3, tension: 0.2, spanGaps: true }
                ]
            },
            options: {
                interaction: { mode: 'index', intersect: false },
                plugins: {
                    tooltip: {
                        callbacks: {
                            title: function (items) { return 'Week of ' + items[0].label; },
                            label: function (ctx) { return ctx.parsed.y === null ? null : ctx.dataset.label + ': ' + c.percent.format(ctx.parsed.y) + '%'; }
                        }
                    }
                },
                scales: {
                    y: { min: 0, max: 100, ticks: { callback: function (v) { return v + '%'; } }, title: { display: true, text: 'Progress' } }
                }
            }
        });
    }

    var costCanvas = document.getElementById('chartCostCurve');
    if (costCanvas && data.cost && data.cost.length) {
        // Actual kumulatif: bulan tanpa actual dianggap 0 sampai bulan actual terakhir, sesudahnya kosong
        var lastActual = -1;
        data.cost.forEach(function (m, i) { if (m.actual !== null) lastActual = i; });
        var actual = data.cost.map(function (m, i) { return i <= lastActual ? (m.actual || 0) : null; });

        new Chart(costCanvas, {
            type: 'line',
            data: {
                labels: data.cost.map(function (m) { return m.month; }),
                datasets: [
                    { label: 'Cumulative estimate', data: c.cumulative(data.cost.map(function (m) { return m.estimate; })),
                      borderColor: c.palette.secondary, borderDash: [6, 4], pointRadius: 2, tension: 0.2 },
                    { label: 'Cumulative actual', data: c.cumulative(actual), borderColor: c.palette.primary,
                      backgroundColor: c.palette.primary, pointRadius: 3, tension: 0.2 }
                ]
            },
            options: {
                interaction: { mode: 'index', intersect: false },
                plugins: { tooltip: { callbacks: { label: c.idrTooltip } } },
                scales: { y: { beginAtZero: true, ticks: { callback: c.compact }, title: { display: true, text: 'IDR' } } }
            }
        });
    }
})();
