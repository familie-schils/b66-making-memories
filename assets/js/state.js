export const state = {
  activeTripId: null,
  stopNumber: 1,
  selectedPhotos: [],
  activeCamperId: null,
  currentStopSaved: false,
};

export function resetTripState() {
  state.activeTripId = null;
  state.stopNumber = 1;
  state.currentStopSaved = false;
}

export function clearSelectedPhotos() {
  state.selectedPhotos = [];
}
