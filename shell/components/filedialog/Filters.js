.pragma library

// What a filter pattern can look like. Applications send globs through the
// portal, spelled the way X11 spells them, where a case-insensitive suffix
// is written out as a class: "*.[pP][nN][gG]". The shell's own callers
// write the bare suffix instead, "png", because that is all they ever mean.

// Every spelling of "anything at all" that turns up in a filter.
const everything = ["*", "*.*", "*.", ".", ""];

const cache = new Map();

function globToRegExp(glob) {
    let source = "";
    for (let i = 0; i < glob.length; i++) {
        const character = glob[i];
        if (character === "*") {
            source += ".*";
        } else if (character === "?") {
            source += ".";
        } else if (character === "[") {
            // A class is the one piece of glob syntax a regular expression
            // spells the same way, so it travels as it is.
            let end = glob.indexOf("]", glob[i + 1] === "!" || glob[i + 1] === "^" ? i + 3 : i + 2);
            if (end < 0) {
                source += "\\[";
                continue;
            }
            source += `[${glob.slice(i + 1, end).replace(/^!/, "^").replace(/\\/g, "\\\\")}]`;
            i = end;
        } else {
            source += character.replace(/[.+^${}()|\\\]]/g, "\\$&");
        }
    }
    return new RegExp(`^${source}$`, "i");
}

function expressionFor(pattern) {
    let expression = cache.get(pattern);
    if (!expression) {
        // A pattern with nothing of a glob about it is a bare suffix.
        expression = globToRegExp(/[*?[\].]/.test(pattern) ? pattern : `*.${pattern}`);
        cache.set(pattern, expression);
    }
    return expression;
}

// How a pattern reads in the filter's own name. A class spelling one
// letter in both cases is what it stands for, so "*.[pP][nN][gG]" is shown
// as the "*.png" the user has in mind.
function display(pattern) {
    if (everything.includes(pattern))
        return "*";
    const glob = /[*?[\].]/.test(pattern) ? pattern : `*.${pattern}`;
    return glob.replace(/\[(\w)(\w)\]/g, (whole, first, second) =>
        first.toLowerCase() === second.toLowerCase() ? first.toLowerCase() : whole);
}

// Whether a file of this name belongs to a set described by these patterns.
// An empty set, like one described only by MIME types, holds everything:
// hiding a whole folder is the worse answer to a filter nothing can match.
function matches(name, patterns) {
    if (!patterns || patterns.length === 0)
        return true;
    return patterns.some(pattern => everything.includes(pattern) || expressionFor(pattern).test(name));
}
