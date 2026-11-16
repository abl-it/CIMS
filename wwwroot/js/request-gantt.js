// Gantt schedule vs actual di Details > Schedule (Frappe Gantt 0.6.1 lokal; Keputusan 16-11-2026, sebagian T8).
// Baris: Preparation (BR-15) lalu per action plan: Plan (isi = % progress terkini) dan Actual
// (mulai aktual s.d. selesai aktual; bila belum selesai s.d. hari ini). Hanya tampilan: tidak bisa di-drag.
(function () {
    'use strict';

    if (!window.Gantt) return;
    var el = document.getElementById('ganttData');
    var target = document.getElementById('ganttSchedule');
    if (!el || !target) return;

    var data;
    try { data = JSON.parse(el.textContent); } catch (e) { return; }
    if (!data || !data.plans || !data.plans.length) return;

    var addDays = function (iso, days) {
        var d = new Date(iso + 'T00:00:00');
        d.setDate(d.getDate() + days);
        return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    };

    var tasks = [];

    // Periode Preparation: awal Preparation s.d. sehari sebelum mulai project
    if (data.preparationStart && data.projectStart && data.preparationStart < data.projectStart) {
        tasks.push({
            id: 'prep', name: 'Preparation', start: data.preparationStart, end: addDays(data.projectStart, -1),
            progress: 0, custom_class: 'gantt-prep'
        });
    }

    data.plans.forEach(function (p) {
        tasks.push({
            id: 'plan-' + p.id,
            name: p.no + '. ' + p.name + ' · plan (' + Number(p.progress) + '%)',
            start: p.planStart, end: p.planEnd,
            progress: Number(p.progress) || 0,
            custom_class: 'gantt-plan'
        });
        if (p.actualStart) {
            var running = !p.actualEnd;
            var end = p.actualEnd || (data.today > p.actualStart ? data.today : p.actualStart);
            tasks.push({
                id: 'act-' + p.id,
                name: p.no + '. ' + p.name + ' · actual' + (running ? ' (running)' : ''),
                start: p.actualStart, end: end,
                progress: 100,
                custom_class: running ? 'gantt-running' : 'gantt-done'
            });
        }
    });

    var gantt = new Gantt(target, tasks, {
        view_mode: 'Week',
        bar_height: 20,
        padding: 14,
        date_format: 'YYYY-MM-DD',
        language: 'en',
        popup_trigger: 'none',
        on_click: function () { },
        on_date_change: function () { },
        on_progress_change: function () { }
    });

    // Tombol skala waktu Day / Week / Month
    document.querySelectorAll('[data-gantt-view]').forEach(function (btn) {
        btn.addEventListener('click', function () {
            var mode = btn.getAttribute('data-gantt-view');
            gantt.change_view_mode(mode);
            document.querySelectorAll('[data-gantt-view]').forEach(function (b) {
                var on = b === btn;
                b.classList.toggle('active', on);
                b.setAttribute('aria-pressed', on ? 'true' : 'false');
            });
        });
    });
})();
