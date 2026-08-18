import { APP_VERSION } from './config.js';
import { createApi } from './api.js';
import { createElements, setStatus } from './dom.js';
import { state } from './state.js';
import { createAuthFeature } from './features/auth.js';
import { createDashboardFeature } from './features/dashboard.js';
import { createFuelFeature } from './features/fuel.js';
import { createMaintenanceFeature } from './features/maintenance.js';
import { createPhotoFeature } from './features/photos.js';
import { createTripFeature } from './features/trips.js';

const api = createApi();
const elements = createElements();
elements.versionText.textContent = `Build: ${APP_VERSION}`;

const photos = createPhotoFeature({ api, elements, state });
const dashboard = createDashboardFeature({ api, elements, state });
const fuel = createFuelFeature({
  api,
  elements,
  state,
  getLatestKnownOdometer: () => dashboard.getLatestKnownOdometer(),
  onChanged: () => dashboard.load(),
});
const maintenance = createMaintenanceFeature({ api, elements, state });
const trips = createTripFeature({
  api,
  elements,
  state,
  getLatestKnownOdometer: () => dashboard.getLatestKnownOdometer(),
  photos,
  onChanged: async () => {
    await Promise.all([dashboard.load(), fuel.prepareForm()]);
  },
});

async function loadAppData() {
  setStatus(elements.appStatus);

  try {
    state.activeCamperId = await api.getActiveCamperId();

    if (!state.activeCamperId) {
      setStatus(elements.appStatus, 'Er is nog geen camper gekoppeld aan dit account. Voeg eerst een camperkoppeling toe in Supabase.', 'warn');
    }

    await Promise.all([
      trips.loadCrewOptions(),
      trips.loadTrips(),
      maintenance.load(),
      dashboard.load(),
      fuel.load(),
    ]);

    await fuel.prepareForm();
  } catch (error) {
    setStatus(elements.appStatus, error.message, 'err');
  }
}

function setupNavigation() {
  document.querySelectorAll('nav button[data-tab]').forEach((button) => {
    button.addEventListener('click', async () => {
      document.querySelectorAll('nav button[data-tab]').forEach((navButton) => navButton.classList.remove('active'));
      button.classList.add('active');
      document.querySelectorAll('section').forEach((section) => section.classList.remove('active'));
      document.getElementById(button.dataset.tab).classList.add('active');

      if (button.dataset.tab === 'fuel') {
        try {
          await fuel.prepareForm();
          await fuel.load();
        } catch (error) {
          setStatus(elements.fuelStatus, error.message, 'err');
        }
      }
    });
  });
}

const auth = createAuthFeature({ api, elements, loadAppData });

auth.setup();
photos.setup();
fuel.setup();
maintenance.setup();
trips.setup();
setupNavigation();

auth.init().catch((error) => setStatus(elements.loginError, error.message, 'err'));
