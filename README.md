
# BCN Surf Forecast

Static page showing the hourly wave forecast (SIWANA model, Puertos del
Estado) for **Boya de Barcelona II** (code `712018020`): significant wave
height, peak and mean period, and the direction waves come from as a 16-point
compass label and degrees (0° = north, clockwise). The API's propagation
direction is rotated by 180° for display; wind direction already indicates
where the wind comes from and is left unchanged.

A GitHub Actions workflow runs every hour, fetches the data from
`https://poem.puertos.es/portus/ForecastData/Siwana/forecast`, renders
`_site/index.html`, and deploys it to GitHub Pages. Open pages also reload
themselves every 15 minutes.

Wind gusts (knots, 10 m) and direction for **Playa del Bogatell** come from the
free [Open-Meteo](https://open-meteo.com/) forecast API (no key needed;
override the point with `WIND_LAT` / `WIND_LON`). If the request fails the
column shows "–".

## Requirements

Ruby ≥ 3.0, standard library only (no gems).

Note: GitHub may delay scheduled runs during busy periods. It also disables
scheduled workflows in public repositories with no activity for 60 days.
If that happens, re-enable the workflow from the Actions tab.

## Spin it up locally

# 1. Build the page
ruby bin/build

# 2. Serve _site/ on port 8000
python3 -m http.server 8000 --directory _site