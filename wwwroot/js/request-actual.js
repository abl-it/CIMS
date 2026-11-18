// Form actual cost satu bulan di halaman Details request (T5-2; BR-18, PRD 6.4).
// - Tambah / hapus baris item; nama field dinomori ulang (items[i].X) agar model binding benar.
// - Amount otomatis = qty × harga satuan saat qty/harga diubah (tetap bisa diubah manual, toleransi IDR 1).
// - Total bulan tampil langsung; cek amount sebelum kirim agar isian tidak hilang karena ditolak server.
// Validasi akhir tetap di stored procedure.
(function () {
    'use strict';

    var form = document.querySelector('form[data-actual-form]');
    if (!form) return;

    var list = form.querySelector('[data-actual-list]');
    var template = form.querySelector('template[data-actual-template]');
    var totalEl = form.querySelector('[data-actual-total]');
    var fmt = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });

    var rows = function () { return Array.from(list.querySelectorAll('[data-actual-row]')); };
    var num = function (input) { var v = parseFloat(input.value); return isNaN(v) ? 0 : v; };
    var round2 = function (v) { return Math.round(v * 100) / 100; };

    var renumber = function () {
        rows().forEach(function (row, i) {
            row.querySelectorAll('[data-field]').forEach(function (input) {
                var field = input.getAttribute('data-field');
                input.name = 'items[' + i + '].' + field;
                input.id = 'act' + i + field;
                var label = input.closest('[class*="col-"]').querySelector('label.form-label');
                if (label) label.htmlFor = input.id;
            });
        });
    };

    var updateTotal = function () {
        var total = rows().reduce(function (sum, row) { return sum + num(row.querySelector('[data-amount]')); }, 0);
        totalEl.textContent = fmt.format(round2(total));
    };

    var addRow = function (focus) {
        var row = template.content.firstElementChild.cloneNode(true);
        list.appendChild(row);
        renumber();
        if (focus) row.querySelector('[data-field="ItemName"]').focus();
    };

    form.querySelector('[data-add-actual]').addEventListener('click', function () {
        addRow(true);
        form.dispatchEvent(new Event('change', { bubbles: true }));
    });

    list.addEventListener('click', function (e) {
        var btn = e.target.closest('button[data-remove-row]');
        if (!btn) return;
        btn.closest('[data-actual-row]').remove();
        renumber();
        updateTotal();
        form.dispatchEvent(new Event('change', { bubbles: true }));
    });

    list.addEventListener('input', function (e) {
        var row = e.target.closest('[data-actual-row]');
        if (!row) return;
        if (e.target.hasAttribute('data-qty') || e.target.hasAttribute('data-price')) {
            var qty = row.querySelector('[data-qty]');
            var price = row.querySelector('[data-price]');
            if (qty.value !== '' && price.value !== '') {
                row.querySelector('[data-amount]').value = round2(num(qty) * num(price)).toFixed(2).replace(/\.00$/, '');
            }
        }
        updateTotal();
    });

    form.addEventListener('submit', function (e) {
        var all = rows();
        for (var i = 0; i < all.length; i++) {
            var expected = round2(num(all[i].querySelector('[data-qty]')) * num(all[i].querySelector('[data-price]')));
            var amount = num(all[i].querySelector('[data-amount]'));
            if (Math.abs(amount - expected) > 1) {
                e.preventDefault();
                e.stopImmediatePropagation();
                if (window.notify) {
                    window.notify.error('Item row ' + (i + 1) + ': amount must equal quantity × unit price (' + fmt.format(expected) + ').',
                        'Please check the data');
                }
                return;
            }
        }

        // BR-96: bulan berisi item wajib punya lampiran detail cost (lama atau baru). Validasi akhir di SP.
        var hasItems = all.some(function (r) { return (r.querySelector('[data-field="ItemName"]') || {}).value; });
        var fileInput = form.querySelector('[data-actual-files]');
        var hasNewFiles = fileInput && fileInput.files && fileInput.files.length > 0;
        if (hasItems && form.getAttribute('data-has-files') !== 'true' && !hasNewFiles) {
            e.preventDefault();
            e.stopImmediatePropagation();
            if (window.notify) {
                window.notify.error('Please attach the cost detail document (e.g. PO / invoice / receipt summary) for this month.',
                    'Please check the data');
            }
            if (fileInput) fileInput.focus();
        }
    });

    // Bulan tanpa item: sediakan satu baris kosong
    if (rows().length === 0) addRow(false);
    renumber();
    updateTotal();
})();
