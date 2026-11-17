.pragma library

function flag(profile) {
    const code = String(profile.country ?? "").toUpperCase();
    if (/^[A-Z]{2}$/.test(code) && code !== "XX" && code !== "ZZ")
        return String.fromCodePoint(...Array.from(code, letter => 0x1f1e6 + letter.charCodeAt(0) - 65));
    return String(profile.name ?? "").match(/\uD83C[\uDDE6-\uDDFF]\uD83C[\uDDE6-\uDDFF]/)?.[0] ?? "🌐";
}

function label(profile) {
    return String(profile.name ?? "").replace(/\uD83C[\uDDE6-\uDDFF]\uD83C[\uDDE6-\uDDFF]/, "").trim();
}
