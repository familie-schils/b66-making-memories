import { esc, setStatus, today, value } from '../dom.js';

const maintenanceOptions = {
  fiat: ['Olie', 'Oliefilter', 'Luchtfilter', 'Brandstoffilter', 'Banden', 'Remmen', 'Accu', 'APK / Keuring', 'Ruitenwissers', 'Overig'],
  vanomobil: ['Vochtcontrole', 'Zonnepaneel', 'Omvormer', 'Kachel', 'Boiler', 'Waterpomp', 'Koelkast', 'Luifel', 'Overig'],
  repair: ['Schade', 'Steenslag', 'Lekke band', 'Slot', 'Verlichting', 'Camera', 'Overig'],
};

export function createMaintenanceFeature({ api, elements, state }) {
  function renderOptions() {
    const items = maintenanceOptions[elements.mCategory.value] || [];
    elements.maintenanceOptions.innerHTML = items
      .map((item) => `
        <label>
          <input type="checkbox" class="maintenanceCheck" value="${esc(item)}">
          ${esc(item)}
        </label>
      `)
      .join('<br>');

    toggleOtherBox();
  }

  function toggleOtherBox() {
    const isOtherSelected = [...document.querySelectorAll('.maintenanceCheck')]
      .some((checkbox) => checkbox.checked && checkbox.value === 'Overig');

    elements.otherMaintenanceBox.classList.toggle('hidden', !isOtherSelected);
  }

  async function load() {
    if (!state.activeCamperId) {
      elements.maintenanceHistory.textContent = 'Nog geen camper gekoppeld.';
      return;
    }

    const entries = await api.getMaintenance(state.activeCamperId);
    elements.maintenanceHistory.innerHTML = entries.length
      ? entries.map((entry) => `
        <div class="item">
          <b>${esc(entry.datum || '')}</b><br>
          ${esc(entry.categorie || '')}<br>
          <div class="muted">${esc(entry.werkzaamheden || '')}</div>
          ${entry.uitvoerder ? `<div>🔧 ${esc(entry.uitvoerder)}</div>` : ''}
          ${entry.kosten ? `<div>💶 € ${esc(entry.kosten)}</div>` : ''}
          ${entry.opmerkingen ? `<div class="muted">${esc(entry.opmerkingen)}</div>` : ''}
        </div>
      `).join('')
      : 'Nog geen onderhoud geregistreerd.';
  }

  async function save() {
    setStatus(elements.maintenanceStatus);

    if (!state.activeCamperId) {
      setStatus(elements.maintenanceStatus, 'Er is nog geen camper gekoppeld aan dit account.', 'warn');
      return;
    }

    const category = value(elements.mCategory);
    if (!category) {
      setStatus(elements.maintenanceStatus, 'Kies eerst een categorie.', 'err');
      return;
    }

    const selectedWork = [...document.querySelectorAll('.maintenanceCheck:checked')].map((checkbox) => checkbox.value);

    await api.createMaintenance({
      camper_id: state.activeCamperId,
      datum: value(elements.mDate) || null,
      categorie: category,
      werkzaamheden: selectedWork.join(', '),
      omschrijving_overig: value(elements.otherMaintenanceText) || null,
      kosten: value(elements.mCost) || null,
      uitvoerder: value(elements.mPerformer) || null,
      opmerkingen: value(elements.mNotes) || null,
    });

    setStatus(elements.maintenanceStatus, '✅ Onderhoud opgeslagen.', 'ok');
    elements.mCategory.value = '';
    elements.mDate.value = today();
    elements.mKm.value = '';
    elements.mCost.value = '';
    elements.mPerformer.value = '';
    elements.mNotes.value = '';
    elements.otherMaintenanceText.value = '';
    elements.maintenanceOptions.innerHTML = '';
    elements.otherMaintenanceBox.classList.add('hidden');
    await load();
  }

  function setup() {
    elements.mDate.value = today();
    elements.mCategory.addEventListener('change', renderOptions);
    elements.maintenanceOptions.addEventListener('change', toggleOtherBox);
    elements.saveMaintenanceBtn.addEventListener('click', () => save().catch((error) => setStatus(elements.maintenanceStatus, error.message, 'err')));
  }

  return {
    setup,
    load,
  };
}
