export function collectKnownKilometers(trips = [], tanks = []) {
  const kilometers = [];

  for (const trip of trips) {
    if (trip.start_km != null) kilometers.push(Number(trip.start_km));
    if (trip.eind_km != null) kilometers.push(Number(trip.eind_km));
  }

  for (const tank of tanks) {
    if (tank.kmstand != null) kilometers.push(Number(tank.kmstand));
  }

  return kilometers;
}

export function getLatestOdometer(trips = [], tanks = []) {
  const kilometers = collectKnownKilometers(trips, tanks);
  return kilometers.length ? Math.max(...kilometers) : null;
}

export function getFirstOdometer(trips = [], tanks = []) {
  const kilometers = collectKnownKilometers(trips, tanks);
  return kilometers.length ? Math.min(...kilometers) : null;
}

export function summarizeFuel(tanks = []) {
  const sortedTanks = [...tanks].sort((a, b) => Number(a.kmstand) - Number(b.kmstand));
  let intervalLiters = 0;
  let intervalKm = 0;
  let totalLiters = 0;
  let totalCost = 0;

  sortedTanks.forEach((tank, index) => {
    const liters = Number(tank.liters || 0);
    const price = Number(tank.prijs_per_liter || 0);
    const cost = tank.totaalbedrag != null ? Number(tank.totaalbedrag) : liters * price;

    totalLiters += liters;
    totalCost += cost;

    if (index > 0) {
      intervalKm += Number(tank.kmstand) - Number(sortedTanks[index - 1].kmstand);
      intervalLiters += liters;
    }
  });

  return {
    totalLiters,
    totalCost,
    count: sortedTanks.length,
    averageConsumption: intervalKm > 0 ? (intervalLiters / intervalKm) * 100 : null,
  };
}
