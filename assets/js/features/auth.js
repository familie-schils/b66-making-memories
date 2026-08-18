import { hide, setStatus, show, value } from '../dom.js';

export function createAuthFeature({ api, elements, loadAppData }) {
  function showLogin() {
    show(elements.loginView);
    hide(elements.appView);
  }

  function showAppShell() {
    hide(elements.loginView);
    show(elements.appView);
  }

  async function login() {
    setStatus(elements.loginError);
    const { error } = await api.signIn({
      email: value(elements.email),
      password: elements.password.value,
    });

    if (error) {
      setStatus(elements.loginError, error.message, 'err');
    }
  }

  async function logout() {
    const { error } = await api.signOut();
    if (error) {
      setStatus(elements.loginError, error.message, 'err');
    }
  }

  async function init() {
    const session = await api.getSession();
    if (session) {
      showAppShell();
      await loadAppData();
    } else {
      showLogin();
    }

    api.onAuthStateChange(async (_event, nextSession) => {
      if (nextSession) {
        showAppShell();
        await loadAppData();
      } else {
        showLogin();
      }
    });
  }

  function setup() {
    elements.loginBtn.addEventListener('click', () => login().catch((error) => setStatus(elements.loginError, error.message, 'err')));
    elements.logoutBtn.addEventListener('click', () => logout().catch((error) => setStatus(elements.loginError, error.message, 'err')));
  }

  return {
    init,
    setup,
    showLogin,
  };
}
