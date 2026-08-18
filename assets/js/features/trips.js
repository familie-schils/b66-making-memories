import { esc, formatKm, hide, sanitizeDigits, setStatus, show, today, value } from '../dom.js';
import { resetTripState } from '../state.js';

function groupByTrip(stops) {
  return stops.reduce((map, stop) => {
    if (!map.has(stop.reis_id)) {
      map.set(stop.reis_id, []);
    }
    map.get(stop.reis_id).push(stop);
    return map;
  }, new Map());
}

function groupPhotosByStop(photos) {
  return photos.reduce((map, photo) => {
    if (!map.has(photo.stop_id)) {
      map.set(photo.stop_id, []);
    }
    map.get(photo.stop_id).push(photo);
    return map;
  }, new Map());
}

export function createTripFeature({ api, elements, state, getLatestKnownOdometer, photos, onChanged }) {
  function clearStopFields() {
    ['sPlace', 'sCountry', 'sPrice', 'sFacilities', 'sNotes'].forEach((id) => {
      elements[id].value = '';
    });
    elements.sRating.value = '5';
    elements.sType.value = 'Camperplaats';
    elements.sDate.value = today();
  }

  function setTripInfo(text = '') {
    elements.activeTripInfo.textContent = text;
  }

  function updateKm() {
    const startKm = value(elements.tStartKm);
    const endKm = value(elements.tEndKmEndBox) || value(elements.tEndKm);

    if (startKm === '' || endKm === '') {
      elements.kmResult.textContent = '🚐 KM gereden: —';
      return;
    }

    const diff = Number(endKm) - Number(startKm);
    if (diff < 0) {
      elements.kmResult.textContent = '⚠️ Eind KM is lager dan Start KM';
      return;
    }

    elements.kmResult.textContent = `🚐 KM gereden: ${formatKm(diff)} km`;
  }

  async function loadCrewOptions() {
    if (!state.activeCamperId) {
      elements.tCrew.innerHTML = '<option>Geen camper gekoppeld</option>';
      return;
    }

    const crew = await api.getCrew(state.activeCamperId);
    elements.tCrew.innerHTML = crew.length
      ? crew.map((member) => `<option>${esc(member.naam)}</option>`).join('')
      : '<option>Geen bemanning gevonden</option>';
  }

  async function loadTrips() {
    if (!state.activeCamperId) {
      elements.tripList.textContent = 'Nog geen camper gekoppeld.';
      return;
    }

    elements.tripList.textContent = 'Reizen laden...';
    const trips = await api.getTrips(state.activeCamperId);
    if (!trips.length) {
      elements.tripList.innerHTML = '<div class="muted">Nog geen reizen. Start jullie eerste reis!</div>';
      return;
    }

    const stops = await api.getStopsByTripIds(trips.map((trip) => trip.id));
    const stopsByTrip = groupByTrip(stops);

    elements.tripList.innerHTML = trips.map((trip) => {
      const tripStops = stopsByTrip.get(trip.id) || [];
      const isClosed = trip.einddatum != null;
      const tripKm = trip.start_km != null && trip.eind_km != null ? Number(trip.eind_km) - Number(trip.start_km) : null;

      return `<div class="item">
        <b>${esc(trip.crew)}</b> · ${esc(trip.datum)}${isClosed ? ` → ${esc(trip.einddatum)}` : ' · 🟢 actief'}
        <div class="muted">${tripStops.length} stop${tripStops.length === 1 ? '' : 's'}${tripKm != null ? ` · ${formatKm(tripKm)} km` : ''}</div>
        ${tripStops.slice(0, 5).map((stop) => `
          <div class="trip-stop">
            📍 <b>${esc(stop.camperplaats || 'Onbenoemde stop')}</b> · ${esc(stop.land || '')}
            <div class="muted">${esc(stop.datum || '')} · ${esc(stop.type_stop || '')} · ${'★'.repeat(Number(stop.beoordeling || 0))}</div>
          </div>
        `).join('')}
        <button class="secondary" data-trip-id="${trip.id}">Bekijk reis</button>
      </div>`;
    }).join('');
  }

  async function startNewTrip() {
    resetTripState();
    hide(elements.tripChooser);
    hide(elements.tripDetail);
    show(elements.tripForm);
    hide(elements.endBox);
    show(elements.tripStartFields);
    elements.tripTitle.textContent = '🚐 Nieuwe reis';
    elements.stopHeading.textContent = '📍 Eerste stop';
    elements.tStartDate.value = today();
    elements.tEndDate.value = today();
    elements.sDate.value = today();
    elements.tStartKm.value = '';
    elements.tEndKm.value = '';
    elements.tEndKmEndBox.value = '';
    elements.kmResult.textContent = '🚐 KM gereden: —';
    show(elements.saveStopBtn);
    hide(elements.nextStopBtn);
    clearStopFields();
    setTripInfo('');
    setStatus(elements.tripStatus);
    photos.clearPhotoSelection();

    const latest = await getLatestKnownOdometer();
    if (latest != null) {
      elements.tStartKm.value = String(latest);
      setTripInfo(`Start KM automatisch overgenomen van de hoogste bekende B66-kilometerstand: ${formatKm(latest)} km`);
    }
  }

  async function ensureTripCreated() {
    if (state.activeTripId) {
      return true;
    }

    if (!state.activeCamperId) {
      setStatus(elements.tripStatus, 'Er is nog geen camper gekoppeld aan dit account.', 'warn');
      return false;
    }

    const startDate = value(elements.tStartDate);
    const startKmText = value(elements.tStartKm);
    if (!value(elements.tCrew) || !startDate || startKmText === '') {
      setStatus(elements.tripStatus, 'Vul eerst wie, startdatum en Start KM in.', 'err');
      return false;
    }

    const startKm = Number(startKmText);
    if (!Number.isInteger(startKm) || startKm < 0) {
      setStatus(elements.tripStatus, 'Vul een geldige Start KM in.', 'err');
      return false;
    }

    const trip = await api.createTrip({
      datum: startDate,
      crew: value(elements.tCrew),
      start_km: startKm,
      camper_id: state.activeCamperId,
    });

    state.activeTripId = trip.id;
    return true;
  }

  async function saveCurrentStop() {
    setStatus(elements.tripStatus);

    if (!(await ensureTripCreated())) {
      return;
    }

    if (state.currentStopSaved) {
      setStatus(elements.tripStatus, `Deze stop is al opgeslagen. Kies "Naar stop ${state.stopNumber + 1}".`, 'warn');
      return;
    }

    const stop = {
      reis_id: state.activeTripId,
      volgorde: state.stopNumber,
      datum: value(elements.sDate) || value(elements.tStartDate),
      type_stop: value(elements.sType),
      camperplaats: value(elements.sPlace),
      land: value(elements.sCountry),
      prijs_per_nacht: value(elements.sPrice) ? Number(value(elements.sPrice)) : null,
      beoordeling: Number(value(elements.sRating) || 0),
      voorzieningen: value(elements.sFacilities),
      ervaring: value(elements.sNotes),
    };

    if (!stop.camperplaats) {
      setStatus(elements.tripStatus, 'Vul minimaal de naam / plaats van de stop in.', 'err');
      return;
    }

    const savedStop = await api.createStop(stop);
    const { uploads, errors } = await photos.uploadSelectedPhotos();

    for (const upload of uploads) {
      try {
        await api.savePhotoLink({
          stop_id: savedStop.id,
          bestandsnaam: upload.naam,
          url: upload.url,
        });
      } catch (error) {
        errors.push(error.message);
      }
    }

    state.currentStopSaved = true;
    show(elements.nextStopBtn);
    hide(elements.saveStopBtn);
    elements.nextStopBtn.textContent = `➡️ Naar stop ${state.stopNumber + 1}`;
    setTripInfo(`Reis actief · ${state.stopNumber} stop${state.stopNumber === 1 ? '' : 's'} opgeslagen`);
    photos.clearPhotoSelection();

    setStatus(
      elements.tripStatus,
      errors.length
        ? `✓ Stop ${state.stopNumber} opgeslagen, maar ${errors.length} foto-actie(s) mislukten.`
        : `✓ Stop ${state.stopNumber} opgeslagen.`,
      errors.length ? 'warn' : 'ok',
    );

    await Promise.all([loadTrips(), onChanged()]);
  }

  function prepareNextStop() {
    if (!state.currentStopSaved) {
      setStatus(elements.tripStatus, 'Sla eerst de huidige stop op.', 'err');
      return;
    }

    state.stopNumber += 1;
    state.currentStopSaved = false;
    hide(elements.tripStartFields);
    elements.tripTitle.textContent = '🚐 Reis actief';
    elements.stopHeading.textContent = `📍 Stop ${state.stopNumber}`;
    setTripInfo(`Reis actief · vul de gegevens van stop ${state.stopNumber} in`);
    show(elements.saveStopBtn);
    hide(elements.nextStopBtn);
    clearStopFields();
    photos.clearPhotoSelection();
  }

  function showEndTrip() {
    if (!state.activeTripId) {
      setStatus(elements.tripStatus, 'Start eerst een reis.', 'err');
      return;
    }

    if (!state.currentStopSaved) {
      setStatus(elements.tripStatus, `Sla eerst stop ${state.stopNumber} op voordat je de reis afsluit.`, 'err');
      return;
    }

    show(elements.endBox);
    elements.tEndDate.value = today();
    elements.tEndKmEndBox.value = '';
    elements.tEndKm.value = '';
    elements.endBox.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  function hideEndTrip() {
    hide(elements.endBox);
  }

  async function finishTrip() {
    const endDate = value(elements.tEndDate);
    const startKmText = value(elements.tStartKm);
    const cleanEndKm = sanitizeDigits(value(elements.tEndKmEndBox));

    if (!endDate || startKmText === '' || cleanEndKm === '') {
      setStatus(elements.tripStatus, 'Vul Einddatum en Eind KM in.', 'err');
      return;
    }

    const startKm = Number(startKmText);
    const endKm = Number(cleanEndKm);
    if (!Number.isInteger(endKm) || endKm < 0) {
      setStatus(elements.tripStatus, 'Vul een geldige Eind KM in.', 'err');
      return;
    }

    if (endKm < startKm) {
      setStatus(elements.tripStatus, 'Eind KM mag niet lager zijn dan Start KM.', 'err');
      return;
    }

    elements.tEndKm.value = cleanEndKm;
    await api.updateTrip(state.activeTripId, { einddatum: endDate, eind_km: endKm });

    const gereden = endKm - startKm;
    setStatus(elements.tripStatus, `✓ Reis afgesloten · ${formatKm(gereden)} km gereden.`, 'ok');
    resetTripState();
    hide(elements.tripForm);
    hide(elements.endBox);
    show(elements.tripChooser);
    show(elements.saveStopBtn);
    hide(elements.nextStopBtn);
    await Promise.all([loadTrips(), onChanged()]);
  }

  function cancelTrip() {
    resetTripState();
    hide(elements.tripForm);
    hide(elements.endBox);
    show(elements.tripChooser);
    setTripInfo('');
    setStatus(elements.tripStatus);
    photos.clearPhotoSelection();
  }

  async function showTripDetail(id) {
    const trip = await api.getTrip(id, state.activeCamperId);
    const stops = await api.getStopsByTripId(id);
    const photosByStop = groupPhotosByStop(await api.getPhotosByStopIds(stops.map((stop) => stop.id)));
    const tripKm = trip.start_km != null && trip.eind_km != null ? Number(trip.eind_km) - Number(trip.start_km) : null;

    elements.tripDetail.innerHTML = `
      <h2>📖 Reis van ${esc(trip.crew)}</h2>
      <div class="muted">${esc(trip.datum)}${trip.einddatum ? ` → ${esc(trip.einddatum)}` : ' · 🟢 nog actief'}</div>
      <p><b>Start KM:</b> ${trip.start_km != null ? formatKm(trip.start_km) : '—'}${trip.eind_km != null ? ` · <b>Eind KM:</b> ${formatKm(trip.eind_km)}` : ''}${tripKm != null ? ` · <b>${formatKm(tripKm)} km gereden</b>` : ''}</p>
      <h3>Stops</h3>
      ${(stops || []).map((stop) => {
        const stopPhotos = photosByStop.get(stop.id) || [];
        return `
          <div class="trip-stop">
            <b>${stop.volgorde}. ${esc(stop.camperplaats || 'Onbenoemde stop')}</b> · ${esc(stop.land || '')}
            <div class="muted">${esc(stop.datum || '')} · ${esc(stop.type_stop || '')} · ${'★'.repeat(Number(stop.beoordeling || 0))}</div>
            <div>${esc(stop.voorzieningen || '')}</div>
            <p>${esc(stop.ervaring || '')}</p>
            <div class="muted">📸 ${stopPhotos.length} foto(s)</div>
            ${stopPhotos.map((photo) => `<div class="photo-thumb"><img src="${esc(photo.url)}" alt="Foto van ${esc(stop.camperplaats || 'stop')}"></div>`).join('')}
            ${stop.prijs_per_nacht != null ? `<div class="muted">€ ${Number(stop.prijs_per_nacht).toFixed(2)} / nacht</div>` : ''}
          </div>`;
      }).join('') || '<div class="muted">Geen stops.</div>'}
      <br>
      <button class="secondary" data-close-trip-detail="true">Sluiten</button>
    `;

    show(elements.tripDetail);
    elements.tripDetail.scrollIntoView({ behavior: 'smooth' });
  }

  function setup() {
    elements.startTripBtn.addEventListener('click', () => startNewTrip().catch((error) => setStatus(elements.tripStatus, error.message, 'err')));
    elements.saveStopBtn.addEventListener('click', () => saveCurrentStop().catch((error) => setStatus(elements.tripStatus, error.message, 'err')));
    elements.nextStopBtn.addEventListener('click', prepareNextStop);
    elements.endTripBtn.addEventListener('click', showEndTrip);
    elements.cancelTripBtn.addEventListener('click', cancelTrip);
    elements.finishTripBtn.addEventListener('click', () => finishTrip().catch((error) => setStatus(elements.tripStatus, error.message, 'err')));
    elements.hideEndTripBtn.addEventListener('click', hideEndTrip);
    elements.tEndKm.addEventListener('input', updateKm);
    elements.tEndKmEndBox.addEventListener('input', () => {
      const clean = sanitizeDigits(elements.tEndKmEndBox.value);
      elements.tEndKmEndBox.value = clean;
      elements.tEndKm.value = clean;
      updateKm();
    });
    elements.tripList.addEventListener('click', (event) => {
      const button = event.target.closest('[data-trip-id]');
      if (button) {
        showTripDetail(Number(button.dataset.tripId)).catch((error) => setStatus(elements.tripStatus, error.message, 'err'));
      }
    });
    elements.tripDetail.addEventListener('click', (event) => {
      const button = event.target.closest('[data-close-trip-detail]');
      if (button) {
        hide(elements.tripDetail);
      }
    });
  }

  return {
    setup,
    loadCrewOptions,
    loadTrips,
  };
}
