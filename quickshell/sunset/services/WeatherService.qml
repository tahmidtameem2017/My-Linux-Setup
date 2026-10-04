pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/share/niri-setup"
    readonly property string statePath: root.stateDir + "/weather-location.json"

    property string city: ""
    property string country: ""
    property real latitude: 0
    property real longitude: 0
    property var current: null
    property var daily: null
    property bool loading: false
    property string lastError: ""
    property string pendingCity: ""
    property string pendingCountry: ""

    readonly property string temperature: root.current ? Math.round(root.current.temperature_2m) + "°" : ""

    function condition(code: int): string {
        if (code === 0)
            return "Clear sky";
        if (code === 1)
            return "Mainly clear";
        if (code === 2)
            return "Partly cloudy";
        if (code === 3)
            return "Overcast";
        if (code === 45 || code === 48)
            return "Fog";
        if (code >= 51 && code <= 57)
            return "Drizzle";
        if (code >= 61 && code <= 67)
            return "Rain";
        if (code >= 71 && code <= 77)
            return "Snow";
        if (code >= 80 && code <= 82)
            return "Rain showers";
        if (code >= 85 && code <= 86)
            return "Snow showers";
        if (code >= 95)
            return "Thunderstorm";
        return "Unknown conditions";
    }

    function saveLocation(name, nation) {
        const nextCity = String(name).trim();
        const nextCountry = String(nation).trim();
        if (nextCity === "" || nextCountry === "") {
            lastError = "Enter both a city and country.";
            return;
        }
        if (geoProc.running || weatherProc.running)
            return;
        pendingCity = nextCity;
        pendingCountry = nextCountry;
        lastError = "";
        loading = true;
        geoProc.running = true;
    }

    function refresh() {
        if (root.city === "" || weatherProc.running || geoProc.running)
            return;
        lastError = "";
        loading = true;
        weatherProc.running = true;
    }

    function loadLocation(raw) {
        try {
            const saved = JSON.parse(raw);
            if (!saved.city || !saved.country || saved.latitude === undefined || saved.longitude === undefined)
                return;
            city = String(saved.city);
            country = String(saved.country);
            latitude = Number(saved.latitude);
            longitude = Number(saved.longitude);
            initialized = true;
            refresh();
        } catch (e) {
            lastError = "Saved location could not be read.";
        }
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.stateDir]
        running: true
        onExited: exitCode => {
            if (exitCode === 0)
                locationFile.reload();
            else
                root.lastError = "Could not access weather settings.";
        }
    }

    FileView {
        id: locationFile
        path: root.statePath
        onLoaded: root.loadLocation(text())
        onLoadFailed: root.initialized = true
    }

    Process {
        id: geoProc
        command: ["curl", "-fsS", "--max-time", "15", "-G", "https://geocoding-api.open-meteo.com/v1/search", "--data-urlencode", "name=" + root.pendingCity, "--data-urlencode", "count=10", "--data-urlencode", "language=en", "--data-urlencode", "format=json"]
        running: false
        stdout: StdioCollector { id: geoOut }
        stderr: StdioCollector { id: geoErr }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.loading = false;
                root.lastError = String(geoErr.text).trim() || "Could not find that city and country.";
                return;
            }
            try {
                const results = JSON.parse(String(geoOut.text)).results;
                let place = null;
                if (results) {
                    for (let i = 0; i < results.length; ++i) {
                        if (String(results[i].country).toLowerCase() === root.pendingCountry.toLowerCase()) {
                            place = results[i];
                            break;
                        }
                    }
                }
                if (!place) {
                    root.loading = false;
                    root.lastError = "City and country not found. Check the spelling and try again.";
                    return;
                }
                root.city = String(place.name);
                root.country = String(place.country || root.pendingCountry);
                root.latitude = Number(place.latitude);
                root.longitude = Number(place.longitude);
                locationFile.setText(JSON.stringify({ city: root.city, country: root.country, latitude: root.latitude, longitude: root.longitude }));
                root.refresh();
            } catch (e) {
                root.loading = false;
                root.lastError = "Could not read the location search result.";
            }
        }
    }

    Process {
        id: weatherProc
        command: ["curl", "-fsS", "--max-time", "15", "-G", "https://api.open-meteo.com/v1/forecast", "--data-urlencode", "latitude=" + root.latitude, "--data-urlencode", "longitude=" + root.longitude, "--data-urlencode", "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m", "--data-urlencode", "daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset", "--data-urlencode", "timezone=auto", "--data-urlencode", "forecast_days=1"]
        running: false
        stdout: StdioCollector { id: weatherOut }
        stderr: StdioCollector { id: weatherErr }
        onExited: exitCode => {
            root.loading = false;
            if (exitCode !== 0) {
                root.lastError = String(weatherErr.text).trim() || "Weather could not be loaded. Try again when online.";
                return;
            }
            try {
                const data = JSON.parse(String(weatherOut.text));
                if (!data.current || !data.daily)
                    throw new Error("Missing weather data");
                root.current = data.current;
                root.daily = data.daily;
                root.lastError = "";
            } catch (e) {
                root.lastError = "Could not read the weather response.";
            }
        }
    }
}
