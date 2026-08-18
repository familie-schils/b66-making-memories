import { supabase } from './supabase.js';

async function requireData(promise, context) {
  const { data, error } = await promise;
  if (error) {
    throw new Error(`${context}: ${error.message}`);
  }
  return data;
}

export function createApi() {
  return {
    async getSession() {
      const { data, error } = await supabase.auth.getSession();
      if (error) throw new Error(`Sessie laden mislukt: ${error.message}`);
      return data.session;
    },

    onAuthStateChange(callback) {
      return supabase.auth.onAuthStateChange(callback);
    },

    signIn(credentials) {
      return supabase.auth.signInWithPassword(credentials);
    },

    signOut() {
      return supabase.auth.signOut();
    },

    async getActiveCamperId() {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError) throw new Error(`Gebruiker laden mislukt: ${authError.message}`);
      const user = authData.user;
      if (!user) return null;

      const { data, error } = await supabase
        .from('camper_users')
        .select('camper_id')
        .eq('user_id', user.id)
        .maybeSingle();

      if (error) throw new Error(`Camper ophalen mislukt: ${error.message}`);
      return data?.camper_id ?? null;
    },

    getCrew(camperId) {
      if (!camperId) return Promise.resolve([]);
      return requireData(
        supabase.from('camper_crew').select('*').eq('camper_id', camperId).order('naam'),
        'Bemanning laden mislukt',
      );
    },

    getTrips(camperId) {
      if (!camperId) return Promise.resolve([]);
      return requireData(
        supabase.from('reizen').select('*').eq('camper_id', camperId).order('datum', { ascending: false }),
        'Reizen laden mislukt',
      );
    },

    createTrip(payload) {
      return requireData(
        supabase.from('reizen').insert(payload).select().single(),
        'Reis starten mislukt',
      );
    },

    updateTrip(id, payload) {
      return requireData(
        supabase.from('reizen').update(payload).eq('id', id).select().single(),
        'Reis bijwerken mislukt',
      );
    },

    getTrip(id, camperId) {
      return requireData(
        supabase.from('reizen').select('*').eq('id', id).eq('camper_id', camperId).single(),
        'Reis laden mislukt',
      );
    },

    getStopsByTripIds(tripIds) {
      if (!tripIds.length) return Promise.resolve([]);
      return requireData(
        supabase.from('reis_stops').select('*').in('reis_id', tripIds).order('volgorde'),
        'Stops laden mislukt',
      );
    },

    getStopsByTripId(tripId) {
      return requireData(
        supabase.from('reis_stops').select('*').eq('reis_id', tripId).order('volgorde'),
        'Stops laden mislukt',
      );
    },

    createStop(payload) {
      return requireData(
        supabase.from('reis_stops').insert(payload).select().single(),
        'Stop opslaan mislukt',
      );
    },

    getPhotosByStopIds(stopIds) {
      if (!stopIds.length) return Promise.resolve([]);
      return requireData(
        supabase.from('fotos').select('*').in('stop_id', stopIds),
        'Foto\'s laden mislukt',
      );
    },

    savePhotoLink(payload) {
      return requireData(
        supabase.from('fotos').insert(payload).select().single(),
        'Foto koppelen mislukt',
      );
    },

    async uploadPhoto(filename, file) {
      const { error } = await supabase.storage.from('fotos').upload(filename, file);
      if (error) {
        throw new Error(`Upload mislukt: ${error.message}`);
      }

      const { data } = supabase.storage.from('fotos').getPublicUrl(filename);
      return data.publicUrl;
    },

    getFuelEntries(camperId) {
      if (!camperId) return Promise.resolve([]);
      return requireData(
        supabase.from('tankbeurten').select('*').eq('camper_id', camperId).order('kmstand', { ascending: true }),
        'Tankbeurten laden mislukt',
      );
    },

    async getPreviousTank(camperId, km) {
      if (!camperId) return null;
      const { data, error } = await supabase
        .from('tankbeurten')
        .select('kmstand,liters,datum')
        .eq('camper_id', camperId)
        .lt('kmstand', km)
        .order('kmstand', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (error) throw new Error(`Vorige tankbeurt laden mislukt: ${error.message}`);
      return data || null;
    },

    createFuelEntry(payload) {
      return requireData(
        supabase.from('tankbeurten').insert(payload).select().single(),
        'Tankbeurt opslaan mislukt',
      );
    },

    getMaintenance(camperId) {
      if (!camperId) return Promise.resolve([]);
      return requireData(
        supabase.from('onderhoud').select('*').eq('camper_id', camperId).order('datum', { ascending: false }),
        'Onderhoud laden mislukt',
      );
    },

    createMaintenance(payload) {
      return requireData(
        supabase.from('onderhoud').insert(payload).select().single(),
        'Onderhoud opslaan mislukt',
      );
    },
  };
}
