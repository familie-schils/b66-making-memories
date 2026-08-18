import { esc, formatCurrency, formatKm, formatLiters } from '../dom.js';
import { getFirstOdometer, getLatestOdometer, summarizeFuel } from '../metrics.js';

export function createDashboardFeature({ api, elements, state }) {
  async function load() {
    if (!state.activeCamperId) {
      elements.odometer.textContent = '—';
      elements.totalKm.textContent = '—';
      elements.avgConsumption.textContent = '—';
      elements.fuelCost.textContent = '€ 0,00';
      elements.tripCount.textContent = '0';
      elements.stopCount.textContent = '0';
      elements.dashboardLiters.textContent = '0,00 l';
      elements.dashboardFuelCount.textContent = '0';
      elements.recent.textContent = 'Nog geen camper gekoppeld.';
      return;
    }

    const trips = await api.getTrips(state.activeCamperId);
    const tripIds = trips.map((trip) => trip.id);
    const [stops, tanks] = await Promise.all([
      api.getStopsByTripIds(tripIds),
      api.getFuelEntries(state.activeCamperId),
    ]);

    const currentKm = getLatestOdometer(trips, tanks);
    const firstKm = getFirstOdometer(trips, tanks);
    const fuelSummary = summarizeFuel(tanks);

    elements.tripCount.textContent = String(trips.filter((trip) => trip.einddatum).length);
    elements.stopCount.textContent = String(stops.length);
    elements.odometer.textContent = currentKm != null ? `${formatKm(currentKm)} km` : '—';
    elements.totalKm.textContent = currentKm != null && firstKm != null ? `${formatKm(currentKm - firstKm)} km` : '—';
    elements.avgConsumption.textContent = fuelSummary.averageConsumption != null
      ? `${fuelSummary.averageConsumption.toFixed(2).replace('.', ',')} l/100 km`
      : '—';
    elements.fuelCost.textContent = formatCurrency(fuelSummary.totalCost);
    elements.dashboardLiters.textContent = formatLiters(fuelSummary.totalLiters);
    elements.dashboardFuelCount.textContent = String(fuelSummary.count);

    const recentStops = [...stops]
      .sort((a, b) => String(b.datum || '').localeCompare(String(a.datum || '')))
      .slice(0, 3);

    elements.recent.innerHTML = recentStops.length
      ? recentStops
        .map((stop) => `<div class="item"><b>${esc(stop.camperplaats || 'Onbenoemde stop')}</b><div class="muted">${esc(stop.land || '')} · ${esc(stop.datum || '')}</div></div>`)
        .join('')
      : 'Nog geen stops.';
  }

  async function getLatestKnownOdometer() {
    if (!state.activeCamperId) return null;
    const [trips, tanks] = await Promise.all([
      api.getTrips(state.activeCamperId),
      api.getFuelEntries(state.activeCamperId),
    ]);
    return getLatestOdometer(trips, tanks);
  }

  return {
    load,
    getLatestKnownOdometer,
  };
}
