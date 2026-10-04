(() => {
  const dialog = document.querySelector('.image-dialog');
  if (!dialog || typeof dialog.showModal !== 'function') return;

  const image = dialog.querySelector('#expanded-image');
  const caption = dialog.querySelector('#image-caption');
  const close = dialog.querySelector('.close-dialog');
  const original = dialog.querySelector('.view-original');
  let opener;

  document.querySelectorAll('[data-lightbox]').forEach(link => {
    link.addEventListener('click', event => {
      // Preserve new-tab and download behavior for modified clicks.
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      opener = link;
      image.src = link.href;
      original.href = link.href;
      image.classList.toggle('wide-screenshot', link.classList.contains('traffic-shot'));
      image.alt = link.querySelector('img').alt;
      caption.textContent = link.dataset.caption;
      dialog.showModal();
      close.focus();
    });
  });

  close.addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
  dialog.addEventListener('close', () => opener?.focus({ preventScroll: true }));
})();
