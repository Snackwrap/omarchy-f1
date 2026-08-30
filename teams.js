.pragma library
// Approximate 2026 constructor colors, keyed by Ergast/Jolpica constructorId.
// Used for the small team-color chips in standings/grid (toggle in settings).
var COLORS = {
  "mercedes": "#27F4D2",
  "ferrari": "#E8002D",
  "mclaren": "#FF8000",
  "red_bull": "#3671C6",
  "rb": "#6692FF",
  "alpine": "#00A1E8",
  "haas": "#B6BABD",
  "audi": "#BB0A30",
  "williams": "#64C4FF",
  "aston_martin": "#229971",
  "cadillac": "#C4A24A",
  // historical / fallbacks
  "sauber": "#52E252",
  "alphatauri": "#5E8FAA",
  "alfa": "#C92D4B",
  "renault": "#FFF500"
}

function colorFor(constructorId, fallback) {
  if (constructorId && COLORS[constructorId]) return COLORS[constructorId]
  return fallback
}
