import { esc, formatCurrency, formatKm, setStatus, today, value } from '../dom.js';

export function createFuelFeature({ api, elements, state, getLatestKnownOdometer, onChanged }) {
  async function updateFuelCalc() {
    const liters = Number(value(elements.fLiters) || 0);
    const price = Number(value(elements.fPrice) || 0);
    const km = Number(value(elements.fKm) || 0);
    const total = liters * price;

    elements.fuelCalc.textContent = `Totaalbedrag: ${formatCurrency(total)} · KM sinds vorige tankbeurt: — · Verbruik: —`;

    if (km <= 0 || !state.activeCamperId) {
      return;
    }

    const previousTank = await api.getPreviousTank(state.activeCamperId, km);
    if (!previousTank || liters <= 0) {
      elements.fuelCalc.textContent = `Totaalbedrag: ${formatCurrency(total)} · Eerste geregistreerde tankbeurt · Verbruik: —`;
      return;
    }

    const distance = km - Number(previousTank.kmstand);
    const consumption = distance > 0 ? (liters / distance) * 100 : null;
    elements.fuelCalc.textContent = `Totaalbedrag: ${formatCurrency(total)} · ${formatKm(distance)} km sinds vorige tankbeurt · Verbruik: ${consumption != null ? `${consumption.toFixed(2).replace('.', ',')} l/100 km` : '—'}`;
  }

  async function prepareForm() {
    if (!elements.fDate.value) {
      elements.fDate.value = today();
    }

    elements.fuelKmHint.textContent = '';
    if (!state.activeCamperId) {
      elements.fKm.value = '';
      await updateFuelCalc();
      return;
    }

    const latest = await getLatestKnownOdometer();
    if (latest != null && !elements.fKm.value) {
      elements.fKm.value = String(latest);
      elements.fuelKmHint.textContent = `Automatisch overgenomen: hoogste bekende B66-KM (${formatKm(latest)} km). Pas dit aan naar de werkelijke KM-stand bij het tanken.`;
    }

    await updateFuelCalc();
  }

  async function load() {
    if (!state.activeCamperId) {
      elements.fuelList.textContent = 'Nog geen camper gekoppeld.';
      elements.fuelTotalLiters.textContent = '0,00 l';
      elements.fuelTotalCost.textContent = '€ 0,00';
      elements.fuelCount.textContent = '0';
      return;
    }

    const rows = await api.getFuelEntries(state.activeCamperId);
    let totalLiters = 0;
    let totalCost = 0;

    elements.fuelList.innerHTML = rows.length
      ? rows.map((entry, index) => {
        const liters = Number(entry.liters || 0);
        const price = Number(entry.prijs_per_liter || 0);
        const cost = entry.totaalbedrag != null ? Number(entry.totaalbedrag) : liters * price;
        totalLiters += liters;
        totalCost += cost;

        const previousEntry = rows[index - 1];
        const distance = previousEntry ? Number(entry.kmstand) - Number(previousEntry.kmstand) : null;
        const consumption = distance > 0 && liters > 0 ? (liters / distance) * 100 : null;

        return `<div class="item">
          <b>⛽ ${formatKm(entry.kmstand)} km</b> · ${esc(entry.datum || '')}
          <div class="muted">${entry.locatie ? `${esc(entry.locatie)} · ` : ''}${entry.land ? esc(entry.land) : ''}</div>
          <div>${liters.toFixed(2).replace('.', ',')} liter · € ${price.toFixed(3).replace('.', ',')}/l · <b>${formatCurrency(cost)}</b></div>
          ${consumption != null
            ? `<div class="muted">${formatKm(distance)} km sinds vorige tankbeurt · ${consumption.toFixed(2).replace('.', ',')} l/100 km</div>`
            : distance != null
              ? `<div class="muted">${formatKm(distance)} km sinds vorige tankbeurt · verbruik niet berekend</div>`
              : '<div class="muted">Eerste geregistreerde tankbeurt — vanaf de volgende tankbeurt wordt het verbruik berekend.</div>'}
        </div>`;
      }).join('')
      : 'Nog geen tankbeurten opgeslagen.';

    elements.fuelTotalLiters.textContent = `${totalLiters.toFixed(2).replace('.', ',')} l`;
    elements.fuelTotalCost.textContent = formatCurrency(totalCost);
    elements.fuelCount.textContent = String(rows.length);
  }

  async function save() {
    setStatus(elements.fuelStatus);

    if (!state.activeCamperId) {
      setStatus(elements.fuelStatus, 'Er is nog geen camper gekoppeld aan dit account.', 'warn');
      return;
    }

    const datum = value(elements.fDate);
    const kmText = value(elements.fKm);
    const litersText = value(elements.fLiters);
    const priceText = value(elements.fPrice);

    if (!datum || kmText === '' || litersText === '' || priceText === '') {
      setStatus(elements.fuelStatus, 'Vul minimaal datum, KM-stand, liters en prijs per liter in.', 'err');
      return;
    }

    const km = Number(kmText);
    const liters = Number(litersText);
    const price = Number(priceText);
    if (!Number.isInteger(km) || km < 0 || liters <= 0 || price < 0) {
      setStatus(elements.fuelStatus, 'Controleer de kilometerstand, liters en prijs per liter.', 'err');
      return;
    }

    const previousTank = await api.getPreviousTank(state.activeCamperId, km);
    if (previousTank && km <= Number(previousTank.kmstand)) {
      setStatus(elements.fuelStatus, 'De KM-stand moet hoger zijn dan de vorige tankbeurt.', 'err');
      return;
    }

    await api.createFuelEntry({
      datum,
      kmstand: km,
      liters,
      prijs_per_liter: price,
      locatie: value(elements.fLocation) || null,
      land: value(elements.fCountry) || null,
      camper_id: state.activeCamperId,
    });

    setStatus(elements.fuelStatus, '✓ Tankbeurt opgeslagen.', 'ok');
    ['fKm', 'fLiters', 'fPrice', 'fLocation', 'fCountry'].forEach((id) => {
      elements[id].value = '';
    });
    elements.fDate.value = today();
    elements.fuelKmHint.textContent = '';
    elements.fuelCalc.textContent = 'Totaalbedrag: € 0,00 · Eerste/nieuwe tankbeurt — · Verbruik: —';

    await Promise.all([load(), onChanged()]);
    await prepareForm();
  }

  function setup() {
    ['fKm', 'fLiters', 'fPrice'].forEach((id) => {
      elements[id].addEventListener('input', () => {
        updateFuelCalc().catch((error) => setStatus(elements.fuelStatus, error.message, 'err'));
      });
    });
    elements.addFuelBtn.addEventListener('click', () => save().catch((error) => setStatus(elements.fuelStatus, error.message, 'err')));
  }

  return {
    setup,
    load,
    prepareForm,
  };
}
