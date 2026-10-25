pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.I18n
import Hyprstack.Portals
import qs.components.filedialog
import qs.utils

Scope {
    id: root

    required property FileChooserPortal portal

    // The dialog walks a path as segments, with the home directory named
    // rather than spelled out.
    function segmentsFor(folder: string): list<string> {
        if (!folder || folder === Paths.home)
            return ["Home"];
        if (folder.startsWith(`${Paths.home}/`))
            return ["Home", ...folder.slice(Paths.home.length + 1).split("/")];
        return folder.split("/");
    }

    // The dialog matches bare suffixes, so "*.png" arrives here as "png". A
    // set described only by MIME types has nothing to match on, so it keeps
    // everything visible rather than hiding the folder's whole contents.
    function groupsFor(filters: var): var {
        return filters.map(filter => {
            const patterns = filter.patterns.map(pattern => pattern.startsWith("*.") ? pattern.slice(2) : pattern);
            return {
                label: filter.label,
                patterns: patterns.length > 0 ? patterns : ["*"]
            };
        });
    }

    Instantiator {
        model: ScriptModel {
            values: [...root.portal.requests]
        }

        FileDialog {
            id: dialog

            required property FileChooserRequest modelData

            mode: {
                if (modelData.directory || modelData.action === FileChooserRequest.SaveMultiple)
                    return FileDialog.SelectFolder;
                return modelData.action === FileChooserRequest.Open ? FileDialog.Open : FileDialog.Save;
            }
            multiple: modelData.multiple
            title: modelData.title || Tr.tr("Select a file")
            acceptLabel: modelData.acceptLabel
            suggestedName: modelData.currentName
            filterGroups: root.groupsFor(modelData.filters)
            currentFilter: Math.max(0, modelData.currentFilter)
            cwd: root.segmentsFor(modelData.currentFolder)

            Component.onCompleted: open()

            onAccepted: paths => {
                // SaveFiles asks only for the folder; the names came with the
                // request and are joined onto it here.
                if (modelData.action === FileChooserRequest.SaveMultiple)
                    modelData.accept(modelData.fileNames.map(name => `${paths[0]}/${name}`), currentFilter);
                else
                    modelData.accept(paths, currentFilter);
            }
            onRejected: modelData.reject()
        }
    }
}
