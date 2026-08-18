import { clearSelectedPhotos } from '../state.js';
import { esc, setPhotoMessage } from '../dom.js';

export function createPhotoFeature({ api, elements, state }) {
  function renderSelectedPhotos() {
    if (!state.selectedPhotos.length) {
      elements.photoList.innerHTML = '';
      setPhotoMessage(elements.photoStatus, 'Nog geen foto geselecteerd.');
      return;
    }

    setPhotoMessage(elements.photoStatus, `${state.selectedPhotos.length} foto(s) geselecteerd`);
    elements.photoList.innerHTML = state.selectedPhotos
      .map((photo) => `<div>📸 ${esc(photo.name)}</div>`)
      .join('');
  }

  function clearPhotoSelection() {
    clearSelectedPhotos();
    elements.photoUpload.value = '';
    renderSelectedPhotos();
  }

  function handleSelection(event) {
    state.selectedPhotos = [...event.target.files];
    renderSelectedPhotos();
  }

  function createUploadName(photo) {
    const cleanedName = photo.name.replace(/\s+/g, '_').replace(/[^a-zA-Z0-9._-]/g, '');
    return `${Date.now()}_${cleanedName}`;
  }

  async function uploadSelectedPhotos() {
    const uploads = [];
    const errors = [];

    for (const photo of state.selectedPhotos) {
      try {
        const url = await api.uploadPhoto(createUploadName(photo), photo);
        uploads.push({ naam: photo.name, url });
      } catch (error) {
        errors.push(error.message);
      }
    }

    return { uploads, errors };
  }

  async function testUpload() {
    const { uploads, errors } = await uploadSelectedPhotos();

    if (uploads.length) {
      setPhotoMessage(elements.photoStatus, `${uploads.length} foto(s) geüpload${errors.length ? ` · ${errors.length} fout(en)` : ''}`);
    } else if (errors.length) {
      setPhotoMessage(elements.photoStatus, errors[0]);
    } else {
      setPhotoMessage(elements.photoStatus, 'Nog geen foto geselecteerd.');
    }
  }

  function setup() {
    elements.photoUpload.addEventListener('change', handleSelection);
    elements.photoTestUploadBtn.addEventListener('click', () => testUpload());
    renderSelectedPhotos();
  }

  return {
    setup,
    uploadSelectedPhotos,
    clearPhotoSelection,
  };
}
