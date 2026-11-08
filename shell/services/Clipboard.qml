pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import qs.utils

Singleton {
    id: root

    // cliphist keeps a bounded history and drops the oldest entries, so a
    // pinned one is copied into the shell's own storage instead of merely
    // being remembered by id.
    readonly property string pinFile: `${Paths.state}/clipboard.json`
    readonly property string pinDir: `${Paths.state}/clipboard`
    readonly property string thumbDir: `${Paths.imagecache}/clipboard`

    // Pinned entries first, then the history with the pinned ones removed:
    // cliphist usually still holds what was pinned from it.
    readonly property var entries: {
        const pinned = root.pins.map(pin => ({
            pinned: true,
            isImage: pin.kind === "image",
            label: pin.kind === "image" ? pin.info : pin.text,
            info: pin.kind === "image" ? pin.info : "",
            id: "",
            line: "",
            file: pin.kind === "image" ? pin.file : "",
            text: pin.text ?? "",
            preview: pin.preview ?? ""
        }));
        const seen = root.pins.map(pin => pin.preview);
        return [...pinned, ...root.history.filter(entry => !seen.includes(entry.preview))];
    }

    property var pins: []
    property var history: []
    // Decoded image previews, keyed by cliphist id.
    property var thumbnails: ({})
    property var pendingThumbnails: []

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    // cliphist previews an image as "[[ binary data 78 B png 10x10 ]]".
    function parseLine(line: string): var {
        const tab = line.indexOf("\t");
        if (tab < 0)
            return null;

        const id = line.slice(0, tab);
        const preview = line.slice(tab + 1);
        const binary = preview.match(/^\[\[ binary data (.+) \]\]$/);
        if (!binary) {
            return {
                pinned: false, isImage: false, label: preview, info: "",
                id, line, file: "", text: "", preview
            };
        }

        // The words are size, unit, format and dimensions.
        const parts = binary[1].split(" ");
        const format = parts.length > 2 ? parts[parts.length - 2] : "";
        const size = parts.slice(0, parts.length - 2).join(" ");
        const info = `${format} ${parts[parts.length - 1]} · ${size}`.trim();
        return {
            pinned: false, isImage: true, label: info, info,
            id, line, file: "", text: "", format, preview
        };
    }

    function activate(entry: var): void {
        if (entry.pinned) {
            if (entry.isImage)
                Quickshell.execDetached(["sh", "-c", 'wl-copy < "$1"', "sh", entry.file]);
            else
                copyTextProc.exec({ command: ["wl-copy", entry.text], environment: {} });
            return;
        }
        Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy', "sh", entry.id]);
    }

    // cliphist only deletes an entry given its whole line on stdin; an id on
    // the command line is quietly ignored.
    function remove(entry: var): void {
        if (entry.pinned)
            unpin(entry);
        if (!entry.line)
            return;
        deleteProc.payload = entry.line;
        deleteProc.stdinEnabled = true;
        deleteProc.running = true;
    }

    function clear(): void {
        wipeProc.running = true;
    }

    function togglePin(entry: var): void {
        if (entry.pinned)
            unpin(entry);
        else
            pin(entry);
    }

    function pin(entry: var): void {
        if (entry.isImage) {
            // The decoded preview is already on disk, so keep a copy of it
            // rather than asking cliphist for the bytes a second time. The
            // copy goes through a shell so the directory is made on the way.
            const source = root.thumbnails[entry.id];
            if (!source)
                return;
            pinImageProc.entry = entry;
            pinImageProc.target = `${root.pinDir}/${Date.now()}-${entry.id}.${entry.format || "png"}`;
            pinImageProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")" && cp -- "$1" "$2"',
                "sh", source, pinImageProc.target];
            pinImageProc.running = true;
            return;
        }

        // The listed preview is truncated, so the full text has to be read
        // back before it can be kept.
        pinTextProc.entry = entry;
        pinTextProc.command = ["cliphist", "decode", entry.id];
        pinTextProc.running = true;
    }

    function unpin(entry: var): void {
        const index = root.pins.findIndex(p => p.preview === entry.preview);
        if (index < 0)
            return;
        const pinned = root.pins[index];
        if (pinned.kind === "image" && pinned.file)
            CUtils.deleteFile(Paths.fileUrl(pinned.file));
        root.pins = root.pins.filter((_, i) => i !== index);
        savePins();
    }

    function savePins(): void {
        pinStore.setText(JSON.stringify({ pins: root.pins }, null, 2));
    }

    // Images are decoded one at a time, on demand, so opening the list does
    // not spawn a process for every picture ever copied.
    function requestThumbnail(entry: var): void {
        if (!entry.isImage || entry.pinned || root.thumbnails[entry.id]
            || root.pendingThumbnails.includes(entry.id))
            return;
        root.pendingThumbnails = [...root.pendingThumbnails, entry.id];
        nextThumbnail();
    }

    function nextThumbnail(): void {
        if (thumbProc.running || root.pendingThumbnails.length === 0)
            return;
        const id = root.pendingThumbnails[0];
        const entry = root.history.find(e => e.id === id);
        thumbProc.requested = id;
        thumbProc.target = `${root.thumbDir}/${id}.${entry?.format || "png"}`;
        thumbProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")" && cliphist decode "$1" > "$2"',
            "sh", id, thumbProc.target];
        thumbProc.running = true;
    }

    onPinsChanged: Qt.callLater(() => {
        // A pin kept only in storage still needs a picture to show.
        for (const pin of root.pins)
            if (pin.kind === "image" && pin.file)
                root.thumbnails = Object.assign({}, root.thumbnails, { [pin.file]: pin.file });
    })

    FileView {
        id: pinStore

        path: root.pinFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.pins = Array.isArray(data.pins) ? data.pins : [];
            } catch (error) {
                console.warn(`Unable to load pinned clipboard entries: ${error}`);
                root.pins = [];
            }
        }
    }

    Process {
        id: listProc

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = [];
                for (const line of text.split("\n")) {
                    const entry = root.parseLine(line);
                    if (entry)
                        parsed.push(entry);
                }
                root.history = parsed;
            }
        }
    }

    Process {
        id: deleteProc

        property string payload

        command: ["cliphist", "delete"]
        onStarted: {
            write(`${payload}\n`);
            stdinEnabled = false;
        }
        onExited: root.refresh()
    }

    Process {
        id: wipeProc

        command: ["cliphist", "wipe"]
        onExited: root.refresh()
    }

    Process {
        id: copyTextProc
    }

    Process {
        id: pinTextProc

        property var entry

        stdout: StdioCollector {
            onStreamFinished: {
                root.pins = [{ kind: "text", preview: pinTextProc.entry.preview, text: text,
                    at: Date.now() }, ...root.pins];
                root.savePins();
            }
        }
    }

    Process {
        id: pinImageProc

        property var entry
        property string target

        onExited: code => { // qmllint disable signal-handler-parameters
            if (code !== 0) {
                console.warn(`Unable to keep a copy of the pinned image at ${target}`);
                return;
            }
            root.pins = [{ kind: "image", preview: pinImageProc.entry.preview, file: pinImageProc.target,
                info: pinImageProc.entry.info, at: Date.now() }, ...root.pins];
            root.savePins();
        }
    }

    Process {
        id: thumbProc

        property string requested
        property string target

        onExited: code => { // qmllint disable signal-handler-parameters
            if (code === 0)
                root.thumbnails = Object.assign({}, root.thumbnails, { [requested]: target });
            root.pendingThumbnails = root.pendingThumbnails.filter(id => id !== requested);
            Qt.callLater(root.nextThumbnail);
        }
    }
}
