/*
 * Runs stail (or any shell command) via the Plasma executable data engine and
 * delivers stdout to a per-command callback. The engine runs each source through
 * a shell, so "$HOME/.local/bin/stail active --json" expands and splits correctly.
 * Pattern verified against the executable engine usage shipped on this box.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

P5Support.DataSource {
    id: src
    engine: "executable"
    connectedSources: []

    // command string -> callback({ stdout, stderr, exitCode })
    property var callbacks: ({})

    function exec(cmd, cb) {
        if (callbacks[cmd] !== undefined) {
            return;  // same command still in flight -> skip; the next poll re-reads
        }
        if (cb && typeof cb === "function") {
            callbacks[cmd] = cb;
        }
        connectSource(cmd);
    }

    onNewData: function (source, data) {
        var cb = callbacks[source];
        // One-shot: disconnect so the same command can be re-run on the next poll.
        disconnectSource(source);
        delete callbacks[source];
        if (cb) {
            cb({
                stdout: data["stdout"] || "",
                stderr: data["stderr"] || "",
                exitCode: data["exit code"]
            });
        }
    }
}
