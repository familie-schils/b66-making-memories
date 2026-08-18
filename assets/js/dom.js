const elementIds = [
  'versionText','loginView','appView','appStatus','loginError','email','password','loginBtn','logoutBtn',
  'tripChooser','tripList','tripForm','tripTitle','tripStatus','tripStartFields','stopHeading','tCrew','tStartDate',
  'tStartKm','tEndKm','tEndKmEndBox','tEndDate','kmResult','activeTripInfo','saveStopBtn','nextStopBtn','endTripBtn',
  'cancelTripBtn','endBox','finishTripBtn','hideEndTripBtn','tripDetail','startTripBtn','sDate','sType','sPlace','sCountry',
  'sPrice','sRating','sFacilities','sNotes','photoUpload','photoStatus','photoList','photoTestUploadBtn',
  'fuelStatus','fDate','fKm','fuelKmHint','fLiters','fPrice','fLocation','fCountry','fuelCalc','addFuelBtn','fuelList',
  'fuelTotalLiters','fuelTotalCost','fuelCount','odometer','totalKm','avgConsumption','fuelCost','tripCount','stopCount',
  'dashboardLiters','dashboardFuelCount','recent','mCategory','mDate','mKm','mCost','mPerformer','maintenanceOptions',
  'otherMaintenanceBox','otherMaintenanceText','mNotes','saveMaintenanceBtn','maintenanceHistory','maintenanceStatus'
];

export function createElements() {
  return Object.fromEntries(elementIds.map((id) => [id, document.getElementById(id)]));
}

export function today() {
  return new Date().toISOString().slice(0, 10);
}

export function value(element) {
  return element.value.trim();
}

export function show(element) {
  element.classList.remove('hidden');
}

export function hide(element) {
  element.classList.add('hidden');
}

export function esc(input) {
  return String(input ?? '').replace(/[&<>"']/g, (match) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;',
  }[match]));
}

export function sanitizeDigits(input) {
  return String(input ?? '').replace(/\D/g, '');
}

export function formatKm(valueToFormat) {
  return Number(valueToFormat).toLocaleString('nl-BE');
}

export function formatCurrency(valueToFormat) {
  return `€ ${Number(valueToFormat || 0).toFixed(2).replace('.', ',')}`;
}

export function formatLiters(valueToFormat) {
  return `${Number(valueToFormat || 0).toFixed(2).replace('.', ',')} l`;
}

export function setStatus(element, text = '', variant = 'ok') {
  if (!text) {
    element.textContent = '';
    element.className = 'status hidden';
    return;
  }

  element.textContent = text;
  element.className = `status ${variant}`;
}

export function setPhotoMessage(element, text) {
  element.textContent = text;
}
