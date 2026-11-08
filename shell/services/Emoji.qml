pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.I18n
import qs.utils

Singleton {
    id: root

    readonly property string storeFile: `${Paths.state}/emoji.json`

    // Groups shipped with the shell, preceded by the two the user fills in
    // themselves once they have anything in them.
    readonly property var groups: {
        const own = [];
        if (root.pins.length > 0)
            own.push({ id: "pinned", name: Tr.tr("Pinned"), icon: "keep" });
        if (root.custom.length > 0)
            own.push({ id: "custom", name: Tr.tr("Mine"), icon: "edit" });
        return [...own, ...root.catalogue];
    }

    property var catalogue: []
    property var entries: []
    // Characters, not whole entries: the catalogue is reloaded on start and
    // a pin has to survive that.
    property var pins: []
    property var custom: []
    property string group: "smileys"

    function entryFor(character: string): var {
        return root.entries.find(entry => entry.c === character)
            ?? root.custom.find(entry => entry.c === character)
            ?? { c: character, n: "", g: "custom", k: "" };
    }

    // An empty query browses the selected group; anything typed searches
    // every group at once, which is what a picker is usually opened for.
    function query(text: string): var {
        const needle = text.trim().toLowerCase();
        if (!needle)
            return groupEntries(root.group);

        const pool = [...root.custom, ...root.entries];
        const starts = [];
        const contains = [];
        for (const entry of pool) {
            const haystack = `${entry.n} ${entry.k}`;
            if (entry.c === needle || haystack.startsWith(needle))
                starts.push(entry);
            else if (haystack.includes(needle))
                contains.push(entry);
        }
        return [...starts, ...contains];
    }

    function groupEntries(id: string): var {
        if (id === "pinned")
            return root.pins.map(character => root.entryFor(character));
        if (id === "custom")
            return root.custom;
        return root.entries.filter(entry => entry.g === id);
    }

    function activate(entry: var): void {
        Quickshell.execDetached(["wl-copy", "--", entry.c]);
    }

    function pinned(entry: var): bool {
        return root.pins.includes(entry.c);
    }

    function togglePin(entry: var): void {
        root.pins = root.pinned(entry) ? root.pins.filter(c => c !== entry.c) : [entry.c, ...root.pins];
        save();
    }

    // Whatever was typed becomes a character of its own, so a face the
    // catalogue has no idea about can still live in the picker.
    function addCustom(text: string): void {
        const character = text.trim();
        if (!character || root.custom.some(entry => entry.c === character))
            return;
        root.custom = [{ c: character, n: character, g: "custom", k: "" }, ...root.custom];
        root.group = "custom";
        save();
    }

    function removeCustom(entry: var): void {
        root.custom = root.custom.filter(item => item.c !== entry.c);
        root.pins = root.pins.filter(c => c !== entry.c);
        save();
    }

    function save(): void {
        store.setText(JSON.stringify({ pins: root.pins, custom: root.custom }, null, 2));
    }

    FileView {
        id: catalogueFile

        path: Quickshell.shellPath("assets/emoji.json")
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.catalogue = data.groups ?? [];
                root.entries = data.entries ?? [];
            } catch (error) {
                console.warn(`Unable to load the character catalogue: ${error}`);
            }
        }
    }

    FileView {
        id: store

        path: root.storeFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.pins = Array.isArray(data.pins) ? data.pins : [];
                root.custom = Array.isArray(data.custom) ? data.custom : [];
            } catch (error) {
                console.warn(`Unable to load saved characters: ${error}`);
                root.pins = [];
                root.custom = [];
            }
        }
    }
}
