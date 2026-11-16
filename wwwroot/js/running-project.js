// Form Input Running Project (T4-3; FR-03, BR-76).
// - Departemen dipilih -> isi ulang lokasi (Company departemen), PIC, dan cost center lewat AJAX (RunningLookups).
// - Bagian Planning/Scheduling dan In-house/Outsource ditampilkan sesuai pilihan; field di bagian tersembunyi
//   dinonaktifkan agar tidak terkirim dan tidak divalidasi.
// - Baris approval di luar sistem: tambah/hapus, nama field dinomori ulang (Approvals[i].X).
// Validasi akhir tetap di server (ModelState + stored procedure).
(function () {
    'use strict';

    var form = document.querySelector('form[data-running-form]');
    if (!form) return;

    /* ---------------- Departemen -> lookup ---------------- */
    var dept = form.querySelector('[data-running-department]');
    var company = form.querySelector('[data-running-company]');
    var lookupUrl = form.getAttribute('data-lookup-url');

    var fillSelect = function (select, items) {
        var keep = select.value;
        select.querySelectorAll('option:not([value=""])').forEach(function (o) { o.remove(); });
        (items || []).forEach(function (item) {
            var opt = document.createElement('option');
            opt.value = String(item.id);
            opt.textContent = item.text;
            select.appendChild(opt);
        });
        select.value = (items || []).some(function (i) { return String(i.id) === keep; }) ? keep : '';
    };

    var clearLookups = function () {
        form.querySelectorAll('[data-running-lookup]').forEach(function (s) { fillSelect(s, []); });
        company.value = '';
    };

    dept.addEventListener('change', async function () {
        if (!dept.value) { clearLookups(); return; }
        dept.disabled = true;
        try {
            var url = lookupUrl + (lookupUrl.indexOf('?') >= 0 ? '&' : '?') + 'departmentId=' + encodeURIComponent(dept.value);
            var res = await fetch(url, { headers: { 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json' } });
            if (!res.ok) { clearLookups(); window.notify.fetchError(res); return; }
            var data = await res.json();
            company.value = data.coCode || '';
            form.querySelectorAll('[data-running-lookup]').forEach(function (s) {
                fillSelect(s, data[s.getAttribute('data-running-lookup')]);
            });
        } catch (err) {
            clearLookups();
            window.notify.fetchError(err);
        } finally {
            dept.disabled = false;
        }
    });

    /* ---------------- Status / cara eksekusi ---------------- */
    var checked = function (selector) {
        var el = form.querySelector(selector + ':checked');
        return el ? el.value : '';
    };

    var applyStatus = function () {
        var scheduling = checked('[data-running-status]') === 'SCHEDULING';
        var exec = checked('[data-running-execution]');
        var visible = {
            scheduling: scheduling,
            boq: !scheduling || exec === 'INHOUSE',
            outsource: scheduling && exec === 'OUTSOURCE'
        };
        form.querySelectorAll('[data-show-when]').forEach(function (section) {
            var show = !!visible[section.getAttribute('data-show-when')];
            section.classList.toggle('d-none', !show);
            section.querySelectorAll('input, select, textarea').forEach(function (input) { input.disabled = !show; });
        });
    };

    form.querySelectorAll('[data-running-status], [data-running-execution]').forEach(function (r) {
        r.addEventListener('change', applyStatus);
    });
    applyStatus();

    /* ---------------- Approval di luar sistem ---------------- */
    var list = form.querySelector('[data-approval-list]');
    var template = form.querySelector('template[data-approval-template]');
    var addBtn = form.querySelector('[data-add-approval]');
    var maxRows = parseInt(list.getAttribute('data-max-rows'), 10) || 10;

    var rows = function () { return Array.from(list.querySelectorAll('[data-approval-row]')); };

    var renumber = function () {
        rows().forEach(function (row, i) {
            row.querySelectorAll('[data-field]').forEach(function (input) {
                var field = input.getAttribute('data-field');
                input.name = 'Approvals[' + i + '].' + field;
                input.id = 'Approvals_' + i + '__' + field;
                var label = input.closest('[class*="col-"]').querySelector('label.form-label');
                if (label) label.htmlFor = input.id;
            });
        });
        addBtn.disabled = rows().length >= maxRows;
    };

    addBtn.addEventListener('click', function () {
        if (rows().length >= maxRows) return;
        var row = template.content.firstElementChild.cloneNode(true);
        list.appendChild(row);
        renumber();
        row.querySelector('[data-field="Step"]').focus();
    });

    list.addEventListener('click', function (e) {
        var btn = e.target.closest('button[data-remove-row]');
        if (!btn) return;
        btn.closest('[data-approval-row]').remove();
        renumber();
        form.dispatchEvent(new Event('change', { bubbles: true }));
    });

    renumber();
})();
