// Schedule, action plan, dan estimasi biaya bulanan di halaman Details request (T4-2; BR-13, BR-15, BR-16).
// - Tambah / hapus / pindah baris; nama field (actionPlans[i].X, estimates[i].X) dinomori ulang agar model binding benar.
// - Total bobot dan total estimasi tampil langsung.
// - Validasi sebelum kirim (urutan tanggal, total, bulan ganda) supaya isian tidak hilang karena ditolak server.
//   Listener submit dipasang di form (fase target), jadi berjalan sebelum konfirmasi notify.js di document.
// - Penyesuaian addendum (T4-4): satu form memuat schedule + estimasi (data-schedule-form dan data-estimate-form),
//   data-dynamic-months = rentang bulan dari tanggal mulai project s.d. tanggal selesai plan terakhir di form,
//   data-min-new-month = bulan paling awal untuk baris estimasi baru (bulan lalu terkunci, BR-85).
// Validasi akhir tetap di stored procedure.
(function () {
    'use strict';

    var fmtNumber = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });

    function num(input) {
        var v = parseFloat(input.value);
        return isNaN(v) ? 0 : v;
    }

    function round2(v) {
        return Math.round(v * 100) / 100;
    }

    function fail(message) {
        if (window.notify) window.notify.error(message, 'Please check the data');
    }

    function stop(e) {
        e.preventDefault();
        e.stopImmediatePropagation();
    }

    // Beri nama field sesuai urutan: prefix[i].Field; id unik untuk label.
    function renumber(rows, prefix) {
        rows.forEach(function (row, i) {
            row.querySelectorAll('[data-field]').forEach(function (input) {
                var field = input.getAttribute('data-field');
                input.name = prefix + '[' + i + '].' + field;
                if (input.type !== 'hidden') {
                    input.id = prefix + i + field;
                    var label = input.closest('[class*="col-"]');
                    label = label && label.querySelector('label.form-label');
                    if (label) label.htmlFor = input.id;
                }
            });
            var no = row.querySelector('[data-row-no]');
            if (no) no.textContent = String(i + 1);
        });
    }

    function markDirty(form) {
        form.dispatchEvent(new Event('change', { bubbles: true }));
    }

    /* ---------------- Schedule + action plan ---------------- */
    var scheduleForm = document.querySelector('form[data-schedule-form]');
    if (scheduleForm) {
        var planList = scheduleForm.querySelector('[data-plan-list]');
        var planTemplate = scheduleForm.querySelector('template[data-plan-template]');
        var weightTotal = scheduleForm.querySelector('[data-weight-total]');
        var projectStart = scheduleForm.querySelector('[data-project-start]');
        var requireComplete = scheduleForm.getAttribute('data-require-complete') === 'true';

        var planRows = function () { return Array.from(planList.querySelectorAll('[data-plan-row]')); };

        var updateWeight = function () {
            var total = round2(planRows().reduce(function (s, row) { return s + num(row.querySelector('[data-weight]')); }, 0));
            weightTotal.textContent = fmtNumber.format(total);
            weightTotal.classList.toggle('text-danger', total > 100);
            weightTotal.classList.toggle('text-success', total === 100);
            return total;
        };

        var refreshPlans = function () {
            renumber(planRows(), 'actionPlans');
            updateWeight();
        };

        scheduleForm.querySelector('[data-add-plan]').addEventListener('click', function () {
            var row = planTemplate.content.firstElementChild.cloneNode(true);
            // Default tanggal mulai: sesudah plan terakhir, atau tanggal mulai project
            var rows = planRows();
            var last = rows.length ? rows[rows.length - 1].querySelector('[data-plan-end]').value : '';
            row.querySelector('[data-plan-start]').value = last || projectStart.value || '';
            planList.appendChild(row);
            refreshPlans();
            row.querySelector('[data-field="Name"]').focus();
            markDirty(scheduleForm);
        });

        planList.addEventListener('click', function (e) {
            var btn = e.target.closest('button');
            if (!btn) return;
            var row = btn.closest('[data-plan-row]');
            if (btn.hasAttribute('data-remove-row')) {
                row.remove();
            } else if (btn.getAttribute('data-move') === 'up' && row.previousElementSibling) {
                planList.insertBefore(row, row.previousElementSibling);
            } else if (btn.getAttribute('data-move') === 'down' && row.nextElementSibling) {
                planList.insertBefore(row.nextElementSibling, row);
            } else {
                return;
            }
            refreshPlans();
            markDirty(scheduleForm);
        });

        planList.addEventListener('input', function (e) {
            if (e.target.hasAttribute('data-weight')) updateWeight();
        });

        scheduleForm.addEventListener('submit', function (e) {
            var start = projectStart.value;
            var rows = planRows();
            for (var i = 0; i < rows.length; i++) {
                var s = rows[i].querySelector('[data-plan-start]').value;
                var en = rows[i].querySelector('[data-plan-end]').value;
                if (s && en && en < s) {
                    stop(e); fail('Action plan ' + (i + 1) + ': plan end date must be on or after the start date.'); return;
                }
                if (start && s && s < start) {
                    stop(e); fail('Action plan ' + (i + 1) + ': plan start date must be on or after the project start date.'); return;
                }
            }
            var total = updateWeight();
            if (total > 100) {
                stop(e); fail('Total action plan weight must not exceed 100% (currently ' + fmtNumber.format(total) + '%).'); return;
            }
            if (requireComplete && total !== 100) {
                stop(e); fail('Total action plan weight must be 100% (currently ' + fmtNumber.format(total) + '%).');
            }
        });

        refreshPlans();
    }

    /* ---------------- Estimasi biaya per bulan ---------------- */
    var estimateForm = document.querySelector('form[data-estimate-form]');
    if (estimateForm) {
        var estList = estimateForm.querySelector('[data-estimate-list]');
        var estTemplate = estimateForm.querySelector('template[data-estimate-template]');
        var estTotal = estimateForm.querySelector('[data-estimate-total]');
        var planCostAttr = estimateForm.getAttribute('data-plan-cost');
        var planCost = planCostAttr ? parseFloat(planCostAttr) : null;
        var planCostLabel = estimateForm.getAttribute('data-plan-cost-label') || 'the plan cost';
        var estRequireComplete = estimateForm.getAttribute('data-require-complete') === 'true';
        var dynamicMonths = estimateForm.getAttribute('data-dynamic-months') === 'true';
        var minNewMonth = estimateForm.getAttribute('data-min-new-month') || '';

        // Rentang bulan: tetap dari atribut, atau (penyesuaian addendum) dari tanggal di form saat ini
        var firstMonth = function () {
            if (!dynamicMonths) return estimateForm.getAttribute('data-first-month');
            var s = estimateForm.querySelector('[data-project-start]');
            return s && s.value ? s.value.substring(0, 7) : '';
        };
        var lastMonth = function () {
            if (!dynamicMonths) return estimateForm.getAttribute('data-last-month');
            var ends = Array.from(estimateForm.querySelectorAll('[data-plan-row] [data-plan-end]'))
                .map(function (i) { return i.value; }).filter(Boolean).sort();
            return ends.length ? ends[ends.length - 1].substring(0, 7) : '';
        };

        var estRows = function () { return Array.from(estList.querySelectorAll('[data-estimate-row]')); };

        var updateTotal = function () {
            var total = round2(estRows().reduce(function (s, row) { return s + num(row.querySelector('[data-amount]')); }, 0));
            estTotal.textContent = fmtNumber.format(total);
            estTotal.classList.toggle('text-danger', planCost !== null && total > planCost);
            estTotal.classList.toggle('text-success', planCost !== null && total === planCost);
            return total;
        };

        var refreshEstimates = function () {
            renumber(estRows(), 'estimates');
            updateTotal();
        };

        // Bulan berikutnya (yyyy-MM) setelah bulan terakhir yang sudah diisi
        var nextMonth = function () {
            var first = firstMonth(), last = lastMonth();
            var months = estRows().map(function (r) { return r.querySelector('[data-month]').value; }).filter(Boolean).sort();
            var m = first;
            if (months.length) {
                var parts = months[months.length - 1].split('-');
                var d = new Date(parseInt(parts[0], 10), parseInt(parts[1], 10), 1);   // bulan JS 0-based -> +1 bulan
                m = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
            }
            if (minNewMonth && m < minNewMonth) m = minNewMonth;
            return !m || (last && m > last) ? '' : m;
        };

        estimateForm.querySelector('[data-add-estimate]').addEventListener('click', function () {
            var row = estTemplate.content.firstElementChild.cloneNode(true);
            if (dynamicMonths) {
                var monthInput = row.querySelector('[data-month]');
                if (minNewMonth) monthInput.min = minNewMonth;
                if (lastMonth()) monthInput.max = lastMonth();
            }
            row.querySelector('[data-month]').value = nextMonth() || '';
            estList.appendChild(row);
            refreshEstimates();
            row.querySelector('[data-amount]').focus();
            markDirty(estimateForm);
        });

        estList.addEventListener('click', function (e) {
            var btn = e.target.closest('button[data-remove-row]');
            if (!btn) return;
            btn.closest('[data-estimate-row]').remove();
            refreshEstimates();
            markDirty(estimateForm);
        });

        estList.addEventListener('input', function (e) {
            if (e.target.hasAttribute('data-amount')) updateTotal();
        });

        estimateForm.addEventListener('submit', function (e) {
            var seen = {};
            var rows = estRows();
            var first = firstMonth(), last = lastMonth();
            for (var i = 0; i < rows.length; i++) {
                var m = rows[i].querySelector('[data-month]').value;
                if (m && ((first && m < first) || (last && m > last))) {
                    stop(e); fail('Cost estimate row ' + (i + 1) + ': month must be within the project schedule.'); return;
                }
                if (m && seen[m]) {
                    stop(e); fail('Each month can only appear once in the cost estimate.'); return;
                }
                seen[m] = true;
            }
            var total = updateTotal();
            if (planCost !== null && total > planCost) {
                stop(e); fail('Total cost estimate must not exceed ' + planCostLabel + ' (IDR ' + fmtNumber.format(planCost) + ').'); return;
            }
            if (estRequireComplete && planCost !== null && total !== planCost) {
                stop(e); fail('Total cost estimate must equal ' + planCostLabel + ' (IDR ' + fmtNumber.format(planCost) + ').');
            }
        });

        refreshEstimates();
    }
})();
