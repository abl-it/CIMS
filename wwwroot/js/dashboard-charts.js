// Grafik dashboard (Keputusan 16-11-2026): status keseluruhan per kategori dan biaya bulanan estimasi vs actual.
(function () {
    'use strict';

    var c = window.cimsCharts;
    if (!c) return;
    var data = c.readJson('dashboardChartData');
    if (!data) return;

    // 1) Batang bertumpuk: On Track / At Risk / Delayed per kategori (BR-70)
    var statusCanvas = document.getElementById('chartStatus');
    if (statusCanvas && data.status) {
        new Chart(statusCanvas, {
            type: 'bar',
            data: {
                labels: data.status.map(function (s) { return s.category; }),
                datasets: [
                    { label: 'On Track', data: data.status.map(function (s) { return s.onTrack; }), backgroundColor: c.palette.success },
                    { label: 'At Risk', data: data.status.map(function (s) { return s.atRisk; }), backgroundColor: c.palette.warning },
                    { label: 'Delayed', data: data.status.map(function (s) { return s.delayed; }), backgroundColor: c.palette.danger }
                ]
            },
            options: {
                scales: {
                    x: { stacked: true },
                    y: { stacked: true, beginAtZero: true, ticks: { precision: 0 }, title: { display: true, text: 'Active projects' } }
                }
            }
        });
    }

    // 2) Batang estimasi vs actual per bulan + garis kumulatif (sumbu kanan)
    var costCanvas = document.getElementById('chartCost');
    if (costCanvas && data.cost && data.cost.length) {
        var estimate = data.cost.map(function (m) { return m.estimate; });
        var actual = data.cost.map(function (m) { return m.actual; });
        new Chart(costCanvas, {
            type: 'bar',
            data: {
                labels: data.cost.map(function (m) { return m.month; }),
                datasets: [
                    { label: 'Estimate', data: estimate, backgroundColor: c.palette.secondary, yAxisID: 'y', order: 2 },
                    { label: 'Actual', data: actual, backgroundColor: c.palette.primary, yAxisID: 'y', order: 2 },
                    { type: 'line', label: 'Cumulative estimate', data: c.cumulative(estimate), borderColor: c.palette.secondary,
                      borderDash: [6, 4], pointRadius: 2, tension: 0.2, yAxisID: 'y1', order: 1 },
                    { type: 'line', label: 'Cumulative actual', data: c.cumulative(actual), borderColor: c.palette.primary,
                      pointRadius: 2, tension: 0.2, spanGaps: false, yAxisID: 'y1', order: 1 }
                ]
            },
            options: {
                interaction: { mode: 'index', intersect: false },
                plugins: { tooltip: { callbacks: { label: c.idrTooltip } } },
                scales: {
                    y: { beginAtZero: true, position: 'left', ticks: { callback: c.compact }, title: { display: true, text: 'Per month (IDR)' } },
                    y1: { beginAtZero: true, position: 'right', grid: { drawOnChartArea: false }, ticks: { callback: c.compact },
                          title: { display: true, text: 'Cumulative (IDR)' } }
                }
            }
        });
    }
})();
