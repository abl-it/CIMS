// Form Request (T2-1): cascade sub-kategori per kategori, bagian ROI khusus CAPEX, luas area = panjang x lebar.
// Hanya perilaku tampilan; validasi tetap di server (ModelState + stored procedure).
(function () {
    'use strict';

    const form = document.getElementById('request-form');
    if (!form) return;

    const category = form.querySelector('[data-request-category]');
    const subCategory = form.querySelector('[data-request-subcategory]');
    const capexOnly = form.querySelectorAll('[data-capex-only]');
    const length = form.querySelector('[data-area-length]');
    const width = form.querySelector('[data-area-width]');
    const area = form.querySelector('[data-area-size]');

    // Sub-kategori: tampilkan hanya milik kategori terpilih; pilihan lama yang tidak cocok dikosongkan.
    function applyCategory() {
        const value = category ? category.value : '';

        if (subCategory) {
            Array.from(subCategory.options).forEach(function (opt) {
                if (!opt.value) return;
                const match = opt.dataset.category === value;
                opt.hidden = !match;
                opt.disabled = !match;
            });
            const selected = subCategory.selectedOptions[0];
            if (selected && selected.value && selected.disabled) subCategory.value = '';
            subCategory.disabled = !value;
        }

        capexOnly.forEach(function (el) {
            el.classList.toggle('d-none', value !== 'CAPEX');
        });
    }

    function applyArea() {
        if (!area) return;
        const l = parseFloat(length && length.value);
        const w = parseFloat(width && width.value);
        area.value = l > 0 && w > 0 ? (Math.round(l * w * 100) / 100).toFixed(2) : '';
    }

    // Select yang disabled tidak ikut terkirim; aktifkan kembali sebelum submit agar nilai kosong tetap terkirim.
    form.addEventListener('submit', function () {
        if (subCategory) subCategory.disabled = false;
    });

    if (category) category.addEventListener('change', applyCategory);
    if (length) length.addEventListener('input', applyArea);
    if (width) width.addEventListener('input', applyArea);

    applyCategory();
    applyArea();
})();
